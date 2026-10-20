import SwiftUI

/// One customer in a list: their initials, name, phone and address, and
/// what they owe when it is anything.
struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: Space.m) {
            Avatar(name: customer.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if !customer.phone.isEmpty {
                    Text(customer.phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if !customer.address.isEmpty {
                    Text(customer.address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            if customer.amountOwed > 0 {
                StatusPill(text: "Owes " + Money.text(customer.amountOwed), tint: Tint.owed)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}
