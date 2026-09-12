import Testing
import Foundation
@testable import MyFinances

struct ForecastEngineTests {
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

    private func item(
        _ label: String, _ minorUnits: Int, _ kind: TransactionKind,
        cadence: RecurringRule.Cadence, next: String, end: String? = nil,
        variable: Bool = false
    ) -> ForecastEngine.ScheduledItem {
        ForecastEngine.ScheduledItem(
            id: UUID(), label: label, amount: Money(minorUnits: minorUnits), kind: kind,
            cadence: cadence, nextDueDate: day(next), endDate: end.map(day),
            isVariableAmount: variable, isCommittedOutflow: kind == .expense
        )
    }

    // MARK: - Cadence

    @Test func weeklyOccurrencesLandEverySevenDays() {
        let rule = item("Transport", 5_000, .expense, cadence: .weekly, next: "2026-09-14")
        let dates = ForecastEngine.occurrences(of: rule, from: day("2026-09-12"),
                                               through: day("2026-10-05"), calendar: calendar)
        #expect(dates == [day("2026-09-14"), day("2026-09-21"),
                          day("2026-09-28"), day("2026-10-05")])
    }

    @Test func monthlyOnThe31stClampsNeverSkips() {
        let rule = item("Rent", 90_000, .expense, cadence: .monthly(day: 31), next: "2026-01-31")
        let dates = ForecastEngine.occurrences(of: rule, from: day("2026-01-01"),
                                               through: day("2026-04-30"), calendar: calendar)
        #expect(dates == [day("2026-01-31"), day("2026-02-28"),
                          day("2026-03-31"), day("2026-04-30")])
    }

    @Test func aRuleThatHasFallenBehindIsCaughtUpNotDuplicated() {
        // Due date three months stale: it must not emit the missed occurrences.
        let rule = item("Rent", 90_000, .expense, cadence: .monthly(day: 1), next: "2026-06-01")
        let dates = ForecastEngine.occurrences(of: rule, from: day("2026-09-12"),
                                               through: day("2026-10-15"), calendar: calendar)
        #expect(dates == [day("2026-10-01")])
    }

    @Test func endDateStopsTheSeries() {
        let rule = item("Instalment", 20_000, .expense, cadence: .weekly,
                        next: "2026-09-14", end: "2026-09-28")
        let dates = ForecastEngine.occurrences(of: rule, from: day("2026-09-12"),
                                               through: day("2026-11-01"), calendar: calendar)
        #expect(dates == [day("2026-09-14"), day("2026-09-21"), day("2026-09-28")])
    }

    @Test func yearlyAndCustomCadences() {
        let yearly = item("Insurance", 52_000, .expense,
                          cadence: .yearly(month: 12, day: 25), next: "2026-12-25")
        #expect(ForecastEngine.occurrences(of: yearly, from: day("2026-09-12"),
                                           through: day("2027-12-31"),
                                           calendar: calendar).count == 2)
        let custom = item("Water", 3_000, .expense, cadence: .custom(days: 10),
                          next: "2026-09-15")
        #expect(ForecastEngine.occurrences(of: custom, from: day("2026-09-12"),
                                           through: day("2026-10-15"),
                                           calendar: calendar)
                == [day("2026-09-15"), day("2026-09-25"), day("2026-10-05"), day("2026-10-15")])
    }

    @Test func anEmptyOrBackwardsWindowYieldsNothing() {
        let rule = item("Rent", 90_000, .expense, cadence: .monthly(day: 1), next: "2026-10-01")
        #expect(ForecastEngine.occurrences(of: rule, from: day("2026-10-05"),
                                           through: day("2026-10-01"),
                                           calendar: calendar).isEmpty)
    }

    // MARK: - Projection

    @Test func balanceWalksForwardDayByDay() {
        // Start ₵1,000.00. Salary +₵3,500 on the 28th, rent −₵900 on the 1st.
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 100_000),
            from: day("2026-09-25"), days: 10,
            scheduled: [
                item("Salary", 350_000, .income, cadence: .monthly(day: 28), next: "2026-09-28"),
                item("Rent", 90_000, .expense, cadence: .monthly(day: 1), next: "2026-10-01"),
            ],
            oneOffs: [], calendar: calendar
        )
        #expect(projection.days.count == 10)
        #expect(projection.days[0].closingBalance.minorUnits == 100_000)   // 25th
        #expect(projection.days[3].closingBalance.minorUnits == 450_000)   // 28th, salary
        #expect(projection.days[6].closingBalance.minorUnits == 360_000)   // 1 Oct, rent
        #expect(projection.endingBalance.minorUnits == 360_000)
    }

    @Test func findsTheFirstNegativeDayAndItsReason() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 50_000),
            from: day("2026-09-12"), days: 30,
            scheduled: [
                item("Rent", 90_000, .expense, cadence: .monthly(day: 24), next: "2026-09-24")
            ],
            oneOffs: [], calendar: calendar
        )
        #expect(projection.hasTrouble)
        let negative = projection.firstNegativeDay
        #expect(negative?.date == day("2026-09-24"))
        #expect(negative?.closingBalance.minorUnits == -40_000)
        #expect(negative?.movements.first?.label == "Rent")
    }

    @Test func aHealthyProjectionReportsNoTrouble() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 500_000),
            from: day("2026-09-12"), days: 60,
            scheduled: [item("Rent", 90_000, .expense, cadence: .monthly(day: 1),
                             next: "2026-10-01")],
            oneOffs: [], calendar: calendar
        )
        #expect(!projection.hasTrouble)
        #expect(projection.firstNegativeDay == nil)
    }

    @Test func theFloorWarnsBeforeZeroDoes() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 100_000),
            from: day("2026-09-12"), days: 30,
            scheduled: [item("Rent", 70_000, .expense, cadence: .monthly(day: 24),
                             next: "2026-09-24")],
            oneOffs: [], floor: Money(minorUnits: 50_000), calendar: calendar
        )
        // 1,000 − 700 = 300, above zero but below the 500 floor.
        #expect(projection.firstNegativeDay == nil)
        #expect(projection.firstDayBelowFloor?.date == day("2026-09-24"))
        #expect(projection.hasTrouble)
    }

    @Test func oneOffEventsLandOnTheirDay() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 100_000),
            from: day("2026-09-12"), days: 30,
            scheduled: [],
            oneOffs: [
                .init(id: UUID(), label: "Kofi's wedding", amount: Money(minorUnits: 40_000),
                      kind: .expense, date: day("2026-09-20"), confidence: .certain)
            ],
            calendar: calendar
        )
        #expect(projection.days.first { $0.date == day("2026-09-20") }?
                    .closingBalance.minorUnits == 60_000)
        #expect(projection.endingBalance.minorUnits == 60_000)
    }

    @Test func eventsOutsideTheWindowAreIgnored() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 100_000),
            from: day("2026-09-12"), days: 10,
            scheduled: [],
            oneOffs: [
                .init(id: UUID(), label: "Later", amount: Money(minorUnits: 90_000),
                      kind: .expense, date: day("2026-11-01"), confidence: .certain),
                .init(id: UUID(), label: "Earlier", amount: Money(minorUnits: 90_000),
                      kind: .expense, date: day("2026-08-01"), confidence: .certain),
            ],
            calendar: calendar
        )
        #expect(projection.endingBalance.minorUnits == 100_000)
    }

    @Test func variableAmountsAreMarkedAsEstimates() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 100_000),
            from: day("2026-09-12"), days: 40,
            scheduled: [item("Electricity", 18_000, .expense, cadence: .monthly(day: 12),
                             next: "2026-10-12", variable: true)],
            oneOffs: [
                .init(id: UUID(), label: "Maybe wedding", amount: Money(minorUnits: 20_000),
                      kind: .expense, date: day("2026-09-20"), confidence: .maybe)
            ],
            calendar: calendar
        )
        let allMovements = projection.days.flatMap(\.movements)
        let everyOneIsAnEstimate = allMovements.allSatisfy(\.isEstimate)
        #expect(everyOneIsAnEstimate)
        #expect(allMovements.count == 2)
    }

    @Test func anEmptyForecastIsFlatNotEmpty() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 25_000),
            from: day("2026-09-12"), days: 60,
            scheduled: [], oneOffs: [], calendar: calendar
        )
        #expect(projection.days.count == 60)
        #expect(projection.endingBalance.minorUnits == 25_000)
        #expect(!projection.hasTrouble)
        let nothingScheduled = projection.days.allSatisfy { !$0.hasMovement }
        #expect(nothingScheduled)
    }

    @Test func sixtyDaysStartsToday() {
        let projection = ForecastEngine.project(
            startingBalance: .zero, from: day("2026-09-12"), days: 60,
            scheduled: [], oneOffs: [], calendar: calendar
        )
        #expect(projection.days.first?.date == day("2026-09-12"))
        #expect(projection.days.last?.date == day("2026-11-10"))
    }

    // MARK: - Suggestion

    @Test func theSuggestionNamesTheMovementWorthShifting() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 50_000),
            from: day("2026-09-12"), days: 30,
            scheduled: [
                item("Rent", 90_000, .expense, cadence: .monthly(day: 24), next: "2026-09-24"),
                item("Data", 4_000, .expense, cadence: .monthly(day: 24), next: "2026-09-24"),
            ],
            oneOffs: [], calendar: calendar
        )
        let formatter = MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB"))
        let suggestion = ForecastEngine.suggestion(for: projection, formatter: formatter)
        // It names the largest outflow on the day, not the first one it happened to find.
        #expect(suggestion?.contains("Rent") == true)
        #expect(suggestion?.contains("₵900.00") == true)   // the movement worth moving
        #expect(suggestion?.contains("₵440.00") == true)   // the shortfall it would clear
    }

    @Test func noTroubleMeansNoSuggestion() {
        let projection = ForecastEngine.project(
            startingBalance: Money(minorUnits: 500_000), from: day("2026-09-12"),
            days: 60, scheduled: [], oneOffs: [], calendar: calendar
        )
        let formatter = MoneyFormatter(currency: .ghs)
        #expect(ForecastEngine.suggestion(for: projection, formatter: formatter) == nil)
    }
}
