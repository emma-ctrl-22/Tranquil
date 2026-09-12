import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let balances: [BalanceEngine.AccountBalance]
    let formatter: MoneyFormatter

    private var active: [BalanceEngine.AccountBalance] {
        balances.filter { !$0.account.isArchived }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                if !active.isEmpty {
                    HStack(spacing: Theme.Space.sm) {
                        Button {
                            model.editingAccountID = nil
                            model.isAccountEditorShown = true
                        } label: {
                            Label("New account", systemImage: "plus")
                        }
                        Button {
                            model.isTransferShown = true
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                        }
                        Spacer()
                    }
                    .controlSize(.small)
                }
                if active.isEmpty {
                    EmptyStateView(
                        icon: "wallet.pass",
                        title: "No accounts yet",
                        message: "Add the places your money actually sits — cash in your pocket, "
                               + "mobile money, your bank. Balances are derived from what you log, "
                               + "never typed in directly.",
                        actionTitle: "Add my first account",
                        action: {
                            model.editingAccountID = nil
                            model.isAccountEditorShown = true
                        }
                    )
                    Button("Or load sample data to look around", action: loadSample)
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Space.md)],
                        spacing: Theme.Space.md
                    ) {
                        ForEach(active) { entry in
                            AccountTile(entry: entry, formatter: formatter, expanded: true) {
                                model.selectedAccountID = entry.account.id
                                model.isInspectorShown = true
                            }
                            .contextMenu {
                                Button("Reconcile…") {
                                    model.reconcilingAccountID = entry.account.id
                                }
                                Button("Edit…") {
                                    model.editingAccountID = entry.account.id
                                    model.isAccountEditorShown = true
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    /// Fills an empty database with a realistic set so the app can be explored before
    /// any real figures are entered. Refuses to touch a database that already has data.
    private func loadSample() {
        try? SeedData.loadDemo(into: context, calendar: FinancialCalendar())
    }
}

struct AccountTile: View {
    @Environment(\.colorScheme) private var scheme
    let entry: BalanceEngine.AccountBalance
    let formatter: MoneyFormatter
    var expanded = false
    let action: () -> Void
    @State private var isHovering = false

    private var account: BalanceEngine.AccountRecord { entry.account }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: account.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.account(account.colorHex))
                        .frame(width: 22, height: 22)
                        .background(Theme.Palette.account(account.colorHex).opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small,
                                                    style: .continuous))
                    Text(account.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(formatter.string(entry.balance))
                    .font(Theme.Font.figure)
                    .foregroundStyle(entry.balance.isNegative ? Theme.Palette.negative : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !entry.earmarked.isZero {
                    Text("\(formatter.string(entry.available)) available")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                if expanded {
                    HStack(spacing: Theme.Space.xs) {
                        Pill(text: account.type.label)
                        if account.isTaxReserve {
                            Pill(text: "not yours", tone: .caution, icon: "lock")
                        }
                        if !account.isLiquid && !account.isTaxReserve {
                            Pill(text: "not liquid")
                        }
                    }
                }

                if entry.isOverCommitted {
                    Pill(text: "over-committed", tone: .caution,
                         icon: "exclamationmark.triangle")
                } else if entry.isBelowFloor {
                    Pill(text: "below floor", tone: .caution, icon: "arrow.down")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(Theme.Palette.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(isHovering ? Theme.Palette.accent.opacity(0.5)
                                       : Theme.Palette.hairline(scheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.name)
        .accessibilityValue(
            formatter.accessibleString(entry.balance)
            + (entry.isOverCommitted ? ", over-committed" : "")
        )
        .accessibilityAddTraits(.isButton)
    }
}
