import SwiftUI

/// The GitHub-style contribution grid, 53 columns by 7 rows.
///
/// The streak is presented as information. No confetti, no gamified guilt, no
/// streak-loss shaming — it exists to support logging, nothing more.
struct HeatmapView: View {
    @Environment(\.colorScheme) private var scheme
    let cells: [InsightsEngine.Cell]
    let streaks: InsightsEngine.StreakSummary
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    @Binding var mode: InsightsEngine.HeatmapMode

    private let cellSize: CGFloat = 10
    private let spacing: CGFloat = 2

    /// Grouped into columns of seven, starting on the week's first day.
    private var columns: [[InsightsEngine.Cell]] {
        guard let first = cells.first else { return [] }
        let offset = calendar.daysBetween(calendar.startOfWeek(containing: first.date), first.date)
        var padded: [InsightsEngine.Cell?] = Array(repeating: nil, count: offset)
        padded.append(contentsOf: cells.map { Optional($0) })
        return stride(from: 0, to: padded.count, by: 7).map { start in
            Array(padded[start..<Swift.min(start + 7, padded.count)]).compactMap { $0 }
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "A year of logging")
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(InsightsEngine.HeatmapMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: spacing) {
                                ForEach(column) { cell in
                                    cellView(cell)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .defaultScrollAnchor(.trailing)

                HStack(spacing: Theme.Space.lg) {
                    figure("Current streak",
                           streaks.current == 0 ? "—" : "\(streaks.current) days")
                    figure("Longest", streaks.longest == 0 ? "—" : "\(streaks.longest) days")
                    figure("Days logged",
                           "\(Money.roundBankers(streaks.rate * 100))%")
                    Spacer()
                    legend
                }
            }
        }
    }

    private func cellView(_ cell: InsightsEngine.Cell) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: cell))
            .frame(width: cellSize, height: cellSize)
            .help(tooltip(for: cell))
            .accessibilityLabel(cell.date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue(tooltip(for: cell))
    }

    private func color(for cell: InsightsEngine.Cell) -> Color {
        guard cell.intensity > 0 else { return Theme.Palette.raised(scheme) }
        let base: Color
        switch mode {
        case .logged, .greenDay: base = Theme.Palette.accent
        case .spend: base = Theme.Palette.caution
        }
        // Four visible steps rather than a continuous ramp, so a glance reads clearly.
        let step = Swift.min(4, Swift.max(1, Int(ceil(cell.intensity * 4))))
        return base.opacity(0.22 * Double(step) + 0.12)
    }

    private func tooltip(for cell: InsightsEngine.Cell) -> String {
        let date = cell.date.formatted(date: .abbreviated, time: .omitted)
        switch mode {
        case .logged:
            return cell.entryCount == 0 ? "\(date): nothing logged"
                                        : "\(date): \(cell.entryCount) entries"
        case .spend:
            return "\(date): \(formatter.string(cell.spend))"
        case .greenDay:
            return cell.stayedInsidePace ? "\(date): inside pace" : "\(date): over pace"
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(text: label)
            Text(value).font(Theme.Font.amount)
        }
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("less").font(Theme.Font.caption).foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step == 0 ? Theme.Palette.raised(scheme)
                          : (mode == .spend ? Theme.Palette.caution : Theme.Palette.accent)
                              .opacity(0.22 * Double(step) + 0.12))
                    .frame(width: 8, height: 8)
            }
            Text("more").font(Theme.Font.caption).foregroundStyle(.tertiary)
        }
    }
}
