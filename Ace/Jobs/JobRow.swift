import SwiftUI

/// One job in a list: who, what, when, and the money line.
struct JobRow: View {
    let job: Job
    var showDate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(job.customer?.name ?? "No customer")
                    .font(.headline)
                    .strikethrough(job.isDone)
                Spacer()
                if !job.priceText.isEmpty {
                    Text(job.priceText)
                        .monospacedDigit()
                        .foregroundStyle(job.isPaid ? .secondary : .primary)
                }
            }
            Text(job.jobType.rawValue + (showDate ? " · " + job.whenText : (job.hasTime ? " · " + job.scheduledAt.formatted(date: .omitted, time: .shortened) : "")))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let address = job.customer?.address, !address.isEmpty {
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if job.isDone || job.isPaid {
                statusLine
            }
        }
        .padding(.vertical, 2)
    }

    /// "Done · Paid", "Done · Unpaid" (unpaid in the warning colour), or "Paid".
    private var statusLine: some View {
        HStack(spacing: 0) {
            if job.isDone {
                Text("Done · ")
            }
            if job.isPaid {
                Text("Paid")
            } else {
                Text("Unpaid")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
