import Testing
import Foundation
@testable import MyFinances

struct InsightsEngineTests {
    private let utc = TimeZone(identifier: "UTC")!

    private var calendar: FinancialCalendar {
        FinancialCalendar(dayBoundaryHour: 4, weekStartsOn: 2, timeZone: utc,
                          now: { self.day("2026-09-12") })
    }

    private func day(_ ymd: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: ymd + "T04:00:00Z")!
    }

    private func input(_ date: Date, entries: Int = 0, spend: Int = 0,
                       inPace: Bool = false) -> InsightsEngine.DayInput {
        InsightsEngine.DayInput(date: date, entryCount: entries,
                                spend: Money(minorUnits: spend), stayedInsidePace: inPace)
    }

    // MARK: - Heatmap

    @Test func theHeatmapCoversFiftyThreeWeeks() {
        let cells = InsightsEngine.heatmap(days: [], mode: .logged,
                                           today: day("2026-09-12"), calendar: calendar)
        // 52 full weeks plus however much of this week has happened: 53 columns.
        #expect(cells.count > 52 * 7)
        #expect(cells.count <= 53 * 7)
        #expect(cells.first?.date == self.calendar.startOfWeek(containing: self.day("2026-09-12")).addingTimeInterval(-364 * 86_400))
        #expect(cells.last?.date == day("2026-09-12"))
    }

    @Test func loggedIntensityRisesWithEntriesAndCapsOut() {
        #expect(InsightsEngine.intensity(mode: .logged, entryCount: 0, spend: .zero,
                                         stayedInsidePace: false, medianSpend: .zero) == 0)
        #expect(InsightsEngine.intensity(mode: .logged, entryCount: 2, spend: .zero,
                                         stayedInsidePace: false, medianSpend: .zero) == 0.5)
        #expect(InsightsEngine.intensity(mode: .logged, entryCount: 4, spend: .zero,
                                         stayedInsidePace: false, medianSpend: .zero) == 1)
        // More than four does not read as "better".
        #expect(InsightsEngine.intensity(mode: .logged, entryCount: 40, spend: .zero,
                                         stayedInsidePace: false, medianSpend: .zero) == 1)
    }

    @Test func spendIntensityIsRelativeToYourOwnMedian() {
        // Never an external benchmark: the app never compares you to anyone.
        let median = Money(minorUnits: 5_000)
        #expect(InsightsEngine.intensity(mode: .spend, entryCount: 1,
                                         spend: Money(minorUnits: 5_000),
                                         stayedInsidePace: false, medianSpend: median) == 0.5)
        #expect(InsightsEngine.intensity(mode: .spend, entryCount: 1,
                                         spend: Money(minorUnits: 10_000),
                                         stayedInsidePace: false, medianSpend: median) == 1)
        #expect(InsightsEngine.intensity(mode: .spend, entryCount: 1, spend: .zero,
                                         stayedInsidePace: false, medianSpend: median) == 0)
    }

    @Test func greenDaysAreBinary() {
        #expect(InsightsEngine.intensity(mode: .greenDay, entryCount: 9,
                                         spend: Money(minorUnits: 99_999),
                                         stayedInsidePace: true, medianSpend: .zero) == 1)
        #expect(InsightsEngine.intensity(mode: .greenDay, entryCount: 9, spend: .zero,
                                         stayedInsidePace: false, medianSpend: .zero) == 0)
    }

    @Test func medianSpendIsTheMiddleNotTheMean() {
        let amounts = [100, 200, 300, 10_000].map(Money.init(minorUnits:))
        // Mean would be 2,650; the median is 250.
        #expect(InsightsEngine.medianSpend(amounts).minorUnits == 250)
        #expect(InsightsEngine.medianSpend([]).isZero)
        #expect(InsightsEngine.medianSpend([Money(minorUnits: 700)]).minorUnits == 700)
    }

    @Test func daysWithNoDataAreEmptyNotMissing() {
        let cells = InsightsEngine.heatmap(days: [input(day("2026-09-10"), entries: 3)],
                                           mode: .logged, today: day("2026-09-12"),
                                           calendar: calendar)
        let logged = cells.first { $0.date == day("2026-09-10") }
        let blank = cells.first { $0.date == day("2026-09-11") }
        #expect(logged?.entryCount == 3)
        #expect(blank?.isEmpty == true)
        #expect(blank?.intensity == 0)
    }

    // MARK: - Streaks

    @Test func theCurrentStreakCountsBackFromToday() {
        let today = day("2026-09-12")
        let days = [
            input(today, entries: 1),
            input(calendar.addDays(-1, to: today), entries: 2),
            input(calendar.addDays(-2, to: today), entries: 1),
            input(calendar.addDays(-4, to: today), entries: 1),
        ]
        let summary = InsightsEngine.streaks(days: days, today: today, calendar: calendar)
        #expect(summary.current == 3)
        #expect(summary.longest == 3)
        #expect(summary.daysLogged == 4)
    }

    @Test func todayNotYetLoggedDoesNotBreakTheStreak() {
        // The day is not over. A streak that punishes you at 09:00 gets muted.
        let today = day("2026-09-12")
        let days = [
            input(calendar.addDays(-1, to: today), entries: 1),
            input(calendar.addDays(-2, to: today), entries: 1),
        ]
        #expect(InsightsEngine.streaks(days: days, today: today, calendar: calendar).current == 2)
    }

    @Test func theLongestStreakIsFoundAnywhereInHistory() {
        let today = day("2026-09-12")
        var days: [InsightsEngine.DayInput] = []
        // A five-day run well in the past.
        for offset in 20...24 { days.append(input(calendar.addDays(-offset, to: today), entries: 1)) }
        // A two-day run just now.
        for offset in 0...1 { days.append(input(calendar.addDays(-offset, to: today), entries: 1)) }
        let summary = InsightsEngine.streaks(days: days, today: today, calendar: calendar)
        #expect(summary.longest == 5)
        #expect(summary.current == 2)
    }

    @Test func noHistoryMeansNoStreakRatherThanACrash() {
        let summary = InsightsEngine.streaks(days: [], today: day("2026-09-12"),
                                             calendar: calendar)
        #expect(summary.current == 0)
        #expect(summary.longest == 0)
        #expect(summary.rate == 0)
    }

    @Test func theLoggingRateIsLoggedOverTotal() {
        let today = day("2026-09-12")
        let days = (0..<10).map { input(calendar.addDays(-$0, to: today), entries: $0 < 5 ? 1 : 0) }
        let summary = InsightsEngine.streaks(days: days, today: today, calendar: calendar)
        #expect(summary.daysLogged == 5)
        #expect(summary.daysTotal == 10)
        #expect(summary.rate == Decimal(string: "0.5"))
    }

    // MARK: - Rollups

    private func total(_ name: String, _ amount: Int, previous: Int = 0,
                       micro: Bool = false) -> InsightsEngine.CategoryTotal {
        InsightsEngine.CategoryTotal(id: UUID(), name: name, colorHex: "#000000",
                                     amount: Money(minorUnits: amount),
                                     previous: Money(minorUnits: previous), isMicro: micro)
    }

    @Test func rollupSortsBySizeAndDropsEmpties() {
        let result = InsightsEngine.rollup([
            total("Lunch", 12_000), total("Nothing", 0), total("Rent", 90_000),
        ])
        #expect(result.map(\.name) == ["Rent", "Lunch"])
    }

    @Test func monthOverMonthDeltaIsSignedBothWays() {
        let up = total("Lunch", 12_000, previous: 10_000)
        let down = total("Data", 3_000, previous: 5_000)
        #expect(up.delta.minorUnits == 2_000)
        #expect(up.deltaFraction == Decimal(string: "0.2"))
        #expect(down.delta.minorUnits == -2_000)
        // No previous period means no percentage rather than a division by zero.
        #expect(total("New", 5_000).deltaFraction == nil)
    }

    @Test func theMicroSpendRollupFindsTheNumberThatHides() {
        // Bus fares and water, a year of them.
        let totals = [
            total("Trotro", 120_000, micro: true),
            total("Water", 36_000, micro: true),
            total("Rent", 1_080_000),
        ]
        #expect(InsightsEngine.microSpendTotal(totals).minorUnits == 156_000)
        #expect(InsightsEngine.microSpendTotal([]).isZero)
    }

    // MARK: - Debt burn-down

    @Test func theBurndownFallsToZeroAndExcludesReceivables() {
        let owed = LoanEngine.position(
            for: LoanEngine.LoanInput(
                id: UUID(), name: "Laptop", lender: "X", direction: .iOwe,
                principal: Money(minorUnits: 120_000), interestModel: .interestFree,
                startDate: day("2026-01-01"), termMonths: 12
            ),
            calendar: calendar
        )
        let lent = LoanEngine.position(
            for: LoanEngine.LoanInput(
                id: UUID(), name: "Lent out", lender: "Kojo", direction: .owedToMe,
                principal: Money(minorUnits: 50_000), interestModel: .interestFree,
                startDate: day("2026-01-01"), termMonths: 12
            ),
            calendar: calendar
        )
        let points = InsightsEngine.debtBurndown(positions: [owed, lent],
                                                 from: day("2026-01-01"), months: 14,
                                                 calendar: calendar)
        #expect(!points.contains { $0.loanName == "Lent out" })
        #expect(points.contains { $0.loanName == "Laptop" })
        // It runs out once the loan is cleared.
        let late = points.filter { $0.date >= self.day("2027-01-01") }
        #expect(late.isEmpty)
    }
}
