import AVFoundation
import SwiftUI

// What a new job or quote from the Assistant is still missing, and the two
// ways to fill it in (Kyle, Oct 20): click the item and type it, or answer
// the question on screen ("No house number. What's the number?") by holding
// the talk button. The app never talks back out loud (Kyle: "I don't want
// it to talk back, maybe it asks questions back on screen").

// MARK: - The gaps

/// Something the form still needs, in the order it is asked about.
enum Gap: String, CaseIterable, Identifiable {
    case name, address, houseNumber, phone, date, price

    var id: String { rawValue }

    /// The button on the Missing row.
    var label: String {
        switch self {
        case .name: return "Name"
        case .address: return "Address"
        case .houseNumber: return "House number"
        case .phone: return "Phone"
        case .date: return "Date"
        case .price: return "Price"
        }
    }

    /// The label inside a sentence: "Listening for the house number."
    var inSentence: String {
        switch self {
        case .phone: return "phone number"
        default: return label.lowercased()
        }
    }

    var symbol: String {
        switch self {
        case .name: return "person"
        case .address: return "mappin.and.ellipse"
        case .houseNumber: return "number"
        case .phone: return "phone"
        case .date: return "calendar"
        case .price: return "dollarsign"
        }
    }

    /// The question on screen.
    var question: String {
        switch self {
        case .name: return "No name. What's the customer's name?"
        case .address: return "No address. What's the address?"
        case .houseNumber: return "No house number. What's the house number?"
        case .phone: return "No phone number. What's the phone number?"
        case .date: return "No date. What day?"
        case .price: return "No price. How much?"
        }
    }

    /// The field name in the follow-up prompt.
    var field: String {
        switch self {
        case .name: return "customerName"
        default: return rawValue
        }
    }

    /// The gap behind one of the save questions' field names, for "Fix it".
    init?(field: String) {
        switch AssistantFlags.key(field) {
        case "customername": self = .name
        case "address": self = .address
        case "phone": self = .phone
        case "date": self = .date
        case "price": self = .price
        default: return nil
        }
    }
}

// MARK: - Reading an answer

enum GapAnswer {
    enum Kind {
        /// "Stop", "that's it": treated as a skip on screen.
        case stop
        /// "Skip", "no phone", "I don't know", or nothing heard.
        case skip
        case answer
    }

    private static let stopPhrases: Set<String> = [
        "stop", "stop asking", "thats it", "thats all", "never mind", "nevermind", "cancel", "done",
    ]

    private static let skipPhrases: Set<String> = [
        "skip", "skip it", "skip that", "next", "no", "nope", "none", "nothing", "pass",
        "i dont know", "dont know", "dunno", "not sure", "no idea", "unknown",
        "leave it", "leave it blank", "later", "not yet", "not sure yet",
    ]

    /// "That's it." → "thats it"
    private static func plain(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func kind(_ text: String) -> Kind {
        let words = plain(text)
        if words.isEmpty { return .skip }
        if stopPhrases.contains(words) { return .stop }
        if skipPhrases.contains(words) { return .skip }
        // "No phone", "no number yet", "don't have one".
        let short = words.split(separator: " ").count <= 4 && !words.contains(where: \.isNumber)
        if short, words.hasPrefix("no ") || words.contains("dont have") || words.contains("didnt say") {
            return .skip
        }
        return .answer
    }

    /// The value read straight from the answer when it is plainly a number,
    /// without asking Claude. Nil when Claude should read it.
    static func local(_ gap: Gap, _ text: String) -> String? {
        switch gap {
        case .houseNumber:
            guard plain(text).split(separator: " ").count <= 4,
                  let match = text.firstMatch(of: /[0-9]+[A-Za-z]?\b/) else { return nil }
            return String(match.output).uppercased()
        case .phone:
            var digits = text.filter(\.isNumber)
            if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
            return digits.count == 10 || digits.count == 7 ? digits : nil
        case .price:
            guard let amount = Parse.money(text) else { return nil }
            return Parse.moneyText(amount)
        case .name, .address, .date:
            return nil
        }
    }
}

// MARK: - The prompt for one answer

/// The instructions for turning one spoken answer into a field's value.
/// Kept word for word in docs/assistant-actions.md, "Follow-up questions".
enum FollowUpPrompt {
    static func system(now: Date = Date()) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US")
        dayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let today = dayFormatter.string(from: now)
        let zone = TimeZone.current.identifier

        return """
        You fill in one missing detail on a booking form for Ace Junk Removal, a junk removal, demolition and dumpster rental company in Massachusetts. The app asked a question on screen and speech recognition wrote down the spoken answer, so words and numbers may be misheard.

        Today is \(today) (\(zone)).

        Return the value for the field named, in its format:
        - customerName: the name as it should be written, e.g. "Maria Pereira" or "First Parish Church".
        - address: house number, street and town, e.g. "42 Elm St, Taunton". Keep the town already on the form when the answer leaves it out.
        - houseNumber: the house number only, with a letter if one was said, e.g. "42" or "42B".
        - phone: the digits only, e.g. "5085550147".
        - date: YYYY-MM-DD, worked out from today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week".
        - price: dollars as digits: "three hundred" is 300.

        Return an empty value when the answer does not give it, for example "skip", "I don't know", "no phone" or something unrelated. Never invent a value.
        """
    }

    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "value": [
                "type": "string",
                "description": "The field's value in its format, or empty.",
            ],
        ],
        "required": ["value"],
        "additionalProperties": false,
    ]
}

// MARK: - Answering by voice

/// One spoken answer at a time: listening while the talk button is held,
/// then reading what was said into the field's value.
@MainActor
@Observable
final class FollowUpListener {
    enum Phase: Equatable {
        case idle
        case listening(Gap)
        case working(Gap)
    }

