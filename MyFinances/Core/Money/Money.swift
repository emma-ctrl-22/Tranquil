import Foundation

/// An amount of money, stored as an integer count of **minor units** (pesewas, cents).
///
/// There is no `Double` anywhere in this type or anywhere that touches it. Rates and
/// percentages are `Decimal`; conversion back to `Money` always names its rounding rule.
nonisolated struct Money: Hashable, Comparable, Codable, Sendable {
    /// Signed count of minor units. Direction in the ledger comes from `Transaction.kind`;
    /// negatives here exist only for computed deltas (gaps, variances, projections).
    let minorUnits: Int

    init(minorUnits: Int) {
        self.minorUnits = minorUnits
    }

    static let zero = Money(minorUnits: 0)

    var isZero: Bool { minorUnits == 0 }
    var isNegative: Bool { minorUnits < 0 }
    var isPositive: Bool { minorUnits > 0 }
    var magnitude: Money { Money(minorUnits: abs(minorUnits)) }
    /// -1, 0 or 1.
    var sign: Int { minorUnits == 0 ? 0 : (minorUnits < 0 ? -1 : 1) }

    // MARK: - Arithmetic

    static func + (a: Money, b: Money) -> Money { Money(minorUnits: a.minorUnits + b.minorUnits) }
    static func - (a: Money, b: Money) -> Money { Money(minorUnits: a.minorUnits - b.minorUnits) }
    static prefix func - (a: Money) -> Money { Money(minorUnits: -a.minorUnits) }
    static func * (a: Money, n: Int) -> Money { Money(minorUnits: a.minorUnits * n) }
    static func * (n: Int, a: Money) -> Money { Money(minorUnits: a.minorUnits * n) }

    static func += (a: inout Money, b: Money) { a = a + b }
    static func -= (a: inout Money, b: Money) { a = a - b }

    static func < (a: Money, b: Money) -> Bool { a.minorUnits < b.minorUnits }

    static func sum(_ amounts: [Money]) -> Money {
        Money(minorUnits: amounts.reduce(0) { $0 + $1.minorUnits })
    }

    static func max(_ a: Money, _ b: Money) -> Money { a > b ? a : b }
    static func min(_ a: Money, _ b: Money) -> Money { a < b ? a : b }

    /// Clamped at zero — used wherever a negative would be nonsense (a shortfall, a remaining target).
    var clampedToZero: Money { minorUnits < 0 ? .zero : self }

    // MARK: - Decimal scaling

    /// Multiply by a rate (a percentage, a proration factor) and round **once**, banker's.
    ///
    /// Rounding happens here and only here; callers must not pre-round their rates.
    func scaled(by rate: Decimal) -> Money {
        let product = Decimal(minorUnits) * rate
        return Money(minorUnits: Money.roundBankers(product))
    }

    /// This amount as a `Decimal` count of minor units, for use inside rate maths.
    var decimalMinorUnits: Decimal { Decimal(minorUnits) }

    /// `self / other` as a ratio, or nil when `other` is zero.
    func ratio(to other: Money) -> Decimal? {
        guard other.minorUnits != 0 else { return nil }
        return Decimal(minorUnits) / Decimal(other.minorUnits)
    }

    /// Banker's rounding (half-to-even) of a `Decimal` to a whole number of minor units.
    static func roundBankers(_ value: Decimal) -> Int {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    // MARK: - Splitting

    /// Split into `parts` pieces that sum **exactly** back to `self`.
    ///
    /// The remainder minor units are distributed one each across the first parts, so
    /// `₵10.00 / 3` is `[3.34, 3.33, 3.33]`. Never loses or creates money.
    func split(into parts: Int) -> [Money] {
        precondition(parts > 0, "Money.split(into:) requires at least one part")
        let sign = minorUnits < 0 ? -1 : 1
        let total = abs(minorUnits)
        let base = total / parts
        let remainder = total % parts
        var result: [Money] = []
        result.reserveCapacity(parts)
        for index in 0..<parts {
            let units = base + (index < remainder ? 1 : 0)
            result.append(Money(minorUnits: sign * units))
        }
        assert(Money.sum(result) == self, "Money.split lost or created money")
        return result
    }

    /// Split proportionally to `weights`, preserving the total exactly.
    ///
    /// Uses the largest-remainder method: everyone gets their floor, then the leftover
    /// minor units go to the parts with the largest discarded fractions. This is how the
    /// windfall allocation sheet and the amortisation schedule divide money.
    func allocate(by weights: [Decimal]) -> [Money] {
        precondition(!weights.isEmpty, "Money.allocate(by:) requires at least one weight")
        precondition(weights.allSatisfy { $0 >= 0 }, "Money.allocate(by:) requires non-negative weights")
        let totalWeight = weights.reduce(Decimal(0), +)
        guard totalWeight > 0 else { return Array(repeating: .zero, count: weights.count) }

        let sign = minorUnits < 0 ? -1 : 1
        let total = abs(minorUnits)

        var floors: [Int] = []
        var remainders: [(index: Int, fraction: Decimal)] = []
        floors.reserveCapacity(weights.count)

        for (index, weight) in weights.enumerated() {
            let exact = (Decimal(total) * weight) / totalWeight
            var floorValue = Decimal()
            var input = exact
            NSDecimalRound(&floorValue, &input, 0, .down)
            let units = NSDecimalNumber(decimal: floorValue).intValue
            floors.append(units)
            remainders.append((index, exact - floorValue))
        }

        var leftover = total - floors.reduce(0, +)
        // Largest fraction first; ties broken by original order so the result is deterministic.
        remainders.sort { $0.fraction == $1.fraction ? $0.index < $1.index : $0.fraction > $1.fraction }
        var cursor = 0
        while leftover > 0 && cursor < remainders.count {
            floors[remainders[cursor].index] += 1
            leftover -= 1
            cursor += 1
        }

        let result = floors.map { Money(minorUnits: sign * $0) }
        assert(Money.sum(result) == self, "Money.allocate lost or created money")
        return result
    }
}

nonisolated extension Money: CustomStringConvertible {
    /// Debug only — user-facing strings come from `MoneyFormatter`.
    var description: String { "Money(\(minorUnits))" }
}
