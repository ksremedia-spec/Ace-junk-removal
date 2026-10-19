import EventKit
import SwiftUI

#if os(iOS)
import EventKitUI

/// Apple's own event screen (EventKitUI), where an event from another
/// calendar can be read and edited as in Apple's Calendar app. Shown as a
/// sheet with its own navigation bar, so its Edit and Done buttons appear.
struct EventViewer: UIViewControllerRepresentable {
    let event: EKEvent
    /// Done tapped, or the event deleted: the sheet closes.
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.onDone = onDone
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        var onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
            super.init()
        }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}

#else

/// Apple's event screens are not available in a Mac app; the Mac shows the
/// read-only page in its detail column instead. This stand-in only keeps
/// the shared iPhone screen compiling for the Mac.
struct EventViewer: View {
    let event: EKEvent
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            CalendarEventPage(event: event)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone() }
                    }
                }
        }
    }
}

#endif
