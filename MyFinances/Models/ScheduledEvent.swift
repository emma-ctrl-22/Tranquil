import Foundation
import SwiftData

/// Birthdays, weddings, funerals, school fees, annual renewals.
/// Feeds the cash-flow calendar and auto-sizes the Gifts and Social funds a year ahead.
@Model
final class ScheduledEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var label: String = ""
    var expectedDate: Date = Date()
    var expectedAmountMinorUnits: Int = 0
    var sinkingFund: SinkingFund?
    var confidenceRaw: String = EventConfidence.likely.rawValue
    /// Recurs every year on the same date (a birthday), rather than once.
    var repeatsAnnually: Bool = false
    var notes: String?

    init(
        label: String,
        expectedDate: Date,
        expectedAmount: Money,
        sinkingFund: SinkingFund? = nil,
        confidence: EventConfidence = .likely,
        repeatsAnnually: Bool = false,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.label = label
        self.expectedDate = expectedDate
        self.expectedAmountMinorUnits = expectedAmount.minorUnits
        self.sinkingFund = sinkingFund
        self.confidenceRaw = confidence.rawValue
        self.repeatsAnnually = repeatsAnnually
    }

    var expectedAmount: Money {
        get { Money(minorUnits: expectedAmountMinorUnits) }
        set { expectedAmountMinorUnits = newValue.minorUnits }
    }

    var confidence: EventConfidence {
        get { EventConfidence(rawValue: confidenceRaw) ?? .likely }
        set { confidenceRaw = newValue.rawValue }
    }

    /// How much of this event to carry into a projection.
    /// ASSUMPTION: certain 100%, likely 100%, maybe 50%. A "maybe" still needs
    /// partial cover — treating it as zero is how people get surprised — but
    /// funding it fully would over-reserve. Halving is the conservative middle.
    func projectionWeight(maybeWeight: Decimal = Decimal(string: "0.5")!) -> Decimal {
        switch confidence {
        case .certain, .likely: 1
        case .maybe: maybeWeight
        }
    }

    func projectedAmount(maybeWeight: Decimal = Decimal(string: "0.5")!) -> Money {
        expectedAmount.scaled(by: projectionWeight(maybeWeight: maybeWeight))
    }
}
