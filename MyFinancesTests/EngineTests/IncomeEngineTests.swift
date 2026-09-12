import Testing
import Foundation
@testable import MyFinances

struct IncomeEngineTests {
    private let formatter = MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB"))

    // MARK: - Interception

    @Test func anythingAboveOnePointFiveWeeksIsIntercepted() {
        let median = Money(minorUnits: 80_769)   // ₵807.69 a week
        let threshold = Decimal(string: "1.5")!
        // 1.5 x 80,769 = 121,153.5, which banker's-rounds to 121,154.
        // The rule is *above* the line, so the line itself is not a windfall.
        #expect(IncomeEngine.isWindfall(Money(minorUnits: 121_155),
                                        medianWeeklyIncome: median, multiple: threshold))
        #expect(!IncomeEngine.isWindfall(Money(minorUnits: 121_154),
                                         medianWeeklyIncome: median, multiple: threshold))
        #expect(!IncomeEngine.isWindfall(Money(minorUnits: 50_000),
                                         medianWeeklyIncome: median, multiple: threshold))
    }

    @Test func withNoIncomeHistoryNothingIsIntercepted() {
        // Otherwise the very first entry would be held hostage on day one.
        #expect(!IncomeEngine.isWindfall(Money(minorUnits: 500_000),
                                         medianWeeklyIncome: .zero,
                                         multiple: Decimal(string: "1.5")!))
    }

    // MARK: - Tax reserve (R3)

    @Test func untaxedIncomeReservesTax() {
        // 25% of ₵5,000 is ₵1,250.
        let reserve = IncomeEngine.taxReserve(on: Money(minorUnits: 500_000),
                                              rate: Decimal(string: "0.25")!,
                                              kind: .projectPayment)
        #expect(reserve.minorUnits == 125_000)
    }

    @Test func alreadyTaxedIncomeReservesNothing() {
        for kind in [IncomeEventKind.salaryRise, .gift, .refund] {
            #expect(IncomeEngine.taxReserve(on: Money(minorUnits: 500_000),
                                            rate: Decimal(string: "0.25")!, kind: kind).isZero)
        }
    }

    @Test func netUsableIsGrossLessTaxAndCosts() {
        let net = IncomeEngine.netUsable(gross: Money(minorUnits: 500_000),
                                         taxReserved: Money(minorUnits: 125_000),
                                         directCosts: Money(minorUnits: 30_000))
        #expect(net.minorUnits == 345_000)
        // Costs exceeding the gross floor at zero rather than going negative.
        #expect(IncomeEngine.netUsable(gross: Money(minorUnits: 1_000),
                                       taxReserved: Money(minorUnits: 800),
                                       directCosts: Money(minorUnits: 500)).isZero)
    }

    // MARK: - Splits

    @Test func theProjectSplitMatchesTheSpec() {
        let shares = IncomeEngine.projectPaymentSplit.map(\.share)
        #expect(shares == [40, 25, 20, 15])
        #expect(IncomeEngine.sharesAreComplete(IncomeEngine.projectPaymentSplit))
    }

    @Test func theSalaryRiseSplitMatchesTheSpec() {
        let shares = IncomeEngine.salaryRiseSplit.map(\.share)
        #expect(shares == [40, 30, 20, 10])
        #expect(IncomeEngine.sharesAreComplete(IncomeEngine.salaryRiseSplit))
    }

    @Test func allocatingASplitLosesNothing() {
        let net = Money(minorUnits: 345_001)
        let result = IncomeEngine.allocate(net, across: IncomeEngine.projectPaymentSplit)
        #expect(Money.sum(result.map(\.amount)) == net)
        #expect(result.count == 4)
    }

    @Test func aSplitThatDoesNotTotalOneHundredIsIncomplete() {
        let broken = Array(IncomeEngine.projectPaymentSplit.dropLast())
        #expect(!IncomeEngine.sharesAreComplete(broken))
    }

    @Test func theFreeSliceExistsOnPurpose() {
        // A system with zero enjoyment gets abandoned in four months.
        let free = IncomeEngine.projectPaymentSplit.first { $0.kind == .free }
        #expect(free?.share == 15)
    }

    // MARK: - Effective hourly rate

    @Test func effectiveHourlyRateIsNetOverHours() {
        // ₵3,450 over 40 hours is ₵86.25 an hour.
        #expect(IncomeEngine.effectiveHourlyRate(netUsable: Money(minorUnits: 345_000),
                                                 hoursWorked: 40)?.minorUnits == 8_625)
        #expect(IncomeEngine.effectiveHourlyRate(netUsable: Money(minorUnits: 345_000),
                                                 hoursWorked: nil) == nil)
        #expect(IncomeEngine.effectiveHourlyRate(netUsable: Money(minorUnits: 345_000),
                                                 hoursWorked: 0) == nil)
    }

    @Test func clientRatesRollUpAndSortByRate() {
        let rates = IncomeEngine.clientRates([
            (client: "Acme", netUsable: Money(minorUnits: 200_000), hours: 40),
            (client: "Acme", netUsable: Money(minorUnits: 200_000), hours: 40),
            (client: "Beta", netUsable: Money(minorUnits: 300_000), hours: 20),
            (client: nil, netUsable: Money(minorUnits: 999_999), hours: 1),
        ])
        #expect(rates.count == 2)
        // Beta pays ₵150/hr, Acme ₵50/hr.
        #expect(rates.first?.client == "Beta")
        #expect(rates.first?.hourlyRate?.minorUnits == 15_000)
        #expect(rates.last?.hourlyRate?.minorUnits == 5_000)
    }

    // MARK: - Concentration

    @Test func oneSourceOverSixtyPercentRaisesTheEmergencyTarget() {
        let result = IncomeEngine.concentration(
            ["Employer": Money(minorUnits: 700_000), "Side": Money(minorUnits: 300_000)],
            baseEmergencyMonths: 3
        )
        #expect(result.isConcentrated)
        #expect(result.topSource == "Employer")
        #expect(result.recommendedEmergencyMonths == 6)
    }

    @Test func exactlySixtyPercentIsNotConcentrated() {
        let result = IncomeEngine.concentration(
            ["A": Money(minorUnits: 600_000), "B": Money(minorUnits: 400_000)],
            baseEmergencyMonths: 3
        )
        #expect(result.share == Decimal(string: "0.6"))
        #expect(!result.isConcentrated)
        #expect(result.recommendedEmergencyMonths == 3)
    }

    @Test func noIncomeMeansNoConcentrationVerdict() {
        let result = IncomeEngine.concentration([:], baseEmergencyMonths: 3)
        #expect(!result.isConcentrated)
        #expect(result.topSource == nil)
    }

    // MARK: - Salary rise

    @Test func onlyAnIncreaseCountsAsARise() {
        let rise = IncomeEngine.salaryRise(previous: Money(minorUnits: 350_000),
                                           current: Money(minorUnits: 420_000))
        #expect(rise?.delta.minorUnits == 70_000)
        #expect(rise?.percentage == Decimal(string: "0.2"))
        // A cut is not a rise, and neither is standing still.
        #expect(IncomeEngine.salaryRise(previous: Money(minorUnits: 350_000),
                                        current: Money(minorUnits: 300_000)) == nil)
        #expect(IncomeEngine.salaryRise(previous: Money(minorUnits: 350_000),
                                        current: Money(minorUnits: 350_000)) == nil)
        #expect(IncomeEngine.salaryRise(previous: nil,
                                        current: Money(minorUnits: 350_000)) == nil)
    }

    @Test func onlyTheDeltaIsAllocatedNotTheWholeSalary() {
        // This is the whole point of the ratchet.
        let rise = IncomeEngine.salaryRise(previous: Money(minorUnits: 350_000),
                                           current: Money(minorUnits: 420_000))!
        let allocated = IncomeEngine.allocate(rise.delta, across: IncomeEngine.salaryRiseSplit)
        #expect(Money.sum(allocated.map(\.amount)).minorUnits == 70_000)
        // 40% of the ₵700 delta goes to investing.
        #expect(allocated.first?.amount.minorUnits == 28_000)
    }

    // MARK: - Creep

    private func point(_ month: Int, essentials: Int, income: Int) -> IncomeEngine.CreepPoint {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 1
        let date = Calendar(identifier: .gregorian).date(from: components)!
        return IncomeEngine.CreepPoint(monthStart: date,
                                       essentialSpend: Money(minorUnits: essentials),
                                       netIncome: Money(minorUnits: income))
    }

    @Test func twoRisingQuartersIsCreep() {
        // Essentials climb 40% → 50% → 60% of a flat income.
        let points = (1...9).map { month -> IncomeEngine.CreepPoint in
            let ratio = month <= 3 ? 40 : (month <= 6 ? 50 : 60)
            return point(month, essentials: 1_000 * ratio, income: 100_000)
        }
        let verdict = IncomeEngine.creep(points: points, drivers: ["Rent", "Lunch"])
        #expect(verdict.isCreeping)
        #expect(verdict.drivers == ["Rent", "Lunch"])
    }

    @Test func aFlatShareIsNotCreep() {
        let points = (1...9).map { point($0, essentials: 40_000, income: 100_000) }
        #expect(!IncomeEngine.creep(points: points).isCreeping)
    }

    @Test func aFallingShareIsNotCreep() {
        // Income rising faster than essentials is exactly what you want.
        let points = (1...9).map { month -> IncomeEngine.CreepPoint in
            let income = 100_000 + month * 5_000
            return point(month, essentials: 40_000, income: income)
        }
        #expect(!IncomeEngine.creep(points: points).isCreeping)
    }

    @Test func oneBadQuarterIsNotCreep() {
        // Up then down must not trip the flag; creep is a trend, not a month.
        let points = (1...9).map { month -> IncomeEngine.CreepPoint in
            let ratio = month <= 3 ? 40 : (month <= 6 ? 55 : 45)
            return point(month, essentials: 1_000 * ratio, income: 100_000)
        }
        #expect(!IncomeEngine.creep(points: points).isCreeping)
    }

    @Test func tooLittleHistoryCannotBeCreeping() {
        let points = (1...5).map { point($0, essentials: 40_000 + $0 * 5_000, income: 100_000) }
        #expect(!IncomeEngine.creep(points: points).isCreeping)
        #expect(!IncomeEngine.creep(points: []).isCreeping)
    }

    @Test func aMonthWithNoIncomeHasNoRatioAndDoesNotBreakTheChart() {
        let zero = point(1, essentials: 40_000, income: 0)
        #expect(zero.ratio == nil)
        let verdict = IncomeEngine.creep(points: [zero])
        #expect(!verdict.isCreeping)
        #expect(verdict.points.count == 1)
    }

    // MARK: - Refunds

    @Test func aRefundIsNeverIncome() {
        // Getting this wrong makes every other number lie.
        #expect(!IncomeEngine.countsTowardIncome(.refund))
        #expect(IncomeEngine.countsTowardIncome(.projectPayment))
        #expect(IncomeEngine.countsTowardIncome(.bonus))
        #expect(IncomeEngine.countsTowardIncome(.gift))
    }
}

