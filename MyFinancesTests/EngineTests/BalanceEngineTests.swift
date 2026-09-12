import Testing
import Foundation
@testable import MyFinances

/// Balances are derived, never stored. These are the golden tests for that derivation.
struct BalanceEngineTests {

    private let cashID = UUID()
    private let bankID = UUID()
    private let taxID = UUID()
    private let lentID = UUID()

    private func account(
        _ id: UUID, _ name: String, _ type: AccountType, opening: Int,
        liquid: Bool? = nil, netWorth: Bool? = nil, floor: Int? = nil,
        taxReserve: Bool = false, archived: Bool = false
    ) -> BalanceEngine.AccountRecord {
        BalanceEngine.AccountRecord(
            id: id, name: name, type: type, openingBalance: Money(minorUnits: opening),
            colorHex: "#000000", icon: "circle", sortOrder: 0,
            includeInNetWorth: netWorth ?? type.countsInNetWorthByDefault,
            isLiquid: liquid ?? type.isLiquidByDefault,
            lowBalanceFloor: floor.map(Money.init(minorUnits:)),
            isArchived: archived, isTaxReserve: taxReserve, isEmergencyFundAccount: false
        )
    }

    private func transaction(
        _ amount: Int, _ kind: TransactionKind, from: UUID?, to: UUID? = nil,
        day: Int = 0, category: UUID? = nil
    ) -> BalanceEngine.TransactionRecord {
        BalanceEngine.TransactionRecord(
            id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            amount: Money(minorUnits: amount), kind: kind,
            accountID: from, counterAccountID: to, categoryID: category, isEstimate: false
        )
    }

    // MARK: - Derivation

    @Test func balanceIsOpeningPlusMovement() {
        // 100.00 opening, +50.00 income, −12.50 spend = 137.50
        let accounts = [account(cashID, "Cash", .cash, opening: 10_000)]
        let transactions = [
            transaction(5_000, .income, from: cashID),
            transaction(1_250, .expense, from: cashID),
        ]
        let result = BalanceEngine.balances(accounts: accounts, transactions: transactions,
                                            earmarks: [])
        #expect(result[0].balance.minorUnits == 13_750)
    }

    @Test func aTransferMovesMoneyWithoutCreatingOrDestroyingIt() {
        let accounts = [
            account(cashID, "Cash", .cash, opening: 10_000),
            account(bankID, "Bank", .bank, opening: 20_000),
        ]
        let transactions = [transaction(4_000, .transfer, from: cashID, to: bankID)]
        let result = BalanceEngine.balances(accounts: accounts, transactions: transactions,
                                            earmarks: [])
        let cash = result.first { $0.account.id == cashID }!
        let bank = result.first { $0.account.id == bankID }!
        #expect(cash.balance.minorUnits == 6_000)
        #expect(bank.balance.minorUnits == 24_000)
        // The total is unchanged: this is the bug every finance app ships.
        #expect((cash.balance + bank.balance).minorUnits == 30_000)
    }

    @Test func transfersNeverReachSpendOrIncomeTotals() {
        let transactions = [
            transaction(4_000, .transfer, from: cashID, to: bankID),
            transaction(1_500, .expense, from: cashID),
            transaction(9_000, .income, from: bankID),
        ]
        let interval = DateInterval(start: Date(timeIntervalSince1970: -86_400),
                                    duration: 86_400 * 10)
        #expect(BalanceEngine.spend(transactions: transactions, in: interval).minorUnits == 1_500)
        #expect(BalanceEngine.income(transactions: transactions, in: interval).minorUnits == 9_000)
    }

    @Test func effectOnAccountIsSignedByKind() {
        let income = transaction(5_000, .income, from: cashID)
        let expense = transaction(5_000, .expense, from: cashID)
        let transfer = transaction(5_000, .transfer, from: cashID, to: bankID)
        #expect(BalanceEngine.effect(of: income, on: cashID).minorUnits == 5_000)
        #expect(BalanceEngine.effect(of: expense, on: cashID).minorUnits == -5_000)
        #expect(BalanceEngine.effect(of: transfer, on: cashID).minorUnits == -5_000)
        #expect(BalanceEngine.effect(of: transfer, on: bankID).minorUnits == 5_000)
        #expect(BalanceEngine.effect(of: transfer, on: taxID).isZero)
    }

