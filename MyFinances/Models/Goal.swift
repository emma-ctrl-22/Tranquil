import Foundation
import SwiftData

/// A goal covers wishlist items too. Its saved amount is an `Earmark` against
/// `holdingAccount`, never a separate balance.
@Model
final class Goal {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var name: String = ""
    var targetAmountMinorUnits: Int = 0
    var targetDate: Date?
    /// Manual, drag to reorder. The app never reorders the user's priorities.
    var priorityRank: Int = 0
    /// Where the money physically sits while saving.
    var holdingAccount: Account?
    /// Don't throw everything at one goal.
    var monthlyCapMinorUnits: Int?
    var desireLevel: Int = 3
    var statusRaw: String = GoalStatus.saving.rawValue

    var actualPricePaidMinorUnits: Int?
    var purchasedAt: Date?

    /// Manual price watch — there is no internet in this app.
    var lastPriceCheckedAt: Date?
    var notes: String?

    init(
        name: String,
        targetAmount: Money,
        targetDate: Date? = nil,
        priorityRank: Int,
        holdingAccount: Account?,
        monthlyCap: Money? = nil,
        desireLevel: Int = 3,
        status: GoalStatus = .saving,
        now: Date = Date()
    ) {
        precondition((1...5).contains(desireLevel), "desireLevel is 1...5")
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.name = name
        self.targetAmountMinorUnits = targetAmount.minorUnits
        self.targetDate = targetDate
        self.priorityRank = priorityRank
        self.holdingAccount = holdingAccount
        self.monthlyCapMinorUnits = monthlyCap?.minorUnits
        self.desireLevel = desireLevel
        self.statusRaw = status.rawValue
    }

    var targetAmount: Money {
        get { Money(minorUnits: targetAmountMinorUnits) }
        set { targetAmountMinorUnits = newValue.minorUnits }
    }
    var monthlyCap: Money? {
        get { monthlyCapMinorUnits.map(Money.init(minorUnits:)) }
        set { monthlyCapMinorUnits = newValue?.minorUnits }
    }
    var actualPricePaid: Money? {
        get { actualPricePaidMinorUnits.map(Money.init(minorUnits:)) }
        set { actualPricePaidMinorUnits = newValue?.minorUnits }
    }
    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .saving }
        set { statusRaw = newValue.rawValue }
    }

    /// Positive when the item came in over plan; feeds the overspend ledger.
    var overspendVariance: Money? {
        guard let paid = actualPricePaid else { return nil }
        return paid - targetAmount
    }
}
