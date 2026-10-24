#if os(macOS)
import SwiftUI

extension Notification.Name {
    /// View › Go to Today also moves the Calendar's month grid to this month.
    static let aceGoToToday = Notification.Name("aceGoToToday")
}

/// What the menu bar's items do in the front window. Each Mac window
/// publishes its own, so an item acts on that window only, not on every
/// open window (audit Oct 24, 32). With no Ace window in front the items
/// are greyed out instead of doing nothing (75); File › New Window or the
/// Dock brings a window back.
struct AceWindowActions {
    var newJob: () -> Void
    var newCustomer: () -> Void
    var newQuote: () -> Void
    var assistant: () -> Void
    var importSheet: () -> Void
    var find: () -> Void
    var goToToday: () -> Void
    var welcome: () -> Void
}

extension FocusedValues {
    @Entry var aceWindow: AceWindowActions?
}

struct AceCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.aceWindow) private var window

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Job") {
                window?.newJob()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(window == nil)

            Button("New Customer") {
                window?.newCustomer()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(window == nil)

            // No shortcut: ⇧⌘Q and ⌥⌘Q belong to the system.
            Button("New Quote") {
                window?.newQuote()
            }
            .disabled(window == nil)

            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Assistant") {
                window?.assistant()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(window == nil)

            Divider()

            Button("Import Customers from Excel…") {
                window?.importSheet()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            // With sync on, jobs come from the Google Sheet; an import as
            // well would make second copies there (audit Oct 21, M10).
            .disabled(window == nil || SyncEngine.shared.isSetUp)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") {
                window?.find()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(window == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Getting Started") {
                window?.welcome()
            }
            .disabled(window == nil)
        }

        // View menu, as in Apple's Calendar app.
        CommandGroup(before: .sidebar) {
            Button("Go to Today") {
                window?.goToToday()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(window == nil)

            // Design idea 7 (audit Oct 21): sync on demand.
            Button("Sync Now") {
                Task { await SyncEngine.shared.syncNow(manual: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!SyncEngine.shared.isSetUp)

            Divider()
        }
    }
}
#endif
