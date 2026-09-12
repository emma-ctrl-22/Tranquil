import SwiftUI
import SwiftData

/// The modal that has to be fast. Logging a bus fare must take under three seconds,
/// so this opens focused, accepts one line of text, and commits on Return.
///
/// The full one-line parser, the global hotkey and batch mode are M2. This is the
/// shape they will land in.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.sortOrder)
    private var categories: [Category]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil })
    private var transactions: [Transaction]
    @Query private var settingsRows: [AppSettings]

    @State private var entry = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var kind: TransactionKind = .expense
    @State private var isEstimate = false
    @State private var justSaved: String?
    @FocusState private var isFieldFocused: Bool

    private var microCategories: [Category] { categories.filter(\.isMicro).prefix(6).map { $0 } }
    private var spendableAccounts: [Account] { accounts.filter { $0.isSpendable } }

    private var parsedAmount: Money? { formatter.parse(amountToken) }

    /// The first token that parses as a number is the amount; the rest is the note.
    private var amountToken: String {
        entry.split(separator: " ").first { formatter.parse(String($0)) != nil }.map(String.init) ?? ""
    }

    private var noteToken: String {
        entry.split(separator: " ")
            .filter { formatter.parse(String($0)) == nil }
            .joined(separator: " ")
    }

    /// A keyword in the line can name a category, so "trotro 5" needs no tapping.
    private var inferredCategory: Category? {
        if let id = selectedCategoryID { return categories.first { $0.id == id } }
        let needle = noteToken.lowercased()
        guard !needle.isEmpty else { return nil }
        return categories.first { needle.contains($0.name.lowercased()) }
    }

    private var resolvedAccount: Account? {
        if let id = selectedAccountID { return accounts.first { $0.id == id } }
        return inferredCategory?.defaultAccount ?? spendableAccounts.first
    }

    private var canSave: Bool {
        guard let amount = parsedAmount else { return false }
        return amount.isPositive && resolvedAccount != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            Divider().opacity(0.5)
            options
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 460)
        .background(Theme.Palette.surface(scheme))
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Field

    private var field: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            TextField("trotro 5", text: $entry)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .light, design: .rounded))
                .focused($isFieldFocused)
                .onSubmit { save() }
                .accessibilityLabel("Amount and note")

            HStack(spacing: Theme.Space.sm) {
                if let amount = parsedAmount, amount.isPositive {
                    Text(preview)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Type an amount, and a word for what it was.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Theme.Space.lg)
    }

    /// Live preview of exactly what will be written. No surprises on Return.
    private var preview: String {
        guard let amount = parsedAmount else { return "" }
        let verb = kind == .income ? "In" : "Out"
        let category = inferredCategory?.name ?? "Miscellaneous"
        let account = resolvedAccount?.name ?? "no account"
        return "\(verb) \(formatter.string(amount)) · \(category) · \(account)"
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if !microCategories.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Quick")
                    FlowRow(spacing: Theme.Space.xs) {
                        ForEach(microCategories) { category in
                            chip(category)
                        }
                    }
                }
            }

            HStack(spacing: Theme.Space.md) {
                Picker("Account", selection: Binding(
                    get: { selectedAccountID ?? resolvedAccount?.id },
                    set: { selectedAccountID = $0 }
                )) {
                    ForEach(spendableAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .frame(maxWidth: 200)

                Picker("", selection: $kind) {
                    Text("Out").tag(TransactionKind.expense)
                    Text("In").tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
            }

            Toggle("Not sure — log as an estimate", isOn: $isEstimate)
                .font(Theme.Font.caption)
                .toggleStyle(.checkbox)
        }
        .padding(Theme.Space.lg)
    }

    private func chip(_ category: Category) -> some View {
        let isSelected = inferredCategory?.id == category.id
        return Button {
            selectedCategoryID = isSelected ? nil : category.id
            // Tapping a chip prefills its last amount, so a repeat spend is one tap.
            if !isSelected, entry.isEmpty, let last = category.lastAmount {
                entry = formatter.string(last, style: .bare)
            }
            isFieldFocused = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.icon).font(.system(size: 9))
                Text(category.name).font(.system(size: 11.5))
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Theme.Palette.accent : .primary)
            .background(isSelected ? Theme.Palette.accentSoft : Theme.Palette.raised(scheme))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let justSaved {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.positive)
                    Text(justSaved).font(Theme.Font.caption).foregroundStyle(.secondary)
                    Button("Undo", action: undo)
                        .font(Theme.Font.caption)
                        .buttonStyle(.link)
                }
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(Theme.Space.md)
    }

    // MARK: - Actions

    private func save() {
        guard let amount = parsedAmount, amount.isPositive,
              let account = resolvedAccount else { return }

        let category = inferredCategory ?? categories.first(where: \.isMiscellaneous)
        let transaction = Transaction(
            date: calendar.currentDate(),
            amount: amount,
            kind: kind,
            account: account,
            category: kind == .transfer ? nil : category,
            note: noteToken.isEmpty ? nil : noteToken,
            isEstimate: isEstimate || category?.isMiscellaneous == true && inferredCategory == nil
        )
        context.insert(transaction)
        category?.lastAmount = amount
        DailyLogService.recordEntry(on: transaction.date, in: context, calendar: calendar)

        // A large inflow is intercepted rather than quietly joining spendable balance.
        if kind == .income, let settings = settingsRows.first,
           IncomeEventService.shouldIntercept(amount: amount, kind: .projectPayment,
                                              settings: settings,
                                              medianWeeklyIncome: medianWeeklyIncome) {
            let event = IncomeEvent(
                kind: .projectPayment, receivedAt: transaction.date, grossAmount: amount,
                taxReserved: IncomeEngine.taxReserve(on: amount, rate: settings.taxReserveRate,
                                                     kind: .projectPayment),
                clientOrSource: noteToken.isEmpty ? nil : noteToken, account: account
            )
            event.transactionID = transaction.id
            transaction.incomeEventID = event.id
            context.insert(event)
        }

        try? context.save()
        WidgetSnapshotWriter.refresh(container: AppEnvironment.container)

        model.lastSaved = (transaction.id, formatter.string(amount))
        justSaved = "Saved \(formatter.string(amount))"

        // Batch mode: the field clears and stays focused so five spends take one pass.
        entry = ""
        selectedCategoryID = nil
        isEstimate = false
        isFieldFocused = true
    }

    /// Soft delete, within the five-second window. Nothing is ever hard-deleted.
    /// The trailing eight weeks of logged income, as a median. Zero until there is
    /// history, which is what stops the very first entry being intercepted.
    private var medianWeeklyIncome: Money {
        let records = transactions.map(DataBridge.record)
        let today = calendar.today()
        let weeks = (1...8).map { offset -> Money in
            let start = calendar.addDays(-7 * offset, to: today)
            return BalanceEngine.income(
                transactions: records,
                in: DateInterval(start: start, end: calendar.addDays(7, to: start))
            )
        }
        return BudgetEngine.medianWeeklyIncome(trailingWeeks: weeks)
    }

    private func undo() {
        guard let saved = model.lastSaved else { return }
        let id = saved.id
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        if let transaction = try? context.fetch(descriptor).first {
            transaction.deletedAt = calendar.currentDate()
            try? context.save()
        }
        model.lastSaved = nil
        justSaved = nil
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
