import Foundation

// SwiftData stores these as raw values. Enums with associated values are decomposed into
// stored columns on the model plus a computed façade — see `Loan` and `RecurringRule`.

nonisolated enum AccountType: String, Codable, CaseIterable, Sendable {
    case cash, bank, mobileMoney, savings, investment, credit, receivable

    var label: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Bank"
        case .mobileMoney: "Mobile money"
        case .savings: "Savings"
        case .investment: "Investment"
        case .credit: "Credit"
        case .receivable: "Receivable"
        }
    }

    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .mobileMoney: "iphone"
        case .savings: "lock.circle"
        case .investment: "chart.line.uptrend.xyaxis"
        case .credit: "creditcard"
        case .receivable: "person.2"
        }
    }

    /// Money you can spend today, before earmarks.
    var isLiquidByDefault: Bool {
        switch self {
        case .cash, .bank, .mobileMoney, .savings: true
        case .investment, .credit, .receivable: false
        }
    }

    /// R11: money lent to a friend is a receivable at zero expected return, never an asset.
    var countsInNetWorthByDefault: Bool {
        switch self {
        case .receivable: false
        default: true
        }
    }
}

nonisolated enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case income, expense, transfer
}

nonisolated enum BudgetPeriod: String, Codable, CaseIterable, Sendable {
    case weekly, monthly
}

nonisolated enum RecurringCadenceKind: String, Codable, CaseIterable, Sendable {
    case weekly, biweekly, monthly, yearly, custom
}

nonisolated enum RecurringMode: String, Codable, CaseIterable, Sendable {
    /// Writes the transaction on the due date without asking.
    case autoPost
    /// Default: tells you it is due and waits.
    case remindOnly
}

nonisolated enum LoanDirection: String, Codable, CaseIterable, Sendable {
    case iOwe, owedToMe
}

nonisolated enum LoanInterestKind: String, Codable, CaseIterable, Sendable {
    case amortizing, flatRate, interestFree, revolving
}

nonisolated enum LoanStatus: String, Codable, CaseIterable, Sendable {
    case planned, active, paid, defaulted
}

nonisolated enum PaymentFrequency: String, Codable, CaseIterable, Sendable {
    case weekly, biweekly, monthly, quarterly

    /// How many payments fall in a year — the `n` in every schedule formula.
    var periodsPerYear: Int {
        switch self {
        case .weekly: 52
        case .biweekly: 26
        case .monthly: 12
        case .quarterly: 4
        }
    }
}

nonisolated enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case saving, funded, purchased, abandoned
}

nonisolated enum EarmarkOwnerType: String, Codable, CaseIterable, Sendable {
    case goal, sinkingFund, emergencyFund
}

nonisolated enum EventConfidence: String, Codable, CaseIterable, Sendable {
    case certain, likely, maybe
}

nonisolated enum IncomeEventKind: String, Codable, CaseIterable, Sendable {
    case projectPayment, salaryRise, bonus, gift, refund, assetSale

    /// ADVISOR_RULES §4c: a refund reverses an expense. It is never income.
    var countsAsIncome: Bool { self != .refund }

    /// R3 — untaxed at source, so the tax reserve comes off the top.
    var needsTaxReserve: Bool {
        switch self {
        case .projectPayment, .assetSale: true
        case .bonus: true   // may already be withheld; the sheet asks
        case .salaryRise, .gift, .refund: false
        }
    }

    /// §4c: gifts and inheritances wait seven days before any allocation.
    var coolOffDays: Int { self == .gift ? 7 : 0 }
}

nonisolated enum IncomeEventStatus: String, Codable, CaseIterable, Sendable {
    case unallocated, allocated
}

nonisolated enum AllocationDestinationKind: String, Codable, CaseIterable, Sendable {
    case taxReserve, ladderGap, goal, investment, sinkingFund, debtPayment, free
}

/// The seven stages of the Tranquility Ladder. Never called "financial freedom".
nonisolated enum LadderStage: Int, Codable, CaseIterable, Sendable, Comparable {
    case visibility = 0
    case twoWeekBuffer = 1
    case nothingLate = 2
    case toxicDebtGone = 3
    case emergencyFund = 4
    case sinkingFundsCurrent = 5
    case debtSmallAndCheap = 6
    case tranquil = 7

    static func < (a: LadderStage, b: LadderStage) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .visibility: "Visibility"
        case .twoWeekBuffer: "Two-week buffer"
        case .nothingLate: "No obligation is late"
        case .toxicDebtGone: "Toxic debt gone"
        case .emergencyFund: "Emergency fund"
        case .sinkingFundsCurrent: "Sinking funds current"
        case .debtSmallAndCheap: "Debt is small and cheap"
        case .tranquil: "Tranquil"
        }
    }
}

nonisolated enum Verdict: String, Codable, CaseIterable, Sendable {
    case approved
    case approvedWithConditions
    case notAdvised
    case blocked

    var title: String {
        switch self {
        case .approved: "Approved"
        case .approvedWithConditions: "Approved with conditions"
        case .notAdvised: "Not advised"
        case .blocked: "Blocked"
        }
    }
}
