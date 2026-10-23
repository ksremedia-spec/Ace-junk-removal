#if os(macOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// File › Import: pick the sheet, see what was found, then import (CLAUDE.md
/// feature 4: "Found 614 customers, 12 rows have no phone number" before
/// saving). Mac only.
extension View {
    func spreadsheetImport(isPresented: Binding<Bool>) -> some View {
        modifier(SpreadsheetImportFlow(choosing: isPresented))
    }
}

private struct SpreadsheetImportFlow: ViewModifier {
    @Binding var choosing: Bool
    @State private var preview: ImportPreview?
    @State private var failure: String?

    private static let types: [UTType] = [UTType(filenameExtension: "xlsx"), .commaSeparatedText].compactMap { $0 }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: openTestSheet)
            .fileImporter(isPresented: $choosing, allowedContentTypes: Self.types) { result in
                switch result {
                case .success(let url): open(url)
                case .failure: break
                }
            }
            .sheet(item: $preview) { preview in
                ImportPreviewSheet(preview: preview)
            }
            .alert("The file could not be imported.", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    /// Debug builds only: `-debug.import sheet.xlsx` opens that file from the
    /// app's temporary folder at launch, so the preview can be checked
    /// without the Open panel. A normal launch never carries the argument.
    private func openTestSheet() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard preview == nil, let index = args.firstIndex(of: "-debug.import"), index + 1 < args.count else { return }
        open(FileManager.default.temporaryDirectory.appendingPathComponent(args[index + 1]))
        #endif
    }

    private func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let tabs = try SpreadsheetReader.read(url)
            let year = SheetImport.year(in: url.lastPathComponent) ?? Calendar.current.component(.year, from: Date())
            guard let found = SheetImport.read(tabs, fallbackYear: year), !found.rows.isEmpty else {
                failure = "No job list was found in it. The import looks for headings like Date, Customer Name and Price."
                return
            }
            preview = ImportPreview(fileName: url.lastPathComponent, sheet: found)
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let sheet: SheetImport
}

private struct ImportPreviewSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview

    @AppStorage(Beta.examplesKey) private var examplesLoaded = false
    @State private var clearExamples = true
    @State private var outcome: SheetImport.Outcome?
    @State private var saved = 0
    @AppStorage("importedSheet") private var importedSheet = false

    private var sheet: SheetImport { preview.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let outcome {
                done(outcome)
            } else {
                summary
            }
        }
        .frame(width: 640, height: 600)
        .sensoryFeedback(.success, trigger: saved)
    }

    // MARK: Before

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Import \(preview.fileName)")
                    .font(.title2.weight(.bold))
                Text("Tab \"\(sheet.tabName)\"" + dateRange)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Space.s) {
                StatTile(title: "Customers", value: "\(sheet.customerCount)", detail: "one per name and address")
                StatTile(title: "Jobs", value: "\(sheet.rows.count)", detail: Money.text(sheet.rows.compactMap(\.price).reduce(0, +)) + " in all")
                StatTile(title: "Not paid", value: "\(sheet.unpaidRows.count)",
                         detail: Money.text(sheet.unpaidRows.compactMap(\.price).reduce(0, +)) + " (red prices)",
                         tint: sheet.unpaidRows.isEmpty ? .primary : Tint.owed)
            }

            VStack(alignment: .leading, spacing: 6) {
                note("phone", "The sheet has no phone numbers. Add them as customers call.")
                if sheet.noHouseNumber > 0 { note("number", "\(Plural.text(sheet.noHouseNumber, "job")) without a house number (\"???\" or the street only).", warn: true) }
                if sheet.noAddress > 0 { note("mappin.slash", "\(Plural.text(sheet.noAddress, "job")) with no address.", warn: true) }
                if sheet.noName > 0 { note("person.fill.questionmark", "\(Plural.text(sheet.noName, "job")) with no name, saved as \"No name\".", warn: true) }
                if sheet.skipped > 0 { note("minus.circle", "\(Plural.text(sheet.skipped, "row")) left out (blank, or headings repeated).") }
                if !sheet.missingColumns.isEmpty { note("tablecells", "Not in the sheet: " + sheet.missingColumns.joined(separator: ", ") + ".") }
                note("calendar.badge.clock", "Jobs come in as Junk removal with no time. Past jobs are marked done. Nothing is added to the calendar.")
            }
            .font(.callout)

            sampleTable

            Spacer(minLength: 0)

            if examplesLoaded && !SyncEngine.shared.isSetUp {
                Toggle("Remove the example data first", isOn: $clearExamples)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(Plural.text(sheet.rows.count, "job"))") { runImport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
    }

    private var dateRange: String {
        guard let first = sheet.firstDate, let last = sheet.lastDate else { return "" }
        return " · " + Dates.shortDay(first) + " to " + Dates.shortDay(last)
    }

    private func note(_ symbol: String, _ text: String, warn: Bool = false) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(warn ? Tint.warning : .secondary)
        }
    }

    /// The first rows, as they will come in.
    private var sampleTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("First rows")
                .font(.headline)
                .padding(.bottom, Space.xs)
            Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: 4) {
                GridRow {
                    Text("Date"); Text("Customer"); Text("Address"); Text("Price"); Text("Paid")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(sheet.rows.prefix(6), id: \.line) { row in
                    GridRow {
                        Text(Dates.shortDay(row.date)).monospacedDigit()
                        Text(row.name.isEmpty ? "No name" : row.name).lineLimit(1)
                        Text(row.address.isEmpty ? "—" : row.address).lineLimit(1).foregroundStyle(.secondary)
                        Text(row.price.map(Money.text) ?? "—").monospacedDigit()
                        HStack(spacing: 4) {
                            if row.unpaid {
                                Text("Not paid").foregroundStyle(Tint.owed)
                            } else if row.payment != .unknown {
                                PaymentMark(type: row.payment, size: 14)
                                if row.payment != .venmo && row.payment != .cashApp {
                                    Text(row.payment.rawValue)
                                }
                            } else {
                                Text("Paid").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private func runImport() {
        if examplesLoaded && clearExamples && !SyncEngine.shared.isSetUp {
            SampleData.clearForImport(context: context)
            examplesLoaded = false
        }
        outcome = sheet.save(into: context)
        importedSheet = true
        saved += 1
    }

    // MARK: After

    private func done(_ outcome: SheetImport.Outcome) -> some View {
        VStack(spacing: Space.m) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Tint.paid)
            Text("Imported \(Plural.text(outcome.newCustomers, "customer")) and \(Plural.text(outcome.jobs, "job")).")
                .font(.title3.weight(.semibold))
            if outcome.existingCustomers > 0 {
                Text(outcome.existingCustomers == 1 ? "1 customer already in Ace got new jobs." : "\(outcome.existingCustomers) customers already in Ace got new jobs.")
                    .foregroundStyle(.secondary)
            }
            if outcome.alreadyThere > 0 {
                Text(outcome.alreadyThere == 1 ? "1 job was already in Ace and was left as it was." : "\(outcome.alreadyThere) jobs were already in Ace and were left as they were.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.l)
    }
}
#endif
