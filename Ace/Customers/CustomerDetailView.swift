import SwiftData
import SwiftUI

/// One customer: contact details, the business done with them, their
/// dumpster rentals and their jobs.
struct CustomerDetailView: View {
    @Environment(\.dismiss) private var dismiss

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
            contactSection
            summarySection
            if !dumpstersOut.isEmpty || !rentals.isEmpty {
                rentalsSection
            }
            jobsSection
        }
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

    private var contactSection: some View {
        Section {
            LabeledContent("Phone") {
                if let url = customer.phoneURL {
                    Link(customer.phone, destination: url)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Address") {
                Text(customer.address.isEmpty ? "—" : customer.address)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(customer.address.isEmpty ? .secondary : .primary)
            }
            if let url = customer.directionsURL {
                Link(destination: url) {
                    Label("Directions", systemImage: "map")
                }
            }
            if !customer.notes.isEmpty {
                Text(customer.notes)
            }
        }
    }

    /// Since when, how much work, and whether anything is owed.
    private var summarySection: some View {
        Section {
            Text(sinceText)
            Text(Plural.text(customer.jobs.count, "job") + " · " + Money.text(customer.totalBilled))
            if customer.amountOwed > 0 {
                Text("Owed " + Money.text(customer.amountOwed))
                    .foregroundStyle(.orange)
            }
        }
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
                    JobRow(job: job)
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
