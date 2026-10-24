import Foundation
import SwiftUI

/// Small settings kept in UserDefaults. The API key is NOT here; it lives in
/// the Keychain (see Keychain.swift).
enum AppSettings {
    /// Dollars per ton over the agreed weight.
    static let overweightRateKey = "settings.overweightRatePerTon"
    static let defaultOverweightRate = 125.0

    /// Which Claude model the Assistant uses.
    static let claudeModelKey = "settings.claudeModel"

    /// Which WhisperKit model the Assistant uses.

    /// Effort level sent to Claude for Assistant requests.
    static let effortKey = "settings.claudeEffort"

    /// Last selected tab, so the app opens where it was left.
    static let lastTabKey = "settings.lastTab"

    /// The calendar jobs are written to (its EventKit identifier). Empty
    /// means None. Kept on each device, not synced.
    static let jobsCalendarKey = "settings.jobsCalendar"

    /// Calendars switched off under Show Calendars (EventKit identifiers).
    /// Kept on each device, not synced.
    static let hiddenCalendarsKey = "settings.hiddenCalendars"

    /// The weekdays salaried crew count as working (Calendar weekday
    /// numbers, 1 is Sunday), as "2,3,4,5,6,7". Monday to Saturday until
    /// Alex says otherwise (Oct 20: an assumption). Shared by sync, like
    /// the overweight rate.
    static let salaryDaysKey = "settings.salaryDays"
    static let defaultSalaryDays: Set<Int> = [2, 3, 4, 5, 6, 7]

    static var salaryDays: Set<Int> { storedSalaryDays ?? defaultSalaryDays }

    /// The days as set on some device, or nil if never set.
    static var storedSalaryDays: Set<Int>? {
        guard let stored = UserDefaults.standard.string(forKey: salaryDaysKey) else { return nil }
        return Set(stored.split(separator: ",").compactMap { Int($0) })
    }

    static var overweightRate: Double { storedOverweightRate ?? defaultOverweightRate }

    /// The rate as set on some device, or nil if never set.
    static var storedOverweightRate: Double? {
        let stored = UserDefaults.standard.double(forKey: overweightRateKey)
        return stored > 0 ? stored : nil
    }

    // MARK: Shared with every device

    /// When the overweight rate or the salary days last changed, here or on
    /// another device. The two travel together as one sync record
    /// (`SyncType.setting`); nil until either is changed, so a new device
    /// sends nothing and keeps its defaults until one arrives.
    static let sharedUpdatedAtKey = "settings.sharedUpdatedAt"

    static var sharedUpdatedAt: Date? { UserDefaults.standard.object(forKey: sharedUpdatedAtKey) as? Date }

    static func stampShared(_ date: Date) {
        UserDefaults.standard.set(date, forKey: sharedUpdatedAtKey)
    }

    /// Changed in Settings: saved, stamped, and sent to the other devices.
    /// The same value again (Settings filling in its field) changes nothing.
    @MainActor static func setOverweightRate(_ value: Double) {
        guard value > 0, value != overweightRate else { return }
        UserDefaults.standard.set(value, forKey: overweightRateKey)
        sharedChanged()
    }

    @MainActor static func setSalaryDays(_ days: Set<Int>) {
        guard days != salaryDays else { return }
        writeSalaryDays(days)
        sharedChanged()
    }

    /// The copy from another device (the later change wins, as for records).
    /// A value it does not have leaves this device's own alone.
    static func applyShared(_ data: SettingData, updatedAt: Date) {
        if let rate = data.overweightRatePerTon, rate > 0 {
            UserDefaults.standard.set(rate, forKey: overweightRateKey)
        }
        if let days = data.salaryDays {
            writeSalaryDays(Set(days))
        }
        stampShared(updatedAt)
    }

    /// Back to the built-in defaults, not yet shared.
    static func clearShared() {
        for key in [overweightRateKey, salaryDaysKey, sharedUpdatedAtKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func writeSalaryDays(_ days: Set<Int>) {
        UserDefaults.standard.set(days.sorted().map(String.init).joined(separator: ","), forKey: salaryDaysKey)
    }

    @MainActor private static func sharedChanged() {
        stampShared(Date())
        SyncEngine.shared.settingsChanged()
    }

    static var claudeModel: ClaudeModel {
        ClaudeModel(rawValue: UserDefaults.standard.string(forKey: claudeModelKey) ?? "") ?? .haiku
    }

    static var effort: ClaudeEffort {
        ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: effortKey) ?? "") ?? .medium
    }
}
