import Foundation

/// Which jobs the Jobs list shows. Shared by the iPhone list, the Mac list
/// and the Mac sidebar.
enum JobsFilter: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case unpaid = "Unpaid"
    case done = "Done"

    var id: String { rawValue }

    /// The jobs this filter shows. Upcoming is soonest first; Unpaid and Done
    /// are newest first. `jobs` must already be sorted by date.
    func apply(to jobs: [Job], today: Date = Dates.startOfToday()) -> [Job] {
        switch self {
        case .upcoming:
            return jobs.filter { !$0.isDone && $0.scheduledAt >= today }
        case .unpaid:
            return jobs.filter { $0.isUnpaid(asOf: today) }.reversed()
        case .done:
            return jobs.filter(\.isDone).reversed()
        }
    }
}

enum JobSearch {
    /// Jobs whose customer name, address or phone, notes or type contain
    /// `text`. Empty text keeps everything.
    static func filter(_ jobs: [Job], _ text: String) -> [Job] {
        let search = SearchText(text)
        guard !search.isEmpty else { return jobs }
        return jobs.filter { job in
            search.matches(texts: [job.customer?.name ?? "", job.customer?.address ?? "", job.notes, job.jobType.rawValue],
                           phoneDigits: job.customer?.phoneDigits ?? "")
        }
    }
}

/// One day's upcoming jobs, for a list section.
struct JobDay: Identifiable {
    let day: Date
    let jobs: [Job]

    var id: Date { day }

    /// "Friday, October 24 · 3 jobs · $1,250". The money is left off when no
    /// job that day has a price.
    var title: String {
        let calendar = Calendar.current
        let name = calendar.isDateInToday(day) ? "Today"
            : calendar.isDateInTomorrow(day) ? "Tomorrow"
            : Dates.longDay(day)
        var text = name + " · " + Plural.text(jobs.count, "job")
        let total = jobs.priceTotal
        if total > 0 { text += " · " + Money.text(total) }
        return text
    }

    /// Groups jobs that are already sorted by date into days.
    static func group(_ jobs: [Job], calendar: Calendar = .current) -> [JobDay] {
        var days: [JobDay] = []
        for job in jobs {
            let start = calendar.startOfDay(for: job.scheduledAt)
            if let last = days.last, last.day == start {
                days[days.count - 1] = JobDay(day: start, jobs: last.jobs + [job])
            } else {
                days.append(JobDay(day: start, jobs: [job]))
            }
        }
        return days
    }
}
