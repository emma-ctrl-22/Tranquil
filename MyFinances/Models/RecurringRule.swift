import Foundation
import SwiftData

/// A scheduled inflow or outflow. Cadence is an enum with associated values in the spec;
/// SwiftData stores it decomposed, with `cadence` as the computed façade.
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var label: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var amountMinorUnits: Int = 0
    var category: Category?
    var account: Account?
    var counterAccount: Account?

    var cadenceKindRaw: String = RecurringCadenceKind.monthly.rawValue
    /// Day of month for `.monthly` and `.yearly`. Clamped at month end, never skipped.
    var cadenceDay: Int?
    /// Month (1–12) for `.yearly`.
    var cadenceMonth: Int?
    /// Interval in days for `.custom`.
    var cadenceCustomDays: Int?

    var nextDueDate: Date = Date()
    var endDate: Date?
    var modeRaw: String = RecurringMode.remindOnly.rawValue
    /// Utilities: remind, don't assume the amount.
    var isVariableAmount: Bool = false

    /// Loans, investments, sinking funds, recurring bills: comes off the top,
    /// before free-to-spend.
    var isCommittedOutflow: Bool = false
    var isArchived: Bool = false

    /// §4b: the previous amount, so a salary rise can be detected and its *delta* allocated.
    var previousAmountMinorUnits: Int?

    init(
        label: String,
        kind: TransactionKind,
        amount: Money,
        account: Account?,
        counterAccount: Account? = nil,
        category: Category? = nil,
        cadence: Cadence,
        nextDueDate: Date,
        endDate: Date? = nil,
        mode: RecurringMode = .remindOnly,
        isVariableAmount: Bool = false,
        isCommittedOutflow: Bool = false,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.label = label
        self.kindRaw = kind.rawValue
        self.amountMinorUnits = amount.minorUnits
        self.account = account
        self.counterAccount = counterAccount
        self.category = category
        self.nextDueDate = nextDueDate
        self.endDate = endDate
        self.modeRaw = mode.rawValue
        self.isVariableAmount = isVariableAmount
        self.isCommittedOutflow = isCommittedOutflow
        self.cadence = cadence
    }

    // MARK: - Façades

    enum Cadence: Equatable, Sendable {
        case weekly
        case biweekly
        case monthly(day: Int)
        case yearly(month: Int, day: Int)
        case custom(days: Int)
    }

    var cadence: Cadence {
        get {
            switch RecurringCadenceKind(rawValue: cadenceKindRaw) ?? .monthly {
            case .weekly: return .weekly
            case .biweekly: return .biweekly
            case .monthly: return .monthly(day: cadenceDay ?? 1)
            case .yearly: return .yearly(month: cadenceMonth ?? 1, day: cadenceDay ?? 1)
            case .custom: return .custom(days: cadenceCustomDays ?? 30)
            }
        }
        set {
            switch newValue {
            case .weekly:
                cadenceKindRaw = RecurringCadenceKind.weekly.rawValue
                cadenceDay = nil; cadenceMonth = nil; cadenceCustomDays = nil
            case .biweekly:
                cadenceKindRaw = RecurringCadenceKind.biweekly.rawValue
                cadenceDay = nil; cadenceMonth = nil; cadenceCustomDays = nil
            case let .monthly(day):
                cadenceKindRaw = RecurringCadenceKind.monthly.rawValue
                cadenceDay = day; cadenceMonth = nil; cadenceCustomDays = nil
            case let .yearly(month, day):
                cadenceKindRaw = RecurringCadenceKind.yearly.rawValue
                cadenceDay = day; cadenceMonth = month; cadenceCustomDays = nil
            case let .custom(days):
                cadenceKindRaw = RecurringCadenceKind.custom.rawValue
                cadenceDay = nil; cadenceMonth = nil; cadenceCustomDays = days
            }
        }
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var mode: RecurringMode {
        get { RecurringMode(rawValue: modeRaw) ?? .remindOnly }
        set { modeRaw = newValue.rawValue }
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set { amountMinorUnits = newValue.minorUnits }
    }

    var previousAmount: Money? {
        get { previousAmountMinorUnits.map(Money.init(minorUnits:)) }
        set { previousAmountMinorUnits = newValue?.minorUnits }
    }

    /// Occurrences per year, for prorating a committed outflow onto a week.
    var occurrencesPerYear: Int {
        switch cadence {
        case .weekly: 52
        case .biweekly: 26
        case .monthly: 12
        case .yearly: 1
        case let .custom(days): Swift.max(1, 365 / Swift.max(1, days))
        }
    }
}
