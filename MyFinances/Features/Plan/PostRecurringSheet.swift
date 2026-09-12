import SwiftUI
import SwiftData

/// Turn a due recurring rule into a real entry, and roll it on to its next date.
///
/// Rules default to remind-only for a reason: a bill you were reminded about but did not
/// actually pay should not appear in the ledger as though you had.
struct PostRecurringSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let rule: RecurringRule
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @State private var amountText = ""
    @State private var date = Date()
    @FocusState private var isAmountFocused: Bool

    private var amount: Money { formatter.parse(amountText) ?? .zero }
    private var isValid: Bool { amount.isPositive }

    private var verb: String {
        switch rule.kind {
        case .income: "Received"
        case .transfer: "Moved"
        case .expense: "Paid"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(verb): \(rule.label)").font(Theme.Font.title)
                Text("Due \(rule.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "Amount")
                    TextField("0.00", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAmountFocused)
                    if rule.isVariableAmount {
                        Text("This one varies, so the figure below is only the last one. "
                             + "Put in what it actually came to.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "When")
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: 210, alignment: .leading)
                }

                Text("This writes one entry"
                     + (rule.kind == .transfer
                        ? " moving the money between your own accounts"
                        : " against \(rule.account?.name ?? "the account")")
                     + ", then moves \(rule.label) on to its next date.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.lg)

            Divider().opacity(0.5)
            HStack {
                Button("Skip this one") { rollForward(); dismiss() }
                    .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Record it") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 440)
        .background(Theme.Palette.surface(scheme))
        .onAppear {
            amountText = formatter.string(rule.amount, style: .bare)
            date = calendar.financialDay(for: rule.nextDueDate)
            isAmountFocused = true
        }
    }

    private func save() {
        guard amount.isPositive else { return }
        let when = calendar.financialDay(for: date)
        let transaction = Transaction(
            date: when, amount: amount, kind: rule.kind,
            account: rule.account,
            counterAccount: rule.kind == .transfer ? rule.counterAccount : nil,
            category: rule.kind == .transfer ? nil : rule.category,
            note: rule.label
        )
        transaction.recurringRuleID = rule.id
        context.insert(transaction)

        // A variable bill learns its latest figure, so the next reminder is closer.
        if rule.isVariableAmount { rule.amount = amount }

        DailyLogService.recordEntry(on: when, in: context, calendar: calendar)
        rollForward()
        dismiss()
    }

    /// Moves the rule to its next occurrence. Month-end clamps rather than skipping.
    private func rollForward() {
        if let next = ForecastEngine.advance(calendar.financialDay(for: rule.nextDueDate),
                                             by: rule.cadence, calendar: calendar) {
            rule.nextDueDate = next
        }
        rule.updatedAt = calendar.currentDate()
        try? context.save()
    }
}
