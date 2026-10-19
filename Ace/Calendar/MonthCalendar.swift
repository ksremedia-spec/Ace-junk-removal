import SwiftUI

#if os(iOS)
import UIKit

/// Apple's iPhone month view (UICalendarView), one day chosen at a time,
/// with a dot under each day that has a job not yet done. Swipe for other
/// months. Sized to sit in a List row.
struct MonthCalendar: UIViewRepresentable {
    @Binding var selectedDay: Date
    /// Start of each day that gets a dot.
    let dottedDays: Set<Date>

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDay: $selectedDay, dottedDays: dottedDays)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.locale = Locale.current
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = CalendarDays.components(selectedDay)
        view.selectionBehavior = selection
        view.visibleDateComponents = CalendarDays.components(selectedDay)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.selectedDay = $selectedDay

        // Redraw the dots of days whose jobs changed.
        let changed = coordinator.dottedDays.symmetricDifference(dottedDays)
        coordinator.dottedDays = dottedDays
        if !changed.isEmpty {
            view.reloadDecorations(forDateComponents: changed.map { CalendarDays.components($0) }, animated: false)
        }

        // The day was changed from outside (the Today button): choose it
        // and show its month.
        guard let selection = view.selectionBehavior as? UICalendarSelectionSingleDate else { return }
        let calendar = Calendar.current
        let chosen = selection.selectedDate.flatMap { calendar.date(from: $0) }
        let matches = chosen.map { calendar.isDate($0, inSameDayAs: selectedDay) } ?? false
        if !matches {
            let wanted = CalendarDays.components(selectedDay)
            selection.setSelected(wanted, animated: true)
            view.setVisibleDateComponents(wanted, animated: true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitted.height)
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var selectedDay: Binding<Date>
        var dottedDays: Set<Date>

        init(selectedDay: Binding<Date>, dottedDays: Set<Date>) {
            self.selectedDay = selectedDay
            self.dottedDays = dottedDays
            super.init()
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            let calendar = Calendar.current
            guard let date = calendar.date(from: dateComponents) else { return nil }
            return dottedDays.contains(calendar.startOfDay(for: date)) ? .default() : nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            let calendar = Calendar.current
            guard let dateComponents, let date = calendar.date(from: dateComponents) else {
                // Tapping the chosen day again clears it; keep it chosen.
                selection.setSelected(CalendarDays.components(selectedDay.wrappedValue), animated: false)
                return
            }
            selectedDay.wrappedValue = calendar.startOfDay(for: date)
        }
    }
}

#else

/// The Mac's Calendar list uses Apple's month picker directly
/// (MacCalendarList). This stand-in only keeps the shared iPhone screen
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
