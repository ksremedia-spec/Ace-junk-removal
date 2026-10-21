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
    /// The form as opened, to tell whether Cancel would lose typing.
    @State private var original: CustomerFormData
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var saved = false

    /// `prefill`: a new customer started from a search ("Souza" or a phone
    /// number), so it is not typed twice.
    init(customer: Customer?, prefill: CustomerFormData? = nil, onSave: ((Customer) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.customer = customer
        self.onSave = onSave
        self.onDelete = onDelete
        let start = prefill ?? CustomerFormData(customer: customer)
        _form = State(initialValue: start)
        _original = State(initialValue: CustomerFormData(customer: customer))
    }

    private var hasChanges: Bool { form != original }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $form.name, prompt: Text("Full name or business"))
                    .wordsCapitalized()
                TextField("Phone", text: $form.phone, prompt: Text("Phone number"))
                    .phoneKeyboard()
                TextField("Address", text: $form.address, prompt: Text("Street and town"), axis: .vertical)
                    .wordsCapitalized()
            } footer: {
                if let problem = PhoneFormat.problem(form.phone) {
                    Text(problem)
                        .foregroundStyle(Tint.owed)
                }
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
                Button("Cancel") {
                    if hasChanges { confirmDiscard = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!form.isValid)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(customer == nil ? "Discard this customer?" : "Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
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
