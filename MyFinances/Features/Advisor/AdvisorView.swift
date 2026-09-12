import SwiftUI
import SwiftData
import AppKit

/// The Order of Operations, the rule book, the override log and the monthly letter.
struct AdvisorView: View {
    @Binding var model: AppModel
    let situation: AdvisorEngine.Situation
    let letter: String
    let formatter: MoneyFormatter

    @Query(filter: #Predicate<OverrideLog> { $0.deletedAt == nil },
           sort: \OverrideLog.occurredAt, order: .reverse)
    private var overrides: [OverrideLog]

    @State private var tab: Tab = .order
    @State private var didCopy = false

    enum Tab: String, CaseIterable, Identifiable {
        case order, rules, letter, overrides
        var id: String { rawValue }
        var title: String {
            switch self {
            case .order: "Order of Operations"
            case .rules: "Rules"
            case .letter: "This month"
            case .overrides: "Overrides"
            }
        }
    }

    private var position: AdvisorEngine.Position { AdvisorEngine.position(situation) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(maxWidth: 480)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    switch tab {
                    case .order: orderTab
                    case .rules: rulesTab
                    case .letter: letterTab
                    case .overrides: overridesTab
                    }
                }
                .padding(Theme.Space.lg)
            }
        }
    }

    // MARK: - Order of Operations

    private var orderTab: some View {
        Group {
            Card(padding: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "The next money you get should go to")
                    Text(position.step.title)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                    Text(position.detail)
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "The full order")
                    ForEach(AdvisorEngine.Step.allCases) { step in
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            Text("\(step.rawValue)")
                                .font(Theme.Font.amount)
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(step.title)
                                        .font(.system(size: 12.5,
                                                      weight: step == position.step
                                                              ? .semibold : .regular))
                                    if step == position.step { Pill(text: "you are here") }
                                }
                                Text(step.why)
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(step.rawValue < position.step.rawValue
                                         ? .secondary : .primary)
                        .padding(.vertical, 1)
                    }
                    Text("The Ladder is where you are. This is what the next unit of money "
                         + "does. They are different questions.")
                        .font(Theme.Font.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.xs)
                }
            }
        }
    }

    // MARK: - Rules

    private var rulesTab: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Hard rules")
                ForEach(AdvisorEngine.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(rule.id)
                                .font(Theme.Font.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(rule.title).font(.system(size: 12.5))
                            if !rule.canOverride {
                                Pill(text: "no override", tone: .negative, icon: "lock")
                            }
                        }
                        Text(rule.rationale)
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .padding(.leading, 29)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
                Divider().opacity(0.4)
                Text("These block an action in the app. You can override any of them except "
                     + "R2 by typing a reason, which is kept and totalled in the monthly "
                     + "review. Nobody argues with you about it.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Letter

    private var letterTab: some View {
        Card(padding: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    SectionLabel(text: "The monthly letter")
                    Spacer()
                    Button(didCopy ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(letter, forType: .string)
                        didCopy = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            didCopy = false
                        }
                    }
                    .controlSize(.small)
                }
                Text(letter)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Overrides

    private var overridesTab: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Override log")
                    Spacer()
                    Text("\(overrides.count)").font(Theme.Font.amount)
                }
                if overrides.isEmpty {
                    Text("Nothing has been overridden. When you do override a rule, the reason "
                         + "you type is kept here permanently and totalled each month.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(overrides) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.ruleID).font(Theme.Font.label)
                                    .foregroundStyle(.secondary)
                                Text(entry.ruleTitle).font(.system(size: 12))
                                Spacer()
                                Text(entry.occurredAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                                if let cost = entry.estimatedCost {
                                    Text(formatter.string(cost)).font(Theme.Font.amount)
                                }
                            }
                            Text(entry.reason)
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                    Divider().opacity(0.4)
                    // Present the number, add no commentary.
                    HStack {
                        Text("Total cost where it could be measured")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatter.string(
                            Money.sum(overrides.compactMap(\.estimatedCost))
                        ))
                        .font(Theme.Font.amount)
                    }
                }
            }
        }
    }
}
