import SwiftUI

/// The small sync icon in the toolbar (Kyle, Oct 21: "a little icon ...
/// that lets that device know it's up to date and synced"). A check mark
/// when everything is sent and received, turning arrows while sending,
/// a warning sign when the server cannot be reached. Click or tap for one
/// line of detail and Sync Now. Hidden until sync is set up.
struct SyncStatusButton: View {
    @State private var sync = SyncEngine.shared
    @State private var showingDetail = false

    var body: some View {
        if sync.status != .off {
            Button {
                showingDetail = true
            } label: {
                icon
            }
            .accessibilityLabel("Sync, " + headline)
            .help(headline)
            .popover(isPresented: $showingDetail) {
                detail
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch sync.status {
        case .sending:
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeating, isActive: true)
        case .waiting:
            Image(systemName: "arrow.triangle.2.circlepath")
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
        case .problem:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(Tint.warning)
        case .upToDate, .off:
            Image(systemName: "checkmark.circle")
        }
    }

    private var headline: String {
        switch sync.status {
        case .off: return "Sync is not set up"
        case .sending: return "Syncing"
        case .waiting: return "Changes are saved and will send in a moment"
        case .offline: return "Offline. Changes are kept on this device and sent when there's a connection."
        case .problem(let text): return text
        case .upToDate: return "Up to date"
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(headline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if sync.problem != nil {
                Text("Changes made here are kept on this device and sent once the server can be reached.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = sync.lastSynced {
                Text("Last synced " + last.formatted(.relative(presentation: .named)) + ".")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(sync.isSyncing ? "Syncing…" : "Sync Now") {
                Task { await sync.syncNow(manual: true) }
            }
            .disabled(sync.isSyncing)
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .frame(minWidth: 240, maxWidth: 320, alignment: .leading)
    }
}
