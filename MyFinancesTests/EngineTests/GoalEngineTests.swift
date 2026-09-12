import Testing
import Foundation
@testable import MyFinances

struct GoalEngineTests {
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

    private func goal(
        _ name: String, target: Int, saved: Int = 0, rank: Int = 0,
        cap: Int? = nil, status: GoalStatus = .saving, id: UUID = UUID()
    ) -> GoalEngine.GoalInput {
        GoalEngine.GoalInput(
            id: id, name: name, targetAmount: Money(minorUnits: target), targetDate: nil,
            priorityRank: rank, holdingAccountID: nil,
            monthlyCap: cap.map(Money.init(minorUnits:)), desireLevel: 3,
            status: status, saved: Money(minorUnits: saved)
        )
    }

    private func fund(_ name: String, required: Int, isEmergency: Bool = false)
    -> GoalEngine.FundInput {
        GoalEngine.FundInput(id: UUID(), name: name,
                             requiredThisPeriod: Money(minorUnits: required),
                             isEmergencyFund: isEmergency)
    }

    // MARK: - Waterfall

    @Test func theLadderRequirementIsPaidFirst() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 100_000),
            ladderRequirement: .init(label: "Buffer top-up",
                                     amountThisPeriod: Money(minorUnits: 40_000)),
            funds: [fund("Gifts", required: 20_000)],
            goals: [goal("iPhone", target: 900_000)]
        )
        #expect(result.allocations.first?.kind == .ladderGap)
        #expect(result.allocations.first?.amount.minorUnits == 40_000)
        #expect(result.leftover.isZero)
    }

    @Test func theEmergencyFundComesBeforeOtherFunds() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 30_000),
            ladderRequirement: .none,
            funds: [fund("Gifts", required: 20_000),
                    fund("Emergency", required: 25_000, isEmergency: true)],
            goals: []
        )
        #expect(result.allocations.first?.label == "Emergency")
        #expect(result.allocations.first?.amount.minorUnits == 25_000)
        // The rest of the surplus trickles to Gifts.
        #expect(result.allocations.last?.amount.minorUnits == 5_000)
    }

    @Test func goalsAreFundedInPriorityOrderNotByDesire() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 50_000),
            ladderRequirement: .none, funds: [],
            goals: [goal("Second", target: 100_000, rank: 1),
                    goal("First", target: 100_000, rank: 0)]
        )
        #expect(result.allocations.map(\.label) == ["First"])
        #expect(result.allocations.first?.amount.minorUnits == 50_000)
    }

    @Test func aMonthlyCapStopsOneGoalEatingEverything() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 100_000),
            ladderRequirement: .none, funds: [],
            goals: [goal("iPhone", target: 900_000, rank: 0, cap: 60_000),
                    goal("Course", target: 180_000, rank: 1)]
        )
        #expect(result.allocations.count == 2)
        #expect(result.allocations[0].amount.minorUnits == 60_000)
        #expect(result.allocations[1].amount.minorUnits == 40_000)
    }

    @Test func aGoalNeverReceivesMoreThanItNeeds() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 100_000),
            ladderRequirement: .none, funds: [],
            goals: [goal("Nearly there", target: 100_000, saved: 95_000)]
        )
        #expect(result.allocations.first?.amount.minorUnits == 5_000)
        #expect(result.leftover.minorUnits == 95_000)
    }

    @Test func fundedAndAbandonedGoalsAreSkipped() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: 50_000),
            ladderRequirement: .none, funds: [],
            goals: [goal("Done", target: 10_000, saved: 10_000),
                    goal("Abandoned", target: 50_000, status: .abandoned),
                    goal("Live", target: 50_000, rank: 2)]
        )
        #expect(result.allocations.map(\.label) == ["Live"])
    }

    @Test func noSurplusAllocatesNothingRatherThanGoingNegative() {
        let result = GoalEngine.waterfall(
            surplus: Money(minorUnits: -5_000),
            ladderRequirement: .init(label: "Buffer",
                                     amountThisPeriod: Money(minorUnits: 40_000)),
            funds: [fund("Gifts", required: 20_000)],
            goals: [goal("iPhone", target: 900_000)]
        )
        #expect(result.allocations.isEmpty)
        #expect(result.leftover.isZero)
    }

    @Test func theWaterfallNeverAllocatesMoreThanTheSurplus() {
        let surplus = Money(minorUnits: 37_777)
        let result = GoalEngine.waterfall(
            surplus: surplus,
            ladderRequirement: .init(label: "Buffer",
                                     amountThisPeriod: Money(minorUnits: 20_000)),
            funds: [fund("Gifts", required: 15_000), fund("Repairs", required: 15_000)],
            goals: [goal("A", target: 500_000, rank: 0), goal("B", target: 500_000, rank: 1)]
        )
        let allocated = Money.sum(result.allocations.map(\.amount))
        #expect(allocated + result.leftover == surplus)
        #expect(allocated <= surplus)
    }

    // MARK: - ETA

    @Test func etaAccountsForEverythingAheadInTheQueue() {
        let phoneID = UUID()
        let courseID = UUID()
        let etas = GoalEngine.etas(
            surplusPerPeriod: Money(minorUnits: 100_000),
            ladderRequirement: .none, funds: [],
            goals: [goal("Course", target: 200_000, rank: 0, id: courseID),
                    goal("iPhone", target: 300_000, rank: 1, id: phoneID)],
            periodLength: .monthly, from: day("2026-09-12"), calendar: calendar
        )
        let course = etas.first { $0.goalID == courseID }
        let phone = etas.first { $0.goalID == phoneID }
        // Course needs 2 periods; the phone only starts getting the overflow.
        #expect(course?.periods == 2)
        #expect(phone?.periods == 5)
        #expect(phone!.periods! > course!.periods!)
    }

    @Test func aGoalThatNeverGetsFundedReportsNoETARatherThanGuessing() {
        let starved = UUID()
        let etas = GoalEngine.etas(
            surplusPerPeriod: Money(minorUnits: 10_000),
            ladderRequirement: .none,
            // The fund swallows the whole surplus every period.
            funds: [fund("Emergency", required: 10_000, isEmergency: true)],
            goals: [goal("iPhone", target: 900_000, id: starved)],
            periodLength: .monthly, from: day("2026-09-12"), calendar: calendar
        )
        #expect(etas.first?.periods == nil)
        #expect(etas.first?.isReachable == false)
    }

    @Test func noSurplusMeansNoETA() {
        let etas = GoalEngine.etas(
            surplusPerPeriod: .zero, ladderRequirement: .none, funds: [],
            goals: [goal("iPhone", target: 900_000)],
            periodLength: .weekly, from: day("2026-09-12"), calendar: calendar
        )
        #expect(etas.first?.periods == nil)
    }

    @Test func anAlreadyFundedGoalArrivesImmediately() {
        let funded = goal("Done", target: 100_000, saved: 100_000)
        let eta = GoalEngine.eta(forGoal: funded, atRate: Money(minorUnits: 5_000),
                                 periodLength: .weekly, from: day("2026-09-12"),
                                 calendar: calendar)
        #expect(eta.periods == 0)
        #expect(eta.date == day("2026-09-12"))
    }

    // MARK: - The lever

    @Test func theLeverShowsTheTradeoff() {
        // ₵9,500 target, ₵800 saved → ₵8,700 left.
        // At ₵250/week that is 35 weeks; at ₵400/week it is 22.
        let phone = goal("iPhone", target: 950_000, saved: 80_000)
        let slow = GoalEngine.eta(forGoal: phone, atRate: Money(minorUnits: 25_000),
                                  periodLength: .weekly, from: day("2026-09-12"),
                                  calendar: calendar)
        let fast = GoalEngine.eta(forGoal: phone, atRate: Money(minorUnits: 40_000),
                                  periodLength: .weekly, from: day("2026-09-12"),
                                  calendar: calendar)
        #expect(slow.periods == 35)
        #expect(fast.periods == 22)
        #expect(fast.date! < slow.date!)
    }

    @Test func aRateOfZeroNeverArrives() {
        let phone = goal("iPhone", target: 950_000)
        let eta = GoalEngine.eta(forGoal: phone, atRate: .zero, periodLength: .weekly,
                                 from: day("2026-09-12"), calendar: calendar)
        #expect(eta.periods == nil)
        #expect(!eta.isReachable)
    }

    @Test func anExactDivisionDoesNotRoundUpAnExtraPeriod() {
        // ₵1,000 left at ₵250 a week is exactly 4 weeks, not 5.
        let target = goal("Thing", target: 100_000)
        let eta = GoalEngine.eta(forGoal: target, atRate: Money(minorUnits: 25_000),
                                 periodLength: .weekly, from: day("2026-09-12"),
                                 calendar: calendar)
        #expect(eta.periods == 4)
    }

    // MARK: - Cost in time

    @Test func costInTimeIsExpressedInPeriodsOfTheTopGoal() {
        // ₵1,200 against ₵400 a week is 3 weeks of the iPhone.
        let phone = goal("iPhone", target: 950_000)
        #expect(GoalEngine.costInTime(of: Money(minorUnits: 120_000),
                                      againstGoal: phone,
                                      ratePerPeriod: Money(minorUnits: 40_000)) == 3)
        // A partial period still costs you a period.
        #expect(GoalEngine.costInTime(of: Money(minorUnits: 10_000),
                                      againstGoal: phone,
                                      ratePerPeriod: Money(minorUnits: 40_000)) == 1)
        #expect(GoalEngine.costInTime(of: Money(minorUnits: 120_000),
                                      againstGoal: phone, ratePerPeriod: .zero) == nil)
    }

    // MARK: - Overspend ledger

    @Test func theOverspendLedgerTotalsVarianceBothWays() {
        let entries = [
            GoalEngine.OverspendEntry(id: UUID(), name: "iPhone",
                                      planned: Money(minorUnits: 950_000),
                                      paid: Money(minorUnits: 990_000)),
            GoalEngine.OverspendEntry(id: UUID(), name: "Course",
                                      planned: Money(minorUnits: 180_000),
                                      paid: Money(minorUnits: 165_000)),
        ]
        #expect(entries[0].variance.minorUnits == 40_000)
        #expect(entries[1].variance.minorUnits == -15_000)
        #expect(GoalEngine.overspendTotal(entries).minorUnits == 25_000)
        #expect(GoalEngine.overspendTotal([]).isZero)
    }

    // MARK: - Earmark invariant

    @Test func overCommitmentIsReportedNotCorrected() {
        #expect(GoalEngine.overCommitment(earmarked: Money(minorUnits: 60_000),
                                          balance: Money(minorUnits: 40_000))
                    .minorUnits == 20_000)
        #expect(GoalEngine.overCommitment(earmarked: Money(minorUnits: 10_000),
                                          balance: Money(minorUnits: 40_000)).isZero)
    }
}
