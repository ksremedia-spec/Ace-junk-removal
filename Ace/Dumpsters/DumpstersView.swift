import SwiftData
import SwiftUI

/// The six dumpsters and where each one is.
struct DumpstersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]

    private var outCount: Int { dumpsters.filter(\.isOut).count }

    var body: some View {
        List {
            if dumpsters.isEmpty {
                Section {
                    Text("No dumpsters set up yet.")
                        .foregroundStyle(.secondary)
                    Button("Set up 6 dumpsters") {
                        for number in 1...6 {
                            context.insert(Dumpster(number: number))
                        }
                        try? context.save()
                    }
                }
            } else {
                Section("\(outCount) out · \(dumpsters.count - outCount) in the yard") {
                    ForEach(dumpsters) { dumpster in
                        NavigationLink {
                            DumpsterDetailView(dumpster: dumpster)
                        } label: {
                            DumpsterRow(dumpster: dumpster)
                        }
                    }
                }
            }
        }
        .navigationTitle("Dumpsters")
    }
}
