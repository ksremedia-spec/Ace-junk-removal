import Foundation

/// Where the work is. Jobs have no address of their own yet: a job said for
/// a known customer at another address (a realtor's listing, a landlord's
/// other house) keeps it as a first line "Job address: …" in the notes
/// (AssistantMatching, audit Oct 21 M9). The Next card, the day cards and
/// the job page use this, so Directions goes to the job, not the customer's
/// address on file (audit Oct 24, 39).
enum JobSite {
    /// The address from a leading "Job address: …" line; nil without one.
    static func address(inNotes notes: String) -> String? {
        let firstLine = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let label = "job address:"
        guard firstLine.lowercased().hasPrefix(label) else { return nil }
        let address = firstLine.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        return address.isEmpty ? nil : address
    }

    /// The job's own address from the notes, else the customer's address on
    /// file. Nil when there is neither.
    static func address(notes: String, customer: Customer?) -> String? {
        if let said = address(inNotes: notes) { return said }
        guard let onFile = customer?.address, !onFile.isEmpty else { return nil }
        return onFile
    }

    /// "15 Bay Road, Fall River": without the state and ZIP, like
    /// `Customer.shortAddress`.
    static func short(_ address: String) -> String {
        address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .prefix(2).joined(separator: ", ")
    }
}

extension Job {
    /// Where the work is: see `JobSite`.
    var siteAddress: String? {
        JobSite.address(notes: notes, customer: customer)
    }
}
