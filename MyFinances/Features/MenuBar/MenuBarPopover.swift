import SwiftUI
import SwiftData
import AppKit

/// The popover behind the menu bar icon. This is the app's front door: quick capture,
/// today's total, what is free to spend, and the logging streak.
///
/// Everything here is built for speed. The field is focused on open, Return commits,
/// and the row clears itself so five spends take one pass.
struct MenuBarPopover: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.sortOrder)
    private var categories: [Category]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil },
           sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]
    @Query(filter: #Predicate<DailyLog> { $0.deletedAt == nil },
           sort: \DailyLog.date, order: .reverse)
    private var dailyLogs: [DailyLog]
    @Query private var settingsRows: [AppSettings]

    @State private var entry = ""
    @State private var lastSaved: (id: UUID, label: String)?
    @State private var selectedAccountID: UUID?
    @FocusState private var isFocused: Bool

    private var settings: AppSettings? { settingsRows.first }
    private var formatter: MoneyFormatter { settings?.formatter ?? MoneyFormatter(currency: .ghs) }
    private var calendar: FinancialCalendar { settings?.calendar ?? FinancialCalendar() }

    private var parser: QuickParser {
        QuickParser(
            formatter: formatter,
            vocabulary: QuickParser.Vocabulary(
                categories: categories.map { .init(id: $0.id, name: $0.name) },
                accounts: accounts.filter(\.isSpendable).map { .init(id: $0.id, name: $0.name) }
            )
        )
    }

    private var parsed: QuickParser.Result { parser.parse(entry) }

    private var balances: [BalanceEngine.AccountBalance] {
        BalanceEngine.balances(
            accounts: accounts.map(DataBridge.record),
            transactions: transactions.map(DataBridge.record),
            earmarks: earmarks.map(DataBridge.record)
        )
    }

    private var todaysSpend: Money {
        BalanceEngine.spend(
            transactions: transactions.map(DataBridge.record),
            in: calendar.financialDayInterval(containing: calendar.currentDate())
        )
    }

    private var streak: Int {
        DailyLogService.currentStreak(logs: dailyLogs, today: calendar.today(), calendar: calendar)
    }

    private var microCategories: [Category] { Array(categories.filter(\.isMicro).prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            captureField
            Divider().opacity(0.5)
            if !microCategories.isEmpty {
                chips
                Divider().opacity(0.5)
            }
            summary
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 320)
        .onAppear {
            isFocused = true
            selectedAccountID = selectedAccountID ?? accounts.first(where: \.isSpendable)?.id
        }
    }

    // MARK: - Capture

    private var captureField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TextField("trotro 5", text: $entry)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light, design: .rounded))
                .focused($isFocused)
                .onSubmit(save)
                .accessibilityLabel("Quick capture")

            Text(previewText)
                .font(Theme.Font.caption)
                .foregroundStyle(parsed.isComplete ? .secondary : .tertiary)
                .lineLimit(1)
        }
        .padding(Theme.Space.md)
    }

    /// Shows exactly what will be saved. No surprises on Return.
    private var previewText: String {
        guard let amount = parsed.amount, amount.isPositive else {
            return "Amount, then what it was."
        }
        let direction = parsed.kind == .income ? "In" : "Out"
        let category = parsed.categoryID
            .flatMap { id in categories.first { $0.id == id }?.name }
            ?? "Miscellaneous"
        let account = resolvedAccount?.name ?? "no account"
        let review = parsed.isUnclassified ? " · needs review" : ""
        return "\(direction) \(formatter.string(amount)) · \(category) · \(account)\(review)"
    }

    private var resolvedAccount: Account? {
        if let id = parsed.accountID { return accounts.first { $0.id == id } }
        if let id = selectedAccountID { return accounts.first { $0.id == id } }
        return accounts.first(where: \.isSpendable)
    }

    private var chips: some View {
        FlowRow(spacing: Theme.Space.xs) {
            ForEach(microCategories) { category in
                Button {
                    // One tap prefills the category and its last amount.
                    let amount = category.lastAmount.map { formatter.string($0, style: .bare) } ?? ""
                    entry = "\(amount) \(category.name)".trimmingCharacters(in: .whitespaces)
                    isFocused = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: category.icon).font(.system(size: 8))
                        Text(category.name).font(.system(size: 11))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.Palette.raised(scheme))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(category.lastAmount.map { "Last: \(formatter.string($0))" } ?? category.name)
            }
        }
        .padding(Theme.Space.md)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            figure("Today", formatter.string(todaysSpend))
            figure("Available", formatter.string(BalanceEngine.totals(for: balances).liquidAvailable))
            figure("Streak", streak == 0 ? "—" : "\(streak)d")
        }
        .padding(Theme.Space.md)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .regular, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.sm) {
            if let lastSaved {
                Text("Saved \(lastSaved.label)").font(Theme.Font.caption).foregroundStyle(.secondary)
                Button("Undo") { undo(lastSaved.id) }
                    .font(Theme.Font.caption).buttonStyle(.link)
            } else {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows
                        .first { $0.identifier?.rawValue.contains("main") == true }?
                        .makeKeyAndOrderFront(nil)
                } label: {
                    Text("Open Tranquil").font(Theme.Font.caption)
                }
                .buttonStyle(.link)
            }
            Spacer()
            Button("Save", action: save)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!parsed.isComplete)
        }
        .padding(Theme.Space.md)
    }

    // MARK: - Actions

    private func save() {
        guard let amount = parsed.amount, amount.isPositive,
              let account = resolvedAccount else { return }

        let category = parsed.categoryID.flatMap { id in categories.first { $0.id == id } }
            ?? categories.first(where: \.isMiscellaneous)

        let transaction = Transaction(
            date: calendar.currentDate(),
            amount: amount,
            kind: parsed.kind,
            account: account,
            category: category,
            note: parsed.note,
            // "I spent something, not sure what" goes to Miscellaneous for review.
            isEstimate: parsed.isUnclassified
        )
        context.insert(transaction)
        category?.lastAmount = amount
        DailyLogService.recordEntry(on: transaction.date, in: context, calendar: calendar)

        // Same interception as the main window: a windfall does not join spendable
        // balance just because it was logged from the menu bar.
        if parsed.kind == .income, let settings {
            let records = transactions.map(DataBridge.record)
            let weeks = (1...8).map { offset -> Money in
                let start = calendar.addDays(-7 * offset, to: calendar.today())
                return BalanceEngine.income(
                    transactions: records,
                    in: DateInterval(start: start, end: calendar.addDays(7, to: start))
                )
            }
            let median = BudgetEngine.medianWeeklyIncome(trailingWeeks: weeks)
            if IncomeEventService.shouldIntercept(amount: amount, kind: .projectPayment,
                                                  settings: settings,
                                                  medianWeeklyIncome: median) {
                let event = IncomeEvent(
                    kind: .projectPayment, receivedAt: transaction.date, grossAmount: amount,
                    taxReserved: IncomeEngine.taxReserve(on: amount,
                                                         rate: settings.taxReserveRate,
                                                         kind: .projectPayment),
                    clientOrSource: parsed.note, account: account
                )
                event.transactionID = transaction.id
                transaction.incomeEventID = event.id
                context.insert(event)
            }
        }

        try? context.save()
        WidgetSnapshotWriter.refresh(container: AppEnvironment.container)

        lastSaved = (transaction.id, formatter.string(amount))
        entry = ""
        isFocused = true

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if lastSaved?.id == transaction.id { lastSaved = nil }
        }
    }

    private func undo(_ id: UUID) {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        if let transaction = try? context.fetch(descriptor).first {
            transaction.deletedAt = calendar.currentDate()
            try? context.save()
        }
        lastSaved = nil
        isFocused = true
    }
}
