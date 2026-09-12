import SwiftUI
import SwiftData

/// Count the real money, tell the app, and let it close the gap with a single,
/// visible "Unaccounted" entry. The ledger is never silently rewritten.
struct ReconcileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let entry: BalanceEngine.AccountBalance
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil })
    private var accounts: [Account]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil })
    private var categories: [Category]

    @State private var actualText = ""
    @FocusState private var isFocused: Bool

    private var actual: Money? { formatter.parse(actualText) }

    private var reconciliation: BalanceEngine.Reconciliation? {
        guard let actual else { return nil }
        return BalanceEngine.reconcile(derived: entry.balance, actual: actual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reconcile \(entry.account.name)").font(Theme.Font.title)
                Text("Count what is actually there, and enter it.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Ledger says")
                        Text(formatter.string(entry.balance)).font(Theme.Font.figure)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Actually there")
                        TextField("0.00", text: $actualText)
                            .textFieldStyle(.plain)
                            .font(Theme.Font.figure)
                            .focused($isFocused)
                            .frame(width: 140)
                            .accessibilityLabel("Real balance")
                    }
                }

                if let reconciliation {
                    Divider().opacity(0.4)
                    if reconciliation.isClean {
                        NoticeRow(
                            tone: .positive, icon: "checkmark.circle",
                            title: "It matches",
                            detail: "Nothing to adjust. Today will be marked reconciled."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            HStack {
                                Text("Gap").font(Theme.Font.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(formatter.string(reconciliation.gap, style: .signed))
                                    .font(Theme.Font.figure)
                                    .foregroundStyle(reconciliation.gap.isNegative
                                                     ? Theme.Palette.negative
                                                     : Theme.Palette.positive)
                            }
                            Text(explanation(reconciliation))
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(Theme.Space.lg)

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(reconciliation?.isClean == true ? "Mark reconciled" : "Post adjustment") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(actual == nil)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 460)
        .background(Theme.Palette.surface(scheme))
        .onAppear { isFocused = true }
    }

    private func explanation(_ reconciliation: BalanceEngine.Reconciliation) -> String {
        let amount = formatter.string(reconciliation.adjustmentAmount)
        if reconciliation.gap.isNegative {
            return "There is \(amount) less than the ledger expects — spending that was never "
                 + "logged. One “Unaccounted” expense of \(amount) will be posted so the "
                 + "balance is honest. It stays visible in the ledger."
        }
        return "There is \(amount) more than the ledger expects — income that was never logged. "
             + "One “Unaccounted” entry of \(amount) will be posted. It stays visible in the ledger."
    }

    private func save() {
        guard let reconciliation else { return }
        let account = accounts.first { $0.id == entry.account.id }

        if !reconciliation.isClean, let account {
            let adjustment = Transaction(
                date: calendar.currentDate(),
                amount: reconciliation.adjustmentAmount,
                kind: reconciliation.adjustmentKind,
                account: account,
                category: categories.first(where: \.isMiscellaneous),
                note: "Unaccounted — reconciled",
                isEstimate: true
            )
            adjustment.isReconciliationAdjustment = true
            context.insert(adjustment)
        }

        // Record that today was reconciled, for the 14-day nag and the heatmap.
        DailyLogService.markReconciled(on: calendar.currentDate(), in: context, calendar: calendar)

        try? context.save()
        dismiss()
    }
}
