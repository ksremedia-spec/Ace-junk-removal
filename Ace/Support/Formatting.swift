import Foundation
import SwiftUI

/// Keyboard choices exist only on iOS; on the Mac these do nothing. The
/// number and phone pads have no Return key, so they get a Done button.
extension View {
    /// `focus`: the field's own focus, when the view already tracks it (the
    /// hours box), so the Done button uses it instead of a second tracker.
    @ViewBuilder
    func decimalKeyboard(focus: FocusState<Bool>.Binding? = nil) -> some View {
        #if os(iOS)
        if let focus {
            self.keyboardType(.decimalPad)
                .modifier(KeyboardDoneFor(focused: focus))
        } else {
            self.keyboardType(.decimalPad)
                .modifier(KeyboardDone())
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func phoneKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad)
            .modifier(KeyboardDone())
        #else
        self
        #endif
    }

    /// Names and addresses: each word starts with a capital, and spelling
    /// correction stays off so "Souza" is not changed to "Sousa".
    @ViewBuilder
    func wordsCapitalized() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Numbers first, letters one tap away, for "12" or "12A".
    @ViewBuilder
    func houseNumberKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}

#if os(iOS)
/// A Done button above the keyboard while this one field is being typed
/// in. Shown per field: one button on the page (Oct 20) never appeared.
private struct KeyboardDone: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }
                    }
                }
            }
    }
}

/// The same Done button, for a field whose focus the view tracks itself.
private struct KeyboardDoneFor: ViewModifier {
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .toolbar {
                if focused.wrappedValue {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused.wrappedValue = false }
                    }
                }
            }
    }
}
#endif

enum Maps {
    /// Apple Maps driving directions to an address, so Directions starts the
    /// route instead of showing a pin or a list of towns (Oct 20 phone audit).
    static func directions(to address: String) -> URL? {
        let place = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: place), URLQueryItem(name: "dirflg", value: "d")]
        return components?.url
    }
}

/// A search as typed, read the way people search a customer list (Oct 20
/// phone audit). Every word must be found somewhere ("souza lakeville",
/// "al souza"), accents do not matter ("conceicao" finds Conceição), and
/// digits search phone numbers only when the search is mostly a phone
/// number, so "42 elm" does not match every phone with a 42 in it.
struct SearchText {
    let words: [String]
    /// The phone digits, when the search reads as a phone number.
    let phoneDigits: String?

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let stripped = trimmed.filter { !" -.()+".contains($0) }
        let digits = PhoneFormat.digits(stripped)
        phoneDigits = digits.count >= 3 && digits.count == stripped.filter(\.isNumber).count && stripped.allSatisfy(\.isNumber) ? digits : nil
    }

    var isEmpty: Bool { words.isEmpty }

    func matches(texts: [String], phoneDigits phone: String) -> Bool {
        guard !isEmpty else { return true }
        if let phoneDigits, phone.contains(phoneDigits) { return true }
        return words.allSatisfy { word in
            texts.contains { $0.localizedStandardContains(word) }
        }
    }
}

enum PhoneFormat {
    /// The phone number's digits, without a leading US 1: "+1 (508) 555-0147"
    /// and "508-555-0147" both give "5085550147".
    static func digits(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits
    }

    /// "Phone number has 9 digits, not 10." for a number that looks short or
    /// long. It still saves; this only warns.
    static func problem(_ raw: String) -> String? {
        let count = digits(raw).count
        guard count > 0, count != 10 else { return nil }
        return "Phone number has \(count) digits, not 10."
    }

    /// "5085550147" → "508-555-0147". Anything else is returned as typed.
    static func formatted(_ raw: String) -> String {
        let digits = digits(raw)
        guard digits.count == 10 else { return raw.trimmingCharacters(in: .whitespaces) }
        let a = digits.prefix(3)
        let b = digits.dropFirst(3).prefix(3)
        let c = digits.dropFirst(6)
        return "\(a)-\(b)-\(c)"
    }
}

enum Parse {
    /// "$300", "300.00", "1,250" → 300, 300, 1250. Empty or junk → nil.
    /// Only the first number counts, so "300-350" is 300, not 300350.
    static func money(_ text: String) -> Double? {
        guard let match = text.firstMatch(of: /[0-9][0-9,]*(\.[0-9]+)?|\.[0-9]+/) else { return nil }
        return Double(match.output.0.replacingOccurrences(of: ",", with: ""))
    }

    static func tons(_ text: String) -> Double? {
        money(text)
    }

    static func moneyText(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return amount.rounded() == amount ? String(Int(amount)) : String(amount)
    }

    static func tonsText(_ tons: Double?) -> String {
        moneyText(tons)
    }
}

enum Dates {
    static func startOfToday(_ calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: Date())
    }

    /// Today at the next full hour, for a new job's default time.
    static func nextFullHour(_ calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? Date()
    }

    /// "Tue, Oct 20", with the year added when it is not this year
    /// ("Sun, Nov 8, 2024"), so two years of history are never confused.
    static func shortDay(_ date: Date) -> String {
        date.formatted(isThisYear(date)
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    static func isThisYear(_ date: Date, _ calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: Date(), toGranularity: .year)
    }

    /// "Friday, October 24", with the year when it is not this year.
    static func longDay(_ date: Date) -> String {
        date.formatted(isThisYear(date)
            ? .dateTime.weekday(.wide).month(.wide).day()
            : .dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// "October 2026"
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func isInCurrentMonth(_ date: Date, _ calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: Date(), toGranularity: .month)
    }
}

enum Tons {
    /// "2.4"
    static func number(_ tons: Double) -> String {
        tons.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "2.4 tons", "1 ton"
    static func text(_ tons: Double) -> String {
        number(tons) + (tons == 1 ? " ton" : " tons")
    }
}

enum Plural {
    /// "1 job", "3 jobs". For words whose plural just adds an s.
    static func text(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
