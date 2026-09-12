import Foundation
import SwiftData

/// Maps SwiftData models into the value types the engines consume.
///
/// Engines never see a `@Model`. This is the only place the two meet.
enum DataBridge {

    static func record(_ account: Account) -> BalanceEngine.AccountRecord {
        BalanceEngine.AccountRecord(
            id: account.id,
            name: account.name,
            type: account.type,
            openingBalance: account.openingBalance,
            colorHex: account.colorHex,
            icon: account.icon,
            sortOrder: account.sortOrder,
            includeInNetWorth: account.includeInNetWorth,
            isLiquid: account.isLiquid,
            lowBalanceFloor: account.lowBalanceFloor,
            isArchived: account.isArchived,
            isTaxReserve: account.isTaxReserve,
            isEmergencyFundAccount: account.isEmergencyFundAccount
        )
    }

    static func record(_ transaction: Transaction) -> BalanceEngine.TransactionRecord {
        BalanceEngine.TransactionRecord(
            id: transaction.id,
            date: transaction.date,
            amount: transaction.amount,
            kind: transaction.kind,
            accountID: transaction.account?.id,
            counterAccountID: transaction.counterAccount?.id,
            categoryID: transaction.category?.id,
            isEstimate: transaction.isEstimate
        )
    }

    static func envelope(_ budget: Budget, carriedIn: Money = .zero) -> BudgetEngine.EnvelopeInput {
        BudgetEngine.EnvelopeInput(
            id: budget.id,
            categoryID: budget.category?.id,
            name: budget.category?.name ?? "Miscellaneous",
            icon: budget.category?.icon ?? "questionmark.circle",
            colorHex: budget.category?.colorHex ?? "#8A8A8A",
            period: budget.period,
            amount: budget.amount,
            rollover: budget.rollover,
            rolloverCapMultiple: budget.rolloverCapMultiple,
            isMiscellaneous: budget.category?.isMiscellaneous ?? true,
            isEssential: budget.category?.isEssential ?? false,
            carriedIn: carriedIn
        )
    }

    static func commitment(_ rule: RecurringRule) -> BudgetEngine.CommitmentInput {
        BudgetEngine.CommitmentInput(
            id: rule.id,
            label: rule.label,
            amount: rule.amount,
            occurrencesPerYear: rule.occurrencesPerYear
        )
    }

    static func scheduled(_ rule: RecurringRule) -> ForecastEngine.ScheduledItem {
        ForecastEngine.ScheduledItem(
            id: rule.id, label: rule.label, amount: rule.amount, kind: rule.kind,
            cadence: rule.cadence, nextDueDate: rule.nextDueDate, endDate: rule.endDate,
            isVariableAmount: rule.isVariableAmount,
            isCommittedOutflow: rule.isCommittedOutflow
        )
    }

    static func oneOff(_ event: ScheduledEvent) -> ForecastEngine.OneOffItem {
        ForecastEngine.OneOffItem(
            id: event.id, label: event.label,
            // Already weighted: a `.maybe` arrives halved.
            amount: event.projectedAmount, kind: .expense,
            date: event.expectedDate, confidence: event.confidence
        )
    }

    static func loan(_ loan: Loan) -> LoanEngine.LoanInput {
        let payments = (loan.payments ?? []).filter { $0.deletedAt == nil }
        return LoanEngine.LoanInput(
            id: loan.id, name: loan.name, lender: loan.lender, direction: loan.direction,
            principal: loan.principal, interestModel: loan.interestModel,
            startDate: loan.startDate, termMonths: loan.termMonths,
            paymentFrequency: loan.paymentFrequency, socialWeight: loan.socialWeight,
            status: loan.status,
            paidPrincipal: Money.sum(payments.map(\.principalPortion)),
            paidInterest: Money.sum(payments.map(\.interestPortion)),
            paymentsMade: payments.count,
            lateCount: payments.filter(\.isLate).count
        )
    }

    static func goal(_ goal: Goal, earmarks: [Earmark]) -> GoalEngine.GoalInput {
        GoalEngine.GoalInput(
            id: goal.id, name: goal.name, targetAmount: goal.targetAmount,
            targetDate: goal.targetDate, priorityRank: goal.priorityRank,
            holdingAccountID: goal.holdingAccount?.id, monthlyCap: goal.monthlyCap,
            desireLevel: goal.desireLevel, status: goal.status,
            saved: Money.sum(
                earmarks.filter { $0.ownerID == goal.id && $0.deletedAt == nil }.map(\.amount)
            )
        )
    }

    static func fund(_ fund: SinkingFund, earmarks: [Earmark],
                     periodsRemaining: Int) -> GoalEngine.FundInput {
        let saved = Money.sum(
            earmarks.filter { $0.ownerID == fund.id && $0.deletedAt == nil }.map(\.amount)
        )
        return GoalEngine.FundInput(
            id: fund.id, name: fund.name,
            requiredThisPeriod: fund.requiredPerPeriod(saved: saved,
                                                       periodsRemaining: periodsRemaining),
            isEmergencyFund: fund.isEmergencyFund
        )
    }

    static func record(_ earmark: Earmark) -> BalanceEngine.EarmarkRecord {
        BalanceEngine.EarmarkRecord(
            id: earmark.id,
            ownerType: earmark.ownerType,
            ownerID: earmark.ownerID,
            accountID: earmark.account?.id,
            amount: earmark.amount
        )
    }
}
