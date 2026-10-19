#if os(macOS)
import AppKit
import Combine
import SwiftData
import SwiftUI

/// The Mac layout: sidebar, list, detail, like Mail and Notes.
struct MacMainView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case today, jobs, unpaid, done, customers, dumpsters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .jobs: return "Jobs"
            case .unpaid: return "Unpaid"
            case .done: return "Done"
            case .customers: return "Customers"
            case .dumpsters: return "Dumpsters"
            }
        }

        var symbol: String {
            switch self {
            case .today: return "sun.max"
            case .jobs: return "calendar"
            case .unpaid: return "dollarsign.circle"
            case .done: return "checkmark.circle"
            case .customers: return "person.2"
            case .dumpsters: return "shippingbox"
            }
        }

        /// Which jobs list this item shows; nil for the other screens.
        var jobsFilter: JobsFilter? {
            switch self {
            case .jobs: return .upcoming
            case .unpaid: return .unpaid
            case .done: return .done
            default: return nil
            }
        }

        static func item(for filter: JobsFilter) -> SidebarItem {
            switch filter {
            case .upcoming: return .jobs
            case .unpaid: return .unpaid
            case .done: return .done
            }
        }
    }

    enum TodayItem: Hashable {
        case job(Job)
        case dumpster(Dumpster)
    }

    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.lastTabKey) private var sidebarRaw = SidebarItem.today.rawValue

    @State private var engine = WhisperKitEngine()
    @State private var selectedJob: Job?
    @State private var selectedCustomer: Customer?
    @State private var selectedDumpster: Dumpster?
    @State private var selectedTodayItem: TodayItem?
    @State private var showingAssistant = false
    @State private var showingNewJob = false
    @State private var showingNewCustomer = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var handledLaunchArguments = false

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: sidebarRaw) ?? .today },
            set: { if let item = $0 { sidebarRaw = item.rawValue } }
        )
    }

    private var section: SidebarItem { SidebarItem(rawValue: sidebarRaw) ?? .today }

    /// The jobs list's filter, kept in step with the sidebar: picking
    /// "Unpaid" in the list highlights Unpaid in the sidebar and back.
    private var jobsFilter: Binding<JobsFilter> {
        Binding(
            get: { section.jobsFilter ?? .upcoming },
            set: { sidebarRaw = SidebarItem.item(for: $0).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                sidebarRow(.today)
                sidebarRow(.jobs)
                sidebarRow(.unpaid, indented: true)
                sidebarRow(.done, indented: true)
                sidebarRow(.customers)
                sidebarRow(.dumpsters)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            NavigationStack {
                detailColumn
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingNewJob = true
                } label: {
                    Label("New Job", systemImage: "plus")
                }
                Button {
                    showingAssistant = true
                } label: {
                    Label("Assistant", systemImage: "apple.intelligence")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .sheet(isPresented: $showingAssistant) {
            AssistantView(engine: engine)
                .frame(minWidth: 520, minHeight: 560)
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil)
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        .sheet(isPresented: $showingNewCustomer) {
            NavigationStack {
                CustomerEditView(customer: nil)
            }
            .frame(minWidth: 480, minHeight: 420)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aceNewJob)) { _ in showingNewJob = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceNewCustomer)) { _ in showingNewCustomer = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceAssistant)) { _ in showingAssistant = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceFind)) { _ in searchFocused = true }
        .onAppear {
            handleLaunchArguments()
            WindowSnapshot.captureIfRequested()
        }
    }

    private func sidebarRow(_ item: SidebarItem, indented: Bool = false) -> some View {
        Label(item.title, systemImage: item.symbol)
            .padding(.leading, indented ? 20 : 0)
            .tag(item)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .today:
            MacTodayList(selection: $selectedTodayItem)
                .navigationTitle("Today")
        case .jobs, .unpaid, .done:
            MacJobsList(selection: $selectedJob, filter: jobsFilter, searchText: searchText)
                .navigationTitle(section.title)
        case .customers:
            MacCustomersList(selection: $selectedCustomer, searchText: searchText)
                .navigationTitle("Customers")
        case .dumpsters:
            MacDumpstersList(selection: $selectedDumpster)
                .navigationTitle("Dumpsters")
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch section {
        case .today:
            switch selectedTodayItem {
            case .job(let job):
                JobEditView(job: job)
                    .id(job.persistentModelID)
            case .dumpster(let dumpster):
                DumpsterDetailView(dumpster: dumpster)
                    .id(dumpster.persistentModelID)
            case .none:
                placeholder("Select a job or a dumpster.")
            }
        case .jobs, .unpaid, .done:
            if let job = selectedJob {
                JobEditView(job: job)
                    .id(job.persistentModelID)
            } else {
                placeholder("Select a job, or press ⌘N for a new one.")
            }
        case .customers:
            if let customer = selectedCustomer {
                CustomerDetailView(customer: customer, onDeleted: { selectedCustomer = nil })
                    .id(customer.persistentModelID)
            } else {
                placeholder("Select a customer.")
            }
        case .dumpsters:
            if let dumpster = selectedDumpster {
                DumpsterDetailView(dumpster: dumpster)
                    .id(dumpster.persistentModelID)
            } else {
                placeholder("Select a dumpster.")
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same testing aid as on iPhone: `-sampledata` loads the sample records,
    /// `-open jobs` picks a sidebar item, `-open assistant` shows the Assistant.
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
        if let item = SidebarItem(rawValue: name) {
            sidebarRaw = item.rawValue
        } else if name == "assistant" {
            showingAssistant = true
        }
    }
}

// MARK: - Lists for the middle column

struct MacTodayList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Binding var selection: MacMainView.TodayItem?

    private var calendar: Calendar { .current }

    private var attentionDumpsters: [Dumpster] {
        dumpsters.filter { [.dueToday, .overdue].contains($0.status()) }
    }

    private var todaysJobs: [Job] { jobs.filter { calendar.isDateInToday($0.scheduledAt) && !$0.isDone } }
    private var tomorrowsJobs: [Job] { jobs.filter { calendar.isDateInTomorrow($0.scheduledAt) && !$0.isDone } }
    private var slippedJobs: [Job] { jobs.filter { !$0.isDone && $0.scheduledAt < Dates.startOfToday() } }

    var body: some View {
        List(selection: $selection) {
            Section("Dumpsters") {
                if attentionDumpsters.isEmpty {
                    Text(dumpsters.isEmpty ? "No dumpsters set up yet." : "Nothing due back today.")
                        .foregroundStyle(.secondary)
                }
                ForEach(attentionDumpsters) { dumpster in
                    DumpsterRow(dumpster: dumpster)
                        .tag(MacMainView.TodayItem.dumpster(dumpster))
                }
            }
            Section(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                if todaysJobs.isEmpty {
                    Text("No jobs today.").foregroundStyle(.secondary)
                }
                ForEach(todaysJobs) { job in
                    JobRow(job: job, showDate: false)
                        .tag(MacMainView.TodayItem.job(job))
                        .contextMenu { JobContextMenu(job: job) }
                }
            }
            if !slippedJobs.isEmpty {
                Section("Not marked done") {
                    ForEach(slippedJobs) { job in
                        JobRow(job: job)
                            .tag(MacMainView.TodayItem.job(job))
                            .contextMenu { JobContextMenu(job: job) }
                    }
                }
            }
            Section("Tomorrow") {
                if tomorrowsJobs.isEmpty {
                    Text("No jobs tomorrow.").foregroundStyle(.secondary)
                }
                ForEach(tomorrowsJobs) { job in
                    JobRow(job: job, showDate: false)
                        .tag(MacMainView.TodayItem.job(job))
                        .contextMenu { JobContextMenu(job: job) }
                }
            }
        }
    }
}

