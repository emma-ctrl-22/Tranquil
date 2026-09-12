import Foundation
import SwiftData

/// Keeps an `IncomeEvent` and the ledger in step.
///
/// An income event that never reaches the ledger is a number in a corner of the app that
/// no balance, no salary check and no chart can see. Every event writes exactly one
/// income `Transaction`, and the tax reserve moves as its own transfer.
@MainActor
enum IncomeEventService {

    /// Writes the ledger entries for a newly recorded inflow.
    ///
    /// - The full gross lands in the receiving account as income.
    /// - The tax reserve immediately transfers out to the reserve account, if one exists,
    ///   so it is never counted as spendable.
    @discardableResult
    static func post(
        _ event: IncomeEvent, in context: ModelContext, calendar: FinancialCalendar
    ) -> Transaction? {
        guard let account = event.account, event.grossAmount.isPositive else { return nil }

        let income = Transaction(
            date: event.receivedAt,
            amount: event.grossAmount,
            kind: .income,
            account: account,
            note: event.clientOrSource ?? label(for: event.kind)
        )
        income.incomeEventID = event.id
        context.insert(income)
        event.transactionID = income.id

        if event.taxReserved.isPositive,
           let reserve = taxReserveAccount(in: context), reserve.id != account.id {
            let transfer = Transaction(
                date: event.receivedAt,
                amount: event.taxReserved,
                kind: .transfer,
                account: account,
                counterAccount: reserve,
                note: "Tax reserve"
            )
            transfer.incomeEventID = event.id
            context.insert(transfer)
        }

        DailyLogService.recordEntry(on: event.receivedAt, in: context, calendar: calendar)
        return income
    }

    /// Carries out an allocation: earmarks for goals and funds, transfers for
    /// investments, and nothing at all for the free slice — that one is yours.
    static func apply(
        allocations: [(slice: IncomeEngine.Slice, amount: Money)],
        for event: IncomeEvent,
        goalID: UUID?,
        sinkingFundID: UUID?,
        in context: ModelContext,
        calendar: FinancialCalendar
    ) {
        for entry in allocations where entry.amount.isPositive {
            switch entry.slice.kind {
            case .goal:
                guard let goalID else { continue }
                addEarmark(ownerType: .goal, ownerID: goalID, amount: entry.amount,
                           account: event.account, in: context, calendar: calendar)
            case .sinkingFund:
                guard let sinkingFundID else { continue }
                addEarmark(ownerType: .sinkingFund, ownerID: sinkingFundID,
                           amount: entry.amount, account: event.account,
                           in: context, calendar: calendar)
            case .investment:
                guard let source = event.account,
                      let destination = investmentAccount(in: context) else { continue }
                let transfer = Transaction(
                    date: calendar.currentDate(), amount: entry.amount, kind: .transfer,
                    account: source, counterAccount: destination, note: "Allocated to investing"
                )
                transfer.incomeEventID = event.id
                context.insert(transfer)
            case .ladderGap, .debtPayment:
                // Where this lands depends on which step you are on, so it is left as an
                // instruction rather than guessed at. The Advisor screen names the step.
                continue
            case .free, .taxReserve:
                continue
            }
        }
    }

    private static func addEarmark(
        ownerType: EarmarkOwnerType, ownerID: UUID, amount: Money, account: Account?,
        in context: ModelContext, calendar: FinancialCalendar
    ) {
        let descriptor = FetchDescriptor<Earmark>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.deletedAt == nil }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.amount = existing.amount + amount
            existing.updatedAt = calendar.currentDate()
        } else {
            context.insert(Earmark(ownerType: ownerType, ownerID: ownerID,
                                   account: account, amount: amount))
        }
    }

    private static func taxReserveAccount(in context: ModelContext) -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.isTaxReserve && $0.deletedAt == nil }
        )
        return try? context.fetch(descriptor).first
    }

    private static func investmentAccount(in context: ModelContext) -> Account? {
        let accounts = (try? context.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        return accounts.first { $0.type == .investment && !$0.isArchived }
    }

    /// Should this inflow be held back until it has been allocated?
    static func shouldIntercept(
        amount: Money, kind: IncomeEventKind, settings: AppSettings,
        medianWeeklyIncome: Money
    ) -> Bool {
        guard kind.countsAsIncome else { return false }
        return IncomeEngine.isWindfall(amount, medianWeeklyIncome: medianWeeklyIncome,
                                       multiple: settings.windfallMultiple)
    }

    private static func label(for kind: IncomeEventKind) -> String {
        switch kind {
        case .projectPayment: "Project payment"
        case .salaryRise: "Salary rise"
        case .bonus: "Bonus"
        case .gift: "Gift"
        case .refund: "Refund"
        case .assetSale: "Asset sale"
        }
    }
}
