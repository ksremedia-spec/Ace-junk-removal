import SwiftData
import SwiftUI

// Pieces shared by the Assistant's confirmation screens, and the screen
// for cancelling a job. Customer screens are in AssistantCustomerViews.swift,
// dumpster screens in AssistantDumpsterViews.swift.

// MARK: - Choosing one

/// "Which job?" when several jobs fit the note.
struct WhichJobList: View {
    let jobs: [Job]
    var onPick: (Job) -> Void
    var onStartOver: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(jobs) { job in
                    Button {
                        onPick(job)
                    } label: {
                        Text(Self.rowText(for: job))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Which job?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }

    /// "Linda Johnson · Junk removal · Mon, Oct 19 at 9:00 AM"
    static func rowText(for job: Job) -> String {
        [job.customer?.name ?? "No customer", job.jobType.rawValue, job.whenText].joined(separator: " · ")
    }
}

/// "Which customer?" when several customers fit the note.
struct WhichCustomerList: View {
    let customers: [Customer]
    var onPick: (Customer) -> Void
    var onStartOver: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(customers) { customer in
                    Button {
                        onPick(customer)
                    } label: {
                        CustomerSummaryRow(customer: customer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Which customer?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }
}

/// Name, with phone and address underneath.
private struct CustomerSummaryRow: View {
    let customer: Customer

    private var details: String {
        [customer.phone, customer.address].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(customer.name)
                .foregroundStyle(.primary)
            if !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// "Which dumpster?" when several dumpsters fit the note.
struct WhichDumpsterList: View {
    let dumpsters: [Dumpster]
    var onPick: (Dumpster) -> Void
    var onStartOver: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(dumpsters) { dumpster in
                    Button {
                        onPick(dumpster)
                    } label: {
                        DumpsterRow(dumpster: dumpster)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which dumpster?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }
}

// MARK: - Nothing found

/// "No customer found for Smith." with Skip, which moves on to the next
/// step (or closes when this was the last).
struct NothingFoundView: View {
    let message: String
    var footer: String = ""
    var onSkip: () -> Void
    var onStartOver: () -> Void

    var body: some View {
        Form {
            Section {
                Text(message)
            } footer: {
                if !footer.isEmpty {
                    Text(footer)
                }
            }
            Section {
                Button("Skip") { onSkip() }
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Job details

/// The job as it stands, read-only. `note` flags the customer row when it
/// is unclear which job was meant.
struct JobDetailsSection: View {
    let job: Job
    var note: String? = nil

    var body: some View {
        Section("Job") {
            FlaggedRow(note) {
                LabeledContent("Customer", value: job.customer?.name ?? "No customer")
            }
            LabeledContent("Type", value: job.jobType.rawValue)
            LabeledContent("Scheduled", value: job.whenText)
            if !job.priceText.isEmpty {
                LabeledContent("Price", value: job.priceText + (job.isPaid ? ", paid" : ", unpaid"))
            }
            if job.isDone {
                LabeledContent("Status", value: "Done")
            }
            if let address = job.customer?.address, !address.isEmpty {
                LabeledContent("Address") {
                    Text(address)
                        .multilineTextAlignment(.trailing)
                }
            }
            if !job.notes.isEmpty {
                Text(job.notes)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Cancel a job

/// "Cancel the Johnson job." Finds the job, shows it, and deletes it after
/// a confirmation. Deleting is how a job is cancelled; there is no
/// cancelled state.
struct CancelJobView: View {
    let candidates: [Job]
    let subject: String
    let issues: [PlanIssue]
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Job?

    private var job: Job? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let job {
            CancelJobForm(
                job: job,
                flags: AssistantFlags(issues: issues),
                onDeleted: { onFinish("Job deleted.") },
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            NothingFoundView(message: "No job found for \(subject).", onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichJobList(jobs: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }
}

private struct CancelJobForm: View {
    @Environment(\.modelContext) private var context

    let job: Job
    let flags: AssistantFlags
    var onDeleted: () -> Void
    var onStartOver: () -> Void

    @State private var confirming = false
    @State private var deleted = false
    @State private var flagged = 0

    var body: some View {
        Form {
            JobDetailsSection(job: job, note: flags["ref"])
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Delete job", role: .destructive) { confirming = true }
            }
        }
        .confirmationDialog("Delete this job?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete job", role: .destructive) { delete() }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: deleted)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func delete() {
        JobActions.shared.forget(job)
        job.remove(from: context)
        deleted.toggle()
        onDeleted()
    }
}
