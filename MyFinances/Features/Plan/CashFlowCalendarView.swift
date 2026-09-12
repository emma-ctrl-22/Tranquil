import SwiftUI
import Charts

/// The 60-day forward view. A line for the balance, a grid for the days, and any day
/// that goes below zero or below the floor called out with its reason and a fix.
struct CashFlowCalendarView: View {
    let projection: ForecastEngine.Projection
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    @State private var selectedDay: ForecastEngine.Day?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if let warning { warningCard(warning) }
            chartCard
            gridCard
            if let selectedDay { dayDetail(selectedDay) }
        }
    }

    private var warning: ForecastEngine.Day? {
        projection.firstNegativeDay ?? projection.firstDayBelowFloor
    }

    private func warningCard(_ day: ForecastEngine.Day) -> some View {
        NoticeRow(
            tone: day.isNegative ? .negative : .caution,
            icon: "exclamationmark.triangle",
            title: day.isNegative
                ? "\(dayLabel(day.date)) projects below zero"
                : "\(dayLabel(day.date)) projects below your floor",
            detail: (ForecastEngine.suggestion(for: projection, formatter: formatter) ?? "")
                  + " Projected balance that day: \(formatter.string(day.closingBalance))."
        )
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Next 60 days")
                    Spacer()
                    Text("Ends at \(formatter.string(projection.endingBalance))")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(projection.days) { day in
                        AreaMark(
                            x: .value("Day", day.date),
                            y: .value("Balance", balanceValue(day.closingBalance))
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Theme.Palette.accent.opacity(0.28), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Day", day.date),
                            y: .value("Balance", balanceValue(day.closingBalance))
                        )
                        .foregroundStyle(Theme.Palette.accent)
                        .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Theme.Palette.negative.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if let floor = projection.floor {
                        RuleMark(y: .value("Floor", balanceValue(floor)))
                            .foregroundStyle(Theme.Palette.caution.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                    if let warning {
                        RuleMark(x: .value("Trouble", warning.date))
                            .foregroundStyle(Theme.Palette.negative.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(formatter.string(
                                    Money(minorUnits: Int(amount * 100)), style: .rounded
                                ))
                                .font(Theme.Font.caption)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 190)
                .accessibilityLabel("Projected balance over the next sixty days")
            }
        }
    }

    /// Charts need a `Double`; money never does. This is the only place one is made,
    /// for pixels only — no total is ever computed from it.
    private func balanceValue(_ money: Money) -> Double {
        Double(money.minorUnits) / 100
    }

    private var gridCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Day by day")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 10),
                    spacing: 3
                ) {
                    ForEach(projection.days) { day in
                        DayCell(
                            day: day,
                            floor: projection.floor,
                            isSelected: selectedDay?.date == day.date
                        ) {
                            selectedDay = selectedDay?.date == day.date ? nil : day
                        }
                    }
                }
                HStack(spacing: Theme.Space.md) {
                    legend(Theme.Palette.negative, "below zero")
                    legend(Theme.Palette.caution, "below floor")
                    legend(Theme.Palette.accent, "money moves")
                    Spacer()
                }
                .padding(.top, Theme.Space.xs)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7)).frame(width: 8, height: 8)
            Text(text).font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    private func dayDetail(_ day: ForecastEngine.Day) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Text(dayLabel(day.date)).font(Theme.Font.title)
                    Spacer()
                    Text(formatter.string(day.closingBalance))
                        .font(Theme.Font.figure)
                        .foregroundStyle(day.isNegative ? Theme.Palette.negative : .primary)
                }
                if day.movements.isEmpty {
                    Text("Nothing scheduled.").font(Theme.Font.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(day.movements) { movement in
                        HStack {
                            Text(movement.label).font(.system(size: 12))
                            if movement.isEstimate { Pill(text: "estimate") }
                            Spacer()
                            Text(formatter.string(movement.amount, style: .signed))
                                .font(Theme.Font.amount)
                                .foregroundStyle(movement.amount.isNegative
                                                 ? .primary : Theme.Palette.positive)
                        }
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("Opens at \(formatter.string(day.openingBalance))")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatter.string(day.netChange, style: .signed))
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if date == calendar.today() { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

private struct DayCell: View {
    @Environment(\.colorScheme) private var scheme
    let day: ForecastEngine.Day
    let floor: Money?
    let isSelected: Bool
    let action: () -> Void

    private var tone: Color {
        if day.isNegative { return Theme.Palette.negative }
        if day.isBelowFloor(floor) { return Theme.Palette.caution }
        if day.hasMovement { return Theme.Palette.accent }
        return Theme.Palette.raised(scheme)
    }

    private var opacity: Double {
        day.isNegative || day.isBelowFloor(floor) ? 0.85 : (day.hasMovement ? 0.5 : 1)
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tone.opacity(opacity))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.primary.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .help(day.date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(day.isNegative ? "projected below zero" : "projected in credit")
    }
}
