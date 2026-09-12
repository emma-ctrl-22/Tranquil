import Testing
import Foundation
@testable import MyFinances

struct LoanEngineTests {
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

    private func loan(
        _ name: String = "Loan", principal: Int, model: Loan.InterestModel,
        months: Int = 12, frequency: PaymentFrequency = .monthly,
        social: Int = 0, direction: LoanDirection = .iOwe,
        paidPrincipal: Int = 0, paymentsMade: Int = 0
    ) -> LoanEngine.LoanInput {
        LoanEngine.LoanInput(
            id: UUID(), name: name, lender: "Lender", direction: direction,
            principal: Money(minorUnits: principal), interestModel: model,
            startDate: day("2026-01-01"), termMonths: months,
            paymentFrequency: frequency, socialWeight: social,
            paidPrincipal: Money(minorUnits: paidPrincipal), paymentsMade: paymentsMade
        )
    }

    // MARK: - Decimal power

    @Test func integerPowerIsExactInDecimal() {
        #expect(LoanEngine.power(Decimal(2), 10) == Decimal(1_024))
        #expect(LoanEngine.power(Decimal(1), 500) == Decimal(1))
        #expect(LoanEngine.power(Decimal(3), 0) == Decimal(1))
        // 1.01^12 — compounding must not drift the way a Double would.
        let compounded = LoanEngine.power(Decimal(string: "1.01")!, 12)
        #expect(compounded > Decimal(string: "1.1268")!)
        #expect(compounded < Decimal(string: "1.1269")!)
    }

    // MARK: - Payment formulas

    @Test func amortisingPaymentMatchesAHandCheckedFigure() {
        // P = 10,000.00, APR 12% → r = 0.01 monthly, n = 12.
        // payment = 1000000 * 0.01 * 1.126825.. / 0.126825.. = 88,848.79 pesewas
        let payment = LoanEngine.amortisingPayment(
            principal: Money(minorUnits: 1_000_000),
            periodicRate: Decimal(string: "0.01")!, periods: 12
        )
        #expect(payment.minorUnits == 88_849)
    }

    @Test func aZeroRateDegradesToEvenSplitNotDivisionByZero() {
        let payment = LoanEngine.amortisingPayment(
            principal: Money(minorUnits: 120_000), periodicRate: 0, periods: 12
        )
        #expect(payment.minorUnits == 10_000)
    }

    @Test func flatRateTotalFollowsTheFormula() {
        // total = P x (1 + rate x years) = 1,000 x (1 + 0.15 x 2) = 1,300
        let total = LoanEngine.flatRateTotal(
            principal: Money(minorUnits: 100_000),
            rate: Decimal(string: "0.15")!, years: 2
        )
        #expect(total.minorUnits == 130_000)
    }

    // MARK: - Schedules

    @Test func interestFreeScheduleDividesExactlyWithNoInterest() {
        let schedule = LoanEngine.schedule(
            for: loan(principal: 200_000, model: .interestFree, months: 12),
            calendar: calendar
        )
        #expect(schedule.periodCount == 12)
        #expect(schedule.totalInterest.isZero)
        // Nothing is lost or created by the division.
        #expect(schedule.totalPrincipal.minorUnits == 200_000)
        #expect(schedule.totalPaid.minorUnits == 200_000)
        #expect(schedule.instalments.last?.balance.isZero == true)
    }

    @Test func anAwkwardPrincipalStillSumsExactly() {
        // 1,000.01 over 7 payments does not divide evenly.
        let schedule = LoanEngine.schedule(
            for: loan(principal: 100_001, model: .interestFree, months: 7),
            calendar: calendar
        )
        #expect(schedule.totalPaid.minorUnits == 100_001)
        #expect(schedule.instalments.last?.balance.isZero == true)
    }

