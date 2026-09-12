import SwiftUI
import SwiftData

/// Record a payment against a loan.
///
/// Writes **both** a `LoanPayment` (which reduces the balance) and a `Transaction`
/// (which leaves the account), linked to each other, so the money is accounted for
/// once in each place and the history survives the loan being cleared.
struct LoanPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let position: LoanEngine.Position
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    /// Pre-fills from a windfall when a payment is being made out of one.
    var prefilledAmount: Money?

    @Query(filter: #Predicate<Loan> { $0.deletedAt == nil }) private var loans: [Loan]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var isLate = false
    @State private var note = ""
    @FocusState private var isAmountFocused: Bool

    private var loan: Loan? { loans.first { $0.id == position.loan.id } }
    private var amount: Money { formatter.parse(amountText) ?? .zero }

    /// Interest owed on the balance for one period; the rest reduces the principal.
    private var interestPortion: Money {
        let rate = position.loan.periodicRate
        guard rate > 0 else { return .zero }
        let owed = Money(minorUnits: Money.roundBankers(
            position.remainingBalance.decimalMinorUnits * rate
        ))
        return Money.min(owed, amount)
    }

    private var principalPortion: Money { amount - interestPortion }
    private var balanceAfter: Money { (position.remainingBalance - principalPortion).clampedToZero }
    private var clearsLoan: Bool { amount.isPositive && balanceAfter.isZero }

    private var isValid: Bool { amount.isPositive && accountID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pay \(position.loan.name)").font(Theme.Font.title)
                Text("\(formatter.string(position.remainingBalance)) outstanding to "
                     + position.loan.lender)
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    field("Amount") {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            TextField("0.00", text: $amountText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isAmountFocused)
                            HStack(spacing: Theme.Space.sm) {
                                Button("Scheduled "
                                       + formatter.string(position.regularPayment)) {
                                    amountText = formatter.string(position.regularPayment,
                                                                  style: .bare)
                                }
                                Button("Clear it — "
                                       + formatter.string(position.remainingBalance
                                                          + interestOnFullBalance)) {
                                    amountText = formatter.string(
                                        position.remainingBalance + interestOnFullBalance,
                                        style: .bare
                                    )
                                }
                                Spacer()
                            }
                            .controlSize(.small)
                        }
                    }

                    field("Paid from") {
                        Picker("", selection: $accountID) {
                            ForEach(accounts.filter(\.isSpendable)) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                    }

                    field("When") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Toggle("This payment was late", isOn: $isLate)
                    field("Note") {
                        TextField("Optional", text: $note).textFieldStyle(.roundedBorder)
                    }

                    if amount.isPositive {
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                SectionLabel(text: "What this payment does")
                                row("Off the principal", formatter.string(principalPortion))
                                if interestPortion.isPositive {
                                    row("Interest", formatter.string(interestPortion))
                                }
                                Divider().opacity(0.4)
                                row("Balance after", formatter.string(balanceAfter),
                                    emphasised: true)
                                Text("It also leaves "
                                     + (accounts.first { $0.id == accountID }?.name ?? "the account")
                                     + " as a transaction, so the money is accounted for on "
                                     + "both sides.")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if clearsLoan {
                        NoticeRow(
                            tone: .positive, icon: "checkmark.seal",
                            title: "This clears the loan",
                            detail: "It will be marked paid and drop out of the payoff order. "
                                  + "Nothing is deleted — the loan and every payment stay in "
                                  + "your records."
                        )
                    }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(clearsLoan ? "Pay and clear" : "Record payment") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 480, height: 620)
        .background(Theme.Palette.surface(scheme))
        .onAppear {
            date = calendar.today()
            accountID = position.loan.id == nil ? nil : (loan?.account?.id
                        ?? accounts.first(where: \.isSpendable)?.id)
            if let prefilledAmount {
                amountText = formatter.string(prefilledAmount, style: .bare)
            }
            isAmountFocused = true
        }
    }

    /// One period's interest on the whole outstanding balance, for the "clear it" figure.
    private var interestOnFullBalance: Money {
        let rate = position.loan.periodicRate
        guard rate > 0 else { return .zero }
        return Money(minorUnits: Money.roundBankers(
            position.remainingBalance.decimalMinorUnits * rate
        ))
    }

    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            content()
        }
    }

    private func row(_ label: String, _ value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasised ? .system(size: 15, weight: .medium).monospacedDigit()
                                 : Theme.Font.amount)
        }
    }

    private func save() {
        guard let loan, amount.isPositive,
              let account = accounts.first(where: { $0.id == accountID }) else { return }
        let when = calendar.financialDay(for: date)

        // The money leaving the account.
        let transaction = Transaction(
            date: when, amount: amount, kind: .expense, account: account,
            note: note.isEmpty ? "\(loan.name) payment" : note
        )
        transaction.loanID = loan.id
        context.insert(transaction)

        // The debt going down.
        let payment = LoanPayment(
            loan: loan, date: when, amount: amount,
            principalPortion: principalPortion, interestPortion: interestPortion,
            isLate: isLate, scheduledDate: position.schedule.instalments
                .first { $0.date >= when }?.date,
            transactionID: transaction.id
        )
        context.insert(payment)

        if balanceAfter.isZero { loan.status = .paid }
        loan.updatedAt = calendar.currentDate()

        DailyLogService.recordEntry(on: when, in: context, calendar: calendar)
        try? context.save()
        dismiss()
    }
}
