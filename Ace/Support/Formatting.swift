import Foundation
import SwiftUI

/// Keyboard choices exist only on iOS; on the Mac these do nothing.
extension View {
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func phoneKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad)
        #else
        self
        #endif
    }
}

enum PhoneFormat {
    /// "5085550147" → "508-555-0147". Anything else is returned as typed.
    static func formatted(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
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
