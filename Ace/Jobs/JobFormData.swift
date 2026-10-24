import Foundation

/// What the job form edits. Copied out of a Job for editing and written back
/// on Save, so a cancelled edit changes nothing.
struct JobFormData: Equatable {
    var customer: Customer?
    var jobType: JobType = .junkRemoval
    var date: Date = Dates.nextFullHour()
    /// Off for a new job until a time is chosen: a blank form used to open
    /// already warning "Overlaps" against whatever was booked at the next
    /// full hour (Oct 20 audit). Turning it on starts at the next full hour.
    var hasTime = false
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

    /// A blank form for a new job on `day` (the Calendar's New job), with
    /// "Set a time" off. Turning it on starts the picker at the next full
    /// hour's clock time on that day.
    init(day: Date) {
        date = JobTimes.combine(day: day, time: Dates.nextFullHour())
        hasTime = false
        endTime = JobTimes.suggestedEnd(after: date)
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

    /// Writes only what was changed since `base` (the form as it was
    /// opened), so a page left open on one device never puts back fields
    /// another device changed meanwhile (audit Oct 21, M8). With no base,
    /// writes everything (a new job).
    func apply(to job: Job, changedSince base: JobFormData?) {
        guard let base else { return apply(to: job) }
        if customer != base.customer { job.customer = customer }
        if jobType != base.jobType { job.jobType = jobType }
        if date != base.date || hasTime != base.hasTime || hasEnd != base.hasEnd || endTime != base.endTime {
            job.scheduledAt = hasTime ? date : Calendar.current.startOfDay(for: date)
            job.hasTime = hasTime
            job.endsAt = endDate
        }
        if priceText != base.priceText { job.price = Parse.money(priceText) }
        if paymentType != base.paymentType { job.paymentType = paymentType }
        if isPaid != base.isPaid { job.isPaid = isPaid }
        if isDone != base.isDone { job.isDone = isDone }
        if notes != base.notes { job.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines) }
        job.updatedAt = Date()
    }

    /// This form after the job changed elsewhere: fields not touched here
    /// take the job's new values; fields typed here are kept.
    func merging(fresh: JobFormData, base: JobFormData) -> JobFormData {
        var merged = self
        if customer == base.customer { merged.customer = fresh.customer }
        if jobType == base.jobType { merged.jobType = fresh.jobType }
        if date == base.date && hasTime == base.hasTime && hasEnd == base.hasEnd && endTime == base.endTime {
            merged.date = fresh.date; merged.hasTime = fresh.hasTime
            merged.hasEnd = fresh.hasEnd; merged.endTime = fresh.endTime
        }
        if priceText == base.priceText { merged.priceText = fresh.priceText }
        if paymentType == base.paymentType { merged.paymentType = fresh.paymentType }
        if isPaid == base.isPaid { merged.isPaid = fresh.isPaid }
        if isDone == base.isDone { merged.isDone = fresh.isDone }
        if notes == base.notes {
            merged.notes = fresh.notes
        } else {
            // Typed notes are kept, but a check number written meanwhile by
            // Mark paid › Check goes into them, or it would be lost when
            // they are saved (audit Oct 24, 23).
            let check = JobActions.checkNumber(in: fresh.notes)
            if check != JobActions.checkNumber(in: base.notes) {
                merged.notes = JobActions.notes(notes, check: check)
            }
        }
        return merged
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
