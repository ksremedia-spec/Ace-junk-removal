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
    static let speechModelKey = "settings.speechModel"
    static let defaultSpeechModel = "openai_whisper-base.en"

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
    /// Alex says otherwise (Oct 20: an assumption). Kept on each device
    /// until sync.
    static let salaryDaysKey = "settings.salaryDays"
    static let defaultSalaryDays: Set<Int> = [2, 3, 4, 5, 6, 7]

    static var salaryDays: Set<Int> {
        get {
            guard let stored = UserDefaults.standard.string(forKey: salaryDaysKey) else { return defaultSalaryDays }
            return Set(stored.split(separator: ",").compactMap { Int($0) })
        }
        set {
            UserDefaults.standard.set(newValue.sorted().map(String.init).joined(separator: ","), forKey: salaryDaysKey)
        }
    }

    static var overweightRate: Double {
        let stored = UserDefaults.standard.double(forKey: overweightRateKey)
        return stored > 0 ? stored : defaultOverweightRate
    }

    static var claudeModel: ClaudeModel {
        ClaudeModel(rawValue: UserDefaults.standard.string(forKey: claudeModelKey) ?? "") ?? .haiku
    }

    static var speechModel: String {
        UserDefaults.standard.string(forKey: speechModelKey) ?? defaultSpeechModel
    }

    static var effort: ClaudeEffort {
        ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: effortKey) ?? "") ?? .medium
    }
}
