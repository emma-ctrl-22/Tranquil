import Foundation
import SwiftData

/// A significant inflow. Anything above `1.5 x medianWeeklyIncome` lands here
/// `.unallocated` and is **excluded from spendable balance** until allocated.
@Model
final class IncomeEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var kindRaw: String = IncomeEventKind.projectPayment.rawValue
    var receivedAt: Date = Date()

    var grossAmountMinorUnits: Int = 0
    /// R3 — off the top, into the tax reserve account. It was never your money.
    var taxReservedMinorUnits: Int = 0
    var directCostsMinorUnits: Int = 0

    /// Project payments: `net usable / hours` is the effective hourly rate.
    var hoursWorked: Int?
    var clientOrSource: String?

    var statusRaw: String = IncomeEventStatus.unallocated.rawValue
    /// Gifts wait seven days before any allocation (§4c).
    var allocatableFrom: Date?
    var allocatedAt: Date?

    /// The account the money landed in.
    var account: Account?
    var transactionID: UUID?
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \IncomeAllocation.incomeEvent)
    var allocations: [IncomeAllocation]? = []

    init(
        kind: IncomeEventKind,
        receivedAt: Date,
        grossAmount: Money,
        taxReserved: Money = .zero,
        directCosts: Money = .zero,
        hoursWorked: Int? = nil,
        clientOrSource: String? = nil,
        account: Account? = nil,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.kindRaw = kind.rawValue
        self.receivedAt = receivedAt
        self.grossAmountMinorUnits = grossAmount.minorUnits
        self.taxReservedMinorUnits = taxReserved.minorUnits
        self.directCostsMinorUnits = directCosts.minorUnits
        self.hoursWorked = hoursWorked
        self.clientOrSource = clientOrSource
        self.account = account
        let coolOff = kind.coolOffDays
        self.allocatableFrom = coolOff > 0
            ? Calendar(identifier: .gregorian).date(byAdding: .day, value: coolOff, to: receivedAt)
            : nil
    }

    var kind: IncomeEventKind {
        get { IncomeEventKind(rawValue: kindRaw) ?? .projectPayment }
        set { kindRaw = newValue.rawValue }
    }
    var status: IncomeEventStatus {
        get { IncomeEventStatus(rawValue: statusRaw) ?? .unallocated }
        set { statusRaw = newValue.rawValue }
    }
    var grossAmount: Money {
        get { Money(minorUnits: grossAmountMinorUnits) }
        set { grossAmountMinorUnits = newValue.minorUnits }
    }
    var taxReserved: Money {
        get { Money(minorUnits: taxReservedMinorUnits) }
        set { taxReservedMinorUnits = newValue.minorUnits }
    }
    var directCosts: Money {
        get { Money(minorUnits: directCostsMinorUnits) }
        set { directCostsMinorUnits = newValue.minorUnits }
    }

    var netUsable: Money { (grossAmount - taxReserved - directCosts).clampedToZero }

    /// The whole point of the module: unallocated money is not spendable.
    var isSpendable: Bool { status == .allocated }

    /// `net usable / hours` — over a year this says which work to take more of.
    func effectiveHourlyRate() -> Money? {
        guard let hours = hoursWorked, hours > 0 else { return nil }
        return netUsable.split(into: hours).first
    }
}
