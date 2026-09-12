import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Builds the widget's snapshot from live data and writes it to the shared container.
///
/// The widget cannot read the database, so everything it shows is computed here, in the
/// app, and handed over pre-formatted. This runs on save and on launch; it is cheap and
/// writes nothing to the store.
@MainActor
enum WidgetSnapshotWriter {

    struct Inputs {
        var settings: AppSettings
        var calendar: FinancialCalendar
        var formatter: MoneyFormatter
        var accounts: [Account] = []
        var transactions: [Transaction] = []
        var earmarks: [Earmark] = []
        var budgets: [Budget] = []
        var rules: [RecurringRule] = []
        var events: [ScheduledEvent] = []
        var dailyLogs: [DailyLog] = []
        var ladder: LadderEngine.Evaluation?
    }

    /// Rebuilds the snapshot from the store. Call this after anything that changes the
    /// ledger — including from the menu bar, where no window is open to notice.
    static func refresh(container: ModelContainer) {
        let context = ModelContext(container)
        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        else { return }

        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter { model in
                (model as? any SoftDeletable)?.deletedAt == nil
            }
        }

        let accounts = fetch(Account.self)
        let transactions = fetch(Transaction.self)
        let earmarks = fetch(Earmark.self)
        let budgets = fetch(Budget.self)
        let rules = fetch(RecurringRule.self)
        let events = fetch(ScheduledEvent.self)
        let loans = fetch(Loan.self)
        let funds = fetch(SinkingFund.self)
        let dailyLogs = fetch(DailyLog.self)

        let ladderSnapshot = LadderSnapshotBuilder.build(
            from: LadderSnapshotBuilder.Sources(
                accounts: accounts, transactions: transactions, earmarks: earmarks,
                budgets: budgets, rules: rules, events: events, loans: loans,
                funds: funds, dailyLogs: dailyLogs, settings: settings
            ),
            calendar: settings.calendar
        )

