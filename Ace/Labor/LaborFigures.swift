import SwiftUI

/// The four figures over the timesheet, iPhone and Mac: hourly hours and
/// pay for the week on show, who is working today, and the crew.
struct LaborFigures: View {
    /// Everyone still on the crew.
    let crew: [Worker]
    /// The week on show.
    let days: [Date]
    var columns = 2

    private var isThisWeek: Bool { days.contains { Calendar.current.isDateInToday($0) } }

    private var hourlyHours: Double {
        crew.filter { !$0.isSalaried }.reduce(0) { $0 + Labor.hours($1, over: days) }
    }

    private var pay: Double {
        crew.reduce(0) { $0 + (Labor.pay($1, over: days) ?? 0) }
    }

    private var workingToday: Int {
        crew.filter { $0.worked(on: Dates.startOfToday()) }.count
    }

    var body: some View {
        StatGrid(columns: columns) {
            StatTile(title: "Hourly hours", value: Labor.hoursLabel(hourlyHours),
                     detail: isThisWeek ? "this week so far" : "that week")
            StatTile(title: "Hourly pay", value: Money.text(pay),
                     detail: crew.contains { !$0.isSalaried && $0.hourlyRate == nil } ? "some rates not set" : "at their rates")
            StatTile(title: "Working today", value: "\(workingToday) of \(crew.count)",
                     detail: Dates.shortDay(Dates.startOfToday()))
            StatTile(title: "Crew", value: crew.count == 1 ? "1 person" : "\(crew.count) people",
                     detail: "\(crew.filter(\.isSalaried).count) salary · \(crew.filter { !$0.isSalaried }.count) hourly")
        }
    }
}
