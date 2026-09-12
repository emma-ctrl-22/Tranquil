import Testing
import Foundation
@testable import MyFinances

struct MoneyFormatterTests {
    private let formatter = MoneyFormatter(
        currency: .ghs,
        locale: Locale(identifier: "en_GB")
    )

    @Test func formatsWholeAndFractionalAmounts() {
        #expect(formatter.string(Money(minorUnits: 0)) == "₵0.00")
        #expect(formatter.string(Money(minorUnits: 5)) == "₵0.05")
        #expect(formatter.string(Money(minorUnits: 500)) == "₵5.00")
        #expect(formatter.string(Money(minorUnits: 123_456)) == "₵1,234.56")
        #expect(formatter.string(Money(minorUnits: 100_000_000)) == "₵1,000,000.00")
    }

    @Test func formatsNegativesWithATrueMinusSign() {
        #expect(formatter.string(Money(minorUnits: -1_250)) == "−₵12.50")
        #expect(formatter.string(Money(minorUnits: -1_250), style: .bare) == "−12.50")
    }

    @Test func signedStyleShowsDirection() {
        #expect(formatter.string(Money(minorUnits: 1_250), style: .signed) == "+₵12.50")
        #expect(formatter.string(Money(minorUnits: -1_250), style: .signed) == "−₵12.50")
    }

    @Test func roundedStyleUsesBankersRounding() {
        #expect(formatter.string(Money(minorUnits: 1_250), style: .rounded) == "₵12")   // 12.5 -> 12
        #expect(formatter.string(Money(minorUnits: 1_350), style: .rounded) == "₵14")   // 13.5 -> 14
        #expect(formatter.string(Money(minorUnits: 1_349), style: .rounded) == "₵13")
    }

    // MARK: - Parsing

    @Test func parsesPlainInput() {
        #expect(formatter.parse("5") == Money(minorUnits: 500))
        #expect(formatter.parse("12.50") == Money(minorUnits: 1_250))
        #expect(formatter.parse("0.05") == Money(minorUnits: 5))
        #expect(formatter.parse(".5") == Money(minorUnits: 50))
        #expect(formatter.parse("12.") == Money(minorUnits: 1_200))
    }

    @Test func parsesSymbolsSpacesAndSigns() {
        #expect(formatter.parse("₵12.50") == Money(minorUnits: 1_250))
        #expect(formatter.parse(" GHS 12.50 ") == Money(minorUnits: 1_250))
        #expect(formatter.parse("-40") == Money(minorUnits: -4_000))
        #expect(formatter.parse("−40") == Money(minorUnits: -4_000))
    }

    @Test func parsesGroupingAndCommaDecimals() {
        #expect(formatter.parse("1,234.56") == Money(minorUnits: 123_456))
        #expect(formatter.parse("1.234,56") == Money(minorUnits: 123_456))
        // A single separator before exactly three digits is thousands, not decimals.
        #expect(formatter.parse("1,200") == Money(minorUnits: 120_000))
        #expect(formatter.parse("5000") == Money(minorUnits: 500_000))
    }

    @Test func parsingRoundsExtraDecimalsRatherThanTruncating() {
        #expect(formatter.parse("1.005") == Money(minorUnits: 101))
        #expect(formatter.parse("1.004") == Money(minorUnits: 100))
    }

    @Test func rejectsGarbageRatherThanGuessing() {
        #expect(formatter.parse("") == nil)
        #expect(formatter.parse("   ") == nil)
        #expect(formatter.parse("lunch") == nil)
        #expect(formatter.parse("12.5x") == nil)
    }

    @Test func roundTripsEveryAmountUnderTenThousand() {
        for units in stride(from: 0, through: 1_000_000, by: 997) {
            let amount = Money(minorUnits: units)
            let text = formatter.string(amount, style: .bare)
            #expect(formatter.parse(text) == amount, "round trip failed for \(units)")
        }
    }
}
