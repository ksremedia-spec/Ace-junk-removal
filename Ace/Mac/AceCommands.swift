#if os(macOS)
import SwiftUI

/// Menu bar items. They post notifications that the front window acts on,
/// so each window handles its own sheets.
extension Notification.Name {
    static let aceNewJob = Notification.Name("aceNewJob")
    static let aceNewCustomer = Notification.Name("aceNewCustomer")
    static let aceNewQuote = Notification.Name("aceNewQuote")
    static let aceAssistant = Notification.Name("aceAssistant")
    static let aceFind = Notification.Name("aceFind")
    static let aceGoToToday = Notification.Name("aceGoToToday")
    static let aceImport = Notification.Name("aceImport")
    static let aceWelcome = Notification.Name("aceWelcome")
}

struct AceCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Job") {
                NotificationCenter.default.post(name: .aceNewJob, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Customer") {
                NotificationCenter.default.post(name: .aceNewCustomer, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            // No shortcut: ⇧⌘Q and ⌥⌘Q belong to the system.
            Button("New Quote") {
                NotificationCenter.default.post(name: .aceNewQuote, object: nil)
            }

            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Assistant") {
                NotificationCenter.default.post(name: .aceAssistant, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Import Customers from Excel…") {
                NotificationCenter.default.post(name: .aceImport, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .aceFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Getting Started") {
                NotificationCenter.default.post(name: .aceWelcome, object: nil)
            }
        }

        // View menu, as in Apple's Calendar app.
        CommandGroup(before: .sidebar) {
            Button("Go to Today") {
                NotificationCenter.default.post(name: .aceGoToToday, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()
        }
    }
}
#endif
