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
    let loans: [Loan]
    let goals: [Goal]
    let earmarks: [Earmark]
    let ladder: LadderEngine.Evaluation
    let advisorPosition: AdvisorEngine.Position
    let unallocatedWindfalls: [IncomeEvent]
    let creep: IncomeEngine.CreepVerdict
    let salaryCheck: IncomeEngine.SalaryCheck
    let investments: InvestmentEngine.Summary
    let streaks: InsightsEngine.StreakSummary
    let microSpendThisMonth: Money

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
            oneOffs: events.map { DataBridge.oneOff($0, maybeWeight: maybeEventWeight) },
            calendar: calendar
        )
    }

    // MARK: - Module summaries

    private var maybeEventWeight: Decimal {
        settings?.maybeEventWeight ?? Decimal(string: "0.5")!
    }

    private var debtPositions: [LoanEngine.Position] {
        loans.filter { $0.status != .planned }
            .map { LoanEngine.position(for: DataBridge.loan($0), calendar: calendar) }
    }

    private var owedPositions: [LoanEngine.Position] {
        debtPositions.filter { $0.loan.direction == .iOwe && !$0.isPaidOff }
    }

    private var totalOwed: Money { Money.sum(owedPositions.map(\.remainingBalance)) }

    private var debtServiceRatio: Decimal? {
        guard let income = settings?.expectedMonthlyNetIncome, income.isPositive,
              !owedPositions.isEmpty else { return nil }
        let monthly = Money.sum(owedPositions.map {
            LoanEngine.monthlyEquivalent($0.regularPayment, frequency: $0.loan.paymentFrequency)
        })
        return monthly.ratio(to: income)
    }

    private var toxicLoans: [LoanEngine.Position] {
        let threshold = settings?.highInterestThresholdAPR ?? Decimal(string: "0.25")!
        return owedPositions.filter { $0.isToxic(highInterestThreshold: threshold) }
    }

    private var goalInputs: [GoalEngine.GoalInput] {
        goals.map { DataBridge.goal($0, earmarks: earmarks) }
    }

    private var goalETAs: [GoalEngine.ETA] {
        GoalEngine.etas(
            surplusPerPeriod: freeToSpend.amount.clampedToZero,
            ladderRequirement: .none, funds: [], goals: goalInputs,
            periodLength: .weekly, from: calendar.today(), calendar: calendar
        )
    }

    /// The top-priority goal still being saved for.
    private var nextGoal: GoalEngine.GoalInput? {
        goalInputs.filter { $0.status == .saving && !$0.isFunded }
            .min { $0.priorityRank < $1.priorityRank }
    }

    /// Every module gets one figure here. Only real problems become notices above.
    private var moduleItems: [ModuleStrip.Item] {
        var items: [ModuleStrip.Item] = []

        items.append(ModuleStrip.Item(
            id: "networth", screen: .accounts, label: "Net worth",
            value: formatter.string(totals.netWorth),
            detail: totals.taxReserved.isZero
                ? "Across every account you own"
                : "\(formatter.string(totals.taxReserved)) held separately for tax",
            tone: .neutral,
            accessibleValue: formatter.accessibleString(totals.netWorth)
        ))

        items.append(ModuleStrip.Item(
            id: "week", screen: .plan, label: "Spent this week",
            value: formatter.string(spentThisWeek),
            detail: envelopeStates.isEmpty
                ? "Day \(elapsed) of 7 · no envelopes set"
                : "Day \(elapsed) of 7 · \(envelopesAheadOfPace.count) ahead of pace",
            tone: envelopesAheadOfPace.isEmpty ? .neutral : .caution,
            accessibleValue: formatter.accessibleString(spentThisWeek)
        ))

        if !commitments.isEmpty || projection.hasTrouble {
            let trouble = projection.firstNegativeDay
            items.append(ModuleStrip.Item(
                id: "forecast", screen: .plan, label: "60-day low",
                value: formatter.string(projection.lowestDay?.closingBalance
                                        ?? totals.liquidAvailable),
                detail: trouble.map {
                    "Goes negative on "
                    + $0.date.formatted(.dateTime.day().month(.abbreviated))
                } ?? "Stays in credit the whole way",
                tone: trouble == nil ? .positive : .negative,
                accessibleValue: formatter.accessibleString(
                    projection.lowestDay?.closingBalance ?? totals.liquidAvailable)
            ))
        }

        if !owedPositions.isEmpty {
            items.append(ModuleStrip.Item(
                id: "debt", screen: .debt, label: "Owed",
                value: formatter.string(totalOwed),
                detail: debtServiceRatio.map {
                    "\(percentText($0)) of income goes to debt"
                } ?? "\(owedPositions.count) active",
                tone: debtTone,
                accessibleValue: formatter.accessibleString(totalOwed)
            ))
        }

        if let goal = nextGoal {
            let eta = goalETAs.first { $0.goalID == goal.id }
            items.append(ModuleStrip.Item(
                id: "goal", screen: .goals, label: "Next: \(goal.name)",
                value: formatter.string(goal.saved),
                detail: eta?.date.map {
                    "of \(formatter.string(goal.targetAmount)) · "
                    + $0.formatted(.dateTime.day().month(.abbreviated))
                } ?? "of \(formatter.string(goal.targetAmount)) · nothing going in yet",
                tone: eta?.isReachable == true ? .positive : .neutral,
                accessibleValue: formatter.accessibleString(goal.saved)
            ))
        }

        if !unallocatedWindfalls.isEmpty {
            let total = Money.sum(unallocatedWindfalls.map(\.netUsable))
            items.append(ModuleStrip.Item(
                id: "windfall", screen: .income, label: "Waiting to allocate",
                value: formatter.string(total),
                detail: "\(unallocatedWindfalls.count) inflow(s) held out of spendable balance",
                tone: .caution,
                accessibleValue: formatter.accessibleString(total)
            ))
        }

        items.append(ModuleStrip.Item(
            id: "advisor", screen: .advisor, label: "Next money goes to",
            value: "\(advisorPosition.step.rawValue)",
            detail: advisorPosition.step.title,
            tone: .neutral,
            accessibleValue: "step \(advisorPosition.step.rawValue), "
                           + advisorPosition.step.title
        ))

        if !investments.holdings.isEmpty {
            let stale = investments.needingValuation(today: calendar.today(),
                                                     calendar: calendar)
            items.append(ModuleStrip.Item(
                id: "investments", screen: .investments, label: "Invested",
                value: formatter.string(investments.totalValue),
                detail: stale.isEmpty
                    ? "\(formatter.string(investments.totalContributed)) put in"
                    : "\(stale.count) holding(s) need a fresh value",
                tone: stale.isEmpty ? .neutral : .caution,
                accessibleValue: formatter.accessibleString(investments.totalValue)
            ))
        }

        items.append(ModuleStrip.Item(
            id: "ladder", screen: .ladder, label: "Stability",
            value: "\(ladder.stabilityScore.total)",
            detail: "\(ladder.currentStage.title) · stage "
                  + "\(ladder.currentStage.rawValue) of 7",
            tone: scoreTone,
            accessibleValue: "\(ladder.stabilityScore.total) out of 100"
        ))

        if let runway = ladder.runwayMonths {
            let tenths = Money.roundBankers(runway * 10)
            items.append(ModuleStrip.Item(
                id: "runway", screen: .ladder, label: "Runway",
                value: "\(tenths / 10).\(abs(tenths % 10)) mo",
                detail: "of essential spend covered by what is liquid",
                tone: runway < 1 ? .negative : (runway < 3 ? .caution : .positive),
                accessibleValue: "\(tenths / 10) point \(abs(tenths % 10)) months"
            ))
        }

        items.append(ModuleStrip.Item(
            id: "insights", screen: .insights, label: "Logging streak",
            value: streaks.current == 0 ? "—" : "\(streaks.current)d",
            detail: microSpendThisMonth.isZero
                ? "Longest \(streaks.longest) days"
                : "\(formatter.string(microSpendThisMonth)) on small, frequent spending "
                  + "this month",
            tone: streaks.current > 0 ? .positive : .neutral,
            accessibleValue: "\(streaks.current) day streak"
        ))

        return items
    }

    private var salaryCheckTitle: String {
        switch salaryCheck.status {
        case .more:
            return "\(formatter.string(salaryCheck.difference.magnitude)) more pay arrived "
                 + "than expected"
        case .less:
            return "\(formatter.string(salaryCheck.difference.magnitude)) less pay arrived "
                 + "than expected"
        case .nothingReceived:
            return "Pay day has passed with no income logged"
        default:
            return "Check this month's pay"
        }
    }

    private var scoreTone: StatTile.Tone {
        let total = ladder.stabilityScore.total
        if total >= 70 { return .positive }
        if total >= 40 { return .caution }
        return .negative
    }

    private var debtTone: StatTile.Tone {
        if !toxicLoans.isEmpty { return .negative }
        guard let ratio = debtServiceRatio else { return .neutral }
        if ratio > (settings?.maxDebtServiceRatio ?? Decimal(string: "0.30")!) { return .negative }
        if ratio > Decimal(string: "0.15")! { return .caution }
        return .neutral
    }

    private func percentText(_ value: Decimal) -> String {
        let scaled = Money.roundBankers(value * 10_000)
        return "\(scaled / 100)%"
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
                nextActionCard
                if !moduleItems.isEmpty {
                    ModuleStrip(items: moduleItems) { screen in model.open(screen) }
                }
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
            || !envelopesAheadOfPace.isEmpty || projection.firstNegativeDay != nil
            || !toxicLoans.isEmpty || !unallocatedWindfalls.isEmpty || creep.isCreeping
            || salaryCheck.needsConfirmation
            || !investments.needingValuation(today: calendar.today(),
                                             calendar: calendar).isEmpty {
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
                if let stale = investments.needingValuation(today: calendar.today(),
                                                            calendar: calendar).first {
                    NoticeRow(
                        tone: .caution,
                        icon: "questionmark.circle",
                        title: "What is \(stale.name) worth now?",
                        detail: stale.valuedOn == nil
                            ? "No value has been entered yet. Check your statement and put "
                              + "the figure in — the app cannot look it up."
                            : "It has been a month since you last checked."
                    )
                }
                if salaryCheck.needsConfirmation {
                    NoticeRow(
                        tone: salaryCheck.isRise ? .positive : .caution,
                        icon: "questionmark.circle",
                        title: salaryCheckTitle,
                        detail: "Open Income to confirm it. Everything that reads your income "
                              + "works from this number."
                    )
                }
                if !unallocatedWindfalls.isEmpty {
                    let total = Money.sum(unallocatedWindfalls.map(\.netUsable))
                    NoticeRow(
                        tone: .caution,
                        icon: "tray.and.arrow.down",
                        title: "\(formatter.string(total)) is waiting to be allocated",
                        detail: "It is deliberately not part of your spendable balance until "
                              + "you decide where it goes."
                    )
                }
                if creep.isCreeping {
                    NoticeRow(
                        tone: .caution,
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Essentials are taking a growing share of income",
                        detail: creep.drivers.isEmpty
                            ? "Two consecutive quarters of increase."
                            : "Two consecutive quarters of increase, mostly in "
                              + creep.drivers.joined(separator: " and ") + "."
                    )
                }
                if let toxic = toxicLoans.first {
                    NoticeRow(
                        tone: .negative,
                        icon: "flame",
                        title: "\(toxic.loan.name) is the one to clear first",
                        detail: toxic.loan.socialWeight >= 4
                            ? "\(formatter.string(toxic.remainingBalance)) owed to someone you "
                              + "know. That costs more than interest does."
                            : "\(formatter.string(toxic.remainingBalance)) at "
                              + "\(percentText(toxic.loan.annualRate)) — above your "
                              + "high-interest line."
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

    /// One recommended action. Never a to-do list of financial obligations.
    private var nextActionCard: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Next")
                    Text(ladder.nextAction.title).font(.system(size: 14, weight: .medium))
                    Text(ladder.nextAction.detail)
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Go") { model.open(ladder.nextAction.screen) }
                    .controlSize(.small)
            }
        }
    }

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
