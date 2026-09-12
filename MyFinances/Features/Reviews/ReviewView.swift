import SwiftUI
import SwiftData
import AppKit

/// The weekly and monthly reviews. Screens with a copy button, not emails.
struct ReviewView: View {
    @Environment(\.colorScheme) private var scheme
    let weekly: ReviewEngine.Weekly
    let monthly: ReviewEngine.Monthly
    let formatter: MoneyFormatter

    @State private var period: Period = .weekly
    @State private var didCopy = false

    enum Period: String, CaseIterable, Identifiable {
        case weekly, monthly
        var id: String { rawValue }
        var title: String { self == .weekly ? "This week" : "This month" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                Spacer()
                Button(didCopy ? "Copied" : "Copy as text", action: copy)
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if period == .weekly { weeklyBody } else { monthlyBody }
                }
                .padding(Theme.Space.lg)
            }
        }
    }

    // MARK: - Weekly

    private var weeklyBody: some View {
        Group {
            Card(padding: Theme.Space.lg) {
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    StatTile(label: "Spent", value: formatter.string(weekly.totalSpent),
                             detail: "Week of \(weekly.weekStart.formatted(date: .abbreviated, time: .omitted))",
                             accessibilityValue: formatter.accessibleString(weekly.totalSpent))
                    StatTile(label: "In", value: formatter.string(weekly.totalIncome),
                             detail: "Net \(formatter.string(weekly.net, style: .signed))",
                             accessibilityValue: formatter.accessibleString(weekly.totalIncome))
                    StatTile(label: "Logged", value: "\(weekly.daysLogged) / 7",
                             detail: weekly.streak > 0 ? "\(weekly.streak) day streak" : "no streak yet",
                             accessibilityValue: "\(weekly.daysLogged) of 7 days")
                }
            }

            if !weekly.envelopes.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionLabel(text: "Envelopes")
                        ForEach(weekly.envelopes) { line in
                            HStack {
                                Text(line.name).font(.system(size: 12.5))
                                Spacer()
                                Text("\(formatter.string(line.spent)) of \(formatter.string(line.budget))")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                                Text(line.isOver
                                     ? "over \(formatter.string(line.variance.magnitude))"
                                     : "\(formatter.string(line.variance)) left")
                                    .font(Theme.Font.amount)
                                    .foregroundStyle(line.isOver ? Theme.Palette.caution
                                                                 : Theme.Palette.positive)
                            }
                        }
                    }
                }
            }

            if !weekly.biggestExpenses.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionLabel(text: "Biggest three")
                        ForEach(weekly.biggestExpenses) { expense in
                            HStack {
                                Text(expense.label).font(.system(size: 12.5))
                                Spacer()
                                Text(formatter.string(expense.amount)).font(Theme.Font.amount)
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "For next week")
                    Text(weekly.suggestion)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Monthly

    private var monthlyBody: some View {
        Group {
            Card(padding: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    let headline = ReviewEngine.headlineFigure(monthly, formatter: formatter)
                    SectionLabel(text: headline.0)
                    Text(headline.1)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                    Text("The figure that moved most this month.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "The month")
                    row("Net worth", formatter.string(monthly.netWorth),
                        trailing: formatter.string(monthly.netWorthChange, style: .signed))
                    row("In", formatter.string(monthly.income))
                    row("Out", formatter.string(monthly.spend))
                    if let rate = monthly.savingsRate {
                        row("Savings rate", "\(Money.roundBankers(rate * 100))%")
                    }
                    if monthly.debtCleared.isPositive {
                        row("Debt cleared", formatter.string(monthly.debtCleared))
                    }
                    row("Sinking funds on track",
                        "\(monthly.sinkingFundsOnTrack) of \(monthly.sinkingFundsTotal)")
                    if !monthly.overspendTotal.isZero {
                        row("Wishlist against plan",
                            formatter.string(monthly.overspendTotal, style: .signed))
                    }
                    if monthly.overrideCount > 0 {
                        Divider().opacity(0.4)
                        row("Advisor overrides", "\(monthly.overrideCount)")
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        SectionLabel(text: "Stability score")
                        Spacer()
                        Text("\(monthly.score.total) / 100").font(Theme.Font.amount)
                    }
                    ForEach(monthly.score.components) { component in
                        HStack {
                            Text(component.name).font(.system(size: 12))
                            Spacer()
                            Text(component.detail)
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                            Text("\(component.earned)/\(component.available)")
                                .font(Theme.Font.amount).frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, trailing: String? = nil) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Text(value).font(Theme.Font.amount)
        }
        .accessibilityElement(children: .combine)
    }

    private func copy() {
        let text = period == .weekly
            ? ReviewEngine.weeklyText(weekly, formatter: formatter)
            : ReviewEngine.monthlyText(monthly, formatter: formatter)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didCopy = false
        }
    }
}
