import SwiftUI

/// One dumpster in a list: number, status, where it is and when it is due.
struct DumpsterRow: View {
    let dumpster: Dumpster

    private var status: Dumpster.Status { dumpster.status() }

    private var statusColor: Color {
        switch status {
        case .overdue: return .red
        case .dueToday: return .orange
        case .out: return .secondary
        case .inYard: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(dumpster.displayName)
                    .font(.headline)
                Spacer()
                Text(status.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }
            if dumpster.isOut {
                if let customer = dumpster.customer {
                    Text(customer.name)
                        .font(.subheadline)
                }
                if !dumpster.location.isEmpty {
                    Text(dumpster.location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let dueBackAt = dumpster.dueBackAt {
                    Text("Due back " + Dates.shortDay(dueBackAt))
                        .font(.footnote)
                        .foregroundStyle(status == .out ? .secondary : statusColor)
                }
            }
            if !dumpster.conditionNote.isEmpty {
                Text(dumpster.conditionNote)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
