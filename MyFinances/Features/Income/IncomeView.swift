import SwiftUI
import SwiftData
import Charts

/// The windfall inbox, the tax reserve, effective hourly rate and the creep chart.
struct IncomeView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let settings: AppSettings?
    let creep: IncomeEngine.CreepVerdict
    let taxReserved: Money
    let salaryCheck: IncomeEngine.SalaryCheck

    @Query(filter: #Predicate<IncomeEvent> { $0.deletedAt == nil },
           sort: \IncomeEvent.receivedAt, order: .reverse)
    private var events: [IncomeEvent]

    @State private var allocatingID: UUID?
    @State private var isRecording = false

    private var unallocated: [IncomeEvent] { events.filter { $0.status == .unallocated } }
    private var allocated: [IncomeEvent] { events.filter { $0.status == .allocated } }

    private var clientRates: [IncomeEngine.ClientRate] {
        IncomeEngine.clientRates(
            events.map { (client: $0.clientOrSource, netUsable: $0.netUsable, hours: $0.hoursWorked) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SalaryCheckCard(check: salaryCheck, settings: settings,
                                formatter: formatter, calendar: calendar)
                inbox
                if !taxReserved.isZero { taxCard }
                if !clientRates.isEmpty { hourlyCard }
                creepCard
            }
            .padding(Theme.Space.lg)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { isRecording = true } label: {
                    Label("Record income", systemImage: "tray.and.arrow.down")
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .sheet(isPresented: $isRecording) {
            IncomeEventEditor(formatter: formatter, calendar: calendar, settings: settings)
        }
        .sheet(item: Binding(
            get: { allocatingID.map { IdentifiedID(id: $0) } },
            set: { allocatingID = $0?.id }
        )) { wrapper in
            if let event = events.first(where: { $0.id == wrapper.id }) {
                AllocationSheet(event: event, formatter: formatter, calendar: calendar)
            }
        }
    }

    // MARK: - Inbox

    private var inbox: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Waiting to be allocated")
                    Spacer()
                    if !unallocated.isEmpty {
                        Pill(text: "\(unallocated.count)", tone: .caution)
                    }
                }
                if unallocated.isEmpty {
                    Text(events.isEmpty
                         ? "Anything that arrives above one and a half times your usual week "
                           + "lands here first, and stays out of your spendable balance until "
                           + "you decide where it goes."
                         : "Nothing waiting. Everything that came in has been allocated.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(unallocated) { event in
                        eventRow(event, actionable: true)
                        if event.id != unallocated.last?.id { Divider().opacity(0.3) }
                    }
                    Text("This money is not counted as available until it is allocated.")
                        .font(Theme.Font.caption).foregroundStyle(.tertiary)
                }

                if !allocated.isEmpty {
                    Divider().opacity(0.4)
                    SectionLabel(text: "Allocated")
                    ForEach(allocated.prefix(5)) { event in
                        eventRow(event, actionable: false)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: IncomeEvent, actionable: Bool) -> some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(event.clientOrSource ?? label(for: event.kind))
                        .font(.system(size: 12.5))
                    if event.kind == .refund { Pill(text: "not income") }
                    if let from = event.allocatableFrom, from > calendar.currentDate() {
                        Pill(text: "waiting", tone: .caution, icon: "clock")
                    }
                }
                Text(event.receivedAt.formatted(date: .abbreviated, time: .omitted)
                     + (event.taxReserved.isZero ? ""
                        : " · \(formatter.string(event.taxReserved)) held for tax"))
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatter.string(event.netUsable)).font(Theme.Font.amount)
            if actionable {
                Button("Allocate") { allocatingID = event.id }
                    .controlSize(.small)
                    .disabled(event.allocatableFrom.map { $0 > calendar.currentDate() } ?? false)
            }
        }
        .padding(.vertical, 2)
    }

    private func label(for kind: IncomeEventKind) -> String {
        switch kind {
        case .projectPayment: "Project payment"
        case .salaryRise: "Salary rise"
        case .bonus: "Bonus"
        case .gift: "Gift"
        case .refund: "Refund"
        case .assetSale: "Asset sale"
        }
    }

    // MARK: - Tax

    private var taxCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Tax reserve")
                    Spacer()
                    Text(formatter.string(taxReserved)).font(Theme.Font.figure)
                }
                Text("Not an asset, not spendable, and excluded from runway, net worth and "
                     + "free-to-spend. It was never your money.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Confirm the rate with a local professional once a year. Tax rules are "
                     + "jurisdictional and they change.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Effective hourly

    private var hourlyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "What your work actually pays")
                ForEach(clientRates) { rate in
                    HStack {
                        Text(rate.client).font(.system(size: 12.5))
                        Spacer()
                        Text("\(rate.totalHours)h").font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(rate.hourlyRate.map { formatter.string($0) + "/h" } ?? "—")
                            .font(Theme.Font.amount)
                    }
                }
                Text("Net of tax and costs, over the trailing year. Over time this says which "
                     + "work to take more of and which to stop taking.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Creep

    private var creepCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Lifestyle creep")
                    Spacer()
                    if creep.isCreeping { Pill(text: "rising", tone: .caution) }
                }

                if creep.points.compactMap(\.ratio).isEmpty {
                    Text("Essentials as a share of income, month by month. Needs a few months "
                         + "of history before it says anything.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Chart {
                        ForEach(creep.points) { point in
                            if let ratio = point.ratio {
                                LineMark(
                                    x: .value("Month", point.monthStart),
                                    y: .value("Share", percentValue(ratio))
                                )
                                .foregroundStyle(creep.isCreeping ? Theme.Palette.caution
                                                                  : Theme.Palette.accent)
                                .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel {
                                if let percent = value.as(Double.self) {
                                    Text("\(Int(percent))%").font(Theme.Font.caption)
                                }
                            }
                        }
                    }
                    .frame(height: 150)
                    .accessibilityLabel("Essential spend as a share of income over time")

                    if creep.isCreeping {
                        Text("Essentials have grown as a share of income for two consecutive "
                             + "quarters"
                             + (creep.drivers.isEmpty ? "."
                                : ". The movement is in \(creep.drivers.joined(separator: ", "))."))
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Essentials are not taking a growing share of what you earn.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Charts need a `Double`. Pixels only — no total is ever computed from it.
    private func percentValue(_ ratio: Decimal) -> Double {
        NSDecimalNumber(decimal: ratio * 100).doubleValue
    }
}
