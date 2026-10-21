import SwiftData
import SwiftUI

/// Prices given that are not booked yet, with the ones to call back on top,
/// and the booked and lost ones under the other two choices. Search works
/// across all three.
struct QuotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]

    /// Open, Booked or Lost. Held by the tab bar, so the Today screen can
    /// open this list on Open.
    @Binding var filter: QuoteStatus
    @State private var searchText = ""
    @State private var showingNewQuote = false
    @State private var quoteToBook: Quote?
    /// "Quote marked lost." and the like, shown under the switch for a moment.
    @State private var notice: String?
    @State private var changed = 0
    /// A quote swiped as lost, waiting for "Mark this quote lost?".
    @State private var pendingLost: Quote?

    private var filtered: [Quote] { QuoteSearch.filter(quotes, searchText) }
    private var shown: [Quote] { QuoteList.shown(filtered, status: filter) }
    private var followUp: [Quote] { QuoteList.followUp(shown) }
    private var waiting: [Quote] { QuoteList.waiting(shown) }
    /// Lost quotes are on no list, but a search finds them, as the Mark lost
    /// question promises (Oct 20 phone audit: the phone never showed them).
    private var lostMatches: [Quote] {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty ? [] : QuoteList.shown(filtered, status: .lost)
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(QuoteStatus.listed) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                if let header = QuoteList.header(shown, status: filter) {
                    Text(header)
                }
            } footer: {
                if let notice {
                    Text(notice)
                }
            }

            switch filter {
            case .open:
                if !followUp.isEmpty {
                    Section("Follow up") {
                        ForEach(followUp) { quote in
                            row(quote)
                        }
                    }
                }
                if !waiting.isEmpty {
                    Section {
                        ForEach(waiting) { quote in
                            row(quote)
                        }
                    } header: {
                        if QuoteFeatures.followUps {
                            Text("Waiting")
                        }
                    }
                }
            case .booked, .lost:
                if !shown.isEmpty {
                    Section {
                        ForEach(shown) { quote in
                            row(quote)
                        }
                    }
                }
            }

            if !lostMatches.isEmpty {
                Section("Lost") {
                    ForEach(lostMatches) { quote in
                        row(quote)
                    }
                }
            }

            if shown.isEmpty && lostMatches.isEmpty {
                Section {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Quotes")
        .confirmationDialog("Mark this quote lost?",
                            isPresented: Binding(get: { pendingLost != nil }, set: { if !$0 { pendingLost = nil } }),
                            titleVisibility: .visible, presenting: pendingLost) { quote in
            Button("Mark lost") {
                markLost(quote)
                pendingLost = nil
            }
        } message: { _ in
            Text("It leaves the Quotes list. Search still finds it, and Reopen brings it back.")
        }
        .navigationDestination(for: Quote.self) { quote in
            QuoteEditView(quote: quote, onSaved: { _ in showNotice("Quote saved.") })
        }
        .searchable(text: $searchText, prompt: "Name, phone, address or details")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewQuote = true
                } label: {
                    Label("New quote", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewQuote) {
            NavigationStack {
                QuoteEditView(quote: nil, onSaved: { _ in showNotice("Quote saved.") })
            }
        }
        .sheet(item: $quoteToBook) { quote in
            NavigationStack {
                JobEditView(job: nil, prefill: QuoteFormData(quote: quote).newJobForm, onSaved: { job in
                    book(quote, with: job)
                })
            }
        }
        .sensoryFeedback(.success, trigger: changed)
    }

    private var emptyText: String {
        searchText.isEmpty ? "No \(filter.rawValue.lowercased()) quotes." : "No matching quotes."
    }

    /// Opened by value rather than by a destination, so the form stays open
    /// when Mark Lost or Reopen moves the quote off this list.
    private func row(_ quote: Quote) -> some View {
        NavigationLink(value: quote) {
            // The Booked list is all booked: no pill on every row.
            QuoteRow(quote: quote, showStatus: filter != .booked)
        }
        .swipeActions(edge: .leading) {
            if quote.status == .open {
                Button {
                    quoteToBook = quote
                } label: {
                    Label("Book", systemImage: "calendar.badge.plus")
                }
                .tint(.green)
            } else {
                Button {
                    reopen(quote)
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if quote.status == .open {
                Button {
                    pendingLost = quote
                } label: {
                    Label("Lost", systemImage: "xmark")
                }
                .tint(.gray)
            }
        }
    }

    // MARK: Actions

    private func markLost(_ quote: Quote) {
        quote.markLost()
        try? context.save()
        changed += 1
        showNotice("Quote marked lost.")
    }

    private func reopen(_ quote: Quote) {
        quote.reopen()
        try? context.save()
        changed += 1
        showNotice("Quote reopened.")
    }

    /// The New Job form opened by Book was saved. It gives its own haptic.
    private func book(_ quote: Quote, with job: Job) {
        quote.markBooked(with: job)
        try? context.save()
        showNotice("Job saved.")
    }

    private func showNotice(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if notice == text { notice = nil }
        }
    }
}
