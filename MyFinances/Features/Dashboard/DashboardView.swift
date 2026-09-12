import SwiftUI
import SwiftData

/// The dashboard answers one question: **am I okay?**
/// If a number does not help answer it, it belongs on another screen.
struct DashboardView: View {
    @Binding var model: AppModel
    let balances: [BalanceEngine.AccountBalance]
    let transactions: [Transaction]
    let settings: AppSettings?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    let lastReconciledOn: Date?

    private var totals: BalanceEngine.Totals { BalanceEngine.totals(for: balances) }
    private var records: [BalanceEngine.TransactionRecord] { transactions.map(DataBridge.record) }
    private var week: DateInterval { calendar.weekInterval(containing: calendar.currentDate()) }
    private var spentThisWeek: Money { BalanceEngine.spend(transactions: records, in: week) }

    private var overCommitted: [BalanceEngine.AccountBalance] {
        balances.filter(\.isOverCommitted)
    }
    private var belowFloor: [BalanceEngine.AccountBalance] {
        balances.filter { $0.isBelowFloor && !$0.account.isArchived }
    }

    private var todaysTransactions: [Transaction] {
        let today = calendar.today()
        return transactions.filter { calendar.financialDay(for: $0.date) == today }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headline
                warnings
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    weekCard
                    todayCard
                }
                accountsStrip
            }
            .padding(Theme.Space.lg)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        Card(padding: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Available to spend")
                        Text(formatter.string(totals.liquidAvailable))
                            .font(Theme.Font.hero)
                            .foregroundStyle(totals.liquidAvailable.isNegative
                                             ? Theme.Palette.negative : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel("Available to spend")
                            .accessibilityValue(formatter.accessibleString(totals.liquidAvailable))
                        Text(availabilityExplanation)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Space.sm) {
                        Button {
                            model.isQuickAddShown = true
                        } label: {
                            Label("Log a spend", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut("n", modifiers: .command)
                        if !totals.taxReserved.isZero {
                            Text("\(formatter.string(totals.taxReserved)) held in tax reserve")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider().opacity(0.4)
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    StatTile(label: "Net worth",
                             value: formatter.string(totals.netWorth),
                             detail: "Excludes the tax reserve and money lent out",
                             accessibilityValue: formatter.accessibleString(totals.netWorth))
                    StatTile(label: "Earmarked",
                             value: formatter.string(totals.earmarkedTotal),
                             detail: "Reserved for goals and funds",
                             accessibilityValue: formatter.accessibleString(totals.earmarkedTotal))
                    StatTile(label: "Spent this week",
                             value: formatter.string(spentThisWeek),
                             detail: weekDetail,
                             accessibilityValue: formatter.accessibleString(spentThisWeek))
                }
            }
        }
    }

    private var availabilityExplanation: String {
        totals.earmarkedTotal.isZero
            ? "Liquid balances across every spendable account"
            : "Liquid balances minus what is earmarked"
    }

    private var reconcileTitle: String {
        guard let days = BalanceEngine.daysSinceReconciliation(
            lastReconciledOn: lastReconciledOn, today: calendar.today(), calendar: calendar
        ) else { return "Nothing has been reconciled yet" }
        return "Nothing reconciled in \(days) days"
    }

    private var weekDetail: String {
        let elapsed = calendar.elapsedDaysInWeek(containing: calendar.currentDate())
        return "Day \(elapsed) of 7"
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warnings: some View {
        let needsReconcile = BalanceEngine.needsReconciliation(
            lastReconciledOn: lastReconciledOn, today: calendar.today(), calendar: calendar
        ) && !balances.isEmpty
        if !overCommitted.isEmpty || !belowFloor.isEmpty || needsReconcile {
            VStack(spacing: Theme.Space.sm) {
                ForEach(overCommitted) { entry in
                    // The invariant is surfaced, never silently rebalanced.
                    NoticeRow(
                        tone: .caution,
                        icon: "exclamationmark.triangle",
                        title: "\(entry.account.name) is over-committed",
                        detail: "\(formatter.string(entry.earmarked)) is earmarked against a "
                              + "balance of \(formatter.string(entry.balance))."
                    )
                }
                if BalanceEngine.needsReconciliation(lastReconciledOn: lastReconciledOn,
                                                     today: calendar.today(),
                                                     calendar: calendar), !balances.isEmpty {
                    NoticeRow(
                        tone: .caution,
                        icon: "checkmark.circle.badge.questionmark",
                        title: reconcileTitle,
                        detail: "Count what is actually in one account and check it against the "
                              + "ledger. Small gaps compound quietly."
                    )
                }
                ForEach(belowFloor) { entry in
                    NoticeRow(
                        tone: .caution,
                        icon: "arrow.down.circle",
                        title: "\(entry.account.name) is below its floor",
                        detail: "\(formatter.string(entry.balance)) against a floor of "
                              + "\(formatter.string(entry.account.lowBalanceFloor ?? .zero))."
                    )
                }
            }
        }
    }

    // MARK: - Cards

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "This week")
                Text(weekRangeText).font(Theme.Font.caption).foregroundStyle(.secondary)
                Divider().opacity(0.4)
                if spentThisWeek.isZero {
                    Text("Nothing logged this week yet.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    Text(formatter.string(spentThisWeek))
                        .font(Theme.Font.figure)
                    Text("Envelopes and the burn meter arrive in M3.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Today")
                    Spacer()
                    Text("\(todaysTransactions.count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().opacity(0.4)
                if todaysTransactions.isEmpty {
                    Text("Nothing logged today.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    ForEach(todaysTransactions.prefix(6)) { transaction in
                        TransactionRow(transaction: transaction, formatter: formatter,
                                       calendar: calendar, showsDate: false)
                    }
                }
            }
        }
    }

    private var weekRangeText: String {
        let start = week.start
        let end = calendar.addDays(6, to: start)
        return start.formatted(date: .abbreviated, time: .omitted)
            + " – " + end.formatted(date: .abbreviated, time: .omitted)
    }

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionLabel(text: "Accounts")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 172), spacing: Theme.Space.md)],
                spacing: Theme.Space.md
            ) {
                ForEach(balances.filter { !$0.account.isArchived }) { entry in
                    AccountTile(entry: entry, formatter: formatter) {
                        model.selectedAccountID = entry.account.id
                        model.isInspectorShown = true
                    }
                }
            }
        }
    }
}

struct NoticeRow: View {
    let tone: StatTile.Tone
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon).foregroundStyle(tone.color).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
