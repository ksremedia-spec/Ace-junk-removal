import SwiftData
import SwiftUI

/// The iPhone layout: five tabs (Calendar, Jobs, Customers, Dumpsters,
/// Labor), with the Assistant reachable from every tab's toolbar and
/// Settings from the Calendar tab's. Quotes moved under Calendar when Labor
/// took the fifth tab (Oct 20): a sixth would hide behind "More". The app
/// reopens on the tab it was left on.
struct MainView: View {
    enum AppTab: String {
        case calendar, jobs, customers, dumpsters, labor
    }

    /// Screens that can be pushed from a launch argument (testing aid) or
    /// from Settings. Kept as plain names so `-open <name>` works.
    enum Screen: String, Hashable {
        case settings, apikey, speech, claude, calendars
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// A stored "today" (from before Calendar replaced Today) opens Calendar.
    @AppStorage(AppSettings.lastTabKey) private var lastTabRaw = AppTab.calendar.rawValue
    @State private var engine = WhisperKitEngine()
    @State private var showingAssistant = false
    @State private var calendarPath = NavigationPath()
    /// The day chosen on the Calendar tab. Not remembered: the app always
    /// opens on today.
    @State private var calendarDay = Dates.startOfToday()
    @State private var handledLaunchArguments = false

    private var selectedTab: Binding<AppTab> {
        Binding(
            // "quotes" (the old fifth tab) and anything unknown open Calendar.
            get: { AppTab(rawValue: lastTabRaw) ?? .calendar },
            set: { lastTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack(path: $calendarPath) {
                    CalendarView(selectedDay: $calendarDay, onShowQuotes: { showOpenQuotes() })
                        .toolbar { toolbarItems(showSettings: true, showToday: !calendarShowsToday) }
                        .navigationDestination(for: Screen.self, destination: screen)
                }
            }
            Tab("Jobs", systemImage: "list.bullet", value: AppTab.jobs) {
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
            Tab("Labor", systemImage: "clock", value: AppTab.labor) {
                NavigationStack {
                    LaborView()
                        .toolbar { toolbarItems(showSettings: false) }
                }
            }
        }
        .sheet(isPresented: $showingAssistant) {
            AssistantView(engine: engine)
        }
        .onAppear(perform: handleLaunchArguments)
        .onChange(of: scenePhase) { _, phase in
            // Calendar access may have been changed in Settings meanwhile.
            if phase == .active { CalendarStore.shared.refresh() }
        }
    }

    private var calendarShowsToday: Bool {
        Calendar.current.isDateInToday(calendarDay)
    }

    /// `showToday`: the Calendar's Today button, next to the gear, shown
    /// while another day is chosen. It goes back to today and its month.
    @ToolbarContentBuilder
    private func toolbarItems(showSettings: Bool, showToday: Bool = false) -> some ToolbarContent {
        if showSettings {
            ToolbarItem(placement: .navigation) {
                NavigationLink(value: Screen.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        if showToday {
            ToolbarItem(placement: .navigation) {
                Button("Today") {
                    calendarDay = Dates.startOfToday()
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

    /// The Calendar's Quotes figure: the Quotes list, on the Calendar tab.
    private func showOpenQuotes() {
        lastTabRaw = AppTab.calendar.rawValue
        calendarPath = NavigationPath()
        calendarPath.append(CalendarView.Route.quotes)
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
        case .calendars:
            ShowCalendarsView()
        }
    }

    /// Testing aid for screenshots. `-open jobs` selects a tab (`-open today`
    /// opens Calendar, as before Calendar replaced Today); `-open settings`
    /// (or apikey, speech, claude) pushes that screen on the Calendar tab;
    /// `-open assistant` shows the Assistant; `-open newjob` opens a blank new
    /// job on the Jobs tab; `-sampledata` loads the sample
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
        } else if name == "quotes" {
            showOpenQuotes()
        } else if name == "today" {
            lastTabRaw = AppTab.calendar.rawValue
        } else if name == "newjob" {
            // The Jobs tab opens the blank form itself (see JobsView).
            lastTabRaw = AppTab.jobs.rawValue
        } else if name == "assistant" {
            showingAssistant = true
        } else if let screen = Screen(rawValue: name) {
            lastTabRaw = AppTab.calendar.rawValue
            calendarPath.append(screen)
        }
    }
}
