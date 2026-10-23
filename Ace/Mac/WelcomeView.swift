#if os(macOS)
import SwiftUI

/// The first-time guide on the Mac (Kyle, Oct 21: "a first time guide when
/// they first open the mac app ... that guides them to input excel"). Shown
/// once, on the first launch; Help › Getting Started opens it again.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("importedSheet") private var importedSheet = false
    @AppStorage(Beta.examplesKey) private var examplesLoaded = false
    @State private var sheetConnected = false
    /// Picks a sidebar section, closing the guide first.
    let go: (MacMainView.SidebarItem) -> Void
    let importSheet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                Image("AceEmblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Ace")
                        .font(.largeTitle.weight(.bold))
                    Text("Jobs, customers, dumpsters and the crew's hours, in one place.")
                        .foregroundStyle(.secondary)
                }
            }

            if examplesLoaded {
                Label("This test copy starts with example customers and jobs. Importing your own sheet can replace them.", systemImage: "info.circle")
                    .font(.callout)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
            }

            VStack(spacing: 0) {
                if SyncEngine.shared.isSetUp {
                    // With sync on, the sheet itself is connected; importing
                    // it as well would make second copies (audit Oct 21, M10).
                    step(1, "Connect the Google Sheet",
                         "In Settings, under Google Sheet, click Connect Google Sheet, sign in, click Allow and pick the job sheet. Its jobs come into Ace, and the two stay in step from then on.",
                         done: sheetConnected) {
                        SettingsLink { Text("Open Settings") }
                    }
                } else {
                    step(1, "Bring in the spreadsheet",
                         "In Google Sheets, open the job list and choose File › Download › Microsoft Excel (.xlsx). Then import that file here. Ace shows what it found before anything is saved.",
                         done: importedSheet) {
                        Button("Import…") { importSheet() }
                    }
                }
                Divider().padding(.leading, 52)
                step(2, "Set up the dumpsters",
                     "Each of the six shows whether it is in the yard or out, and when it is due back. On a new Mac, click Set up 6 dumpsters there. Drop-offs and pickups are logged there too.") {
                    Button("Open Dumpsters") { go(.dumpsters) }
                }
                Divider().padding(.leading, 52)
                step(3, "Add the crew",
                     "The people who work for you, so their weekly hours and pay can be kept on the Labor page.") {
                    Button("Open Labor") { go(.labor) }
                }
                Divider().padding(.leading, 52)
                step(4, "Use the Assistant",
                     Beta.relayURL != nil
                        ? "Set up for this test. Click Assistant in the toolbar and type or say a job, such as \"Linda Johnson, Friday at 9, $350.\""
                        : "Add the Anthropic key once in Settings. Then click Assistant and type or say a job, such as \"Linda Johnson, Friday at 9, $350.\"",
                     done: Beta.assistantReady) {
                    if !Beta.assistantReady {
                        SettingsLink { Text("Open Settings") }
                    }
                }
            }
            .cardBackground()

            HStack(spacing: Space.l) {
                shortcut("⌘N", "New job")
                shortcut("⌘F", "Search")
                shortcut("⇧⌘A", "Assistant")
                shortcut("⌘T", "Today")
                shortcut("⇧⌘I", "Import")
            }
            .font(.callout)

            Spacer(minLength: 0)

            HStack {
                Text("Open this again from Help › Getting Started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .task {
            if SyncEngine.shared.isSetUp {
                sheetConnected = await SyncEngine.shared.sheet("status")?.connected ?? false
            }
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step<Action: View>(_ number: Int, _ title: String, _ detail: String, done: Bool = false,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            ZStack {
                Circle()
                    .fill(done ? Tint.paid : Color.accentColor.opacity(0.15))
                if done {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number), \(title)\(done ? ", done" : ""). \(detail)")

            Spacer(minLength: Space.s)
            action()
        }
        .padding(Space.m)
    }

    private func shortcut(_ keys: String, _ name: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.callout.monospaced().weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(name)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