    @Test func asOfDateExcludesLaterTransactions() {
        let accounts = [account(cashID, "Cash", .cash, opening: 10_000)]
        let transactions = [
            transaction(1_000, .expense, from: cashID, day: 1),
            transaction(2_000, .expense, from: cashID, day: 5),
        ]
        let cutoff = Date(timeIntervalSince1970: 3 * 86_400)
        let result = BalanceEngine.balances(accounts: accounts, transactions: transactions,
                                            earmarks: [], asOf: cutoff)
        #expect(result[0].balance.minorUnits == 9_000)
    }

    // MARK: - Earmarks

    @Test func availableIsBalanceMinusEarmarks() {
        let accounts = [account(cashID, "Cash", .cash, opening: 10_000)]
        let earmarks = [
            BalanceEngine.EarmarkRecord(id: UUID(), ownerType: .goal, ownerID: UUID(),
                                        accountID: cashID, amount: Money(minorUnits: 3_000)),
            BalanceEngine.EarmarkRecord(id: UUID(), ownerType: .sinkingFund, ownerID: UUID(),
                                        accountID: cashID, amount: Money(minorUnits: 2_000)),
        ]
        let result = BalanceEngine.balances(accounts: accounts, transactions: [],
                                            earmarks: earmarks)
        #expect(result[0].earmarked.minorUnits == 5_000)
        #expect(result[0].available.minorUnits == 5_000)
        #expect(!result[0].isOverCommitted)
    }

    @Test func overCommitmentIsSurfacedNotSilentlyFixed() {
        // The CLAUDE.md invariant: earmarks must not exceed the balance.
        let accounts = [account(cashID, "Cash", .cash, opening: 4_000)]
        let earmarks = [
            BalanceEngine.EarmarkRecord(id: UUID(), ownerType: .goal, ownerID: UUID(),
                                        accountID: cashID, amount: Money(minorUnits: 6_000))
        ]
        let result = BalanceEngine.balances(accounts: accounts, transactions: [],
                                            earmarks: earmarks)
        #expect(result[0].isOverCommitted)
        // The engine reports the real, negative figure rather than clamping it away.
        #expect(result[0].available.minorUnits == -2_000)
        #expect(result[0].balance.minorUnits == 4_000)
    }

    @Test func lowBalanceFloorIsDetected() {
        let accounts = [account(cashID, "Cash", .cash, opening: 1_500, floor: 2_000)]
        let result = BalanceEngine.balances(accounts: accounts, transactions: [], earmarks: [])
        #expect(result[0].isBelowFloor)
    }

    // MARK: - Totals

    @Test func taxReserveIsNotYourMoney() {
        let accounts = [
            account(cashID, "Cash", .cash, opening: 10_000),
            account(taxID, "Tax reserve", .savings, opening: 50_000, taxReserve: true),
        ]
        let totals = BalanceEngine.totals(
            for: BalanceEngine.balances(accounts: accounts, transactions: [], earmarks: [])
        )
        // Excluded from net worth, from liquid available, and from runway.
        #expect(totals.netWorth.minorUnits == 10_000)
        #expect(totals.liquidAvailable.minorUnits == 10_000)
        #expect(totals.taxReserved.minorUnits == 50_000)
    }

    @Test func moneyLentOutIsNotAnAsset() {
        // R11: a receivable is logged at zero expected return, never counted as wealth.
        let accounts = [
            account(cashID, "Cash", .cash, opening: 10_000),
            account(lentID, "Lent to Kojo", .receivable, opening: 50_000),
        ]
        let totals = BalanceEngine.totals(
            for: BalanceEngine.balances(accounts: accounts, transactions: [], earmarks: [])
        )
        #expect(totals.netWorth.minorUnits == 10_000)
        #expect(totals.liquidAvailable.minorUnits == 10_000)
    }

