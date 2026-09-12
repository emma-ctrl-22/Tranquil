import Foundation
import SwiftData

/// An envelope: a budget for a category over a period.
@Model
final class Budget {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    /// nil = the Miscellaneous catch-all envelope, which is first-class, not a leftover.
    var category: Category?
    var periodRaw: String = BudgetPeriod.weekly.rawValue
    var amountMinorUnits: Int = 0

    var rollover: Bool = false
    /// Unspent weeks shouldn't become a licence to splurge.
    var rolloverCapMultipleBasisPoints: Int = 20_000   // 2.00x

    /// §4b anti-creep ratchet: raising an envelope is a deliberate, logged act.
    var lastRaisedAt: Date?
    var lastRaiseReason: String?

    init(
        category: Category?,
        period: BudgetPeriod,
        amount: Money,
        rollover: Bool = false,
        rolloverCapMultiple: Decimal = 2,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.category = category
        self.periodRaw = period.rawValue
        self.amountMinorUnits = amount.minorUnits
        self.rollover = rollover
        self.rolloverCapMultipleBasisPoints = Money.roundBankers(rolloverCapMultiple * 10_000)
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .weekly }
        set { periodRaw = newValue.rawValue }
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set { amountMinorUnits = newValue.minorUnits }
    }

    var rolloverCapMultiple: Decimal {
        get { Decimal(rolloverCapMultipleBasisPoints) / 10_000 }
        set { rolloverCapMultipleBasisPoints = Money.roundBankers(newValue * 10_000) }
    }

    /// A monthly envelope shown at weekly pace: `monthly x 7 / daysInMonth`.
    func weeklyPace(daysInMonth: Int) -> Money {
        switch period {
        case .weekly: return amount
        case .monthly:
            guard daysInMonth > 0 else { return .zero }
            return amount.scaled(by: Decimal(7) / Decimal(daysInMonth))
        }
    }
}
