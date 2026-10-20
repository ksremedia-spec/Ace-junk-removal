import SwiftUI

/// One job in a list: its type badge, who, what and when, and on the right
/// the price with Done / Paid / Unpaid pills. Done work is not crossed out
/// (Kyle, 2026-10-19: crossed-out names read as cancelled); its badge goes
/// grey instead.
struct JobRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let job: Job
    var showDate = true
    /// False on a customer's own page, where every row is theirs: the job
    /// type leads instead of the name.
    var showCustomer = true
    /// The list this row is in. Unpaid and Done lists leave out the pills
    /// that only repeat the list's own name, which gave the date and address
    /// their room back; Unpaid shows how long the money has been owed.
    var context: JobsFilter? = nil

    /// At the largest text sizes the price and pills go under the details
    /// instead of squeezing them (the price wrapped as "$3 / 00").
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.m))
    }

    var body: some View {
        layout {
            TypeBadge(type: job.jobType, muted: job.isDone)
            VStack(alignment: .leading, spacing: 2) {
                Text(showCustomer ? (job.customer?.name ?? "No customer") : job.jobType.rawValue)
                    .font(.body.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(showCustomer ? whenLine : job.whenText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if showCustomer, let address = job.customer?.address, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Space.s)
            }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Space.xs) {
                if !job.priceText.isEmpty {
                    Text(job.priceText)
                        .font(.body.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(job.isPaid ? .secondary : .primary)
                }
                switch context {
                case .unpaid:
                    Text(owedForText)
                        .font(.caption.weight(.medium))
                        .rowTint(Tint.owed)
                case .done:
                    JobPills(job: job, showDone: false)
                default:
                    JobPills(job: job)
                }
            }
        }
        .padding(.vertical, Space.xs + 1)
        .accessibilityElement(children: .combine)
    }

    /// "Today", "1 day", "12 days" since the job's day: how long it has been
    /// owed, for the Unpaid list.
    private var owedForText: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: job.scheduledAt), to: Dates.startOfToday()).day ?? 0
        return days <= 0 ? "Today" : Plural.text(days, "day")
    }

    /// "Fri, Oct 24, 9:00 to 11:00 AM · Junk removal", or without the day
    /// ("9:00 to 11:00 AM · Junk removal") in a list already grouped by day.
    /// The time comes first: on a narrow phone the end gets cut, and the
    /// badge already says the type.
    private var whenLine: String {
        if showDate { return job.whenText + " · " + job.jobType.rawValue }
        guard job.hasTime else { return job.jobType.rawValue }
        return job.timeRangeText + " · " + job.jobType.rawValue
    }
}
