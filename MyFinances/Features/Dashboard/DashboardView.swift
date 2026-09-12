import SwiftUI
import SwiftData

/// The dashboard answers one question: **am I okay?**
/// If a number does not help answer it, it belongs on another screen.
struct DashboardView: View {
    @Binding var model: AppModel
    let balances: [BalanceEngine.AccountBalance]
    let transactions: [Transaction]
    let settings: AppSettings?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let lastReconciledOn: Date?
    let budgets: [Budget]
    let rules: [RecurringRule]
    let events: [ScheduledEvent]

    private var totals: BalanceEngine.Totals { BalanceEngine.totals(for: balances) }
    private var records: [BalanceEngine.TransactionRecord] { transactions.map(DataBridge.record) }
    private var week: DateInterval { calendar.weekInterval(containing: calendar.currentDate()) }
    private var spentThisWeek: Money { BalanceEngine.spend(transactions: records, in: week) }

    private var overCommitted: [BalanceEngine.AccountBalance] {
        balances.filter(\.isOverCommitted)
    }
    private var belowFloor: [BalanceEngine.AccountBalance] {
        balances.filter { $0.isBelowFloor && !$0.account.isArchived }
    }

    private var elapsed: Int { calendar.elapsedDaysInWeek(containing: calendar.currentDate()) }
    private var daysInMonth: Int { calendar.daysInMonth(containing: calendar.currentDate()) }

    private var commitments: [BudgetEngine.CommitmentInput] {
        rules.filter { $0.isCommittedOutflow && !$0.isArchived }.map(DataBridge.commitment)
    }

    /// The number actually looked at.
    private var freeToSpend: BudgetEngine.FreeToSpend {
        BudgetEngine.freeToSpend(
            expectedIncomeThisWeek: BudgetEngine.weeklyFromMonthly(
                settings?.expectedMonthlyNetIncome ?? .zero
            ),
            commitments: commitments,
            // Goal allocations arrive with M6; until then nothing is reserved for them.
            goalAllocationsThisWeek: .zero,
            alreadySpentThisWeek: spentThisWeek
        )
    }

    private var envelopeStates: [BudgetEngine.EnvelopeState] {
        budgets.map { budget in
            let ids = budget.category.map { Set([$0.id]) }
            return BudgetEngine.state(
                for: DataBridge.envelope(budget),
                spent: BalanceEngine.spend(transactions: records, in: week, categoryIDs: ids),
                elapsedDaysInWeek: elapsed,
                daysInMonth: daysInMonth
            )
        }
    }

    private var envelopesAheadOfPace: [BudgetEngine.EnvelopeState] {
        envelopeStates.filter { $0.isAheadOfPace || $0.isOverspent }
    }

    /// The 60-day forward view, summarised as one line on the dashboard.
    private var projection: ForecastEngine.Projection {
        ForecastEngine.project(
            startingBalance: totals.liquidAvailable,
            from: calendar.currentDate(),
            days: 60,
            scheduled: rules.filter { !$0.isArchived }.map(DataBridge.scheduled),
            oneOffs: events.map(DataBridge.oneOff),
            calendar: calendar
        )
    }

