import SwiftUI
import SwiftData
import Charts

/// Investments and the emergency fund — the money that is not for spending.
struct InvestmentsView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let summary: InvestmentEngine.Summary
    let contributionMonths: Int
    let contributionRate: Decimal?

    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil }, sort: \SinkingFund.sortOrder)
    private var funds: [SinkingFund]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]
    @Query(filter: #Predicate<Valuation> { $0.deletedAt == nil },
           sort: \Valuation.date, order: .reverse)
    private var valuations: [Valuation]

    @State private var valuingAccountID: UUID?

    private var emergencyFund: SinkingFund? { funds.first(where: \.isEmergencyFund) }

    private var emergencySaved: Money {
        guard let fund = emergencyFund else { return .zero }
        return Money.sum(earmarks.filter { $0.ownerID == fund.id }.map(\.amount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if summary.holdings.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No investment accounts yet",
                        message: "Add an account of type Investment — an MFund, a T-bill "
                               + "ladder, whatever you actually hold. Transfer into it from "
                               + "the Accounts screen and the app tracks what you put in. "
                               + "You tell it what the balance is worth; it never guesses.",
                        actionTitle: "Go to Accounts",
                        action: { model.open(.accounts) }
                    )
                } else {
                    overview
                    ForEach(summary.holdings) { holding in
                        holdingCard(holding)
                    }
                }
                if emergencyFund != nil { emergencyCard }
            }
            .padding(Theme.Space.lg)
        }
        .sheet(item: Binding(
            get: { valuingAccountID.map { IdentifiedID(id: $0) } },
            set: { valuingAccountID = $0?.id }
        )) { wrapper in
            ValuationSheet(accountID: wrapper.id, formatter: formatter, calendar: calendar)
        }
    }

    private var overview: some View {
        Card(padding: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    StatTile(label: "You have put in",
                             value: formatter.string(summary.totalContributed),
                             detail: "Every transfer in, less anything taken out",
                             accessibilityValue: formatter.accessibleString(
                                summary.totalContributed))
                    StatTile(label: "Worth now",
                             value: summary.hasAnyValuation
                                ? formatter.string(summary.totalValue) : "—",
                             detail: summary.hasAnyValuation
                                ? "From the figures you entered"
                                : "Enter a value to see this",
                             accessibilityValue: summary.hasAnyValuation
                                ? formatter.accessibleString(summary.totalValue) : "not entered")
                    StatTile(label: "Months contributed",
                             value: "\(contributionMonths) / 12",
                             detail: contributionRate.map {
                                "\(Money.roundBankers($0 * 100))% of what you earned"
                             } ?? "Consistency matters more than size",
                             tone: contributionMonths >= 9 ? .positive
                                   : (contributionMonths >= 5 ? .caution : .neutral),
                             accessibilityValue: "\(contributionMonths) of 12 months")
                }
                Text("This app will never forecast what an investment might become. It shows "
                     + "what you put in, and whatever you last told it the holding is worth.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func holdingCard(_ holding: InvestmentEngine.Holding) -> some View {
        let history = valuations.filter { $0.account?.id == holding.accountID }
        let stale = holding.needsValuation(today: calendar.today(), calendar: calendar)
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: holding.colorHex))
                        .frame(width: 3, height: 16)
                    Text(holding.name).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button(holding.currentValue == nil ? "Enter its value" : "Update value") {
                        valuingAccountID = holding.accountID
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(holding.currentValue == nil ? Theme.Palette.accent : .secondary)
                }

                HStack(spacing: Theme.Space.lg) {
                    figure("Put in", formatter.string(holding.contributed))
                    figure("Worth", holding.currentValue.map { formatter.string($0) } ?? "—")
                    if let gain = holding.gain {
                        figure("Difference", formatter.string(gain, style: .signed),
                               tone: gain.isNegative ? .negative : .positive)
                    }
                }

                if let valuedOn = holding.valuedOn {
                    Text("Last valued "
                         + valuedOn.formatted(date: .abbreviated, time: .omitted)
                         + (stale ? " — worth checking again" : ""))
                        .font(Theme.Font.caption)
                        .foregroundStyle(stale ? Theme.Palette.caution : .secondary)
                } else {
                    Text("No value entered yet. Check your statement and put the figure in.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }

                if history.count >= 2 {
                    Chart {
                        ForEach(history.reversed()) { valuation in
                            LineMark(x: .value("Date", valuation.date),
                                     y: .value("Value",
                                               Double(valuation.valueMinorUnits) / 100))
                                .foregroundStyle(Color(hex: holding.colorHex))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(formatter.string(Money(minorUnits: Int(amount * 100)),
                                                          style: .rounded))
                                        .font(Theme.Font.caption)
                                }
                            }
                        }
                    }
                    .frame(height: 110)
                    .accessibilityLabel("\(holding.name) value over time")
                }
            }
        }
    }

    private var emergencyCard: some View {
        let fund = emergencyFund
        let target = fund?.targetAmount ?? .zero
        let fraction = target.isPositive
            ? (emergencySaved.ratio(to: target).map {
                NSDecimalNumber(decimal: $0).doubleValue } ?? 0)
            : 0
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Emergency fund")
                    Pill(text: "protected", tone: .positive, icon: "shield")
                    Spacer()
                    Text("\(formatter.string(emergencySaved)) of \(formatter.string(target))")
                        .font(Theme.Font.amount).foregroundStyle(.secondary)
                }
                MeterBar(fraction: fraction, tone: .positive, height: 7)
                Text("This one is special: the allocation engine only ever adds to it, never "
                     + "takes from it, and spending out of it asks you to confirm and say why.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ label: String, _ value: String,
                        tone: StatTile.Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(text: label)
            Text(value).font(Theme.Font.amount).foregroundStyle(tone.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Enter what a holding is worth today.
struct ValuationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let accountID: UUID
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }) private var accounts: [Account]

    @State private var valueText = ""
    @State private var date = Date()
    @State private var note = ""
    @FocusState private var isFocused: Bool

    private var account: Account? { accounts.first { $0.id == accountID } }
    private var value: Money? { formatter.parse(valueText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What is \(account?.name ?? "it") worth?").font(Theme.Font.title)
                Text("Check your statement and type the figure. Nothing is looked up — this "
                     + "app has no internet access.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "Value today")
                    TextField("0.00", text: $valueText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .light, design: .rounded))
                        .focused($isFocused)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "As at")
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: 210, alignment: .leading)
                }
                TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder)

                Text("This does not move any money or change your balances. It only records "
                     + "what the holding was worth on that date.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.lg)

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(value == nil)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 420)
        .background(Theme.Palette.surface(scheme))
        .onAppear { date = calendar.today(); isFocused = true }
    }

    private func save() {
        guard let value, let account else { return }
        context.insert(Valuation(account: account,
                                 date: calendar.financialDay(for: date),
                                 value: value,
                                 note: note.isEmpty ? nil : note))
        try? context.save()
        dismiss()
    }
}
