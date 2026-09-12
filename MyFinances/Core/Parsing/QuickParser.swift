import Foundation

/// Turns one typed line into a transaction. `trotro 5`, `15 lunch momo`, `-40 data`,
/// `5000 salary`.
///
/// Pure and testable: it takes a vocabulary in and hands a result back. It never
/// guesses silently — anything it could not place stays in `note`, and `matched`
/// says exactly what it recognised so the preview can show its work.
nonisolated struct QuickParser: Sendable {

    struct Vocabulary: Sendable {
        struct Term: Sendable {
            let id: UUID
            let name: String
            /// Extra spellings: "momo" for MTN MoMo, "bus" for Trotro.
            let aliases: [String]

            init(id: UUID, name: String, aliases: [String] = []) {
                self.id = id
                self.name = name
                self.aliases = aliases
            }

            var spellings: [String] { ([name] + aliases).map { $0.lowercased() } }
        }

        let categories: [Term]
        let accounts: [Term]
        /// Words that mean money came in. Checked before the expense default.
        let incomeKeywords: Set<String>

        init(
            categories: [Term],
            accounts: [Term],
            incomeKeywords: Set<String> = QuickParser.defaultIncomeKeywords
        ) {
            self.categories = categories
            self.accounts = accounts
            self.incomeKeywords = incomeKeywords
        }
    }

    /// ASSUMPTION: these words flip a line to income when no explicit sign is typed.
    /// They are deliberately few — a false positive files a spend as income and
    /// corrupts the savings rate, which is worse than making the user type "+".
    static let defaultIncomeKeywords: Set<String> = [
        "salary", "wage", "wages", "paid", "payment", "income", "bonus",
        "refund", "reimbursement", "gift", "sold",
    ]

    struct Result: Equatable, Sendable {
        var amount: Money?
        var kind: TransactionKind = .expense
        var categoryID: UUID?
        var accountID: UUID?
        var note: String?
        /// The words that were consumed, for the live preview.
        var matched: [String] = []
        /// True when the line named no category — the entry belongs in Miscellaneous
        /// and should be flagged for review.
        var isUnclassified: Bool { categoryID == nil }

        var isComplete: Bool { amount?.isPositive == true }
    }

    let formatter: MoneyFormatter
    let vocabulary: Vocabulary

    init(formatter: MoneyFormatter, vocabulary: Vocabulary) {
        self.formatter = formatter
        self.vocabulary = vocabulary
    }

    func parse(_ input: String) -> Result {
        var result = Result()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }

        var tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var explicitSign: TransactionKind?

        // 1. Amount — the first token that parses as money wins.
        var amountIndex: Int?
        for (index, token) in tokens.enumerated() {
            guard let parsed = formatter.parse(token) else { continue }
            if token.hasPrefix("+") { explicitSign = .income }
            else if token.hasPrefix("-") || token.hasPrefix("−") { explicitSign = .expense }
            result.amount = parsed.magnitude
            amountIndex = index
            break
        }
        if let amountIndex {
            result.matched.append(tokens[amountIndex])
            tokens.remove(at: amountIndex)
        }

        // 2. Category, then account — longest spelling first so "mobile money" beats
        //    "money", and a phrase is not half-consumed by a shorter term.
        if let match = bestMatch(in: &tokens, terms: vocabulary.categories) {
            result.categoryID = match.id
            result.matched.append(match.text)
        }
        if let match = bestMatch(in: &tokens, terms: vocabulary.accounts) {
            result.accountID = match.id
            result.matched.append(match.text)
        }

        // 3. Direction. An explicit sign always wins over a keyword.
        if let explicitSign {
            result.kind = explicitSign
        } else if tokens.contains(where: { vocabulary.incomeKeywords.contains($0.lowercased()) })
                    || result.matched.contains(where: {
                        vocabulary.incomeKeywords.contains($0.lowercased())
                    }) {
            result.kind = .income
        }

        // 4. Whatever is left is the note, kept verbatim.
        let remainder = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        result.note = remainder.isEmpty ? nil : remainder
        return result
    }

    // MARK: - Matching

    private struct Match {
        let id: UUID
        let text: String
    }

    /// Finds the longest term whose spelling appears in the tokens, consuming the
    /// tokens it used so a later term cannot claim them again.
    private func bestMatch(in tokens: inout [String], terms: [Vocabulary.Term]) -> Match? {
        var best: (term: Vocabulary.Term, spelling: String, range: Range<Int>)?

        for term in terms {
            for spelling in term.spellings {
                let words = spelling.split(separator: " ").map(String.init)
                guard !words.isEmpty, words.count <= tokens.count else { continue }
                for start in 0...(tokens.count - words.count) {
                    let window = tokens[start..<(start + words.count)].map { $0.lowercased() }
                    guard window == words else { continue }
                    let range = start..<(start + words.count)
                    if best == nil || words.count > best!.range.count {
                        best = (term, spelling, range)
                    }
                }
            }
        }

        guard let best else { return nil }
        let text = tokens[best.range].joined(separator: " ")
        tokens.removeSubrange(best.range)
        return Match(id: best.term.id, text: text)
    }
}
