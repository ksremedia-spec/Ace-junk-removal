import SwiftUI

extension Dumpster.Status {
    var tint: Color {
        switch self {
        case .overdue: return Tint.overdue
        case .dueToday: return Tint.owed
        case .out: return .indigo
        case .inYard: return Tint.paid
        }
    }
}

/// A dumpster's number in a rounded square of its status colour.
struct DumpsterBadge: View {
    let dumpster: Dumpster
    var size: CGFloat = 30

    var body: some View {
        Text("\(dumpster.number)")
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(dumpster.status().tint)
            )
            .accessibilityHidden(true)
    }
}

/// One dumpster in a list: number, status, where it is and when it is due.
struct DumpsterRow: View {
    let dumpster: Dumpster

    private var status: Dumpster.Status { dumpster.status() }

    /// "15 yard · Harborview Realty", "15 yard", or the customer alone.
    private var subtitle: String {
        var parts: [String] = []
        if !dumpster.label.isEmpty { parts.append(dumpster.label) }
        if dumpster.isOut { parts.append(dumpster.customer?.name ?? "No customer") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.m) {
            DumpsterBadge(dumpster: dumpster)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dumpster \(dumpster.number)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if dumpster.isOut {
                    if !dumpster.location.isEmpty {
                        Text(dumpster.location)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !dumpster.conditionNote.isEmpty {
                    Label(dumpster.conditionNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .rowTint(Tint.owed)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.xs) {
                StatusPill(text: status.rawValue, tint: status.tint)
                if dumpster.isOut, let dueBackAt = dumpster.dueBackAt {
                    Text("Back " + Dates.shortDay(dueBackAt))
                        .font(.caption)
                        .rowTint(status == .out ? .secondary : status.tint)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}