/// The monthly check that what arrived matches what you said you earn.
struct SalaryCheckTests {

    private func check(expected: Int, received: Int, payDayPassed: Bool = true)
    -> IncomeEngine.SalaryCheck {
        IncomeEngine.salaryCheck(expectedMonthly: Money(minorUnits: expected),
                                 receivedThisMonth: Money(minorUnits: received),
                                 payDayPassed: payDayPassed)
    }

    @Test func anExactMatchNeedsNoConfirmation() {
        let result = check(expected: 350_000, received: 350_000)
        #expect(result.status == .matches)
        #expect(!result.needsConfirmation)
        #expect(result.difference.isZero)
    }

    @Test func smallRoundingNoiseCountsAsAMatch() {
        // Pay wobbles by a few pesewas. Prompting monthly about that trains you to ignore it.
        // 1% of ₵3,500 is ₵35.
        #expect(check(expected: 350_000, received: 353_400).status == .matches)
        #expect(check(expected: 350_000, received: 346_600).status == .matches)
        #expect(check(expected: 350_000, received: 353_600).status == .more)
        #expect(check(expected: 350_000, received: 346_400).status == .less)
    }

    @Test func moreThanExpectedIsARise() {
        let result = check(expected: 350_000, received: 420_000)
        #expect(result.status == .more)
        #expect(result.needsConfirmation)
        #expect(result.isRise)
        #expect(result.difference.minorUnits == 70_000)
    }

    @Test func lessThanExpectedIsFlaggedButIsNotARise() {
        // A short month must not ratchet anything.
        let result = check(expected: 350_000, received: 300_000)
        #expect(result.status == .less)
        #expect(result.needsConfirmation)
        #expect(!result.isRise)
        #expect(result.difference.minorUnits == -50_000)
    }

    @Test func nothingReceivedAfterPayDayIsRaised() {
        let result = check(expected: 350_000, received: 0, payDayPassed: true)
        #expect(result.status == .nothingReceived)
        #expect(result.needsConfirmation)
    }

    @Test func beforePayDayAShortfallIsNotADiscrepancy() {
        // Mid-month with nothing in yet is normal, not a problem.
        let result = check(expected: 350_000, received: 0, payDayPassed: false)
        #expect(result.status == .notYetDue)
        #expect(!result.needsConfirmation)
    }

    @Test func moneyArrivingEarlyStillReadsCorrectly() {
        let result = check(expected: 350_000, received: 350_000, payDayPassed: false)
        #expect(result.status == .matches)
    }
}
