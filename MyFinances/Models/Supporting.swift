import Foundation
import SwiftData

/// One row per financial day. Powers the heatmap, the streak, and the reconcile nag.
@Model
final class DailyLog {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    /// Midnight of the financial day, as returned by `FinancialCalendar.financialDay(for:)`.
    var date: Date = Date()
    var entryCount: Int = 0
    var wasReconciled: Bool = false
    /// Total spend that day, cached for the heatmap's "spend" mode.
    var spendMinorUnits: Int = 0
    /// Stayed inside pace — the heatmap's "green day" mode.
    var stayedInsidePace: Bool = false

    init(date: Date, entryCount: Int = 0, wasReconciled: Bool = false, now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.date = date
        self.entryCount = entryCount
        self.wasReconciled = wasReconciled
    }

    var spend: Money {
        get { Money(minorUnits: spendMinorUnits) }
        set { spendMinorUnits = newValue.minorUnits }
    }
}

/// Where the user is on the Ladder, with the evidence that put them there.
/// Falling back is recorded honestly; the history is a record, not a scoreboard.
@Model
final class LadderState {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var stageRaw: Int = LadderStage.visibility.rawValue
    var enteredAt: Date = Date()
    /// JSON snapshot of the numbers that justified this stage at the time.
    var evidenceJSON: String = "{}"
    var stabilityScore: Int = 0

    init(stage: LadderStage, enteredAt: Date, evidenceJSON: String = "{}", stabilityScore: Int = 0, now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.stageRaw = stage.rawValue
        self.enteredAt = enteredAt
        self.evidenceJSON = evidenceJSON
        self.stabilityScore = stabilityScore
    }

    var stage: LadderStage {
        get { LadderStage(rawValue: stageRaw) ?? .visibility }
        set { stageRaw = newValue.rawValue }
    }
}

/// A nightly cache of account balances, for fast charts.
/// Always reconstructable from the ledger — if the two disagree, the ledger wins.
@Model
final class BalanceSnapshot {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var date: Date = Date()
    var accountID: UUID = UUID()
    var balanceMinorUnits: Int = 0

    init(date: Date, accountID: UUID, balance: Money, now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.date = date
        self.accountID = accountID
        self.balanceMinorUnits = balance.minorUnits
    }

    var balance: Money {
        get { Money(minorUnits: balanceMinorUnits) }
        set { balanceMinorUnits = newValue.minorUnits }
    }
}
