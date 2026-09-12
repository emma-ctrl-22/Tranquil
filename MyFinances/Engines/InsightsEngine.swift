import Foundation

/// The charts' data layer: the heatmap, streaks, and the rollups that answer
/// "where did it actually go".
nonisolated enum InsightsEngine {

    // MARK: - Heatmap

    enum HeatmapMode: String, CaseIterable, Identifiable, Sendable {
        /// Entries that day — the discipline habit.
        case logged
        /// Spend relative to your own trailing median day.
        case spend
        /// Binary: stayed inside pace.
        case greenDay

        var id: String { rawValue }
        var title: String {
            switch self {
            case .logged: "Logged"
            case .spend: "Spend"
            case .greenDay: "Green days"
            }
        }
    }

    struct Cell: Identifiable, Sendable {
        let date: Date
        let entryCount: Int
        let spend: Money
        let stayedInsidePace: Bool
        /// 0…1, for the colour ramp.
        let intensity: Double

        var id: Date { date }
        var isEmpty: Bool { entryCount == 0 && spend.isZero }
    }

    struct DayInput: Sendable {
        let date: Date
        let entryCount: Int
        let spend: Money
        let stayedInsidePace: Bool
    }

    /// 53 weeks by 7 days, ending today.
    static func heatmap(
        days: [DayInput], mode: HeatmapMode, today: Date, calendar: FinancialCalendar
    ) -> [Cell] {
        // 52 full weeks plus the current one: 53 columns, the last of them partial.
        let start = calendar.addDays(-7 * 52, to: calendar.startOfWeek(containing: today))
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let median = medianSpend(days.filter { $0.spend.isPositive }.map(\.spend))

        return calendar.days(from: start, through: today).map { date in
            let day = byDate[date]
            let entryCount = day?.entryCount ?? 0
            let spend = day?.spend ?? .zero
            return Cell(
                date: date,
                entryCount: entryCount,
                spend: spend,
                stayedInsidePace: day?.stayedInsidePace ?? false,
                intensity: intensity(mode: mode, entryCount: entryCount, spend: spend,
                                     stayedInsidePace: day?.stayedInsidePace ?? false,
                                     medianSpend: median)
            )
        }
    }

    /// Intensity is always relative to **your own** history, never an external benchmark.
    static func intensity(
        mode: HeatmapMode, entryCount: Int, spend: Money,
        stayedInsidePace: Bool, medianSpend: Money
    ) -> Double {
        switch mode {
        case .logged:
            // Four entries is a full-intensity day; more does not read as "better".
            guard entryCount > 0 else { return 0 }
            return Swift.min(1, Double(entryCount) / 4)
        case .spend:
            guard spend.isPositive, medianSpend.isPositive else { return spend.isPositive ? 1 : 0 }
            let ratio = spend.ratio(to: medianSpend) ?? 0
            // Twice your median day is full intensity.
            return Swift.min(1, NSDecimalNumber(decimal: ratio).doubleValue / 2)
        case .greenDay:
            return stayedInsidePace ? 1 : 0
        }
    }

    static func medianSpend(_ amounts: [Money]) -> Money {
        guard !amounts.isEmpty else { return .zero }
        let sorted = amounts.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]).split(into: 2).first ?? .zero
        }
        return sorted[middle]
    }

    // MARK: - Streaks

    struct StreakSummary: Sendable {
        let current: Int
        let longest: Int
        let daysLogged: Int
        let daysTotal: Int

        /// Share of days logged, 0…1.
        var rate: Decimal {
            daysTotal > 0 ? Decimal(daysLogged) / Decimal(daysTotal) : 0
        }
    }

    static func streaks(
        days: [DayInput], today: Date, calendar: FinancialCalendar
    ) -> StreakSummary {
        let logged = Set(days.filter { $0.entryCount > 0 }.map(\.date))
        guard !logged.isEmpty else {
            return StreakSummary(current: 0, longest: 0, daysLogged: 0, daysTotal: days.count)
        }

        // Current: counting back from today. Today not yet logged does not break it —
        // the day is not over.
        var current = 0
        var cursor = logged.contains(today) ? today : calendar.addDays(-1, to: today)
        while logged.contains(cursor) {
            current += 1
            cursor = calendar.addDays(-1, to: cursor)
        }

        // Longest: walk the sorted set forward.
        var longest = 0
        var run = 0
        var previous: Date?
        for date in logged.sorted() {
            if let previous, calendar.addDays(1, to: previous) == date {
                run += 1
            } else {
                run = 1
            }
            longest = Swift.max(longest, run)
            previous = date
        }

        return StreakSummary(current: current, longest: longest,
                             daysLogged: logged.count, daysTotal: days.count)
    }

    // MARK: - Category rollups

    struct CategoryTotal: Identifiable, Sendable {
        let id: UUID
        let name: String
        let colorHex: String
        let amount: Money
        /// The same category in the previous period, for the delta.
        let previous: Money
        let isMicro: Bool

        var delta: Money { amount - previous }
        var deltaFraction: Decimal? {
            previous.isPositive ? amount.ratio(to: previous).map { $0 - 1 } : nil
        }
    }

    static func rollup(_ totals: [CategoryTotal]) -> [CategoryTotal] {
        totals.filter { $0.amount.isPositive }.sorted { $0.amount > $1.amount }
    }

    /// "How much did bus fares actually cost me this year?" — the number that hides.
    static func microSpendTotal(_ totals: [CategoryTotal]) -> Money {
        Money.sum(totals.filter(\.isMicro).map(\.amount))
    }

    // MARK: - Series

    struct Point: Identifiable, Sendable {
        let date: Date
        let value: Money
        var id: Date { date }
    }

    struct MonthBar: Identifiable, Sendable {
        let monthStart: Date
        let income: Money
        let expense: Money
        var id: Date { monthStart }
        var net: Money { income - expense }
    }

    /// Debt outstanding over time, per loan, for the stacked burn-down.
    struct DebtPoint: Identifiable, Sendable {
        let date: Date
        let loanName: String
        let balance: Money
        var id: String { "\(loanName)-\(date.timeIntervalSince1970)" }
    }

    static func debtBurndown(
        positions: [LoanEngine.Position], from date: Date, months: Int,
        calendar: FinancialCalendar
    ) -> [DebtPoint] {
        var points: [DebtPoint] = []
        for offset in 0...months {
            let cursor = calendar.addMonths(offset, to: date)
            for position in positions where position.loan.direction == .iOwe {
                // The scheduled balance at this point in the loan's life.
                let remaining = position.schedule.instalments
                    .last { $0.date <= cursor }?.balance
                    ?? position.loan.principal
                guard remaining.isPositive else { continue }
                points.append(DebtPoint(date: cursor, loanName: position.loan.name,
                                        balance: remaining))
            }
        }
        return points
    }
}
