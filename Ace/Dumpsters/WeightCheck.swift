import SwiftUI

/// A weight over 15 tons is almost surely a slip, "28" typed or said for
/// 2.8: no dumpster Ace rents holds that much, and at $125 a ton the slip
/// would add thousands to the bill. Every place a pickup weight is saved
/// asks first (audit Oct 21, fix-now 13).
enum WeightCheck {
    static let limit: Double = 15

    /// The weight probably meant (28 → 2.8), or nil when the weight looks
    /// right.
    static func suggestion(for tons: Double?) -> Double? {
        guard let tons, tons > limit else { return nil }
        return (tons / 10 * 100).rounded() / 100
    }

    /// The short warning under the weight box, or nil.
    static func note(for tons: Double?) -> String? {
        guard let tons, suggestion(for: tons) != nil else { return nil }
        return "\(Tons.text(tons)) is more than a dumpster holds. Check the weight."
    }
}

extension View {
    /// "28 tons is more than a dumpster holds. Was it 2.8 tons?" with a
    /// button for each weight. `onChoose` gets the weight to save.
    func heavyWeightQuestion(isPresented: Binding<Bool>, tons: Double?, onChoose: @escaping (Double) -> Void) -> some View {
        let suggested = WeightCheck.suggestion(for: tons)
        let title = if let tons, let suggested {
            "\(Tons.text(tons)) is more than a dumpster holds. Was it \(Tons.text(suggested))?"
        } else {
            "Check the weight."
        }
        return confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            if let tons, let suggested {
                Button("Save as \(Tons.text(suggested))") { onChoose(suggested) }
                Button("Save as \(Tons.text(tons))") { onChoose(tons) }
            }
            Button("Change the weight", role: .cancel) {}
        }
    }
}
