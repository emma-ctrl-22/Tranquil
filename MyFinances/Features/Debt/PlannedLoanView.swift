import SwiftUI

/// The verdict before you sign, with the arithmetic visible.
///
/// The advisor never says "you cannot afford that". It says what the thing costs, and
/// then you choose.
struct PlannedLoanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let existingPositions: [LoanEngine.Position]
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let settings: AppSettings?

    @State private var amountText = ""
    @State private var aprText = "25"
    @State private var months = 12
    @State private var interestKind: LoanInterestKind = .amortizing
    @State private var purposeIsDepreciating = true

    private var amount: Money? { formatter.parse(amountText) }
    private var apr: Decimal? {
        guard let value = Decimal(string: aprText.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return value / 100
    }

    private var planned: LoanEngine.LoanInput? {
        guard let amount, amount.isPositive, let apr else { return nil }
        let model: Loan.InterestModel
        switch interestKind {
        case .amortizing: model = .amortizing(apr: apr)
        case .flatRate: model = .flatRate(rate: apr, years: Swift.max(1, months / 12))
        case .revolving: model = .revolving(apr: apr)
        case .interestFree: model = .interestFree
        }
        return LoanEngine.LoanInput(
            id: UUID(), name: "Planned", lender: "", direction: .iOwe,
            principal: amount, interestModel: model, startDate: calendar.today(),
            termMonths: months, status: .planned
        )
    }

    private var verdict: LoanEngine.LoanVerdict? {
        guard let planned else { return nil }
        return LoanEngine.verdict(
            for: planned,
            existingPositions: existingPositions,
            medianMonthlyNetIncome: settings?.expectedMonthlyNetIncome ?? .zero,
            maxDebtServiceRatio: settings?.maxDebtServiceRatio ?? Decimal(string: "0.30")!,
            highInterestThreshold: settings?.highInterestThresholdAPR
                ?? Decimal(string: "0.25")!,
            calendar: calendar
        )
    }

    /// The alternative the spec insists on showing: not borrowing, and saving instead.
    private var savingInstead: (months: Int, perMonth: Money)? {
        guard let amount, amount.isPositive, let verdict else { return nil }
        let perMonth = verdict.newMonthlyPayment
        guard perMonth.isPositive else { return nil }
        let needed = amount.ratio(to: perMonth).map {
            Money.roundBankers($0)
        } ?? 0
        return (Swift.max(1, needed), perMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Thinking about a loan").font(Theme.Font.title)
                Text("Nothing is saved. This only tells you what it would cost.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    inputs
                    if let verdict { verdictCard(verdict) }
                    if let alternative = savingInstead { alternativeCard(alternative) }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 520, height: 660)
        .background(Theme.Palette.surface(scheme))
    }

    private var inputs: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Amount")
                        TextField("0.00", text: $amountText).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Rate %")
                        TextField("25", text: $aprText).textFieldStyle(.roundedBorder)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "Interest type")
                    Picker("", selection: $interestKind) {
                        Text("Reducing balance").tag(LoanInterestKind.amortizing)
                        Text("Flat rate").tag(LoanInterestKind.flatRate)
                        Text("Interest-free").tag(LoanInterestKind.interestFree)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Stepper("Over \(months) months", value: $months, in: 1...120)
                Toggle("It is something that loses value", isOn: $purposeIsDepreciating)
            }
        }
    }

    private func verdictCard(_ verdict: LoanEngine.LoanVerdict) -> some View {
        Card(padding: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Text(verdict.affordability.title)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tone(verdict).color)
                    Spacer()
                    Pill(text: verdict.verdict.title, tone: tone(verdict))
                }

                Divider().opacity(0.4)

                arithmetic("New monthly payment", formatter.string(verdict.newMonthlyPayment))
                arithmetic("Debt you already service",
                           formatter.string(verdict.existingMonthlyDebt))
                arithmetic("Monthly income",
                           formatter.string(settings?.expectedMonthlyNetIncome ?? .zero))
                Divider().opacity(0.4)
                arithmetic("Debt service ratio", percent(verdict.debtServiceRatio),
                           emphasised: true)
                arithmetic("Total interest over its life",
                           formatter.string(verdict.totalInterestOverLife), emphasised: true)

                if !verdict.ruleIDs.isEmpty {
                    Divider().opacity(0.4)
                    ForEach(verdict.ruleIDs, id: \.self) { rule in
                        NoticeRow(
                            tone: rule == "R4" ? .negative : .caution,
                            icon: "exclamationmark.triangle",
                            title: ruleTitle(rule),
                            detail: ruleDetail(rule)
                        )
                    }
                }

                if purposeIsDepreciating && verdict.ruleIDs.contains("R1") {
                    Text("Borrowing at this rate to buy something that loses value is two "
                         + "losses stacked.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(closingLine(verdict))
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func alternativeCard(_ alternative: (months: Int, perMonth: Money)) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Instead of borrowing")
                Text("Saving \(formatter.string(alternative.perMonth)) a month — the same amount "
                     + "the repayment would take — gets you there in about "
                     + "\(alternative.months) months, with no interest at all.")
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Whether waiting is worth it is your call, not the app's.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func tone(_ verdict: LoanEngine.LoanVerdict) -> StatTile.Tone {
        switch verdict.affordability {
        case .comfortable: .positive
        case .tight: .caution
        case .notAffordable: .negative
        }
    }

    private func closingLine(_ verdict: LoanEngine.LoanVerdict) -> String {
        switch verdict.affordability {
        case .comfortable:
            return "This fits. It still costs "
                 + "\(formatter.string(verdict.totalInterestOverLife)) in interest."
        case .tight:
            return "This fits, with no room to absorb a bad month. Your call."
        case .notAffordable:
            return "Above \(percent(settings?.maxDebtServiceRatio ?? Decimal(string: "0.30")!)) "
                 + "of income there is no room for anything going wrong. Taking it anyway "
                 + "needs a typed reason, which is recorded."
        }
    }

    private func ruleTitle(_ rule: String) -> String {
        switch rule {
        case "R1": "R1 — you are carrying expensive debt already"
        case "R4": "R4 — debt service above the limit"
        default: rule
        }
    }

    private func ruleDetail(_ rule: String) -> String {
        switch rule {
        case "R1": "New debt for something that loses value, while a loan above your "
                 + "high-interest threshold is still outstanding."
        case "R4": "Above this ratio you have no room to absorb a bad month."
        default: ""
        }
    }

    private func arithmetic(_ label: String, _ value: String,
                            emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasised ? .system(size: 14, weight: .medium).monospacedDigit()
                                 : Theme.Font.amount)
        }
    }

    private func percent(_ value: Decimal) -> String {
        let scaled = Money.roundBankers(value * 10_000)
        return "\(scaled / 100).\(String(format: "%02d", abs(scaled % 100)))%"
    }
}