    private(set) var phase: Phase = .idle
    /// A line about the last answer: "Heard “42”." or "Nothing heard."
    private(set) var note = ""

    var current: Gap? {
        switch phase {
        case .idle: return nil
        case .listening(let gap), .working(let gap): return gap
        }
    }

    /// Waiting for the microphone question; cleared by `cancel`.
    private var starting = false

    func begin(_ gap: Gap, engine: SpeechEngine) async {
        guard phase == .idle, !starting else { return }
        starting = true
        // Asked the first time. A refusal is said plainly, not as "Nothing
        // heard." after a silent recording (audit Oct 24).
        let allowed = await AVAudioApplication.requestRecordPermission()
        // The form closed while the question was up.
        guard starting else { return }
        starting = false
        guard allowed else {
            note = Self.microphoneOffText
            return
        }
        do {
            try engine.startListening()
            note = ""
            phase = .listening(gap)
        } catch {
            note = error.localizedDescription
        }
    }

    enum Outcome {
        case value(String)
        /// "Skip", "no phone", "I don't know".
        case skip
        /// Nothing heard, or nothing usable in it; the question stays.
        case none
    }

    /// The talk button was let go: what was said, read into the field's value.
    func end(engine: SpeechEngine, form: String) async -> Outcome {
        guard case .listening(let gap) = phase else { return .none }
        phase = .working(gap)
        defer { phase = .idle }
        let answer = (try? await engine.stopListening().text) ?? ""
        guard !answer.isEmpty else {
            note = "Nothing heard. Hold the button while you talk."
            return .none
        }
        note = "Heard “\(answer)”."
        if GapAnswer.kind(answer) != .answer { return .skip }
        if let value = GapAnswer.local(gap, answer) { return .value(value) }
        do {
            let value = try await ClaudeClient.fill(gap.field, question: gap.question, answer: answer, form: form)
            if value.isEmpty { note = "Heard “\(answer)”, but no \(gap.inSentence) in it." }
            return value.isEmpty ? .none : .value(value)
        } catch {
            note = "Heard “\(answer)”. \(error.localizedDescription)"
            return .none
        }
    }

    private static var microphoneOffText: String {
        #if os(macOS)
        return "Microphone access is off. Type the answer, or turn it on in System Settings › Privacy & Security › Microphone."
        #else
        return "Microphone access is off. Type the answer, or turn it on in Settings › Privacy & Security › Microphone."
        #endif
    }

    /// Stops listening without reading anything, when the form closes.
    func cancel(engine: SpeechEngine?) {
        starting = false
        guard case .listening = phase else { return }
        phase = .idle
        Task { await engine?.cancelListening() }
    }
}

// MARK: - The Missing section

/// The top of the filled-in form while something is missing. The first
/// item is asked as a question, answered by holding the talk button or by
/// typing in its field; Skip moves on. Under it, every missing item is a
/// button that puts the cursor in its field.
struct MissingSection: View {
    let gaps: [Gap]
    /// The voice model; the talk button shows once it is ready.
    let engine: SpeechEngine?
    /// The form as it stands, for reading a spoken answer in context.
    var formSummary: () -> String
    /// Puts the cursor in the gap's field.
    var onPick: (Gap) -> Void
    /// A spoken answer, into its field.
    var onFill: (Gap, String) -> Void
    /// Gaps passed over with Skip. Held by the form, so Save does not ask
    /// about them again (Oct 20 phone audit).
    @Binding var skipped: Set<Gap>

    @State private var listener = FollowUpListener()
    @State private var answered = 0

    /// The question on screen: the first gap not skipped.
    private var question: Gap? {
        if let current = listener.current { return current }
        return gaps.first { !skipped.contains($0) }
    }

    private var canTalk: Bool { engine?.state == .ready }

    var body: some View {
        if !gaps.isEmpty {
            Section {
                if let question {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text(question.question)
                            .font(.headline)
                        if listener.phase == .listening(question), let engine {
                            LiveWords(engine: engine, placeholder: "Listening.")
                        } else if listener.phase == .working(question) {
                            HStack(spacing: Space.s) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Filling in the \(question.inSentence).")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: Space.s) {
                            if canTalk, let engine {
                                HoldToTalkButton(
                                    idleTitle: "Hold to answer",
                                    isListening: listener.phase == .listening(question),
                                    onStart: { Task { @MainActor in await listener.begin(question, engine: engine) } },
                                    onEnd: { finish(question, engine: engine) }
                                )
                                .disabled(listener.phase == .working(question))
                            }
                            Button("Type it") { onPick(question) }
                                .buttonStyle(.action(Tint.warning))
                            Button("Not now") { skipped.insert(question) }
                                .buttonStyle(.action(.secondary))
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                if !listener.note.isEmpty {
                    Text(listener.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                FlowRow(spacing: Space.s) {
                    ForEach(gaps) { gap in
                        Button {
                            onPick(gap)
                        } label: {
                            Label(gap.label, systemImage: gap.symbol)
                        }
                        .buttonStyle(.action(Tint.warning))
                        .help("Type the \(gap.inSentence)")
                    }
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("Missing")
            }
            .onDisappear { listener.cancel(engine: engine) }
            .sensoryFeedback(.success, trigger: answered)
        }
    }

    private func finish(_ gap: Gap, engine: SpeechEngine) {
        Task { @MainActor in
            switch await listener.end(engine: engine, form: formSummary()) {
            case .value(let value):
                onFill(gap, value)
                answered += 1
            case .skip:
                skipped.insert(gap)
            case .none:
                break
            }
        }
    }
}
