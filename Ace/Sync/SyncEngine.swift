import Foundation
import Observation
import SwiftData
#if os(iOS)
import UIKit
#endif

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
    /// Something was saved here and has not reached the server yet.
    private(set) var hasUnsent = false
    /// Sync Now was pressed: show the turning arrows even for a quick sync.
    private(set) var isManual = false
    /// The last try failed only because there was no connection: a calm,
    /// grey state, not a problem (audit Oct 21, design idea 4).
    private(set) var isOffline = false
    /// The Google Sheet link as the server last reported it, checked every
    /// couple of minutes, so a stopped link shows on the icon (audit M12).
    private(set) var sheetStatus: SheetStatus?
    @ObservationIgnored private var sheetCheckedAt: Date?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var state = SyncState.load()
    @ObservationIgnored private var soon: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// True while the sync saves its own changes, so they do not count as
    /// new edits.
    @ObservationIgnored private var savingOwn = false
    /// Something was saved while a sync was running: sync again after it.
    @ObservationIgnored private var again = false
    /// Goes up whenever the sync memory is cleared, so a sync already
    /// running drops what it fetched (audit fix-now 6).
    @ObservationIgnored private var generation = 0
    /// Changes this copy of Ace could not read, for the status line.
    private(set) var unreadableCount = 0
    /// The sync running now, so others can wait for it to finish.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// The server answered with the ID this device knows, since Ace opened.
    @ObservationIgnored private var serverChecked = false

    private init() {
        heldRecords = state.held.count
    }

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
        if let text = UserDefaults.standard.string(forKey: Self.urlKey),
           let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme != nil,
           let code = Keychain.read(Self.codeAccount), !code.isEmpty {
            return Config(url: url, code: code)
        }
        return Self.builtIn
    }

    /// The business's server, built into its copy of Ace so nobody types
    /// it (Kyle, Oct 21): `SyncServer.txt` next to the app's code, two
    /// lines, the address then the sync code. The file is kept out of the
    /// public repository (.gitignore); without it, sync waits for Settings.
    static let builtIn: Config? = {
        #if !DEBUG
        // A beta copy must never reach the business's server: a tester's
        // typing would go into the real books (audit Oct 21, M1).
        if Beta.isBeta { return nil }
        #endif
        guard let file = Bundle.main.url(forResource: "SyncServer", withExtension: "txt"),
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, let url = URL(string: lines[0]), url.scheme != nil, !lines[1].isEmpty else { return nil }
        return Config(url: url, code: lines[1])
    }()

    var isSetUp: Bool { config != nil }

    /// Syncing with a real server, not a test server on this Mac. Example
    /// data and the debug tools are off then: they would reach every device
    /// and Ashley's sheet (audit Oct 21, M2).
    var isLive: Bool {
        guard let host = config?.url.host()?.lowercased() else { return false }
        return !(host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local"))
    }

    /// Set up, but this device has never finished a sync, so it does not
    /// have the other devices' records yet.
    var isWaitingForFirstSync: Bool { isSetUp && lastSynced == nil && state.since == 0 }

    // MARK: When to sync

    func start(_ context: ModelContext) {
        self.context = context
        // No queue: runs at once on the main thread that saved, so the sync's
        // own saves can be told apart from edits.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.savingOwn else { return }
                self.noteLocalChange()
            }
        }
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                await self?.checkSheetIfDue()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Something was saved here: send it shortly.
    private func noteLocalChange() {
        hasUnsent = true
        if running != nil {
            again = true
        } else {
            // Short on iPhone: Alex saves and pockets the phone (audit M7).
            #if os(iOS)
            syncSoon(after: 1)
            #else
            syncSoon(after: 3)
            #endif
        }
    }

    /// The overweight rate or the salary days changed in Settings: send them
    /// shortly. A change made now is meant for this server, even if the old
    /// value was held back after a move to another server.
    func settingsChanged() {
        state.held.remove(SyncState.key(.setting, SyncIDs.settings))
        heldRecords = state.held.count
        noteLocalChange()
    }

    /// Going to the background: finish sending what was just saved. iOS
    /// gives an app a short while to do so when asked (audit Oct 21, M7).
    func syncBeforeBackground() {
        #if os(iOS)
        guard isSetUp else { return }
        endBackgroundTime()
        let task = UIApplication.shared.beginBackgroundTask(withName: "Ace sync") {
            MainActor.assumeIsolated { SyncEngine.shared.endBackgroundTime() }
        }
        backgroundTime = task
        Task { [weak self] in
            guard let self else { return }
            // A sync already under way may be the one carrying the change
            // just saved: wait for it, then send anything still unsent
            // (audit Oct 24, finding 13).
            let wasRunning = self.running != nil
            await self.finishRunning()
            if !wasRunning || self.hasUnsent { await self.syncNow() }
            if backgroundTime == task { self.endBackgroundTime() }
        }
        #endif
    }

    #if os(iOS)
    /// Hands the background time back to iOS, once.
    private func endBackgroundTime() {
        guard backgroundTime != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTime)
        backgroundTime = .invalid
    }
    #endif

    private func checkSheetIfDue() async {
        guard isSetUp else { return }
        if let at = sheetCheckedAt, Date().timeIntervalSince(at) < 120 { return }
        sheetCheckedAt = Date()
        if let status = await sheet("status") { sheetStatus = status }
    }

    /// A plain line when the sheet link has stopped, or nil.
    var sheetProblem: String? {
        guard let s = sheetStatus, s.connected else { return nil }
        if let paused = s.paused, !paused.isEmpty { return "The Google Sheet paused: " + paused }
        if let error = s.lastError, !error.isEmpty { return "The Google Sheet stopped syncing. Open Settings, Google Sheet." }
        if let last = s.lastChecked, Date().timeIntervalSince(last) > 600 {
            return "The Google Sheet hasn't been checked for over 10 minutes."
        }
        return nil
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
        // A sync running now must not apply what it fetched for the old memory.
        generation += 1
        heldDeletions = 0
        heldRecords = 0
        serverChecked = false
    }

    /// More deletions than this in one sync are held back until confirmed in
    /// Settings: a replaced or broken database must not empty every device
    /// (audit fix-now 35).
    static let maxDeletionsWithoutAsking = 20
    /// Deletions held back on this device; Settings offers to send them.
    private(set) var heldDeletions = 0
    @ObservationIgnored private var allowBulkDeletions = false

    func sendHeldDeletions() async {
        // A sync already running would make this one return at once, and
        // nothing would be sent (audit Oct 24, finding 51).
        await finishRunning()
        allowBulkDeletions = true
        await syncNow(manual: true)
        allowBulkDeletions = false
    }

    /// Records that were on this device before it was moved to this server
    /// (it had synced with another one: a test server, or this one before it
    /// was wiped). They are not sent until Settings › Sync says so, so old
    /// test data cannot reach a fresh server (audit Oct 24, findings 5, 11).
    private(set) var heldRecords = 0

    /// Sends the held records to the server after all.
    func sendHeldRecords() async {
        await finishRunning()
        state.held = []
        state.save()
        heldRecords = 0
        await syncNow(manual: true)
    }

    /// Removes the held records from this device only, then brings
    /// everything down from the server again, so a record it has that was
    /// held here is not missed.
    func removeHeldRecords() async {
        guard let context else { return }
        await finishRunning()
        var snapshot = SyncSnapshot.read(context).0
        for key in state.held where state.known[key] == nil {
            guard let (type, id) = SyncState.split(key) else { continue }
            snapshot.delete(type, id, in: context)
        }
        saveOwn(context)
        state.held = []
        state.since = 0
        state.save()
        heldRecords = 0
        await syncNow(manual: true)
    }

    // MARK: One sync

    /// One sync, unless one is already running (then it returns at once).
    func syncNow(manual: Bool = false) async {
        guard context != nil, config != nil, running == nil else { return }
        // The task clears `running` itself, so anyone waiting on it sees it
        // gone as soon as it finishes.
        let task = Task {
            await self.syncOnce(manual: manual)
            self.running = nil
        }
        running = task
        await task.value
    }

    /// Waits until no sync is running.
    private func finishRunning() async {
        while let task = running { await task.value }
    }

    private func syncOnce(manual: Bool) async {
        guard let context, let config else { return }
        isSyncing = true
        isManual = manual
        again = false
        defer {
            isSyncing = false
            isManual = false
            if again { syncSoon(after: 1) }
        }
        do {
            try await run(context, config)
            lastSynced = Date()
            problem = nil
            isOffline = false
            // Anything saved during this sync is sent by the next one.
            if !again { hasUnsent = false }
        } catch let error as SyncError {
            problem = error.text
            isOffline = false
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            // No signal, or iOS cut the request when the phone locked: not a
            // problem, the changes are kept and go next time.
            isOffline = true
            problem = nil
        } catch {
            problem = "Could not reach the sync server."
            isOffline = false
        }
    }

    // MARK: What the sync icon shows

    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff, .cancelled,
    ]

    enum Status: Equatable {
        /// No server address or sync code on this device.
        case off
        case sending
        case upToDate(Date)
        /// Saved here; sends in a moment.
        case waiting
        /// No connection; changes are kept and sent later.
        case offline
        case problem(String)
    }

    var status: Status {
        guard isSetUp else { return .off }
        if isSyncing && (hasUnsent || isManual) { return .sending }
        if let problem { return .problem(problem) }
        if isOffline { return .offline }
        if heldDeletions > 0 { return .problem("\(heldDeletions) deletions were held back. Open Settings › Sync.") }
        if heldRecords > 0 { return .problem(heldRecordsText + " Open Settings › Sync.") }
        if unreadableCount > 0 { return .problem("\(Plural.text(unreadableCount, "change")) from another device couldn't be read. Update Ace on this device.") }
        if let sheetProblem { return .problem(sheetProblem) }
        if hasUnsent { return .waiting }
        if let lastSynced { return .upToDate(lastSynced) }
        return .waiting
    }

    /// "412 records on this device are not on the sync server."
    var heldRecordsText: String {
        heldRecords == 1
            ? "1 record on this device is not on the sync server."
            : "\(heldRecords) records on this device are not on the sync server."
    }

    private func run(_ context: ModelContext, _ config: Config) async throws {
        // Talking to a different server than last time: start afresh. The
        // old server's ID is kept, so a device that had synced elsewhere
        // holds its records back instead of sending them (finding 5).
        if state.url != config.url.absoluteString {
            let server = state.server
            forget()
            state.url = config.url.absoluteString
            state.server = server
            state.save()
        }
        let runGeneration = generation
        let serverBefore = state.server
        let heldBefore = state.held
        let read = SyncSnapshot.read(context)
        var snapshot = read.0
        if read.1 { saveOwn(context) }

        // The database was replaced (or emptied) but the sync memory
        // survived: start afresh instead of deleting everything everywhere.
        // The shared settings are not in the database, so they don't count.
        // This also fires when a device really deleted its last records:
        // rare, and those records then come back (docs/device-sync.md).
        let total = SyncType.allCases.reduce(0) { $0 + ($1 == .setting ? 0 : snapshot.ids(of: $1).count) }
        if total == 0 && state.known.keys.contains(where: { SyncState.split($0)?.0 != .setting }) {
            let url = state.url
            forget()
            state.url = url
            state.save()
            return
        }

        // What changed here since the last sync.
        var outgoing: [Outgoing] = []
        var seen = Set<String>()
        let now = Date()
        for type in SyncType.allCases {
            for id in snapshot.ids(of: type) {
                let key = SyncState.key(type, id)
                seen.insert(key)
                let known = state.known[key]
                // Held back after a move to another server, until Settings says.
                if known == nil && state.held.contains(key) { continue }
                guard let (data, stamped) = snapshot.encoded(type, id) else { continue }
                let print = SyncCoding.fingerprint(data)
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
        var deletions: [Outgoing] = []
        for key in state.known.keys where !seen.contains(key) {
            guard let (type, id) = SyncState.split(key) else { continue }
            deletions.append(Outgoing(type: type, id: id, updatedAt: now, deleted: true, data: Data("{}".utf8), fingerprint: ""))
        }
        // Crew hours and dumpster history go with their person or dumpster,
        // so they don't count: deleting one person with a month of hours is
        // an ordinary delete (audit Oct 24, finding 51).
        let counted = deletions.filter { $0.type != .labor && $0.type != .rental }.count
        if counted > Self.maxDeletionsWithoutAsking && !allowBulkDeletions {
            heldDeletions = deletions.count
        } else {
            heldDeletions = 0
            outgoing += deletions
        }

        // Send in groups of 40 (the server's limit), then keep asking until
        // everything newer has come back.
        var incoming: [String: Incoming] = [:]
        var since = state.since
        var index = 0
        // The first request after Ace opens carries no changes when this
        // device knows its server, so a wiped or replaced server is noticed
        // before any of this device's records reach it (finding 5).
        var probe = !serverChecked && state.server != nil
        repeat {
            let group = probe ? [] : Array(outgoing[index..<min(index + 40, outgoing.count)])
            probe = false
            let reply = try await send(group, since: since, config)
            guard generation == runGeneration else { return }
            // A different server answered (it was replaced or wiped): start
            // afresh on the next sync instead of mixing the two. What is on
            // this device came from the old server, so it is held back until
            // Settings › Sync says to send or remove it (finding 5).
            if let server = reply.server, let old = state.server, server != old {
                let url = state.url
                forget()
                state.url = url
                state.server = server
                state.held = seen
                state.save()
                heldRecords = state.held.count
                return
            }
            // The same server, reset: start afresh, sending everything.
            if reply.reset {
                let url = state.url
                forget()
                state.url = url
                state.server = reply.server
                state.save()
                return
            }
            if state.server == nil { state.server = reply.server }
            serverChecked = true
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
            // What was sent is remembered now; the running number only once
            // everything received is saved below. Saved earlier, a sync cut
            // short (the phone locked mid-download, Oct 21) would leave the
            // device sure it had records it never stored.
            if !group.isEmpty { state.save() }
            if index >= outgoing.count && !reply.more { break }
        } while true

        // Changes that could not be read last time get another try.
        for old in state.unreadable {
            guard let type = SyncType(rawValue: old.type), let id = UUID(uuidString: old.id) else { continue }
            let key = SyncState.key(type, id)
            if incoming[key] == nil {
                incoming[key] = Incoming(type: type, id: id, updatedAtMilliseconds: old.updatedAt, deleted: old.deleted, data: old.data)
            }
        }
        // Changes applied with a link to a record that wasn't here get
        // another try, in case it has arrived since (audit Oct 24, finding 53).
        for old in state.unlinked {
            guard let type = SyncType(rawValue: old.type), let id = UUID(uuidString: old.id) else { continue }
            let key = SyncState.key(type, id)
            if incoming[key] == nil {
                incoming[key] = Incoming(type: type, id: id, updatedAtMilliseconds: old.updatedAt, deleted: false, data: old.data, retry: true)
            }
        }
        var unreadable: [SyncState.Unreadable] = []
        var unlinked: [SyncState.Unreadable] = []

        // Re-read: records may have been deleted on this device while the
        // request was out (fix-now 6). Skipped when there is nothing to
        // apply or tidy (finding 50).
        if !incoming.isEmpty || !state.held.isEmpty {
            snapshot = SyncSnapshot.read(context).0
        }

        /// The local copy has an edit not sent yet, and it is the newer one.
        func localWins(_ type: SyncType, _ change: Incoming) -> Bool {
            let key = SyncState.key(type, change.id)
            // Held back from another server: this server's copy wins.
            if state.known[key] == nil && state.held.contains(key) { return false }
            guard let local = snapshot.encoded(type, change.id) else { return false }
            // Unchanged since the last sync: the incoming change is newer
            // news, whatever the local stamp says (fix-now 2).
            guard SyncCoding.fingerprint(local.data) != state.known[key]?.fingerprint else { return false }
            guard let time = local.updatedAt else { return false }
            return Self.milliseconds(time) > change.updatedAtMilliseconds
        }

        // Apply what came back, in an order that keeps links whole.
        var applied = false
        for type in SyncType.allCases {
            for change in incoming.values where change.type == type && !change.deleted {
                let key = SyncState.key(type, change.id)
                if change.retry {
                    // Again only if nothing changed here since it was applied.
                    guard let known = state.known[key], known.updatedAt == change.updatedAtMilliseconds,
                          let local = snapshot.encoded(type, change.id),
                          SyncCoding.fingerprint(local.data) == known.fingerprint else { continue }
                } else if state.known[key]?.updatedAt == change.updatedAtMilliseconds,
                          snapshot.encoded(type, change.id) != nil {
                    // This device's own change coming back, or nothing new.
                    continue
                }
                if localWins(type, change) { continue }
                let linked: Bool
                do {
                    linked = try snapshot.apply(type, change.id, change.data, updatedAt: change.updatedAt, in: context)
                } catch {
                    // One change this copy can't read must not stop the rest.
                    unreadable.append(.init(type: type.rawValue, id: change.id.uuidString, updatedAt: change.updatedAtMilliseconds, deleted: false, data: change.data))
                    continue
                }
                if !linked {
                    unlinked.append(.init(type: type.rawValue, id: change.id.uuidString, updatedAt: change.updatedAtMilliseconds, deleted: false, data: change.data))
                }
                if let (data, _) = snapshot.encoded(type, change.id) {
                    state.known[key] = .init(fingerprint: SyncCoding.fingerprint(data), updatedAt: change.updatedAtMilliseconds)
                }
                if linked || !change.retry { applied = true }
            }
        }
        for type in SyncType.allCases.reversed() {
            for change in incoming.values where change.type == type && change.deleted {
                let key = SyncState.key(type, change.id)
                if localWins(type, change) { continue }
                if snapshot.encoded(type, change.id) != nil {
                    snapshot.delete(type, change.id, in: context)
                    applied = true
                }
                state.known[key] = nil
            }
        }
        guard generation == runGeneration else { return }
        if applied || !outgoing.isEmpty { saveOwn(context) }
        // A held record stops being held once this server has sent its own
        // copy, or once it is deleted here.
        if !state.held.isEmpty {
            state.held = state.held.filter { key in
                guard state.known[key] == nil, let (type, id) = SyncState.split(key) else { return false }
                return snapshot.has(type, id)
            }
        }
        heldRecords = state.held.count
        state.unreadable = unreadable
        state.unlinked = unlinked
        unreadableCount = unreadable.count
        // Written only when something moved, not every 30 seconds while
        // idle (finding 50).
        let moved = since != state.since || !incoming.isEmpty || !outgoing.isEmpty
            || serverBefore != state.server || heldBefore != state.held
        state.since = since
        if moved { state.save() }
    }

    private func saveOwn(_ context: ModelContext) {
        savingOwn = true
        try? context.save()
        savingOwn = false
    }

    // MARK: The Google Sheet link (docs/google-sheet-sync.md)

    struct SheetStatus: Decodable, Equatable {
        var connected: Bool
        /// The server has Google's sign-in set up.
        var configured: Bool
        var sheetName: String?
        var lastRun: Double?
        /// When the sheet was connected, so Connect Again can tell the new
        /// link from the old one.
        var connectedAt: Double?
        var paused: String?
        var lastError: String?
        var error: String?
        var url: String?

        var lastChecked: Date? {
            guard let lastRun, lastRun > 0 else { return nil }
            return Date(timeIntervalSince1970: lastRun / 1000)
        }
    }

    /// Asks the server about the sheet link, or (for start, resume,
    /// disconnect, run) to act on it.
    func sheet(_ action: String) async -> SheetStatus? {
        guard let config else { return nil }
        var request = URLRequest(url: config.url.appending(path: "v1/google/\(action)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(config.code)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // "start" answers with only a sign-in address (or an error).
        if action == "start" {
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return SheetStatus(connected: false, configured: true, error: reply?["error"] as? String, url: reply?["url"] as? String)
        }
        return try? JSONDecoder().decode(SheetStatus.self, from: data)
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
        /// Applied before with a link missing; tried again (finding 53).
        var retry = false
        var updatedAt: Date { Date(timeIntervalSince1970: updatedAtMilliseconds / 1000) }
    }

    private struct Reply {
        var changes: [Incoming]
        var latest: Int
        var more: Bool
        var server: String?
        var reset: Bool
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
        return Reply(changes: incoming, latest: reply["latest"] as? Int ?? since, more: reply["more"] as? Bool ?? false,
                     server: reply["server"] as? String, reset: reply["reset"] as? Bool ?? false)
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
    /// Which server this memory belongs to (address, and the server's own
    /// ID), so moving to another server starts afresh instead of missing
    /// records (audit Oct 21, fix-now 1).
    var url: String?
    var server: String?
    /// Changes from the server this copy of Ace could not read; kept and
    /// tried again on every sync (fix-now 4).
    var unreadable: [Unreadable] = []
    /// Changes applied with a link to a record not on this device; tried
    /// again on every sync until the link is found (finding 53).
    var unlinked: [Unreadable] = []
    /// Records on this device not sent since it moved to another server,
    /// until Settings › Sync says to send or remove them (finding 5).
    var held: Set<String> = []

    struct Unreadable: Codable {
        var type: String
        var id: String
        var updatedAt: Double
        var deleted: Bool
        var data: Data
    }

    enum CodingKeys: String, CodingKey { case device, since, known, url, server, unreadable, unlinked, held }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? UUID().uuidString
        since = try c.decodeIfPresent(Int.self, forKey: .since) ?? 0
        known = try c.decodeIfPresent([String: Known].self, forKey: .known) ?? [:]
        url = try c.decodeIfPresent(String.self, forKey: .url)
        server = try c.decodeIfPresent(String.self, forKey: .server)
        unreadable = try c.decodeIfPresent([Unreadable].self, forKey: .unreadable) ?? []
        unlinked = try c.decodeIfPresent([Unreadable].self, forKey: .unlinked) ?? []
        held = try c.decodeIfPresent(Set<String>.self, forKey: .held) ?? []
    }

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

#if os(iOS)
/// The extra time iOS gave the sync when Ace last went to the background.
@MainActor private var backgroundTime = UIBackgroundTaskIdentifier.invalid
#endif
