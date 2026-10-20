import SwiftUI

/// A week across the screen, one button per day, for the iPhone Calendar
/// and Labor pages: the weekday letter, the date (today's in teal, the
/// chosen day in a teal circle) and a dot under a marked day. The arrows,
/// or a swipe, move a week at a time. Its text stops growing at the
/// xxLarge size, as in Apple's Calendar, so seven days still fit a row.
struct WeekStrip: View {
    @Binding var day: Date
    /// Grows with the text, up to its size at xxLarge (the metric itself
    /// reads the uncapped size).
    @ScaledMetric(relativeTo: .body) private var scaledCircle: CGFloat = 34
    private var circle: CGFloat { min(scaledCircle, 42) }
    /// Start of each day that gets a dot.
    var marked: Set<Date> = []

    private var calendar: Calendar { .current }
    private var days: [Date] { Labor.week(containing: day, calendar: calendar) }

    var body: some View {
        VStack(spacing: Space.s) {
            HStack {
                Text(Dates.monthYear(days.first ?? day))
                    .font(.headline)
                Spacer()
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous week")
                Button { step(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next week")
            }
            .buttonStyle(.borderless)
            HStack(spacing: 2) {
                ForEach(days, id: \.self) { date in
                    dayButton(date)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    step(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func dayButton(_ date: Date) -> some View {
        let isChosen = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDateInToday(date)
        return Button {
            day = calendar.startOfDay(for: date)
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.body.weight(isChosen || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isChosen ? Color.white : (isToday ? Color.accentColor : .primary))
                    .frame(width: circle, height: circle)
                    .background(Circle().fill(isChosen ? Color.accentColor : .clear))
                Circle()
                    .fill(marked.contains(calendar.startOfDay(for: date)) ? Color.secondary : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Dates.longDay(date) + (isToday ? ", today" : ""))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func step(_ direction: Int) {
        if let moved = calendar.date(byAdding: .weekOfYear, value: direction, to: day) {
            day = calendar.startOfDay(for: moved)
        }
    }
}