    private var todaysTransactions: [Transaction] {
        let today = calendar.today()
        return transactions.filter { calendar.financialDay(for: $0.date) == today }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headline
                warnings
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    weekCard
                    todayCard
                }
                accountsStrip
            }
            .padding(Theme.Space.lg)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        Card(padding: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: heroLabel)
                        Text(formatter.string(heroAmount))
                            .font(Theme.Font.hero)
                            .foregroundStyle(heroAmount.isNegative
                                             ? Theme.Palette.negative : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel(heroLabel)
                            .accessibilityValue(formatter.accessibleString(heroAmount))
                        Text(heroExplanation)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Space.sm) {
                        Button {
                            model.isQuickAddShown = true
                        } label: {
                            Label("Log a spend", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut("n", modifiers: .command)
                        if !totals.taxReserved.isZero {
                            Text("\(formatter.string(totals.taxReserved)) held in tax reserve")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider().opacity(0.4)
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    StatTile(label: "Net worth",
                             value: formatter.string(totals.netWorth),
                             detail: "Excludes the tax reserve and money lent out",
                             accessibilityValue: formatter.accessibleString(totals.netWorth))
                    StatTile(label: "Earmarked",
                             value: formatter.string(totals.earmarkedTotal),
                             detail: "Reserved for goals and funds",
                             accessibilityValue: formatter.accessibleString(totals.earmarkedTotal))
                    StatTile(label: "Spent this week",
                             value: formatter.string(spentThisWeek),
                             detail: weekDetail,
                             accessibilityValue: formatter.accessibleString(spentThisWeek))
                }
            }
        }
    }

    /// Once there are commitments to come off the top, free-to-spend is the honest
    /// headline. Before that it would just repeat the available balance.
    private var showsFreeToSpend: Bool { !commitments.isEmpty }

    private var heroLabel: String {
        showsFreeToSpend ? "Free to spend this week" : "Available to spend"
    }

    private var heroAmount: Money {
        showsFreeToSpend ? freeToSpend.amount : totals.liquidAvailable
    }

    private var heroExplanation: String {
        guard showsFreeToSpend else {
            return totals.earmarkedTotal.isZero
                ? "Liquid balances across every spendable account"
                : "Liquid balances minus what is earmarked"
        }
        return "\(formatter.string(freeToSpend.expectedIncome)) expected, less "
            + "\(formatter.string(freeToSpend.committedOutflows)) committed and "
            + "\(formatter.string(freeToSpend.alreadySpent)) already spent"
    }

    private var reconcileTitle: String {
        guard let days = BalanceEngine.daysSinceReconciliation(
            lastReconciledOn: lastReconciledOn, today: calendar.today(), calendar: calendar
        ) else { return "Nothing has been reconciled yet" }
        return "Nothing reconciled in \(days) days"
    }

    private var weekDetail: String {
        let elapsed = calendar.elapsedDaysInWeek(containing: calendar.currentDate())
        return "Day \(elapsed) of 7"
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warnings: some View {
        let needsReconcile = BalanceEngine.needsReconciliation(
            lastReconciledOn: lastReconciledOn, today: calendar.today(), calendar: calendar
        ) && !balances.isEmpty
        if !overCommitted.isEmpty || !belowFloor.isEmpty || needsReconcile
            || !envelopesAheadOfPace.isEmpty || projection.firstNegativeDay != nil {
            VStack(spacing: Theme.Space.sm) {
                ForEach(overCommitted) { entry in
                    // The invariant is surfaced, never silently rebalanced.
                    NoticeRow(
                        tone: .caution,
                        icon: "exclamationmark.triangle",
                        title: "\(entry.account.name) is over-committed",
                        detail: "\(formatter.string(entry.earmarked)) is earmarked against a "
                              + "balance of \(formatter.string(entry.balance))."
                    )
                }
                if BalanceEngine.needsReconciliation(lastReconciledOn: lastReconciledOn,
                                                     today: calendar.today(),
                                                     calendar: calendar), !balances.isEmpty {
                    NoticeRow(
                        tone: .caution,
                        icon: "checkmark.circle.badge.questionmark",
                        title: reconcileTitle,
                        detail: "Count what is actually in one account and check it against the "
                              + "ledger. Small gaps compound quietly."
                    )
                }
                if let trouble = projection.firstNegativeDay {
                    NoticeRow(
                        tone: .negative,
                        icon: "calendar.badge.exclamationmark",
                        title: "\(trouble.date.formatted(.dateTime.weekday(.wide).day().month())) "
                             + "projects below zero",
                        detail: ForecastEngine.suggestion(for: projection, formatter: formatter)
                            ?? "Open Plan to see what lands that day."
                    )
                }
                ForEach(envelopesAheadOfPace) { state in
                    NoticeRow(
                        tone: state.isOverspent ? .negative : .caution,
                        icon: "speedometer",
                        title: state.isOverspent
                            ? "\(state.name) is over budget"
                            : "\(state.name) is ahead of pace",
                        detail: "\(formatter.string(state.spent)) of "
                              + "\(formatter.string(state.budget)) on day \(elapsed) of 7."
                    )
                }
                ForEach(belowFloor) { entry in
                    NoticeRow(
                        tone: .caution,
                        icon: "arrow.down.circle",
                        title: "\(entry.account.name) is below its floor",
                        detail: "\(formatter.string(entry.balance)) against a floor of "
                              + "\(formatter.string(entry.account.lowBalanceFloor ?? .zero))."
                    )
                }
            }
        }
    }

    // MARK: - Cards

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "This week")
                Text(weekRangeText).font(Theme.Font.caption).foregroundStyle(.secondary)
                Divider().opacity(0.4)
                if envelopeStates.isEmpty {
                    Text(spentThisWeek.isZero
                         ? "Nothing logged this week yet."
                         : "\(formatter.string(spentThisWeek)) spent. Set up envelopes in Plan "
                           + "to see pace.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    ForEach(envelopeStates.sorted { ($0.paceDelta ?? 0) > ($1.paceDelta ?? 0) }
                        .prefix(5)) { state in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(state.name).font(.system(size: 11.5))
                                Spacer()
                                Text(formatter.string(state.remaining))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                            MeterBar(
                                fraction: state.burn.map {
                                    NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
                                expected: NSDecimalNumber(
                                    decimal: state.expectedFraction).doubleValue,
                                tone: state.isOverspent ? .negative
                                      : (state.isAheadOfPace ? .caution : .positive),
                                height: 5
                            )
                        }
                    }
                }
            }
        }
    }

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Today")
                    Spacer()
                    Text("\(todaysTransactions.count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().opacity(0.4)
                if todaysTransactions.isEmpty {
                    Text("Nothing logged today.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    ForEach(todaysTransactions.prefix(6)) { transaction in
                        TransactionRow(transaction: transaction, formatter: formatter,
                                       calendar: calendar, showsDate: false)
                    }
                }
            }
        }
    }

    private var weekRangeText: String {
        let start = week.start
        let end = calendar.addDays(6, to: start)
        return start.formatted(date: .abbreviated, time: .omitted)
            + " – " + end.formatted(date: .abbreviated, time: .omitted)
    }

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionLabel(text: "Accounts")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 172), spacing: Theme.Space.md)],
                spacing: Theme.Space.md
            ) {
                ForEach(balances.filter { !$0.account.isArchived }) { entry in
                    AccountTile(entry: entry, formatter: formatter) {
                        model.selectedAccountID = entry.account.id
                        model.isInspectorShown = true
                    }
                }
            }
        }
    }
}

struct NoticeRow: View {
    let tone: StatTile.Tone
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon).foregroundStyle(tone.color).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
