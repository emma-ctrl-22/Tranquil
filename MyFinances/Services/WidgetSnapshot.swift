import Foundation

/// What the widget shows.
///
/// The widget runs in its own process and cannot open the app's database, so the app
/// writes this small file into a shared App Group container and the widget reads it.
/// The database itself never moves and the widget never writes anything.
///
/// **Add this one file to both targets** (Tranquil and TranquilWidget).
struct WidgetSnapshot: Codable, Sendable {

    /// Bump when the shape changes so a stale file is ignored rather than misread.
    static let currentVersion = 1

    /// The App Group both targets share.
    static let appGroupID = "group.com.MyFinances"
    static let fileName = "widget-snapshot.json"

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date = Date()

    /// Pre-formatted so the widget never has to know about Money or currency settings.
    var freeToSpend: String = "—"
    var freeToSpendIsNegative: Bool = false
    var freeToSpendCaption: String = ""

    var available: String = "—"
    var spentToday: String = "—"
    var spentThisWeek: String = "—"

    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var loggedToday: Bool = false
    var daysElapsedInWeek: Int = 1

    var runway: String?
    var stabilityScore: Int?
    var ladderStage: String?

    /// The single next action from the Ladder.
    var nextAction: String?

    /// The nearest thing worth knowing about, if anything is.
    var warning: String?
    /// The next scheduled outgoing, e.g. "Rent ₵900 on 1 Oct".
    var nextDue: String?

    /// Envelopes running ahead of pace, most urgent first.
    var envelopesAheadOfPace: [String] = []

    var hasAnyData: Bool = false

    // MARK: - Shared location

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    /// Reads the snapshot, or nil when the app has not written one yet.
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    /// Written atomically so the widget never reads a half-written file.
    func save() {
        guard let url = WidgetSnapshot.fileURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Shown before the app has ever written a snapshot.
    static let placeholder = WidgetSnapshot(
        freeToSpend: "₵248.00",
        freeToSpendCaption: "Day 3 of 7",
        available: "₵1,240.00",
        spentToday: "₵22.00",
        spentThisWeek: "₵210.00",
        currentStreak: 5,
        longestStreak: 12,
        loggedToday: true,
        daysElapsedInWeek: 3,
        runway: "2.4 mo",
        stabilityScore: 61,
        ladderStage: "Two-week buffer",
        nextAction: "Build a two-week buffer",
        nextDue: "Rent ₵900.00 on 1 Oct",
        hasAnyData: true
    )
}
