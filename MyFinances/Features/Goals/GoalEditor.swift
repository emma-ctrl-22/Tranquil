import SwiftUI
import SwiftData

struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let editingID: UUID?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil }, sort: \Goal.priorityRank)
    private var goals: [Goal]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]
    @Query private var settingsRows: [AppSettings]

    @State private var name = ""
    @State private var targetText = ""
    @State private var holdingAccountID: UUID?
    @State private var capText = ""
    @State private var desireLevel = 3
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var setAsideText = ""
    @State private var isMarkingPurchased = false
    @State private var pricePaidText = ""

    private var existing: Goal? {
        guard let editingID else { return nil }
        return goals.first { $0.id == editingID }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var target: Money? { formatter.parse(targetText) }

    /// Suggest the best liquid home that is not the daily spending account.
    private var suggestedAccounts: [Account] {
        accounts.filter { $0.isSpendable && $0.isLiquid }
            .sorted { a, b in
                if a.type == .savings && b.type != .savings { return true }
                if b.type == .savings && a.type != .savings { return false }
                return a.sortOrder < b.sortOrder
            }
    }

    private var saved: Money {
        guard let existing else { return .zero }
        return Money.sum(earmarks.filter { $0.ownerID == existing.id }.map(\.amount))
    }

    /// Anything above the threshold waits seven days before it can be bought without
    /// a confirmation.
    private var coolOffRemaining: Int? {
        guard let existing, let settings,
              existing.targetAmount >= settings.coolOffThreshold else { return nil }
        let elapsed = calendar.daysBetween(existing.createdAt, calendar.today())
        return elapsed >= 7 ? nil : 7 - elapsed
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (target?.isPositive ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "New goal" : "Edit goal")
                .font(Theme.Font.title).padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    field("What is it") {
                        TextField("iPhone 15", text: $name).textFieldStyle(.roundedBorder)
                    }
                    field("Price") {
                        TextField("0.00", text: $targetText).textFieldStyle(.roundedBorder)
                    }
                    if existing != nil {
                        Text("You check the price yourself — this app never goes online. "
                             + "Update it when you see it change.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    field("Where the money sits while you save") {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Picker("", selection: $holdingAccountID) {
                                ForEach(suggestedAccounts) { account in
                                    Text(account.name).tag(Optional(account.id))
                                }
                            }
                            .labelsHidden()
                            Text("The money is earmarked inside that account, not moved to a "
                                 + "separate balance. It still shows in the account; it just "
                                 + "stops counting as available.")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if existing != nil {
                        field("Set aside so far") {
                            HStack {
                                TextField(formatter.string(saved, style: .bare),
                                          text: $setAsideText)
                                    .textFieldStyle(.roundedBorder).frame(width: 120)
                                Text("currently \(formatter.string(saved))")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    field("Most per month") {
                        HStack {
                            TextField("No cap", text: $capText)
                                .textFieldStyle(.roundedBorder).frame(width: 120)
                            Text("stops one goal taking everything")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                    }

                    field("How much you want it") {
                        Picker("", selection: $desireLevel) {
                            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }

                    Toggle("It has a deadline", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("", selection: $targetDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(maxWidth: 210, alignment: .leading)
                    }

                    if let existing, existing.status == .saving {
                        Divider().opacity(0.4)
                        Toggle("I bought it", isOn: $isMarkingPurchased)
                        if isMarkingPurchased {
                            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                TextField("What you actually paid", text: $pricePaidText)
                                    .textFieldStyle(.roundedBorder)
                                if let days = coolOffRemaining {
                                    NoticeRow(
                                        tone: .caution, icon: "clock",
                                        title: "\(days) days of the cool-off left",
                                        detail: "Goals above "
                                              + formatter.string(settings?.coolOffThreshold ?? .zero)
                                              + " wait a week before being marked bought. You can "
                                              + "still do it — this is just the pause."
                                    )
                                }
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
        .frame(width: 460, height: 660)
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
        holdingAccountID = suggestedAccounts.first?.id
        targetDate = calendar.addMonths(6, to: calendar.today())
        guard let existing else { return }
        name = existing.name
        targetText = formatter.string(existing.targetAmount, style: .bare)
        holdingAccountID = existing.holdingAccount?.id
        capText = existing.monthlyCap.map { formatter.string($0, style: .bare) } ?? ""
        desireLevel = existing.desireLevel
        if let date = existing.targetDate { hasTargetDate = true; targetDate = date }
    }

    private func save() {
        guard let target else { return }
        let account = holdingAccountID.flatMap { id in accounts.first { $0.id == id } }
        let cap = capText.isEmpty ? nil : formatter.parse(capText)

        let goal: Goal
        if let existing {
            existing.name = name
            existing.targetAmount = target
            existing.holdingAccount = account
            existing.monthlyCap = cap
            existing.desireLevel = desireLevel
            existing.targetDate = hasTargetDate ? calendar.financialDay(for: targetDate) : nil
            existing.lastPriceCheckedAt = Date()
            existing.updatedAt = Date()
            goal = existing
        } else {
            let created = Goal(
                name: name, targetAmount: target,
                targetDate: hasTargetDate ? calendar.financialDay(for: targetDate) : nil,
                priorityRank: (goals.map(\.priorityRank).max() ?? -1) + 1,
                holdingAccount: account, monthlyCap: cap, desireLevel: desireLevel
            )
            context.insert(created)
            goal = created
        }

        // The saved amount is an earmark against the holding account, never a
        // separate balance.
        if let amount = formatter.parse(setAsideText) {
            let existingEarmark = earmarks.first { $0.ownerID == goal.id }
            if let existingEarmark {
                existingEarmark.amount = amount.clampedToZero
                existingEarmark.account = account
                existingEarmark.updatedAt = Date()
            } else if amount.isPositive {
                context.insert(Earmark(ownerType: .goal, ownerID: goal.id,
                                       account: account, amount: amount))
            }
        }

        if isMarkingPurchased, let paid = formatter.parse(pricePaidText) {
            goal.status = .purchased
            goal.actualPricePaid = paid
            goal.purchasedAt = calendar.currentDate()
        }

        try? context.save()
        dismiss()
    }
}
