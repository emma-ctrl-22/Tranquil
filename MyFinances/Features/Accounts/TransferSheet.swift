import SwiftUI
import SwiftData

/// Move money between your own accounts. Writes **one** record with a counter account,
/// never two — and it never touches income or expense totals.
struct TransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amountText = ""
    @State private var note = ""
    @FocusState private var isAmountFocused: Bool

    private var available: [Account] { accounts.filter { !$0.isArchived && $0.deletedAt == nil } }
    private var source: Account? { available.first { $0.id == fromID } }
    private var destination: Account? { available.first { $0.id == toID } }
    private var amount: Money? { formatter.parse(amountText) }

    /// A tax reserve cannot be spent from — it is not your money.
    private var blockedByTaxReserve: Bool { source?.isTaxReserve == true }

    private var isValid: Bool {
        guard let amount, amount.isPositive, let source, let destination else { return false }
        return source.id != destination.id && !blockedByTaxReserve
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transfer").font(Theme.Font.title).padding(Theme.Space.lg)
            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TextField("0.00", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .focused($isAmountFocused)
                    .accessibilityLabel("Amount")

                HStack(spacing: Theme.Space.md) {
                    picker("From", selection: $fromID)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    picker("To", selection: $toID)
                }

                TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder)

                if blockedByTaxReserve {
                    NoticeRow(
                        tone: .caution, icon: "lock",
                        title: "You cannot spend from a tax reserve",
                        detail: "That money is set aside for tax. Moving it out defeats the "
                              + "point of holding it."
                    )
                } else if source?.id == destination?.id && source != nil {
                    NoticeRow(tone: .caution, icon: "exclamationmark.triangle",
                              title: "Pick two different accounts",
                              detail: "A transfer needs somewhere to come from and somewhere to go.")
                } else if let amount, amount.isPositive, let source {
                    Text("A transfer moves your own money. It will not count as spending or "
                         + "income, and \(source.name) is debited as \(destination?.name ?? "—") "
                         + "is credited by the same \(formatter.string(amount)).")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.lg)

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Transfer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 460)
        .background(Theme.Palette.surface(scheme))
        .onAppear {
            fromID = fromID ?? available.first { $0.isSpendable }?.id
            toID = toID ?? available.first { $0.id != fromID }?.id
            isAmountFocused = true
        }
    }

    private func picker(_ title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            Picker("", selection: selection) {
                ForEach(available) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .labelsHidden()
        }
    }

    private func save() {
        guard let amount, let source, let destination, isValid else { return }
        let transfer = Transaction(
            date: calendar.currentDate(),
            amount: amount,
            kind: .transfer,
            account: source,
            counterAccount: destination,
            note: note.isEmpty ? nil : note
        )
        context.insert(transfer)
        try? context.save()
        dismiss()
    }
}
