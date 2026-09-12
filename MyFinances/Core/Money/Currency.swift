import Foundation

/// A single-currency app: one `Currency` is configured and used everywhere.
/// No FX conversion exists anywhere in Tranquil, by design.
nonisolated struct Currency: Codable, Hashable, Sendable {
    /// ISO 4217 code, e.g. "GHS".
    let code: String
    /// Display symbol, e.g. "₵".
    let symbol: String
    /// Number of decimal places, e.g. 2 for pesewas.
    let minorUnitExponent: Int

    /// Number of minor units in one major unit (100 for a 2-decimal currency).
    var minorUnitsPerMajor: Int {
        var result = 1
        for _ in 0..<minorUnitExponent { result *= 10 }
        return result
    }

    static let ghs = Currency(code: "GHS", symbol: "₵", minorUnitExponent: 2)
    static let usd = Currency(code: "USD", symbol: "$", minorUnitExponent: 2)
    static let eur = Currency(code: "EUR", symbol: "€", minorUnitExponent: 2)
    static let ngn = Currency(code: "NGN", symbol: "₦", minorUnitExponent: 2)

    static let known: [Currency] = [.ghs, .usd, .eur, .ngn]

    static func named(_ code: String) -> Currency? {
        known.first { $0.code == code }
    }
}
