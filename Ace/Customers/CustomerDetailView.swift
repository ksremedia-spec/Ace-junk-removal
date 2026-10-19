import SwiftData
import SwiftUI

/// One customer: contact details and their jobs.
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

    private var phoneURL: URL? {
        let digits = customer.phoneDigits
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Phone") {
                    if let phoneURL {
                        Link(customer.phone, destination: phoneURL)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Address") {
                    Text(customer.address.isEmpty ? "—" : customer.address)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(customer.address.isEmpty ? .secondary : .primary)
                }
                if !customer.notes.isEmpty {
                    Text(customer.notes)
                }
            }

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
                JobEditView(job: nil, prefill: newJobPrefill)
            }
        }
    }

    private var newJobPrefill: JobFormData {
        var form = JobFormData()
        form.customer = customer
        return form
    }
}
