#if os(macOS)
import AppKit
import Combine
import SwiftData
import SwiftUI

/// The Mac layout: sidebar, list, detail, like Mail and Notes.
struct MacMainView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case calendar, jobs, unpaid, done, quotes, customers, dumpsters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "Calendar"
            case .jobs: return "Jobs"
            case .unpaid: return "Unpaid"
            case .done: return "Done"
            case .quotes: return "Quotes"
            case .customers: return "Customers"
            case .dumpsters: return "Dumpsters"
            }
        }

        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .jobs: return "list.bullet"
            case .unpaid: return "dollarsign.circle"
            case .done: return "checkmark.circle"
            case .quotes: return "doc.text"
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

    /// What can be selected in the Calendar list.
    enum CalendarItem: Hashable {
        case job(Job)
        case dumpster(Dumpster)
        case quote(Quote)
        case event(OtherEvent)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Job.scheduledAt) private var allJobs: [Job]
    @Query(sort: \Quote.quotedOn) private var allQuotes: [Quote]
    @Query(sort: \Dumpster.number) private var allDumpsters: [Dumpster]
    /// A stored "today" (from before Calendar replaced Today) opens Calendar.
    @AppStorage(AppSettings.lastTabKey) private var sidebarRaw = SidebarItem.calendar.rawValue

    @State private var engine = WhisperKitEngine()
    @State private var selectedJob: Job?
    @State private var selectedCustomer: Customer?
    @State private var selectedDumpster: Dumpster?
    @State private var selectedQuote: Quote?
    @State private var selectedCalendarItem: CalendarItem?
    /// The day chosen in the Calendar list. Not remembered: the app always
    /// opens on today.
    @State private var calendarDay = Dates.startOfToday()
    /// The day the app last thought was today, so a stale "today" can be
    /// moved on after midnight without moving a day Ashley picked.
    @State private var knownToday = Dates.startOfToday()
    @State private var showingAssistant = false
    @State private var showingNewJob = false
    @State private var showingNewCustomer = false
    @State private var showingNewQuote = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var handledLaunchArguments = false

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: sidebarRaw) ?? .calendar },
            set: { if let item = $0 { sidebarRaw = item.rawValue } }
        )
    }

    private var section: SidebarItem { SidebarItem(rawValue: sidebarRaw) ?? .calendar }

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
            sidebarList
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            NavigationStack {
                detailColumn
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Click for a new job; hold or use the arrow for a quote or a
                // customer (Oct 20 audit: + only ever made jobs).
                Menu {
                    Button("New Job") { showingNewJob = true }
                    Button("New Quote") { showingNewQuote = true }
                    Button("New Customer") { showingNewCustomer = true }
                } label: {
                    Label("New", systemImage: "plus")
                } primaryAction: {
                    showingNewJob = true
                }
                .help("New job (⌘N). Click and hold for a quote or customer.")
                Button {
                    showingAssistant = true
                } label: {
                    Label("Assistant", systemImage: "apple.intelligence")
                        .labelStyle(.titleAndIcon)
                }
                .help("Assistant (⇧⌘A)")
                // Kyle could not find Settings: it lived only in the app menu.
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
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
        .sheet(isPresented: $showingNewQuote) {
            NavigationStack {
                QuoteEditView(quote: nil)
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aceNewJob)) { _ in showingNewJob = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceNewCustomer)) { _ in showingNewCustomer = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceNewQuote)) { _ in showingNewQuote = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceAssistant)) { _ in showingAssistant = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceFind)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .aceGoToToday)) { _ in goToToday() }
        .onChange(of: calendarDay) { _, _ in
            // The chosen job or event belongs to the day that was showing.
            selectedCalendarItem = nil
        }
        .onChange(of: scenePhase) { _, phase in
            // Calendar access may have been changed in System Settings.
            if phase == .active {
                CalendarStore.shared.refresh()
                rollOverToday()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            rollOverToday()
        }
        // A search typed for one list should not silently filter the next.
        .onChange(of: sidebarRaw) { _, _ in searchText = "" }
        .onAppear {
            handleLaunchArguments()
            WindowSnapshot.captureIfRequested()
        }
    }

    /// The screenshot workflow draws the window from inside the app, where the
    /// sidebar's glass highlight comes out as a black block. For that run only,
    /// the sidebar uses a plain highlight and hides its collapse button.
    private var screenshotMode: Bool { ProcessInfo.processInfo.arguments.contains("-screenshot") }

    private var sidebarRows: some View {
        List(selection: sidebarSelection) {
            sidebarRow(.calendar)
            sidebarRow(.jobs)
            sidebarRow(.unpaid, indented: true)
            sidebarRow(.done, indented: true)
            sidebarRow(.quotes)
            sidebarRow(.customers)
            sidebarRow(.dumpsters)
        }
    }

    @ViewBuilder
    private var sidebarList: some View {
        if screenshotMode {
            sidebarRows
                .listStyle(.plain)
                .toolbar(removing: .sidebarToggle)
        } else {
            sidebarRows
        }
    }

    private func sidebarRow(_ item: SidebarItem, indented: Bool = false) -> some View {
        Label(item.title, systemImage: item.symbol)
            .padding(.leading, indented ? 20 : 0)
            .badge(badgeCount(item))
            .tag(item)
    }

    /// The number beside a sidebar item: jobs owed, open quotes, dumpsters
    /// due back today or overdue. Zero shows nothing.
    private func badgeCount(_ item: SidebarItem) -> Int {
        switch item {
        case .unpaid:
            return JobsFilter.unpaid.apply(to: allJobs).count
        case .quotes:
            return allQuotes.filter { $0.status == .open }.count
        case .dumpsters:
            return allDumpsters.filter { [.dueToday, .overdue].contains($0.status()) }.count
        default:
            return 0
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .calendar:
            MacCalendarList(selection: $selectedCalendarItem, day: $calendarDay)
                .navigationTitle("Calendar")
        case .jobs, .unpaid, .done:
            MacJobsList(selection: $selectedJob, filter: jobsFilter, searchText: searchText)
                .navigationTitle(section.title)
        case .quotes:
            MacQuotesList(selection: $selectedQuote, searchText: searchText)
                .navigationTitle("Quotes")
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
        case .calendar:
            switch selectedCalendarItem {
            case .job(let job):
                JobEditView(job: job)
                    .id(job.persistentModelID)
            case .dumpster(let dumpster):
                DumpsterDetailView(dumpster: dumpster)
                    .id(dumpster.persistentModelID)
            case .quote(let quote):
                QuoteEditView(quote: quote, onDeleted: { selectedCalendarItem = nil })
                    .id(quote.persistentModelID)
            case .event(let item):
                CalendarEventPage(event: item.event)
                    .id(item.id)
            case .none:
                EmptyDetail(title: "Nothing selected", symbol: "calendar",
                            message: "Choose a job, dumpster, quote or event on the left.")
            }
        case .jobs, .unpaid, .done:
            if let job = selectedJob {
                JobEditView(job: job)
                    .id(job.persistentModelID)
            } else {
                EmptyDetail(title: "No job selected", symbol: "truck.box",
                            message: "Choose a job on the left, or press ⌘N for a new one.")
            }
        case .quotes:
            if let quote = selectedQuote {
                QuoteEditView(quote: quote, onDeleted: { selectedQuote = nil })
                    .id(quote.persistentModelID)
            } else {
                EmptyDetail(title: "No quote selected", symbol: "doc.text",
                            message: "Choose a quote on the left.")
            }
        case .customers:
            if let customer = selectedCustomer {
                CustomerDetailView(customer: customer, onDeleted: { selectedCustomer = nil })
                    .id(customer.persistentModelID)
            } else {
                EmptyDetail(title: "No customer selected", symbol: "person.2",
                            message: "Choose a customer on the left, or press ⇧⌘N for a new one.")
            }
        case .dumpsters:
            if let dumpster = selectedDumpster {
                DumpsterDetailView(dumpster: dumpster)
                    .id(dumpster.persistentModelID)
            } else {
                EmptyDetail(title: "No dumpster selected", symbol: "shippingbox",
                            message: "Choose a dumpster on the left to drop it off, pick it up or see its rentals.")
            }
        }
    }

    /// After midnight (or waking the Mac the next day) a Calendar left on
    /// today moves to the new today; a day Ashley chose stays put.
    private func rollOverToday() {
        let now = Dates.startOfToday()
        guard now != knownToday else { return }
        if calendarDay == knownToday { calendarDay = now }
        knownToday = now
    }

    /// View › Go to Today (⌘T): the Calendar, on today.
    private func goToToday() {
        sidebarRaw = SidebarItem.calendar.rawValue
        calendarDay = Dates.startOfToday()
    }

    /// Same testing aid as on iPhone: `-sampledata` loads the sample records,
    /// `-open jobs` picks a sidebar item (`-open today` opens Calendar, as
    /// before Calendar replaced Today), `-open assistant` shows the
    /// Assistant, `-open newjob` opens a blank new job.
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
        } else if name == "today" {
            sidebarRaw = SidebarItem.calendar.rawValue
        } else if name == "assistant" {
            showingAssistant = true
        } else if name == "newjob" {
            sidebarRaw = SidebarItem.jobs.rawValue
            showingNewJob = true
        }
    }
}

