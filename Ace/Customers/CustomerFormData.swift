import Foundation

struct CustomerFormData: Equatable {
    var name = ""
    var phone = ""
    var address = ""
    var notes = ""

    init() {}

    init(customer: Customer?) {
        guard let customer else { return }
        name = customer.name
        phone = customer.phone
        address = customer.address
        notes = customer.notes
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func apply(to customer: Customer) {
        customer.name = name.trimmingCharacters(in: .whitespaces)
        customer.phone = PhoneFormat.formatted(phone)
        customer.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        customer.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        customer.updatedAt = Date()
    }
}
