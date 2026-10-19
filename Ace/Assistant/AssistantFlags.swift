import SwiftUI

/// Claude's issues keyed by field, with room for the gaps the app itself can
/// see. Field names are reduced to one spelling, so "customerName",
/// "customer_name" and "CustomerName" all find the same note.
struct AssistantFlags {
    private var notes: [String: String]

    init(draft: JobDraft) {
        notes = Dictionary(draft.issues.map { (Self.key($0.field), $0.question) }, uniquingKeysWith: { first, _ in first })
    }

    static func key(_ field: String) -> String {
        field.lowercased().filter { $0 != "_" && $0 != " " }
    }

    subscript(field: String) -> String? {
        notes[Self.key(field)]
    }

    /// Adds the app's own note for a field, unless Claude already asked about it.
    mutating func add(_ field: String, _ note: String) {
        let key = Self.key(field)
        if notes[key] == nil { notes[key] = note }
    }

    var isEmpty: Bool { notes.isEmpty }
}

/// A form row that turns the warning color when it needs attention, with the
/// short note underneath. Same look as the flagged fields on the job review.
struct FlaggedRow<Content: View>: View {
    let note: String?
    let content: Content

    init(_ note: String?, @ViewBuilder content: () -> Content) {
        self.note = note
        self.content = content()
    }

    var body: some View {
        if let note {
            content
                .foregroundStyle(Color.orange)
            Text(note)
                .font(.footnote)
                .foregroundStyle(.orange)
        } else {
            content
        }
    }
}
