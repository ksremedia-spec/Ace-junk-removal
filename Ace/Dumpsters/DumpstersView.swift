import SwiftData
import SwiftUI

/// The six dumpsters as tiles in their status colour, the same as the Mac
/// Dumpsters page (Kyle, Oct 20): how late, who has it, where, days out,
/// price and agreed weight. Tap one to drop it off, pick it up or see its
/// rentals.
struct DumpstersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "3 of 6 out · 1 overdue · 1 due today", or "6 in the yard". "1 out"
    /// next to an overdue one read as if only one was out (Oct 20 phone audit).
    private var summary: String {
        let out = dumpsters.filter(\.isOut).count
        guard out > 0 else { return "\(dumpsters.count) in the yard" }
        let overdue = dumpsters.filter { $0.status() == .overdue }.count
        let dueToday = dumpsters.filter { $0.status() == .dueToday }.count
        var parts = ["\(out) of \(dumpsters.count) out"]
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                if dumpsters.isEmpty && SyncEngine.shared.isWaitingForFirstSync {
                    // The real ones are on their way; blank ones set up now
                    // would only get in the way (audit Oct 21, M5).
                    Label("Getting the dumpsters from the other devices…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                } else if dumpsters.isEmpty {
                    Text("No dumpsters set up yet.")
                        .foregroundStyle(.secondary)
                    Button("Set up 6 dumpsters") {
                        for number in 1...6 {
                            context.insert(Dumpster(number: number))
                        }
                        try? context.save()
                    }
                    .buttonStyle(.action(.accentColor, prominent: true))
                } else {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    // One a row at the largest text sizes.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: typeSize.isAccessibilitySize ? 1 : 2),
                              spacing: Space.s) {
                        ForEach(dumpsters) { dumpster in
                            NavigationLink {
                                DumpsterDetailView(dumpster: dumpster)
                            } label: {
                                DumpsterTile(dumpster: dumpster, isSelected: false, showsPlace: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { DumpsterQuickMenu(dumpster: dumpster) }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .background(Tint.boardPage)
        .environment(\.cardFill, Tint.boardCard)
        .navigationTitle("Dumpsters")
        .refreshable { await SyncEngine.shared.syncNow(manual: true) }
    }
}