    @Test func flatRateScheduleChargesInterestOnTheOriginalPrincipal() {
        let schedule = LoanEngine.schedule(
            for: loan(principal: 100_000,
                      model: .flatRate(rate: Decimal(string: "0.15")!, years: 1), months: 12),
            calendar: calendar
        )
        #expect(schedule.totalPaid.minorUnits == 115_000)
        #expect(schedule.totalInterest.minorUnits == 15_000)
        #expect(schedule.totalPrincipal.minorUnits == 100_000)
        #expect(schedule.instalments.last?.balance.isZero == true)
    }

    @Test func amortisingScheduleClearsTheBalanceExactly() {
        let schedule = LoanEngine.schedule(
            for: loan(principal: 1_000_000,
                      model: .amortizing(apr: Decimal(string: "0.12")!), months: 12),
            calendar: calendar
        )
        #expect(schedule.periodCount == 12)
        // Principal must sum to exactly what was borrowed — no stray pesewa.
        #expect(schedule.totalPrincipal.minorUnits == 1_000_000)
        #expect(schedule.instalments.last?.balance.isZero == true)
        // Total interest on 10,000 at 12% over a year is roughly 661.
        #expect(schedule.totalInterest.minorUnits > 65_000)
        #expect(schedule.totalInterest.minorUnits < 67_000)
    }

    @Test func interestFallsAsPrincipalRisesAcrossAnAmortisingSchedule() {
        let schedule = LoanEngine.schedule(
            for: loan(principal: 450_000,
                      model: .amortizing(apr: Decimal(string: "0.32")!), months: 18),
            calendar: calendar
        )
        let first = schedule.instalments.first!
        let last = schedule.instalments.last!
        #expect(first.interest > last.interest)
        #expect(first.principal < last.principal)
        #expect(schedule.totalPrincipal.minorUnits == 450_000)
    }

    @Test func scheduleDatesFollowThePaymentFrequency() {
        let monthly = LoanEngine.schedule(
            for: loan(principal: 120_000, model: .interestFree, months: 3), calendar: calendar
        )
        #expect(monthly.instalments.map(\.date)
                == [day("2026-02-01"), day("2026-03-01"), day("2026-04-01")])

