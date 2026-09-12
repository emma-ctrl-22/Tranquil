import Testing
import Foundation
@testable import MyFinances

struct ExportServiceTests {
    private let formatter = MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB"))
    private let calendar = FinancialCalendar(timeZone: TimeZone(identifier: "UTC")!,
                                             now: { Date(timeIntervalSince1970: 1_789_000_000) })

    // MARK: - CSV writing

    @Test func plainFieldsAreNotQuoted() {
        #expect(ExportService.csvField("lunch") == "lunch")
        #expect(ExportService.csvField("12.50") == "12.50")
    }

    @Test func awkwardFieldsAreQuotedAndEscaped() {
        #expect(ExportService.csvField("lunch, with ama") == "\"lunch, with ama\"")
        #expect(ExportService.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(ExportService.csvField("two\nlines") == "\"two\nlines\"")
    }

    // MARK: - CSV reading

    @Test func quotedFieldsWithCommasSurviveTheRoundTrip() {
        let text = ExportService.csvRow(["2026-09-12", "12.50", "lunch, with ama"])
        let rows = ExportService.parseCSV(text)
        #expect(rows.count == 1)
        #expect(rows[0] == ["2026-09-12", "12.50", "lunch, with ama"])
    }

    @Test func escapedQuotesSurviveTheRoundTrip() {
        let original = ["note", "he said \"yes\""]
        let rows = ExportService.parseCSV(ExportService.csvRow(original))
        #expect(rows[0] == original)
    }

    @Test func embeddedNewlinesDoNotSplitARow() {
        let rows = ExportService.parseCSV("a,\"two\nlines\",c")
        #expect(rows.count == 1)
        #expect(rows[0] == ["a", "two\nlines", "c"])
    }

    @Test func blankLinesAreIgnored() {
        let rows = ExportService.parseCSV("a,b\n\nc,d\n")
        #expect(rows.count == 2)
    }

    @Test func everyLineEndingIsUnderstood() {
        // Swift treats CRLF as a single Character; all three shapes must split a row.
        for ending in ["\n", "\r\n", "\r"] {
            let rows = ExportService.parseCSV("a,b\(ending)c,d\(ending)")
            #expect(rows.count == 2, "failed for \(ending.debugDescription)")
            #expect(rows.last == ["c", "d"], "failed for \(ending.debugDescription)")
        }
    }

    // MARK: - Column mapping

    @Test func headersAreGuessedFromCommonNames() {
        let mapping = ExportService.suggestMapping(
            headers: ["Date", "Description", "Amount", "Category"]
        )
        #expect(mapping.date == 0)
        #expect(mapping.note == 1)
        #expect(mapping.amount == 2)
        #expect(mapping.category == 3)
        #expect(mapping.isUsable)
    }

    @Test func aMappingWithoutDateAndAmountIsNotUsable() {
        let mapping = ExportService.suggestMapping(headers: ["Thing", "Whatever"])
        #expect(!mapping.isUsable)
    }

    // MARK: - Date parsing

    @Test func commonSpreadsheetDateShapesAreAccepted() {
        #expect(ExportService.parseDate("2026-09-12") != nil)
        #expect(ExportService.parseDate("12/09/2026") != nil)
        #expect(ExportService.parseDate("12-09-2026") != nil)
        #expect(ExportService.parseDate("12 Sep 2026") != nil)
        #expect(ExportService.parseDate("not a date") == nil)
        #expect(ExportService.parseDate("") == nil)
    }

    // MARK: - Import

    private func rows(_ csv: String) -> [[String]] { ExportService.parseCSV(csv) }

    @Test func aWellFormedFileImportsCleanly() {
        let csv = """
        Date,Amount,Category,Description
        2026-09-10,12.50,Lunch,with ama
        2026-09-11,5.00,Trotro,
        """
        let mapping = ExportService.suggestMapping(headers: ["Date", "Amount", "Category",
                                                             "Description"])
        let result = ExportService.parseRows(rows(csv), mapping: mapping, hasHeader: true,
                                             formatter: formatter, calendar: calendar)
        #expect(result.rows.count == 2)
        #expect(result.skipped.isEmpty)
        #expect(result.rows[0].amount.minorUnits == 1_250)
        #expect(result.rows[0].categoryName == "Lunch")
        #expect(result.rows[1].note == nil)
    }

