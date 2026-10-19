import SwiftData
import SwiftUI

@main
struct AceApp: App {
    /// One on-device database shared by every window.
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Customer.self, Job.self, Dumpster.self, RentalRecord.self)
        } catch {
            fatalError("The app's database could not be opened: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(macOS)
            MacMainView()
            #else
            MainView()
            #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .commands {
            AceCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            MacSettingsWindow()
        }
        .modelContainer(container)
        #endif
    }
}
