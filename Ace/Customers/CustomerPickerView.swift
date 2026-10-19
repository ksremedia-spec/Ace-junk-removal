import SwiftData
import SwiftUI

/// Pick an existing customer or add a new one. Presented as a sheet.
struct CustomerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]

    @Binding var selection: Customer?
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
            Section {
                Button {
                    showingNew = true
                } label: {
                    Label("New customer", systemImage: "plus")
                }
            }
            Section {
                if filtered.isEmpty {
                    Text(customers.isEmpty ? "No customers yet." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { customer in
                    Button {
                        selection = customer
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(customer.name)
                                    .foregroundStyle(.primary)
                                if !customer.phone.isEmpty || !customer.address.isEmpty {
                                    Text([customer.phone, customer.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if selection?.persistentModelID == customer.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Customer")
        .searchable(text: $searchText, prompt: "Name, phone or address")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingNew) {
            NavigationStack {
                CustomerEditView(customer: nil) { created in
                    selection = created
                    dismiss()
                }
            }
        }
    }
}
