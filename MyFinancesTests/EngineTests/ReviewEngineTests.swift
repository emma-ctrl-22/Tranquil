import Testing
import Foundation
@testable import MyFinances

struct ReviewEngineTests {
    private let formatter = MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB"))

    private func envelope(_ name: String, budget: Int, spent: Int) -> ReviewEngine.EnvelopeLine {
        ReviewEngine.EnvelopeLine(id: UUID(), name: name,
                                  budget: Money(minorUnits: budget),
                                  spent: Money(minorUnits: spent))
    }

    private func expense(_ label: String, _ amount: Int) -> ReviewEngine.ExpenseLine {
        ReviewEngine.ExpenseLine(id: UUID(), label: label,
                                 amount: Money(minorUnits: amount),
                                 date: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Weekly

    @Test func theWeeklyPicksTheBiggestThreeExpenses() {
        let review = ReviewEngine.weekly(
            weekStart: Date(timeIntervalSince1970: 0),
            envelopes: [],
            expenses: [expense("Lunch", 1_500), expense("Rent", 90_000),
                       expense("Data", 4_000), expense("Trotro", 500)],
            totalIncome: .zero, streak: 5, daysLogged: 7, needsReviewCount: 0, goalsMoved: []
        )
        #expect(review.biggestExpenses.map(\.label) == ["Rent", "Data", "Lunch"])
        #expect(review.totalSpent.minorUnits == 96_000)
    }

    @Test func envelopeVarianceIsSignedCorrectly() {
        let under = envelope("Lunch", budget: 12_000, spent: 9_000)
        let over = envelope("Misc", budget: 9_000, spent: 14_000)
        #expect(under.variance.minorUnits == 3_000)
        #expect(!under.isOver)
        #expect(over.variance.minorUnits == -5_000)
        #expect(over.isOver)
    }

    @Test func exactlyOnBudgetIsNotOver() {
        let exact = envelope("Lunch", budget: 12_000, spent: 12_000)
        #expect(!exact.isOver)
        #expect(exact.variance.isZero)
    }

    // MARK: - The one suggestion

    @Test func poorLoggingIsTheFirstThingRaised() {
        // Nothing downstream is trustworthy if the input is missing.
        let suggestion = ReviewEngine.suggestion(
            envelopes: [envelope("Misc", budget: 9_000, spent: 30_000)],
            daysLogged: 2, needsReviewCount: 0
        )
        #expect(suggestion.contains("2 of 7"))
    }

    @Test func theWorstEnvelopeIsNamedWhenLoggingIsFine() {
        let suggestion = ReviewEngine.suggestion(
            envelopes: [envelope("Lunch", budget: 12_000, spent: 13_000),
                        envelope("Misc", budget: 9_000, spent: 30_000)],
            daysLogged: 7, needsReviewCount: 0
        )
        #expect(suggestion.contains("Misc"))
    }

    @Test func aCleanWeekSaysSoWithoutPraise() {
        let suggestion = ReviewEngine.suggestion(
            envelopes: [envelope("Lunch", budget: 12_000, spent: 9_000)],
            daysLogged: 7, needsReviewCount: 0
        )
        #expect(suggestion.contains("Nothing needs changing"))
        #expect(!suggestion.contains("!"))
        #expect(!suggestion.lowercased().contains("well done"))
        #expect(!suggestion.lowercased().contains("great"))
    }

    @Test func onlyOneSuggestionIsEverReturned() {
        // Several things are wrong at once; it still returns a single line.
        let suggestion = ReviewEngine.suggestion(
            envelopes: [envelope("Lunch", budget: 12_000, spent: 20_000),
                        envelope("Misc", budget: 9_000, spent: 30_000)],
            daysLogged: 2, needsReviewCount: 9
        )
        #expect(!suggestion.contains("\\n"))
    }

    // MARK: - Savings rate

    @Test func savingsRateIsIncomeLessSpendOverIncome() {
        // ₵3,500 in, ₵2,800 out → 20%.
        #expect(ReviewEngine.savingsRate(income: Money(minorUnits: 350_000),
                                         spend: Money(minorUnits: 280_000))
                == Decimal(string: "0.2"))
    }

    @Test func spendingMoreThanYouEarnedGivesANegativeRateNotZero() {
        let rate = ReviewEngine.savingsRate(income: Money(minorUnits: 100_000),
                                            spend: Money(minorUnits: 150_000))
        #expect(rate == Decimal(string: "-0.5"))
    }