    @Test func aNegativeAmountBecomesAnExpenseStoredPositive() {
        // Direction lives in `kind`; the database never holds a negative amount.
        let csv = "Date,Amount\n2026-09-10,-40.00"
        let mapping = ExportService.suggestMapping(headers: ["Date", "Amount"])
        let result = ExportService.parseRows(rows(csv), mapping: mapping, hasHeader: true,
                                             formatter: formatter, calendar: calendar)
        #expect(result.rows[0].kind == .expense)
        #expect(result.rows[0].amount.minorUnits == 4_000)
        #expect(!result.rows[0].amount.isNegative)
    }

    @Test func bankStyleKindWordsAreUnderstood() {
        let csv = """
        Date,Amount,Type
        2026-09-10,40.00,debit
        2026-09-11,90.00,credit
        """
        let mapping = ExportService.suggestMapping(headers: ["Date", "Amount", "Type"])
        let result = ExportService.parseRows(rows(csv), mapping: mapping, hasHeader: true,
                                             formatter: formatter, calendar: calendar)
        #expect(result.rows[0].kind == .expense)
        #expect(result.rows[1].kind == .income)
    }

    @Test func unreadableRowsAreSkippedAndReportedNeverGuessed() {
        // A silently mangled import is worse than a failed one.
        let csv = """
        Date,Amount
        2026-09-10,12.50
        not-a-date,5.00
        2026-09-12,rubbish
        """
        let mapping = ExportService.suggestMapping(headers: ["Date", "Amount"])
        let result = ExportService.parseRows(rows(csv), mapping: mapping, hasHeader: true,
                                             formatter: formatter, calendar: calendar)
        #expect(result.rows.count == 1)
        #expect(result.skipped.count == 2)
        #expect(result.skipped[0].contains("Line 3"))
        #expect(result.skipped[1].contains("Line 4"))
    }

    @Test func anUnusableMappingImportsNothingAndSaysWhy() {
        let result = ExportService.parseRows(rows("a,b\n1,2"),
                                             mapping: ExportService.ColumnMapping(),
                                             hasHeader: true, formatter: formatter,
                                             calendar: calendar)
        #expect(result.rows.isEmpty)
        #expect(result.skipped.count == 1)
    }

    @Test func anEmptyFileImportsNothingWithoutCrashing() {
        let mapping = ExportService.suggestMapping(headers: ["Date", "Amount"])
        let result = ExportService.parseRows([], mapping: mapping, hasHeader: true,
                                             formatter: formatter, calendar: calendar)
        #expect(result.rows.isEmpty)
    }
}

struct BackupServiceTests {
    private let calendar = FinancialCalendar(timeZone: TimeZone(identifier: "UTC")!,
                                             now: { Date(timeIntervalSince1970: 1_789_000_000) })

    @Test func backupNamesSortChronologicallyAsText() {
        let early = BackupService.backupFileName(at: Date(timeIntervalSince1970: 1_700_000_000))
        let late = BackupService.backupFileName(at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(early < late)
        #expect(early.hasPrefix("tranquil-"))
        #expect(early.hasSuffix(".store"))
    }

    @Test func theWeeklyBackupIsDueAfterSevenDays() {
        let now = calendar.today()
        #expect(BackupService.isWeeklyBackupDue(lastBackup: nil, now: now, calendar: calendar))
        #expect(!BackupService.isWeeklyBackupDue(lastBackup: calendar.addDays(-6, to: now),
                                                 now: now, calendar: calendar))
        #expect(BackupService.isWeeklyBackupDue(lastBackup: calendar.addDays(-7, to: now),
                                                now: now, calendar: calendar))
    }

    @Test func pruningKeepsTheMostRecentTwelve() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for index in 0..<20 {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400)
            let url = folder.appendingPathComponent(BackupService.backupFileName(at: date))
            try Data("x".utf8).write(to: url)
        }
        #expect(try BackupService.existingBackups(in: folder).count == 20)
        try BackupService.prune(in: folder)
        #expect(try BackupService.existingBackups(in: folder).count == BackupService.keepCount)
    }

    @Test func unrelatedFilesInTheFolderAreLeftAlone() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let unrelated = folder.appendingPathComponent("my-taxes.pdf")
        try Data("x".utf8).write(to: unrelated)
        for index in 0..<15 {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400)
            try Data("x".utf8).write(
                to: folder.appendingPathComponent(BackupService.backupFileName(at: date))
            )
        }
        try BackupService.prune(in: folder)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
