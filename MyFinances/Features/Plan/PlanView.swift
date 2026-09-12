import SwiftUI
import SwiftData

/// Envelopes and their burn meters. Weekly is the unit that matters.
struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let transactions: [Transaction]
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil })
    private var budgets: [Budget]
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil })
    private var rules: [RecurringRule]

    @State private var editingBudgetID: UUID?
    @State private var isCreatingEnvelope = false

    private var week: DateInterval { calendar.weekInterval(containing: calendar.currentDate()) }
    private var previousWeek: DateInterval {
        calendar.weekInterval(containing: calendar.addDays(-7, to: calendar.currentDate()))
    }
    private var elapsed: Int { calendar.elapsedDaysInWeek(containing: calendar.currentDate()) }
    private var daysInMonth: Int { calendar.daysInMonth(containing: calendar.currentDate()) }
    private var records: [BalanceEngine.TransactionRecord] { transactions.map(DataBridge.record) }

    /// Miscellaneous sorts last but renders as a first-class card, because that is
    /// where discipline actually breaks.
    private var states: [BudgetEngine.EnvelopeState] {
        budgets
            .map { budget in
                BudgetEngine.state(
                    for: DataBridge.envelope(budget, carriedIn: carriedIn(for: budget)),
                    spent: spent(for: budget, in: week),
                    elapsedDaysInWeek: elapsed,
                    daysInMonth: daysInMonth
                )
            }
            .sorted { a, b in
                if a.input.isMiscellaneous != b.input.isMiscellaneous {
                    return !a.input.isMiscellaneous
                }
                return a.name < b.name
            }
    }

    private func spent(for budget: Budget, in interval: DateInterval) -> Money {
        let ids = budget.category.map { Set([$0.id]) }
        return BalanceEngine.spend(transactions: records, in: interval, categoryIDs: ids)
    }

    /// Last week's unspent budget, which rollover may carry forward (capped).
    private func carriedIn(for budget: Budget) -> Money {
        guard budget.rollover else { return .zero }
        let base = BudgetEngine.weeklyBudget(
            for: DataBridge.envelope(budget), daysInMonth: daysInMonth
        )
        return (base - spent(for: budget, in: previousWeek)).clampedToZero
    }

    private var commitments: [BudgetEngine.CommitmentInput] {
        rules.filter { $0.isCommittedOutflow && !$0.isArchived }.map(DataBridge.commitment)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if states.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: "No envelopes yet",
                        message: "An envelope is a weekly number for one kind of spending. "
                               + "Start with the three you actually lose money on, and give "
                               + "Miscellaneous a real number too.",
                        actionTitle: "Create an envelope",
                        action: { isCreatingEnvelope = true }
                    )
                } else {
                    header
                    ForEach(states) { state in
                        EnvelopeCard(state: state, formatter: formatter) {
                            editingBudgetID = state.id
                        }
                    }
                    commitmentsCard
                }
            }
            .padding(Theme.Space.lg)
        }
        .sheet(isPresented: $isCreatingEnvelope) {
            EnvelopeEditor(editingID: nil, formatter: formatter)
        }
        .sheet(item: Binding(
            get: { editingBudgetID.map { IdentifiedID(id: $0) } },
            set: { editingBudgetID = $0?.id }
        )) { wrapper in
            EnvelopeEditor(editingID: wrapper.id, formatter: formatter)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Week of \(week.start.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.Font.title)
                Text("Day \(elapsed) of 7")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isCreatingEnvelope = true
            } label: {
                Label("New envelope", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    private var commitmentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Committed this week")
                if commitments.isEmpty {
                    Text("No committed outflows yet. Recurring bills, loan payments and "
                         + "investments come off the top before anything is called free — "
                         + "they arrive with M4.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(commitments) { commitment in
                        HStack {
                            Text(commitment.label).font(.system(size: 12))
                            Spacer()
                            Text(formatter.string(
                                commitment.amount.scaled(
                                    by: Decimal(commitment.occurrencesPerYear) / Decimal(52)
                                )
                            ))
                            .font(Theme.Font.amount).foregroundStyle(.secondary)
                        }
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("Total").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(formatter.string(BudgetEngine.weeklyCommitted(commitments)))
                            .font(Theme.Font.amount)
                    }
                }
            }
        }
    }
}

/// A `UUID` that can drive `.sheet(item:)`.
struct IdentifiedID: Identifiable, Hashable {
    let id: UUID
}

struct EnvelopeCard: View {
    let state: BudgetEngine.EnvelopeState
    let formatter: MoneyFormatter
    let onEdit: () -> Void

    private var tone: StatTile.Tone {
        if state.isOverspent { return .negative }
        if state.isAheadOfPace { return .caution }
        return .positive
    }

    private var burnFraction: Double {
        guard let burn = state.burn else { return 0 }
        return NSDecimalNumber(decimal: burn).doubleValue
    }

    private var expectedFraction: Double {
        NSDecimalNumber(decimal: state.expectedFraction).doubleValue
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: state.input.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: state.input.colorHex))
                    Text(state.name).font(.system(size: 13, weight: .medium))
                    if state.input.isMiscellaneous { Pill(text: "catch-all") }
                    if state.input.rollover { Pill(text: "rolls over") }
                    Spacer()
                    Text("\(formatter.string(state.spent)) of \(formatter.string(state.budget))")
                        .font(Theme.Font.amount)
                        .foregroundStyle(.secondary)
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Edit this envelope")
                }

                MeterBar(fraction: burnFraction, expected: expectedFraction, tone: tone, height: 8)

                HStack {
                    Text(statusText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(state.isAheadOfPace || state.isOverspent
                                         ? tone.color : .secondary)
                    Spacer()
                    Text(state.isOverspent
                         ? "\(formatter.string(state.remaining.magnitude)) over"
                         : "\(formatter.string(state.remaining)) left")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.name)
        .accessibilityValue(
            "\(formatter.accessibleString(state.spent)) spent of "
            + "\(formatter.accessibleString(state.budget)). \(statusText)"
        )
    }

    /// Neutral language. "Ahead of pace", never "you failed".
    private var statusText: String {
        if state.isOverspent { return "Over budget for the week" }
        if state.isAheadOfPace { return "Ahead of pace for this point in the week" }
        if state.budget.isZero { return "No budget set" }
        return "On pace"
    }
}
