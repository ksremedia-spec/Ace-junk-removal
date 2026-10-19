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
    static func money(_ text: String) -> Double? {
        let cleaned = text.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
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

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
