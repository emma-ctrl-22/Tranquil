import SwiftUI
import SwiftData
import Charts

/// The heatmap, net worth, category rollups, the micro-spend number, and income
/// against expense.
struct InsightsView: View {
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let cells: [InsightsEngine.Cell]
    let streaks: InsightsEngine.StreakSummary
    let categoryTotals: [InsightsEngine.CategoryTotal]
    let monthBars: [InsightsEngine.MonthBar]
    let netWorthSeries: [InsightsEngine.Point]
    let debtPoints: [InsightsEngine.DebtPoint]
    @Binding var heatmapMode: InsightsEngine.HeatmapMode

    private var microTotal: Money { InsightsEngine.microSpendTotal(categoryTotals) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HeatmapView(cells: cells, streaks: streaks, formatter: formatter,
                            calendar: calendar, mode: $heatmapMode)
                if !monthBars.isEmpty { incomeVsExpense }
                if !netWorthSeries.isEmpty { netWorthChart }
                if !debtPoints.isEmpty { debtBurndown }
                if !categoryTotals.isEmpty {
                    microRollup
                    categoryBreakdown
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    // MARK: - Income vs expense

    private var incomeVsExpense: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "In and out, 12 months")
                Chart {
                    ForEach(monthBars) { bar in
                        BarMark(
                            x: .value("Month", bar.monthStart, unit: .month),
                            y: .value("In", value(bar.income))
                        )
                        .position(by: .value("Kind", "In"))
                        .foregroundStyle(Theme.Palette.positive)
                        BarMark(
                            x: .value("Month", bar.monthStart, unit: .month),
                            y: .value("Out", value(bar.expense))
                        )
                        .position(by: .value("Kind", "Out"))
                        .foregroundStyle(Theme.Palette.negative.opacity(0.75))
                    }
                }
                .chartYAxis { axisMarks }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.month(.narrow))
                    }
                }
                .frame(height: 170)
                .accessibilityLabel("Income against expenses by month")
            }
        }
    }

    // MARK: - Net worth

    private var netWorthChart: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Net worth")
                    Spacer()
                    if let latest = netWorthSeries.last {
                        Text(formatter.string(latest.value)).font(Theme.Font.amount)
                    }
                }
                Chart {
                    ForEach(netWorthSeries) { point in
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Net worth", value(point.value)))
                            .foregroundStyle(Theme.Palette.accent)
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("Date", point.date),
                                 y: .value("Net worth", value(point.value)))
                            .foregroundStyle(.linearGradient(
                                colors: [Theme.Palette.accent.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .bottom))
                    }
                }
                .chartYAxis { axisMarks }
                .frame(height: 150)
                .accessibilityLabel("Net worth over time")
                Text("Excludes the tax reserve and money lent out.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Debt

    private var debtBurndown: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Debt burn-down")
                Chart {
                    ForEach(debtPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Balance", value(point.balance)),
                            stacking: .standard
                        )
                        .foregroundStyle(by: .value("Loan", point.loanName))
                    }
                }
                .chartYAxis { axisMarks }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 170)
                .accessibilityLabel("Projected debt balance by loan")
                Text("If you keep to the schedule. The extra-payment simulator on the Debt "
                     + "screen shows what changes if you do not.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Micro-spend

    /// "How much did bus fares actually cost me this year?" — the number that hides.
    private var microRollup: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Small, frequent spending")
                    Spacer()
                    Text(formatter.string(microTotal)).font(Theme.Font.figure)
                }
                if microTotal.isZero {
                    Text("Nothing tagged as a micro-spend yet.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(categoryTotals.filter(\.isMicro)) { total in
                        HStack {
                            Text(total.name).font(.system(size: 12))
                            Spacer()
                            Text(formatter.string(total.amount))
                                .font(Theme.Font.amount).foregroundStyle(.secondary)
                        }
                    }
                    Text("Individually trivial, collectively not. This is the number that "
                         + "hides.")
                        .font(Theme.Font.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Categories

    private var categoryBreakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Where it went this month")
                ForEach(categoryTotals) { total in
                    HStack(spacing: Theme.Space.sm) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: total.colorHex))
                            .frame(width: 3, height: 16)
                        Text(total.name).font(.system(size: 12.5))
                        Spacer()
                        if let fraction = total.deltaFraction, !total.delta.isZero {
                            Text(deltaText(fraction))
                                .font(Theme.Font.caption)
                                .foregroundStyle(total.delta.isPositive
                                                 ? Theme.Palette.caution
                                                 : Theme.Palette.positive)
                        }
                        Text(formatter.string(total.amount))
                            .font(Theme.Font.amount)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func deltaText(_ fraction: Decimal) -> String {
        let percent = Money.roundBankers(fraction * 100)
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    // MARK: - Shared

    private var axisMarks: some AxisContent {
        AxisMarks { value in
            AxisGridLine().foregroundStyle(.quaternary)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(formatter.string(Money(minorUnits: Int(amount * 100)), style: .rounded))
                        .font(Theme.Font.caption)
                }
            }
        }
    }

    /// Charts need a `Double`. Pixels only — no total is ever derived from it.
    private func value(_ money: Money) -> Double {
        Double(money.minorUnits) / 100
    }
}
