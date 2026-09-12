import SwiftUI
import SwiftData

/// Record an inflow. Anything unusual lands unallocated and stays out of spendable
/// balance until the allocation sheet is done.
struct IncomeEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let settings: AppSettings?

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var kind: IncomeEventKind = .projectPayment
    @State private var grossText = ""
    @State private var costsText = ""
    @State private var hoursText = ""
    @State private var source = ""
    @State private var accountID: UUID?

    private var gross: Money { formatter.parse(grossText) ?? .zero }
    private var costs: Money { formatter.parse(costsText) ?? .zero }

    private var taxReserved: Money {
        IncomeEngine.taxReserve(on: gross,
                                rate: settings?.taxReserveRate ?? Decimal(string: "0.25")!,
                                kind: kind)
    }

    private var netUsable: Money {
        IncomeEngine.netUsable(gross: gross, taxReserved: taxReserved, directCosts: costs)
    }

    private var isValid: Bool { gross.isPositive && accountID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Record income").font(Theme.Font.title).padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    field("What kind") {
                        Picker("", selection: $kind) {
                            Text("Project payment").tag(IncomeEventKind.projectPayment)
                            Text("Bonus").tag(IncomeEventKind.bonus)
                            Text("Gift").tag(IncomeEventKind.gift)
                            Text("Asset sale").tag(IncomeEventKind.assetSale)
                            Text("Refund").tag(IncomeEventKind.refund)
                        }
                        .labelsHidden()
                    }

                    if kind == .refund {
                        NoticeRow(
                            tone: .caution, icon: "arrow.uturn.left",
                            title: "A refund is not income",
                            detail: "It reverses the original expense. It will not count "
                                  + "towards income, your savings rate, or a good month."
                        )
                    }
                    if kind == .gift {
                        NoticeRow(
                            tone: .caution, icon: "clock",
                            title: "Seven days before any allocation",
                            detail: "No decisions in the first week. Large sums invite bad ones."
                        )
                    }

                    field("Amount received") {
                        TextField("0.00", text: $grossText).textFieldStyle(.roundedBorder)
                    }
                    field("Direct costs") {
                        TextField("Optional", text: $costsText).textFieldStyle(.roundedBorder)
                    }
                    field("Who from") {
                        TextField("Client or source", text: $source)
                            .textFieldStyle(.roundedBorder)
                    }
                    if kind == .projectPayment {
                        field("Hours worked") {
                            TextField("Optional", text: $hoursText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    field("Into") {
                        Picker("", selection: $accountID) {
                            ForEach(accounts.filter { !$0.isArchived && !$0.isTaxReserve }) {
                                Text($0.name).tag(Optional($0.id))
                            }
                        }
                        .labelsHidden()
                    }

                    if gross.isPositive {
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                row("Gross", formatter.string(gross))
                                if taxReserved.isPositive {
                                    row("Tax reserve", "− " + formatter.string(taxReserved))
                                }
                                if costs.isPositive {
                                    row("Direct costs", "− " + formatter.string(costs))
                                }
                                Divider().opacity(0.4)
                                row("Net usable", formatter.string(netUsable), emphasised: true)
                                if taxReserved.isPositive {
                                    Text("The tax reserve is held separately and cannot be "
                                         + "spent from. It was never your money.")
                                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Record") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 460, height: 640)
        .background(Theme.Palette.surface(scheme))
        .onAppear { accountID = accounts.first { $0.isSpendable }?.id }
    }

    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            content()
        }
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

    private func save() {
        let account = accountID.flatMap { id in accounts.first { $0.id == id } }
        let event = IncomeEvent(
            kind: kind, receivedAt: calendar.currentDate(), grossAmount: gross,
            taxReserved: taxReserved, directCosts: costs,
            hoursWorked: Int(hoursText.trimmingCharacters(in: .whitespaces)),
            clientOrSource: source.isEmpty ? nil : source, account: account
        )
        context.insert(event)
        try? context.save()
        dismiss()
    }
}
