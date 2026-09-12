import SwiftUI
import SwiftData

/// End-of-month check: did what actually arrived match what you said you earn?
///
/// If your pay has changed, this is where the baseline gets updated — deliberately,
/// with the increase treated as a rise to allocate rather than a new normal.
struct SalaryCheckCard: View {
    @Environment(\.modelContext) private var context
    let check: IncomeEngine.SalaryCheck
    let settings: AppSettings?
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar
    var onAllocateRise: ((Money) -> Void)?

    @State private var didUpdate = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "This month's pay")
                    Spacer()
                    Pill(text: statusLabel, tone: tone)
                }

                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    figure("You said", formatter.string(check.expected))
                    figure("Actually in", formatter.string(check.received))
                    figure("Difference",
                           formatter.string(check.difference, style: .signed),
                           tone: check.difference.isZero ? .neutral
                                 : (check.isRise ? .positive : .caution))
                }

                Text(explanation)
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if check.needsConfirmation && !didUpdate {
                    Divider().opacity(0.4)
                    HStack(spacing: Theme.Space.sm) {
                        if check.status != .nothingReceived {
                            Button(check.isRise ? "Yes — my pay went up" : "Yes — my pay changed") {
                                updateBaseline()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        Button("No, leave it as it is") { didUpdate = true }
                            .controlSize(.small)
                        Spacer()
                    }
                }

                if didUpdate {
                    Text("Noted. Nothing else changed on its own.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusLabel: String {
        switch check.status {
        case .matches: "matches"
        case .more: "more than expected"
        case .less: "less than expected"
        case .nothingReceived: "nothing in yet"
        case .notYetDue: "not due yet"
        }
    }

    private var tone: StatTile.Tone {
        switch check.status {
        case .matches: .positive
        case .more: .positive
        case .less, .nothingReceived: .caution
        case .notYetDue: .neutral
        }
    }

    private var explanation: String {
        switch check.status {
        case .matches:
            return "What arrived matches what you told the app. Everything that reads your "
                 + "income — free to spend, goal dates, loan verdicts — is working from a "
                 + "true number."
        case .more:
            return "\(formatter.string(check.difference.magnitude)) more than expected. If "
                 + "this is a raise rather than a one-off, updating the baseline keeps every "
                 + "projection honest — and the increase gets allocated deliberately instead "
                 + "of quietly becoming your new spending level."
        case .less:
            return "\(formatter.string(check.difference.magnitude)) less than expected. If "
                 + "this is the new normal, update it: a baseline that is too high makes free "
                 + "to spend too generous every single week."
        case .nothingReceived:
            return "Pay day has passed and no income is logged this month. Either it has not "
                 + "arrived, or it has not been entered."
        case .notYetDue:
            return "Pay day has not come round yet this month."
        }
    }

    private func figure(_ label: String, _ value: String,
                        tone: StatTile.Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: label)
            Text(value)
                .font(Theme.Font.figure)
                .foregroundStyle(tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Updates the stored baseline. An increase is recorded as a rise so §4b can
    /// allocate the delta; envelopes are deliberately left exactly where they are.
    private func updateBaseline() {
        guard let settings else { return }
        let previous = settings.expectedMonthlyNetIncome
        settings.expectedMonthlyNetIncome = check.received
        settings.updatedAt = calendar.currentDate()

        if check.isRise, let rise = IncomeEngine.salaryRise(previous: previous,
                                                            current: check.received) {
            let event = IncomeEvent(
                kind: .salaryRise, receivedAt: calendar.currentDate(),
                grossAmount: rise.delta, clientOrSource: "Salary rise"
            )
            context.insert(event)
            onAllocateRise?(rise.delta)
        }
        try? context.save()
        didUpdate = true
    }
}
