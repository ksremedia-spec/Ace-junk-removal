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

    /// "2 overdue · 1 out · 3 in the yard"
    private var summary: String {
        let overdue = dumpsters.filter { $0.status() == .overdue }.count
        let dueToday = dumpsters.filter { $0.status() == .dueToday }.count
        let out = dumpsters.filter { $0.status() == .out }.count
        let yard = dumpsters.filter { !$0.isOut }.count
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if out > 0 { parts.append("\(out) out") }
        parts.append("\(yard) in the yard")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                if dumpsters.isEmpty {
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
    }
}