/// Jobs: upcoming by day, unpaid, or done. The filter is shared with the
/// sidebar, so either one changes the other.
struct MacJobsList: View {
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Binding var selection: Job?
    @Binding var filter: JobsFilter
    var searchText: String

    private var filtered: [Job] { JobSearch.filter(jobs, searchText) }
    private var shown: [Job] { filter.apply(to: filtered) }
    private var days: [JobDay] { JobDay.group(shown) }
    private var slipped: [Job] { filtered.filter { !$0.isDone && $0.scheduledAt < Dates.startOfToday() } }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(JobsFilter.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch filter {
            case .upcoming:
                upcomingSections
            case .unpaid:
                flatSection(header: unpaidHeader, empty: searchText.isEmpty ? "Nothing owed." : "No matching jobs.")
            case .done:
                flatSection(header: doneHeader, empty: searchText.isEmpty ? "No done jobs yet." : "No matching jobs.")
            }
        }
    }

    @ViewBuilder
    private var upcomingSections: some View {
        if !slipped.isEmpty {
            Section("Not marked done") {
                ForEach(slipped) { job in
                    row(job)
                }
            }
        }
        if days.isEmpty {
            Section("Upcoming") {
                Text(searchText.isEmpty ? "No jobs scheduled." : "No matching jobs.")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(days) { day in
            Section(day.title) {
                ForEach(day.jobs) { job in
                    row(job)
                }
            }
        }
    }

    private func flatSection(header: String, empty: String) -> some View {
        Section(header) {
            if shown.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { job in
                row(job)
            }
        }
    }

    private var unpaidHeader: String {
        shown.isEmpty ? "Unpaid" : "Unpaid · " + Plural.text(shown.count, "job") + " · " + Money.text(shown.priceTotal)
    }

    private var doneHeader: String {
        shown.isEmpty ? "Done" : "Done · \(shown.count)"
    }

    private func row(_ job: Job) -> some View {
        JobRow(job: job)
            .tag(job)
            .contextMenu { JobContextMenu(job: job) }
    }
}

/// How the Mac customers list is ordered.
enum CustomerSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case lastJob = "Last job"
    case totalSpent = "Total spent"

    var id: String { rawValue }

    /// `customers` arrive sorted by name from the query.
    func sorted(_ customers: [Customer]) -> [Customer] {
        switch self {
        case .name:
            return customers
        case .lastJob:
            return customers.sorted { ($0.lastJobDate ?? .distantPast) > ($1.lastJobDate ?? .distantPast) }
        case .totalSpent:
            return customers.sorted { $0.totalBilled > $1.totalBilled }
        }
    }
}

