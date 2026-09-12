import Foundation
import SwiftData

/// Money inside an account reserved for a goal or fund.
///
/// Invariant: `sum(earmarks on an account) <= account.balance`. When violated the
/// account is **over-committed** — surfaced as a warning, never silently rebalanced.
@Model
final class Earmark {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var ownerTypeRaw: String = EarmarkOwnerType.goal.rawValue
    var ownerID: UUID = UUID()
    var account: Account?
    var amountMinorUnits: Int = 0

    init(
        ownerType: EarmarkOwnerType,
        ownerID: UUID,
        account: Account?,
        amount: Money,
        now: Date = Date()
    ) {
        precondition(!amount.isNegative, "An earmark is never negative")
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.ownerTypeRaw = ownerType.rawValue
        self.ownerID = ownerID
        self.account = account
        self.amountMinorUnits = amount.minorUnits
    }

    var ownerType: EarmarkOwnerType {
        get { EarmarkOwnerType(rawValue: ownerTypeRaw) ?? .goal }
        set { ownerTypeRaw = newValue.rawValue }
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set {
            precondition(!newValue.isNegative, "An earmark is never negative")
            amountMinorUnits = newValue.minorUnits
        }
    }
}
