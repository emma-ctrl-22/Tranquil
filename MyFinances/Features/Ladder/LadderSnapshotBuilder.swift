import Foundation
import SwiftData

/// Gathers everything the Ladder needs from the store, once.
///
/// The engine stays pure; this is the seam where SwiftData meets it.
enum LadderSnapshotBuilder {

    struct Sources {
        var accounts: [Account] = []
        var transactions: [Transaction] = []
        var earmarks: [Earmark] = []
        var budgets: [Budget] = []
        var rules: [RecurringRule] = []
        var events: [ScheduledEvent] = []
        var loans: [Loan] = []
        var funds: [SinkingFund] = []
        var dailyLogs: [DailyLog] = []
        var settings: AppSettings?
    }

    static func build(from sources: Sources, calendar: FinancialCalendar)
    -> LadderEngine.Snapshot {
        let today = calendar.today()
        let records = sources.transactions.map(DataBridge.record)
        let balances = BalanceEngine.balances(
            accounts: sources.accounts.map(DataBridge.record),
            transactions: records,
            earmarks: sources.earmarks.map(DataBridge.record)
        )
        let totals = BalanceEngine.totals(for: balances)

        // Essential spend: trailing three-month **median**, never the mean, so one
        // heavy month does not permanently raise the bar.
        let essentialIDs = Set(
            sources.transactions.compactMap { $0.category }
                .filter(\.isEssential).map(\.id)
        )
        let monthlyEssentials = (0..<3).map { offset -> Money in
            let monthStart = calendar.addMonths(-offset - 1, to: today)
            let interval = DateInterval(start: monthStart,
                                        end: calendar.addMonths(1, to: monthStart))
            return BalanceEngine.spend(transactions: records, in: interval,
                                       categoryIDs: essentialIDs)
        }
        let essentialMonthlySpend = BudgetEngine.medianWeeklyIncome(
            trailingWeeks: monthlyEssentials
        )

        // Logging and reconciliation.
        let last28 = Set(calendar.days(from: calendar.addDays(-27, to: today), through: today))
        let daysLogged = sources.dailyLogs
            .filter { $0.deletedAt == nil && $0.entryCount > 0 && last28.contains($0.date) }
            .count
        let lastReconciled = sources.dailyLogs
            .filter { $0.deletedAt == nil && $0.wasReconciled }
            .map(\.date).max()
        let daysSinceReconciliation = lastReconciled.map { calendar.daysBetween($0, today) }

        // Loans.
        let positions = sources.loans
            .filter { $0.status != .planned }
            .map { LoanEngine.position(for: DataBridge.loan($0), calendar: calendar) }
        let owed = positions.filter { $0.loan.direction == .iOwe && !$0.isPaidOff }
        let threshold = sources.settings?.highInterestThresholdAPR ?? Decimal(string: "0.25")!
        let toxic = Money.sum(
            owed.filter { $0.isToxic(highInterestThreshold: threshold) }.map(\.remainingBalance)
        )
        let allPayments = sources.loans.flatMap { ($0.payments ?? []) }
            .filter { $0.deletedAt == nil }
        let latePayments = allPayments.filter(\.isLate)
        let daysSinceLastLate = latePayments.map(\.date).max()
            .map { calendar.daysBetween($0, today) }
        let overdue = sources.loans.filter { loan in
            loan.status == .active && loan.deletedAt == nil
                && (loan.payments ?? []).filter { $0.deletedAt == nil && $0.isLate }.isEmpty == false
        }.count
        let onTimeRatio: Decimal = allPayments.isEmpty
            ? 1
            : Decimal(allPayments.count - latePayments.count) / Decimal(allPayments.count)

        let monthlyDebt = Money.sum(owed.map {
            LoanEngine.monthlyEquivalent($0.regularPayment, frequency: $0.loan.paymentFrequency)
        })
        let income = sources.settings?.expectedMonthlyNetIncome ?? .zero
        let debtServiceRatio: Decimal = income.isPositive
            ? (monthlyDebt.ratio(to: income) ?? 0)
            : (owed.isEmpty ? 0 : 1)
        let highestAPR = owed.map(\.loan.annualRate).max() ?? 0

        // The next 30 days, for "nothing is late".
        let projection = ForecastEngine.project(
            startingBalance: totals.liquidAvailable,
            from: calendar.currentDate(), days: 30,
            scheduled: sources.rules.filter { !$0.isArchived }.map(DataBridge.scheduled),
            oneOffs: sources.events.map(DataBridge.oneOff),
            calendar: calendar
        )
        let billsDue = Money.sum(
            projection.days.flatMap(\.movements).filter(\.amount.isNegative).map(\.amount.magnitude)
        )

        // Emergency fund and sinking funds.
        let emergencyFund = sources.funds.first(where: \.isEmergencyFund)
        let emergencyBalance = emergencyFund.map { fund in
            Money.sum(sources.earmarks.filter { $0.ownerID == fund.id }.map(\.amount))
        } ?? .zero
        let fundsWithTargets = sources.funds.filter { $0.targetAmount.isPositive }
        let fundsOnTrack = fundsWithTargets.filter { fund in
            let saved = Money.sum(sources.earmarks.filter { $0.ownerID == fund.id }.map(\.amount))
            return saved >= requiredToDate(for: fund, calendar: calendar)
        }.count

        // Investment consistency: months with a transfer into an investment account.
        let investmentAccountIDs = Set(
            sources.accounts.filter { $0.type == .investment }.map(\.id)
        )
        func investedMonths(_ count: Int) -> Int {
            (0..<count).filter { offset in
                let monthStart = calendar.addMonths(-offset, to: today)
                let interval = DateInterval(start: monthStart,
                                            end: calendar.addMonths(1, to: monthStart))
                return records.contains { record in
                    record.kind == .transfer
                        && record.counterAccountID.map(investmentAccountIDs.contains) == true
                        && interval.start <= record.date && record.date < interval.end
                }
            }.count
        }

        // Budget adherence over the trailing eight weeks.
        let adherence = budgetAdherence(budgets: sources.budgets, records: records,
                                        calendar: calendar)

        return LadderEngine.Snapshot(
            liquidAvailable: totals.liquidAvailable,
            essentialMonthlySpend: essentialMonthlySpend,
            daysLoggedLast28: daysLogged,
            daysSinceReconciliation: daysSinceReconciliation,
            overdueLoanCount: overdue,
            daysSinceLastLatePayment: daysSinceLastLate,
            billsDueNext30Days: billsDue,
            projectedLowNext30Days: projection.lowestDay?.closingBalance ?? totals.liquidAvailable,
            toxicDebtRemaining: toxic,
            emergencyFundBalance: emergencyBalance,
            daysSinceEmergencyFundWithdrawal: nil,
            sinkingFundsOnTrack: fundsOnTrack,
            sinkingFundsTotal: fundsWithTargets.count,
            debtServiceRatio: debtServiceRatio,
            highestRemainingAPR: highestAPR,
            investmentMonthsLast12: investedMonths(12),
            investmentMonthsLast6: investedMonths(6),
            monthsAllStagesHeld: 0,
            onTimePaymentsRatio: onTimeRatio,
            budgetAdherenceRatio: adherence,
            emergencyFundTargetMonths: sources.settings?.recommendedEmergencyFundMonths ?? 6
        )
    }

