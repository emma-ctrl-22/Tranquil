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
    ///
    /// macOS requires the Team ID prefix — on iOS a plain `group.x` is fine, on macOS
    /// the container will simply not resolve without it.
    static let appGroupID = "VZ4AFL6ZHN.group.com.MyFinances"
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

    /// One entry per financial day, oldest first, for the contribution grid.
    /// 0 = nothing logged, 1–4 = increasing number of entries.
    var loggingGrid: [Int] = []
    /// The day of week (0 = week start) the grid begins on, so columns line up.
    var gridStartWeekday: Int = 0

    // MARK: - Shared location

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    /// Why the widget has nothing to show, when it has nothing to show.
    ///
    /// A widget that quietly renders sample figures when it cannot reach your data is
    /// worse than one that admits it: the numbers look real and are not.
    enum LoadFailure: Error, Sendable {
        /// The App Group is missing or misspelled on one of the two targets.
        case noSharedContainer
        /// The container is reachable but the app has not written a snapshot yet.
        case noSnapshotYet
        /// Written by a different version of the app.
        case versionMismatch
        /// The file is there but unreadable.
        case unreadable

        var message: String {
            switch self {
            case .noSharedContainer: "Can't reach shared data"
            case .noSnapshotYet: "Open Tranquil once"
            case .versionMismatch: "Update Tranquil"
            case .unreadable: "Data unreadable"
            }
        }

        var detail: String {
            switch self {
            case .noSharedContainer: "The App Group is not set up on both targets."
            case .noSnapshotYet: "Launch the app and this will fill in."
            case .versionMismatch: "The app and widget are different versions."
            case .unreadable: "The snapshot file could not be read."
            }
        }
    }

    /// Reads the snapshot, or says why it could not.
    static func loadResult() -> Result<WidgetSnapshot, LoadFailure> {
        guard let url = fileURL else { return .failure(.noSharedContainer) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.noSnapshotYet) }
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .failure(.unreadable)
        }
        guard snapshot.version == currentVersion else { return .failure(.versionMismatch) }
        return .success(snapshot)
    }

    /// Reads the snapshot, or nil when it could not be read.
    static func load() -> WidgetSnapshot? {
        try? loadResult().get()
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
        hasAnyData: true,
        loggingGrid: (0..<91).map { index in
            [0, 0, 1, 2, 3, 4, 2, 1, 0, 3][index % 10]
        },
        gridStartWeekday: 0
    )
}
