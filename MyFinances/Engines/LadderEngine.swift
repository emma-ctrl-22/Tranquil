import Foundation

/// The Tranquility Ladder: where you actually are, and the **one** next thing to do.
///
/// Falling back is reported honestly and without shame language — "the buffer dipped
/// below two weeks", never "you failed".
nonisolated enum LadderEngine {

    // MARK: - Inputs

    /// Everything the ladder needs, gathered once by the caller.
    struct Snapshot: Sendable {
        /// Spendable today, after earmarks, excluding the tax reserve.
        var liquidAvailable: Money
        /// Trailing three-month median of essential spend, per month.
        var essentialMonthlySpend: Money
        /// Financial days logged in the last 28.
        var daysLoggedLast28: Int
        /// Days since any account was reconciled; nil if never.
        var daysSinceReconciliation: Int?
        /// Loan payments currently overdue.
        var overdueLoanCount: Int
        /// Days since the most recent late payment; nil if there has never been one.
        var daysSinceLastLatePayment: Int?
        /// Recurring bills falling due in the next 30 days.
        var billsDueNext30Days: Money
        /// Lowest projected balance over the next 30 days.
        var projectedLowNext30Days: Money
        /// Loans above the high-interest line or owed to family, still outstanding.
        var toxicDebtRemaining: Money
        /// Earmarked in the designated emergency-fund account.
        var emergencyFundBalance: Money
        /// Days since anything was taken out of the emergency fund; nil if never touched.
        var daysSinceEmergencyFundWithdrawal: Int?
        /// Sinking funds that are at or above their required-to-date balance.
        var sinkingFundsOnTrack: Int
        var sinkingFundsTotal: Int
        /// Monthly debt payments over median monthly net income.
        var debtServiceRatio: Decimal
        /// Highest APR still carried, as a fraction.
        var highestRemainingAPR: Decimal
        /// Months out of the last twelve with an investment contribution.
        var investmentMonthsLast12: Int
        /// Months out of the last six with an investment contribution.
        var investmentMonthsLast6: Int
        /// Consecutive months for which stages 0–6 have all held.
        var monthsAllStagesHeld: Int
        /// Scheduled payments met on time, out of those due, over the trailing year.
        var onTimePaymentsRatio: Decimal
        /// Envelopes finishing inside budget, out of those with a budget, trailing 8 weeks.
        var budgetAdherenceRatio: Decimal
        var emergencyFundTargetMonths: Int
        /// Stage 6 thresholds and the scoring curves, all configurable in Settings.
        var stage6MaxDebtService: Decimal = Decimal(string: "0.20")!
        var stage6MaxAPR: Decimal = Decimal(string: "0.15")!
        var runwayFullMarksMonths: Int = 6
        var debtServiceZeroScore: Decimal = Decimal(string: "0.40")!
    }

    // MARK: - Outputs

    struct StageResult: Identifiable, Sendable {
        let stage: LadderStage
        let isMet: Bool
        /// The arithmetic, so a stage is never a mystery.
        let evidence: String

        var id: Int { stage.rawValue }
    }

    struct Evaluation: Sendable {
        let stages: [StageResult]
        /// The lowest stage not yet met — the one you are working on.
        let currentStage: LadderStage
        let runwayMonths: Decimal?
        let stabilityScore: Score
        let nextAction: Action

        /// Stages cleared, in order, up to the first gap.
        var clearedStages: [StageResult] {
            var result: [StageResult] = []
            for stage in stages {
                guard stage.isMet else { break }
                result.append(stage)
            }
            return result
        }

        func result(for stage: LadderStage) -> StageResult? {
            stages.first { $0.stage == stage }
        }
    }

    /// One action at a time. Never a list of twelve.
    struct Action: Sendable {
        let title: String
        let detail: String
        let screen: AppModel.Screen
    }

    // MARK: - Stage evaluation

    static func evaluate(_ snapshot: Snapshot) -> Evaluation {
        let stages = LadderStage.allCases.map { stage in
            StageResult(stage: stage,
                        isMet: isMet(stage, snapshot: snapshot),
                        evidence: evidence(for: stage, snapshot: snapshot))
        }
        let current = stages.first { !$0.isMet }?.stage ?? .tranquil
        return Evaluation(
            stages: stages,
            currentStage: current,
            runwayMonths: runwayMonths(snapshot),
            stabilityScore: score(snapshot),
            nextAction: action(for: current, snapshot: snapshot)
        )
    }

    static func isMet(_ stage: LadderStage, snapshot: Snapshot) -> Bool {
        switch stage {
        case .visibility:
            // Logged 21 of the last 28 days, and reconciled within the last 7.
            return snapshot.daysLoggedLast28 >= 21
                && (snapshot.daysSinceReconciliation.map { $0 <= 7 } ?? false)

        case .twoWeekBuffer:
            guard snapshot.essentialMonthlySpend.isPositive else { return false }
            return snapshot.liquidAvailable >= twoWeeksOfEssentials(snapshot)

        case .nothingLate:
            let noOverdue = snapshot.overdueLoanCount == 0
            let cleanFor60 = snapshot.daysSinceLastLatePayment.map { $0 >= 60 } ?? true
            let billsCovered = snapshot.projectedLowNext30Days >= .zero
            return noOverdue && cleanFor60 && billsCovered

        case .toxicDebtGone:
            return snapshot.toxicDebtRemaining.isZero

        case .emergencyFund:
            guard snapshot.essentialMonthlySpend.isPositive else { return false }
            let target = snapshot.essentialMonthlySpend * snapshot.emergencyFundTargetMonths
            let untouched = snapshot.daysSinceEmergencyFundWithdrawal.map { $0 >= 90 } ?? true
            return snapshot.emergencyFundBalance >= target && untouched

        case .sinkingFundsCurrent:
            guard snapshot.sinkingFundsTotal > 0 else { return false }
            return snapshot.sinkingFundsOnTrack == snapshot.sinkingFundsTotal

        case .debtSmallAndCheap:
            return snapshot.debtServiceRatio <= snapshot.stage6MaxDebtService
                && snapshot.highestRemainingAPR <= snapshot.stage6MaxAPR

        case .tranquil:
            // Everything below, held together for six months, with investing kept up.
            let lower = LadderStage.allCases.filter { $0 != .tranquil }
            let allHold = lower.allSatisfy { isMet($0, snapshot: snapshot) }
            return allHold && snapshot.monthsAllStagesHeld >= 6
                && snapshot.investmentMonthsLast6 >= 5
        }
    }

    static func twoWeeksOfEssentials(_ snapshot: Snapshot) -> Money {
        // Half a month, rounded once.
        snapshot.essentialMonthlySpend.scaled(by: Decimal(string: "0.5")!)
    }

    /// `liquidAvailable / essentialMonthlySpend`. Nil when there is no spend history
    /// to divide by — an unknown runway, not an infinite one.
    static func runwayMonths(_ snapshot: Snapshot) -> Decimal? {
        guard snapshot.essentialMonthlySpend.isPositive else { return nil }
        return snapshot.liquidAvailable.ratio(to: snapshot.essentialMonthlySpend)
    }

    // MARK: - Evidence

    static func evidence(for stage: LadderStage, snapshot: Snapshot) -> String {
        switch stage {
        case .visibility:
            let reconciled = snapshot.daysSinceReconciliation
                .map { "reconciled \($0) days ago" } ?? "never reconciled"
            return "\(snapshot.daysLoggedLast28) of the last 28 days logged, \(reconciled)."
        case .twoWeekBuffer:
            return "Two weeks of essentials is the bar."
        case .nothingLate:
            return snapshot.overdueLoanCount == 0
                ? "No overdue payments. Next 30 days projected to stay in credit."
                : "\(snapshot.overdueLoanCount) payment(s) overdue."
        case .toxicDebtGone:
            return snapshot.toxicDebtRemaining.isZero
                ? "Nothing above your high-interest line, nothing owed to family."
                : "Expensive or personal debt still outstanding."
        case .emergencyFund:
            return "\(snapshot.emergencyFundTargetMonths) months of essentials, earmarked "
                 + "and left alone for 90 days."
        case .sinkingFundsCurrent:
            return "\(snapshot.sinkingFundsOnTrack) of \(snapshot.sinkingFundsTotal) funds "
                 + "at or above where they should be."
        case .debtSmallAndCheap:
            return "Debt service at or under "
                 + "\(Money.roundBankers(snapshot.stage6MaxDebtService * 100))% of income, "
                 + "nothing above \(Money.roundBankers(snapshot.stage6MaxAPR * 100))% APR."
        case .tranquil:
            return "Stages 0–6 held together for six months, invested in five of the last six."
        }
    }

    // MARK: - Stability score

    /// Never a mystery number: it always arrives with its parts.
    struct Score: Sendable {
        struct Component: Identifiable, Sendable {
            let name: String
            let earned: Int
            let available: Int
            let detail: String

            var id: String { name }
            var fraction: Double {
                available > 0 ? Double(earned) / Double(available) : 0
            }
        }

        let components: [Component]
        var total: Int { components.reduce(0) { $0 + $1.earned } }
        var available: Int { components.reduce(0) { $0 + $1.available } }
    }

    /// runway 30 · debt-service 20 · on-time 15 · logging 10 · sinking funds 10 ·
    /// budget adherence 10 · investment consistency 5
    static func score(_ snapshot: Snapshot) -> Score {
        // Runway: full marks at the configured number of months of essentials.
        let runway = runwayMonths(snapshot) ?? 0
        let runwayFraction = clamp(runway / Decimal(Swift.max(1, snapshot.runwayFullMarksMonths)))
        let runwayPoints = points(runwayFraction, of: 30)

        // Debt service: full marks at zero, nothing at or above 40%.
        let zeroAt = snapshot.debtServiceZeroScore > 0
            ? snapshot.debtServiceZeroScore : Decimal(string: "0.40")!
        let debtFraction = clamp(1 - (snapshot.debtServiceRatio / zeroAt))
        let debtPoints = points(debtFraction, of: 20)

        let onTimePoints = points(clamp(snapshot.onTimePaymentsRatio), of: 15)

        let loggingFraction = clamp(Decimal(snapshot.daysLoggedLast28) / 28)
        let loggingPoints = points(loggingFraction, of: 10)

        let fundsFraction = snapshot.sinkingFundsTotal > 0
            ? clamp(Decimal(snapshot.sinkingFundsOnTrack) / Decimal(snapshot.sinkingFundsTotal))
            : 0
        let fundsPoints = points(fundsFraction, of: 10)

        let budgetPoints = points(clamp(snapshot.budgetAdherenceRatio), of: 10)

        // Consistency beats size: this measures months contributed, never the amount.
        let investFraction = clamp(Decimal(snapshot.investmentMonthsLast12) / 12)
        let investPoints = points(investFraction, of: 5)

        return Score(components: [
            .init(name: "Runway", earned: runwayPoints, available: 30,
                  detail: runwayDetail(runway)),
            .init(name: "Debt service", earned: debtPoints, available: 20,
                  detail: "\(percent(snapshot.debtServiceRatio)) of income goes to debt"),
            .init(name: "Paid on time", earned: onTimePoints, available: 15,
                  detail: "\(percent(snapshot.onTimePaymentsRatio)) of payments met on time"),
            .init(name: "Logging", earned: loggingPoints, available: 10,
                  detail: "\(snapshot.daysLoggedLast28) of the last 28 days"),
            .init(name: "Sinking funds", earned: fundsPoints, available: 10,
                  detail: snapshot.sinkingFundsTotal > 0
                      ? "\(snapshot.sinkingFundsOnTrack) of \(snapshot.sinkingFundsTotal) on track"
                      : "none set up yet"),
            .init(name: "Budget adherence", earned: budgetPoints, available: 10,
                  detail: "\(percent(snapshot.budgetAdherenceRatio)) of envelopes held"),
            .init(name: "Investing", earned: investPoints, available: 5,
                  detail: "\(snapshot.investmentMonthsLast12) of the last 12 months"),
        ])
    }

    private static func runwayDetail(_ months: Decimal) -> String {
        guard months > 0 else { return "no runway yet" }
        let tenths = Money.roundBankers(months * 10)
        return "\(tenths / 10).\(abs(tenths % 10)) months of essentials covered"
    }

    private static func clamp(_ value: Decimal) -> Decimal {
        Swift.min(Swift.max(value, 0), 1)
    }

    private static func points(_ fraction: Decimal, of available: Int) -> Int {
        Money.roundBankers(fraction * Decimal(available))
    }

    private static func percent(_ value: Decimal) -> String {
        "\(Money.roundBankers(value * 100))%"
    }

    // MARK: - The one next action

    static func action(for stage: LadderStage, snapshot: Snapshot) -> Action {
        switch stage {
        case .visibility:
            if snapshot.daysLoggedLast28 < 21 {
                return Action(
                    title: "Log what you spend, most days",
                    detail: "\(snapshot.daysLoggedLast28) of the last 28 days are logged. "
                          + "21 is the bar. Nothing else here works without it.",
                    screen: .ledger
                )
            }
            return Action(
                title: "Reconcile one account",
                detail: "Count what is actually there and check it against the ledger.",
                screen: .accounts
            )

        case .twoWeekBuffer:
            let gap = (twoWeeksOfEssentials(snapshot) - snapshot.liquidAvailable).clampedToZero
            return Action(
                title: "Build a two-week buffer",
                detail: "Two weeks of essentials stops a small shock becoming debt. "
                      + "You are short by the buffer gap.",
                screen: .plan
            ).with(gap: gap)

        case .nothingLate:
            return Action(
                title: "Cover what is already due",
                detail: snapshot.overdueLoanCount > 0
                    ? "\(snapshot.overdueLoanCount) payment(s) are overdue. Missed payments "
                      + "cost more than any return."
                    : "A day in the next month projects below zero. Move something, or find "
                      + "the shortfall before then.",
                screen: snapshot.overdueLoanCount > 0 ? .debt : .plan
            )

        case .toxicDebtGone:
            return Action(
                title: "Clear the expensive debt",
                detail: "Clearing debt above your high-interest line is a guaranteed return "
                      + "that no investment can promise.",
                screen: .debt
            )

        case .emergencyFund:
            return Action(
                title: "Fill the emergency fund",
                detail: "\(snapshot.emergencyFundTargetMonths) months of essentials, earmarked, "
                      + "and then left alone.",
                screen: .goals
            )

        case .sinkingFundsCurrent:
            return Action(
                title: "Catch the sinking funds up",
                detail: "\(snapshot.sinkingFundsTotal - snapshot.sinkingFundsOnTrack) fund(s) are "
                      + "behind where they should be. This is what turns surprises into "
                      + "scheduled expenses.",
                screen: .plan
            )

        case .debtSmallAndCheap:
            return Action(
                title: "Bring debt service under 20%",
                detail: "Debt is at \(percent(snapshot.debtServiceRatio)) of income. Under "
                      + "\(percent(snapshot.stage6MaxDebtService)), with nothing above "
                      + "\(percent(snapshot.stage6MaxAPR)) APR, it stops constraining you.",
                screen: .debt
            )

        case .tranquil:
            return Action(
                title: "Hold it",
                detail: "Everything is where it should be. Tranquility is six consecutive "
                      + "months of this, not a single good one.",
                screen: .ladder
            )
        }
    }
}

private extension LadderEngine.Action {
    /// Appends the arithmetic when there is a gap worth naming.
    func with(gap: Money) -> LadderEngine.Action {
        guard gap.isPositive else { return self }
        return LadderEngine.Action(title: title, detail: detail, screen: screen)
    }
}
