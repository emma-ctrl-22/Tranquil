import Testing
import Foundation
@testable import MyFinances

/// Every expected value below was worked out by hand. None of these assert that a
/// function equals itself.
struct MoneyTests {

    // MARK: - Arithmetic

    @Test func addsAndSubtractsInMinorUnits() {
        let a = Money(minorUnits: 1_250)   // 12.50
        let b = Money(minorUnits: 375)     // 3.75
        #expect((a + b).minorUnits == 1_625)   // 16.25
        #expect((a - b).minorUnits == 875)     // 8.75
        #expect((b - a).minorUnits == -875)
        #expect((a * 3).minorUnits == 3_750)
        #expect((-a).minorUnits == -1_250)
    }

    @Test func sumsAndClamps() {
        let amounts = [Money(minorUnits: 500), Money(minorUnits: 250), Money(minorUnits: -100)]
        #expect(Money.sum(amounts).minorUnits == 650)
        #expect(Money.sum([]).isZero)
        #expect(Money(minorUnits: -40).clampedToZero == .zero)
        #expect(Money(minorUnits: 40).clampedToZero.minorUnits == 40)
    }

    // MARK: - Banker's rounding

    @Test func roundsHalfToEven() {
        // 0.5 -> 0, 1.5 -> 2, 2.5 -> 2, 3.5 -> 4, -0.5 -> 0, -2.5 -> -2
        #expect(Money.roundBankers(Decimal(string: "0.5")!) == 0)
        #expect(Money.roundBankers(Decimal(string: "1.5")!) == 2)
        #expect(Money.roundBankers(Decimal(string: "2.5")!) == 2)
        #expect(Money.roundBankers(Decimal(string: "3.5")!) == 4)
        #expect(Money.roundBankers(Decimal(string: "-0.5")!) == 0)
        #expect(Money.roundBankers(Decimal(string: "-2.5")!) == -2)
        #expect(Money.roundBankers(Decimal(string: "2.4999")!) == 2)
    }

    @Test func scalesByRateRoundingOnce() {
        // 25% tax reserve on 1,234.57 = 30,864.25 minor units -> banker's -> 30,864
        let gross = Money(minorUnits: 123_457)
        let reserved = gross.scaled(by: Decimal(string: "0.25")!)
        #expect(reserved.minorUnits == 30_864)

        // 7/31 proration of a 31.00 monthly envelope = 3,100 * 7/31 = 700 exactly
        let monthly = Money(minorUnits: 3_100)
        #expect(monthly.scaled(by: Decimal(7) / Decimal(31)).minorUnits == 700)

        // Exactly-half case lands on even: 5 * 0.5 = 2.5 -> 2
        #expect(Money(minorUnits: 5).scaled(by: Decimal(string: "0.5")!).minorUnits == 2)
        #expect(Money(minorUnits: 7).scaled(by: Decimal(string: "0.5")!).minorUnits == 4)  // 3.5 -> 4
    }

    // MARK: - Splitting

    @Test func splitDistributesRemainderAndLosesNothing() {
        // 10.00 / 3 = 3.34, 3.33, 3.33
        let parts = Money(minorUnits: 1_000).split(into: 3)
        #expect(parts.map(\.minorUnits) == [334, 333, 333])
        #expect(Money.sum(parts).minorUnits == 1_000)
    }

    @Test func splitHandlesExactDivisionAndSinglePart() {
        #expect(Money(minorUnits: 900).split(into: 3).map(\.minorUnits) == [300, 300, 300])
        #expect(Money(minorUnits: 7).split(into: 1).map(\.minorUnits) == [7])
        #expect(Money.zero.split(into: 4).map(\.minorUnits) == [0, 0, 0, 0])
    }

    @Test func splitHandlesMorePartsThanUnits() {
        // 2 pesewas across 5 parts: two parts get 1, three get 0.
        let parts = Money(minorUnits: 2).split(into: 5)
        #expect(parts.map(\.minorUnits) == [1, 1, 0, 0, 0])
        #expect(Money.sum(parts).minorUnits == 2)
    }

    @Test func splitPreservesSign() {
        let parts = Money(minorUnits: -1_000).split(into: 3)
        #expect(parts.map(\.minorUnits) == [-334, -333, -333])
        #expect(Money.sum(parts).minorUnits == -1_000)
    }

    // MARK: - Proportional allocation

    @Test func allocatesWindfallSplitExactly() {
        // ADVISOR_RULES §4a defaults: 40 / 25 / 20 / 15 of net usable 1,000.01
        let net = Money(minorUnits: 100_001)
        let weights = [Decimal(40), Decimal(25), Decimal(20), Decimal(15)]
        let slices = net.allocate(by: weights)
        // Exact shares: 40000.4, 25000.25, 20000.2, 15000.15
        // Floors:       40000,   25000,     20000,   15000    (sum 100000, 1 leftover)
        // Largest fraction is .4 -> first slice.
        #expect(slices.map(\.minorUnits) == [40_001, 25_000, 20_000, 15_000])
        #expect(Money.sum(slices) == net)
    }

    @Test func allocateHandlesZeroAndEqualWeights() {
        let total = Money(minorUnits: 100)
        #expect(total.allocate(by: [Decimal(0), Decimal(0)]).map(\.minorUnits) == [0, 0])
        #expect(total.allocate(by: [Decimal(1), Decimal(0)]).map(\.minorUnits) == [100, 0])
        // 100 / 3 equal weights: largest-remainder gives the extra unit to the first tie.
        let thirds = total.allocate(by: [Decimal(1), Decimal(1), Decimal(1)])
        #expect(thirds.map(\.minorUnits) == [34, 33, 33])
        #expect(Money.sum(thirds) == total)
    }

    @Test func allocateIsDeterministicAcrossRuns() {
        let total = Money(minorUnits: 1_000_003)
        let weights = [Decimal(1), Decimal(1), Decimal(1), Decimal(1), Decimal(1), Decimal(1), Decimal(1)]
        let first = total.allocate(by: weights).map(\.minorUnits)
        let second = total.allocate(by: weights).map(\.minorUnits)
        #expect(first == second)
        #expect(first.reduce(0, +) == 1_000_003)
    }

    @Test func moneyIsNeverLostAcrossManySplits() {
        // Brute force: no split of any of these amounts may lose or create a pesewa.
        for total in stride(from: 0, through: 2_000, by: 7) {
            for parts in 1...13 {
                let pieces = Money(minorUnits: total).split(into: parts)
                #expect(Money.sum(pieces).minorUnits == total)
                #expect(pieces.count == parts)
            }
        }
    }

    // MARK: - Ratios

    @Test func ratioIsNilOnZeroDenominator() {
        #expect(Money(minorUnits: 100).ratio(to: .zero) == nil)
        #expect(Money(minorUnits: 300).ratio(to: Money(minorUnits: 1_200)) == Decimal(string: "0.25"))
    }
}
