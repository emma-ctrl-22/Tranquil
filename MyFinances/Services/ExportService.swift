import Foundation
import SwiftData

/// CSV and JSON export, and CSV import with a column mapper.
///
/// Everything here is local file I/O. Nothing is uploaded anywhere, ever.
nonisolated enum ExportService {

    // MARK: - CSV

    /// RFC 4180 quoting: wrap in quotes when the value contains a comma, quote or newline,
    /// and double any embedded quotes.
    static func csvField(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csvRow(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    static let transactionColumns = [
        "date", "amount", "kind", "account", "counterAccount",
        "category", "note", "tags", "isEstimate",
    ]

    /// Amounts export in **major units** with full precision, so a spreadsheet reads
    /// them as money rather than as a count of pesewas.
    static func exportTransactions(
        _ transactions: [Transaction], formatter: MoneyFormatter, calendar: FinancialCalendar
    ) -> String {
        var lines = [csvRow(transactionColumns)]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            lines.append(csvRow([
                dateFormatter.string(from: calendar.financialDay(for: transaction.date)),
                formatter.string(transaction.amount, style: .bare),
                transaction.kind.rawValue,
                transaction.account?.name ?? "",
                transaction.counterAccount?.name ?? "",
                transaction.category?.name ?? "",
                transaction.note ?? "",
                transaction.tags.joined(separator: ";"),
                transaction.isEstimate ? "true" : "false",
            ]))
        }
        return lines.joined(separator: "\n")
    }

    /// A minimal CSV parser that honours quoted fields and embedded newlines.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                // Swift treats CRLF as one Character, so all three line endings are
                // matched explicitly. Missing this quietly folds the break into a field.
                case "\n", "\r\n", "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default: field.append(character)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    // MARK: - Import

    /// Maps whatever columns a spreadsheet happens to have onto the fields we need.
    struct ColumnMapping: Sendable {
        var date: Int?
        var amount: Int?
        var kind: Int?
        var account: Int?
        var category: Int?
        var note: Int?

        var isUsable: Bool { date != nil && amount != nil }
    }

    /// Best-effort guess at which column is which, by header name.
    static func suggestMapping(headers: [String]) -> ColumnMapping {
        var mapping = ColumnMapping()
        for (index, header) in headers.enumerated() {
            let name = header.lowercased().trimmingCharacters(in: .whitespaces)
            switch name {
            case "date", "day", "when", "transaction date": mapping.date = mapping.date ?? index
            case "amount", "value", "sum", "total": mapping.amount = mapping.amount ?? index
            case "kind", "type", "direction": mapping.kind = mapping.kind ?? index
            case "account", "wallet", "source": mapping.account = mapping.account ?? index
            case "category", "cat", "label": mapping.category = mapping.category ?? index
            case "note", "description", "memo", "details": mapping.note = mapping.note ?? index
            default: break
            }
        }
        return mapping
    }

    struct ImportedRow: Sendable {
        let date: Date
        let amount: Money
        let kind: TransactionKind
        let accountName: String?
        let categoryName: String?
        let note: String?
    }

    struct ImportResult: Sendable {
        var rows: [ImportedRow] = []
        var skipped: [String] = []
    }

    /// Parses rows against a mapping. A row it cannot read is **skipped and reported**,
    /// never guessed at — a silently mangled import is worse than a failed one.
    static func parseRows(
        _ rows: [[String]], mapping: ColumnMapping, hasHeader: Bool,
        formatter: MoneyFormatter, calendar: FinancialCalendar
    ) -> ImportResult {
        var result = ImportResult()
        guard mapping.isUsable else {
            result.skipped.append("A date column and an amount column are both required.")
            return result
        }

        let body = hasHeader ? Array(rows.dropFirst()) : rows
        for (offset, row) in body.enumerated() {
            let lineNumber = offset + (hasHeader ? 2 : 1)

            func field(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }

            guard let dateText = field(mapping.date), let date = parseDate(dateText) else {
                result.skipped.append("Line \(lineNumber): could not read the date.")
                continue
            }
            guard let amountText = field(mapping.amount),
                  let parsed = formatter.parse(amountText) else {
                result.skipped.append("Line \(lineNumber): could not read the amount.")
                continue
            }

            // A negative amount in a spreadsheet means an expense; we store it positive
            // and put the direction in `kind`.
            var kind: TransactionKind = parsed.isNegative ? .expense : .income
            if let kindText = field(mapping.kind)?.lowercased() {
                if let explicit = TransactionKind(rawValue: kindText) {
                    kind = explicit
                } else if ["debit", "out", "spend", "expense"].contains(kindText) {
                    kind = .expense
                } else if ["credit", "in", "income", "deposit"].contains(kindText) {
                    kind = .income
                }
            }

            result.rows.append(ImportedRow(
                date: calendar.financialDay(for: date),
                amount: parsed.magnitude,
                kind: kind,
                accountName: field(mapping.account),
                categoryName: field(mapping.category),
                note: field(mapping.note)
            ))
        }
        return result
    }

    /// Accepts the common spreadsheet date shapes rather than demanding one.
    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: text) { return date }

        let patterns = ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy",
                        "yyyy/MM/dd", "d MMM yyyy", "MMM d, yyyy"]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    // MARK: - JSON

    /// A full, human-readable dump. Money is exported as minor units so a round trip
    /// is exact.
    static func exportJSON(
        accounts: [Account], transactions: [Transaction], categories: [Category],
        loans: [Loan], goals: [Goal], calendar: FinancialCalendar
    ) throws -> Data {
        let iso = ISO8601DateFormatter()

        func accountJSON(_ account: Account) -> [String: Any] {
            [
                "id": account.id.uuidString, "name": account.name,
                "type": account.type.rawValue,
                "openingBalanceMinorUnits": account.openingBalanceMinorUnits,
                "isLiquid": account.isLiquid, "isTaxReserve": account.isTaxReserve,
                "includeInNetWorth": account.includeInNetWorth,
            ]
        }

        func transactionJSON(_ transaction: Transaction) -> [String: Any] {
            var object: [String: Any] = [
                "id": transaction.id.uuidString,
                "date": iso.string(from: transaction.date),
                "amountMinorUnits": transaction.amountMinorUnits,
                "kind": transaction.kind.rawValue,
                "isEstimate": transaction.isEstimate,
            ]
            if let account = transaction.account { object["account"] = account.name }
            if let counter = transaction.counterAccount { object["counterAccount"] = counter.name }
            if let category = transaction.category { object["category"] = category.name }
            if let note = transaction.note { object["note"] = note }
            return object
        }

        let payload: [String: Any] = [
            "format": "tranquil.v1",
            "exportedAt": iso.string(from: calendar.currentDate()),
            "note": "Amounts are integer minor units. Nothing here has left this machine.",
            "accounts": accounts.map(accountJSON),
            "categories": categories.map { ["id": $0.id.uuidString, "name": $0.name,
                                            "group": $0.group, "isEssential": $0.isEssential,
                                            "isMicro": $0.isMicro] },
            "transactions": transactions.map(transactionJSON),
            "loans": loans.map { ["id": $0.id.uuidString, "name": $0.name,
                                  "lender": $0.lender,
                                  "principalMinorUnits": $0.principalMinorUnits,
                                  "direction": $0.direction.rawValue] },
            "goals": goals.map { ["id": $0.id.uuidString, "name": $0.name,
                                  "targetMinorUnits": $0.targetAmountMinorUnits,
                                  "status": $0.status.rawValue] },
        ]
        return try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys])
    }
}
