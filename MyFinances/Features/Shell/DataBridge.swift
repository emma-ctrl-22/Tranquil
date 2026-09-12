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
