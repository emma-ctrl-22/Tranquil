import Foundation

/// Investment tracking: what you put in, what you say it is worth, and how consistently
/// you contribute.
///
/// It never projects returns or forecasts markets. Contributed principal is a fact the
/// ledger knows; current value is a number only you can supply.
nonisolated enum InvestmentEngine {

    struct Holding: Identifiable, Sendable {
        let accountID: UUID
        let name: String
        let colorHex: String
        /// Everything transferred in, less anything taken out.
        let contributed: Money
        /// The latest figure you entered, if any.
        let currentValue: Money?
        let valuedOn: Date?

        var id: UUID { accountID }

        /// Value minus what you put in. Nil until you have entered a value —
        /// the app will not guess at it.
        var gain: Money? {
            guard let currentValue else { return nil }
            return currentValue - contributed
        }

        var gainFraction: Decimal? {
            guard let gain, contributed.isPositive else { return nil }
            return gain.ratio(to: contributed)
        }

        /// How stale the figure is, in days.
        func daysSinceValued(today: Date, calendar: FinancialCalendar) -> Int? {
            valuedOn.map { calendar.daysBetween($0, today) }
        }

        /// ASSUMPTION: a valuation older than 30 days is worth re-checking. Funds report
        /// monthly, so asking more often would be noise.
        func needsValuation(today: Date, calendar: FinancialCalendar) -> Bool {
            guard let days = daysSinceValued(today: today, calendar: calendar) else {
                return contributed.isPositive
            }
            return days >= 30
        }
    }

    struct Summary: Sendable {
        let holdings: [Holding]

        var totalContributed: Money { Money.sum(holdings.map(\.contributed)) }
        /// Falls back to contributed for holdings you have not valued, so the total is
        /// never overstated by treating an unvalued holding as zero.
        var totalValue: Money {
            Money.sum(holdings.map { $0.currentValue ?? $0.contributed })
        }
        var totalGain: Money { totalValue - totalContributed }
        var hasAnyValuation: Bool { holdings.contains { $0.currentValue != nil } }

        func needingValuation(today: Date, calendar: FinancialCalendar) -> [Holding] {
            holdings.filter { $0.needsValuation(today: today, calendar: calendar) }
        }
    }

    /// Months out of the last `count` with a contribution. Consistency beats size.
    static func contributionStreak(
        contributionMonths: Set<Date>, months count: Int, today: Date,
        calendar: FinancialCalendar
    ) -> Int {
        (0..<count).filter { offset in
            let start = calendar.startOfMonth(containing: calendar.addMonths(-offset, to: today))
            return contributionMonths.contains(start)
        }.count
    }

    /// Contributions as a share of net income over the same window.
    static func contributionRate(contributed: Money, netIncome: Money) -> Decimal? {
        guard netIncome.isPositive else { return nil }
        return contributed.ratio(to: netIncome)
    }
}
