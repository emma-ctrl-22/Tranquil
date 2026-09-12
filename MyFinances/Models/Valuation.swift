import Foundation
import SwiftData

/// A manually entered "what it is worth today" figure for an investment account.
///
/// The app never projects returns and has no way to look a price up — it has no network.
/// You check your fund yourself and type the number in; the app keeps the history and
/// shows it against what you actually put in.
@Model
final class Valuation {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var account: Account?
    /// The financial day this valuation applies to.
    var date: Date = Date()
    var valueMinorUnits: Int = 0
    var note: String?

    init(account: Account?, date: Date, value: Money, note: String? = nil,
         now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.account = account
        self.date = date
        self.valueMinorUnits = value.minorUnits
        self.note = note
    }

    var value: Money {
        get { Money(minorUnits: valueMinorUnits) }
        set { valueMinorUnits = newValue.minorUnits }
    }
}