        write(Inputs(
            settings: settings, calendar: settings.calendar, formatter: settings.formatter,
            accounts: accounts, transactions: transactions, earmarks: earmarks,
            budgets: budgets, rules: rules, events: events, dailyLogs: dailyLogs,
            ladder: LadderEngine.evaluate(ladderSnapshot)
        ))
    }

    static func write(_ inputs: Inputs) {
        var snapshot = WidgetSnapshot()
        let calendar = inputs.calendar
        let formatter = inputs.formatter
        let today = calendar.today()
        let week = calendar.weekInterval(containing: calendar.currentDate())
        let elapsed = calendar.elapsedDaysInWeek(containing: calendar.currentDate())
        let records = inputs.transactions.map(DataBridge.record)

        snapshot.generatedAt = calendar.currentDate()
        snapshot.hasAnyData = !inputs.accounts.isEmpty
        snapshot.daysElapsedInWeek = elapsed

        let balances = BalanceEngine.balances(
            accounts: inputs.accounts.map(DataBridge.record),
            transactions: records,
            earmarks: inputs.earmarks.map(DataBridge.record)
        )
        let totals = BalanceEngine.totals(for: balances)
        snapshot.available = formatter.string(totals.liquidAvailable)

        let spentThisWeek = BalanceEngine.spend(transactions: records, in: week)
        snapshot.spentThisWeek = formatter.string(spentThisWeek)
        snapshot.spentToday = formatter.string(
            BalanceEngine.spend(transactions: records,
                                in: calendar.financialDayInterval(containing: calendar.currentDate()))
        )

        // Free to spend, with the same arithmetic the dashboard shows.
        let commitments = inputs.rules
            .filter { $0.isCommittedOutflow && !$0.isArchived }
            .map(DataBridge.commitment)
        let free = BudgetEngine.freeToSpend(
            expectedIncomeThisWeek: BudgetEngine.weeklyFromMonthly(
                inputs.settings.expectedMonthlyNetIncome
            ),
            commitments: commitments,
            goalAllocationsThisWeek: .zero,
            alreadySpentThisWeek: spentThisWeek
        )
        if commitments.isEmpty {
            // Before there are commitments the two numbers are the same; show the
            // simpler, honest label rather than implying a calculation that has not run.
            snapshot.freeToSpend = formatter.string(totals.liquidAvailable)
            snapshot.freeToSpendIsNegative = totals.liquidAvailable.isNegative
            snapshot.freeToSpendCaption = "Available to spend"
        } else {
            snapshot.freeToSpend = formatter.string(free.amount)
            snapshot.freeToSpendIsNegative = free.isNegative
            snapshot.freeToSpendCaption = "Free this week · day \(elapsed) of 7"
        }

        // Streaks.
        let heatmapDays = inputs.dailyLogs.map {
            InsightsEngine.DayInput(date: $0.date, entryCount: $0.entryCount,
                                    spend: $0.spend, stayedInsidePace: $0.stayedInsidePace)
        }
        let streaks = InsightsEngine.streaks(days: heatmapDays, today: today, calendar: calendar)
        snapshot.currentStreak = streaks.current
        snapshot.longestStreak = streaks.longest
        snapshot.loggedToday = inputs.dailyLogs.contains {
            $0.date == today && $0.entryCount > 0
        }

        // Ladder.
        if let ladder = inputs.ladder {
            snapshot.stabilityScore = ladder.stabilityScore.total
            snapshot.ladderStage = ladder.currentStage.title
            snapshot.nextAction = ladder.nextAction.title
            if let months = ladder.runwayMonths {
                let tenths = Money.roundBankers(months * 10)
                snapshot.runway = "\(tenths / 10).\(abs(tenths % 10)) mo"
            }
        }

        // The next scheduled outgoing.
        let projection = ForecastEngine.project(
            startingBalance: totals.liquidAvailable,
            from: calendar.currentDate(), days: 60,
            scheduled: inputs.rules.filter { !$0.isArchived }.map(DataBridge.scheduled),
            oneOffs: inputs.events.map {
                DataBridge.oneOff($0, maybeWeight: inputs.settings.maybeEventWeight)
            },
            calendar: calendar
        )
        if let next = projection.days
            .first(where: { $0.movements.contains { $0.amount.isNegative } }),
           let movement = next.movements.filter({ $0.amount.isNegative })
            .min(by: { $0.amount < $1.amount }) {
            snapshot.nextDue = "\(movement.label) "
                + formatter.string(movement.amount.magnitude) + " on "
                + next.date.formatted(.dateTime.day().month(.abbreviated))
        }

        // Envelopes past pace.
        let daysInMonth = calendar.daysInMonth(containing: calendar.currentDate())
        snapshot.envelopesAheadOfPace = inputs.budgets.compactMap { budget in
            let state = BudgetEngine.state(
                for: DataBridge.envelope(budget),
                spent: BalanceEngine.spend(transactions: records, in: week,
                                           categoryIDs: budget.category.map { Set([$0.id]) }),
                elapsedDaysInWeek: elapsed, daysInMonth: daysInMonth,
                alertMargin: inputs.settings.burnAlertMargin
            )
            guard state.isAheadOfPace || state.isOverspent else { return nil }
            return state.name
        }

        // The contribution grid: 13 weeks ending today, aligned to whole weeks so the
        // columns line up the way they do on the Insights heatmap.
        let gridStart = calendar.addDays(-7 * 12, to: calendar.startOfWeek(containing: today))
        let byDay = Dictionary(
            inputs.dailyLogs.map { ($0.date, $0.entryCount) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshot.loggingGrid = calendar.days(from: gridStart, through: today).map { day in
            let count = byDay[day] ?? 0
            // Four entries is a full-intensity day, matching the Insights heatmap.
            return count == 0 ? 0 : Swift.min(4, count)
        }
        snapshot.gridStartWeekday = 0

        // One warning, chosen by what matters most.
        if let negative = projection.firstNegativeDay {
            snapshot.warning = negative.date.formatted(.dateTime.day().month(.abbreviated))
                + " projects below zero"
        } else if let overCommitted = balances.first(where: \.isOverCommitted) {
            snapshot.warning = "\(overCommitted.account.name) is over-committed"
        } else if let envelope = snapshot.envelopesAheadOfPace.first {
            snapshot.warning = "\(envelope) is ahead of pace"
        } else if !snapshot.loggedToday {
            snapshot.warning = "Nothing logged today"
        }

        snapshot.save()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
