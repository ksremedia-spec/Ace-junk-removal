import SwiftData
import SwiftUI

/// One action from the plan, on the screen that confirms it. A reference in
/// the action (C4, J12, D3) wins over matching what was said; see
/// docs/assistant-actions.md, "Finding the record".
struct AssistantStepView: View {
    let action: AssistantAction
    /// The plan's questions for this action only.
    let issues: [PlanIssue]
    let refs: RecordRefs
    let customers: [Customer]
    let jobs: [Job]
    let dumpsters: [Dumpster]
    /// Called after a save with the confirmation ("Job saved."), or with an
    /// empty string when nothing was saved (Done on the contact screen).
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void
    /// Turns this step into a new job, for "Start a new job instead".
    var onStartNewJob: () -> Void

    var body: some View {
        switch action.kind ?? .newJob {
        case .newJob: newJob
        case .updateJob: updateJob
        case .cancelJob: cancelJob
        case .newCustomer: newCustomer
        case .updateCustomer: updateCustomer
        case .contactCustomer: contactCustomer
        case .dumpsterDropoff: dropoff
        case .dumpsterPickup: pickup
        case .dumpsterSwap: swapDumpsters
        case .updateRental: updateRental
        case .dumpsterNote: dumpsterNote
        }
    }

    // MARK: References

    /// A job reference, while that job is still on the books.
    private var refJob: Job? { refs.job(action.ref, among: jobs) }

    /// The customer a reference means: the customer, the job's customer, or
    /// the customer a dumpster is out with.
    private var refCustomer: Customer? { refs.customerMeant(by: action.ref, jobs: jobs) }

    private var refDumpster: Dumpster? { refs.dumpster(action.ref) }

    /// The action in the form the older screens take. A dumpster reference
    /// wins over a spoken number.
    private var draft: JobDraft {
        var draft = action.jobDraft(issues: issues)
        if let refDumpster { draft.dumpsterNumber = String(refDumpster.number) }
        return draft
    }

    /// Who or what the note named, for "No customer found for …".
    private var subject: String {
        if let refCustomer { return refCustomer.name }
        for said in [action.customerName, action.phone, action.address] {
            let trimmed = said.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "that"
    }

    /// Why no dumpster that is out could be found.
    private var noOutDumpster: String {
        if let number = Int(draft.dumpsterNumber.filter(\.isNumber)) {
            if dumpsters.contains(where: { $0.number == number }) { return "Dumpster \(number) is in the yard." }
            return "There is no Dumpster \(number)."
        }
        let address = action.address.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty { return "No dumpster is out at \(address)." }
        let name = refCustomer?.name ?? action.customerName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return "No dumpster is out at \(name)'s." }
        return "No dumpster is out."
    }

    private var customerCandidates: [Customer] {
        findCustomers(draft, refCustomer: refCustomer, customers: customers)
    }

    private var outDumpsterCandidates: [Dumpster] {
        findOutDumpsters(draft, refDumpster: refDumpster, refCustomer: refCustomer, dumpsters: dumpsters)
    }

    // MARK: Jobs

    private var newJob: some View {
        let customer = refCustomer
        var prefilled = draft
        if let customer {
            prefilled.customerName = customer.name
            if prefilled.phone.isEmpty { prefilled.phone = customer.phone }
            if prefilled.address.isEmpty { prefilled.address = customer.address }
        }
        return JobReviewView(
            draft: prefilled,
            knownCustomer: customer,
            onSaved: { onFinish("Job saved.") },
            onStartOver: onStartOver
        )
    }

    private var updateJob: some View {
        let job = refJob
        return JobUpdateView(
            draft: draft,
            customers: customers,
            jobs: jobs,
            refJob: job,
            refCustomer: job == nil ? refCustomer : nil,
            onSaved: { onFinish("Job saved.") },
            onStartOver: onStartOver,
            onStartNewJob: onStartNewJob
        )
    }

    private var cancelJob: some View {
        let job = refJob
        let candidates = findJobs(
            draft,
            refJob: job,
            refCustomer: job == nil ? refCustomer : nil,
            customers: customers,
            jobs: jobs,
            today: Dates.startOfToday()
        )
        return CancelJobView(
            candidates: candidates,
            subject: subject,
            issues: issues,
            onFinish: onFinish,
            onSkip: onSkip,
            onStartOver: onStartOver
        )
    }

    // MARK: Customers

    private var newCustomer: some View {
        NewCustomerView(
            action: action,
            issues: issues,
            customers: customers,
            onFinish: onFinish,
            onStartOver: onStartOver
        )
    }

    private var updateCustomer: some View {
        UpdateCustomerView(
            action: action,
            issues: issues,
            candidates: customerCandidates,
            customers: customers,
            subject: subject,
            onFinish: onFinish,
            onSkip: onSkip,
            onStartOver: onStartOver
        )
    }

    private var contactCustomer: some View {
        ContactCustomerView(
            action: action,
            issues: issues,
            candidates: customerCandidates,
            subject: subject,
            onFinish: onFinish,
            onSkip: onSkip,
            onStartOver: onStartOver
        )
    }

    // MARK: Dumpsters

    private var dropoff: some View {
        DumpsterDropoffView(
            draft: draft,
            customers: customers,
            dumpsters: dumpsters,
            refCustomer: refCustomer,
            onSaved: onFinish,
            onStartOver: onStartOver
        )
    }

    private var pickup: some View {
        let dumpster = refDumpster
        return DumpsterPickupView(
            draft: draft,
            dumpsters: dumpsters,
            refDumpster: dumpster,
            refCustomer: dumpster == nil ? refCustomer : nil,
            onSaved: onFinish,
            onStartOver: onStartOver,
            onDone: onSkip
        )
    }

    private var swapDumpsters: some View {
        DumpsterSwapView(
            action: action,
            issues: issues,
            candidates: outDumpsterCandidates,
            dumpsters: dumpsters,
            notFoundMessage: noOutDumpster,
            onFinish: onFinish,
            onSkip: onSkip,
            onStartOver: onStartOver
        )
    }

    private var updateRental: some View {
        UpdateRentalView(
            action: action,
            issues: issues,
            candidates: outDumpsterCandidates,
            notFoundMessage: noOutDumpster,
            onFinish: onFinish,
            onSkip: onSkip,
            onStartOver: onStartOver
        )
    }

    private var dumpsterNote: some View {
        DumpsterNoteView(
            action: action,
            issues: issues,
            dumpsters: dumpsters,
            preselected: refDumpster?.number ?? Int(action.dumpsterNumber.filter(\.isNumber)),
            onFinish: onFinish,
            onStartOver: onStartOver
        )
    }
}