    @Test func illiquidAccountsCountForNetWorthButNotForSpending() {
        let investmentID = UUID()
        let accounts = [
            account(cashID, "Cash", .cash, opening: 10_000),
            account(investmentID, "Investment", .investment, opening: 300_000),
        ]
        let totals = BalanceEngine.totals(
            for: BalanceEngine.balances(accounts: accounts, transactions: [], earmarks: [])
        )
        #expect(totals.netWorth.minorUnits == 310_000)
        #expect(totals.liquidAvailable.minorUnits == 10_000)
    }

    @Test func archivedAccountsAreExcludedFromEveryTotal() {
        let accounts = [
            account(cashID, "Cash", .cash, opening: 10_000),
            account(bankID, "Old bank", .bank, opening: 99_000, archived: true),
        ]
        let totals = BalanceEngine.totals(
            for: BalanceEngine.balances(accounts: accounts, transactions: [], earmarks: [])
        )
        #expect(totals.netWorth.minorUnits == 10_000)
        #expect(totals.liquidAvailable.minorUnits == 10_000)
    }

    @Test func emptyDatabaseProducesZeros() {
        let totals = BalanceEngine.totals(
            for: BalanceEngine.balances(accounts: [], transactions: [], earmarks: [])
        )
        #expect(totals.netWorth.isZero)
        #expect(totals.liquidAvailable.isZero)
        #expect(totals.taxReserved.isZero)
        #expect(totals.earmarkedTotal.isZero)
    }

    @Test func spendFiltersByCategoryAndInterval() {
        let lunchID = UUID()
        let trotroID = UUID()
        let transactions = [
            transaction(1_500, .expense, from: cashID, day: 1, category: lunchID),
            transaction(500, .expense, from: cashID, day: 1, category: trotroID),
            transaction(9_900, .expense, from: cashID, day: 40, category: lunchID),
        ]
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0),
                                    duration: 86_400 * 7)
        #expect(BalanceEngine.spend(transactions: transactions, in: interval).minorUnits == 2_000)
        #expect(BalanceEngine.spend(transactions: transactions, in: interval,
                                    categoryIDs: [lunchID]).minorUnits == 1_500)
    }

    @Test func intervalBoundariesAreHalfOpen() {
        // A transaction exactly on `end` belongs to the next period, not this one.
        let start = Date(timeIntervalSince1970: 0)
        let transactions = [
            BalanceEngine.TransactionRecord(id: UUID(), date: start,
                                            amount: Money(minorUnits: 100), kind: .expense,
                                            accountID: cashID, counterAccountID: nil,
                                            categoryID: nil, isEstimate: false),
            BalanceEngine.TransactionRecord(id: UUID(),
                                            date: start.addingTimeInterval(86_400 * 7),
                                            amount: Money(minorUnits: 900), kind: .expense,
                                            accountID: cashID, counterAccountID: nil,
                                            categoryID: nil, isEstimate: false),
        ]
        let interval = DateInterval(start: start, duration: 86_400 * 7)
        #expect(BalanceEngine.spend(transactions: transactions, in: interval).minorUnits == 100)
    }

    @Test func handlesFiveThousandTransactionsQuickly() {
        let accounts = [account(cashID, "Cash", .cash, opening: 1_000_000)]
        let transactions = (0..<5_000).map { index in
            transaction(100 + index % 500, .expense, from: cashID, day: index % 365)
        }
        let started = Date()
        let result = BalanceEngine.balances(accounts: accounts, transactions: transactions,
                                            earmarks: [])
        #expect(result.count == 1)
        #expect(Date().timeIntervalSince(started) < 1.0, "5,000 transactions must derive fast")
    }
}