        let weekly = LoanEngine.schedule(
            for: loan(principal: 120_000, model: .interestFree, months: 12, frequency: .weekly),
            calendar: calendar
        )
        #expect(weekly.periodCount == 52)
        #expect(weekly.instalments.first?.date == day("2026-01-08"))
    }

    @Test func aLoanThatCannotClearEndsRatherThanLoopingForever() {
        // A payment that never covers the interest would otherwise run forever.
        let schedule = LoanEngine.schedule(
            for: loan(principal: 1_000_000,
                      model: .amortizing(apr: Decimal(string: "50")!), months: 360),
            calendar: calendar
        )
        #expect(schedule.periodCount <= 960)
    }

    // MARK: - Position

    @Test func remainingBalanceReflectsPaymentsMade() {
        let position = LoanEngine.position(
            for: loan(principal: 120_000, model: .interestFree, months: 12, paymentsMade: 4),
            calendar: calendar
        )
        #expect(position.remainingBalance.minorUnits == 80_000)
        #expect(position.paymentsRemaining == 8)
        #expect(!position.isPaidOff)
    }

    @Test func aFullyPaidLoanIsPaidOff() {
        let position = LoanEngine.position(
            for: loan(principal: 120_000, model: .interestFree, months: 12, paymentsMade: 12),
            calendar: calendar
        )
        #expect(position.isPaidOff)
        #expect(position.interestRemaining.isZero)
    }

    @Test func toxicityIsRateOrWhoYouOweItTo() {
        let threshold = Decimal(string: "0.25")!
        let expensive = LoanEngine.position(
            for: loan(principal: 100_000, model: .amortizing(apr: Decimal(string: "0.32")!)),
            calendar: calendar
        )
        let family = LoanEngine.position(
            for: loan(principal: 100_000, model: .interestFree, social: 5), calendar: calendar
        )
        let ordinary = LoanEngine.position(
            for: loan(principal: 100_000, model: .amortizing(apr: Decimal(string: "0.10")!),
                      social: 1),
            calendar: calendar
        )
        #expect(expensive.isToxic(highInterestThreshold: threshold))
        #expect(family.isToxic(highInterestThreshold: threshold))
        #expect(!ordinary.isToxic(highInterestThreshold: threshold))
    }

    // MARK: - Simulator

    @Test func extraPaymentsShortenTheTermAndSaveInterest() {
        let target = loan(principal: 450_000,
                          model: .amortizing(apr: Decimal(string: "0.32")!), months: 18)
        let simulation = LoanEngine.simulateExtra(
            Money(minorUnits: 10_000), on: target, calendar: calendar
        )
        #expect(simulation.periodsSaved > 0)
        #expect(simulation.interestSaved.isPositive)
        #expect(simulation.newTotalInterest < simulation.baseTotalInterest)
        if let base = simulation.basePayoffDate, let new = simulation.newPayoffDate {
            #expect(new < base)
        }
    }

    @Test func extraPaymentsOnAFlatRateLoanShortenButDoNotSaveInterest() {
        // This is exactly why flat-rate borrowing is expensive, and the app should
        // not pretend otherwise.
        let target = loan(principal: 100_000,
                          model: .flatRate(rate: Decimal(string: "0.15")!, years: 1), months: 12)
        let simulation = LoanEngine.simulateExtra(
            Money(minorUnits: 5_000), on: target, calendar: calendar
        )
        #expect(simulation.periodsSaved > 0)
        #expect(simulation.interestSaved.isZero)
    }

    @Test func noExtraMeansNoChange() {
        let target = loan(principal: 450_000,
                          model: .amortizing(apr: Decimal(string: "0.20")!), months: 24)
        let simulation = LoanEngine.simulateExtra(.zero, on: target, calendar: calendar)
        #expect(simulation.periodsSaved == 0)
        #expect(simulation.interestSaved.isZero)
    }

    // MARK: - Payoff order

    private var portfolio: [LoanEngine.Position] {
        [
            loan("Expensive", principal: 450_000,
                 model: .amortizing(apr: Decimal(string: "0.32")!), months: 18, social: 1),
            loan("Family", principal: 200_000, model: .interestFree, months: 10, social: 5),
            loan("Small", principal: 50_000,
                 model: .amortizing(apr: Decimal(string: "0.18")!), months: 6, social: 0),
        ].map { LoanEngine.position(for: $0, calendar: calendar) }
    }

    @Test func avalancheTakesTheHighestRateFirst() {
        let order = LoanEngine.payoffOrder(portfolio, strategy: .avalanche, calendar: calendar)
        #expect(order.map(\.loan.name) == ["Expensive", "Small", "Family"])
    }

    @Test func snowballTakesTheSmallestBalanceFirst() {
        let order = LoanEngine.payoffOrder(portfolio, strategy: .snowball, calendar: calendar)
        #expect(order.first?.loan.name == "Small")
    }

    @Test func peaceOfMindTakesTheFamilyLoanFirst() {
        let order = LoanEngine.payoffOrder(portfolio, strategy: .peaceOfMind, calendar: calendar)
        #expect(order.first?.loan.name == "Family")
    }

    @Test func balancedProducesACompleteDeterministicOrder() {
        let first = LoanEngine.payoffOrder(portfolio, strategy: .balanced, calendar: calendar)
        let second = LoanEngine.payoffOrder(portfolio, strategy: .balanced, calendar: calendar)
        #expect(first.map(\.loan.name) == second.map(\.loan.name))
        #expect(first.count == 3)
    }

    @Test func moneyOwedToYouIsNotInThePayoffQueue() {
        // R11: a receivable is not a debt, and never appears in what to clear.
        let positions = portfolio + [
            LoanEngine.position(
                for: loan("Lent to Kojo", principal: 50_000, model: .interestFree,
                          direction: .owedToMe),
                calendar: calendar
            )
        ]
        let order = LoanEngine.payoffOrder(positions, strategy: .avalanche, calendar: calendar)
        #expect(order.count == 3)
        #expect(!order.contains { $0.loan.name == "Lent to Kojo" })
    }

    @Test func anEmptyPortfolioOrdersToNothing() {
        #expect(LoanEngine.payoffOrder([], strategy: .balanced, calendar: calendar).isEmpty)
    }

    // MARK: - Verdict

    private func verdict(
        principal: Int, apr: String, months: Int, income: Int,
        existing: [LoanEngine.Position] = []
    ) -> LoanEngine.LoanVerdict {
        LoanEngine.verdict(
            for: loan(principal: principal, model: .amortizing(apr: Decimal(string: apr)!),
                      months: months),
            existingPositions: existing,
            medianMonthlyNetIncome: Money(minorUnits: income),
            maxDebtServiceRatio: Decimal(string: "0.30")!,
            highInterestThreshold: Decimal(string: "0.25")!,
            calendar: calendar
        )
    }

    @Test func aSmallLoanAgainstAGoodIncomeIsComfortable() {
        // ₵1,000 over 24 months at 12% ≈ ₵47/month against ₵3,500 income — about 1.3%.
        let result = verdict(principal: 100_000, apr: "0.12", months: 24, income: 350_000)
        #expect(result.affordability == .comfortable)
        #expect(result.verdict == .approved)
        #expect(result.debtServiceRatio < Decimal(string: "0.15")!)
    }

    @Test func aboveThirtyPercentIsNotAffordableNotTight() {
        // R4. Above the cap the app says "not affordable" and blocks.
        let result = verdict(principal: 3_000_000, apr: "0.30", months: 24, income: 350_000)
        #expect(result.affordability == .notAffordable)
        #expect(result.verdict == .blocked)
        #expect(result.ruleIDs.contains("R4"))
    }

    @Test func theMiddleBandIsTight() {
        let result = verdict(principal: 1_200_000, apr: "0.20", months: 24, income: 350_000)
        #expect(result.affordability == .tight)
        #expect(result.debtServiceRatio > Decimal(string: "0.15")!)
        #expect(result.debtServiceRatio <= Decimal(string: "0.30")!)
    }

    @Test func existingDebtCountsTowardsTheRatio() {
        let existing = [LoanEngine.position(
            for: loan("Existing", principal: 450_000,
                      model: .amortizing(apr: Decimal(string: "0.32")!), months: 18),
            calendar: calendar
        )]
        let alone = verdict(principal: 100_000, apr: "0.12", months: 24, income: 350_000)
        let withExisting = verdict(principal: 100_000, apr: "0.12", months: 24,
                                   income: 350_000, existing: existing)
        #expect(withExisting.debtServiceRatio > alone.debtServiceRatio)
        #expect(withExisting.existingMonthlyDebt.isPositive)
    }

    @Test func borrowingWhileToxicDebtIsOutstandingRaisesR1() {
        let toxic = [LoanEngine.position(
            for: loan("Toxic", principal: 200_000,
                      model: .amortizing(apr: Decimal(string: "0.40")!), months: 24),
            calendar: calendar
        )]
        let result = verdict(principal: 50_000, apr: "0.10", months: 12,
                             income: 350_000, existing: toxic)
        #expect(result.ruleIDs.contains("R1"))
        // Affordable on the arithmetic, but not a clean approval.
        #expect(result.verdict != .approved)
    }

    @Test func noIncomeMeansNothingIsAffordable() {
        // Dividing by zero income must not crash or read as comfortable.
        let result = verdict(principal: 100_000, apr: "0.12", months: 24, income: 0)
        #expect(result.affordability == .notAffordable)
        #expect(result.debtServiceRatio == Decimal(1))
    }

    @Test func monthlyEquivalentConvertsFrequencies() {
        // ₵100 a week is ₵433.33 a month.
        #expect(LoanEngine.monthlyEquivalent(Money(minorUnits: 10_000), frequency: .weekly)
                    .minorUnits == 43_333)
        #expect(LoanEngine.monthlyEquivalent(Money(minorUnits: 10_000), frequency: .monthly)
                    .minorUnits == 10_000)
        #expect(LoanEngine.monthlyEquivalent(Money(minorUnits: 30_000), frequency: .quarterly)
                    .minorUnits == 10_000)
    }
}
