import SwiftData
import SwiftUI

/// One customer: contact details, the business done with them, their
/// dumpster rentals and their jobs.
struct CustomerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let customer: Customer
    /// On the Mac the parent clears its selection; on iPhone this screen pops.
    var onDeleted: (() -> Void)? = nil

    @State private var showingEdit = false
    @State private var showingNewJob = false
    @State private var deleted = false

    private var jobsNewestFirst: [Job] {
        customer.jobs.sorted { $0.scheduledAt > $1.scheduledAt }
    }

    private var dumpstersOut: [Dumpster] { customer.dumpstersOut }
    private var rentals: [RentalRecord] { customer.rentalsNewestFirst }

    var body: some View {
        List {
            Section {
                header
                    .bareRow()
                figures
                    .bareRow()
                    .padding(.bottom, Space.s)
            }
            if !customer.notes.isEmpty {
                Section("Notes") {
                    Text(customer.notes)
                }
            }
            if !dumpstersOut.isEmpty || !rentals.isEmpty {
                rentalsSection
            }
            jobsSection
        }
        .readableWidth()
        .navigationTitle(customer.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: {
            guard deleted else { return }
            if let onDeleted { onDeleted() } else { dismiss() }
        }) {
            NavigationStack {
                CustomerEditView(customer: customer, onDelete: { deleted = true })
            }
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil, prefill: JobFormData(customer: customer))
            }
        }
    }

    // MARK: Sections

    /// Initials, name, since when, phone and address, and the ways to reach
    /// them.
    private var header: some View {
        DetailHeader(
            title: customer.name,
            subtitle: [customer.phone, sinceText].filter { !$0.isEmpty }.joined(separator: " · "),
            caption: customer.address.isEmpty ? nil : customer.address
        ) {
            Avatar(name: customer.name, size: 52)
        } pills: {
            if customer.amountOwed > 0 {
                StatusPill(text: "Owes " + Money.text(customer.amountOwed), tint: Tint.owed)
            }
        } actions: {
            if let url = customer.phoneURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.action())
            }
            if let url = customer.directionsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Directions", systemImage: "map.fill")
                }
                .buttonStyle(.action())
            }
            Button {
                showingNewJob = true
            } label: {
                Label("New job", systemImage: "plus")
            }
            .buttonStyle(.action(.accentColor, prominent: true))
        }
    }

    /// How much work, how much billed, and what is owed.
    private var figures: some View {
        StatGrid(columns: 3) {
            StatTile(title: "Jobs", value: "\(customer.jobs.count)", detail: jobsDetail)
            StatTile(title: "Billed", value: Money.text(customer.totalBilled),
                     detail: billedDetail)
            StatTile(title: "Owed", value: Money.text(customer.amountOwed),
                     detail: customer.amountOwed > 0 ? "Not paid yet" : (customer.jobs.isEmpty ? "Nothing yet" : "All paid"),
                     tint: customer.amountOwed > 0 ? Tint.owed : .primary)
        }
    }

    /// "Next Tue, Oct 20" when work is booked, else "Last Sun, Nov 8, 2024".
    private var jobsDetail: String {
        if let next = customer.nextJobDate { return "Next " + Dates.shortDay(next) }
        if let last = customer.lastJobDate { return "Last " + Dates.shortDay(last) }
        return "None yet"
    }

    /// "$275 a job" over done, priced work, or "Has a dumpster now" while
    /// one is out with them.
    private var billedDetail: String {
        if !dumpstersOut.isEmpty { return "Has a dumpster now" }
        let priced = customer.jobs.filter { $0.isDone && $0.price != nil }
        guard !priced.isEmpty else { return "Nothing priced" }
        return Money.text(customer.totalBilled / Double(priced.count)) + " a job"
    }

    private var sinceText: String {
        if let first = customer.firstJobDate {
            return "Customer since " + Dates.monthYear(first)
        }
        return "New customer"
    }

    /// The dumpster out with them now, if any, then past rentals, newest first.
    private var rentalsSection: some View {
        Section("Dumpster rentals") {
            ForEach(dumpstersOut) { dumpster in
                VStack(alignment: .leading, spacing: 3) {
                    Text(dumpster.displayName)
                        .font(.headline)
                    Text(dumpster.currentRentalLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(rentals) { record in
                Text(record.customerLine)
                    .font(.subheadline)
            }
        }
    }

    private var jobsSection: some View {
        Section("Jobs") {
            if jobsNewestFirst.isEmpty {
                Text("No jobs yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(jobsNewestFirst) { job in
                NavigationLink {
                    JobEditView(job: job)
                } label: {
                    JobRow(job: job, showCustomer: false)
                }
            }
            Button {
                showingNewJob = true
            } label: {
                Label("New job for \(customer.name)", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}
