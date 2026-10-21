import SwiftUI

/// The top of the Calendar on today, iPhone and Mac: four tiles instead of
/// lines of text. Today's open jobs and what they are worth, what is owed,
/// dumpsters that need attention, and open quotes.
struct TodayFigures: View {
    let jobs: [Job]
    let dumpsters: [Dumpster]
    let quotes: [Quote]
    /// iPhone: tapping Quotes opens the Quotes tab.
    var onShowQuotes: (() -> Void)? = nil
    /// Two rows of two, or one row of four on the wide Mac board.
    var columns = 2

    private var calendar: Calendar { .current }

    private var todaysOpenJobs: [Job] { jobs.filter { calendar.isDateInToday($0.scheduledAt) && !$0.isDone } }
    private var owedJobs: [Job] { jobs.filter { $0.owedAmount > 0 } }
    private var owedTotal: Double { owedJobs.reduce(0) { $0 + $1.owedAmount } }
    private var overdue: [Dumpster] { dumpsters.filter { $0.status() == .overdue } }
    private var dueToday: [Dumpster] { dumpsters.filter { $0.status() == .dueToday } }
    private var openQuotes: [Quote] { quotes.filter { $0.status == .open } }

    var body: some View {
        StatGrid(columns: columns) {
            StatTile(
                title: "Today",
                value: Plural.text(todaysOpenJobs.count, "job"),
                detail: todaysOpenJobs.priceTotal > 0 ? Money.text(todaysOpenJobs.priceTotal) + " booked" : "Nothing priced"
            )
            StatTile(
                title: "Owed",
                value: Money.text(owedTotal),
                detail: owedJobs.isEmpty ? "All paid" : "from " + Plural.text(owedJobs.count, "job"),
                tint: owedTotal > 0 ? Tint.owed : .primary
            )
            StatTile(
                title: "Dumpsters",
                value: dumpsterValue,
                detail: dumpsterDetail,
                tint: !overdue.isEmpty ? Tint.overdue : (!dueToday.isEmpty ? Tint.owed : .primary)
            )
            if let onShowQuotes {
                Button(action: onShowQuotes) {
                    quotesTile
                }
                .buttonStyle(.plain)
            } else {
                quotesTile
            }
        }
    }

    private var quotesTile: some View {
        StatTile(title: "Quotes", value: "\(openQuotes.count) open", detail: openQuotesDetail)
    }

    /// Leads with what needs doing: "1 overdue", "2 due today", else "3 of 6 out".
    private var dumpsterValue: String {
        if !overdue.isEmpty { return "\(overdue.count) overdue" }
        if !dueToday.isEmpty { return "\(dueToday.count) due today" }
        return outText
    }

    private var dumpsterDetail: String {
        var parts: [String] = []
        if !overdue.isEmpty || !dueToday.isEmpty { parts.append(outText) }
        if !overdue.isEmpty && !dueToday.isEmpty { parts.append("\(dueToday.count) due today") }
        return parts.isEmpty ? "None due back today" : parts.joined(separator: ", ")
    }

    private var outText: String {
        "\(dumpsters.filter(\.isOut).count) of \(dumpsters.count) out"
    }

    private var openQuotesDetail: String {
        let total = openQuotes.reduce(0) { $0 + ($1.price ?? 0) }
        if openQuotes.isEmpty { return "None waiting" }
        return total > 0 ? Money.text(total) + " waiting" : "None priced"
    }
}
