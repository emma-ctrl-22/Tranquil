import SwiftUI
import SwiftData

/// Goals and the wishlist. For any goal: how long, which account, where is it now,
/// and what does it cost the others.
struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let settings: AppSettings?
    let weeklySurplus: Money

    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil }, sort: \Goal.priorityRank)
    private var goals: [Goal]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]
    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil }, sort: \SinkingFund.sortOrder)
    private var funds: [SinkingFund]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var editingGoalID: UUID?
    @State private var isCreating = false
    @State private var selectedGoalID: UUID?

    private var inputs: [GoalEngine.GoalInput] {
        goals.map { DataBridge.goal($0, earmarks: earmarks) }
    }

    private var fundInputs: [GoalEngine.FundInput] {
        funds.map { DataBridge.fund($0, earmarks: earmarks, periodsRemaining: 12) }
    }

    private var etas: [GoalEngine.ETA] {
        GoalEngine.etas(
            surplusPerPeriod: weeklySurplus,
            ladderRequirement: .none,
            funds: fundInputs,
            goals: inputs,
            periodLength: .weekly,
            from: calendar.today(),
            calendar: calendar
        )
    }

    private var active: [GoalEngine.GoalInput] {
        inputs.filter { $0.status == .saving || $0.status == .funded }
    }

    private var purchased: [GoalEngine.GoalInput] {
        inputs.filter { $0.status == .purchased }
    }

    private var overspendEntries: [GoalEngine.OverspendEntry] {
        goals.compactMap { goal in
            guard goal.status == .purchased, let paid = goal.actualPricePaid else { return nil }
            return GoalEngine.OverspendEntry(id: goal.id, name: goal.name,
                                             planned: goal.targetAmount, paid: paid)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if active.isEmpty && purchased.isEmpty {
                    EmptyStateView(
                        icon: "target",
                        title: "Nothing on the list yet",
                        message: "Add the thing you actually want. The app will tell you how "
                               + "far away it is, which account it sits in, and what buying it "
                               + "sooner costs the rest.",
                        actionTitle: "Add a goal",
                        action: { isCreating = true }
                    )
                } else {
                    header
                    ForEach(active) { goal in
                        GoalCard(
                            goal: goal,
                            eta: etas.first { $0.goalID == goal.id },
                            accountName: accountName(for: goal),
                            formatter: formatter,
                            calendar: calendar,
                            weeklySurplus: weeklySurplus
                        ) {
                            editingGoalID = goal.id
                        }
                    }
                    if !overspendEntries.isEmpty { overspendCard }
                }
            }
            .padding(Theme.Space.lg)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { isCreating = true } label: {
                    Label("New goal", systemImage: "plus.circle")
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .sheet(isPresented: $isCreating) {
            GoalEditor(editingID: nil, formatter: formatter, calendar: calendar)
        }
        .sheet(item: Binding(
            get: { editingGoalID.map { IdentifiedID(id: $0) } },
            set: { editingGoalID = $0?.id }
        )) { wrapper in
            GoalEditor(editingID: wrapper.id, formatter: formatter, calendar: calendar)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Saving \(formatter.string(weeklySurplus)) a week")
                    .font(Theme.Font.title)
                Text(weeklySurplus.isPositive
                     ? "Everything below flows from that, in priority order."
                     : "There is no surplus this week, so nothing is moving yet.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func accountName(for goal: GoalEngine.GoalInput) -> String? {
        goal.holdingAccountID.flatMap { id in accounts.first { $0.id == id }?.name }
    }

    /// "Wishlist items came in ₵X over plan." The number does the work.
    private var overspendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Bought")
                ForEach(overspendEntries) { entry in
                    HStack {
                        Text(entry.name).font(.system(size: 12.5))
                        Spacer()
                        Text("planned \(formatter.string(entry.planned))")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                        Text(formatter.string(entry.variance, style: .signed))
                            .font(Theme.Font.amount)
                            .foregroundStyle(entry.variance.isPositive
                                             ? Theme.Palette.caution : Theme.Palette.positive)
                    }
                }
                Divider().opacity(0.4)
                HStack {
                    Text("Against plan").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(formatter.string(GoalEngine.overspendTotal(overspendEntries),
                                          style: .signed))
                        .font(Theme.Font.amount)
                }
            }
        }
    }
}

struct GoalCard: View {
    let goal: GoalEngine.GoalInput
    let eta: GoalEngine.ETA?
    let accountName: String?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let weeklySurplus: Money
    let onEdit: () -> Void

    /// The lever: drag it and feel the tradeoff.
    @State private var rateOverride: Double?

    private var currentRate: Money {
        if let rateOverride { return Money(minorUnits: Int(rateOverride)) }
        return eta?.perPeriod ?? .zero
    }

    private var leverETA: GoalEngine.ETA {
        GoalEngine.eta(forGoal: goal, atRate: currentRate, periodLength: .weekly,
                       from: calendar.today(), calendar: calendar)
    }

    private var sliderMax: Double {
        Double(Swift.max(weeklySurplus.minorUnits, (eta?.perPeriod.minorUnits ?? 0) * 3, 10_000))
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Text(goal.name).font(.system(size: 13, weight: .medium))
                    if goal.isFunded { Pill(text: "funded", tone: .positive, icon: "checkmark") }
                    Spacer()
                    Text("\(formatter.string(goal.saved)) of "
                         + "\(formatter.string(goal.targetAmount))")
                        .font(Theme.Font.amount).foregroundStyle(.secondary)
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                }

                MeterBar(
                    fraction: NSDecimalNumber(decimal: goal.fraction).doubleValue,
                    tone: .positive, height: 7
                )

                // 2 and 3 of the four questions: which account, and where is it now.
                HStack(spacing: Theme.Space.md) {
                    if let accountName {
                        Label(accountName, systemImage: "wallet.pass")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                    Text("\(formatter.string(goal.remaining)) to go")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                    Spacer()
                }

                Divider().opacity(0.4)

                // 1: how long, with the lever alongside it.
                HStack {
                    Text(etaText).font(.system(size: 12.5))
                    Spacer()
                }
                if !goal.isFunded {
                    HStack(spacing: Theme.Space.sm) {
                        Slider(
                            value: Binding(
                                get: { rateOverride ?? Double(currentRate.minorUnits) },
                                set: { rateOverride = $0 }
                            ),
                            in: 0...sliderMax
                        )
                        .controlSize(.small)
                        Text("\(formatter.string(currentRate))/wk")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        if rateOverride != nil {
                            Button("Reset") { rateOverride = nil }
                                .font(Theme.Font.caption).buttonStyle(.link)
                        }
                    }
                    .accessibilityLabel("Weekly amount towards \(goal.name)")
                }
            }
        }
    }

    private var etaText: String {
        if goal.isFunded { return "Funded. Ready when you are." }
        guard let date = leverETA.date, let periods = leverETA.periods else {
            return currentRate.isPositive
                ? "Nothing reaches this goal at that rate."
                : "Nothing is going into this yet — everything ahead of it takes the surplus."
        }
        return "\(formatter.string(currentRate)) a week → "
             + date.formatted(date: .abbreviated, time: .omitted)
             + " (\(periods) \(periods == 1 ? "week" : "weeks"))"
    }
}
