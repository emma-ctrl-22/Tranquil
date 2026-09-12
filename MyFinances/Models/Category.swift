import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var name: String = ""
    /// Coarse grouping for the breakdown chart, e.g. "Living", "Transport".
    var group: String = ""
    var icon: String = "circle"
    var colorHex: String = "#7C8B9A"

    /// Feeds the buffer, runway and creep maths.
    var isEssential: Bool = false
    /// Bus fare, water — shown as a quick-capture chip.
    var isMicro: Bool = false
    /// ADVISOR_RULES §1: skills, tools, courses. Investment, not discretionary.
    /// The advisor defends this line during cutbacks.
    var isEarningPower: Bool = false
    /// The catch-all envelope. Exactly one category carries this.
    var isMiscellaneous: Bool = false

    var defaultAccount: Account?
    var sortOrder: Int = 0
    /// Last amount logged against this category, so a chip tap prefills it.
    var lastAmountMinorUnits: Int?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    init(
        name: String,
        group: String,
        icon: String = "circle",
        colorHex: String = "#7C8B9A",
        isEssential: Bool = false,
        isMicro: Bool = false,
        isEarningPower: Bool = false,
        isMiscellaneous: Bool = false,
        defaultAccount: Account? = nil,
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.name = name
        self.group = group
        self.icon = icon
        self.colorHex = colorHex
        self.isEssential = isEssential
        self.isMicro = isMicro
        self.isEarningPower = isEarningPower
        self.isMiscellaneous = isMiscellaneous
        self.defaultAccount = defaultAccount
        self.sortOrder = sortOrder
    }

    var lastAmount: Money? {
        get { lastAmountMinorUnits.map(Money.init(minorUnits:)) }
        set { lastAmountMinorUnits = newValue?.minorUnits }
    }
}
