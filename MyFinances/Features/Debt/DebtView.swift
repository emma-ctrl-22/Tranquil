import SwiftUI
import SwiftData

/// Loans owed, in the order worth clearing them, with what each order costs.
struct DebtView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let settings: AppSettings?

    @Query(filter: #Predicate<Loan> { $0.deletedAt == nil }, sort: \Loan.name)
    private var loans: [Loan]

    @State private var strategy: LoanEngine.PayoffStrategy = .avalanche
    @State private var selectedLoanID: UUID?
    @State private var isCreatingLoan = false
    @State private var isPlanningLoan = false
    @State private var payingLoanID: UUID?

    private var positions: [LoanEngine.Position] {
        loans.filter { $0.status != .planned }
            .map { LoanEngine.position(for: DataBridge.loan($0), calendar: calendar) }
    }

    private var owed: [LoanEngine.Position] {
        positions.filter { $0.loan.direction == .iOwe && !$0.isPaidOff }
    }

    private var owedToMe: [LoanEngine.Position] {
        positions.filter { $0.loan.direction == .owedToMe && !$0.isPaidOff }
    }

    private var ordered: [LoanEngine.Position] {
        LoanEngine.payoffOrder(positions, strategy: strategy,
                               today: calendar.today(), calendar: calendar)
    }

    private var totalOwed: Money { Money.sum(owed.map(\.remainingBalance)) }
    private var totalInterestRemaining: Money { Money.sum(owed.map(\.interestRemaining)) }

    private var monthlyDebtService: Money {
        Money.sum(owed.map {
            LoanEngine.monthlyEquivalent($0.regularPayment, frequency: $0.loan.paymentFrequency)
        })
    }

    private var debtServiceRatio: Decimal? {
        guard let income = settings?.expectedMonthlyNetIncome, income.isPositive else { return nil }
        return monthlyDebtService.ratio(to: income)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if owed.isEmpty && owedToMe.isEmpty {
                    EmptyStateView(
                        icon: "creditcard",
                        title: "No loans recorded",
                        message: "Add what you owe and to whom. A loan from family at zero "
                               + "interest still costs you something, and this is where that "
                               + "gets counted.",
                        actionTitle: "Add a loan",
                        action: { isCreatingLoan = true }
                    )
                } else {
                    summaryCard
                    strategyCard
                    ForEach(ordered) { position in
                        LoanCard(position: position, formatter: formatter, calendar: calendar,
                                 highInterestThreshold: settings?.highInterestThresholdAPR
                                     ?? Decimal(string: "0.25")!) {
                            selectedLoanID = position.loan.id
                        }
                        .contextMenu {
                            Button("Record a payment…") { payingLoanID = position.loan.id }
                            Button("Schedule and simulator…") {
                                selectedLoanID = position.loan.id
                            }
                        }
                    }
                    if !owedToMe.isEmpty { receivablesCard }
                }
            }
            .padding(Theme.Space.lg)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { isPlanningLoan = true } label: {
                    Label("Thinking about a loan", systemImage: "questionmark.circle")
                }
                .labelStyle(.titleAndIcon)
                Button { isCreatingLoan = true } label: {
                    Label("New loan", systemImage: "plus.circle")
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .sheet(isPresented: $isCreatingLoan) {
            LoanEditor(editingID: nil, formatter: formatter, calendar: calendar)
        }
        .sheet(isPresented: $isPlanningLoan) {
            PlannedLoanView(existingPositions: positions, formatter: formatter,
                            calendar: calendar, settings: settings)
        }
        .sheet(item: Binding(
            get: { selectedLoanID.map { IdentifiedID(id: $0) } },
            set: { selectedLoanID = $0?.id }
        )) { wrapper in
            if let position = positions.first(where: { $0.loan.id == wrapper.id }) {
                LoanDetailSheet(position: position, formatter: formatter,
                                calendar: calendar) {
                    payingLoanID = position.loan.id
                }
            }
        }
        .sheet(item: Binding(
            get: { payingLoanID.map { IdentifiedID(id: $0) } },
            set: { payingLoanID = $0?.id }
        )) { wrapper in
            if let position = positions.first(where: { $0.loan.id == wrapper.id }) {
                LoanPaymentSheet(position: position, formatter: formatter, calendar: calendar)
            }
        }
    }

    private var summaryCard: some View {
        Card(padding: Theme.Space.lg) {
            HStack(alignment: .top, spacing: Theme.Space.lg) {
                StatTile(label: "Owed", value: formatter.string(totalOwed),
                         detail: "\(owed.count) active \(owed.count == 1 ? "loan" : "loans")",
                         accessibilityValue: formatter.accessibleString(totalOwed))
                StatTile(label: "Interest still to pay",
                         value: formatter.string(totalInterestRemaining),
                         detail: "If you keep to the schedule",
                         tone: totalInterestRemaining.isPositive ? .caution : .neutral,
                         accessibilityValue: formatter.accessibleString(totalInterestRemaining))
                StatTile(label: "Monthly debt service",
                         value: formatter.string(monthlyDebtService),
                         detail: debtServiceDetail,
                         tone: debtServiceTone,
                         accessibilityValue: formatter.accessibleString(monthlyDebtService))
            }
        }
    }

    private var debtServiceDetail: String {
        guard let ratio = debtServiceRatio else { return "Set your income to see the ratio" }
        return "\(percent(ratio)) of your monthly income"
    }

    private var debtServiceTone: StatTile.Tone {
        guard let ratio = debtServiceRatio else { return .neutral }
        if ratio > Decimal(string: "0.30")! { return .negative }
        if ratio > Decimal(string: "0.15")! { return .caution }
        return .positive
    }

    private var strategyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Clear them in this order")
                Picker("", selection: $strategy) {
                    ForEach(LoanEngine.PayoffStrategy.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(strategy.explanation)
                    .font(Theme.Font.caption).foregroundStyle(.secondary)

                if let cost = costComparison {
                    Divider().opacity(0.4)
                    Text(cost)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What choosing peace over arithmetic costs, stated plainly — and then you choose.
    private var costComparison: String? {
        guard owed.count > 1 else { return nil }
        let cheapest = LoanEngine.costOfStrategy(.avalanche, positions: positions,
                                                 calendar: calendar)
        let chosen = LoanEngine.costOfStrategy(strategy, positions: positions, calendar: calendar)
        let difference = chosen - cheapest
        if strategy == .avalanche || !difference.isPositive {
            return "This is the cheapest order: \(formatter.string(cheapest)) in interest."
        }
        return "This order costs \(formatter.string(difference)) more in interest than "
             + "Avalanche. Sleeping at night is worth something. Your call."
    }

    private var receivablesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Owed to you")
                ForEach(owedToMe) { position in
                    HStack {
                        Text(position.loan.name).font(.system(size: 12.5))
                        Spacer()
                        Text(formatter.string(position.remainingBalance))
                            .font(Theme.Font.amount).foregroundStyle(.secondary)
                    }
                }
                Text("Recorded at zero expected return and never counted as wealth. Be "
                     + "generous if you want to be — just do not count it as an asset.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func percent(_ value: Decimal) -> String {
        let scaled = Money.roundBankers(value * 10_000)
        return "\(scaled / 100).\(String(format: "%02d", abs(scaled % 100)))%"
    }
}

struct LoanCard: View {
    let position: LoanEngine.Position
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let highInterestThreshold: Decimal
    let onTap: () -> Void

    private var progress: Double {
        let paid = position.loan.principal - position.remainingBalance
        guard position.loan.principal.isPositive else { return 0 }
        return paid.ratio(to: position.loan.principal)
            .map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }

    var body: some View {
        Button(action: onTap) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        Text(position.loan.name).font(.system(size: 13, weight: .medium))
                        if position.isToxic(highInterestThreshold: highInterestThreshold) {
                            Pill(text: "clear this first", tone: .negative,
                                 icon: "exclamationmark.triangle")
                        }
                        if position.loan.socialWeight >= 4 {
                            Pill(text: "family", tone: .caution, icon: "person.2")
                        }
                        Spacer()
                        Text(formatter.string(position.remainingBalance))
                            .font(Theme.Font.figure)
                    }
                    Text("\(position.loan.lender) · \(rateText) · "
                         + "\(position.paymentsMade) of \(position.scheduledPayments) paid")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)

                    MeterBar(fraction: progress, tone: .positive, height: 6)

                    HStack {
                        Text(payoffText).font(Theme.Font.caption).foregroundStyle(.secondary)
                        Spacer()
                        if position.interestRemaining.isPositive {
                            Text("\(formatter.string(position.interestRemaining)) interest left")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.loan.name)
        .accessibilityValue(formatter.accessibleString(position.remainingBalance) + " remaining")
    }

    private var rateText: String {
        switch position.loan.interestModel {
        case .interestFree: "interest-free"
        case let .amortizing(apr): "\(percent(apr)) APR"
        case let .revolving(apr): "\(percent(apr)) revolving"
        case let .flatRate(rate, years): "\(percent(rate))/yr flat over \(years)y"
        }
    }

    private var payoffText: String {
        guard let date = position.payoffDate else { return "No schedule" }
        return "Clear by \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func percent(_ value: Decimal) -> String {
        let scaled = Money.roundBankers(value * 10_000)
        return "\(scaled / 100).\(String(format: "%02d", abs(scaled % 100)))%"
    }
}
