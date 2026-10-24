import SwiftUI

/// "Updated 2 minutes ago", quietly, at the foot of the iPhone Calendar and
/// the Mac sidebar (audit Oct 21, design idea 4). Nothing when sync is off.
struct SyncFootnote: View {
    @State private var sync = SyncEngine.shared

    var body: some View {
        if sync.isSetUp {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var text: String {
        switch sync.status {
        case .offline: return "Offline. Changes are kept and sent later."
        case .sending: return "Syncing…"
        default:
            guard let last = sync.lastSynced else { return "Not synced yet" }
            if Date().timeIntervalSince(last) < 60 { return "Updated just now" }
            return "Updated " + last.formatted(.relative(presentation: .named))
        }
    }
}

/// Long-press menu on a dumpster tile: the things Alex does from the truck
/// without opening the page (audit Oct 21, design idea 6).
struct DumpsterQuickMenu: View {
    @Environment(\.modelContext) private var context
    let dumpster: Dumpster

    var body: some View {
        if dumpster.isOut {
            if let url = dumpster.customer?.phoneURL {
                Link(destination: url) { Label("Call \(dumpster.customer?.name ?? "the renter")", systemImage: "phone") }
            }
            if let url = Maps.directions(to: dumpster.location.isEmpty ? (dumpster.customer?.address ?? "") : dumpster.location) {
                Link(destination: url) { Label("Directions", systemImage: "map") }
            }
            Divider()
            Button { extend(by: 3) } label: { Label("Extend 3 days", systemImage: "calendar.badge.plus") }
            Button { extend(by: 7) } label: { Label("Extend 1 week", systemImage: "calendar.badge.plus") }
        }
    }

    private func extend(by days: Int) {
        // From today when it's already overdue, so Extend never leaves it
        // overdue (audit Oct 24, 71).
        let today = Dates.startOfToday()
        let from = max(dumpster.dueBackAt.map { Calendar.current.startOfDay(for: $0) } ?? today, today)
        dumpster.dueBackAt = Calendar.current.date(byAdding: .day, value: days, to: from)
        dumpster.updatedAt = Date()
        try? context.save()
    }
}
