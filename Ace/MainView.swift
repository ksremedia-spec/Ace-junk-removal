import SwiftData
import SwiftUI

/// The iPhone layout: four tabs, with the Assistant and Settings reachable
/// from every tab's toolbar. The app reopens on the tab it was left on.
struct MainView: View {
    enum AppTab: String {
        case today, jobs, customers, dumpsters
    }

    /// Screens that can be pushed from a launch argument (testing aid) or
    /// from Settings. Kept as plain names so `-open <name>` works.
    enum Screen: String, Hashable {
        case settings, apikey, speech, claude
    }

    @Environment(\.modelContext) private var context

    @AppStorage(AppSettings.lastTabKey) private var lastTabRaw = AppTab.today.rawValue
    @State private var engine = WhisperKitEngine()
    @State private var showingAssistant = false
    @State private var todayPath = NavigationPath()
    @State private var handledLaunchArguments = false

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: lastTabRaw) ?? .today },
            set: { lastTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView()
                        .toolbar { toolbarItems(showSettings: true) }
                        .navigationDestination(for: Screen.self, destination: screen)
                }
            }
            Tab("Jobs", systemImage: "calendar", value: AppTab.jobs) {
                NavigationStack {
                    JobsView()
                        .toolbar { toolbarItems(showSettings: false) }
                }
            }
            Tab("Customers", systemImage: "person.2", value: AppTab.customers) {
                NavigationStack {
                    CustomersView()
                        .toolbar { toolbarItems(showSettings: false) }
                }
            }
            Tab("Dumpsters", systemImage: "shippingbox", value: AppTab.dumpsters) {
                NavigationStack {
                    DumpstersView()
                        .toolbar { toolbarItems(showSettings: false) }
                }
            }
        }
        .sheet(isPresented: $showingAssistant) {
            AssistantView(engine: engine)
        }
        .onAppear(perform: handleLaunchArguments)
    }

    @ToolbarContentBuilder
    private func toolbarItems(showSettings: Bool) -> some ToolbarContent {
        if showSettings {
            ToolbarItem(placement: .navigation) {
                NavigationLink(value: Screen.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAssistant = true
            } label: {
                Label("Assistant", systemImage: "apple.intelligence")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    @ViewBuilder
    private func screen(_ screen: Screen) -> some View {
        switch screen {
        case .settings:
            SettingsView()
        case .apikey:
            APIKeyView()
        case .speech:
            SpeechTestView(engine: engine)
        case .claude:
            ClaudeTestView()
        }
    }

    /// Testing aid for screenshots. `-open jobs` selects a tab; `-open settings`
    /// (or apikey, speech, claude) pushes that screen on the Today tab;
    /// `-open assistant` shows the Assistant; `-sampledata` loads the sample
    /// records first. Normal launches carry none of these and nothing happens.
    private func handleLaunchArguments() {
        guard !handledLaunchArguments else { return }
        handledLaunchArguments = true
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-sampledata") {
            SampleData.clear(context: context)
            SampleData.load(into: context)
        }

        var name: String?
        if let index = args.firstIndex(of: "-open"), index + 1 < args.count {
            name = args[index + 1].lowercased()
        } else if let arg = args.first(where: { $0.hasPrefix("-open=") }) {
            name = String(arg.dropFirst("-open=".count)).lowercased()
        }
        guard let name else { return }

        if let tab = AppTab(rawValue: name) {
            lastTabRaw = tab.rawValue
        } else if name == "assistant" {
            showingAssistant = true
        } else if let screen = Screen(rawValue: name) {
            lastTabRaw = AppTab.today.rawValue
            todayPath.append(screen)
        }
    }
}
