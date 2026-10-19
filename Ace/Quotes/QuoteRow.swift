import SwiftUI

/// One quote in a list: who, what and for how much, when it was quoted and
/// when to call back. A follow-up that is due shows in the warning colour.
struct QuoteRow: View {
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quote.customer?.name ?? "No customer")
                .font(.headline)
            Text(quote.typeAndPriceText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(quote.datesText())
                .font(.footnote)
                .foregroundStyle(quote.isFollowUpDue() ? Color.orange : Color.secondary)
            if !quote.details.isEmpty {
                Text(quote.details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
