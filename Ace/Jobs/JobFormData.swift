import Foundation

/// What the job form edits. Copied out of a Job for editing and written back
/// on Save, so a cancelled edit changes nothing.
struct JobFormData {
    var customer: Customer?
    var jobType: JobType = .junkRemoval
    var date: Date = Dates.nextFullHour()
    var hasTime = true
    /// The job's own length in minutes. 0 follows the type's default, so the
    /// length tracks the type until it is picked by hand.
    var durationMinutes = 0
    var priceText = ""
    var paymentType: PaymentType = .unknown
    var isPaid = false
    var isDone = false
    var notes = ""

    init() {}

    /// A blank form for a new job with the customer already chosen.
    init(customer: Customer) {
        self.customer = customer
    }

    /// What How long shows: the length picked, or the type's default.
    var lengthMinutes: Int {
        durationMinutes > 0 ? durationMinutes : jobType.defaultMinutes
    }

    init(job: Job?) {
        guard let job else { return }
        customer = job.customer
        jobType = job.jobType
        date = job.scheduledAt
        hasTime = job.hasTime
        durationMinutes = job.durationMinutes
        priceText = Parse.moneyText(job.price)
        paymentType = job.paymentType
        isPaid = job.isPaid
        isDone = job.isDone
        notes = job.notes
    }

    func apply(to job: Job) {
        job.customer = customer
        job.jobType = jobType
        job.scheduledAt = hasTime ? date : Calendar.current.startOfDay(for: date)
        job.hasTime = hasTime
        job.durationMinutes = durationMinutes
        job.price = Parse.money(priceText)
        job.paymentType = paymentType
        job.isPaid = isPaid
        job.isDone = isDone
        job.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        job.updatedAt = Date()
    }
}
