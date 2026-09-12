import SwiftUI
import SwiftData

/// The right-hand panel. Shows whatever is selected, and falls back to a summary
/// rather than sitting empty.
struct InspectorPanel: View {
    @Binding var model: AppModel
    let balances: [BalanceEngine.AccountBalance]
    let transactions: [Transaction]
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    private var selectedAccount: BalanceEngine.AccountBalance? {
        guard let id = model.selectedAccountID else { return nil }
        return balances.first { $0.account.id == id }
    }

    private var selectedTransaction: Transaction? {
        guard let id = model.selectedTransactionID else { return nil }
        return transactions.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if let transaction = selectedTransaction {
                    transactionDetail(transaction)
                } else if let entry = selectedAccount {
                    accountDetail(entry)
                } else {
                    summary
                }
            }
            .padding(Theme.Space.md)
        }
    }

    // MARK: - Account

    private func accountDetail(_ entry: BalanceEngine.AccountBalance) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header(title: entry.account.name, subtitle: entry.account.type.label) {
                model.selectedAccountID = nil
            }

            HStack(spacing: Theme.Space.sm) {
                Button("Reconcile") { model.reconcilingAccountID = entry.account.id }
                Button("Edit") {
                    model.editingAccountID = entry.account.id
                    model.isAccountEditorShown = true
                }
                Spacer()
            }
            .controlSize(.small)

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    row("Balance", formatter.string(entry.balance))
                    row("Earmarked", formatter.string(entry.earmarked))
                    Divider().opacity(0.4)
                    row("Available", formatter.string(entry.available), emphasised: true)
                }
            }

            if entry.isOverCommitted {
                NoticeRow(
                    tone: .caution,
                    icon: "exclamationmark.triangle",
                    title: "Over-committed",
                    detail: "More is earmarked here than the account holds. Nothing has been "
                          + "moved for you — reduce an earmark or move money in."
                )
            }

            if entry.account.isTaxReserve {
                NoticeRow(
                    tone: .caution, icon: "lock",
                    title: "Not your money",
                    detail: "A tax reserve cannot be spent from, holds no goal earmarks, and is "
                          + "excluded from runway and free-to-spend."
                )
            }

            let recent = transactions.filter {
                $0.account?.id == entry.account.id || $0.counterAccount?.id == entry.account.id
            }
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Recent")
                if recent.isEmpty {
                    Text("Nothing logged against this account yet.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                } else {
                    Card(padding: Theme.Space.sm) {
                        VStack(spacing: Theme.Space.xs) {
                            ForEach(recent.prefix(8)) { transaction in
                                TransactionRow(transaction: transaction, formatter: formatter,
                                               calendar: calendar)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transaction

    private func transactionDetail(_ transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header(
                title: transaction.category?.name ?? transaction.note ?? "Transaction",
                subtitle: transaction.kind.rawValue.capitalized
            ) {
                model.selectedTransactionID = nil
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    row("Amount", formatter.string(transaction.amount), emphasised: true)
                    row("Financial day",
                        calendar.financialDay(for: transaction.date)
                            .formatted(date: .abbreviated, time: .omitted))
                    row("Logged at", transaction.date.formatted(date: .omitted, time: .shortened))
                    if transaction.kind == .transfer {
                        row("From", transaction.account?.name ?? "—")
                        row("To", transaction.counterAccount?.name ?? "—")
                    } else {
                        row("Account", transaction.account?.name ?? "—")
                    }
                    if let note = transaction.note { row("Note", note) }
                }
            }

            if transaction.isEstimate {
                NoticeRow(
                    tone: .caution, icon: "questionmark.circle",
                    title: "Logged from memory",
                    detail: "This is an estimate and sits in the needs-review queue until you "
                          + "correct it."
                )
            }

            if transaction.kind == .transfer {
                Text("A transfer is one record, not two. It moves money between your own "
                     + "accounts and never counts as income or spending.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Fallback

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionLabel(text: "Details")
            Text("Select an account or an entry to see it here.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)

            let totals = BalanceEngine.totals(for: balances)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    row("Liquid balance", formatter.string(totals.liquidBalance))
                    row("Earmarked", formatter.string(totals.earmarkedTotal))
                    Divider().opacity(0.4)
                    row("Available", formatter.string(totals.liquidAvailable), emphasised: true)
                    if !totals.taxReserved.isZero {
                        Divider().opacity(0.4)
                        row("Tax reserve", formatter.string(totals.taxReserved))
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func header(title: String, subtitle: String, onClose: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.title).lineLimit(2)
                Text(subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
            .accessibilityLabel("Clear selection")
        }
    }

    private func row(_ label: String, _ value: String, emphasised: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.sm)
            Text(value)
                .font(emphasised ? .system(size: 15, weight: .medium).monospacedDigit()
                                 : Theme.Font.amount)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
