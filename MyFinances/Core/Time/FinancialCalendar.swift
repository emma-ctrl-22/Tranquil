import Foundation

/// The one source of truth for "what day is it, financially".
///
/// Nothing else in the app calls `Date()` or `Calendar.current`. Inject this.
nonisolated struct FinancialCalendar: Sendable {
    /// Hour (0–23) at which a new financial day begins. A 01:30 taxi ride belongs to
    /// the previous financial day, so the default is 04:00.
    let dayBoundaryHour: Int
    /// 1 = Sunday … 7 = Saturday, matching `Calendar.firstWeekday`.
    let weekStartsOn: Int
    let timeZone: TimeZone
    /// Injected clock, so tests never depend on the wall clock.
    private let now: @Sendable () -> Date

    init(
        dayBoundaryHour: Int = 4,
        weekStartsOn: Int = 2,  // Monday
        timeZone: TimeZone = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition((0...23).contains(dayBoundaryHour), "dayBoundaryHour must be 0...23")
        precondition((1...7).contains(weekStartsOn), "weekStartsOn must be 1...7")
        self.dayBoundaryHour = dayBoundaryHour
        self.weekStartsOn = weekStartsOn
        self.timeZone = timeZone
        self.now = now
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = weekStartsOn
        // Makes weekOfYear arithmetic agree with firstWeekday.
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func currentDate() -> Date { now() }

    // MARK: - Financial days

    /// The financial day an instant belongs to, once the day boundary is applied.
    ///
    /// A financial day is represented by **the instant it starts** — midnight plus
    /// `dayBoundaryHour` — not by midnight. That makes this idempotent: feeding a day
    /// back in returns the same day, which midnight-based representations do not.
    func financialDay(for date: Date) -> Date {
        // Compare against this calendar day's own boundary rather than shifting the
        // instant back by a fixed interval. On a DST change the interval and the wall
        // clock disagree, and a fixed shift assigns the boundary hour itself to the
        // wrong day.
        let midnight = calendar.startOfDay(for: date)
        let boundary = dayStart(fromMidnight: midnight)
        if date >= boundary { return boundary }
        guard let previousMidnight = calendar.date(byAdding: .day, value: -1, to: midnight) else {
            return boundary
        }
        return dayStart(fromMidnight: calendar.startOfDay(for: previousMidnight))
    }

    /// Normalises any instant to the start of its financial day. Same thing as
    /// `financialDay(for:)`, named for the places where that reads better.
    func startOfFinancialDay(_ date: Date) -> Date { financialDay(for: date) }

    /// The calendar date a financial day is labelled with — midnight, for display,
    /// grouping and `DateComponents` work. Never use this for arithmetic.
    func calendarMidnight(of day: Date) -> Date {
        calendar.startOfDay(for: financialDay(for: day))
    }

    /// Half-open `[start, end)` covering one financial day.
    func financialDayInterval(containing date: Date) -> DateInterval {
        let start = financialDay(for: date)
        return DateInterval(start: start, end: addDays(1, to: start))
    }

    func today() -> Date { financialDay(for: now()) }

    func isSameFinancialDay(_ a: Date, _ b: Date) -> Bool {
        financialDay(for: a) == financialDay(for: b)
    }

    /// Whole financial days from `a` to `b`; negative when `b` is earlier.
    func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: financialDay(for: a), to: financialDay(for: b)).day ?? 0
    }

    /// Day arithmetic on financial days. DST-aware: adding a day always lands on the
    /// same boundary hour, even across a clock change.
    func addDays(_ count: Int, to day: Date) -> Date {
        let start = financialDay(for: day)
        guard let shifted = calendar.date(byAdding: .day, value: count, to: start) else { return start }
        return financialDay(for: shifted)
    }

    /// Every financial day in `[start, end]`, inclusive of both ends.
    func days(from start: Date, through end: Date) -> [Date] {
        var day = financialDay(for: start)
        let last = financialDay(for: end)
        guard day <= last else { return [] }
        var result: [Date] = []
        while day <= last {
            result.append(day)
            day = addDays(1, to: day)
        }
        return result
    }

    /// Turns a midnight into the start of that financial day.
    ///
    /// Sets the wall-clock hour rather than adding an interval. On the morning the
    /// clocks go forward, midnight plus four hours is 05:00, not 04:00 — which would
    /// make `financialDay(for:)` non-idempotent for one day a year and quietly drift
    /// every streak, heatmap cell and weekly total that day. If the boundary hour does
    /// not exist at all (a 04:00 jurisdiction that springs forward at 03:00), take the
    /// next valid instant.
    private func dayStart(fromMidnight midnight: Date) -> Date {
        calendar.date(
            bySettingHour: dayBoundaryHour,
            minute: 0,
            second: 0,
            of: midnight,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? midnight
    }

    // MARK: - Weeks

    /// Half-open `[start, end)` of the financial week containing `date`.
    /// Bounds are day-boundary-aware instants, not midnights.
    func weekInterval(containing date: Date) -> DateInterval {
        let start = startOfWeek(containing: date)
        return DateInterval(start: start, end: addDays(7, to: start))
    }

    /// Midnight of the first financial day of the week containing `date`.
    func startOfWeek(containing date: Date) -> Date {
        let day = financialDay(for: date)
        let weekday = calendar.component(.weekday, from: calendarMidnight(of: day))
        let offset = (weekday - weekStartsOn + 7) % 7
        return addDays(-offset, to: day)
    }

    /// 1…7 — how many financial days of this week have begun, including today.
    /// Used by the burn meter's `expected = elapsedDaysInWeek / 7`.
    func elapsedDaysInWeek(containing date: Date) -> Int {
        daysBetween(startOfWeek(containing: date), date) + 1
    }

    // MARK: - Months

    /// Half-open `[start, end)` of the financial month containing `date`.
    func monthInterval(containing date: Date) -> DateInterval {
        let start = startOfMonth(containing: date)
        return DateInterval(start: start, end: addMonths(1, to: start))
    }

    func startOfMonth(containing date: Date) -> Date {
        let day = financialDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: day)
        guard let midnight = calendar.date(from: components) else { return day }
        return dayStart(fromMidnight: midnight)
    }

    func addMonths(_ count: Int, to day: Date) -> Date {
        let start = financialDay(for: day)
        guard let shifted = calendar.date(byAdding: .month, value: count, to: start) else { return start }
        return financialDay(for: shifted)
    }

    func daysInMonth(containing date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: calendarMidnight(of: date))?.count ?? 30
    }

    /// "Monthly on the 31st" in February is the 28th or 29th — never a skipped month.
    /// Clamps `dayOfMonth` to the length of the target month.
    func date(year: Int, month: Int, clampedDay dayOfMonth: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let first = calendar.date(from: components) else { return nil }
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        guard let midnight = calendar.date(byAdding: .day, value: Swift.min(dayOfMonth, length) - 1, to: first)
        else { return nil }
        return dayStart(fromMidnight: midnight)
    }

    /// The next occurrence of `dayOfMonth` strictly after `day`, clamped at month end.
    func nextMonthly(dayOfMonth: Int, after day: Date) -> Date? {
        let anchor = financialDay(for: day)
        var components = calendar.dateComponents([.year, .month], from: calendarMidnight(of: anchor))
        guard let year = components.year, let month = components.month else { return nil }
        if let thisMonth = date(year: year, month: month, clampedDay: dayOfMonth), thisMonth > anchor {
            return thisMonth
        }
        components.month = month + 1
        guard let nextMonthStart = calendar.date(from: components) else { return nil }
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonthStart)
        guard let nextYear = nextComponents.year, let next = nextComponents.month else { return nil }
        return date(year: nextYear, month: next, clampedDay: dayOfMonth)
    }

    /// The next occurrence of a yearly date, clamped (29 Feb in a common year becomes 28 Feb).
    func nextYearly(month: Int, dayOfMonth: Int, after day: Date) -> Date? {
        let anchor = financialDay(for: day)
        guard let year = calendar.dateComponents([.year], from: calendarMidnight(of: anchor)).year
        else { return nil }
        if let thisYear = date(year: year, month: month, clampedDay: dayOfMonth), thisYear > anchor {
            return thisYear
        }
        return date(year: year + 1, month: month, clampedDay: dayOfMonth)
    }

    // MARK: - Derived personal facts

    /// Age is derived from birth year, never stored as a number that goes stale.
    func age(birthYear: Int) -> Int {
        let year = calendar.dateComponents([.year], from: now()).year ?? birthYear
        return Swift.max(0, year - birthYear)
    }
}
