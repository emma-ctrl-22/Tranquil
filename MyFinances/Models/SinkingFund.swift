import Foundation
import SwiftData

/// Saving toward a known future expense — a target, a date, and a holding account.
@Model
final class SinkingFund {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var name: String = ""
    var targetAmountMinorUnits: Int = 0
    var targetDate: Date?
    var cadenceRaw: String = BudgetPeriod.monthly.rawValue
    var holdingAccount: Account?
    /// Special: a Ladder requirement, never auto-raided by the allocation engine,
    /// and spending from it needs an explicit confirm plus a logged reason.
    var isEmergencyFund: Bool = false
    var icon: String = "umbrella"
    var colorHex: String = "#7C8B9A"
    var sortOrder: Int = 0
    var notes: String?

    init(
        name: String,
        targetAmount: Money,
        targetDate: Date? = nil,
        cadence: BudgetPeriod = .monthly,
        holdingAccount: Account?,
        isEmergencyFund: Bool = false,
        icon: String = "umbrella",
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.name = name
        self.targetAmountMinorUnits = targetAmount.minorUnits
        self.targetDate = targetDate
        self.cadenceRaw = cadence.rawValue
        self.holdingAccount = holdingAccount
        self.isEmergencyFund = isEmergencyFund
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var targetAmount: Money {
        get { Money(minorUnits: targetAmountMinorUnits) }
        set { targetAmountMinorUnits = newValue.minorUnits }
    }

    var cadence: BudgetPeriod {
        get { BudgetPeriod(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    /// `(target - saved) / periodsRemaining`, clamped so a passed date asks for the
    /// whole remainder rather than dividing by zero.
    func requiredPerPeriod(saved: Money, periodsRemaining: Int) -> Money {
        let remaining = (targetAmount - saved).clampedToZero
        guard periodsRemaining > 0 else { return remaining }
        return remaining.split(into: periodsRemaining).first ?? .zero
    }
}
