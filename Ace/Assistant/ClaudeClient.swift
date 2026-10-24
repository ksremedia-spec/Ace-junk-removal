import Foundation
#if os(iOS)
import UIKit
#endif

/// Talks to the Anthropic Messages API. With a key in this device's Keychain
/// it goes straight to api.anthropic.com. Without one, it goes through the
/// business's sync server (`/v1/claude`, sync code required), which holds
/// the key, so nobody types it on a phone (Oct 24). The beta used Kyle's
/// relay instead (Beta.relayURL).
enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        }
    }
}

enum ClaudeEffort: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }
}

enum ClaudeError: LocalizedError {
    case missingKey
    case badStatus(Int, String)
    case refused(String)
    case cutOff
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No API key. Add it in Settings › API key."
        // Plain words Alex can act on, with the code at the end so Kyle can
        // still tell what happened (Oct 20 phone audit).
        case .badStatus(let code, _) where code == 401 || code == 403:
            return "The Assistant key on this device isn't working. Check it in Settings › API key. (\(code))"
        case .badStatus(let code, _) where code == 429 || code >= 500:
            return "The Assistant is busy. Tap Send again in a minute. (\(code))"
        case .badStatus(let code, let message):
            return "The Assistant could not take this note. (\(code)) \(message)"
        case .refused:
            return "This note could not be handled. Try saying it another way."
        case .cutOff:
            return "The answer was cut off before it finished. Send again."
        case .unreadable:
            return "The answer could not be read. Send again."
        }
    }
}

struct ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    /// Sends the spoken note and the records, and gets back the plan: a
    /// reply, the actions to confirm and the questions to ask, as
    /// structured JSON in the shape of docs/assistant-actions.md.
    /// `directory` is the full customer list (AssistantRecords); it goes
    /// first, in its own block marked for caching, so a second note within a
    /// few minutes does not pay for 600 customers again.
    static func plan(note: String, directory: String, records: String, model: ClaudeModel, effort: ClaudeEffort) async throws -> (plan: AssistantPlan, seconds: Double, inputTokens: Int, outputTokens: Int) {
        let route = try await currentRoute()

        let userText = "Spoken note:\n\(note)\n\nRecords:\n\(records)"
        var userContent: [[String: Any]] = []
        if !directory.isEmpty {
            userContent.append([
                "type": "text",
                "text": directory,
                "cache_control": ["type": "ephemeral"],
            ])
        }
        userContent.append(["type": "text", "text": userText])

        let body: [String: Any] = [
            "model": model.rawValue,
            // Thinking tokens count toward this cap; leave plenty of room.
            "max_tokens": 16000,
            "system": AssistantPlan.systemPrompt(),
            // Asked for explicitly: in Oct 2026 tests Sonnet 5.5 sometimes
            // skipped thinking and returned every field empty.
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": effort.rawValue,
                "format": [
                    "type": "json_schema",
                    "schema": AssistantPlan.jsonSchema,
                ],
            ],
            "messages": [
                [
                    "role": "user",
                    "content": userContent,
                ],
            ],
        ]

        let (text, json, seconds) = try await send(body, route: route, timeout: 90)

        #if DEBUG
        // Debug builds only: the last note and Claude's raw answer, in the
        // app's own temporary folder, to see what came back when a screen
        // looks wrong. Never in a build given to Ashley or Alex.
        let debugFile = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-last.txt")
        try? ("NOTE:\n" + note + "\n\nANSWER:\n" + text).write(to: debugFile, atomically: true, encoding: .utf8)
        #endif

        var plan: AssistantPlan
        do {
            plan = try JSONDecoder().decode(AssistantPlan.self, from: Data(text.utf8))
        } catch {
            throw ClaudeError.unreadable(error.localizedDescription)
        }
        plan.numberActions()

        let usage = json["usage"] as? [String: Any] ?? [:]
        return (
            plan: plan,
            seconds: seconds,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0
        )
    }

    /// One spoken answer to a follow-up question ("No house number. What's
    /// the number?"), turned into the field's value in the form's format.
    /// Empty when the answer does not give it. Haiku at low effort: the
    /// task is small and the person is waiting with the phone in hand.
    static func fill(_ field: String, question: String, answer: String, form: String) async throws -> String {
        let route = try await currentRoute()
        let body: [String: Any] = [
            "model": ClaudeModel.haiku.rawValue,
            "max_tokens": 2000,
            "system": FollowUpPrompt.system(),
            "output_config": [
                "effort": ClaudeEffort.low.rawValue,
                "format": [
                    "type": "json_schema",
                    "schema": FollowUpPrompt.jsonSchema,
                ],
            ],
            "messages": [
                [
                    "role": "user",
                    "content": "Field: \(field)\nQuestion asked: \(question)\nSpoken answer: \(answer)\n\nThe form so far:\n\(form)",
                ],
            ],
        ]
        let (text, _, _) = try await send(body, route: route, timeout: 30)
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        return (json?["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where a request goes and how it proves it may: the device's own key
    /// first, then the beta relay, then the sync server.
    private enum Route {
        case direct(key: String)
        case relay(URL)
        case server(URL, code: String)
    }

    @MainActor
    private static func currentRoute() throws -> Route {
        if let key = Keychain.read(Keychain.anthropicAPIKey), !key.isEmpty { return .direct(key: key) }
        if let relay = Beta.relayURL { return .relay(relay) }
        if let config = SyncEngine.shared.config { return .server(config.url, code: config.code) }
        throw ClaudeError.missingKey
    }

    /// Posts one Messages request and returns the reply's text, the whole
    /// response and how long it took. Throws on an error status, a refusal
    /// or a cut-off answer.
    private static func send(_ body: [String: Any], route: Route, timeout: TimeInterval) async throws -> (text: String, json: [String: Any], seconds: Double) {
        var request: URLRequest
        switch route {
        case .direct(let key):
            request = URLRequest(url: endpoint)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .relay(let url):
            request = URLRequest(url: url.appendingPathComponent("v1/messages"))
        case .server(let url, let code):
            request = URLRequest(url: url.appending(path: "v1/claude"))
            request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        #if DEBUG
        if let sent = request.httpBody {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            try? sent.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("assistant-request-\(stamp).json"))
        }
        #endif

        #if os(iOS)
        // Locking the phone while the Assistant works would otherwise cut
        // the request off and show No signal (ship audit Oct 24, #19): iOS
        // gives a request started in the foreground about 30 seconds more.
        let background = await BackgroundTime(name: "Assistant")
        defer { Task { @MainActor in background.end() } }
        #endif

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let seconds = Date().timeIntervalSince(started)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        #if DEBUG
        // Debug builds only: the whole reply (how it ended, token counts,
        // thinking), to see why an answer came back short (Oct 20, Sonnet).
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("assistant-response-\(stamp).json"))
        #endif

        guard (200..<300).contains(status) else {
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.badStatus(status, message)
        }

        let stopReason = json["stop_reason"] as? String ?? ""
        if stopReason == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw ClaudeError.refused(details?["explanation"] as? String ?? "")
        }
        if stopReason == "max_tokens" {
            throw ClaudeError.cutOff
        }

        // Read blocks by type, never by position: the first block may be thinking.
        let content = json["content"] as? [[String: Any]] ?? []
        guard let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw ClaudeError.unreadable("No text in the reply.")
        }
        return (text, json, seconds)
    }
}

#if os(iOS)
/// A little time to finish after the app leaves the screen.
@MainActor
final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
