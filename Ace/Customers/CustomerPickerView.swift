import SwiftData
import SwiftUI

/// Pick an existing customer or add a new one. Presented as a sheet.
struct CustomerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]

    @Binding var selection: Customer?
    @State private var searchText = ""
    @State private var showingNew = false

    /// The chosen customer first, then everyone else (or the matches).
    private var filtered: [Customer] {
        let search = SearchText(searchText)
        let list = search.isEmpty ? customers : customers.filter { $0.matches(search) }
        guard let chosen = selection, list.contains(where: { $0.persistentModelID == chosen.persistentModelID }) else { return list }
        return [chosen] + list.filter { $0.persistentModelID != chosen.persistentModelID }
    }

    /// A new customer started from the search: a typed name or number is
    /// carried over instead of typed again.
    private var prefill: CustomerFormData? {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var form = CustomerFormData()
        if SearchText(text).phoneDigits != nil { form.phone = text } else { form.name = text }
        return form
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingNew = true
                } label: {
                    Label(prefill.map { "New customer \"\($0.name.isEmpty ? $0.phone : $0.name)\"" } ?? "New customer", systemImage: "plus")
                }
                .buttonStyle(.borderless)
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
                        .contentShape(Rectangle())
                    }
                    // Plain, so names read black and details grey, like a
                    // list, not a column of teal links.
                    .buttonStyle(.plain)
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
                CustomerEditView(customer: nil, prefill: prefill) { created in
                    selection = created
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}
