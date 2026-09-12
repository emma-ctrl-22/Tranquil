import SwiftUI
import SwiftData

/// One window. Sidebar on the left, content in the middle, an inspector panel on the
/// right, and sheets for entry. Everything is reachable from the keyboard.
struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @State private var model = AppModel()

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil },
           sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]
    @Query(filter: #Predicate<DailyLog> { $0.deletedAt == nil },
           sort: \DailyLog.date, order: .reverse)
    private var dailyLogs: [DailyLog]
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil })
    private var budgets: [Budget]
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil })
    private var rules: [RecurringRule]
    @Query(filter: #Predicate<ScheduledEvent> { $0.deletedAt == nil })
    private var events: [ScheduledEvent]
    @Query(filter: #Predicate<Loan> { $0.deletedAt == nil })
    private var loans: [Loan]
    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil }, sort: \Goal.priorityRank)
    private var goals: [Goal]
    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil })
    private var funds: [SinkingFund]
    @Query(filter: #Predicate<OverrideLog> { $0.deletedAt == nil })
    private var overrides: [OverrideLog]
    @Query(filter: #Predicate<IncomeEvent> { $0.deletedAt == nil })
    private var incomeEvents: [IncomeEvent]
    @Query private var settingsRows: [AppSettings]

    private var settings: AppSettings? { settingsRows.first }
    private var formatter: MoneyFormatter { settings?.formatter ?? MoneyFormatter(currency: .ghs) }
    private var calendar: FinancialCalendar { settings?.calendar ?? FinancialCalendar() }

    private var balances: [BalanceEngine.AccountBalance] {
        BalanceEngine.balances(
            accounts: accounts.map(DataBridge.record),
            transactions: transactions.map(DataBridge.record),
            earmarks: earmarks.map(DataBridge.record)
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: $model, formatter: formatter, totals: BalanceEngine.totals(for: balances))
                .navigationSplitViewColumnWidth(min: 196, ideal: 214, max: 260)
        } detail: {
            content
                .background(Theme.Palette.canvas(scheme))
                .toolbar { toolbarItems }
                .inspector(isPresented: $model.isInspectorShown) {
                    InspectorPanel(model: $model, balances: balances,
                                   transactions: transactions, formatter: formatter,
                                   calendar: calendar)
                        .inspectorColumnWidth(min: 240, ideal: 288, max: 360)
                }
        }
        .frame(minWidth: 980, minHeight: 620)
        .sheet(isPresented: $model.isQuickAddShown) {
            QuickAddSheet(model: $model, formatter: formatter, calendar: calendar)
        }
        .sheet(isPresented: $model.isTransferShown) {
            TransferSheet(formatter: formatter, calendar: calendar)
        }
        .sheet(isPresented: $model.isAccountEditorShown) {
            AccountEditor(editingID: model.editingAccountID, formatter: formatter)
        }
        .sheet(item: Binding(
            get: { model.reconcilingAccountID.flatMap { id in balances.first { $0.account.id == id } } },
            set: { model.reconcilingAccountID = $0?.account.id }
        )) { entry in
            ReconcileSheet(entry: entry, formatter: formatter, calendar: calendar)
        }
        .task { bootstrapIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .dashboard:
            DashboardView(model: $model, balances: balances, transactions: transactions,
                          settings: settings, formatter: formatter, calendar: calendar,
                          lastReconciledOn: lastReconciledOn,
                          budgets: budgets, rules: rules, events: events,
                          loans: loans, goals: goals, earmarks: earmarks,
                          ladder: ladderEvaluation,
                          advisorPosition: AdvisorEngine.position(advisorSituation),
                          unallocatedWindfalls: incomeEvents.filter { $0.status == .unallocated },
                          creep: creepVerdict)
        case .accounts:
            AccountsView(model: $model, balances: balances, formatter: formatter)
        case .ledger:
            LedgerView(model: $model, transactions: transactions,
                       formatter: formatter, calendar: calendar)
        case .plan:
            PlanView(model: $model, transactions: transactions,
                     formatter: formatter, calendar: calendar)
        case .debt:
            DebtView(model: $model, formatter: formatter, calendar: calendar,
                     settings: settings)
        case .goals:
            GoalsView(model: $model, formatter: formatter, calendar: calendar,
                      settings: settings, weeklySurplus: weeklySurplus)
        case .ladder:
            LadderView(model: $model, evaluation: ladderEvaluation,
                       snapshot: ladderSnapshot, formatter: formatter)
        case .review:
            ReviewView(weekly: weeklyReview, monthly: monthlyReview, formatter: formatter)
        case .income:
            IncomeView(model: $model, formatter: formatter, calendar: calendar,
                       settings: settings, creep: creepVerdict, taxReserved: taxReserved)
        case .advisor:
            AdvisorView(model: $model, situation: advisorSituation,
                        letter: monthlyLetter, formatter: formatter)
        default:
            ComingSoonView(screen: model.screen)
        }
    }

    /// Everything the Ladder needs, gathered once.
    private var ladderSources: LadderSnapshotBuilder.Sources {
        LadderSnapshotBuilder.Sources(
            accounts: accounts, transactions: transactions, earmarks: earmarks,
            budgets: budgets, rules: rules, events: events, loans: loans,
            funds: funds, dailyLogs: dailyLogs, settings: settings
        )
    }

    private var ladderSnapshot: LadderEngine.Snapshot {
        LadderSnapshotBuilder.build(from: ladderSources, calendar: calendar)
    }

    private var ladderEvaluation: LadderEngine.Evaluation {
        LadderEngine.evaluate(ladderSnapshot)
    }

    /// What is left each week after commitments and what has already been spent.
    /// The goal waterfall flows from this.
    private var weeklySurplus: Money {
        BudgetEngine.freeToSpend(
            expectedIncomeThisWeek: BudgetEngine.weeklyFromMonthly(
                settings?.expectedMonthlyNetIncome ?? .zero
            ),
            commitments: rules.filter { $0.isCommittedOutflow && !$0.isArchived }
                .map(DataBridge.commitment),
            goalAllocationsThisWeek: .zero,
            alreadySpentThisWeek: BalanceEngine.spend(
                transactions: transactions.map(DataBridge.record),
                in: calendar.weekInterval(containing: calendar.currentDate())
            )
        ).amount.clampedToZero
    }

    /// The most recent financial day on which any account was reconciled.
    private var lastReconciledOn: Date? {
        dailyLogs.first { $0.wasReconciled }?.date
    }

    // MARK: - Income and advisor

    private var taxReserved: Money {
        BalanceEngine.totals(for: balances).taxReserved
    }

    /// Essential spend against net income, month by month, for 24 months.
    private var creepVerdict: IncomeEngine.CreepVerdict {
        let records = transactions.map(DataBridge.record)
        let essentialIDs = Set(
            transactions.compactMap(\.category).filter(\.isEssential).map(\.id)
        )
        let today = calendar.today()
        var points: [IncomeEngine.CreepPoint] = []
        for offset in stride(from: 23, through: 0, by: -1) {
            let monthStart = calendar.addMonths(-offset, to: today)
            let interval = DateInterval(start: monthStart,
                                        end: calendar.addMonths(1, to: monthStart))
            points.append(IncomeEngine.CreepPoint(
                monthStart: monthStart,
                essentialSpend: BalanceEngine.spend(transactions: records, in: interval,
                                                    categoryIDs: essentialIDs),
                netIncome: BalanceEngine.income(transactions: records, in: interval)
            ))
        }
        // Name the essential categories that grew most over the last quarter.
        let drivers = topEssentialCategories(records: records, essentialIDs: essentialIDs)
        return IncomeEngine.creep(points: points, drivers: drivers)
    }

    private func topEssentialCategories(
        records: [BalanceEngine.TransactionRecord], essentialIDs: Set<UUID>
    ) -> [String] {
        let today = calendar.today()
        let recent = DateInterval(start: calendar.addMonths(-3, to: today),
                                  end: calendar.addMonths(1, to: today))
        let earlier = DateInterval(start: calendar.addMonths(-6, to: today),
                                   end: calendar.addMonths(-3, to: today))
        var growth: [(name: String, delta: Int)] = []
        for category in transactions.compactMap(\.category) where essentialIDs.contains(category.id) {
            guard !growth.contains(where: { $0.name == category.name }) else { continue }
            let ids: Set<UUID> = [category.id]
            let now = BalanceEngine.spend(transactions: records, in: recent, categoryIDs: ids)
            let before = BalanceEngine.spend(transactions: records, in: earlier, categoryIDs: ids)
            growth.append((category.name, now.minorUnits - before.minorUnits))
        }
        return growth.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }
            .prefix(2).map(\.name)
    }

    private var advisorSituation: AdvisorEngine.Situation {
        var situation = AdvisorEngine.Situation()
        let snapshot = ladderSnapshot
        situation.liquidAvailable = snapshot.liquidAvailable
        situation.essentialMonthlySpend = snapshot.essentialMonthlySpend
        situation.hasOverduePayments = snapshot.overdueLoanCount > 0
        situation.highInterestDebtRemaining = snapshot.toxicDebtRemaining
        situation.emergencyFundBalance = snapshot.emergencyFundBalance
        situation.emergencyFundTargetMonths = snapshot.emergencyFundTargetMonths
        situation.sinkingFundsBehind = snapshot.sinkingFundsTotal - snapshot.sinkingFundsOnTrack
        situation.investedThisMonth = snapshot.investmentMonthsLast6 > 0
        situation.goalsOutstanding = goals.filter { $0.status == .saving }.count
        situation.ladderStage = ladderEvaluation.currentStage
        situation.netWorth = BalanceEngine.totals(for: balances).netWorth
        // Unallocated windfalls still owing a tax reserve.
        situation.taxReserveOwed = Money.sum(
            incomeEvents.filter { $0.status == .unallocated }.map(\.taxReserved)
        )
        return situation
    }

    private var monthlyLetter: String {
        var input = AdvisorEngine.LetterInput()
        let month = calendar.monthInterval(containing: calendar.currentDate())
        input.monthName = month.start.formatted(.dateTime.month(.wide).year())
        let headline = ReviewEngine.headlineFigure(monthlyReview, formatter: formatter)
        input.headlineLabel = headline.0
        input.headlineValue = headline.1

        let review = weeklyReview
        if review.envelopesOver.isEmpty && !review.envelopes.isEmpty {
            input.whatWentRight.append("Every envelope held this week.")
        }
        if ladderSnapshot.daysLoggedLast28 >= 21 {
            input.whatWentRight.append(
                "\(ladderSnapshot.daysLoggedLast28) of the last 28 days logged."
            )
        }
        if monthlyReview.debtCleared.isPositive {
            input.whatWentRight.append(
                "\(formatter.string(monthlyReview.debtCleared)) of principal cleared."
            )
        }

        for envelope in review.envelopesOver.sorted(by: { $0.variance < $1.variance }).prefix(2) {
            input.whatToChange.append(
                "\(envelope.name) went over by "
                + formatter.string(envelope.variance.magnitude) + "."
            )
        }
        if ladderSnapshot.daysLoggedLast28 < 21 {
            input.whatToChange.append(
                "Only \(ladderSnapshot.daysLoggedLast28) of 28 days are logged."
            )
        }

        let creep = creepVerdict
        input.creepRatio = creep.latestQuarterAverage
        input.creepIsRising = creep.isCreeping
        input.creepDrivers = creep.drivers

        input.instruction = ladderEvaluation.nextAction.title + "."
        let monthOverrides = overrides.filter { entry -> Bool in
            entry.occurredAt >= month.start && entry.occurredAt < month.end
        }
        input.overrideCount = monthOverrides.count
        input.overrideCost = Money.sum(monthOverrides.compactMap(\.estimatedCost))

        return AdvisorEngine.monthlyLetter(input, formatter: formatter)
    }

    // MARK: - Reviews

    private var weeklyReview: ReviewEngine.Weekly {
        let week = calendar.weekInterval(containing: calendar.currentDate())
        let records = transactions.map(DataBridge.record)
        let elapsed = calendar.elapsedDaysInWeek(containing: calendar.currentDate())
        let days = calendar.daysInMonth(containing: calendar.currentDate())

        let envelopes = budgets.map { budget -> ReviewEngine.EnvelopeLine in
            let ids = budget.category.map { Set([$0.id]) }
            return ReviewEngine.EnvelopeLine(
                id: budget.id,
                name: budget.category?.name ?? "Miscellaneous",
                budget: BudgetEngine.weeklyBudget(for: DataBridge.envelope(budget),
                                                  daysInMonth: days),
                spent: BalanceEngine.spend(transactions: records, in: week, categoryIDs: ids)
            )
        }

        let expenses = transactions
            .filter { $0.kind == .expense && week.start <= $0.date && $0.date < week.end }
            .map { ReviewEngine.ExpenseLine(
                id: $0.id,
                label: $0.category?.name ?? $0.note ?? "Unlabelled",
                amount: $0.amount, date: $0.date
            ) }

        let loggedDays = dailyLogs.filter {
            $0.entryCount > 0 && week.start <= calendar.startOfFinancialDay($0.date)
                && calendar.startOfFinancialDay($0.date) < week.end
        }.count

        return ReviewEngine.weekly(
            weekStart: week.start,
            envelopes: envelopes,
            expenses: expenses,
            totalIncome: BalanceEngine.income(transactions: records, in: week),
            streak: DailyLogService.currentStreak(logs: dailyLogs, today: calendar.today(),
                                                  calendar: calendar),
            daysLogged: Swift.min(loggedDays, elapsed),
            needsReviewCount: transactions.filter(\.isEstimate).count,
            goalsMoved: []
        )
    }

    private var monthlyReview: ReviewEngine.Monthly {
        let month = calendar.monthInterval(containing: calendar.currentDate())
        let records = transactions.map(DataBridge.record)
        let balances = BalanceEngine.balances(
            accounts: accounts.map(DataBridge.record), transactions: records,
            earmarks: earmarks.map(DataBridge.record)
        )
        let totals = BalanceEngine.totals(for: balances)
        let income = BalanceEngine.income(transactions: records, in: month)
        let spend = BalanceEngine.spend(transactions: records, in: month)

        // Broken into steps with explicit types: the chained form defeats the type checker.
        var allPayments: [LoanPayment] = []
        for loan in loans { allPayments.append(contentsOf: loan.payments ?? []) }
        let monthPayments = allPayments.filter { payment -> Bool in
            payment.deletedAt == nil && payment.date >= month.start && payment.date < month.end
        }
        let debtCleared = Money.sum(monthPayments.map { $0.principalPortion })

        let overspend = GoalEngine.overspendTotal(
            goals.compactMap { goal in
                guard goal.status == .purchased, let paid = goal.actualPricePaid else { return nil }
                return GoalEngine.OverspendEntry(id: goal.id, name: goal.name,
                                                 planned: goal.targetAmount, paid: paid)
            }
        )

        let monthOverrides = overrides.filter { entry -> Bool in
            entry.occurredAt >= month.start && entry.occurredAt < month.end
        }

        return ReviewEngine.Monthly(
            monthStart: month.start,
            netWorth: totals.netWorth,
            netWorthChange: income - spend,
            income: income, spend: spend,
            savingsRate: ReviewEngine.savingsRate(income: income, spend: spend),
            debtCleared: debtCleared,
            stageNow: ladderEvaluation.currentStage,
            stagePrevious: nil,
            score: ladderEvaluation.stabilityScore,
            overspendTotal: overspend,
            sinkingFundsOnTrack: ladderSnapshot.sinkingFundsOnTrack,
            sinkingFundsTotal: ladderSnapshot.sinkingFundsTotal,
            overrideCount: monthOverrides.count,
            overrideCost: Money.sum(monthOverrides.compactMap(\.estimatedCost))
        )
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.screen.title).font(Theme.Font.title)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isQuickAddShown = true
            } label: {
                Label("Log", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Log a transaction (⌘N)")

            Button {
                model.isTransferShown = true
            } label: {
                Label("Transfer", systemImage: "arrow.left.arrow.right")
            }
            .keyboardShortcut("t", modifiers: .command)
            .help("Move money between accounts (⌘T)")

            Button {
                model.isInspectorShown.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Toggle the details panel (⌥⌘I)")
        }
    }

    /// A brand new database still needs its categories and a settings row before
    /// anything can be logged.
    private func bootstrapIfNeeded() {
        guard settingsRows.isEmpty else { return }
        let settings = AppSettings()
        settings.applyCurrency(.ghs)
        settings.incomeType = .mixed
        context.insert(settings)
        if (try? context.fetch(FetchDescriptor<Category>()))?.isEmpty ?? true {
            for category in SeedData.defaultCategories() { context.insert(category) }
        }
        try? context.save()
    }
}

/// Placeholder for screens that belong to later milestones. Says which one, rather
/// than pretending to be broken.
struct ComingSoonView: View {
    let screen: AppModel.Screen

    private var milestone: String {
        switch screen {
        case .plan: "M3 and M4 — envelopes, recurring rules and the cash-flow calendar"
        case .debt: "M5 — loans, payoff order and the planned-loan verdict"
        case .goals: "M6 — earmarks, the allocation waterfall and goal ETAs"
        case .ladder: "M7 — the seven stages and the stability score"
        case .income: "M7.5 — windfall interception and the allocation sheet"
        case .advisor: "M7.5 — the Order of Operations and the rule engine"
        case .insights: "M8 — the heatmap and every chart"
        default: "a later milestone"
        }
    }

    var body: some View {
        EmptyStateView(
            icon: screen.icon,
            title: screen.title,
            message: "This screen arrives in \(milestone)."
        )
        .frame(maxHeight: .infinity)
    }
}
