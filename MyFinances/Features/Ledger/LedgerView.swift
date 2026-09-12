import SwiftUI
import SwiftData

struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Binding var model: AppModel
    let transactions: [Transaction]
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, expense, income, transfer, needsReview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .expense: "Spend"
            case .income: "In"
            case .transfer: "Transfers"
            case .needsReview: "Needs review"
            }
        }
    }

    private var filtered: [Transaction] {
        transactions.filter { transaction in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .expense: matchesFilter = transaction.kind == .expense
            case .income: matchesFilter = transaction.kind == .income
            case .transfer: matchesFilter = transaction.kind == .transfer
            case .needsReview: matchesFilter = transaction.isEstimate
            }
            guard matchesFilter else { return false }
            guard !model.searchText.isEmpty else { return true }
            let needle = model.searchText.lowercased()
            return (transaction.category?.name.lowercased().contains(needle) ?? false)
                || (transaction.note?.lowercased().contains(needle) ?? false)
                || (transaction.account?.name.lowercased().contains(needle) ?? false)
        }
    }

    /// Grouped by financial day, so a 01:00 taxi sits under the previous day.
    private var grouped: [(day: Date, items: [Transaction])] {
        Dictionary(grouping: filtered) { calendar.financialDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.5)
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "list.bullet",
                    title: model.searchText.isEmpty ? "Nothing here yet" : "No matches",
                    message: model.searchText.isEmpty
                        ? "Press ⌘N to log a spend. It should take under three seconds."
                        : "Nothing matches “\(model.searchText)”.",
                    actionTitle: model.searchText.isEmpty ? "Log a spend" : nil,
                    action: model.searchText.isEmpty ? { model.isQuickAddShown = true } : nil
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.md, pinnedViews: .sectionHeaders) {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                Card(padding: Theme.Space.sm) {
                                    VStack(spacing: 0) {
                                        ForEach(group.items) { transaction in
                                            TransactionRow(transaction: transaction,
                                                           formatter: formatter,
                                                           calendar: calendar,
                                                           showsDate: false)
                                                .padding(.vertical, 3)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    model.selectedTransactionID = transaction.id
                                                    model.isInspectorShown = true
                                                }
                                                .contextMenu {
                                                    Button("Delete", role: .destructive) {
                                                        softDelete(transaction)
                                                    }
                                                }
                                            if transaction.id != group.items.last?.id {
                                                Divider().opacity(0.3)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                dayHeader(group.day, items: group.items)
                            }
                        }
                    }
                    .padding(Theme.Space.lg)
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search the ledger")
        .overlay(alignment: .bottom) { undoToast }
    }

    /// Nothing is ever hard-deleted. The row is marked deleted and can be restored
    /// from the toast; the purge is a separate, confirmed action in Settings.
    private func softDelete(_ transaction: Transaction) {
        transaction.deletedAt = calendar.currentDate()
        transaction.updatedAt = calendar.currentDate()
        try? context.save()
        model.lastSaved = (transaction.id, formatter.string(transaction.amount))
        if model.selectedTransactionID == transaction.id { model.selectedTransactionID = nil }
    }

    private func restore(_ id: UUID) {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        if let transaction = try? context.fetch(descriptor).first {
            transaction.deletedAt = nil
            transaction.updatedAt = calendar.currentDate()
            try? context.save()
        }
        model.lastSaved = nil
    }

    @ViewBuilder
    private var undoToast: some View {
        if let saved = model.lastSaved {
            HStack(spacing: Theme.Space.sm) {
                Text("Deleted \(saved.label)").font(Theme.Font.caption)
                Button("Undo") { restore(saved.id) }
                    .font(Theme.Font.caption)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 8, y: 2)
            .padding(.bottom, Theme.Space.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: saved.id) {
                // A five-second window, then the toast retires itself.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if model.lastSaved?.id == saved.id { model.lastSaved = nil }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach(Filter.allCases) { option in
                let count = option == .needsReview
                    ? transactions.filter(\.isEstimate).count : 0
                Button {
                    filter = option
                } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                        if option == .needsReview && count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.Palette.caution.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 4)
                .foregroundStyle(filter == option ? Theme.Palette.accent : .secondary)
                .background(filter == option ? Theme.Palette.accentSoft : .clear)
                .clipShape(Capsule())
            }
            Spacer()
            Text("\(filtered.count) entries")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
    }

    private func dayHeader(_ day: Date, items: [Transaction]) -> some View {
        let spent = Money.sum(items.filter { $0.kind == .expense }.map(\.amount))
        return HStack {
            Text(dayLabel(day)).font(.system(size: 12, weight: .semibold))
            Spacer()
            if !spent.isZero {
                Text(formatter.string(spent))
                    .font(Theme.Font.amount)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, Theme.Space.xs)
        .background(.ultraThinMaterial)
    }

    private func dayLabel(_ day: Date) -> String {
        let today = calendar.today()
        if day == today { return "Today" }
        if day == calendar.addDays(-1, to: today) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    var showsDate = true

    private var tone: Color {
        switch transaction.kind {
        case .income: Theme.Palette.positive
        case .transfer: .secondary
        case .expense: .primary
        }
    }

    private var signed: String {
        switch transaction.kind {
        case .income: "+" + formatter.string(transaction.amount)
        case .expense: "−" + formatter.string(transaction.amount)
        case .transfer: formatter.string(transaction.amount)
        }
    }

    private var title: String {
        transaction.category?.name
            ?? transaction.note
            ?? (transaction.kind == .transfer ? "Transfer" : transaction.kind.rawValue.capitalized)
    }

    private var subtitle: String {
        var parts: [String] = []
        if transaction.kind == .transfer {
            let from = transaction.account?.name ?? "?"
            let to = transaction.counterAccount?.name ?? "?"
            parts.append("\(from) → \(to)")
        } else if let account = transaction.account?.name {
            parts.append(account)
        }
        if showsDate {
            parts.append(calendar.financialDay(for: transaction.date)
                .formatted(date: .abbreviated, time: .omitted))
        }
        if let note = transaction.note, transaction.category != nil { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: transaction.kind == .transfer
                  ? "arrow.left.arrow.right"
                  : (transaction.category?.icon ?? "circle"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Theme.Palette.accentSoft.opacity(0.5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12.5))
                    if transaction.isEstimate {
                        Pill(text: "estimate", tone: .caution)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            Text(signed)
                .font(Theme.Font.amount)
                .foregroundStyle(tone)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(formatter.accessibleString(transaction.amount) + ", " + subtitle)
    }
}
