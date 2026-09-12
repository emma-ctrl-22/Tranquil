import SwiftUI
import SwiftData

/// M0's only UI: proof that the schema, the seed and the money formatting work.
/// The real screens arrive in M1 onward.
struct DebugDataView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.sortOrder)
    private var categories: [Category]
    @Query(filter: #Predicate<Loan> { $0.deletedAt == nil }, sort: \Loan.name)
    private var loans: [Loan]
    @Query(filter: #Predicate<Goal> { $0.deletedAt == nil }, sort: \Goal.priorityRank)
    private var goals: [Goal]
    @Query(filter: #Predicate<SinkingFund> { $0.deletedAt == nil }, sort: \SinkingFund.sortOrder)
    private var funds: [SinkingFund]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil },
           sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query private var settingsRows: [AppSettings]

    @State private var status: String?
    @State private var isWorking = false

    private var settings: AppSettings? { settingsRows.first }
    private var formatter: MoneyFormatter { settings?.formatter ?? MoneyFormatter(currency: .ghs) }
    private var calendar: FinancialCalendar { settings?.calendar ?? FinancialCalendar() }

    var body: some View {
        NavigationStack {
            List {
                if accounts.isEmpty {
                    emptyState
                } else {
                    accountsSection
                    envelopesSection
                    commitmentsSection
                    recentSection
                }
                toolsSection
            }
            .navigationTitle("Tranquil — debug")
            .frame(minWidth: 520, minHeight: 560)
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No data yet")
                    .font(.headline)
                Text("The schema is in place. Load the demo data below to see accounts, "
                     + "categories, loans and goals, or start entering real figures in M1.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var accountsSection: some View {
        Section("Accounts") {
            ForEach(accounts) { account in
                LabeledContent {
                    Text(formatter.string(account.openingBalance))
                        .monospacedDigit()
                        .accessibilityLabel(formatter.accessibleString(account.openingBalance))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: account.icon)
                            .foregroundStyle(.secondary)
                        Text(account.name)
                        if account.isTaxReserve {
                            Text("tax reserve")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !account.isLiquid {
                            Text("not liquid")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Opening balances only — derived balances arrive with BalanceEngine in M1.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var envelopesSection: some View {
        Section("Categories (\(categories.count))") {
            ForEach(categories) { category in
                HStack(spacing: 6) {
                    Image(systemName: category.icon).foregroundStyle(.secondary)
                    Text(category.name)
                    Spacer()
                    ForEach(flags(for: category), id: \.self) { flag in
                        Text(flag).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var commitmentsSection: some View {
        Group {
            if !loans.isEmpty {
                Section("Loans") {
                    ForEach(loans) { loan in
                        LabeledContent {
                            Text(formatter.string(loan.principal)).monospacedDigit()
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(loan.name) — \(loan.lender)")
                                Text(loanSubtitle(loan))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !goals.isEmpty {
                Section("Goals") {
                    ForEach(goals) { goal in
                        LabeledContent(goal.name, value: formatter.string(goal.targetAmount))
                    }
                }
            }
            if !funds.isEmpty {
                Section("Sinking funds") {
                    ForEach(funds) { fund in
                        LabeledContent {
                            Text(formatter.string(fund.targetAmount)).monospacedDigit()
                        } label: {
                            Text(fund.name + (fund.isEmergencyFund ? " — emergency" : ""))
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Transactions (\(transactions.count))") {
            ForEach(transactions.prefix(15)) { transaction in
                LabeledContent {
                    Text(formatter.string(signed(transaction), style: .signed))
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(transaction.category?.name ?? transaction.note ?? transaction.kind.rawValue)
                        Text(calendar.financialDay(for: transaction.date)
                            .formatted(date: .abbreviated, time: .omitted)
                            + (transaction.isEstimate ? " · estimate" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var toolsSection: some View {
        Section("Debug tools") {
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Button("Load demo data") { run { try loadDemo() } }
                .disabled(isWorking || !accounts.isEmpty)
            Button("Add 5,000 stress transactions") { run { try loadStress() } }
                .disabled(isWorking || accounts.isEmpty)
            Button("Wipe everything", role: .destructive) { run { try SeedData.wipe(context) } }
                .disabled(isWorking)
        }
    }

    // MARK: - Helpers

    private func signed(_ transaction: Transaction) -> Money {
        transaction.kind == .income ? transaction.amount : -transaction.amount
    }

    private func flags(for category: Category) -> [String] {
        var result: [String] = []
        if category.isMicro { result.append("micro") }
        if category.isEssential { result.append("essential") }
        if category.isEarningPower { result.append("earning power") }
        if category.isMiscellaneous { result.append("catch-all") }
        return result
    }

    private func loanSubtitle(_ loan: Loan) -> String {
        let direction = loan.direction == .iOwe ? "I owe" : "Owed to me"
        switch loan.interestModel {
        case let .amortizing(apr):
            return "\(direction) · amortizing \(percent(apr)) APR · social \(loan.socialWeight)"
        case let .revolving(apr):
            return "\(direction) · revolving \(percent(apr)) APR · social \(loan.socialWeight)"
        case let .flatRate(rate, years):
            return "\(direction) · flat \(percent(rate))/yr over \(years)y · social \(loan.socialWeight)"
        case .interestFree:
            return "\(direction) · interest-free · social \(loan.socialWeight)"
        }
    }

    private func percent(_ rate: Decimal) -> String {
        let scaled = Money.roundBankers(rate * 10_000)
        return "\(scaled / 100).\(String(format: "%02d", abs(scaled % 100)))%"
    }

    private func run(_ work: @escaping () throws -> Void) {
        isWorking = true
        do {
            try work()
            status = nil
        } catch {
            status = error.localizedDescription
        }
        isWorking = false
    }

    private func loadDemo() throws {
        let summary = try SeedData.loadDemo(into: context, calendar: calendar)
        status = "Loaded \(summary.transactions) transactions across \(summary.accounts) accounts."
    }

    private func loadStress() throws {
        let added = try SeedData.loadStressTransactions(into: context, calendar: calendar)
        status = "Added \(added) transactions."
    }
}
