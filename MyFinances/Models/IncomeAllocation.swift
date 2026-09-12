import Foundation
import SwiftData

/// One slice of a windfall. The slices on an event must sum exactly to `netUsable`.
@Model
final class IncomeAllocation {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var incomeEvent: IncomeEvent?
    var destinationKindRaw: String = AllocationDestinationKind.free.rawValue
    /// Goal, sinking fund or loan the slice goes to, when the kind names one.
    var destinationID: UUID?
    var destinationAccount: Account?
    var amountMinorUnits: Int = 0
    var label: String = ""

    init(
        incomeEvent: IncomeEvent?,
        destinationKind: AllocationDestinationKind,
        destinationID: UUID? = nil,
        destinationAccount: Account? = nil,
        amount: Money,
        label: String,
        now: Date = Date()
    ) {
        precondition(!amount.isNegative, "An allocation slice is never negative")
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.incomeEvent = incomeEvent
        self.destinationKindRaw = destinationKind.rawValue
        self.destinationID = destinationID
        self.destinationAccount = destinationAccount
        self.amountMinorUnits = amount.minorUnits
        self.label = label
    }

    var destinationKind: AllocationDestinationKind {
        get { AllocationDestinationKind(rawValue: destinationKindRaw) ?? .free }
        set { destinationKindRaw = newValue.rawValue }
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set { amountMinorUnits = newValue.minorUnits }
    }
}
