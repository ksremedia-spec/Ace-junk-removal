import Foundation

/// What the job form edits. Copied out of a Job for editing and written back
/// on Save, so a cancelled edit changes nothing.
struct JobFormData {
    var customer: Customer?
    var jobType: JobType = .junkRemoval
    var date: Date = Dates.nextFullHour()
    var hasTime = true
    var priceText = ""
    var paymentType: PaymentType = .unknown
    var isPaid = false
    var isDone = false
    var notes = ""

    init() {}

    init(job: Job?) {
        guard let job else { return }
        customer = job.customer
        jobType = job.jobType
        date = job.scheduledAt
        hasTime = job.hasTime
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
        job.price = Parse.money(priceText)
        job.paymentType = paymentType
        job.isPaid = isPaid
        job.isDone = isDone
        job.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        job.updatedAt = Date()
    }
}
