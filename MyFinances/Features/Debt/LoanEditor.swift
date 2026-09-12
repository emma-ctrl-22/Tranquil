import SwiftUI
import SwiftData

struct LoanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let editingID: UUID?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Loan> { $0.deletedAt == nil }) private var loans: [Loan]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var name = ""
    @State private var lender = ""
    @State private var direction: LoanDirection = .iOwe
    @State private var principalText = ""
    @State private var interestKind: LoanInterestKind = .interestFree
    @State private var rateText = "0"
    @State private var months = 12
    @State private var frequency: PaymentFrequency = .monthly
    @State private var socialWeight = 0
    @State private var startDate = Date()
    @State private var accountID: UUID?
    @State private var notes = ""

    private var existing: Loan? {
        guard let editingID else { return nil }
        return loans.first { $0.id == editingID }
    }

    private var principal: Money? { formatter.parse(principalText) }
    private var rate: Decimal {
        (Decimal(string: rateText.trimmingCharacters(in: .whitespaces)) ?? 0) / 100
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (principal?.isPositive ?? false)
    }

    private var interestModel: Loan.InterestModel {
        switch interestKind {
        case .amortizing: .amortizing(apr: rate)
        case .revolving: .revolving(apr: rate)
        case .flatRate: .flatRate(rate: rate, years: Swift.max(1, months / 12))
        case .interestFree: .interestFree
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "New loan" : "Edit loan")
                .font(Theme.Font.title).padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    field("What is it") {
                        TextField("Laptop financing", text: $name).textFieldStyle(.roundedBorder)
                    }
                    field("Who") {
                        TextField("Lender or person", text: $lender)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("Direction") {
                        Picker("", selection: $direction) {
                            Text("I owe it").tag(LoanDirection.iOwe)
                            Text("Owed to me").tag(LoanDirection.owedToMe)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    if direction == .owedToMe {
                        Text("Recorded at zero expected return and kept out of net worth. "
                             + "Be generous if you want to be — just do not count it as wealth.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    field("Amount") {
                        TextField("0.00", text: $principalText).textFieldStyle(.roundedBorder)
                    }
                    field("Interest") {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Picker("", selection: $interestKind) {
                                Text("None").tag(LoanInterestKind.interestFree)
                                Text("Reducing").tag(LoanInterestKind.amortizing)
                                Text("Flat").tag(LoanInterestKind.flatRate)
                                Text("Revolving").tag(LoanInterestKind.revolving)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            if interestKind != .interestFree {
                                HStack {
                                    TextField("0", text: $rateText)
                                        .textFieldStyle(.roundedBorder).frame(width: 80)
                                    Text("% a year").font(Theme.Font.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    field("Term") {
                        Stepper("\(months) months", value: $months, in: 1...240)
                    }
                    field("Paid") {
                        Picker("", selection: $frequency) {
                            Text("Weekly").tag(PaymentFrequency.weekly)
                            Text("Fortnightly").tag(PaymentFrequency.biweekly)
                            Text("Monthly").tag(PaymentFrequency.monthly)
                            Text("Quarterly").tag(PaymentFrequency.quarterly)
                        }
                        .labelsHidden()
                    }
                    field("Started") {
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    if direction == .iOwe {
                        field("How much it weighs on you") {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Picker("", selection: $socialWeight) {
                                    ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                                }
                                .pickerStyle(.segmented).labelsHidden()
                                Text(socialWeight >= 4
                                     ? "Money owed to people you know. The Peace of mind order "
                                       + "clears this first, whatever the arithmetic says."
                                     : "0 is a faceless lender, 5 is family.")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                if existing != nil {
                    Button("Delete", role: .destructive) {
                        existing?.deletedAt = Date()
                        try? context.save()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 460, height: 640)
        .background(Theme.Palette.surface(scheme))
        .onAppear(perform: load)
    }

    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            content()
        }
    }

    private func load() {
        startDate = calendar.today()
        accountID = accounts.first?.id
        guard let existing else { return }
        name = existing.name
        lender = existing.lender
        direction = existing.direction
        principalText = formatter.string(existing.principal, style: .bare)
        months = existing.termMonths
        frequency = existing.paymentFrequency
        socialWeight = existing.socialWeight
        startDate = existing.startDate
        accountID = existing.account?.id
        notes = existing.notes ?? ""
        switch existing.interestModel {
        case .interestFree: interestKind = .interestFree
        case let .amortizing(apr): interestKind = .amortizing; rateText = percentText(apr)
        case let .revolving(apr): interestKind = .revolving; rateText = percentText(apr)
        case let .flatRate(rate, _): interestKind = .flatRate; rateText = percentText(rate)
        }
    }

    private func percentText(_ value: Decimal) -> String {
        "\(Money.roundBankers(value * 10_000) / 100)"
    }

    private func save() {
        guard let principal else { return }
        let account = accountID.flatMap { id in accounts.first { $0.id == id } }
        if let existing {
            existing.name = name
            existing.lender = lender
            existing.direction = direction
            existing.principal = principal
            existing.interestModel = interestModel
            existing.termMonths = months
            existing.paymentFrequency = frequency
            existing.socialWeight = socialWeight
            existing.startDate = calendar.financialDay(for: startDate)
            existing.account = account
            existing.notes = notes.isEmpty ? nil : notes
            existing.updatedAt = Date()
        } else {
            let loan = Loan(
                name: name, lender: lender, direction: direction, principal: principal,
                interestModel: interestModel,
                startDate: calendar.financialDay(for: startDate), termMonths: months,
                paymentFrequency: frequency, socialWeight: socialWeight,
                account: account, notes: notes.isEmpty ? nil : notes
            )
            let schedule = LoanEngine.schedule(for: DataBridge.loan(loan), calendar: calendar)
            loan.scheduledPayment = schedule.regularPayment
            context.insert(loan)
        }
        try? context.save()
        dismiss()
    }
}
