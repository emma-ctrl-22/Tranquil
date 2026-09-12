import Foundation

/// The opinionated layer: a **deterministic rule engine** over `ADVISOR_RULES.md`.
///
/// Not a model, no network, identical output for identical input. Every verdict is
/// reproducible and explainable by pointing at a rule ID.
///
/// It advises on behaviour only — how much, in what order, held where, and what a
/// decision costs. It never selects investments, names products, forecasts returns, or
/// phrases anything as buy or sell.
nonisolated enum AdvisorEngine {

    // MARK: - Rules

    struct Rule: Identifiable, Sendable {
        let id: String
        let title: String
        let rationale: String
        /// R2 is the one rule with no override path.
        let canOverride: Bool
    }

    static let rules: [Rule] = [
        .init(id: "R1",
              title: "No new debt for something that loses value while expensive debt is outstanding",
              rationale: "Borrowing at 30% to buy something losing value is two losses stacked.",
              canOverride: true),
        .init(id: "R2",
              title: "No borrowing to invest. Ever.",
              rationale: "Leverage turns a bad year into a permanent one.",
              canOverride: false),
        .init(id: "R3",
              title: "Untaxed income is not yours until the tax reserve is deducted",
              rationale: "The most common way self-employed people at your stage get destroyed.",
              canOverride: true),
        .init(id: "R4",
              title: "Debt service above the cap is Not affordable, not tight",
              rationale: "Above that ratio you have no room to absorb a bad month.",
              canOverride: true),
        .init(id: "R5",
              title: "Don't invest new money while carrying debt above the high-interest line",
              rationale: "Paying 28% debt is a certain 28%; no investment offers certainty.",
              canOverride: true),
        .init(id: "R6",
              title: "The emergency fund cannot drop below one month without a logged reason",
              rationale: "It only works if it is there when you need it.",
              canOverride: true),
        .init(id: "R7",
              title: "No purchase that drops runway below the current Ladder stage requirement",
              rationale: "Buying a thing should not cost you a stage.",
              canOverride: true),
        .init(id: "R8",
              title: "Instalment plans over six months need an explicit override",
              rationale: "Convert it to a savings goal first and see if you still want it.",
              canOverride: true),
        .init(id: "R9",
              title: "Speculative holdings capped at 5% of net worth, and only from stage 4",
              rationale: "Fine as entertainment, ruinous as a plan.",
              canOverride: true),
        .init(id: "R10",
              title: "Illiquid or locked products are blocked before the emergency fund exists",
              rationale: "Breaking them early costs more than they pay.",
              canOverride: true),
        .init(id: "R11",
              title: "Money lent to friends or family is a receivable at zero expected return",
              rationale: "Be generous if you want to be — just don't count it as wealth.",
              canOverride: true),
    ]

    static func rule(_ id: String) -> Rule? { rules.first { $0.id == id } }

    // MARK: - Order of Operations

    enum Step: Int, CaseIterable, Identifiable, Sendable {
        case taxReserve = 1
        case minimumPayments
        case starterBuffer
        case employerMatch
        case highInterestDebt
        case emergencyFund
        case sinkingFunds
        case investing
        case mediumInterestDebt
        case goals
        case speculation

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .taxReserve: "Tax reserve"
            case .minimumPayments: "Minimum payments on everything"
            case .starterBuffer: "Starter buffer — two weeks of essentials"
            case .employerMatch: "Employer match, if any"
            case .highInterestDebt: "Debt above the high-interest line"
            case .emergencyFund: "Emergency fund"
            case .sinkingFunds: "Sinking funds funded to date"
            case .investing: "Long-term investing, automatic and boring"
            case .mediumInterestDebt: "Medium-interest debt"
            case .goals: "Goals and wants"
            case .speculation: "Speculation, capped"
            }
        }

        var why: String {
            switch self {
            case .taxReserve: "It was never your money."
            case .minimumPayments: "Missed payments cost more than any return."
            case .starterBuffer: "Stops small shocks becoming debt."
            case .employerMatch: "A guaranteed 100% return. Nothing else comes close."
            case .highInterestDebt: "Clearing 28% debt is a guaranteed 28% return."
            case .emergencyFund: "Higher if freelance or single-client: use six months."
            case .sinkingFunds: "Turns surprises into scheduled events."
            case .investing: "Time is the asset you have most of."
            case .mediumInterestDebt: "Below the line, no rush."
            case .goals: "Deliberate, funded, guilt-free."
            case .speculation: "Only from here down."
            }
        }
    }

    /// What the next unit of money should do.
    ///
    /// Distinct from the Ladder, which is *where you are*. This is *what to do next*.
    struct Position: Sendable {
        let step: Step
        let detail: String
    }

    struct Situation: Sendable {
        var taxReserveOwed: Money = .zero
        var hasOverduePayments: Bool = false
        var liquidAvailable: Money = .zero
        var essentialMonthlySpend: Money = .zero
        var hasEmployerMatchAvailable: Bool = false
        var highInterestDebtRemaining: Money = .zero
        var emergencyFundBalance: Money = .zero
        var emergencyFundTargetMonths: Int = 6
        var sinkingFundsBehind: Int = 0
        var investedThisMonth: Bool = false
        var mediumInterestDebtRemaining: Money = .zero
        var goalsOutstanding: Int = 0
        var ladderStage: LadderStage = .visibility
        var netWorth: Money = .zero
        var speculativeHoldings: Money = .zero

        var twoWeeksOfEssentials: Money {
            essentialMonthlySpend.scaled(by: Decimal(string: "0.5")!)
        }
        var emergencyFundTarget: Money {
            essentialMonthlySpend * emergencyFundTargetMonths
        }
    }

    /// The advisor never recommends a step while an earlier one is unmet.
    static func position(_ situation: Situation) -> Position {
        if situation.taxReserveOwed.isPositive {
            return Position(step: .taxReserve,
                            detail: "Set aside what is owed before anything else happens to it.")
        }
        if situation.hasOverduePayments {
            return Position(step: .minimumPayments,
                            detail: "Something is overdue. Nothing else earns more than fixing that.")
        }
        if situation.essentialMonthlySpend.isPositive,
           situation.liquidAvailable < situation.twoWeeksOfEssentials {
            return Position(step: .starterBuffer,
                            detail: "Two weeks of essentials, liquid, before anything is committed.")
        }
        if situation.hasEmployerMatchAvailable {
            return Position(step: .employerMatch,
                            detail: "Free money. Take all of it before any other use.")
        }
        if situation.highInterestDebtRemaining.isPositive {
            return Position(step: .highInterestDebt,
                            detail: "A guaranteed return equal to the rate you are paying.")
        }
        if situation.essentialMonthlySpend.isPositive,
           situation.emergencyFundBalance < situation.emergencyFundTarget {
            return Position(step: .emergencyFund,
                            detail: "\(situation.emergencyFundTargetMonths) months of essentials, "
                                  + "then leave it alone.")
        }
        if situation.sinkingFundsBehind > 0 {
            return Position(step: .sinkingFunds,
                            detail: "\(situation.sinkingFundsBehind) fund(s) behind. This is what "
                                  + "turns surprises into scheduled expenses.")
        }
        if !situation.investedThisMonth {
            return Position(step: .investing,
                            detail: "Automatic and boring, every month, whatever the amount.")
        }
        if situation.mediumInterestDebtRemaining.isPositive {
            return Position(step: .mediumInterestDebt,
                            detail: "Below the high-interest line. Steady, no rush.")
        }
        if situation.goalsOutstanding > 0 {
            return Position(step: .goals, detail: "Funded deliberately, and spent without guilt.")
        }
        return Position(step: .speculation,
                        detail: "Capped at 5% of net worth. Entertainment, not a plan.")
    }

    // MARK: - Verdicts

    struct Finding: Identifiable, Sendable {
        let ruleID: String
        let title: String
        let detail: String
        let blocks: Bool
        let canOverride: Bool

        var id: String { ruleID }
    }

    struct Assessment: Sendable {
        let verdict: Verdict
        let findings: [Finding]
        /// The arithmetic, always shown.
        let arithmetic: [(label: String, value: String)]
        let summary: String

        var blockingFindings: [Finding] { findings.filter(\.blocks) }
        var requiresOverride: Bool { !blockingFindings.isEmpty }
        /// R2 has no override path at all.
        var isAbsolutelyBlocked: Bool { blockingFindings.contains { !$0.canOverride } }
    }

    /// A purchase or commitment, checked against the hard rules.
    struct Proposal: Sendable {
        var amount: Money = .zero
        var isDepreciatingAsset: Bool = false
        var isBorrowedToInvest: Bool = false
        var isInvestment: Bool = false
        var isIlliquidOrLocked: Bool = false
        var isSpeculative: Bool = false
        var instalmentMonths: Int = 0
        var fromEmergencyFund: Bool = false
    }

    static func assess(
        _ proposal: Proposal,
        situation: Situation,
        formatter: MoneyFormatter
    ) -> Assessment {
        var findings: [Finding] = []

        func add(_ id: String, _ detail: String, blocks: Bool = true) {
            guard let rule = rule(id) else { return }
            findings.append(Finding(ruleID: rule.id, title: rule.title, detail: detail,
                                    blocks: blocks, canOverride: rule.canOverride))
        }

        // R2 first: it is the only rule with no way past it.
        if proposal.isBorrowedToInvest {
            add("R2", "Borrowing to invest turns a bad year into a permanent one. There is no "
                    + "override for this one.")
        }

        if proposal.isDepreciatingAsset && situation.highInterestDebtRemaining.isPositive {
            add("R1", "You are carrying "
                    + formatter.string(situation.highInterestDebtRemaining)
                    + " above your high-interest line.")
        }

        if proposal.isInvestment && situation.highInterestDebtRemaining.isPositive {
            add("R5", "Clearing that debt is a certain return equal to its rate. No investment "
                    + "offers certainty.")
        }

        if proposal.fromEmergencyFund {
            let oneMonth = situation.essentialMonthlySpend
            let after = situation.emergencyFundBalance - proposal.amount
            if after < oneMonth {
                add("R6", "That leaves " + formatter.string(after.clampedToZero)
                        + " in the emergency fund, under one month of essentials.")
            }
        }

        if proposal.instalmentMonths > 6 {
            add("R8", "\(proposal.instalmentMonths) months converts a one-time choice into "
                    + "years of reduced flexibility.")
        }

        if proposal.isSpeculative {
            if situation.ladderStage < .emergencyFund {
                add("R9", "Speculation starts at Ladder stage 4. You are at stage "
                        + "\(situation.ladderStage.rawValue).")
            } else {
                let cap = situation.netWorth.scaled(by: Decimal(string: "0.05")!)
                let after = situation.speculativeHoldings + proposal.amount
                if after > cap {
                    add("R9", "That takes speculative holdings to " + formatter.string(after)
                            + ", above the 5% cap of " + formatter.string(cap) + ".")
                }
            }
        }

        if proposal.isIlliquidOrLocked,
           situation.emergencyFundBalance < situation.emergencyFundTarget {
            add("R10", "Locked money before the emergency fund exists costs more than it pays "
                     + "when you have to break it early.")
        }

        // Runway: does this purchase cost a stage?
        var arithmetic: [(String, String)] = []
        if situation.essentialMonthlySpend.isPositive {
            let after = situation.liquidAvailable - proposal.amount
            let runwayAfter = after.ratio(to: situation.essentialMonthlySpend) ?? 0
            arithmetic.append(("Liquid now", formatter.string(situation.liquidAvailable)))
            arithmetic.append(("After this", formatter.string(after)))
            arithmetic.append(("Runway after", months(runwayAfter)))
            if after < situation.twoWeeksOfEssentials
                && situation.liquidAvailable >= situation.twoWeeksOfEssentials {
                add("R7", "That drops you under two weeks of essentials, which costs you a "
                        + "Ladder stage.")
            }
        }
        if situation.taxReserveOwed.isPositive {
            arithmetic.append(("Tax reserve owed", formatter.string(situation.taxReserveOwed)))
        }

        let verdict: Verdict
        if findings.contains(where: { $0.blocks && !$0.canOverride }) {
            verdict = .blocked
        } else if findings.contains(where: \.blocks) {
            verdict = .blocked
        } else if !findings.isEmpty {
            verdict = .approvedWithConditions
        } else if situation.taxReserveOwed.isPositive {
            verdict = .approvedWithConditions
        } else {
            verdict = .approved
        }

        return Assessment(
            verdict: verdict, findings: findings, arithmetic: arithmetic,
            summary: summary(verdict: verdict, proposal: proposal, situation: situation,
                             formatter: formatter)
        )
    }

    /// Never "you cannot afford that". Always what it costs, and then your call.
    private static func summary(
        verdict: Verdict, proposal: Proposal, situation: Situation, formatter: MoneyFormatter
    ) -> String {
        switch verdict {
        case .approved:
            return formatter.string(proposal.amount) + ". Nothing here objects."
        case .approvedWithConditions:
            return formatter.string(proposal.amount)
                 + ". Fine, in the order set out above. Your call."
        case .notAdvised:
            return formatter.string(proposal.amount)
                 + ". Allowed, and here is precisely what it costs."
        case .blocked:
            return formatter.string(proposal.amount)
                 + ". A hard rule says no. You can still do it, with a reason that gets kept."
        }
    }

    private static func months(_ value: Decimal) -> String {
        let tenths = Money.roundBankers(value * 10)
        return "\(tenths / 10).\(abs(tenths % 10)) months"
    }

    // MARK: - Cost in time

    /// "₵1,200 = 3 weeks of the iPhone." The currency that actually persuades.
    static func costInTime(
        of amount: Money, goalName: String, weeklyRate: Money, formatter: MoneyFormatter
    ) -> String? {
        guard weeklyRate.isPositive, amount.isPositive else { return nil }
        let weeks = Swift.max(1, Int(ceil(
            NSDecimalNumber(decimal: amount.ratio(to: weeklyRate) ?? 0).doubleValue
        )))
        return formatter.string(amount) + " = \(weeks) \(weeks == 1 ? "week" : "weeks") of "
             + goalName
    }

    // MARK: - The monthly letter

    struct LetterInput: Sendable {
        var monthName: String = ""
        var headlineLabel: String = ""
        var headlineValue: String = ""
        var whatWentRight: [String] = []
        var whatToChange: [String] = []
        var creepRatio: Decimal?
        var creepIsRising: Bool = false
        var creepDrivers: [String] = []
        var instruction: String = ""
        var overrideCount: Int = 0
        var overrideCost: Money = .zero
    }

    /// §6, generated from templates and real numbers. Deterministic and offline.
    /// No exclamation marks, no emoji, no encouragement filler.
    static func monthlyLetter(_ input: LetterInput, formatter: MoneyFormatter) -> String {
        var lines: [String] = []
        lines.append(input.monthName)
        lines.append("")

        lines.append("The number that matters")
        lines.append("\(input.headlineLabel): \(input.headlineValue)")
        lines.append("")

        if !input.whatWentRight.isEmpty {
            lines.append("What went right")
            for item in input.whatWentRight { lines.append("— \(item)") }
            lines.append("")
        }

        if !input.whatToChange.isEmpty {
            lines.append("What I would change")
            // At most two, the two largest by impact.
            for item in input.whatToChange.prefix(2) { lines.append("— \(item)") }
            lines.append("")
        }

        lines.append("The creep check")
        if let ratio = input.creepRatio {
            let percent = Money.roundBankers(ratio * 100)
            lines.append("Essentials are \(percent)% of net income.")
            if input.creepIsRising {
                let drivers = input.creepDrivers.isEmpty
                    ? "" : " The movement is in \(input.creepDrivers.joined(separator: ", "))."
                lines.append("That share has risen for two consecutive quarters." + drivers)
            } else {
                lines.append("That share is not rising.")
            }
        } else {
            lines.append("Not enough income history yet to measure it.")
        }
        lines.append("")

        if input.overrideCount > 0 {
            lines.append("Overrides")
            let cost = input.overrideCost.isZero
                ? "" : ", costing \(formatter.string(input.overrideCost))"
            lines.append("\(input.overrideCount) this month\(cost).")
            lines.append("")
        }

        lines.append("One thing for next month")
        lines.append(input.instruction)

        return lines.joined(separator: "\n")
    }
}
