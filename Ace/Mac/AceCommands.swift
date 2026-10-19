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

            // Step 7 of the build order. Shown now so the menu is complete.
            Button("Import Customers from Excel…") {}
                .disabled(true)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .aceFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
#endif
