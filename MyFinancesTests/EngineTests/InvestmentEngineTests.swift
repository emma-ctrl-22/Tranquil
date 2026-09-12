import Testing
import Foundation
@testable import MyFinances

struct InvestmentEngineTests {
    private let utc = TimeZone(identifier: "UTC")!
    private var calendar: FinancialCalendar {
        FinancialCalendar(timeZone: utc, now: { Date(timeIntervalSince1970: 1_789_000_000) })
    }

    private func holding(
        contributed: Int, value: Int? = nil, valuedDaysAgo: Int? = nil
    ) -> InvestmentEngine.Holding {
        InvestmentEngine.Holding(
            accountID: UUID(), name: "MFund", colorHex: "#000000",
            contributed: Money(minorUnits: contributed),
            currentValue: value.map(Money.init(minorUnits:)),
            valuedOn: valuedDaysAgo.map { calendar.addDays(-$0, to: calendar.today()) }
        )
    }

    @Test func gainIsValueLessWhatYouPutIn() {
        let up = holding(contributed: 300_000, value: 345_000, valuedDaysAgo: 1)
        #expect(up.gain?.minorUnits == 45_000)
        #expect(up.gainFraction == Decimal(string: "0.15"))

        let down = holding(contributed: 300_000, value: 270_000, valuedDaysAgo: 1)
        #expect(down.gain?.minorUnits == -30_000)
    }

    @Test func withNoValuationThereIsNoGainRatherThanZero() {
        // The app must not imply a holding is flat just because you have not checked it.
        let unvalued = holding(contributed: 300_000)
        #expect(unvalued.currentValue == nil)
        #expect(unvalued.gain == nil)
        #expect(unvalued.gainFraction == nil)
    }

    @Test func aValuationGoesStaleAfterAMonth() {
        let today = calendar.today()
        #expect(!holding(contributed: 300_000, value: 300_000, valuedDaysAgo: 29)
            .needsValuation(today: today, calendar: calendar))
        #expect(holding(contributed: 300_000, value: 300_000, valuedDaysAgo: 30)
            .needsValuation(today: today, calendar: calendar))
    }

    @Test func aHoldingWithMoneyInItButNoValuationIsAsked() {
        #expect(holding(contributed: 300_000)
            .needsValuation(today: calendar.today(), calendar: calendar))
        // An empty account is not worth nagging about.
        #expect(!holding(contributed: 0)
            .needsValuation(today: calendar.today(), calendar: calendar))
    }

    @Test func theTotalFallsBackToContributedForUnvaluedHoldings() {
        // Treating an unvalued holding as zero would understate the total badly.
        let summary = InvestmentEngine.Summary(holdings: [
            holding(contributed: 300_000, value: 345_000, valuedDaysAgo: 1),
            holding(contributed: 200_000),
        ])
        #expect(summary.totalContributed.minorUnits == 500_000)
        #expect(summary.totalValue.minorUnits == 545_000)
        #expect(summary.totalGain.minorUnits == 45_000)
        #expect(summary.hasAnyValuation)
    }

    @Test func anEmptyPortfolioIsAllZerosWithoutCrashing() {
        let summary = InvestmentEngine.Summary(holdings: [])
        #expect(summary.totalContributed.isZero)
        #expect(summary.totalValue.isZero)
        #expect(!summary.hasAnyValuation)
        #expect(summary.needingValuation(today: calendar.today(), calendar: calendar).isEmpty)
    }

    @Test func contributionStreakCountsMonthsNotAmounts() {
        // Consistency beats size: this never looks at how much went in.
        let today = calendar.today()
        let months = Set((0..<5).map {
            calendar.startOfMonth(containing: calendar.addMonths(-$0, to: today))
        })
        #expect(InvestmentEngine.contributionStreak(
            contributionMonths: months, months: 12, today: today, calendar: calendar) == 5)
        #expect(InvestmentEngine.contributionStreak(
            contributionMonths: [], months: 12, today: today, calendar: calendar) == 0)
    }

    @Test func contributionRateIsAShareOfIncome() {
        #expect(InvestmentEngine.contributionRate(contributed: Money(minorUnits: 480_000),
                                                  netIncome: Money(minorUnits: 4_200_000))
                == Decimal(string: "0.114285714285714285714285714285714285714"))
        // No income means no rate, not a division by zero.
        #expect(InvestmentEngine.contributionRate(contributed: Money(minorUnits: 100),
                                                  netIncome: .zero) == nil)
    }
}