struct MacCustomersList: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Binding var selection: Customer?
    var searchText: String

    @State private var sort: CustomerSort = .name
    @State private var newJobCustomer: Customer?
    @State private var customerToDelete: Customer?
    @State private var confirmDelete = false

    private var filtered: [Customer] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return sort.sorted(customers) }
        let digits = query.filter(\.isNumber)
        return sort.sorted(customers.filter {
            $0.name.lowercased().contains(query)
                || $0.address.lowercased().contains(query)
                || (!digits.isEmpty && $0.phoneDigits.contains(digits))
        })
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Sort by", selection: $sort) {
                    ForEach(CustomerSort.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
            }
            Section {
                if filtered.isEmpty {
                    Text(customers.isEmpty ? "No customers yet." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { customer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name)
                        if !customer.phone.isEmpty || !customer.address.isEmpty {
                            Text([customer.phone, customer.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(customer)
                    .contextMenu { contextMenu(for: customer) }
                }
            }
        }
        .sheet(item: $newJobCustomer) { customer in
            NavigationStack {
                JobEditView(job: nil, prefill: JobFormData(customer: customer))
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        .confirmationDialog(deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deletePendingCustomer() }
        }
    }

    @ViewBuilder
    private func contextMenu(for customer: Customer) -> some View {
        Button("New Job for \(customer.name)") {
            newJobCustomer = customer
        }
        if let url = customer.phoneURL {
            Button("Call") {
                openURL(url)
            }
        }
        if !customer.address.isEmpty {
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                _ = NSPasteboard.general.setString(customer.address, forType: .string)
            }
        }
        Divider()
        Button("Delete…", role: .destructive) {
            customerToDelete = customer
            confirmDelete = true
        }
    }

    private var deleteQuestion: String {
        "Delete \(customerToDelete?.name ?? "this customer")? Their jobs are kept without a customer."
    }

    private func deletePendingCustomer() {
        guard let customer = customerToDelete else { return }
        if selection == customer { selection = nil }
        customer.remove(from: context)
        customerToDelete = nil
    }
}

struct MacDumpstersList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Binding var selection: Dumpster?

    var body: some View {
        List(selection: $selection) {
            if dumpsters.isEmpty {
                Text("No dumpsters set up yet.")
                    .foregroundStyle(.secondary)
                Button("Set up 6 dumpsters") {
                    for number in 1...6 {
                        context.insert(Dumpster(number: number))
                    }
                    try? context.save()
                }
            }
            ForEach(dumpsters) { dumpster in
                DumpsterRow(dumpster: dumpster)
                    .tag(dumpster)
            }
        }
    }
}

/// Right-click menu for a job row.
struct JobContextMenu: View {
    @Environment(\.modelContext) private var context
    let job: Job

    var body: some View {
        Button(job.isDone ? "Mark Not Done" : "Mark Done") {
            job.isDone.toggle()
            job.updatedAt = Date()
            try? context.save()
        }
        Button(job.isPaid ? "Mark Unpaid" : "Mark Paid") {
            job.isPaid.toggle()
            job.updatedAt = Date()
            try? context.save()
        }
        Divider()
        Button("Delete Job", role: .destructive) {
            context.delete(job)
            try? context.save()
        }
    }
}

// MARK: - Settings window (app menu › Settings, ⌘,)

struct MacSettingsWindow: View {
    @State private var engine = WhisperKitEngine()

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationDestination(for: MainView.Screen.self) { screen in
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
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
#endif
