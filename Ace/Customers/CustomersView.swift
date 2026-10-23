import SwiftData
import SwiftUI

/// Every customer, alphabetically, with search.
struct CustomersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var searchText = ""
    @State private var showingNew = false
    /// A customer swiped for deletion, waiting for the question.
    @State private var pendingDelete: Customer?

    private var filtered: [Customer] {
        let search = SearchText(searchText)
        guard !search.isEmpty else { return customers }
        return customers.filter { $0.matches(search) }
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
                    CustomerRow(customer: customer)
                }
                // Asks first, never on a full swipe (Oct 20 phone audit).
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDelete = customer
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .confirmationDialog("Delete this customer? Their jobs are kept without a customer.",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { customer in
            Button("Delete \(customer.name)", role: .destructive) {
                customer.remove(from: context)
                pendingDelete = nil
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $searchText, prompt: "Name, phone or address")
        .refreshable { await SyncEngine.shared.syncNow(manual: true) }
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