/// Reconciliation closes the gap between the ledger and the real world with one
/// visible entry, never by rewriting history.
struct ReconciliationTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func calendar(now: Date) -> FinancialCalendar {
        FinancialCalendar(timeZone: utc, now: { now })
    }

    @Test func aMatchingCountNeedsNoAdjustment() {
        let result = BalanceEngine.reconcile(derived: Money(minorUnits: 12_500),
                                             actual: Money(minorUnits: 12_500))
        #expect(result.isClean)
        #expect(result.gap.isZero)
        #expect(result.adjustmentAmount.isZero)
    }

    @Test func missingMoneyPostsAnExpense() {
        // Ledger says 125.00, only 100.00 is really there: 25.00 was spent unlogged.
        let result = BalanceEngine.reconcile(derived: Money(minorUnits: 12_500),
                                             actual: Money(minorUnits: 10_000))
        #expect(!result.isClean)
        #expect(result.gap.minorUnits == -2_500)
        #expect(result.adjustmentKind == .expense)
        // The posted amount is positive: direction lives in `kind`, never in the sign.
        #expect(result.adjustmentAmount.minorUnits == 2_500)
    }

    @Test func extraMoneyPostsIncome() {
        let result = BalanceEngine.reconcile(derived: Money(minorUnits: 10_000),
                                             actual: Money(minorUnits: 12_500))
        #expect(result.gap.minorUnits == 2_500)
        #expect(result.adjustmentKind == .income)
        #expect(result.adjustmentAmount.minorUnits == 2_500)
    }

    @Test func adjustmentAlwaysClosesTheGapExactly() {
        for derived in stride(from: -5_000, through: 5_000, by: 311) {
            for actual in stride(from: -5_000, through: 5_000, by: 733) {
                let result = BalanceEngine.reconcile(derived: Money(minorUnits: derived),
                                                     actual: Money(minorUnits: actual))
                let signed = result.adjustmentKind == .income
                    ? result.adjustmentAmount : -result.adjustmentAmount
                #expect((Money(minorUnits: derived) + signed).minorUnits == actual)
                #expect(!result.adjustmentAmount.isNegative)
            }
        }
    }

    @Test func nagsAfterFourteenDays() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let fc = calendar(now: now)
        let today = fc.today()
        #expect(!BalanceEngine.needsReconciliation(
            lastReconciledOn: fc.addDays(-13, to: today), today: today, calendar: fc))
        #expect(BalanceEngine.needsReconciliation(
            lastReconciledOn: fc.addDays(-14, to: today), today: today, calendar: fc))
        // Never reconciled at all also counts as due.
        #expect(BalanceEngine.needsReconciliation(
            lastReconciledOn: nil, today: today, calendar: fc))
        #expect(BalanceEngine.daysSinceReconciliation(
            lastReconciledOn: nil, today: today, calendar: fc) == nil)
    }
}

@MainActor
struct DailyLogServiceTests {
    private func makeCalendar(now: Date) -> FinancialCalendar {
        FinancialCalendar(timeZone: TimeZone(identifier: "UTC")!, now: { now })
    }

    @Test func streakCountsConsecutiveLoggedDays() {
        let fc = makeCalendar(now: Date(timeIntervalSince1970: 1_789_000_000))
        let today = fc.today()
        let logs = [
            DailyLog(date: today, entryCount: 2),
            DailyLog(date: fc.addDays(-1, to: today), entryCount: 1),
            DailyLog(date: fc.addDays(-2, to: today), entryCount: 4),
            // Gap at -3.
            DailyLog(date: fc.addDays(-4, to: today), entryCount: 1),
        ]
        #expect(DailyLogService.currentStreak(logs: logs, today: today, calendar: fc) == 3)
    }

    @Test func todayNotYetLoggedDoesNotBreakTheStreak() {
        // The day is not over. A streak that punishes you at 09:00 is a streak you mute.
        let fc = makeCalendar(now: Date(timeIntervalSince1970: 1_789_000_000))
        let today = fc.today()
        let logs = [
            DailyLog(date: fc.addDays(-1, to: today), entryCount: 1),
            DailyLog(date: fc.addDays(-2, to: today), entryCount: 1),
        ]
        #expect(DailyLogService.currentStreak(logs: logs, today: today, calendar: fc) == 2)
    }

    @Test func emptyHistoryIsZero() {
        let fc = makeCalendar(now: Date(timeIntervalSince1970: 1_789_000_000))
        #expect(DailyLogService.currentStreak(logs: [], today: fc.today(), calendar: fc) == 0)
    }
}
