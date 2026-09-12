import SwiftUI
import SwiftData

/// Recurring rules and sinking funds — everything that is already spoken for.
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var context
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil }, sort: \RecurringRule.nextDueDate)
    private var rules: [RecurringRule]
    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil }, sort: \SinkingFund.sortOrder)
    private var funds: [SinkingFund]
    @Query(filter: #Predicate<ScheduledEvent> { $0.deletedAt == nil },
           sort: \ScheduledEvent.expectedDate)
    private var events: [ScheduledEvent]
    @Query(filter: #Predicate<Earmark> { $0.deletedAt == nil })
    private var earmarks: [Earmark]

    @State private var editingRuleID: UUID?
    @State private var isCreatingRule = false
    @State private var postingRuleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            rulesSection
            fundsSection
            eventsSection
        }
        .sheet(isPresented: $isCreatingRule) {
            RecurringRuleEditor(editingID: nil, formatter: formatter, calendar: calendar)
        }
        .sheet(item: Binding(
            get: { editingRuleID.map { IdentifiedID(id: $0) } },
            set: { editingRuleID = $0?.id }
        )) { wrapper in
            RecurringRuleEditor(editingID: wrapper.id, formatter: formatter, calendar: calendar)
        }
        .sheet(item: Binding(
            get: { postingRuleID.map { IdentifiedID(id: $0) } },
            set: { postingRuleID = $0?.id }
        )) { wrapper in
            if let rule = rules.first(where: { $0.id == wrapper.id }) {
                PostRecurringSheet(rule: rule, formatter: formatter, calendar: calendar)
            }
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Recurring")
                    Spacer()
                    Button {
                        isCreatingRule = true
                    } label: {
                        Label("Add", systemImage: "plus").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New recurring rule")
                }
                if rules.isEmpty {
                    Text("Rent, salary, data bundles, the monthly investment. Anything with a "
                         + "date attached belongs here — it is what makes the forward view work.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rules.filter { !$0.isArchived }) { rule in
                        ruleRow(rule)
                        if rule.id != rules.last?.id { Divider().opacity(0.3) }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: rule.kind == .income ? "arrow.down.circle"
                  : (rule.kind == .transfer ? "arrow.left.arrow.right" : "arrow.up.circle"))
                .font(.system(size: 11))
                .foregroundStyle(rule.kind == .income ? Theme.Palette.positive : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(rule.label).font(.system(size: 12.5))
                    if rule.isCommittedOutflow { Pill(text: "committed") }
                    if rule.isVariableAmount { Pill(text: "varies", tone: .caution) }
                }
                Text("\(cadenceText(rule.cadence)) · next "
                     + rule.nextDueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatter.string(rule.amount)).font(Theme.Font.amount)
            if isDue(rule) {
                Button(rule.kind == .income ? "Received" : "Paid") {
                    postingRuleID = rule.id
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
            Button {
                editingRuleID = rule.id
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// Due within the next three days, or already overdue.
    private func isDue(_ rule: RecurringRule) -> Bool {
        calendar.daysBetween(calendar.today(), rule.nextDueDate) <= 3
    }

    private func cadenceText(_ cadence: RecurringRule.Cadence) -> String {
        switch cadence {
        case .weekly: "Weekly"
        case .biweekly: "Every two weeks"
        case let .monthly(day): "Monthly on the \(ordinal(day))"
        case let .yearly(month, day): "Yearly on \(ordinal(day)) of month \(month)"
        case let .custom(days): "Every \(days) days"
        }
    }

    private func ordinal(_ value: Int) -> String {
        let suffix: String
        switch (value % 10, value % 100) {
        case (1, 11), (_, 11): suffix = value % 100 == 11 ? "th" : "st"
        case (1, _): suffix = "st"
        case (2, 12): suffix = "th"
        case (2, _): suffix = "nd"
        case (3, 13): suffix = "th"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }

    // MARK: - Sinking funds

    private var fundsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Sinking funds")
                if funds.isEmpty {
                    Text("A sinking fund turns a surprise into a scheduled expense: gifts, "
                         + "repairs, the annual renewal you forget every year.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(funds) { fund in
                        fundRow(fund)
                    }
                }
            }
        }
    }

    private func fundRow(_ fund: SinkingFund) -> some View {
        let saved = Money.sum(
            earmarks.filter { $0.ownerID == fund.id }.map(\.amount)
        )
        let fraction = fund.targetAmount.isZero
            ? 0 : (saved.ratio(to: fund.targetAmount).map {
                NSDecimalNumber(decimal: $0).doubleValue } ?? 0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: fund.icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(fund.name).font(.system(size: 12.5))
                if fund.isEmergencyFund {
                    Pill(text: "protected", tone: .positive, icon: "shield")
                }
                Spacer()
                Text("\(formatter.string(saved)) of \(formatter.string(fund.targetAmount))")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            MeterBar(fraction: fraction, tone: .positive, height: 5)
            if let periods = periodsRemaining(for: fund), fund.targetAmount.isPositive {
                Text("\(formatter.string(fund.requiredPerPeriod(saved: saved, periodsRemaining: periods))) "
                     + "a \(fund.cadence == .weekly ? "week" : "month") to stay on track")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func periodsRemaining(for fund: SinkingFund) -> Int? {
        guard let target = fund.targetDate else { return nil }
        let days = calendar.daysBetween(calendar.today(), target)
        guard days > 0 else { return 0 }
        return fund.cadence == .weekly ? Swift.max(1, days / 7) : Swift.max(1, days / 30)
    }

    // MARK: - Events

    private var eventsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Coming up")
                if events.isEmpty {
                    Text("Birthdays, weddings, funerals, school fees. Put them here and they "
                         + "stop being surprises.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(events.prefix(10)) { event in
                        HStack(spacing: Theme.Space.sm) {
                            Text(event.label).font(.system(size: 12.5))
                            if event.confidence != .certain {
                                Pill(text: event.confidence.rawValue, tone: .caution)
                            }
                            Spacer()
                            Text(event.expectedDate.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                            Text(formatter.string(event.expectedAmount))
                                .font(Theme.Font.amount)
                        }
                    }
                    Text("A “maybe” is carried at half its amount — enough to not be ambushed, "
                         + "not so much that you over-reserve.")
                        .font(Theme.Font.caption).foregroundStyle(.tertiary)
                        .padding(.top, Theme.Space.xs)
                }
            }
        }
    }
}
