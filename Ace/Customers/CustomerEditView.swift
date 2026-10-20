import SwiftData
import SwiftUI

/// Add or edit a customer. Presented as a sheet.
struct CustomerEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let customer: Customer?
    /// Called with the saved customer, so a picker can select it.
    var onSave: ((Customer) -> Void)? = nil
    /// Called when the customer was deleted, so the screen behind can close.
    var onDelete: (() -> Void)? = nil

    @State private var form: CustomerFormData
    @State private var confirmDelete = false
    @State private var saved = false

    init(customer: Customer?, onSave: ((Customer) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.customer = customer
        self.onSave = onSave
        self.onDelete = onDelete
        _form = State(initialValue: CustomerFormData(customer: customer))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $form.name, prompt: Text("Full name or business"))
                TextField("Phone", text: $form.phone, prompt: Text("508-555-0123"))
                    .phoneKeyboard()
                TextField("Address", text: $form.address, prompt: Text("Street and town"), axis: .vertical)
            }
            Section("Notes") {
                TextEditor(text: $form.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }
            if customer != nil {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete customer", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(customer == nil ? "New customer" : "Edit customer")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!form.isValid)
            }
        }
        .confirmationDialog("Delete this customer? Their jobs are kept without a customer.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .sensoryFeedback(.success, trigger: saved)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private func save() {
        let target: Customer
        if let customer {
            target = customer
        } else {
            target = Customer(name: form.name)
            context.insert(target)
        }
        form.apply(to: target)
        try? context.save()
        CalendarStore.shared.customerSaved(target)
        saved.toggle()
        onSave?(target)
        dismiss()
    }

    private func delete() {
        if let customer {
            customer.remove(from: context)
            onDelete?()
        }
        dismiss()
    }
}
