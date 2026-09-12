import Foundation

/// Everything in the store is soft-deleted, so anything reading it generically needs to
/// be able to ask. Saves repeating the same filter per model type.
protocol SoftDeletable {
    var deletedAt: Date? { get }
}

extension Account: SoftDeletable {}
extension Transaction: SoftDeletable {}
extension Category: SoftDeletable {}
extension Budget: SoftDeletable {}
extension RecurringRule: SoftDeletable {}
extension Loan: SoftDeletable {}
extension LoanPayment: SoftDeletable {}
extension Goal: SoftDeletable {}
extension Earmark: SoftDeletable {}
extension SinkingFund: SoftDeletable {}
extension ScheduledEvent: SoftDeletable {}
extension IncomeEvent: SoftDeletable {}
extension IncomeAllocation: SoftDeletable {}
extension OverrideLog: SoftDeletable {}
extension DailyLog: SoftDeletable {}
extension LadderState: SoftDeletable {}
extension BalanceSnapshot: SoftDeletable {}
extension Valuation: SoftDeletable {}
