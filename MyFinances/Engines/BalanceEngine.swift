import Foundation

/// Derives every balance in the app from the ledger. Balances are never stored as
/// editable state — this is the only thing that computes them.
///
/// Pure functions over value types: no SwiftData, no `@Environment`, no writes.
nonisolated enum BalanceEngine {

    // MARK: - Inputs

    struct AccountRecord: Identifiable, Hashable, Sendable {
        let id: UUID
        let name: String
        let type: AccountType
        let openingBalance: Money
        let colorHex: String
        let icon: String
        let sortOrder: Int
        let includeInNetWorth: Bool
        let isLiquid: Bool
        let lowBalanceFloor: Money?
        let isArchived: Bool
        let isTaxReserve: Bool
        let isEmergencyFundAccount: Bool
    }

    struct TransactionRecord: Identifiable, Hashable, Sendable {
        let id: UUID
        let date: Date
        let amount: Money
        let kind: TransactionKind
        let accountID: UUID?
        let counterAccountID: UUID?
        let categoryID: UUID?
        let isEstimate: Bool
    }

    struct EarmarkRecord: Identifiable, Hashable, Sendable {
        let id: UUID
        let ownerType: EarmarkOwnerType
        let ownerID: UUID
        let accountID: UUID?
        let amount: Money
    }

    // MARK: - Outputs

    struct AccountBalance: Identifiable, Hashable, Sendable {
        let account: AccountRecord
        let balance: Money
        let earmarked: Money

        var id: UUID { account.id }

        /// What is actually spendable: balance minus earmarks.
        var available: Money { balance - earmarked }

        /// The invariant from CLAUDE.md: earmarks must not exceed the balance they sit
        /// against. When this is true the account is **over-committed** — surfaced as a
        /// warning, never silently rebalanced.
        var isOverCommitted: Bool { earmarked > balance }

        var isBelowFloor: Bool {
            guard let floor = account.lowBalanceFloor else { return false }
            return balance < floor
        }
    }

    struct Totals: Sendable {
        /// Everything in accounts marked `includeInNetWorth`, minus what is owed.
        /// A tax reserve is excluded: it is not your money.
        let netWorth: Money
        /// Spendable today, after earmarks. Excludes tax reserve and illiquid accounts.
        let liquidAvailable: Money
        /// Liquid balance before earmarks, for the over-commitment warning.
        let liquidBalance: Money
        let earmarkedTotal: Money
        let taxReserved: Money
    }

    // MARK: - Derivation

    /// Signed effect of one transaction on one account.
    /// A transfer moves money: it debits the source and credits the destination, and
    /// the two cancel. It must never reach an income or expense total.
    static func effect(of transaction: TransactionRecord, on accountID: UUID) -> Money {
        var result = Money.zero
        if transaction.accountID == accountID {
            result += transaction.kind == .income ? transaction.amount : -transaction.amount
        }
        if transaction.kind == .transfer, transaction.counterAccountID == accountID {
            result += transaction.amount
        }
        return result
    }

    static func balances(
        accounts: [AccountRecord],
        transactions: [TransactionRecord],
        earmarks: [EarmarkRecord],
        asOf date: Date? = nil
    ) -> [AccountBalance] {
        var movement: [UUID: Money] = [:]
        for transaction in transactions {
            if let cutoff = date, transaction.date > cutoff { continue }
            if let source = transaction.accountID {
                movement[source, default: .zero] += transaction.kind == .income
                    ? transaction.amount : -transaction.amount
            }
            if transaction.kind == .transfer, let destination = transaction.counterAccountID {
                movement[destination, default: .zero] += transaction.amount
            }
        }

        var reserved: [UUID: Money] = [:]
        for earmark in earmarks {
            guard let accountID = earmark.accountID else { continue }
            reserved[accountID, default: .zero] += earmark.amount
        }

        return accounts.map { account in
            AccountBalance(
                account: account,
                balance: account.openingBalance + (movement[account.id] ?? .zero),
                earmarked: reserved[account.id] ?? .zero
            )
        }
    }

    static func totals(for balances: [AccountBalance]) -> Totals {
        var netWorth = Money.zero
        var liquidAvailable = Money.zero
        var liquidBalance = Money.zero
        var earmarkedTotal = Money.zero
        var taxReserved = Money.zero

        for entry in balances where !entry.account.isArchived {
            if entry.account.isTaxReserve {
                // Not an asset, not spendable, not part of runway.
                taxReserved += entry.balance
                continue
            }
            if entry.account.includeInNetWorth { netWorth += entry.balance }
            earmarkedTotal += entry.earmarked
            if entry.account.isLiquid {
                liquidBalance += entry.balance
                liquidAvailable += entry.available
            }
        }

        return Totals(
            netWorth: netWorth,
            liquidAvailable: liquidAvailable,
            liquidBalance: liquidBalance,
            earmarkedTotal: earmarkedTotal,
            taxReserved: taxReserved
        )
    }

    /// Total spend over a half-open interval. Transfers are excluded by construction —
    /// moving your own money is not spending.
    static func spend(
        transactions: [TransactionRecord],
        in interval: DateInterval,
        categoryIDs: Set<UUID>? = nil
    ) -> Money {
        Money.sum(
            transactions.compactMap { transaction in
                guard transaction.kind == .expense,
                      interval.start <= transaction.date, transaction.date < interval.end
                else { return nil }
                if let categoryIDs {
                    guard let categoryID = transaction.categoryID,
                          categoryIDs.contains(categoryID) else { return nil }
                }
                return transaction.amount
            }
        )
    }

    // MARK: - Reconciliation

    struct Reconciliation: Sendable {
        let derived: Money
        let actual: Money
        /// Positive when the real world holds more than the ledger says.
        var gap: Money { actual - derived }
        var isClean: Bool { gap.isZero }

        /// The single balancing entry that closes the gap. Income when money turned up
        /// unaccounted for, expense when it went missing.
        var adjustmentKind: TransactionKind { gap.isNegative ? .expense : .income }
        var adjustmentAmount: Money { gap.magnitude }
    }

    /// Compare the ledger against a real-world balance the user has counted.
    static func reconcile(derived: Money, actual: Money) -> Reconciliation {
        Reconciliation(derived: derived, actual: actual)
    }

    /// Nag if nothing has been reconciled in this many days.
    static let reconciliationGraceDays = 14

    /// Days since the most recent reconciliation, or nil if there has never been one.
    static func daysSinceReconciliation(
        lastReconciledOn: Date?,
        today: Date,
        calendar: FinancialCalendar
    ) -> Int? {
        guard let lastReconciledOn else { return nil }
        return calendar.daysBetween(lastReconciledOn, today)
    }

    static func needsReconciliation(
        lastReconciledOn: Date?,
        today: Date,
        calendar: FinancialCalendar
    ) -> Bool {
        guard let days = daysSinceReconciliation(lastReconciledOn: lastReconciledOn,
                                                 today: today, calendar: calendar)
        else { return true }
        return days >= reconciliationGraceDays
    }

    static func income(transactions: [TransactionRecord], in interval: DateInterval) -> Money {
        Money.sum(
            transactions.compactMap { transaction in
                guard transaction.kind == .income,
                      interval.start <= transaction.date, transaction.date < interval.end
                else { return nil }
                return transaction.amount
            }
        )
    }
}
