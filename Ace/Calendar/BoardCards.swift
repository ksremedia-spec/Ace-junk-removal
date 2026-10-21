import SwiftUI

// The pieces the Calendar, Dumpsters and Labor pages are built from, on the
// iPhone and the Mac alike (Kyle, Oct 20: "bright cards" and the week
// board): job cards tinted by the kind of work, small cards for dumpster
// comings and goings and other calendars' events, dumpster tiles in their
// status colour, and titled cards holding a short list.

/// A job on the board: time, who, and what, tinted by the kind of work.
struct JobCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let job: Job
    let isSelected: Bool

    private var timeText: String {
        job.hasTime ? JobTimes.text(start: job.scheduledAt, end: nil) : "Any time"
    }

    private var detail: String {
        var parts = [job.jobType.rawValue]
        if let price = job.price { parts.append(Money.text(price)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let tint = job.jobType.tint
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(timeText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(job.isDone ? .secondary : tint)
                Spacer(minLength: 0)
                // Owed comes first: a done job that is not paid still needs
                // the money (it is always done, so it never showed before).
                if job.owedAmount > 0 {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Tint.owed)
                } else if job.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(job.customer?.name ?? "No customer")
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(job.isDone ? .secondary : .primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Wraps at the largest text sizes so the price is not cut.
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(job.isDone ? 0.06 : (isSelected ? 0.30 : 0.14)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// A dumpster drop-off or due-back, or another calendar's event, on the board.
struct SmallCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : tint.opacity(0.35), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// One dumpster: its number big, its status, and who has it or that it is
/// in the yard. Also the Mac Dumpsters screen's grid.
struct DumpsterTile: View {
    let dumpster: Dumpster
    let isSelected: Bool
    /// The Dumpsters page also shows the address it is at.
    var showsPlace = false

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Grows with the text, so at large sizes it is not the smallest thing
    /// on the tile.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 30

    private var status: Dumpster.Status { dumpster.status() }
    /// Detail lines a shade darker than the usual grey, for sunlight on a
    /// tinted tile (Oct 20 phone audit).
    private var detailColor: Color { Color.primary.opacity(0.7) }
    private var lines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    /// "3 days late", "Due today", "Back Sat, Oct 24", "In the yard".
    private var whenText: String {
        switch status {
        case .inYard:
            return "In the yard"
        case .dueToday:
            return "Due back today"
        case .overdue:
            guard let due = dumpster.dueBackAt else { return "Overdue" }
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: due),
                                                       to: Dates.startOfToday()).day ?? 0
            return Plural.text(max(days, 1), "day") + " late"
        case .out:
            guard let due = dumpster.dueBackAt else { return "Out" }
            return "Back " + Dates.shortDay(due)
        }
    }

    /// "Out 5 days · $450 · 2 tons"
    private var rentalText: String {
        var parts: [String] = []
        if let dropped = dumpster.droppedOffAt {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: dropped),
                                                       to: Dates.startOfToday()).day ?? 0
            parts.append(days <= 0 ? "Out since today" : "Out " + Plural.text(days, "day"))
        }
        if let price = dumpster.price { parts.append(Money.text(price)) }
        if let tons = dumpster.agreedWeightTons { parts.append(Tons.text(tons)) }
        return parts.joined(separator: " · ")
    }

    private var whoText: String {
        if dumpster.isOut { return dumpster.customer?.name ?? (dumpster.location.isEmpty ? "No customer" : dumpster.location) }
        return dumpster.label
    }

    var body: some View {
        let tint = status.tint
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(dumpster.number)")
                    .font(.system(size: min(numberSize, 56), weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if dumpster.isOut, !dumpster.label.isEmpty {
                    Text(dumpster.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(whenText)
                .font(.callout.weight(.semibold))
                .foregroundStyle(status == .inYard || status == .out ? Color.primary : tint)
            Text(whoText)
                .font(.caption)
                .foregroundStyle(dumpster.isOut ? Color.primary : detailColor)
                .lineLimit(lines)
            if showsPlace, dumpster.isOut {
                if !dumpster.location.isEmpty {
                    Text(dumpster.location)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .lineLimit(lines)
                }
                if !rentalText.isEmpty {
                    Text(rentalText)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .monospacedDigit()
                        .lineLimit(lines)
                        .padding(.top, 2)
                }
            }
            // "Cracked door, don't send out" shows where it is seen.
            if !dumpster.conditionNote.isEmpty {
                Label(dumpster.conditionNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tint.owed)
                    .lineLimit(lines)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: showsPlace ? 124 : 92, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(isSelected ? 0.28 : 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dumpster \(dumpster.number), \(whenText), \(whoText)")
    }
}

// MARK: - Lists in cards

/// A titled white card holding a short list.
struct BoardListCard<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("\(count)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.xs)
            content
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

/// A clickable row inside a board card, highlighted when chosen.
struct BoardRow<Label: View>: View {
    let isSelected: Bool
    @ViewBuilder var label: Label
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Space.s)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.05) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
