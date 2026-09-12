import Testing
import Foundation
@testable import MyFinances

struct FinancialCalendarTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func calendar(
        boundary: Int = 4,
        weekStart: Int = 2,
        now: Date = Date(timeIntervalSince1970: 0)
    ) -> FinancialCalendar {
        FinancialCalendar(dayBoundaryHour: boundary, weekStartsOn: weekStart,
                          timeZone: utc, now: { now })
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    /// A financial day is the instant it starts: midnight plus the 04:00 boundary.
    private func day(_ ymd: String) -> Date { date(ymd + "T04:00:00Z") }
    private func midnightDay(_ ymd: String) -> Date { date(ymd + "T00:00:00Z") }

    // MARK: - The day boundary

    @Test func lateNightSpendBelongsToThePreviousDay() {
        let fc = calendar()
        // 01:30 on the 12th is still the 11th financially.
        #expect(fc.financialDay(for: date("2026-09-12T01:30:00Z")) == day("2026-09-11"))
        // 03:59 is the last minute of the previous day.
        #expect(fc.financialDay(for: date("2026-09-12T03:59:00Z")) == day("2026-09-11"))
        // 04:00 starts the new day.
        #expect(fc.financialDay(for: date("2026-09-12T04:00:00Z")) == day("2026-09-12"))
        #expect(fc.financialDay(for: date("2026-09-12T23:59:00Z")) == day("2026-09-12"))
    }

    @Test func midnightBoundaryBehavesLikeACalendarDay() {
        let fc = calendar(boundary: 0)
        #expect(fc.financialDay(for: date("2026-09-12T00:00:00Z")) == midnightDay("2026-09-12"))
        #expect(fc.financialDay(for: date("2026-09-12T23:59:00Z")) == midnightDay("2026-09-12"))
    }

    @Test func financialDayIsIdempotent() {
        // Feeding a day back in must return the same day. Everything that does day
        // arithmetic depends on this.
        let fc = calendar()
        let d = fc.financialDay(for: date("2026-09-12T01:30:00Z"))
        #expect(fc.financialDay(for: d) == d)
        #expect(fc.financialDay(for: fc.addDays(3, to: d)) == fc.addDays(3, to: d))
        #expect(fc.startOfWeek(containing: fc.startOfWeek(containing: d)) == fc.startOfWeek(containing: d))
    }

    @Test func aFinancialDayIntervalIsExactlyTwentyFourHours() {
        let fc = calendar()
        let interval = fc.financialDayInterval(containing: date("2026-09-12T10:00:00Z"))
        #expect(interval.start == date("2026-09-12T04:00:00Z"))
        #expect(interval.end == date("2026-09-13T04:00:00Z"))
        #expect(interval.duration == 24 * 60 * 60)
    }

    @Test func sameDayAcrossTheMidnightGap() {
        let fc = calendar()
        // 23:00 Saturday and 02:00 Sunday are the same financial day.
        #expect(fc.isSameFinancialDay(date("2026-09-12T23:00:00Z"), date("2026-09-13T02:00:00Z")))
        #expect(!fc.isSameFinancialDay(date("2026-09-12T23:00:00Z"), date("2026-09-13T05:00:00Z")))
    }

    // MARK: - Weeks

    @Test func weekStartsOnMonday() {
        let fc = calendar()
        // 2026-09-12 is a Saturday; its week starts Monday 2026-09-07.
        #expect(fc.startOfWeek(containing: day("2026-09-12")) == day("2026-09-07"))
        #expect(fc.startOfWeek(containing: day("2026-09-07")) == day("2026-09-07"))
        // Sunday 2026-09-13 still belongs to the week that began the 7th.
        #expect(fc.startOfWeek(containing: day("2026-09-13")) == day("2026-09-07"))
        // Monday the 14th opens a new week.
        #expect(fc.startOfWeek(containing: day("2026-09-14")) == day("2026-09-14"))
    }

    @Test func weekStartsOnSundayWhenConfigured() {
        let fc = calendar(weekStart: 1)
        #expect(fc.startOfWeek(containing: day("2026-09-12")) == day("2026-09-06"))
        #expect(fc.startOfWeek(containing: day("2026-09-13")) == day("2026-09-13"))
    }

    @Test func elapsedDaysDrivesTheBurnMeter() {
        let fc = calendar()
        // Monday is day 1 of 7, Sunday is day 7 — burn expects elapsed/7.
        #expect(fc.elapsedDaysInWeek(containing: day("2026-09-07")) == 1)
        #expect(fc.elapsedDaysInWeek(containing: day("2026-09-09")) == 3)
        #expect(fc.elapsedDaysInWeek(containing: day("2026-09-13")) == 7)
    }

    @Test func weekIntervalSpansSevenDaysFromTheBoundaryHour() {
        let fc = calendar()
        let interval = fc.weekInterval(containing: day("2026-09-12"))
        #expect(interval.start == day("2026-09-07"))
        #expect(interval.end == day("2026-09-14"))
        #expect(interval.duration == 7 * 24 * 60 * 60)
    }

    // MARK: - Months

    @Test func monthlyOnThe31stClampsRatherThanSkipping() {
        let fc = calendar()
        // From 15 Jan, the next "31st" is 31 Jan; from 31 Jan it is 28 Feb, not March.
        #expect(fc.nextMonthly(dayOfMonth: 31, after: day("2026-01-15")) == day("2026-01-31"))
        #expect(fc.nextMonthly(dayOfMonth: 31, after: day("2026-01-31")) == day("2026-02-28"))
        #expect(fc.nextMonthly(dayOfMonth: 31, after: day("2026-02-28")) == day("2026-03-31"))
        // 2028 is a leap year.
        #expect(fc.nextMonthly(dayOfMonth: 31, after: day("2028-01-31")) == day("2028-02-29"))
    }

    @Test func monthlyOnThe1stRollsToNextMonth() {
        let fc = calendar()
        #expect(fc.nextMonthly(dayOfMonth: 1, after: day("2026-09-01")) == day("2026-10-01"))
        #expect(fc.nextMonthly(dayOfMonth: 1, after: day("2026-12-15")) == day("2027-01-01"))
    }

    @Test func yearlyClampsLeapDay() {
        let fc = calendar()
        #expect(fc.nextYearly(month: 2, dayOfMonth: 29, after: day("2026-03-01")) == day("2027-02-28"))
        #expect(fc.nextYearly(month: 2, dayOfMonth: 29, after: day("2027-03-01")) == day("2028-02-29"))
    }

    @Test func clampedDayNeverOverflowsIntoTheNextMonth() {
        let fc = calendar()
        #expect(fc.date(year: 2026, month: 2, clampedDay: 31) == day("2026-02-28"))
        #expect(fc.date(year: 2026, month: 4, clampedDay: 31) == day("2026-04-30"))
        #expect(fc.date(year: 2026, month: 1, clampedDay: 1) == day("2026-01-01"))
    }

    @Test func monthIntervalAndLength() {
        let fc = calendar()
        #expect(fc.startOfMonth(containing: day("2026-09-12")) == day("2026-09-01"))
        #expect(fc.daysInMonth(containing: day("2026-02-10")) == 28)
        #expect(fc.daysInMonth(containing: day("2028-02-10")) == 29)
        #expect(fc.daysInMonth(containing: day("2026-09-10")) == 30)
        let interval = fc.monthInterval(containing: day("2026-09-12"))
        #expect(interval.start == day("2026-09-01"))
        #expect(interval.end == day("2026-10-01"))
    }

    // MARK: - Day arithmetic

    @Test func daysBetweenIgnoresTimeOfDay() {
        let fc = calendar()
        #expect(fc.daysBetween(date("2026-09-12T23:00:00Z"), date("2026-09-13T02:00:00Z")) == 0)
        #expect(fc.daysBetween(date("2026-09-12T23:00:00Z"), date("2026-09-13T05:00:00Z")) == 1)
        #expect(fc.daysBetween(day("2026-09-13"), day("2026-09-12")) == -1)
    }

    @Test func dayRangesAreInclusiveOfBothEnds() {
        let fc = calendar()
        let range = fc.days(from: day("2026-09-10"), through: day("2026-09-13"))
        #expect(range.count == 4)
        #expect(range.first == day("2026-09-10"))
        #expect(range.last == day("2026-09-13"))
        #expect(fc.days(from: day("2026-09-13"), through: day("2026-09-10")).isEmpty)
    }

    @Test func dayRangeCrossesADaylightSavingChange() {
        // Europe/London springs forward on 2026-03-29. The range must still be 4 days,
        // not 3 days and 23 hours collapsed into one.
        let london = FinancialCalendar(dayBoundaryHour: 4, weekStartsOn: 2,
                                       timeZone: TimeZone(identifier: "Europe/London")!,
                                       now: { Date(timeIntervalSince1970: 0) })
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 27; components.hour = 12
        let start = london.calendar.date(from: components)!
        components.day = 30
        let end = london.calendar.date(from: components)!
        #expect(london.days(from: start, through: end).count == 4)
        #expect(london.daysBetween(start, end) == 3)
    }

    // MARK: - Derived facts

    @Test func ageIsDerivedFromBirthYear() {
        let fc = calendar(now: date("2026-09-12T12:00:00Z"))
        #expect(fc.age(birthYear: 2002) == 24)
        #expect(fc.age(birthYear: 2026) == 0)
    }
}
