import Foundation
import SwiftData

/// The one place the schema is declared. Every new `@Model` type is registered here.
enum TranquilSchema {
    static let models: [any PersistentModel.Type] = [
        AppSettings.self,
        Account.self,
        Category.self,
        Transaction.self,
        Budget.self,
        RecurringRule.self,
        Loan.self,
        LoanPayment.self,
        Goal.self,
        Earmark.self,
        SinkingFund.self,
        ScheduledEvent.self,
        IncomeEvent.self,
        IncomeAllocation.self,
        OverrideLog.self,
        DailyLog.self,
        LadderState.self,
        BalanceSnapshot.self,
    ]

    static var schema: Schema { Schema(models) }

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
