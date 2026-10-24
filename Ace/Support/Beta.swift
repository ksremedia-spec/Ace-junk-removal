import Foundation
import SwiftData

/// The test copy Kyle sends out before the visit (Oct 20): it opens on the
/// sample data instead of an empty app, so non-technical testers have
/// something to try. Off for the business copy (Oct 24): Ashley and Alex
/// start empty and sync with the business's server.
enum Beta {
    static let isBeta = false

    /// The Cloudflare relay that holds Kyle's API key for the beta
    /// (cloudflare/beta-relay). When set, the Assistant sends notes there
    /// and needs no key on the device. Nil: the device's own key is used.
    /// The address is read from `BetaRelay.txt` next to this file, which is
    /// kept out of the public repository (anyone with the address could use
    /// the relay). Without that file, there is no relay.
    static let relayURL: URL? = {
        guard isBeta,
              let file = Bundle.main.url(forResource: "BetaRelay", withExtension: "txt"),
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }()

    /// The Assistant can send notes: with a key in this device's Keychain,
    /// through the relay, or through the sync server, which passes them on
    /// with the key it holds (ClaudeClient).
    @MainActor
    static var assistantReady: Bool {
        relayURL != nil || Keychain.read(Keychain.anthropicAPIKey) != nil || SyncEngine.shared.config != nil
    }

    /// Set once the example records were loaded, so the guide and the import
    /// mention them only when they are there.
    static let examplesKey = "examplesLoaded"

    /// Loads the sample records the first time the app opens with an empty
    /// database. A database that already has customers is left alone.
    @MainActor
    static func loadSampleDataIfEmpty(in context: ModelContext) {
        guard isBeta else { return }
        #if DEBUG
        // `-debug.empty`: start with nothing, the way the finished app opens
        // for Ashley and Alex. A normal launch never carries the argument.
        if ProcessInfo.processInfo.arguments.contains("-debug.empty") { return }
        #endif
        // A copy that syncs gets its records from the server; examples here
        // would be sent to every other device.
        if SyncEngine.builtIn != nil { return }
        let count = (try? context.fetchCount(FetchDescriptor<Customer>())) ?? 0
        guard count == 0 else { return }
        SampleData.load(into: context)
        UserDefaults.standard.set(true, forKey: examplesKey)
    }
}
