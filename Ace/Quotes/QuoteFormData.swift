import Foundation

/// What the quote form edits. Copied out of a Quote for editing and written
/// back on Save, so a cancelled edit changes nothing. The status is not part
/// of it: Book Job, Mark Lost and Reopen change the quote directly.
struct QuoteFormData {
    var customer: Customer?
    var jobType: JobType = .junkRemoval
    var details = ""
    var priceText = ""
    var quotedOn: Date = Dates.startOfToday()
    var hasFollowUp = false
    /// Used only when `hasFollowUp` is on. Starts three days out.
    var followUpOn: Date = QuoteFormData.defaultFollowUp()
    var notes = ""

    init() {}

    init(quote: Quote?) {
        guard let quote else { return }
        customer = quote.customer
        jobType = quote.jobType
        details = quote.details
        priceText = Parse.moneyText(quote.price)
        quotedOn = quote.quotedOn
        if let followUp = quote.followUpOn {
            hasFollowUp = true
            followUpOn = followUp
        }
        notes = quote.notes
    }

    static func defaultFollowUp() -> Date {
        let today = Dates.startOfToday()
        return Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today
    }

    func apply(to quote: Quote) {
        let calendar = Calendar.current
        quote.customer = customer
        quote.jobType = jobType
        quote.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        quote.price = Parse.money(priceText)
        quote.quotedOn = calendar.startOfDay(for: quotedOn)
        quote.followUpOn = hasFollowUp ? calendar.startOfDay(for: followUpOn) : nil
        quote.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        quote.updatedAt = Date()
    }

    /// The New Job form filled in from this quote: the customer, the type,
    /// the price, and what was quoted as the job's notes. The date is the
    /// New Job form's usual default.
    var newJobForm: JobFormData {
        var job = JobFormData()
        job.customer = customer
        job.jobType = jobType
        job.priceText = Parse.moneyText(Parse.money(priceText))
        job.notes = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return job
    }
}
