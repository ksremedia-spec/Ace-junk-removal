import EventKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Settings › Calendar, on iPhone and Mac: calendar access, the Calendar for
/// Jobs, and which other calendars show on the Calendar screen. This is the
/// only place Ace asks for calendar access; it never asks at launch. The
/// spec is docs/calendar-tab.md.
struct CalendarSettingsSection: View {
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    #endif

    private var store: CalendarStore { .shared }

    private var jobsCalendarChoice: Binding<String> {
        Binding(
            get: { store.jobsCalendarID },
            set: { store.setJobsCalendar($0) }
        )
    }

    var body: some View {
        Section {
            LabeledContent("Calendar Access", value: store.access.text)
            if store.access == .notSet {
                Button("Allow Calendar Access") {
                    Task { await store.requestAccess() }
                }
            }
            #if os(iOS)
            if store.access == .off {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            #endif
            if store.access == .full {
                Picker("Calendar for Jobs", selection: jobsCalendarChoice) {
                    Text("None").tag("")
                    if store.jobsCalendarMissing {
                        Text("Not found").tag(store.jobsCalendarID)
                    }
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                        Text(CalendarStore.label(for: calendar)).tag(calendar.calendarIdentifier)
                    }
                }
                NavigationLink("Show Calendars", value: MainView.Screen.calendars)
            }
        } header: {
            Text("Calendar")
        } footer: {
            if store.access == .off {
                Text(offText)
            } else {
                Text("Jobs are added to the calendar for jobs when saved. Changes made in Google Calendar do not change jobs in Ace.")
            }
        }
    }

    private var offText: String {
        #if os(iOS)
        return "Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars."
        #else
        return "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars."
        #endif
    }
}

/// Every calendar on the device, by account, with a switch each; all on to
/// start. Switched-off calendars stay out of the Calendar screen. The
/// Calendar for Jobs is not listed: its copies of jobs are hidden when the
/// job is on this device, and its other events always show.
struct ShowCalendarsView: View {
    private var store: CalendarStore { .shared }

    private struct Account: Identifiable {
        let id: String
        let title: String
        let calendars: [EKCalendar]
    }

    /// The calendars grouped by account, in the store's order.
    private var accounts: [Account] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var grouped: [String: [EKCalendar]] = [:]
        for calendar in store.otherCalendars {
            let key = calendar.source?.sourceIdentifier ?? ""
            if grouped[key] == nil {
                order.append(key)
                titles[key] = calendar.source?.title ?? ""
            }
            grouped[key, default: []].append(calendar)
        }
        return order.map { Account(id: $0, title: titles[$0] ?? "", calendars: grouped[$0] ?? []) }
    }

    var body: some View {
        Form {
            if accounts.isEmpty {
                Section {
                    Text(store.access == .full ? "No other calendars on this device." : "Calendar access is off.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(accounts) { account in
                Section(account.title.isEmpty ? "Other" : account.title) {
                    ForEach(account.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: shown(calendar)) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(OtherEvent.color(of: calendar))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Show Calendars")
    }

    private func shown(_ calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { store.isShown(calendar) },
            set: { store.setShown($0, for: calendar) }
        )
    }
}
