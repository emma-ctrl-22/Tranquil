import SwiftUI
import SwiftData

/// The seven stages, where you are, and the evidence for each.
struct LadderView: View {
    @Binding var model: AppModel
    let evaluation: LadderEngine.Evaluation
    let snapshot: LadderEngine.Snapshot
    let formatter: MoneyFormatter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headline
                nextActionCard
                scoreCard
                stagesCard
            }
            .padding(Theme.Space.lg)
        }
    }

    private var headline: some View {
        Card(padding: Theme.Space.lg) {
            HStack(alignment: .top, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(text: "You are working on")
                    Text(evaluation.currentStage.title)
                        .font(.system(size: 26, weight: .light, design: .rounded))
                    Text("Stage \(evaluation.currentStage.rawValue) of 7 · "
                         + "\(evaluation.clearedStages.count) cleared")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    SectionLabel(text: "Runway")
                    Text(runwayText)
                        .font(Theme.Font.figure)
                        .foregroundStyle(runwayTone.color)
                    Text("of essential spend covered")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var runwayText: String {
        guard let months = evaluation.runwayMonths else { return "—" }
        let tenths = Money.roundBankers(months * 10)
        return "\(tenths / 10).\(abs(tenths % 10)) mo"
    }

    private var runwayTone: StatTile.Tone {
        guard let months = evaluation.runwayMonths else { return .neutral }
        if months < 1 { return .negative }
        if months < 3 { return .caution }
        return .positive
    }

    /// One action. Never a to-do list of financial obligations.
    private var nextActionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "Next")
                Text(evaluation.nextAction.title).font(.system(size: 15, weight: .medium))
                Text(evaluation.nextAction.detail)
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Go there") { model.open(evaluation.nextAction.screen) }
                    .controlSize(.small)
                    .padding(.top, Theme.Space.xs)
            }
        }
    }

    /// Always broken into its parts, so it is never a mystery number.
    private var scoreCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "Stability score")
                    Spacer()
                    Text("\(evaluation.stabilityScore.total)")
                        .font(Theme.Font.figure)
                    Text("/ 100").font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Divider().opacity(0.4)
                ForEach(evaluation.stabilityScore.components) { component in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(component.name).font(.system(size: 12))
                            Spacer()
                            Text("\(component.earned) / \(component.available)")
                                .font(Theme.Font.amount).foregroundStyle(.secondary)
                        }
                        MeterBar(fraction: component.fraction,
                                 tone: component.fraction > 0.66 ? .positive
                                       : (component.fraction > 0.33 ? .caution : .negative),
                                 height: 4)
                        Text(component.detail)
                            .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var stagesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "The seven stages")
                ForEach(evaluation.stages) { stage in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Image(systemName: icon(for: stage))
                            .font(.system(size: 12))
                            .foregroundStyle(tone(for: stage).color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text("\(stage.stage.rawValue). \(stage.stage.title)")
                                    .font(.system(size: 12.5,
                                                  weight: stage.stage == evaluation.currentStage
                                                          ? .semibold : .regular))
                                if stage.stage == evaluation.currentStage {
                                    Pill(text: "you are here")
                                }
                            }
                            Text(stage.evidence)
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(stage.isMet ? "cleared" : "not yet")
                }
                Text("Stages are checked continuously. Slipping back is information, not a "
                     + "verdict — the bar simply has not been met this week.")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.xs)
            }
        }
    }

    private func icon(for stage: LadderEngine.StageResult) -> String {
        if stage.isMet { return "checkmark.circle.fill" }
        if stage.stage == evaluation.currentStage { return "circle.dotted" }
        return "circle"
    }

    private func tone(for stage: LadderEngine.StageResult) -> StatTile.Tone {
        if stage.isMet { return .positive }
        if stage.stage == evaluation.currentStage { return .caution }
        return .neutral
    }
}
