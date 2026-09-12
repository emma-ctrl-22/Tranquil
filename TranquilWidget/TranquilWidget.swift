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
            TranquilWidgetView(snapshot: entry.snapshot, failure: entry.failure)
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
    /// Set when the real data could not be read, so the widget can say so rather than
    /// render convincing sample figures.
    var failure: WidgetSnapshot.LoadFailure?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // The gallery preview is the one place sample data is honest.
        if context.isPreview {
            completion(SnapshotEntry(date: Date(), snapshot: .placeholder))
            return
        }
        completion(entry())
    }

    private func entry() -> SnapshotEntry {
        switch WidgetSnapshot.loadResult() {
        case let .success(snapshot):
            return SnapshotEntry(date: Date(), snapshot: snapshot)
        case let .failure(failure):
            return SnapshotEntry(date: Date(), snapshot: .placeholder, failure: failure)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = entry()
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
    var failure: WidgetSnapshot.LoadFailure?

    var body: some View {
        if let failure {
            unavailable(failure)
        } else if !snapshot.hasAnyData {
            empty
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
    }

    /// Says what is wrong instead of showing numbers that are not yours.
    private func unavailable(_ failure: WidgetSnapshot.LoadFailure) -> some View {
        StateCard(
            title: failure.message,
            detail: failure.detail,
            tone: .attention,
            compact: family == .systemSmall
        )
    }

    private var empty: some View {
        StateCard(
            title: "Nothing here yet",
            detail: "Add an account in Tranquil and this fills in.",
            tone: .calm,
            compact: family == .systemSmall
        )
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

            if !snapshot.loggingGrid.isEmpty {
                ContributionGrid(values: snapshot.loggingGrid)
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


/// A GitHub-style contribution grid: one square per financial day, seven rows, oldest
/// column first. Intensity is entries logged that day, capped at four.
struct ContributionGrid: View {
    let values: [Int]

    /// Split into columns of seven, so each column is one week.
    private var weeks: [[Int]] {
        stride(from: 0, to: values.count, by: 7).map { start in
            Array(values[start..<Swift.min(start + 7, values.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text("LOGGED")
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("13 weeks")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let columns = CGFloat(Swift.max(weeks.count, 1))
                let cell = Swift.max(
                    3,
                    Swift.min(
                        (geometry.size.width - spacing * (columns - 1)) / columns,
                        (geometry.size.height - spacing * 6) / 7
                    )
                )
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, value in
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(colour(value))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 58)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Logging over the last thirteen weeks")
        .accessibilityValue("\(values.filter { $0 > 0 }.count) of \(values.count) days logged")
    }

    /// Four visible steps rather than a continuous ramp, so a glance reads clearly.
    private func colour(_ value: Int) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.08) }
        let step = Swift.min(4, value)
        return Color(red: 0.31, green: 0.54, blue: 0.48)
            .opacity(0.25 + 0.19 * Double(step))
    }
}


// MARK: - Empty and unavailable states

/// The widget's resting face when it has nothing to show. It carries the app's leaf
/// rather than a warning triangle: nothing here is an emergency, and a finance widget
/// shouting at you from the desktop is a widget you remove.
struct StateCard: View {
    enum Tone {
        /// Waiting for data. Entirely neutral.
        case calm
        /// Something needs doing before it can work.
        case attention

        var mark: Color {
            switch self {
            case .calm: Color(red: 0.31, green: 0.54, blue: 0.48)
            case .attention: Color(red: 0.69, green: 0.54, blue: 0.31)
            }
        }
    }

    let title: String
    let detail: String
    let tone: Tone
    var compact: Bool = false

    private var markSize: CGFloat { compact ? 34 : 42 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            leafMark
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: compact ? 12 : 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    /// The leaf sitting on a soft tint, the same motif as the app icon and the menu bar.
    private var leafMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: markSize * 0.28, style: .continuous)
                .fill(tone.mark.opacity(0.16))
            ZStack {
                LeafMark()
                    .fill(
                        LinearGradient(
                            colors: [tone.mark.opacity(0.95), tone.mark.opacity(0.70)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                // The midrib, so it reads as a leaf and not a seed at this size.
                LeafRib()
                    .stroke(tone.mark.opacity(0.001), lineWidth: 0)
                LeafRib()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(
                        lineWidth: Swift.max(1, markSize * 0.028), lineCap: .round
                    ))
            }
            // The icon's proportions: a leaf is roughly half as wide as it is long.
            .frame(width: markSize * 0.335, height: markSize * 0.62)
            .rotationEffect(.degrees(-22))
        }
        .frame(width: markSize, height: markSize)
    }
}

/// The midrib, curving gently from base to tip.
struct LeafRib: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08),
            control: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.midY)
        )
        return path
    }
}

/// The leaf from the app icon, as a resolution-independent shape.
struct LeafMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let half = width / 2

        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let base = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: base)
        // Right flank: widest below the middle, tapering to a point at the tip.
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.midX + half * 1.45, y: rect.minY + height * 0.66),
            control2: CGPoint(x: rect.midX + half * 0.70, y: rect.minY + height * 0.20)
        )
        // Left flank back down, mirrored.
        path.addCurve(
            to: base,
            control1: CGPoint(x: rect.midX - half * 0.70, y: rect.minY + height * 0.20),
            control2: CGPoint(x: rect.midX - half * 1.45, y: rect.minY + height * 0.66)
        )
        path.closeSubpath()
        return path
    }
}
