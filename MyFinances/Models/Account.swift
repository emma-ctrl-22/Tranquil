import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Soft delete only. Every query filters on this being nil.
    var deletedAt: Date?

    var name: String = ""
    var typeRaw: String = AccountType.cash.rawValue
    /// Minor units. The only balance figure ever stored; everything else is derived.
    var openingBalanceMinorUnits: Int = 0

    var colorHex: String = "#7C8B9A"
    var icon: String = "banknote"
    var sortOrder: Int = 0

    var includeInNetWorth: Bool = true
    /// Can I spend from this today?
    var isLiquid: Bool = true
    /// Alert below this. Minor units; nil means no floor.
    var lowBalanceFloorMinorUnits: Int?
    var isArchived: Bool = false

    /// ADVISOR_RULES §4: cannot be spent from, holds no earmarks, excluded from
    /// runway and free-to-spend. It is not your money.
    var isTaxReserve: Bool = false
    /// The designated emergency-fund home for Ladder stage 4.
    var isEmergencyFundAccount: Bool = false

    var notes: String?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.counterAccount)
    var incomingTransfers: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \Earmark.account)
    var earmarks: [Earmark]? = []

    init(
        name: String,
        type: AccountType,
        openingBalance: Money = .zero,
        colorHex: String = "#7C8B9A",
        icon: String? = nil,
        sortOrder: Int = 0,
        includeInNetWorth: Bool? = nil,
        isLiquid: Bool? = nil,
        lowBalanceFloor: Money? = nil,
        isTaxReserve: Bool = false,
        isEmergencyFundAccount: Bool = false,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.name = name
        self.typeRaw = type.rawValue
        self.openingBalanceMinorUnits = openingBalance.minorUnits
        self.colorHex = colorHex
        self.icon = icon ?? type.systemImage
        self.sortOrder = sortOrder
        self.includeInNetWorth = includeInNetWorth ?? type.countsInNetWorthByDefault
        self.isLiquid = isLiquid ?? type.isLiquidByDefault
        self.lowBalanceFloorMinorUnits = lowBalanceFloor?.minorUnits
        self.isTaxReserve = isTaxReserve
        self.isEmergencyFundAccount = isEmergencyFundAccount
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .cash }
        set { typeRaw = newValue.rawValue }
    }

    var openingBalance: Money {
        get { Money(minorUnits: openingBalanceMinorUnits) }
        set { openingBalanceMinorUnits = newValue.minorUnits }
    }

    var lowBalanceFloor: Money? {
        get { lowBalanceFloorMinorUnits.map(Money.init(minorUnits:)) }
        set { lowBalanceFloorMinorUnits = newValue?.minorUnits }
    }

    /// A tax reserve is not spendable and holds no goal money, whatever its type says.
    var isSpendable: Bool { !isTaxReserve && !isArchived && deletedAt == nil }
}
