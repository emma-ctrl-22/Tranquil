import Foundation
import SwiftData

/// A permanent record of overriding a hard rule. Totalled in the monthly review.
/// The number does the work; the app adds no commentary.
@Model
final class OverrideLog {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    /// R1…R11.
    var ruleID: String = ""
    var ruleTitle: String = ""
    /// Typed by the user. Required — there is no override without one.
    var reason: String = ""
    var occurredAt: Date = Date()
    /// What the override cost, where the engine could compute it.
    var estimatedCostMinorUnits: Int?
    var contextSummary: String?

    init(
        ruleID: String,
        ruleTitle: String,
        reason: String,
        occurredAt: Date,
        estimatedCost: Money? = nil,
        contextSummary: String? = nil,
        now: Date = Date()
    ) {
        precondition(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     "An override requires a typed reason")
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.ruleID = ruleID
        self.ruleTitle = ruleTitle
        self.reason = reason
        self.occurredAt = occurredAt
        self.estimatedCostMinorUnits = estimatedCost?.minorUnits
        self.contextSummary = contextSummary
    }

    var estimatedCost: Money? {
        get { estimatedCostMinorUnits.map(Money.init(minorUnits:)) }
        set { estimatedCostMinorUnits = newValue?.minorUnits }
    }
}
