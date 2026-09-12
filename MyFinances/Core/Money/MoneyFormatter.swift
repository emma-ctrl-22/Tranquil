import Foundation

/// The only place in the app that turns an amount into a string, or a string into an amount.
/// No view builds a currency string from a number itself.
nonisolated struct MoneyFormatter: Sendable {
    let currency: Currency
    let locale: Locale

    init(currency: Currency, locale: Locale = .autoupdatingCurrent) {
        self.currency = currency
        self.locale = locale
    }

    enum Style: Sendable {
        /// `₵1,234.50`
        case full
        /// `₵1,235` — whole major units, for dense charts and axis labels.
        case rounded
        /// `1,234.50` — no symbol, for table columns that carry the symbol in the header.
        case bare
        /// `+₵1,234.50` / `−₵1,234.50` — used where direction matters at a glance.
        case signed
    }

    func string(_ amount: Money, style: Style = .full) -> String {
        switch style {
        case .full:
            return (amount.isNegative ? "−" : "") + currency.symbol + digits(amount.magnitude, fractional: true)
        case .rounded:
            let whole = roundedToMajorUnits(amount)
            return (whole < 0 ? "−" : "") + currency.symbol + groupedInteger(abs(whole))
        case .bare:
            return (amount.isNegative ? "−" : "") + digits(amount.magnitude, fractional: true)
        case .signed:
            let mark = amount.isNegative ? "−" : "+"
            return mark + currency.symbol + digits(amount.magnitude, fractional: true)
        }
    }

    /// Accessible reading, e.g. "12 cedis 50 pesewas" is overkill; we read the plain figure
    /// with the code spelled out so VoiceOver does not say "swirl one two".
    func accessibleString(_ amount: Money) -> String {
        let sign = amount.isNegative ? "minus " : ""
        return sign + digits(amount.magnitude, fractional: true) + " " + currency.code
    }

    // MARK: - Parsing

    /// Parse user input in **major units** ("12.50", "12,50", "1 200", "₵12") into `Money`.
    /// Returns nil rather than guessing. Never goes via `Double`.
    func parse(_ text: String) -> Money? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        var negative = false
        for marker in ["−", "-"] where cleaned.hasPrefix(marker) {
            negative = true
            cleaned.removeFirst()
        }
        cleaned = cleaned.replacingOccurrences(of: currency.symbol, with: "")
        cleaned = cleaned.replacingOccurrences(of: currency.code, with: "")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\u{00A0}", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }

        // Whichever of . or , appears last is the decimal separator; the other groups thousands.
        let lastDot = cleaned.lastIndex(of: ".")
        let lastComma = cleaned.lastIndex(of: ",")
        var decimalSeparator: Character?
        switch (lastDot, lastComma) {
        case let (dot?, comma?): decimalSeparator = dot > comma ? "." : ","
        case (_?, nil): decimalSeparator = "."
        case (nil, _?): decimalSeparator = ","
        case (nil, nil): decimalSeparator = nil
        }

        var wholePart = ""
        var fractionPart = ""
        if let separator = decimalSeparator, let index = cleaned.lastIndex(of: separator) {
            wholePart = String(cleaned[cleaned.startIndex..<index])
            fractionPart = String(cleaned[cleaned.index(after: index)...])
            // A group of exactly three digits after the *only* separator is thousands,
            // not decimals — but only when that separator is NOT the locale's decimal
            // separator. Otherwise "1.005" would silently become one thousand and five.
            let isDecimalSeparator = String(separator) == decimalSeparatorString
            if fractionPart.count == 3 && !isDecimalSeparator
                && cleaned.filter({ $0 == separator }).count == 1
                && currency.minorUnitExponent != 3 {
                let others: Set<Character> = [".", ","]
                if !wholePart.contains(where: { others.contains($0) }) && wholePart.count <= 3 && !wholePart.isEmpty {
                    wholePart += fractionPart
                    fractionPart = ""
                }
            }
        } else {
            wholePart = cleaned
        }

        wholePart = wholePart.filter { $0.isNumber || $0 == "." || $0 == "," }
        wholePart = wholePart.filter { $0.isNumber }
        guard fractionPart.allSatisfy({ $0.isNumber }) else { return nil }
        guard !(wholePart.isEmpty && fractionPart.isEmpty) else { return nil }
        guard wholePart.count <= 15 else { return nil }

        let exponent = currency.minorUnitExponent
        // Extra typed decimals round rather than truncate, so "1.005" is not silently "1.00".
        var fractionUnits = 0
        if !fractionPart.isEmpty {
            let padded = fractionPart.count < exponent
                ? fractionPart + String(repeating: "0", count: exponent - fractionPart.count)
                : fractionPart
            let kept = String(padded.prefix(exponent))
            guard let keptValue = Int(kept.isEmpty ? "0" : kept) else { return nil }
            fractionUnits = keptValue
            if padded.count > exponent {
                let rest = String(padded.dropFirst(exponent))
                if let first = rest.first, let digit = first.wholeNumberValue, digit >= 5 {
                    fractionUnits += 1
                }
            }
        }

        let whole = wholePart.isEmpty ? 0 : Int(wholePart)
        guard let whole else { return nil }
        let units = whole * currency.minorUnitsPerMajor + fractionUnits
        return Money(minorUnits: negative ? -units : units)
    }

    // MARK: - Internals

    private func digits(_ amount: Money, fractional: Bool) -> String {
        let per = currency.minorUnitsPerMajor
        let whole = amount.minorUnits / per
        let fraction = abs(amount.minorUnits % per)
        guard fractional && currency.minorUnitExponent > 0 else { return groupedInteger(whole) }
        let padded = String(format: "%0\(currency.minorUnitExponent)d", fraction)
        return groupedInteger(whole) + decimalSeparatorString + padded
    }

    private func roundedToMajorUnits(_ amount: Money) -> Int {
        let per = currency.minorUnitsPerMajor
        guard per > 1 else { return amount.minorUnits }
        return Money.roundBankers(Decimal(amount.minorUnits) / Decimal(per))
    }

    private var decimalSeparatorString: String { locale.decimalSeparator ?? "." }
    private var groupingSeparatorString: String { locale.groupingSeparator ?? "," }

    private func groupedInteger(_ value: Int) -> String {
        let text = String(abs(value))
        var grouped = ""
        for (offset, character) in text.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 { grouped.append(contentsOf: groupingSeparatorString.reversed()) }
            grouped.append(character)
        }
        return (value < 0 ? "-" : "") + String(grouped.reversed())
    }
}
