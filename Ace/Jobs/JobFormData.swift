import Foundation

/// What the job form edits. Copied out of a Job for editing and written back
/// on Save, so a cancelled edit changes nothing.
struct JobFormData {
    var customer: Customer?
    var jobType: JobType = .junkRemoval
    var date: Date = Dates.nextFullHour()
    var hasTime = true
    /// "Set an end time". Off by default: nothing is assumed.
    var hasEnd = false
    /// The Ends picker. Only its clock time is used, on the job's own day.
    var endTime: Date = JobTimes.suggestedEnd(after: Dates.nextFullHour())
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

    /// The end time to save: on the job's day, or nil without a time or
    /// an end time.
    var endDate: Date? {
        hasTime ? JobTimes.end(start: date, hasEnd: hasEnd, endTime: endTime) : nil
    }

    /// False while an end time is set that is not after the start.
    var endIsValid: Bool {
        !hasTime || JobTimes.endIsValid(start: date, hasEnd: hasEnd, endTime: endTime)
    }

    init(job: Job?) {
        guard let job else { return }
        customer = job.customer
        jobType = job.jobType
        date = job.scheduledAt
        hasTime = job.hasTime
        if job.hasTime, let end = job.endsAt {
            hasEnd = true
            endTime = end
        } else {
            endTime = JobTimes.suggestedEnd(after: job.scheduledAt)
        }
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
        job.endsAt = endDate
        job.price = Parse.money(priceText)
        job.paymentType = paymentType
        job.isPaid = isPaid
        job.isDone = isDone
        job.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        job.updatedAt = Date()
    }
}