    /// Where a sinking fund should be by now, given how much of its runway has elapsed.
    private static func requiredToDate(for fund: SinkingFund,
                                       calendar: FinancialCalendar) -> Money {
        guard let target = fund.targetDate else { return .zero }
        let today = calendar.today()
        let total = calendar.daysBetween(fund.createdAt, target)
        guard total > 0 else { return fund.targetAmount }
        let elapsed = Swift.max(0, Swift.min(total, calendar.daysBetween(fund.createdAt, today)))
        return fund.targetAmount.scaled(by: Decimal(elapsed) / Decimal(total))
    }

    private static func budgetAdherence(budgets: [Budget], records: [BalanceEngine.TransactionRecord],
                                        calendar: FinancialCalendar) -> Decimal {
        let live = budgets.filter { $0.deletedAt == nil && $0.amount.isPositive }
        guard !live.isEmpty else { return 1 }
        var held = 0
        var total = 0
        for weekOffset in 1...8 {
            let anchor = calendar.addDays(-7 * weekOffset, to: calendar.today())
            let week = calendar.weekInterval(containing: anchor)
            let days = calendar.daysInMonth(containing: anchor)
            for budget in live {
                let ids = budget.category.map { Set([$0.id]) }
                let spent = BalanceEngine.spend(transactions: records, in: week, categoryIDs: ids)
                let allowed = BudgetEngine.weeklyBudget(for: DataBridge.envelope(budget),
                                                        daysInMonth: days)
                total += 1
                if spent <= allowed { held += 1 }
            }
        }
        guard total > 0 else { return 1 }
        return Decimal(held) / Decimal(total)
    }
}
