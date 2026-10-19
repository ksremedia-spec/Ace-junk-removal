import SwiftData
import SwiftUI

/// Every customer, alphabetically, with search.
struct CustomersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var searchText = ""
    @State private var showingNew = false

    private var filtered: [Customer] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return customers }
        let digits = query.filter(\.isNumber)
        return customers.filter {
            $0.name.lowercased().contains(query)
                || $0.address.lowercased().contains(query)
                || (!digits.isEmpty && $0.phoneDigits.contains(digits))
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Text(customers.isEmpty ? "No customers yet." : "No matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(filtered) { customer in
                NavigationLink {
                    CustomerDetailView(customer: customer)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name)
                        if !customer.phone.isEmpty || !customer.address.isEmpty {
                            Text([customer.phone, customer.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(filtered[index])
                }
                try? context.save()
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $searchText, prompt: "Name, phone or address")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("New customer", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            NavigationStack {
                CustomerEditView(customer: nil)
            }
        }
    }
}
