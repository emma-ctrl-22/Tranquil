import SwiftUI
import SwiftData

/// Where a windfall goes. Prefilled with the defaults, every slice adjustable, and it
/// must total 100% before it can be committed.
struct AllocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let event: IncomeEvent
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @State private var shares: [String: Double] = [:]
    @State private var goalID: UUID?
    @State private var fundID: UUID?

    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil }, sort: \Goal.priorityRank)
    private var goals: [Goal]
    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil }, sort: \SinkingFund.sortOrder)
    private var funds: [SinkingFund]

    private var slices: [IncomeEngine.Slice] { IncomeEngine.defaultSplit(for: event.kind) }

    private var adjusted: [IncomeEngine.Slice] {
        slices.map { slice in
            IncomeEngine.Slice(
                id: slice.id, label: slice.label, kind: slice.kind,
                share: Decimal(shares[slice.id] ?? NSDecimalNumber(decimal: slice.share).doubleValue),
                rationale: slice.rationale
            )
        }
    }

    private var total: Double { adjusted.reduce(0) { $0 + doubleValue($1.share) } }
    private var isComplete: Bool { abs(total - 100) < 0.5 }

    private var allocations: [(slice: IncomeEngine.Slice, amount: Money)] {
        IncomeEngine.allocate(event.netUsable, across: adjusted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    breakdown
                    slicesCard
                }
                .padding(Theme.Space.lg)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 520, height: 660)
        .background(Theme.Palette.surface(scheme))
        .onAppear {
            for slice in slices { shares[slice.id] = doubleValue(slice.share) }
            goalID = goals.first { $0.status == .saving }?.id
            fundID = funds.first?.id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Allocate \(formatter.string(event.netUsable))").font(Theme.Font.title)
            Text("Until this is done, the money stays out of your spendable balance.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.lg)
    }

    /// The arithmetic from §4a, shown before anything is divided.
    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                row("Gross received", formatter.string(event.grossAmount))
                if !event.taxReserved.isZero {
                    row("Tax reserve", "− " + formatter.string(event.taxReserved))
                }
                if !event.directCosts.isZero {
                    row("Direct costs", "− " + formatter.string(event.directCosts))
                }
                Divider().opacity(0.4)
                row("Net usable", formatter.string(event.netUsable), emphasised: true)
                if let rate = event.effectiveHourlyRate() {
                    Divider().opacity(0.4)
                    row("Effective hourly", formatter.string(rate) + " / hour")
                }
            }
        }
    }

    private var slicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    SectionLabel(text: "Where it goes")
                    Spacer()
                    Text("\(Int(total.rounded()))%")
                        .font(Theme.Font.amount)
                        .foregroundStyle(isComplete ? Theme.Palette.positive
                                                    : Theme.Palette.caution)
                }

                ForEach(Array(allocations.enumerated()), id: \.element.slice.id) { _, entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.slice.label).font(.system(size: 12.5))
                            Spacer()
                            Text("\(Int(doubleValue(entry.slice.share).rounded()))%")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                            Text(formatter.string(entry.amount))
                                .font(Theme.Font.amount).frame(width: 92, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { shares[entry.slice.id] ?? 0 },
                                set: { shares[entry.slice.id] = $0 }
                            ),
                            in: 0...100
                        )
                        .controlSize(.small)
                        .accessibilityLabel(entry.slice.label)
                        Text(entry.slice.rationale)
                            .font(Theme.Font.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if allocations.contains(where: { $0.slice.kind == .goal && $0.amount.isPositive }),
                   !goals.isEmpty {
                    Divider().opacity(0.4)
                    HStack {
                        Text("Goal slice goes to").font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $goalID) {
                            ForEach(goals.filter { $0.status == .saving }) { goal in
                                Text(goal.name).tag(Optional(goal.id))
                            }
                        }
                        .labelsHidden().frame(maxWidth: 200)
                    }
                }

                if !isComplete {
                    NoticeRow(
                        tone: .caution, icon: "equal.circle",
                        title: "The slices must add up to 100%",
                        detail: "Currently \(Int(total.rounded()))%. Every pesewa needs a "
                              + "destination, including the part that is simply yours."
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to defaults") {
                for slice in slices { shares[slice.id] = doubleValue(slice.share) }
            }
            .controlSize(.small)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Allocate") { commit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
        }
        .padding(Theme.Space.md)
    }

    private func row(_ label: String, _ value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasised ? .system(size: 15, weight: .medium).monospacedDigit()
                                 : Theme.Font.amount)
        }
    }

    private func doubleValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    private func commit() {
        for entry in allocations where entry.amount.isPositive {
            context.insert(IncomeAllocation(
                incomeEvent: event,
                destinationKind: entry.slice.kind,
                destinationAccount: event.account,
                amount: entry.amount,
                label: entry.slice.label
            ))
        }
        // Record what was decided, then actually carry it out.
        IncomeEventService.apply(allocations: allocations, for: event,
                                 goalID: goalID ?? goals.first { $0.status == .saving }?.id,
                                 sinkingFundID: fundID ?? funds.first?.id,
                                 in: context, calendar: calendar)
        event.status = .allocated
        event.allocatedAt = calendar.currentDate()
        event.updatedAt = calendar.currentDate()
        try? context.save()
        dismiss()
    }
}
