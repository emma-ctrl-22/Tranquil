import SwiftUI

/// One loan: its schedule, and what adding a little each month would do.
struct LoanDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let position: LoanEngine.Position
    let formatter: MoneyFormatter
    let calendar: FinancialCalendar

    @State private var extraText = ""
    @State private var isPaying = false
    let onRecordPayment: () -> Void

    private var extra: Money { formatter.parse(extraText) ?? .zero }

    private var simulation: LoanEngine.Simulation? {
        guard extra.isPositive else { return nil }
        return LoanEngine.simulateExtra(extra, on: position.loan, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    facts
                    simulator
                    scheduleTable
                }
                .padding(Theme.Space.lg)
            }
            Divider().opacity(0.5)
            HStack {
                if !position.isPaidOff && position.loan.direction == .iOwe {
                    Button("Record a payment") {
                        dismiss()
                        onRecordPayment()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 560, height: 680)
        .background(Theme.Palette.surface(scheme))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(position.loan.name).font(Theme.Font.title)
            Text(position.loan.lender).font(Theme.Font.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.lg)
    }

    private var facts: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                row("Remaining", formatter.string(position.remainingBalance), emphasised: true)
                row("Regular payment", formatter.string(position.regularPayment))
                row("Payments made", "\(position.paymentsMade) of \(position.scheduledPayments)")
                row("Interest still to pay", formatter.string(position.interestRemaining))
                if let date = position.payoffDate {
                    row("Projected payoff", date.formatted(date: .abbreviated, time: .omitted))
                }
                if position.loan.lateCount > 0 {
                    row("Late payments", "\(position.loan.lateCount)")
                }
                if position.loan.socialWeight >= 4 {
                    Divider().opacity(0.4)
                    Text("Borrowed from someone you know. That is a real cost even at zero "
                         + "interest, and the Peace of mind order clears it first.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var simulator: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionLabel(text: "If I paid a bit more")
                HStack {
                    TextField("0.00", text: $extraText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("extra each payment").font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                if let simulation {
                    Divider().opacity(0.4)
                    if simulation.periodsSaved == 0 && simulation.interestSaved.isZero {
                        Text("No change at that amount.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            if let base = simulation.basePayoffDate,
                               let new = simulation.newPayoffDate {
                                Text("Payoff moves from "
                                     + base.formatted(date: .abbreviated, time: .omitted)
                                     + " to "
                                     + new.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12.5))
                            }
                            Text("\(simulation.periodsSaved) fewer payments"
                                 + (simulation.interestSaved.isPositive
                                    ? ", saving \(formatter.string(simulation.interestSaved)) in interest."
                                    : "."))
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                            if simulation.interestSaved.isZero {
                                Text("On a flat-rate loan the interest is fixed at signing, so "
                                     + "paying early clears it sooner but saves nothing. That is "
                                     + "what makes flat rates expensive.")
                                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var scheduleTable: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel(text: "Schedule")
                    Spacer()
                    Text("\(position.schedule.periodCount) payments · "
                         + "\(formatter.string(position.schedule.totalInterest)) interest")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("#").frame(width: 26, alignment: .leading)
                    Text("Date").frame(width: 92, alignment: .leading)
                    Text("Payment").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Principal").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Interest").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Balance").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)

                ForEach(position.schedule.instalments) { instalment in
                    HStack {
                        Text("\(instalment.number)")
                            .frame(width: 26, alignment: .leading)
                            .foregroundStyle(instalment.number <= position.paymentsMade
                                             ? .tertiary : .secondary)
                        Text(instalment.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                            .frame(width: 92, alignment: .leading)
                        Text(formatter.string(instalment.payment))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatter.string(instalment.principal))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatter.string(instalment.interest))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatter.string(instalment.balance))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(Theme.Font.amount)
                    .foregroundStyle(instalment.number <= position.paymentsMade
                                     ? .tertiary : .primary)
                }
            }
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
        .accessibilityElement(children: .combine)
    }
}
