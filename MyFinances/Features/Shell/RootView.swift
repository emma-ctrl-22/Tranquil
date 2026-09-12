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
    @Query(filter: #Predicate<Valuation> { $0.deletedAt == nil },
           sort: \Valuation.date, order: .reverse)
    private var valuations: [Valuation]
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
        .task {
            bootstrapIfNeeded()
            runNotificationRules()
            refreshWidget()
        }
        .onChange(of: transactions.count) { _, _ in refreshWidget() }
        .onChange(of: accounts.count) { _, _ in refreshWidget() }
        .onChange(of: dailyLogs.count) { _, _ in refreshWidget() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            model.open(.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAdd)) { _ in
            model.isQuickAddShown = true
        }
        .background {
            // Keyboard navigation: one shortcut per screen, always available.
            ForEach(Array(AppModel.Screen.allCases.enumerated()), id: \.element) { index, screen in
                if screen.isAvailable && index < 9 {
                    Button("") { model.open(screen) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")), modifiers: .command
                        )
                        .hidden()
                }
            }
        }
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
                          creep: creepVerdict, salaryCheck: salaryCheck,
                          investments: investmentSummary,
                          streaks: streakSummary,
                          microSpendThisMonth: InsightsEngine.microSpendTotal(categoryTotals))
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
                       settings: settings, creep: creepVerdict, taxReserved: taxReserved,
                       salaryCheck: salaryCheck)
        case .advisor:
            AdvisorView(model: $model, situation: advisorSituation,
                        letter: monthlyLetter, formatter: formatter)
        case .help:
            HelpView(model: $model, formatter: formatter)
        case .settings:
            SettingsView()
        case .investments:
            InvestmentsView(model: $model, formatter: formatter, calendar: calendar,
                            summary: investmentSummary,
                            contributionMonths: investmentContributionMonths,
                            contributionRate: investmentContributionRate)
        case .help:
            HelpView(model: $model, formatter: formatter)
        case .settings:
            SettingsView()
        case .investments:
            InvestmentsView(model: $model, formatter: formatter, calendar: calendar,
                            summary: investmentSummary,
                            contributionMonths: investmentContributionMonths,
                            contributionRate: investmentContributionRate)
        case .insights:
            InsightsView(model: $model, formatter: formatter, calendar: calendar,
                         cells: heatmapCells, streaks: streakSummary,
                         categoryTotals: categoryTotals, monthBars: monthBars,
                         netWorthSeries: netWorthSeries, debtPoints: debtSeries,
                         heatmapMode: $model.heatmapMode)
        default:
            ComingSoonView(screen: model.screen)
        }
    }

    private var maybeEventWeight: Decimal {
        settings?.maybeEventWeight ?? Decimal(string: "0.5")!
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

    // MARK: - Investments

    /// Contributed principal comes from the ledger; current value only from what the
    /// user has entered. The app never invents the second number.
    private var investmentSummary: InvestmentEngine.Summary {
        let records = transactions.map(DataBridge.record)
        let holdings = accounts
            .filter { $0.type == .investment && !$0.isArchived }
            .map { account -> InvestmentEngine.Holding in
                var contributed = account.openingBalance
                for record in records {
                    contributed += BalanceEngine.effect(of: record, on: account.id)
                }
                let latest = valuations.first { $0.account?.id == account.id }
                return InvestmentEngine.Holding(
                    accountID: account.id, name: account.name, colorHex: account.colorHex,
                    contributed: contributed,
                    currentValue: latest?.value, valuedOn: latest?.date
                )
            }
        return InvestmentEngine.Summary(holdings: holdings)
    }

    private var investmentAccountIDs: Set<UUID> {
        Set(accounts.filter { $0.type == .investment }.map(\.id))
    }

    private var investmentContributionMonths: Int {
        let records = transactions.map(DataBridge.record)
        var months: Set<Date> = []
        for record in records where record.kind == .transfer {
            guard let destination = record.counterAccountID,
                  investmentAccountIDs.contains(destination) else { continue }
            months.insert(calendar.startOfMonth(containing: record.date))
        }
        return InvestmentEngine.contributionStreak(
            contributionMonths: months, months: 12, today: calendar.today(), calendar: calendar
        )
    }

    private var investmentContributionRate: Decimal? {
        let records = transactions.map(DataBridge.record)
        let today = calendar.today()
        let year = DateInterval(start: calendar.addMonths(-12, to: today),
                                end: calendar.addDays(1, to: today))
        var contributed = Money.zero
        for record in records where record.kind == .transfer {
            guard let destination = record.counterAccountID,
                  investmentAccountIDs.contains(destination),
                  year.start <= record.date, record.date < year.end else { continue }
            contributed += record.amount
        }
        return InvestmentEngine.contributionRate(
            contributed: contributed,
            netIncome: BalanceEngine.income(transactions: records, in: year)
        )
    }

    // MARK: - Insights

    private var heatmapDays: [InsightsEngine.DayInput] {
        dailyLogs.map {
            InsightsEngine.DayInput(date: $0.date, entryCount: $0.entryCount,
                                    spend: $0.spend, stayedInsidePace: $0.stayedInsidePace)
        }
    }

    private var heatmapCells: [InsightsEngine.Cell] {
        InsightsEngine.heatmap(days: heatmapDays, mode: model.heatmapMode,
                               today: calendar.today(), calendar: calendar)
    }

    private var streakSummary: InsightsEngine.StreakSummary {
        InsightsEngine.streaks(days: heatmapDays, today: calendar.today(), calendar: calendar)
    }

    private var categoryTotals: [InsightsEngine.CategoryTotal] {
        let records = transactions.map(DataBridge.record)
        let month = calendar.monthInterval(containing: calendar.currentDate())
        let previousStart = calendar.addMonths(-1, to: month.start)
        let previous = DateInterval(start: previousStart, end: month.start)

        var seen: Set<UUID> = []
        var totals: [InsightsEngine.CategoryTotal] = []
        for category in transactions.compactMap(\.category) where !seen.contains(category.id) {
            seen.insert(category.id)
            let ids: Set<UUID> = [category.id]
            totals.append(InsightsEngine.CategoryTotal(
                id: category.id, name: category.name, colorHex: category.colorHex,
                amount: BalanceEngine.spend(transactions: records, in: month, categoryIDs: ids),
                previous: BalanceEngine.spend(transactions: records, in: previous,
                                              categoryIDs: ids),
                isMicro: category.isMicro
            ))
        }
        return InsightsEngine.rollup(totals)
    }

    private var monthBars: [InsightsEngine.MonthBar] {
        let records = transactions.map(DataBridge.record)
        let today = calendar.today()
        return stride(from: 11, through: 0, by: -1).map { offset -> InsightsEngine.MonthBar in
            let start = calendar.startOfMonth(containing: calendar.addMonths(-offset, to: today))
            let interval = DateInterval(start: start, end: calendar.addMonths(1, to: start))
            return InsightsEngine.MonthBar(
                monthStart: start,
                income: BalanceEngine.income(transactions: records, in: interval),
                expense: BalanceEngine.spend(transactions: records, in: interval)
            )
        }
    }

    /// Net worth reconstructed from the ledger. `BalanceSnapshot` is only ever a cache;
    /// if it disagreed with the ledger the ledger would win, so the chart reads the
    /// ledger directly.
    private var netWorthSeries: [InsightsEngine.Point] {
        let records = transactions.map(DataBridge.record)
        let accountRecords = accounts.map(DataBridge.record)
        let today = calendar.today()
        return stride(from: 11, through: 0, by: -1).map { offset -> InsightsEngine.Point in
            let date = calendar.addMonths(-offset, to: today)
            let asOf = BalanceEngine.balances(accounts: accountRecords, transactions: records,
                                              earmarks: [], asOf: date)
            return InsightsEngine.Point(date: date,
                                        value: BalanceEngine.totals(for: asOf).netWorth)
        }
    }

    private var debtSeries: [InsightsEngine.DebtPoint] {
        let positions = loans.filter { $0.status != .planned }
            .map { LoanEngine.position(for: DataBridge.loan($0), calendar: calendar) }
        guard !positions.isEmpty else { return [] }
        return InsightsEngine.debtBurndown(positions: positions, from: calendar.today(),
                                           months: 24, calendar: calendar)
    }

    // MARK: - Income and advisor

    /// What actually arrived this month against what the settings say you earn.
    private var salaryCheck: IncomeEngine.SalaryCheck {
        let month = calendar.monthInterval(containing: calendar.currentDate())
        let received = BalanceEngine.income(transactions: transactions.map(DataBridge.record),
                                            in: month)
        let payDay = settings?.salaryDayOfMonth ?? 28
        let dayOfMonth = calendar.calendar.component(
            .day, from: calendar.calendarMidnight(of: calendar.today())
        )
        return IncomeEngine.salaryCheck(
            expectedMonthly: settings?.expectedMonthlyNetIncome ?? .zero,
            receivedThisMonth: received,
            payDayPassed: dayOfMonth >= payDay
        )
    }

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
        // These are always available, whatever screen you are on, so they are labelled.
        // A screen's own add button is a bare glyph; these never are.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isQuickAddShown = true
            } label: {
                Label("Log a spend", systemImage: "square.and.pencil")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("n", modifiers: .command)
            .help("Log a transaction (⌘N)")

            Button {
                model.isTransferShown = true
            } label: {
                Label("Transfer", systemImage: "arrow.left.arrow.right")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("t", modifiers: .command)
            .help("Move money between accounts (⌘T)")

            Divider()

            Button {
                model.isInspectorShown.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Toggle the details panel (⌥⌘I)")
        }
    }

    /// Hands the widget a fresh snapshot. The widget cannot read the database, so
    /// everything it shows is computed here.
    private func refreshWidget() {
        guard let settings else { return }
        WidgetSnapshotWriter.write(WidgetSnapshotWriter.Inputs(
            settings: settings, calendar: calendar, formatter: formatter,
            accounts: accounts, transactions: transactions, earmarks: earmarks,
            budgets: budgets, rules: rules, events: events, dailyLogs: dailyLogs,
            ladder: ladderEvaluation
        ))
    }

    /// Runs the declarative rule set against live data, once per launch.
    private func runNotificationRules() {
        guard let settings else { return }
        let week = calendar.weekInterval(containing: calendar.currentDate())
        let records = transactions.map(DataBridge.record)
        let elapsed = calendar.elapsedDaysInWeek(containing: calendar.currentDate())
        let days = calendar.daysInMonth(containing: calendar.currentDate())

        let envelopes = budgets.map { budget in
            BudgetEngine.state(
                for: DataBridge.envelope(budget),
                spent: BalanceEngine.spend(transactions: records, in: week,
                                           categoryIDs: budget.category.map { Set([$0.id]) }),
                elapsedDaysInWeek: elapsed, daysInMonth: days
            )
        }

        NotificationScheduler.evaluate(NotificationScheduler.Context(
            settings: settings,
            calendar: calendar,
            formatter: formatter,
            dailyLogs: dailyLogs,
            envelopes: envelopes,
            loans: loans.filter { $0.status != .planned }
                .map { LoanEngine.position(for: DataBridge.loan($0), calendar: calendar) },
            rules: rules,
            balances: balances,
            projection: ForecastEngine.project(
                startingBalance: BalanceEngine.totals(for: balances).liquidAvailable,
                from: calendar.currentDate(), days: 30,
                scheduled: rules.filter { !$0.isArchived }.map(DataBridge.scheduled),
                oneOffs: events.map { DataBridge.oneOff($0, maybeWeight: maybeEventWeight) }, calendar: calendar
            ),
            lastReconciledOn: lastReconciledOn,
            goals: goals.map { DataBridge.goal($0, earmarks: earmarks) }
        ))
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
