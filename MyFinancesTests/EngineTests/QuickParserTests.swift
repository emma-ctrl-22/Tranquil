import Testing
import Foundation
@testable import MyFinances

/// The parser is the three-second promise. Every example from the spec is here.
struct QuickParserTests {
    private let trotroID = UUID()
    private let lunchID = UUID()
    private let dataID = UUID()
    private let salaryID = UUID()
    private let momoID = UUID()
    private let bankID = UUID()

    private var parser: QuickParser {
        QuickParser(
            formatter: MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB")),
            vocabulary: QuickParser.Vocabulary(
                categories: [
                    .init(id: trotroID, name: "Trotro", aliases: ["bus"]),
                    .init(id: lunchID, name: "Lunch"),
                    .init(id: dataID, name: "Data"),
                    .init(id: salaryID, name: "Salary"),
                ],
                accounts: [
                    .init(id: momoID, name: "MTN MoMo", aliases: ["momo"]),
                    .init(id: bankID, name: "GCB Current", aliases: ["bank", "gcb"]),
                ]
            )
        )
    }

    // MARK: - The spec's own examples

    @Test func parsesTrotroFive() {
        let result = parser.parse("trotro 5")
        #expect(result.amount == Money(minorUnits: 500))
        #expect(result.kind == .expense)
        #expect(result.categoryID == trotroID)
        #expect(result.note == nil)
        #expect(result.isComplete)
    }

    @Test func parsesAmountCategoryAccount() {
        let result = parser.parse("15 lunch momo")
        #expect(result.amount == Money(minorUnits: 1_500))
        #expect(result.categoryID == lunchID)
        #expect(result.accountID == momoID)
        #expect(result.kind == .expense)
        #expect(result.note == nil)
    }

    @Test func parsesExplicitNegativeAsExpense() {
        let result = parser.parse("-40 data")
        #expect(result.amount == Money(minorUnits: 4_000))
        #expect(result.kind == .expense)
        #expect(result.categoryID == dataID)
        // The amount is stored positive; direction lives in kind.
        #expect(!result.amount!.isNegative)
    }

    @Test func parsesSalaryAsIncome() {
        let result = parser.parse("5000 salary")
        #expect(result.amount == Money(minorUnits: 500_000))
        #expect(result.kind == .income)
        #expect(result.categoryID == salaryID)
    }

    // MARK: - Direction

    @Test func explicitPlusMeansIncome() {
        #expect(parser.parse("+250 lunch").kind == .income)
    }

    @Test func explicitSignBeatsAnIncomeKeyword() {
        // "-500 refund" is a refund you paid out. The typed sign is never overridden.
        let result = parser.parse("-500 refund")
        #expect(result.kind == .expense)
    }

    @Test func incomeKeywordInTheNoteAlsoCounts() {
        let result = parser.parse("300 paid by kofi")
        #expect(result.kind == .income)
        #expect(result.amount == Money(minorUnits: 30_000))
    }

    @Test func unknownWordsDoNotFlipDirection() {
        let result = parser.parse("12 kenkey")
        #expect(result.kind == .expense)
        #expect(result.note == "kenkey")
    }

    // MARK: - Matching

    @Test func aliasesMatch() {
        #expect(parser.parse("5 bus").categoryID == trotroID)
        #expect(parser.parse("5 lunch gcb").accountID == bankID)
    }

    @Test func multiWordAccountNamesMatch() {
        let result = parser.parse("20 lunch mtn momo")
        #expect(result.accountID == momoID)
        #expect(result.categoryID == lunchID)
        #expect(result.note == nil)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(parser.parse("5 TROTRO").categoryID == trotroID)
        #expect(parser.parse("5 Lunch MoMo").accountID == momoID)
    }

    @Test func orderDoesNotMatter() {
        let a = parser.parse("trotro 5 momo")
        let b = parser.parse("momo trotro 5")
        #expect(a.amount == b.amount)
        #expect(a.categoryID == b.categoryID)
        #expect(a.accountID == b.accountID)
    }

    @Test func leftoverWordsBecomeTheNote() {
        let result = parser.parse("25 lunch with ama")
        #expect(result.categoryID == lunchID)
        #expect(result.note == "with ama")
    }

    @Test func aTermIsConsumedOnceSoItCannotBeClaimedTwice() {
        let result = parser.parse("5 trotro")
        #expect(result.categoryID == trotroID)
        #expect(result.accountID == nil)
        #expect(result.note == nil)
    }

    // MARK: - Amounts

    @Test func decimalsAndGroupingParse() {
        #expect(parser.parse("12.50 lunch").amount == Money(minorUnits: 1_250))
        #expect(parser.parse("1,200 rent").amount == Money(minorUnits: 120_000))
    }

    @Test func theFirstNumberIsTheAmount() {
        // "2 waters" — the 2 is the amount, "waters" stays as the note.
        let result = parser.parse("2 waters")
        #expect(result.amount == Money(minorUnits: 200))
        #expect(result.note == "waters")
    }

    // MARK: - Incomplete input

    @Test func emptyInputYieldsNothing() {
        let result = parser.parse("")
        #expect(result.amount == nil)
        #expect(!result.isComplete)
        #expect(result.note == nil)
    }

    @Test func whitespaceOnlyYieldsNothing() {
        #expect(!parser.parse("    ").isComplete)
    }

    @Test func wordsWithNoAmountAreIncomplete() {
        let result = parser.parse("lunch momo")
        #expect(result.amount == nil)
        #expect(!result.isComplete)
        // It still recognises what it can, so the preview can show its work.
        #expect(result.categoryID == lunchID)
        #expect(result.accountID == momoID)
    }

    @Test func zeroIsNotACompleteEntry() {
        let result = parser.parse("0 lunch")
        #expect(result.amount == Money.zero)
        #expect(!result.isComplete)
    }

    @Test func anUnclassifiedLineIsFlagged() {
        // "I spent something, not sure what" — lands in Miscellaneous for review.
        let result = parser.parse("30")
        #expect(result.isComplete)
        #expect(result.isUnclassified)
    }

    @Test func aClassifiedLineIsNotFlagged() {
        #expect(!parser.parse("30 lunch").isUnclassified)
    }
}
