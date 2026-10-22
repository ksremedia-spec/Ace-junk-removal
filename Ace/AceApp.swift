import SwiftData
import SwiftUI

@main
struct AceApp: App {
    /// One on-device database shared by every window.
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try ModelContainer(for: Customer.self, Job.self, Dumpster.self, RentalRecord.self, Quote.self, Worker.self, LaborEntry.self)
        } catch {
            fatalError("The app's database could not be opened: \(error.localizedDescription)")
        }
        Beta.loadSampleDataIfEmpty(in: container.mainContext)
        SyncEngine.shared.start(container.mainContext)
        #if os(macOS)
        // Screenshot workflow aid; does nothing without the -screenshot argument.
        WindowSnapshot.captureIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                #if os(macOS)
                MacMainView()
                #else
                MainView()
                #endif
            }
            // Back in front: bring in what changed elsewhere meanwhile.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { SyncEngine.shared.syncSoon() }
            }
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
