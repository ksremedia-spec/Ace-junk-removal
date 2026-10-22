import Foundation
import Observation
import SwiftData

/// Keeps this device in step with Ace's sync server (docs/device-sync.md):
/// sends what changed here, brings back what changed elsewhere. Runs when
/// Ace opens, when it comes to the front, a few seconds after a save, and
/// every 30 seconds while open. Does nothing until a server address and
/// sync code are set.
@MainActor @Observable
final class SyncEngine {
    static let shared = SyncEngine()

    static let urlKey = "sync.url"
    static let codeAccount = "sync-code"

    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    /// Plain words for the last problem, or nil when the last sync worked.
    private(set) var problem: String?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var state = SyncState.load()
    @ObservationIgnored private var soon: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?

    private init() {}

    // MARK: Settings

    struct Config {
        let url: URL
        let code: String
    }

    /// The server and code: from Settings, or in Debug builds from
    /// `-sync.url` and `-sync.key` (a local test server on Kyle's Mac).
    var config: Config? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let u = args.firstIndex(of: "-sync.url"), u + 1 < args.count,
           let k = args.firstIndex(of: "-sync.key"), k + 1 < args.count,
           let url = URL(string: args[u + 1]) {
            return Config(url: url, code: args[k + 1])
        }
        #endif
        guard let text = UserDefaults.standard.string(forKey: Self.urlKey),
              let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme != nil,
              let code = Keychain.read(Self.codeAccount), !code.isEmpty else { return nil }
        return Config(url: url, code: code)
    }

    var isSetUp: Bool { config != nil }

    // MARK: When to sync

    func start(_ context: ModelContext) {
        self.context = context
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncing else { return }
                self.syncSoon(after: 3)
            }
        }
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// A sync shortly, gathering several saves into one.
    func syncSoon(after seconds: Double = 0.5) {
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Starts over as if this device had never synced: next time it brings
    /// everything down again and sends what it has as new. Used when this
    /// device's data is cleared or replaced on purpose.
    func forget() {
        let device = state.device
        state = SyncState()
        state.device = device
        state.save()
    }

    // MARK: One sync

    func syncNow() async {
        guard let context, let config, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await run(context, config)
            lastSynced = Date()
            problem = nil
        } catch let error as SyncError {
            problem = error.text
        } catch {
            problem = "Could not reach the sync server."
        }
    }

    private func run(_ context: ModelContext, _ config: Config) async throws {
        let read = SyncSnapshot.read(context)
        var snapshot = read.0
        if read.1 { try? context.save() }

        // What changed here since the last sync.
        var outgoing: [Outgoing] = []
        var seen = Set<String>()
        let now = Date()
        for type in SyncType.allCases {
            for id in snapshot.ids(of: type) {
                let key = SyncState.key(type, id)
                seen.insert(key)
                guard let (data, stamped) = snapshot.encoded(type, id) else { continue }
                let print = SyncCoding.fingerprint(data)
                let known = state.known[key]
                guard known?.fingerprint != print else { continue }
                var time = stamped ?? .distantPast
                // Fields changed without a new "last changed" time: stamp it now.
                if let known, Self.milliseconds(time) <= known.updatedAt {
                    time = now
                    snapshot.stamp(type, id, now)
                }
                outgoing.append(Outgoing(type: type, id: id, updatedAt: time, deleted: false, data: data, fingerprint: print))
            }
        }
        // Records synced before and gone now were deleted here.
        for key in state.known.keys where !seen.contains(key) {
            guard let (type, id) = SyncState.split(key) else { continue }
            outgoing.append(Outgoing(type: type, id: id, updatedAt: now, deleted: true, data: Data("{}".utf8), fingerprint: ""))
        }

        // Send in groups of 40 (the server's limit), then keep asking until
        // everything newer has come back.
        var incoming: [String: Incoming] = [:]
        var since = state.since
        var index = 0
        repeat {
            let group = Array(outgoing[index..<min(index + 40, outgoing.count)])
            let reply = try await send(group, since: since, config)
            for sent in group {
                let key = SyncState.key(sent.type, sent.id)
                if sent.deleted {
                    state.known[key] = nil
                } else {
                    state.known[key] = .init(fingerprint: sent.fingerprint, updatedAt: Self.milliseconds(sent.updatedAt))
                }
            }
            for change in reply.changes {
                incoming[SyncState.key(change.type, change.id)] = change
            }
            since = reply.latest
            index += group.count
            state.since = since
            state.save()
            if index >= outgoing.count && !reply.more { break }
        } while true

        // Apply what came back, in an order that keeps links whole.
        var applied = false
        for type in SyncType.allCases {
            for change in incoming.values where change.type == type && !change.deleted {
                let key = SyncState.key(type, change.id)
                // This device's own change coming back, or nothing new.
                if state.known[key]?.updatedAt == change.updatedAtMilliseconds,
                   snapshot.encoded(type, change.id) != nil { continue }
                if let local = snapshot.encoded(type, change.id), let time = local.updatedAt,
                   Self.milliseconds(time) > change.updatedAtMilliseconds { continue }
                try snapshot.apply(type, change.id, change.data, updatedAt: change.updatedAt, in: context)
                if let (data, _) = snapshot.encoded(type, change.id) {
                    state.known[key] = .init(fingerprint: SyncCoding.fingerprint(data), updatedAt: change.updatedAtMilliseconds)
                }
                applied = true
            }
        }
        for type in SyncType.allCases.reversed() {
            for change in incoming.values where change.type == type && change.deleted {
                let key = SyncState.key(type, change.id)
                if let local = snapshot.encoded(type, change.id), let time = local.updatedAt,
                   Self.milliseconds(time) > change.updatedAtMilliseconds { continue }
                if snapshot.encoded(type, change.id) != nil {
                    snapshot.delete(type, change.id, in: context)
                    applied = true
                }
                state.known[key] = nil
            }
        }
        if applied || !outgoing.isEmpty { try? context.save() }
        state.save()
    }

    // MARK: Talking to the server

    /// Whole milliseconds since 1970: the time as sent, stored and compared.
    nonisolated static func milliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private struct Outgoing {
        let type: SyncType
        let id: UUID
        let updatedAt: Date
        let deleted: Bool
        let data: Data
        let fingerprint: String
    }

    private struct Incoming {
        let type: SyncType
        let id: UUID
        let updatedAtMilliseconds: Double
        let deleted: Bool
        let data: Data
        var updatedAt: Date { Date(timeIntervalSince1970: updatedAtMilliseconds / 1000) }
    }

    private struct Reply {
        var changes: [Incoming]
        var latest: Int
        var more: Bool
    }

    private func send(_ group: [Outgoing], since: Int, _ config: Config) async throws -> Reply {
        let changes: [[String: Any]] = try group.map {
            [
                "type": $0.type.rawValue,
                "id": $0.id.uuidString,
                "updatedAt": Self.milliseconds($0.updatedAt),
                "deleted": $0.deleted,
                "data": try JSONSerialization.jsonObject(with: $0.data),
            ]
        }
        let body: [String: Any] = ["device": state.device, "since": since, "changes": changes]
        var request = URLRequest(url: config.url.appending(path: "v1/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.code)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SyncError(text: "The sync code is wrong.") }
        guard status == 200, let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError(text: "The sync server answered with an error (\(status)).")
        }
        let rows = reply["changes"] as? [[String: Any]] ?? []
        var incoming: [Incoming] = []
        for row in rows {
            guard let typeText = row["type"] as? String, let type = SyncType(rawValue: typeText),
                  let idText = row["id"] as? String, let id = UUID(uuidString: idText),
                  let time = row["updatedAt"] as? Double,
                  let fields = row["data"] else { continue }
            incoming.append(Incoming(type: type, id: id, updatedAtMilliseconds: time,
                                     deleted: row["deleted"] as? Bool ?? false,
                                     data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])))
        }
        return Reply(changes: incoming, latest: reply["latest"] as? Int ?? since, more: reply["more"] as? Bool ?? false)
    }
}

struct SyncError: Error {
    let text: String
}

/// The sync's own bookkeeping, in a small file next to the database: the
/// last running number seen, and for each synced record a fingerprint of
/// its fields and its time as last sent or received.
struct SyncState: Codable {
    struct Known: Codable {
        var fingerprint: String
        var updatedAt: Double
    }

    var device = UUID().uuidString
    var since = 0
    var known: [String: Known] = [:]

    static func key(_ type: SyncType, _ id: UUID) -> String { "\(type.rawValue)/\(id.uuidString)" }

    static func split(_ key: String) -> (SyncType, UUID)? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let type = SyncType(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        return (type, id)
    }

    private static var file: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "ace-sync-state.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