// MARK: - Lists for the middle column

/// Jobs: upcoming by day, unpaid, or done. The filter is shared with the
/// sidebar, so either one changes the other.
struct MacJobsList: View {
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Binding var selection: Job?
    @Binding var filter: JobsFilter
    var searchText: String
    @State private var jobToDelete: Job?

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
        .confirmJobDelete($jobToDelete) { deleted in
            if selection == deleted { selection = nil }
        }
        // The page beside the list must be one of the jobs in it.
        .onChange(of: filter) { _, _ in
            selection = nil
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
                    row(job, showDate: false)
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

    private func row(_ job: Job, showDate: Bool = true) -> some View {
        JobRow(job: job, showDate: showDate, context: filter)
            .tag(job)
            .contextMenu { JobContextMenu(job: job, onDelete: { jobToDelete = $0 }) }
    }
}

/// Quotes: open (follow up first, then waiting), booked or lost. Same
/// sections and order as the iPhone list; right-click for Book Job, Mark
/// Lost or Reopen, and Delete.
struct MacQuotesList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Binding var selection: Quote?
    var searchText: String

    @State private var filter: QuoteStatus = .open
    @State private var quoteToBook: Quote?
    @State private var quoteToLose: Quote?
    @State private var quoteToDelete: Quote?
    /// "Quote marked lost." and the like, shown under the switch for a moment.
    @State private var notice: String?
    @State private var changed = 0