    @Test func noIncomeMeansNoSavingsRateRatherThanDivisionByZero() {
        #expect(ReviewEngine.savingsRate(income: .zero, spend: Money(minorUnits: 5_000)) == nil)
    }

    // MARK: - Monthly

    private func monthly(
        stageNow: LadderStage = .twoWeekBuffer, stagePrevious: LadderStage? = nil,
        debtCleared: Int = 0, income: Int = 350_000, spend: Int = 280_000
    ) -> ReviewEngine.Monthly {
        ReviewEngine.Monthly(
            monthStart: Date(timeIntervalSince1970: 1_789_000_000),
            netWorth: Money(minorUnits: 500_000),
            netWorthChange: Money(minorUnits: 40_000),
            income: Money(minorUnits: income), spend: Money(minorUnits: spend),
            savingsRate: ReviewEngine.savingsRate(income: Money(minorUnits: income),
                                                  spend: Money(minorUnits: spend)),
            debtCleared: Money(minorUnits: debtCleared),
            stageNow: stageNow, stagePrevious: stagePrevious,
            score: LadderEngine.Score(components: [
                .init(name: "Runway", earned: 12, available: 30, detail: "2.4 months")
            ]),
            overspendTotal: Money(minorUnits: 4_000),
            sinkingFundsOnTrack: 2, sinkingFundsTotal: 4,
            overrideCount: 1, overrideCost: Money(minorUnits: 20_000)
        )
    }

    @Test func aLadderMoveIsTheHeadlineWhenItHappens() {
        let headline = ReviewEngine.headlineFigure(
            monthly(stageNow: .nothingLate, stagePrevious: .twoWeekBuffer),
            formatter: formatter
        )
        #expect(headline.0 == "Ladder stage")
        #expect(headline.1 == "No obligation is late")
    }

    @Test func debtClearedOutranksTheSavingsRate() {
        let headline = ReviewEngine.headlineFigure(monthly(debtCleared: 50_000),
                                                   formatter: formatter)
        #expect(headline.0 == "Debt cleared")
    }

    @Test func theSavingsRateLeadsAnOtherwiseQuietMonth() {
        let headline = ReviewEngine.headlineFigure(monthly(), formatter: formatter)
        #expect(headline.0 == "Savings rate")
        #expect(headline.1 == "20%")
    }

    @Test func aMonthWithNothingToReportFallsBackToNetWorth() {
        let headline = ReviewEngine.headlineFigure(
            monthly(income: 100_000, spend: 150_000), formatter: formatter
        )
        #expect(headline.0 == "Net worth")
    }

    // MARK: - Copy as text

    @Test func theWeeklyTextCarriesTheNumbersAndKeepsTheVoice() {
        let review = ReviewEngine.weekly(
            weekStart: Date(timeIntervalSince1970: 1_789_000_000),
            envelopes: [envelope("Lunch", budget: 12_000, spent: 9_000)],
            expenses: [expense("Rent", 90_000)],
            totalIncome: Money(minorUnits: 350_000), streak: 5, daysLogged: 7,
            needsReviewCount: 0, goalsMoved: []
        )
        let text = ReviewEngine.weeklyText(review, formatter: formatter)
        #expect(text.contains("₵900.00"))
        #expect(text.contains("Lunch"))
        #expect(text.contains("streak 5"))
        #expect(!text.contains("!"))
    }

    @Test func theMonthlyTextAlwaysShowsTheScoreBreakdown() {
        let text = ReviewEngine.monthlyText(monthly(), formatter: formatter)
        // The score is never a mystery number, in the copy either.
        #expect(text.contains("Runway: 12/30"))
        #expect(text.contains("2.4 months"))
        #expect(text.contains("Advisor overrides: 1"))
        #expect(!text.contains("!"))
    }

    @Test func anEmptyWeekProducesAReviewRatherThanNothing() {
        let review = ReviewEngine.weekly(
            weekStart: Date(timeIntervalSince1970: 0), envelopes: [], expenses: [],
            totalIncome: .zero, streak: 0, daysLogged: 0, needsReviewCount: 0, goalsMoved: []
        )
        #expect(review.totalSpent.isZero)
        #expect(review.biggestExpenses.isEmpty)
        #expect(!review.suggestion.isEmpty)
        #expect(!ReviewEngine.weeklyText(review, formatter: formatter).isEmpty)
    }
}
