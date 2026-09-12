import Foundation
import SwiftData

/// Evaluates every rule in `NotificationRules` against live data and schedules what
/// passes the central gate.
///
/// Adding a notification means adding a rule, never a scheduling call in feature code.
@MainActor
enum NotificationScheduler {

    struct Context {
        var settings: AppSettings
        var calendar: FinancialCalendar
        var formatter: MoneyFormatter
        var dailyLogs: [DailyLog] = []
        var envelopes: [BudgetEngine.EnvelopeState] = []
        var loans: [LoanEngine.Position] = []
        var rules: [RecurringRule] = []
        var balances: [BalanceEngine.AccountBalance] = []
        var projection: ForecastEngine.Projection?
        var lastReconciledOn: Date?
        var goals: [GoalEngine.GoalInput] = []
    }

    /// Runs the whole rule set. Each rule still passes through `shouldDeliver`, which
    /// enforces quiet hours, the daily cap and cooldowns.
    static func evaluate(_ context: Context) {
        let service = NotificationService.shared
        let calendar = context.calendar
        let today = calendar.today()
        let budget = service.budget(from: context.settings)
        let enabled = context.settings.notificationsEnabled

        func schedule(_ trigger: NotificationRules.Trigger, at hour: Int, minute: Int = 0,
                      body: String? = nil, on day: Date = today) {
            var components = calendar.calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            service.schedule(trigger, at: components, bodyOverride: body, budget: budget,
                             notificationsEnabled: enabled, calendar: calendar)
        }

        // Nothing logged today, and the stronger wording once it has been a while.
        let loggedToday = context.dailyLogs.contains { $0.date == today && $0.entryCount > 0 }
        if !loggedToday {
            let unloggedRun = consecutiveUnloggedDays(logs: context.dailyLogs, today: today,
                                                      calendar: calendar)
            if unloggedRun >= 5 {
                schedule(.nothingLoggedStreakAtRisk, at: 22)
            } else {
                schedule(.nothingLoggedToday, at: 20, minute: 30)
            }
        }

        // Envelopes running ahead of pace.
        for envelope in context.envelopes where envelope.isAheadOfPace {
            schedule(.envelopeBurnAhead, at: 18,
                     body: "\(envelope.name): \(context.formatter.string(envelope.spent)) of "
                         + "\(context.formatter.string(envelope.budget)) this week.")
        }

        // Miscellaneous past 60% before Wednesday.
        let weekday = calendar.calendar.component(.weekday, from: calendar.calendarMidnight(of: today))
        if weekday <= 4,
           let misc = context.envelopes.first(where: { $0.input.isMiscellaneous }),
           let burn = misc.burn, burn > Decimal(string: "0.6")! {
            schedule(.miscEnvelopePastSixtyPercent, at: 18)
        }

        // Loan payments: T−3 and the morning of T.
        for loan in context.loans where !loan.isPaidOff {
            guard let next = loan.schedule.instalments
                .first(where: { $0.date >= today })?.date else { continue }
            let days = calendar.daysBetween(today, next)
            if days == 3 || days == 0 {
                schedule(.loanPaymentDue, at: 9,
                         body: "\(loan.loan.name): "
                             + "\(context.formatter.string(loan.regularPayment)) "
                             + (days == 0 ? "due today." : "due in three days."))
            }
        }

        // Recurring bills at T−2.
        for rule in context.rules where rule.isCommittedOutflow && !rule.isArchived {
            let days = calendar.daysBetween(today, rule.nextDueDate)
            if days == 2 {
                schedule(.recurringBillDue, at: 9,
                         body: "\(rule.label): \(context.formatter.string(rule.amount)) "
                             + "due in two days.")
            }
        }

        // Expected income that has not arrived, T+2.
        for rule in context.rules where rule.kind == .income && !rule.isArchived {
            let overdueBy = calendar.daysBetween(rule.nextDueDate, today)
            if overdueBy == 2 {
                schedule(.expectedIncomeMissing, at: 10,
                         body: "\(rule.label) was expected two days ago.")
            }
        }

        // Accounts below their floor.
        for balance in context.balances where balance.isBelowFloor {
            schedule(.accountBelowFloor, at: 12,
                     body: "\(balance.account.name) is at "
                         + "\(context.formatter.string(balance.balance)).")
        }

        // A projected negative day inside a fortnight.
        if let projection = context.projection, let trouble = projection.firstNegativeDay,
           calendar.daysBetween(today, trouble.date) <= 14 {
            schedule(.projectedNegativeDay, at: 12,
                     body: trouble.date.formatted(.dateTime.weekday(.wide).day().month())
                         + " projects below zero.")
        }

        // Goal milestones at each quarter.
        for goal in context.goals where goal.status == .saving {
            let percent = Money.roundBankers(goal.fraction * 100)
            if [25, 50, 75, 100].contains(percent) {
                schedule(.goalMilestone, at: 12,
                         body: "\(goal.name) is \(percent)% funded.")
            }
        }

        // Nothing reconciled in a fortnight.
        if BalanceEngine.needsReconciliation(lastReconciledOn: context.lastReconciledOn,
                                             today: today, calendar: calendar),
           !context.balances.isEmpty {
            schedule(.nothingReconciled, at: 10)
        }

        // Weekly and monthly reviews.
        if weekday == 1 { schedule(.weeklyReview, at: 18) }
        if calendar.addDays(1, to: today) == calendar.startOfMonth(
            containing: calendar.addMonths(1, to: today)
        ) {
            schedule(.monthlyReview, at: 19)
        }
    }

    /// A single spend well above the usual for its category. Fires immediately, on save.
    static func flagUnusualExpense(
        amount: Money, categoryName: String, categoryMedian: Money,
        settings: AppSettings, calendar: FinancialCalendar, formatter: MoneyFormatter
    ) {
        guard categoryMedian.isPositive,
              amount > categoryMedian.scaled(by: Decimal(string: "1.5")!) else { return }
        var components = calendar.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: calendar.currentDate()
        )
        components.minute = (components.minute ?? 0) + 1
        NotificationService.shared.schedule(
            .unusuallyLargeExpense, at: components,
            bodyOverride: "\(formatter.string(amount)) on \(categoryName) is well above the "
                        + "usual \(formatter.string(categoryMedian)). Confirm it?",
            budget: NotificationService.shared.budget(from: settings),
            notificationsEnabled: settings.notificationsEnabled, calendar: calendar
        )
    }

    static func consecutiveUnloggedDays(
        logs: [DailyLog], today: Date, calendar: FinancialCalendar
    ) -> Int {
        let logged = Set(logs.filter { $0.entryCount > 0 }.map(\.date))
        var count = 0
        var cursor = today
        while !logged.contains(cursor) && count < 60 {
            count += 1
            cursor = calendar.addDays(-1, to: cursor)
        }
        return count
    }
}
