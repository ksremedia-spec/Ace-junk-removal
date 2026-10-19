import SwiftData
import SwiftUI

@main
struct AceApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: [Customer.self, Job.self, Dumpster.self, RentalRecord.self])
    }
}
