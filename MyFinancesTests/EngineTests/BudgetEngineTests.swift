import Testing
import Foundation
@testable import MyFinances

struct BudgetEngineTests {

    private func envelope(
        _ name: String = "Lunch", weekly: Int? = nil, monthly: Int? = nil,
        rollover: Bool = false, cap: Decimal = 2, carriedIn: Int = 0,
        isMiscellaneous: Bool = false
    ) -> BudgetEngine.EnvelopeInput {
        BudgetEngine.EnvelopeInput(
            id: UUID(), categoryID: UUID(), name: name,
            period: weekly != nil ? .weekly : .monthly,
            amount: Money(minorUnits: (weekly ?? monthly ?? 0)),
            rollover: rollover, rolloverCapMultiple: cap,
            isMiscellaneous: isMiscellaneous,
            carriedIn: Money(minorUnits: carriedIn)
        )
    }

    // MARK: - Weekly pace

    @Test func aWeeklyEnvelopeIsItsOwnPace() {
        let state = BudgetEngine.state(for: envelope(weekly: 12_000), spent: .zero,
                                       elapsedDaysInWeek: 1, daysInMonth: 31)
        #expect(state.budget.minorUnits == 12_000)
    }

    @Test func aMonthlyEnvelopeShowsAWeeklyPace() {
        // ₵310.00 a month in a 31-day month paces at ₵70.00 a week.
        let state = BudgetEngine.state(for: envelope(monthly: 31_000), spent: .zero,
                                       elapsedDaysInWeek: 1, daysInMonth: 31)
        #expect(state.budget.minorUnits == 7_000)
        // February: 31,000 x 7 / 28 = 7,750
        let february = BudgetEngine.state(for: envelope(monthly: 31_000), spent: .zero,
                                          elapsedDaysInWeek: 1, daysInMonth: 28)
        #expect(february.budget.minorUnits == 7_750)
    }

    // MARK: - Burn

    @Test func burnAndExpectedFollowTheSpec() {
        // ₵100.00 budget, ₵50.00 spent, day 3 of 7.
        // burn = 0.5, expected = 3/7 ≈ 0.4286, delta ≈ 0.0714 — inside the 0.25 alert.
        let state = BudgetEngine.state(for: envelope(weekly: 10_000),
                                       spent: Money(minorUnits: 5_000),
                                       elapsedDaysInWeek: 3, daysInMonth: 30)
        #expect(state.burn == Decimal(string: "0.5"))
        #expect(state.expectedFraction == Decimal(3) / Decimal(7))
        #expect(!state.isAheadOfPace)
    }

    @Test func alertsWhenBurnExceedsExpectedByMoreThanAQuarter() {
        // Day 2 of 7 (expected ≈ 0.2857) with 80% spent: delta ≈ 0.514 — alert.
        let state = BudgetEngine.state(for: envelope(weekly: 10_000),
                                       spent: Money(minorUnits: 8_000),
                                       elapsedDaysInWeek: 2, daysInMonth: 30)
        #expect(state.isAheadOfPace)
    }

    @Test func theAlertMarginIsASettingNotAConstant() {
        // Same spend, different tolerance: a tighter margin flags it, a looser one does not.
        let spent = Money(minorUnits: 7_000)
        let tight = BudgetEngine.state(for: envelope(weekly: 10_000), spent: spent,
                                       elapsedDaysInWeek: 3, daysInMonth: 30,
                                       alertMargin: Decimal(string: "0.1")!)
        let loose = BudgetEngine.state(for: envelope(weekly: 10_000), spent: spent,
                                       elapsedDaysInWeek: 3, daysInMonth: 30,
                                       alertMargin: Decimal(string: "0.9")!)
        #expect(tight.isAheadOfPace)
        #expect(!loose.isAheadOfPace)
    }

    @Test func exactlyAQuarterAheadDoesNotAlert() {
        // The spec says alert when the gap is *greater* than 0.25, not equal to it.
        // Day 7 of 7: expected = 1.0. Spending 125% is exactly 0.25 over.
        let state = BudgetEngine.state(for: envelope(weekly: 10_000),
                                       spent: Money(minorUnits: 12_500),
                                       elapsedDaysInWeek: 7, daysInMonth: 30)
        #expect(state.paceDelta == Decimal(string: "0.25"))
        #expect(!state.isAheadOfPace)
    }

