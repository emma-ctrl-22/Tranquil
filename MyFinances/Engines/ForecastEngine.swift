import Foundation

/// The 60-day forward projection — the "will I be short on the 24th" view.
///
/// Pure: it takes today's liquid balance plus everything scheduled, and returns a day
/// by day picture. It never reads the store and never writes anything.
nonisolated enum ForecastEngine {

    // MARK: - Inputs

    struct ScheduledItem: Identifiable, Sendable {
        let id: UUID
        let label: String
        let amount: Money
        let kind: TransactionKind
        let cadence: RecurringRule.Cadence
        let nextDueDate: Date
        let endDate: Date?
        /// Utilities and the like: the date is known, the amount is a guess.
        let isVariableAmount: Bool
        let isCommittedOutflow: Bool
    }

    struct OneOffItem: Identifiable, Sendable {
        let id: UUID
        let label: String
        /// Already weighted by confidence — a `.maybe` event arrives here halved.
        let amount: Money
        let kind: TransactionKind
        let date: Date
        let confidence: EventConfidence
    }

    // MARK: - Outputs

    struct Movement: Identifiable, Sendable {
        let id: UUID
        let label: String
        /// Signed: negative leaves, positive arrives.
        let amount: Money
        let isEstimate: Bool
    }

    struct Day: Identifiable, Sendable {
        let date: Date
        let openingBalance: Money
        let movements: [Movement]
        let closingBalance: Money

        var id: Date { date }
        var netChange: Money { closingBalance - openingBalance }
        var hasMovement: Bool { !movements.isEmpty }
        var isNegative: Bool { closingBalance.isNegative }

        func isBelowFloor(_ floor: Money?) -> Bool {
            guard let floor else { return false }
            return closingBalance < floor
        }
    }

    struct Projection: Sendable {
        let days: [Day]
        let startingBalance: Money
        let floor: Money?

        /// The first day the projection goes below zero, if any.
        var firstNegativeDay: Day? { days.first(where: \.isNegative) }

        /// The first day below the configured floor — a softer, earlier warning.
        var firstDayBelowFloor: Day? {
            guard let floor else { return nil }
            return days.first { $0.isBelowFloor(floor) && !$0.isNegative }
        }

        var lowestDay: Day? { days.min { $0.closingBalance < $1.closingBalance } }
        var endingBalance: Money { days.last?.closingBalance ?? startingBalance }
        var hasTrouble: Bool { firstNegativeDay != nil || firstDayBelowFloor != nil }
    }

    // MARK: - Cadence

    /// Every occurrence of a rule in `[from, through]`, inclusive.
    ///
    /// Month-end is clamped, never skipped: "monthly on the 31st" falls on 28 or 29
    /// February. A rule whose `nextDueDate` is in the past is caught up rather than
    /// silently dropped.
    static func occurrences(
        of item: ScheduledItem,
        from start: Date,
        through end: Date,
        calendar: FinancialCalendar
    ) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.financialDay(for: item.nextDueDate)
        let first = calendar.financialDay(for: start)
        let last = calendar.financialDay(for: end)
        guard last >= first else { return [] }

        // A rule can have fallen behind; advance it to the window without emitting.
        var guardRail = 0
        while cursor < first && guardRail < 5_000 {
            guard let next = advance(cursor, by: item.cadence, calendar: calendar) else { break }
            if next == cursor { break }
            cursor = next
            guardRail += 1
        }

        while cursor <= last && guardRail < 5_000 {
            if let endDate = item.endDate, cursor > calendar.financialDay(for: endDate) { break }
            if cursor >= first { result.append(cursor) }
            guard let next = advance(cursor, by: item.cadence, calendar: calendar) else { break }
            if next == cursor { break }
            cursor = next
            guardRail += 1
        }
        return result
    }

    /// The next date after `date` for a cadence.
    static func advance(
        _ date: Date, by cadence: RecurringRule.Cadence, calendar: FinancialCalendar
    ) -> Date? {
        switch cadence {
        case .weekly:
            return calendar.addDays(7, to: date)
        case .biweekly:
            return calendar.addDays(14, to: date)
        case let .monthly(day):
            return calendar.nextMonthly(dayOfMonth: day, after: date)
        case let .yearly(month, day):
            return calendar.nextYearly(month: month, dayOfMonth: day, after: date)
        case let .custom(days):
            return calendar.addDays(Swift.max(1, days), to: date)
        }
    }

    // MARK: - Projection

    static func project(
        startingBalance: Money,
        from start: Date,
        days dayCount: Int,
        scheduled: [ScheduledItem],
        oneOffs: [OneOffItem],
        floor: Money? = nil,
        calendar: FinancialCalendar
    ) -> Projection {
        let firstDay = calendar.financialDay(for: start)
        let lastDay = calendar.addDays(Swift.max(0, dayCount - 1), to: firstDay)

        // Bucket every movement onto its financial day first, so the walk is one pass.
        var byDay: [Date: [Movement]] = [:]

        for item in scheduled {
            let dates = occurrences(of: item, from: firstDay, through: lastDay, calendar: calendar)
            for date in dates {
                let signed = item.kind == .income ? item.amount : -item.amount
                byDay[date, default: []].append(
                    Movement(id: UUID(), label: item.label, amount: signed,
                             isEstimate: item.isVariableAmount)
                )
            }
        }

        for item in oneOffs {
            let day = calendar.financialDay(for: item.date)
            guard day >= firstDay, day <= lastDay else { continue }
            let signed = item.kind == .income ? item.amount : -item.amount
            byDay[day, default: []].append(
                Movement(id: UUID(), label: item.label, amount: signed,
                         isEstimate: item.confidence != .certain)
            )
        }

        var days: [Day] = []
        days.reserveCapacity(dayCount)
        var balance = startingBalance

        for day in calendar.days(from: firstDay, through: lastDay) {
            let movements = byDay[day] ?? []
            let opening = balance
            balance = movements.reduce(balance) { $0 + $1.amount }
            days.append(Day(date: day, openingBalance: opening,
                            movements: movements, closingBalance: balance))
        }

        return Projection(days: days, startingBalance: startingBalance, floor: floor)
    }

    // MARK: - Suggestions

    /// A plain, actionable fix for a projected shortfall. Never a lecture.
    static func suggestion(for projection: Projection, formatter: MoneyFormatter) -> String? {
        guard let trouble = projection.firstNegativeDay ?? projection.firstDayBelowFloor
        else { return nil }

        // The largest outflow on the day is the one worth moving.
        let largest = trouble.movements
            .filter(\.amount.isNegative)
            .min { $0.amount < $1.amount }

        let shortfall = trouble.isNegative
            ? trouble.closingBalance.magnitude
            : ((projection.floor ?? .zero) - trouble.closingBalance).clampedToZero

        if let largest {
            return "\(largest.label) of \(formatter.string(largest.amount.magnitude)) lands that "
                 + "day. Moving it later, or finding \(formatter.string(shortfall)) before then, "
                 + "clears it."
        }
        return "Finding \(formatter.string(shortfall)) before then clears it."
    }
}
