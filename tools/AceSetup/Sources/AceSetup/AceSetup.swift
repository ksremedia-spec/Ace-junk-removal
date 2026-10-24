import AppKit
import SwiftUI

// "Ace Setup": a step-by-step guide for setup day, for Kyle. Each step says
// what to do in plain words, has one button that does the work (by running
// a script in tools/setup), and shows what happened. Progress is remembered.

@main
struct AceSetupApp: App {
    var body: some Scene {
        WindowGroup("Ace Setup") {
            SetupView()
                .frame(minWidth: 720, minHeight: 640)
                .onAppear {
                    // `-step` (pictures of the guide): the window at the left edge.
                    guard ProcessInfo.processInfo.arguments.contains("-step") else { return }
                    DispatchQueue.main.async {
                        NSApp.windows.first?.setFrame(NSRect(x: 0, y: 100, width: 730, height: 760), display: true)
                    }
                }
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Steps

struct SetupStep: Identifiable, Hashable {
    enum Kind: Hashable { case info, script, iphone, mac, sheet, check }
    let id: String
    let title: String
    let symbol: String
    let kind: Kind
    let intro: String
    let bullets: [String]
    var script: String? = nil
    var arguments: [String] = []
    var button: String? = nil
    var confirm: String? = nil
}

let steps: [SetupStep] = [
    SetupStep(id: "before", title: "Before they arrive", symbol: "checklist", kind: .check,
              intro: "Checks this Mac and the Ace server are ready. Nothing is changed.",
              bullets: ["Plug this Mac into power and keep it on Wi-Fi.",
                        "Have their iPhones' charging cables handy.",
                        "Ask Ashley to bring her MacBook and know her Google (Gmail) password."],
              script: "preflight.sh", button: "Check"),
    SetupStep(id: "fresh", title: "Make the server fresh", symbol: "arrow.counterclockwise.icloud", kind: .script,
              intro: "Puts the newest server code on Cloudflare, removes all the test jobs and customers from the Ace server, disconnects the test Google Sheet, and makes a new sync code, so only their copies of Ace can reach it. Then it checks the Assistant answers. Do this once, the morning of setup day.",
              bullets: ["Your own test copies of Ace stop syncing after this. That's expected.",
                        "Nothing on their devices is touched: Ace isn't on them yet.",
                        "If you later want the business copy on your own iPhone or Mac, delete your test copy of Ace from it first, so its test jobs can't reach their server."],
              script: "server-ready.sh", button: "Make the Server Fresh",
              confirm: "This empties the live Ace server and changes its sync code. Your test copies stop syncing. Continue?"),
    SetupStep(id: "build", title: "Build their copies", symbol: "hammer", kind: .script,
              intro: "Builds the business versions of Ace with the new sync code inside: the Mac copy is sent to Apple to be checked (notarized), the iPhone copy is uploaded to TestFlight. Takes about 15 minutes, then Apple needs 15–30 minutes more before the iPhone copy shows in TestFlight.",
              bullets: ["Do this right after \"Make the server fresh\".",
                        "The Mac file goes in a folder on your Desktop: \"Ace for the business\"."],
              script: "build-business.sh", button: "Build"),
    SetupStep(id: "iphones", title: "Their iPhones (TestFlight)", symbol: "iphone", kind: .info,
              intro: "Each iPhone gets Ace over the air through Apple's TestFlight app. No cable, no Developer Mode. Yours too, to check it end to end.",
              bullets: ["Once, at appstoreconnect.apple.com: TestFlight › Internal Testing › + › name it \"Ace team\", tick Enable automatic distribution, then Invite Testers: you, Ashley and Alex. (They must have accepted the email inviting them to your team first.)",
                        "On each iPhone: open the TestFlight email from Apple, install the free TestFlight app from the App Store, then tap Install next to Ace.",
                        "Open Ace. Allow notifications and the microphone when asked. It starts empty and fills in from the server within a minute.",
                        "On your own iPhone, delete the old Ace first, so its test jobs don't come along.",
                        "Backup if TestFlight won't work: plug the iPhone in, then use Install below (it needs Developer Mode on the phone)."]),
    SetupStep(id: "updates", title: "Automatic updates", symbol: "arrow.triangle.2.circlepath", kind: .script,
              intro: "A TestFlight copy stops opening 90 days after it was uploaded. This turns on a daily check on this Mac that uploads a fresh copy of the last committed version every 60 days, so theirs never runs out.",
              bullets: ["This Mac has to be on (or wake up) now and then, and Xcode has to stay signed in to your Apple account.",
                        "If an upload fails, a notice appears on this Mac and it tries again the next day; the copy on their phones keeps working until day 90.",
                        "After you change Ace, commit the change, then click Build in step 3 to send it out right away."],
              script: "testflight-job.sh", arguments: ["install"], button: "Turn On Automatic Updates"),
    SetupStep(id: "mac", title: "Ashley's Mac", symbol: "laptopcomputer", kind: .mac,
              intro: "Puts Ace on Ashley's MacBook. Her Mac needs macOS 26 or newer: on her Mac, Apple menu › About This Mac.",
              bullets: ["Click AirDrop to Ashley's Mac (her Mac must be nearby, awake, with AirDrop on), or copy the file with a USB stick.",
                        "On her Mac: open the file, drag Ace into Applications, then open Ace from Applications.",
                        "The first time, macOS may ask to confirm opening an app from the internet: click Open."]),
    SetupStep(id: "sheet", title: "Connect her Google Sheet", symbol: "tablecells", kind: .sheet,
              intro: "On Ashley's Mac, in Ace: Settings › Google Sheet › Connect Google Sheet. She signs in with the business Gmail, clicks Allow, and picks \"2026 ACE Books\".",
              bullets: ["If the sheet has a small \".XLSX\" tag next to its name, open it in Google Sheets and choose File › Save as Google Sheets first, then pick the new one.",
                        "Within a minute every job in the sheet shows up in Ace on all three devices.",
                        "Click Check Server below to see it worked."],
              script: "status.sh", button: "Check Server"),
    SetupStep(id: "setup", title: "Dumpsters, crew, rate", symbol: "shippingbox", kind: .info,
              intro: "In Ace on any one device. The others follow by themselves.",
              bullets: ["Dumpsters: tap Set up 6 dumpsters, then for each one that's out, log its drop-off (customer, address, due back, price, agreed weight).",
                        "Labor: add each crew member with their pay.",
                        "Settings › Dumpsters: set the overweight rate per ton (ask Alex; $125 is only a placeholder). It reaches the other devices by itself.",
                        "Try the Assistant on Alex's phone: hold the button and say a job. No key to type; it goes through the Ace server."]),
    SetupStep(id: "final", title: "Final check", symbol: "checkmark.seal", kind: .script,
              intro: "Shows what the server holds now: how many jobs and customers, how many devices have synced (should be 3), and the Google Sheet link.",
              bullets: ["On each device, the small icon at the top should be a check mark.",
                        "The iPhone copies renew themselves through TestFlight every 60 days (step 5). Never delete Ace from their phones: that would remove what hasn't synced yet."],
              script: "status.sh", button: "Check Everything"),
]

// MARK: - Running a step

@MainActor @Observable
final class Runner {
    var lines: [String] = []
    var running = false
    var lastExit: Int32?

    static var repo: URL {
        if let path = Bundle.main.object(forInfoDictionaryKey: "AceRepo") as? String { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Documents/Ace-junk-removal")
    }

    func run(_ script: String, _ arguments: [String] = []) async {
        guard !running else { return }
        running = true
        lastExit = nil
        lines = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [Self.repo.appending(path: "tools/setup/\(script)").path] + arguments
        process.currentDirectoryURL = Self.repo
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let new = text.split(whereSeparator: \.isNewline).map(String.init)
            Task { @MainActor in self.lines.append(contentsOf: new) }
        }
        do {
            try process.run()
        } catch {
            lines.append("FAIL: Could not start \(script): \(error.localizedDescription)")
            running = false
            return
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in done.resume() }
        }
        handle.readabilityHandler = nil
        lastExit = process.terminationStatus
        running = false
    }

    /// The lines a person needs (STEP/OK/FAIL/INFO and the server status),
    /// in plain words; everything else is kept for "Show details".
    var plain: [String] {
        lines.compactMap { line in
            for prefix in ["STEP: ", "OK: ", "FAIL: ", "INFO: "] where line.hasPrefix(prefix) { return line }
            for prefix in ["SERVER: ", "RECORDS: ", "DEVICES: ", "SHEET: ", "IPHONE: ", "MAC: "] where line.hasPrefix(prefix) { return line }
            return nil
        }
    }
}

// MARK: - Screens

struct SetupView: View {
    @AppStorage("done") private var doneRaw = ""
    // `-step <id>` opens on that step (for pictures of the guide).
    @State private var selection: String? = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-step"), i + 1 < args.count { return args[i + 1] }
        return steps.first?.id
    }()

    private var done: Set<String> { Set(doneRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 10) {
                        Image(systemName: done.contains(step.id) ? "checkmark.circle.fill" : step.symbol)
                            .foregroundStyle(done.contains(step.id) ? Color.green : Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(index + 1). \(step.title)")
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(step.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            if let step = steps.first(where: { $0.id == selection }) {
                StepView(step: step, isDone: done.contains(step.id)) { isDone in
                    var set = done
                    if isDone { set.insert(step.id) } else { set.remove(step.id) }
                    doneRaw = set.sorted().joined(separator: ",")
                    if isDone, let next = steps.firstIndex(of: step).map({ $0 + 1 }), next < steps.count {
                        selection = steps[next].id
                    }
                }
                .id(step.id)
            }
        }
    }
}

struct StepView: View {
    let step: SetupStep
    let isDone: Bool
    let setDone: (Bool) -> Void

    @State private var runner = Runner()
    @State private var confirming = false
    @State private var showDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(step.title, systemImage: step.symbol)
                    .font(.largeTitle.weight(.bold))
                Text(step.intro)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(step.bullets.enumerated()), id: \.offset) { index, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.callout.weight(.semibold))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            Text(bullet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.body)

                switch step.kind {
                case .iphone: IPhoneInstaller(runner: runner)
                case .info where step.id == "iphones": IPhoneInstaller(runner: runner)
                case .mac: MacInstaller(runner: runner)
                default: EmptyView()
                }

                if let button = step.button, let script = step.script {
                    Button {
                        if step.confirm != nil { confirming = true } else { start(script) }
                    } label: {
                        if runner.running {
                            HStack { ProgressView().controlSize(.small); Text("Working…") }
                        } else {
                            Text(button)
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(runner.running)
                    .confirmationDialog(step.confirm ?? "", isPresented: $confirming) {
                        Button(button, role: .destructive) { start(script) }
                    }
                }

                ResultView(runner: runner, showDetails: $showDetails)

                Divider()
                Toggle("This step is done", isOn: Binding(get: { isDone }, set: { setDone($0) }))
                    .toggleStyle(.checkbox)
                    .font(.headline)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func start(_ script: String) {
        Task { await runner.run(script, step.arguments) }
    }
}

struct ResultView: View {
    let runner: Runner
    @Binding var showDetails: Bool

    var body: some View {
        if !runner.lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(runner.plain.enumerated()), id: \.offset) { _, line in
                    row(line)
                }
                if let exit = runner.lastExit {
                    Label(exit == 0 ? "Finished." : "Stopped. Nothing after the red line was done.",
                          systemImage: exit == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(exit == 0 ? Color.green : Color.red)
                        .font(.headline)
                        .padding(.top, 4)
                }
                DisclosureGroup("Show details", isExpanded: $showDetails) {
                    ScrollView {
                        Text(runner.lines.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("FAIL: ") {
            Label(String(line.dropFirst(6)), systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } else if line.hasPrefix("OK: ") {
            Label(String(line.dropFirst(4)), systemImage: "checkmark.circle").foregroundStyle(.green)
        } else if line.hasPrefix("STEP: ") {
            Label(String(line.dropFirst(6)), systemImage: "arrow.right.circle").foregroundStyle(.secondary)
        } else if line.hasPrefix("INFO: ") {
            Label(String(line.dropFirst(6)), systemImage: "info.circle")
        } else {
            Text(StatusText.plain(line)).font(.body)
        }
    }
}

/// The server's status lines in plain words.
enum StatusText {
    static func plain(_ line: String) -> String {
        func json(_ prefix: String) -> Any? {
            guard line.hasPrefix(prefix) else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(line.dropFirst(prefix.count).utf8))
        }
        if line.hasPrefix("SERVER: ") { return line.contains("\"ok\":true") ? "The Ace server is online." : "The Ace server did not answer." }
        if let rows = json("RECORDS: ") as? [[String: Any]] {
            if rows.isEmpty { return "The server is empty." }
            let names = ["setting": "settings", "job": "jobs", "customer": "customers", "dumpster": "dumpsters", "rental": "past rentals", "quote": "quotes", "worker": "crew", "labor": "days of hours"]
            return "On the server: " + rows.compactMap { r in
                guard let t = r["type"] as? String, let n = r["n"] as? Int else { return nil }
                return "\(n) \(names[t] ?? t)"
            }.joined(separator: ", ") + "."
        }
        if let rows = json("DEVICES: ") as? [[String: Any]], let n = rows.first?["n"] as? Int {
            return n == 1 ? "1 device has sent changes." : "\(n) devices have sent changes."
        }
        if let rows = json("SHEET: ") as? [[String: Any]] {
            guard let s = rows.first else { return "No Google Sheet is connected." }
            let name = s["sheet_name"] as? String ?? "a sheet"
            if let paused = s["paused"] as? String, !paused.isEmpty { return "Connected to \"\(name)\", but paused: \(paused)" }
            if let error = s["last_error"] as? String, !error.isEmpty { return "Connected to \"\(name)\", with a problem: \(error)" }
            return "Connected to \"\(name)\". It's being checked every minute."
        }
        if line.hasPrefix("IPHONE: ") || line.hasPrefix("MAC: ") { return String(line.drop(while: { $0 != " " }).dropFirst()) }
        return line
    }
}

// MARK: - Installing

struct IPhone: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let state: String
    let ios: String
    let developerMode: String

    var iosOK: Bool { (Int(ios.split(separator: ".").first ?? "") ?? 0) >= 26 }
}

struct IPhoneInstaller: View {
    let runner: Runner
    @State private var phones: [IPhone] = []
    @State private var picked: IPhone?
    @State private var looking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(looking ? "Looking…" : "Find iPhones") { Task { await find() } }
                    .disabled(looking || runner.running)
                if phones.isEmpty && !looking { Text("Plug the iPhone in, unlock it, then click Find iPhones.").foregroundStyle(.secondary) }
            }
            ForEach(phones) { phone in
                Button { picked = phone } label: {
                    HStack {
                        Image(systemName: picked == phone ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(phone.name).font(.headline)
                            Text("\(phone.model) · iOS \(phone.ios) · Developer Mode \(phone.developerMode == "enabled" ? "on" : "off")")
                                .foregroundStyle(phone.iosOK ? Color.secondary : Color.red)
                            if !phone.iosOK { Text("Needs iOS 26 or newer: Settings › General › Software Update.").foregroundStyle(.red) }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let picked {
                Button("Install Ace on \(picked.name)") {
                    Task { await runner.run("install-iphone.sh", [picked.id]) }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(runner.running || !picked.iosOK)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
    }

    private func find() async {
        looking = true
        defer { looking = false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [Runner.repo.appending(path: "tools/setup/list-iphones.sh").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        phones = text.split(whereSeparator: \.isNewline).compactMap { line in
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 6 else { return nil }
            return IPhone(id: p[0], name: p[1], model: p[2], state: p[3], ios: p[4], developerMode: p[5])
        }
        // Kyle's own phones are known; their newest-connected one is not picked by default.
        picked = phones.count == 1 ? phones.first : nil
    }
}

struct MacInstaller: View {
    let runner: Runner

    private var dmg: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Desktop/Ace for the business/Ace.dmg")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let exists = FileManager.default.fileExists(atPath: dmg.path)
            Text(exists ? "Ready: Ace.dmg in \"Ace for the business\" on your Desktop." : "Build their copies first (step 3).")
                .foregroundStyle(exists ? Color.primary : Color.red)
            HStack {
                Button("AirDrop to Ashley's Mac") {
                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [dmg])
                }
                .disabled(!exists)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([dmg]) }
                    .disabled(!exists)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
    }
}
