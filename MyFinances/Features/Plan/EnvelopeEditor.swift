import SwiftUI
import SwiftData

/// Create or change an envelope.
///
/// Raising one is a deliberate act: ADVISOR_RULES §4b holds envelopes still when income
/// rises, so an increase asks for a reason and records it.
struct EnvelopeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let editingID: UUID?
    let formatter: MoneyFormatter

    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil })
    private var budgets: [Budget]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var categoryID: UUID?
    @State private var period: BudgetPeriod = .weekly
    @State private var amountText = ""
    @State private var rollover = false
    @State private var raiseReason = ""

    private var existing: Budget? {
        guard let editingID else { return nil }
        return budgets.first { $0.id == editingID }
    }

    private var amount: Money? { formatter.parse(amountText) }

    /// Categories that do not already have an envelope.
    private var availableCategories: [Category] {
        let taken = Set(budgets.compactMap { $0.category?.id })
        return categories.filter { $0.id == categoryID || !taken.contains($0.id) }
    }

    private var isRaise: Bool {
        guard let existing, let amount else { return false }
        return amount > existing.amount && existing.period == period
    }

    private var isValid: Bool {
        guard amount != nil else { return false }
        if isRaise { return !raiseReason.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "New envelope" : "Edit envelope")
                .font(Theme.Font.title)
                .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Category")
                        Picker("", selection: $categoryID) {
                            Text("Miscellaneous (catch-all)").tag(UUID?.none)
                            ForEach(availableCategories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        .labelsHidden()
                        .disabled(existing != nil)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Period")
                        Picker("", selection: $period) {
                            Text("Weekly").tag(BudgetPeriod.weekly)
                            Text("Monthly").tag(BudgetPeriod.monthly)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if period == .monthly {
                            Text("Shown at its weekly pace, so you never have to divide it "
                                 + "in your head.")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Amount")
                        TextField("0.00", text: $amountText).textFieldStyle(.roundedBorder)
                    }

                    Toggle("Carry unspent budget into next week", isOn: $rollover)
                    if rollover {
                        Text("Capped at twice the budget, so quiet weeks do not become a "
                             + "licence to splurge.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }

                    if isRaise {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            NoticeRow(
                                tone: .caution, icon: "arrow.up.circle",
                                title: "You are raising this envelope",
                                detail: "Envelopes do not rise automatically when income does. "
                                      + "Raising one on purpose is fine — it just gets recorded."
                            )
                            TextField("Why are you raising it?", text: $raiseReason)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                if existing != nil {
                    Button("Delete", role: .destructive) { delete() }
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
        .frame(width: 440, height: 520)
        .background(Theme.Palette.surface(scheme))
        .onAppear(perform: load)
    }

    private func load() {
        guard let existing else { return }
        categoryID = existing.category?.id
        period = existing.period
        amountText = formatter.string(existing.amount, style: .bare)
        rollover = existing.rollover
    }

    private func save() {
        guard let amount else { return }
        if let existing {
            if isRaise {
                existing.lastRaisedAt = Date()
                existing.lastRaiseReason = raiseReason
            }
            existing.amount = amount
            existing.period = period
            existing.rollover = rollover
            existing.updatedAt = Date()
        } else {
            let category = categoryID.flatMap { id in categories.first { $0.id == id } }
                ?? categories.first(where: \.isMiscellaneous)
            context.insert(Budget(category: category, period: period,
                                  amount: amount, rollover: rollover))
        }
        try? context.save()
        dismiss()
    }

    /// Soft delete, like everything else.
    private func delete() {
        existing?.deletedAt = Date()
        try? context.save()
        dismiss()
    }
}
