import WidgetKit
import SwiftUI

/// The desktop widget. Display only — widgets cannot take typed input, and ⌥⌘E already
/// opens capture from anywhere, which is faster than reaching for a widget.
///
/// It reads the snapshot the app writes into the shared App Group container. It never
/// touches the database and never writes anything.
@main
struct TranquilWidgetBundle: WidgetBundle {
    var body: some Widget {
        TranquilWidget()
    }
}

struct TranquilWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TranquilWidget", provider: SnapshotProvider()) { entry in
            TranquilWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tranquil")
        .description("What you can spend, and whether anything needs attention.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(),
                                 snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(),
                                  snapshot: WidgetSnapshot.load() ?? .placeholder)
        // The app reloads the timeline whenever the ledger changes, so this is only a
        // fallback for a day where nothing is logged at all.
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct TranquilWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        if !snapshot.hasAnyData {
            empty
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "leaf")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Tranquil").font(.system(size: 13, weight: .medium))
            Text("Add an account to get started.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            label(snapshot.freeToSpendCaption.isEmpty ? "Available"
                  : String(snapshot.freeToSpendCaption.split(separator: "·").first ?? "")
                    .trimmingCharacters(in: .whitespaces))
            Text(snapshot.freeToSpend)
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(snapshot.freeToSpendIsNegative ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if let warning = snapshot.warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                streakLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                label(snapshot.freeToSpendCaption)
                Text(snapshot.freeToSpend)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(snapshot.freeToSpendIsNegative ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                streakLine
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                stat("Today", snapshot.spentToday)
                stat("This week", snapshot.spentThisWeek)
                if let runway = snapshot.runway { stat("Runway", runway) }
                Spacer(minLength: 0)
                if let warning = snapshot.warning {
                    Text(warning)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                label(snapshot.freeToSpendCaption)
                Text(snapshot.freeToSpend)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(snapshot.freeToSpendIsNegative ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                stat("Today", snapshot.spentToday)
                stat("This week", snapshot.spentThisWeek)
                stat("Available", snapshot.available)
            }

            HStack(alignment: .top, spacing: 12) {
                if let runway = snapshot.runway { stat("Runway", runway) }
                if let score = snapshot.stabilityScore { stat("Stability", "\(score)/100") }
                stat("Streak", snapshot.currentStreak == 0 ? "—"
                     : "\(snapshot.currentStreak)d")
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                if let action = snapshot.nextAction {
                    row("arrow.right.circle", action, .primary)
                }
                if let due = snapshot.nextDue {
                    row("calendar", due, .secondary)
                }
                if let warning = snapshot.warning {
                    row("exclamationmark.triangle", warning, .orange)
                }
                if let stage = snapshot.ladderStage {
                    row("stairs", stage, .secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            label(name)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(tint == .primary ? .primary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Information, not a score to protect. Today being unlogged does not break it —
    /// the day is not over.
    private var streakLine: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.loggedToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(snapshot.loggedToday ? .green : .secondary)
            Text(snapshot.currentStreak == 0
                 ? "nothing logged yet"
                 : "\(snapshot.currentStreak) day streak")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
