import SwiftUI
import SwiftData

struct RecurringRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let editingID: UUID?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil })
    private var rules: [RecurringRule]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var label = ""
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var counterAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var cadenceKind: RecurringCadenceKind = .monthly
    @State private var dayOfMonth = 1
    @State private var month = 1
    @State private var customDays = 30
    @State private var nextDue = Date()
    @State private var mode: RecurringMode = .remindOnly
    @State private var isVariableAmount = false
    @State private var isCommittedOutflow = true

    private var existing: RecurringRule? {
        guard let editingID else { return nil }
        return rules.first { $0.id == editingID }
    }

    private var amount: Money? { formatter.parse(amountText) }

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && amount != nil
            && accountID != nil
            && (kind != .transfer || (counterAccountID != nil && counterAccountID != accountID))
    }

    private var cadence: RecurringRule.Cadence {
        switch cadenceKind {
        case .weekly: .weekly
        case .biweekly: .biweekly
        case .monthly: .monthly(day: dayOfMonth)
        case .yearly: .yearly(month: month, day: dayOfMonth)
        case .custom: .custom(days: customDays)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "New recurring rule" : "Edit rule")
                .font(Theme.Font.title).padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    field("Label") {
                        TextField("Rent", text: $label).textFieldStyle(.roundedBorder)
                    }

                    field("Kind") {
                        Picker("", selection: $kind) {
                            Text("Out").tag(TransactionKind.expense)
                            Text("In").tag(TransactionKind.income)
                            Text("Transfer").tag(TransactionKind.transfer)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }

                    field("Amount") {
                        TextField("0.00", text: $amountText).textFieldStyle(.roundedBorder)
                    }

                    field(kind == .transfer ? "From" : "Account") {
                        Picker("", selection: $accountID) {
                            ForEach(accounts.filter { !$0.isArchived }) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                    }

                    if kind == .transfer {
                        field("To") {
                            Picker("", selection: $counterAccountID) {
                                ForEach(accounts.filter { !$0.isArchived }) { account in
                                    Text(account.name).tag(Optional(account.id))
                                }
                            }
                            .labelsHidden()
                        }
                    } else {
                        field("Category") {
                            Picker("", selection: $categoryID) {
                                Text("None").tag(UUID?.none)
                                ForEach(categories) { category in
                                    Text(category.name).tag(Optional(category.id))
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    field("Repeats") {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Picker("", selection: $cadenceKind) {
                                Text("Weekly").tag(RecurringCadenceKind.weekly)
                                Text("Fortnightly").tag(RecurringCadenceKind.biweekly)
                                Text("Monthly").tag(RecurringCadenceKind.monthly)
                                Text("Yearly").tag(RecurringCadenceKind.yearly)
                                Text("Custom").tag(RecurringCadenceKind.custom)
                            }
                            .labelsHidden()

                            switch cadenceKind {
                            case .monthly:
                                Stepper("On the \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                                if dayOfMonth > 28 {
                                    Text("Short months use their last day, so this never skips "
                                         + "a month.")
                                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                                }
                            case .yearly:
                                Stepper("Month \(month)", value: $month, in: 1...12)
                                Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                            case .custom:
                                Stepper("Every \(customDays) days", value: $customDays, in: 1...365)
                            default:
                                EmptyView()
                            }
                        }
                    }

                    field("Next due") {
                        DatePicker("", selection: $nextDue, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(maxWidth: 210, alignment: .leading)
                    }

                    Toggle("The amount varies", isOn: $isVariableAmount)
                    if isVariableAmount {
                        Text("Utilities and the like. The date is known, the amount is a "
                             + "guess — it is marked as an estimate in the forecast.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }

                    Toggle("Comes off the top, before free-to-spend", isOn: $isCommittedOutflow)

                    Toggle("Post it automatically on the day", isOn: Binding(
                        get: { mode == .autoPost },
                        set: { mode = $0 ? .autoPost : .remindOnly }
                    ))
                    Text(mode == .autoPost
                         ? "The entry is written on the due date without asking."
                         : "You are reminded and nothing is written until you confirm.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
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
        nextDue = calendar.today()
        accountID = accounts.first { !$0.isArchived }?.id
        guard let existing else { return }
        label = existing.label
        kind = existing.kind
        amountText = formatter.string(existing.amount, style: .bare)
        accountID = existing.account?.id
        counterAccountID = existing.counterAccount?.id
        categoryID = existing.category?.id
        nextDue = existing.nextDueDate
        mode = existing.mode
        isVariableAmount = existing.isVariableAmount
        isCommittedOutflow = existing.isCommittedOutflow
        switch existing.cadence {
        case .weekly: cadenceKind = .weekly
        case .biweekly: cadenceKind = .biweekly
        case let .monthly(day): cadenceKind = .monthly; dayOfMonth = day
        case let .yearly(m, day): cadenceKind = .yearly; month = m; dayOfMonth = day
        case let .custom(days): cadenceKind = .custom; customDays = days
        }
    }

    private func save() {
        guard let amount, let accountID else { return }
        let account = accounts.first { $0.id == accountID }
        let counter = counterAccountID.flatMap { id in accounts.first { $0.id == id } }
        let category = categoryID.flatMap { id in categories.first { $0.id == id } }

        if let existing {
            // Keep the previous amount so a salary rise can be detected and its delta
            // allocated per ADVISOR_RULES §4b, rather than becoming a new baseline.
            if existing.kind == .income && amount != existing.amount {
                existing.previousAmount = existing.amount
            }
            existing.label = label
            existing.kind = kind
            existing.amount = amount
            existing.account = account
            existing.counterAccount = kind == .transfer ? counter : nil
            existing.category = kind == .transfer ? nil : category
            existing.cadence = cadence
            existing.nextDueDate = calendar.financialDay(for: nextDue)
            existing.mode = mode
            existing.isVariableAmount = isVariableAmount
            existing.isCommittedOutflow = isCommittedOutflow
            existing.updatedAt = Date()
        } else {
            context.insert(RecurringRule(
                label: label, kind: kind, amount: amount, account: account,
                counterAccount: kind == .transfer ? counter : nil,
                category: kind == .transfer ? nil : category,
                cadence: cadence, nextDueDate: calendar.financialDay(for: nextDue),
                mode: mode, isVariableAmount: isVariableAmount,
                isCommittedOutflow: isCommittedOutflow
            ))
        }
        try? context.save()
        dismiss()
    }
}