    private var filtered: [Quote] { QuoteSearch.filter(quotes, searchText) }
    private var shown: [Quote] { QuoteList.shown(filtered, status: filter) }
    private var followUp: [Quote] { QuoteList.followUp(shown) }
    private var waiting: [Quote] { QuoteList.waiting(shown) }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(QuoteStatus.listed) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                if let header = QuoteList.header(shown, status: filter) {
                    Text(header)
                }
            } footer: {
                if let notice {
                    Text(notice)
                }
            }

            switch filter {
            case .open:
                if !followUp.isEmpty {
                    Section("Follow up") {
                        ForEach(followUp) { quote in
                            row(quote)
                        }
                    }
                }
                if !waiting.isEmpty {
                    Section {
                        ForEach(waiting) { quote in
                            row(quote)
                        }
                    } header: {
                        if QuoteFeatures.followUps {
                            Text("Waiting")
                        }
                    }
                }
            case .booked, .lost:
                if !shown.isEmpty {
                    Section {
                        ForEach(shown) { quote in
                            row(quote)
                        }
                    }
                }
            }

            if shown.isEmpty {
                Section {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
            }

            // Lost quotes have no list of their own any more; a search still
            // finds them, so one marked lost by mistake can be reopened.
            if !searchText.isEmpty, !lostMatches.isEmpty {
                Section("Lost") {
                    ForEach(lostMatches) { quote in
                        row(quote, showStatus: true)
                    }
                }
            }
        }
        .onChange(of: filter) { _, _ in selection = nil }
        .confirmationDialog("Mark this quote lost?", isPresented: Binding(
            get: { quoteToLose != nil }, set: { if !$0 { quoteToLose = nil } }
        ), titleVisibility: .visible) {
            Button("Mark lost") { if let quoteToLose { markLost(quoteToLose) } }
        } message: {
            Text("It leaves the Quotes list. Search still finds it, and Reopen brings it back.")
        }
        .confirmationDialog(deleteQuestion, isPresented: Binding(
            get: { quoteToDelete != nil }, set: { if !$0 { quoteToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Quote", role: .destructive) { if let quoteToDelete { delete(quoteToDelete) } }
        }
        .sheet(item: $quoteToBook) { quote in
            NavigationStack {
                JobEditView(job: nil, prefill: QuoteFormData(quote: quote).newJobForm, onSaved: { job in
                    book(quote, with: job)
                })
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        .sensoryFeedback(.success, trigger: changed)
    }

    private var emptyText: String {
        searchText.isEmpty ? "No \(filter.rawValue.lowercased()) quotes." : "No matching quotes."
    }

    private var lostMatches: [Quote] { QuoteList.shown(filtered, status: .lost) }

    private var deleteQuestion: String {
        "Delete the quote for \(quoteToDelete?.customer?.name ?? "this customer")?"
    }

    /// In the Booked list every row is booked, so the pill is left off there.
    private func row(_ quote: Quote, showStatus: Bool = false) -> some View {
        QuoteRow(quote: quote, showStatus: showStatus)
            .tag(quote)
            .contextMenu { contextMenu(for: quote) }
    }

    @ViewBuilder
    private func contextMenu(for quote: Quote) -> some View {
        if quote.status == .open {
            Button("Book Job") {
                quoteToBook = quote
            }
            Button("Mark Lost…") {
                quoteToLose = quote
            }
        } else {
            Button("Reopen") {
                reopen(quote)
            }
        }
        Divider()
        Button("Delete Quote…", role: .destructive) {
            quoteToDelete = quote
        }
    }

    private func markLost(_ quote: Quote) {
        quote.markLost()
        try? context.save()
        changed += 1
        showNotice("Quote marked lost.")
    }

    private func reopen(_ quote: Quote) {
        quote.reopen()
        try? context.save()
        changed += 1
        showNotice("Quote reopened.")
    }

    /// The New Job form opened by Book Job was saved. It gives its own haptic.
    private func book(_ quote: Quote, with job: Job) {
        quote.markBooked(with: job)
        try? context.save()
        showNotice("Job saved.")
    }

    /// Clears the selection first, so the detail column never shows a
    /// deleted quote.
    private func delete(_ quote: Quote) {
        if selection == quote { selection = nil }
        context.delete(quote)
        try? context.save()
    }

    private func showNotice(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if notice == text { notice = nil }
        }
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
                    CustomerRow(customer: customer)
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

/// Right-click menu for a job row. Delete asks first (`confirmJobDelete`).
struct JobContextMenu: View {
    @Environment(\.modelContext) private var context
    let job: Job
    /// Called by Delete Job; the list shows the confirmation.
    var onDelete: (Job) -> Void

    var body: some View {
        Button(job.isDone ? "Mark Not Done" : "Mark Done") {
            job.isDone.toggle()
            job.updatedAt = Date()
            try? context.save()
            CalendarStore.shared.jobSaved(job)
        }
        Button(job.isPaid ? "Mark Unpaid" : "Mark Paid") {
            job.isPaid.toggle()
            job.updatedAt = Date()
            try? context.save()
            CalendarStore.shared.jobSaved(job)
        }
        Divider()
        Button("Delete Job…", role: .destructive) {
            onDelete(job)
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
                    case .calendars:
                        ShowCalendarsView()
                    }
                }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
/// "Delete Linda Johnson's job on Mon, Oct 19?" before a right-click
/// delete, the same as every other delete in the app.
struct ConfirmJobDelete: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var job: Job?
    /// Clears the selection when it was the deleted job.
    var onDeleted: (Job) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(question, isPresented: Binding(
            get: { job != nil },
            set: { if !$0 { job = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Job", role: .destructive) {
                if let job {
                    onDeleted(job)
                    job.remove(from: context)
                }
                job = nil
            }
        }
    }

    private var question: String {
        guard let job else { return "Delete this job?" }
        let who = job.customer.map { $0.name + "'s" } ?? "this"
        return "Delete \(who) \(job.jobType.rawValue.lowercased()) on \(Dates.shortDay(job.scheduledAt))?"
    }
}

extension View {
    func confirmJobDelete(_ job: Binding<Job?>, onDeleted: @escaping (Job) -> Void) -> some View {
        modifier(ConfirmJobDelete(job: job, onDeleted: onDeleted))
    }
}
#endif
