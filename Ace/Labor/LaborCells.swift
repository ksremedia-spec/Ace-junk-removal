import SwiftData
import SwiftUI

// One day of one person on the timesheet, on the Mac grid and the iPhone
// day list alike.

/// Tall enough to tap on a phone, compact on the Mac grid.
enum LaborCellSize {
    #if os(iOS)
    static let height: CGFloat = 40
    #else
    static let height: CGFloat = 28
    #endif
}

/// An hourly person's hours for one day. Typed text is kept until Return,
/// Tab or clicking away, then read ("8", "7.5", "7:30") and saved. On the
/// iPhone, tapping the box selects what is there, so typing replaces it;
/// the number pad's Done button comes with `decimalKeyboard()`.
struct HoursCell: View {
    @Environment(\.modelContext) private var context
    let worker: Worker
    let day: Date
    /// Called when the box is tapped into, so the page can scroll it clear
    /// of the keyboard.
    var onFocus: (() -> Void)? = nil

    @State private var text = ""
    @State private var rejected = 0
    @FocusState private var focused: Bool

    private var stored: String {
        worker.hours(on: day).map { Labor.hoursText($0) } ?? ""
    }

    var body: some View {
        TextField("", text: $text, prompt: Text("–"))
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .textFieldStyle(.plain)
            .font(.callout.weight(.medium))
            .decimalKeyboard(focus: $focused)
            .frame(maxWidth: .infinity, minHeight: LaborCellSize.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(text.isEmpty ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: focused ? 1.5 : 0)
            )
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    selectAll()
                    onFocus?()
                } else {
                    commit()
                }
            }
            .onAppear { text = stored }
            .onChange(of: stored) { _, value in
                if !focused { text = value }
            }
            // The iPhone reuses this box when another day is picked in the
            // week strip: typing still under way belongs to the day it was
            // typed for, not the newly picked one.
            .onChange(of: day) { oldDay, _ in
                if focused { commit(on: oldDay) }
                text = stored
            }
            .sensoryFeedback(.warning, trigger: rejected)
            .accessibilityLabel("\(worker.name), \(Dates.longDay(day)), hours")
    }

    /// Selects the box's text once the tap has placed the cursor.
    private func selectAll() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        #endif
    }

    private func commit() {
        commit(on: day)
    }

    /// Saves the typed hours to `target`. Text that is not hours (or more
    /// than 24) is not saved: the old value comes back with a warning buzz.
    private func commit(on target: Date) {
        switch Labor.validHours(text) {
        case .clear:
            Labor.setHours(nil, for: worker, on: target, in: context)
        case .hours(let hours):
            Labor.setHours(hours, for: worker, on: target, in: context)
        case .invalid:
            rejected += 1
        }
        text = stored
    }
}

/// A salaried person's day: a check when working, "Off" when not, a dash
/// on a day outside the work week. Clicking switches it.
struct SalaryCell: View {
    @Environment(\.modelContext) private var context
    let worker: Worker
    let day: Date

    var body: some View {
        let worked = worker.worked(on: day)
        let workDay = worker.usuallyWorks(on: day)
        // Days still to come are planned, not worked yet.
        let ahead = day > Dates.startOfToday()
        Button {
            Labor.setWorked(!worked, for: worker, on: day, in: context)
        } label: {
            Group {
                if worked {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                } else if workDay {
                    Text("Off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Tint.owed)
                } else {
                    Text("–")
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(ahead ? 0.45 : 1)
            .frame(maxWidth: .infinity, minHeight: LaborCellSize.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(worked ? Color.accentColor.opacity(ahead ? 0.06 : 0.14) : (workDay ? Tint.owed.opacity(0.12) : Color.primary.opacity(0.04)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(worked ? "Mark off this day" : "Mark worked this day")
        .accessibilityLabel("\(worker.name), \(Dates.longDay(day)), " + (worked ? "worked" : "off"))
    }
}
