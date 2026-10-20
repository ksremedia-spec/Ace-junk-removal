import SwiftUI

extension QuoteStatus {
    var tint: Color {
        switch self {
        case .open: return .accentColor
        case .booked: return Tint.paid
        case .lost: return .secondary
        }
    }
}

/// One quote in a list: its type badge, who and what was quoted, when, and
/// the price with a pill once it is booked or lost.
struct QuoteRow: View {
    let quote: Quote
    /// The Booked or Lost pill. Off in a list that is all one status.
    var showStatus = true

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            TypeBadge(type: quote.jobType, muted: quote.status != .open)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.customer?.name ?? "No customer")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(quote.details.isEmpty ? quote.jobType.rawValue : quote.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(quote.datesText())
                    .font(.footnote)
                    .rowTint(quote.isFollowUpDue() ? Tint.owed : Color.secondary)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(quote.price.map(Money.text) ?? "No price")
                    .font(.body.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(quote.price == nil ? .secondary : .primary)
                if showStatus && quote.status != .open {
                    StatusPill(text: quote.status.rawValue, tint: quote.status.tint)
                }
            }
        }
        .padding(.vertical, Space.xs + 1)
        .accessibilityElement(children: .combine)
    }
}
