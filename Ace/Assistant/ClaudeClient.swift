import Foundation

/// Talks to the Anthropic Messages API directly from the device. The API key
/// comes from the Keychain and is sent only to api.anthropic.com.
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
        case .badStatus(let code, let message):
            return "The Anthropic service answered with error \(code). \(message)"
        case .refused(let reason):
            return "Claude declined this request. \(reason)"
        case .cutOff:
            return "The answer was cut off before it finished."
        case .unreadable(let detail):
            return "The answer could not be read. \(detail)"
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
        guard let apiKey = Keychain.read(Keychain.anthropicAPIKey), !apiKey.isEmpty else {
            throw ClaudeError.missingKey
        }

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

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        #if DEBUG
        if let sent = request.httpBody {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            try? sent.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("assistant-request-\(stamp).json"))
        }
        #endif

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let seconds = Date().timeIntervalSince(started)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

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
}