    @Test func anEnvelopeWithNoBudgetIsNeverAheadOfPace() {
        // Dividing by zero here would crash or produce nonsense; it must do neither.
        let state = BudgetEngine.state(for: envelope(weekly: 0),
                                       spent: Money(minorUnits: 5_000),
                                       elapsedDaysInWeek: 3, daysInMonth: 30)
        #expect(state.burn == nil)
        #expect(!state.isAheadOfPace)
        #expect(state.isOverspent)
        #expect(state.remaining.minorUnits == -5_000)
    }

    @Test func expectedFractionIsClampedToTheWeek() {
        #expect(BudgetEngine.expectedFraction(elapsedDaysInWeek: 0) == 0)
        #expect(BudgetEngine.expectedFraction(elapsedDaysInWeek: 7) == 1)
        #expect(BudgetEngine.expectedFraction(elapsedDaysInWeek: 9) == 1)
        #expect(BudgetEngine.expectedFraction(elapsedDaysInWeek: -3) == 0)
    }

    @Test func remainingGoesNegativeHonestlyWhenOverspent() {
        let state = BudgetEngine.state(for: envelope(weekly: 6_000),
                                       spent: Money(minorUnits: 9_500),
                                       elapsedDaysInWeek: 5, daysInMonth: 30)
        #expect(state.isOverspent)
        #expect(state.remaining.minorUnits == -3_500)
    }

    // MARK: - Rollover

    @Test func rolloverAddsUnspentBudget() {
        let state = BudgetEngine.state(
            for: envelope(weekly: 10_000, rollover: true, carriedIn: 3_000),
            spent: .zero, elapsedDaysInWeek: 1, daysInMonth: 30
        )
        #expect(state.budget.minorUnits == 13_000)
    }

    @Test func rolloverIsCappedAtTwiceTheBudget() {
        // Three quiet weeks must not become a licence to splurge.
        let state = BudgetEngine.state(
            for: envelope(weekly: 10_000, rollover: true, carriedIn: 45_000),
            spent: .zero, elapsedDaysInWeek: 1, daysInMonth: 30
        )
        #expect(state.budget.minorUnits == 20_000)
    }

    @Test func rolloverIsIgnoredWhenTheEnvelopeDoesNotRollOver() {
        let state = BudgetEngine.state(
            for: envelope(weekly: 10_000, rollover: false, carriedIn: 5_000),
            spent: .zero, elapsedDaysInWeek: 1, daysInMonth: 30
        )
        #expect(state.budget.minorUnits == 10_000)
    }

    @Test func carryOutIsUnspentBudgetAndNeverNegative() {
        let under = BudgetEngine.state(for: envelope(weekly: 10_000, rollover: true),
                                       spent: Money(minorUnits: 4_000),
                                       elapsedDaysInWeek: 7, daysInMonth: 30)
        #expect(BudgetEngine.carryOut(for: under).minorUnits == 6_000)

        let over = BudgetEngine.state(for: envelope(weekly: 10_000, rollover: true),
                                      spent: Money(minorUnits: 14_000),
                                      elapsedDaysInWeek: 7, daysInMonth: 30)
        // Overspending does not create a debt that follows you into next week.
        #expect(BudgetEngine.carryOut(for: over).isZero)

        let noRollover = BudgetEngine.state(for: envelope(weekly: 10_000, rollover: false),
                                            spent: .zero, elapsedDaysInWeek: 7, daysInMonth: 30)
        #expect(BudgetEngine.carryOut(for: noRollover).isZero)
    }

    // MARK: - Commitments

    @Test func commitmentsAreProratedOntoTheWeek() {
        // ₵900.00 monthly rent = 900 x 12 / 52 = ₵207.69 a week.
        let rent = BudgetEngine.CommitmentInput(id: UUID(), label: "Rent",
                                                amount: Money(minorUnits: 90_000),
                                                occurrencesPerYear: 12)
        #expect(BudgetEngine.weeklyCommitted([rent]).minorUnits == 20_769)

        // A weekly commitment is already weekly.
        let weekly = BudgetEngine.CommitmentInput(id: UUID(), label: "Transport",
                                                  amount: Money(minorUnits: 5_000),
                                                  occurrencesPerYear: 52)
        #expect(BudgetEngine.weeklyCommitted([weekly]).minorUnits == 5_000)

        // A yearly insurance renewal of ₵520.00 is ₵10.00 a week.
        let yearly = BudgetEngine.CommitmentInput(id: UUID(), label: "Insurance",
                                                  amount: Money(minorUnits: 52_000),
                                                  occurrencesPerYear: 1)
        #expect(BudgetEngine.weeklyCommitted([yearly]).minorUnits == 1_000)
    }

