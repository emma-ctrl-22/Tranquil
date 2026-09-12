import Foundation
import SwiftData

/// One ledger row.
///
/// A transfer is **one** record with a `counterAccount`, never two rows. Transfers
/// must never reach income or expense totals — `BalanceEngine` asserts this.
@Model
final class Transaction {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var date: Date = Date()
    /// Always positive. Direction comes from `kind`; there are no negative amounts stored.
    var amountMinorUnits: Int = 0
    var kindRaw: String = TransactionKind.expense.rawValue

    /// Source for expense and transfer; destination for income.
    var account: Account?
    /// Destination. Transfers only.
    var counterAccount: Account?

    var category: Category?
    var subcategory: String?

    var note: String?
    var tags: [String] = []

    /// Logged from memory — flagged for later correction and queued in Needs review.
    var isEstimate: Bool = false

    var recurringRuleID: UUID?
    var loanID: UUID?
    var goalID: UUID?
    var sinkingFundID: UUID?
    var incomeEventID: UUID?

    /// Local receipt photo. Never uploaded anywhere.
    var attachmentPath: String?

    /// Written by Reconcile as the single balancing "Unaccounted" adjustment.
    var isReconciliationAdjustment: Bool = false

    init(
        date: Date,
        amount: Money,
        kind: TransactionKind,
        account: Account?,
        counterAccount: Account? = nil,
        category: Category? = nil,
        subcategory: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        isEstimate: Bool = false,
        now: Date = Date()
    ) {
        precondition(!amount.isNegative, "Transaction amounts are stored positive; direction comes from kind")
        precondition(
            kind != .transfer || counterAccount != nil,
            "A transfer needs a counterAccount"
        )
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.date = date
        self.amountMinorUnits = amount.minorUnits
        self.kindRaw = kind.rawValue
        self.account = account
        self.counterAccount = counterAccount
        self.category = category
        self.subcategory = subcategory
        self.note = note
        self.tags = tags
        self.isEstimate = isEstimate
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set {
            precondition(!newValue.isNegative, "Transaction amounts are stored positive")
            amountMinorUnits = newValue.minorUnits
        }
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Signed effect on `account`'s balance.
    var effectOnPrimaryAccount: Money {
        switch kind {
        case .income: amount
        case .expense, .transfer: -amount
        }
    }

    /// Signed effect on `counterAccount`'s balance — non-zero for transfers only.
    var effectOnCounterAccount: Money {
        kind == .transfer ? amount : .zero
    }
}
