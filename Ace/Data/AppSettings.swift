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