    @Test func commitmentsWithNoCadenceContributeNothingRatherThanCrashing() {
        let broken = BudgetEngine.CommitmentInput(id: UUID(), label: "?",
                                                  amount: Money(minorUnits: 1_000),
                                                  occurrencesPerYear: 0)
        #expect(BudgetEngine.weeklyCommitted([broken]).isZero)
        #expect(BudgetEngine.weeklyCommitted([]).isZero)
    }

    // MARK: - Free to spend

    @Test func freeToSpendFollowsTheSpecExactly() {
        // Income 807.69, rent 900/month (207.69/wk), investment 400/month (92.31/wk),
        // goals 50.00, already spent 210.00
        // 807.69 − 300.00 − 50.00 − 210.00 = 247.69
        let result = BudgetEngine.freeToSpend(
            expectedIncomeThisWeek: Money(minorUnits: 80_769),
            commitments: [
                .init(id: UUID(), label: "Rent", amount: Money(minorUnits: 90_000),
                      occurrencesPerYear: 12),
                .init(id: UUID(), label: "Investment", amount: Money(minorUnits: 40_000),
                      occurrencesPerYear: 12),
            ],
            goalAllocationsThisWeek: Money(minorUnits: 5_000),
            alreadySpentThisWeek: Money(minorUnits: 21_000)
        )
        #expect(result.committedOutflows.minorUnits == 30_000)
        #expect(result.amount.minorUnits == 24_769)
        #expect(!result.isNegative)
    }

    @Test func freeToSpendGoesNegativeRatherThanHidingIt() {
        let result = BudgetEngine.freeToSpend(
            expectedIncomeThisWeek: Money(minorUnits: 10_000),
            commitments: [.init(id: UUID(), label: "Rent", amount: Money(minorUnits: 90_000),
                                occurrencesPerYear: 12)],
            goalAllocationsThisWeek: .zero,
            alreadySpentThisWeek: Money(minorUnits: 5_000)
        )
        #expect(result.isNegative)
        #expect(result.amount.minorUnits == -15_769)
    }

    // MARK: - Income expectation

    @Test func medianNotMeanSoOneGoodMonthDoesNotInflateEverything() {
        // 100, 120, 110, 900 — the mean is 307.50, the median is 115.00.
        let weeks = [10_000, 12_000, 11_000, 90_000].map(Money.init(minorUnits:))
        #expect(BudgetEngine.medianWeeklyIncome(trailingWeeks: weeks).minorUnits == 11_500)
    }

    @Test func medianOfAnOddCountIsTheMiddleValue() {
        let weeks = [10_000, 30_000, 20_000].map(Money.init(minorUnits:))
        #expect(BudgetEngine.medianWeeklyIncome(trailingWeeks: weeks).minorUnits == 20_000)
    }

    @Test func medianOfAnEmptyHistoryIsZero() {
        #expect(BudgetEngine.medianWeeklyIncome(trailingWeeks: []).isZero)
    }

    @Test func aMonthlySalarySpreadsAcrossTheYear() {
        // ₵3,500.00 a month = 3,500 x 12 / 52 = ₵807.69 a week.
        #expect(BudgetEngine.weeklyFromMonthly(Money(minorUnits: 350_000)).minorUnits == 80_769)
    }

    @Test func salaryAndIrregularIncomeCombine() {
        // A monthly median would read zero in three weeks out of four; spreading fixes it.
        let result = BudgetEngine.expectedWeeklyIncome(
            monthlySalary: Money(minorUnits: 350_000),
            irregularTrailingWeeks: [Money.zero, Money(minorUnits: 20_000), Money.zero]
        )
        #expect(result.minorUnits == 80_769)  // salary + median(0, 0, 200) = 807.69 + 0
    }
}
