import SwiftUI

#if os(iOS)

/// The iPhone month: a dot under each day that has a job not yet done.
/// Our own grid, like the Mac's (MacMonthGrid), in place of Apple's
/// UICalendarView: Apple's month name opens wheels that close only when the
/// name is tapped again, which Kyle could not find (Oct 21). Here the month
/// name opens "Go to month" with a Done button. Arrows or a swipe move a
/// month.
struct MonthCalendar: View {
    @Binding var selectedDay: Date
    /// Start of each day that gets a dot.
    let dottedDays: Set<Date>

    /// Any day in the month on show.
    @State private var month: Date
    @State private var choosingMonth = false
    /// Grows with the text, up to 40 points, so seven days always fit
    /// across a phone (the metric itself reads the uncapped size).
    @ScaledMetric(relativeTo: .body) private var scaledCircle: CGFloat = 36
    private var circle: CGFloat { min(scaledCircle, 40) }

    init(selectedDay: Binding<Date>, dottedDays: Set<Date>) {
        _selectedDay = selectedDay
        self.dottedDays = dottedDays
        _month = State(initialValue: selectedDay.wrappedValue)
    }

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: Space.s) {
            header
            VStack(spacing: 2) {
                weekdayRow
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
            // The days stop growing at xxLarge, as in Apple's Calendar and
            // the week strip, so the right-hand days stay on screen.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        move(by: drag.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .onChange(of: selectedDay) { _, newValue in
            // The Today button chose a day in another month.
            if !calendar.isDate(newValue, equalTo: month, toGranularity: .month) {
                month = newValue
            }
        }
        .sheet(isPresented: $choosingMonth) {
            GoToMonthSheet(month: month) { chosen in
                month = chosen
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Month and arrows

    private var header: some View {
        HStack {
            Button {
                choosingMonth = true
            } label: {
                HStack(spacing: 6) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
            .accessibilityHint("Opens Go to month")
            Spacer()
            arrow("chevron.left", label: "Previous month", by: -1)
            arrow("chevron.right", label: "Next month", by: 1)
        }
    }

    private func arrow(_ symbol: String, label: String, by months: Int) -> some View {
        Button {
            move(by: months)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func move(by months: Int) {
        if let moved = calendar.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) { month = moved }
        }
    }

    // MARK: Days

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    /// Six weeks, so the month keeps its height from month to month.
    private var weeks: [[Date]] {
        guard let first = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<6).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: start) }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasJobs = dottedDays.contains(calendar.startOfDay(for: day))

        return Button {
            selectedDay = calendar.startOfDay(for: day)
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.body.monospacedDigit())
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(numberColor(inMonth: inMonth, isSelected: isSelected, isToday: isToday))
                    .frame(width: circle, height: circle)
                    .background {
                        if isSelected { Circle().fill(Color.accentColor) }
                    }
                Circle()
                    .fill(hasJobs ? (inMonth ? Color.secondary : Color(uiColor: .quaternaryLabel)) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : "") + (hasJobs ? ", has jobs" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func numberColor(inMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return inMonth ? .primary : Color(uiColor: .tertiaryLabel)
    }
}

/// "Go to month": month and year wheels, then Done (or Cancel).
private struct GoToMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDone: (Date) -> Void
    @State private var monthNumber: Int
    @State private var year: Int

    private static let years = Array(2020...2040)

    init(month: Date, onDone: @escaping (Date) -> Void) {
        self.onDone = onDone
        let parts = Calendar.current.dateComponents([.year, .month], from: month)
        _monthNumber = State(initialValue: parts.month ?? 1)
        _year = State(initialValue: parts.year ?? 2026)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $monthNumber) {
                    ForEach(1...12, id: \.self) { number in
                        Text(Calendar.current.standaloneMonthSymbols[number - 1]).tag(number)
                    }
                }
                Picker("Year", selection: $year) {
                    ForEach(Self.years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal)
            .navigationTitle("Go to month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let date = Calendar.current.date(from: DateComponents(year: year, month: monthNumber, day: 1)) {
                            onDone(date)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#else

/// The Mac's Calendar list uses Apple's month picker directly
/// (MacBoard). This stand-in only keeps the shared iPhone screen
/// compiling for the Mac, where it is never shown.
struct MonthCalendar: View {
    @Binding var selectedDay: Date
    let dottedDays: Set<Date>

    var body: some View {
        DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
    }
}

#endif
