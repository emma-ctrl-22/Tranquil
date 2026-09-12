import Foundation

/// Goals, the allocation waterfall, and the ETA that answers the iPhone question:
/// how long, which account, where is it now, and what does it cost me.
nonisolated enum GoalEngine {

    // MARK: - Inputs

    struct GoalInput: Identifiable, Sendable {
        let id: UUID
        let name: String
        let targetAmount: Money
        let targetDate: Date?
        /// Manual. The app never reorders the user's priorities.
        let priorityRank: Int
        let holdingAccountID: UUID?
        /// Don't throw everything at one goal.
        let monthlyCap: Money?
        let desireLevel: Int
        let status: GoalStatus
        /// Already set aside, from the earmark against the holding account.
        let saved: Money

        var remaining: Money { (targetAmount - saved).clampedToZero }
        var isFunded: Bool { saved >= targetAmount }

        var fraction: Decimal {
            guard targetAmount.isPositive else { return 0 }
            return saved.ratio(to: targetAmount) ?? 0
        }
    }

    struct FundInput: Identifiable, Sendable {
        let id: UUID
        let name: String
        /// What this fund needs this period to stay on track.
        let requiredThisPeriod: Money
        let isEmergencyFund: Bool
    }

    /// What the current Ladder stage needs before anything else is funded.
    struct LadderRequirement: Sendable {
        let label: String
        let amountThisPeriod: Money

        static let none = LadderRequirement(label: "", amountThisPeriod: .zero)
    }

    // MARK: - Waterfall

    struct Allocation: Identifiable, Sendable {
        let id: UUID
        let label: String
        let amount: Money
        let kind: AllocationDestinationKind
    }

    struct WaterfallResult: Sendable {
        let allocations: [Allocation]
        let leftover: Money
        let surplus: Money

        func amount(forGoal id: UUID) -> Money {
            allocations.first { $0.id == id && $0.kind == .goal }?.amount ?? .zero
        }
    }

    /// One period's surplus flowing down the waterfall:
    /// 1. the current Ladder stage requirement
    /// 2. sinking funds due this period
    /// 3. goals in priority order, each capped
    /// 4. whatever is left
    ///
    /// Nothing is ever taken **out** of the emergency fund here — the allocation engine
    /// only ever adds to it.
    static func waterfall(
        surplus: Money,
        ladderRequirement: LadderRequirement,
        funds: [FundInput],
        goals: [GoalInput]
    ) -> WaterfallResult {
        var remaining = surplus.clampedToZero
        var allocations: [Allocation] = []

        func take(_ wanted: Money, label: String, id: UUID,
                  kind: AllocationDestinationKind) {
            let amount = Money.min(wanted.clampedToZero, remaining)
            guard amount.isPositive else { return }
            allocations.append(Allocation(id: id, label: label, amount: amount, kind: kind))
            remaining -= amount
        }

        if ladderRequirement.amountThisPeriod.isPositive {
            take(ladderRequirement.amountThisPeriod, label: ladderRequirement.label,
                 id: UUID(), kind: .ladderGap)
        }

        // Emergency fund first among funds: it is a Ladder requirement, not a want.
        let orderedFunds = funds.sorted { a, b in
            a.isEmergencyFund == b.isEmergencyFund ? a.name < b.name : a.isEmergencyFund
        }
        for fund in orderedFunds {
            take(fund.requiredThisPeriod, label: fund.name, id: fund.id, kind: .sinkingFund)
        }

        for goal in goals.filter({ $0.status == .saving && !$0.isFunded })
            .sorted(by: { $0.priorityRank < $1.priorityRank }) {
            let wanted = goal.monthlyCap.map { Money.min($0, goal.remaining) } ?? goal.remaining
            take(wanted, label: goal.name, id: goal.id, kind: .goal)
        }

        return WaterfallResult(allocations: allocations, leftover: remaining, surplus: surplus)
    }

    // MARK: - ETA

    struct ETA: Sendable {
        let goalID: UUID
        /// Periods from now until the goal is funded. Nil when it never gets there.
        let periods: Int?
        let date: Date?
        let perPeriod: Money
        let remaining: Money

        var isReachable: Bool { periods != nil }
    }

    /// The first period where cumulative allocation covers what is left.
    ///
    /// Runs the waterfall forward period by period, so a goal's ETA accounts for
    /// everything ahead of it in the queue — which is what makes "what does it cost me"
    /// answerable.
    static func etas(
        surplusPerPeriod: Money,
        ladderRequirement: LadderRequirement,
        funds: [FundInput],
        goals: [GoalInput],
        periodLength: PeriodLength,
        from date: Date,
        calendar: FinancialCalendar,
        maxPeriods: Int = 520
    ) -> [ETA] {
        var progress: [UUID: Money] = [:]
        var result: [UUID: ETA] = [:]
        let active = goals.filter { $0.status == .saving }

        for goal in active {
            progress[goal.id] = goal.saved
            result[goal.id] = ETA(goalID: goal.id, periods: nil, date: nil,
                                  perPeriod: .zero, remaining: goal.remaining)
        }

        guard surplusPerPeriod.isPositive else { return active.compactMap { result[$0.id] } }

        var perPeriodSeen: [UUID: Money] = [:]

        for period in 1...maxPeriods {
            // Re-evaluate with current progress so funded goals stop consuming surplus.
            let snapshot = active.map { goal -> GoalInput in
                GoalInput(
                    id: goal.id, name: goal.name, targetAmount: goal.targetAmount,
                    targetDate: goal.targetDate, priorityRank: goal.priorityRank,
                    holdingAccountID: goal.holdingAccountID, monthlyCap: goal.monthlyCap,
                    desireLevel: goal.desireLevel, status: goal.status,
                    saved: progress[goal.id] ?? .zero
                )
            }
            let step = waterfall(surplus: surplusPerPeriod,
                                 ladderRequirement: ladderRequirement,
                                 funds: funds, goals: snapshot)

            var anyProgress = false
            for allocation in step.allocations where allocation.kind == .goal {
                progress[allocation.id, default: .zero] += allocation.amount
                if perPeriodSeen[allocation.id] == nil {
                    perPeriodSeen[allocation.id] = allocation.amount
                }
                anyProgress = true
            }

            for goal in active where result[goal.id]?.periods == nil {
                let saved = progress[goal.id] ?? .zero
                if saved >= goal.targetAmount {
                    result[goal.id] = ETA(
                        goalID: goal.id, periods: period,
                        date: periodLength.advance(date, by: period, calendar: calendar),
                        perPeriod: perPeriodSeen[goal.id] ?? .zero,
                        remaining: goal.remaining
                    )
                }
            }

            if result.values.allSatisfy({ $0.periods != nil }) { break }
            // Nothing reached the goals this period and nothing will change: stop.
            if !anyProgress && step.leftover == surplusPerPeriod { break }
        }

        // Record the rate even for goals that never arrive, so the UI can show the lever.
        for goal in active where result[goal.id]?.periods == nil {
            result[goal.id] = ETA(goalID: goal.id, periods: nil, date: nil,
                                  perPeriod: perPeriodSeen[goal.id] ?? .zero,
                                  remaining: goal.remaining)
        }

        return active.compactMap { result[$0.id] }
    }

    enum PeriodLength: Sendable {
        case weekly, monthly

        func advance(_ date: Date, by periods: Int, calendar: FinancialCalendar) -> Date {
            switch self {
            case .weekly: calendar.addDays(7 * periods, to: date)
            case .monthly: calendar.addMonths(periods, to: date)
            }
        }

        var perYear: Int {
            switch self {
            case .weekly: 52
            case .monthly: 12
            }
        }
    }

    // MARK: - Levers

    /// "₵250/week → 14 Mar. At ₵400/week → 2 Feb." — the tradeoff, made concrete.
    static func eta(
        forGoal goal: GoalInput,
        atRate perPeriod: Money,
        periodLength: PeriodLength,
        from date: Date,
        calendar: FinancialCalendar
    ) -> ETA {
        guard perPeriod.isPositive, goal.remaining.isPositive else {
            return ETA(goalID: goal.id,
                       periods: goal.remaining.isZero ? 0 : nil,
                       date: goal.remaining.isZero ? date : nil,
                       perPeriod: perPeriod, remaining: goal.remaining)
        }
        let periods = Int(ceil(
            NSDecimalNumber(decimal: goal.remaining.ratio(to: perPeriod) ?? 0).doubleValue
        ))
        let clamped = Swift.max(1, periods)
        return ETA(
            goalID: goal.id, periods: clamped,
            date: periodLength.advance(date, by: clamped, calendar: calendar),
            perPeriod: perPeriod, remaining: goal.remaining
        )
    }

    // MARK: - Cost of a purchase

    /// "₮1,200 = 3 weeks of the iPhone goal." The currency that actually persuades.
    static func costInTime(
        of amount: Money,
        againstGoal goal: GoalInput,
        ratePerPeriod: Money
    ) -> Int? {
        guard ratePerPeriod.isPositive, amount.isPositive else { return nil }
        let periods = NSDecimalNumber(
            decimal: amount.ratio(to: ratePerPeriod) ?? 0
        ).doubleValue
        return Swift.max(1, Int(ceil(periods)))
    }

    // MARK: - Overspend ledger

    struct OverspendEntry: Identifiable, Sendable {
        let id: UUID
        let name: String
        let planned: Money
        let paid: Money
        var variance: Money { paid - planned }
    }

    /// "Wishlist items came in ₮X over plan this year." Present the number, add no
    /// commentary.
    static func overspendTotal(_ entries: [OverspendEntry]) -> Money {
        Money.sum(entries.map(\.variance))
    }

    // MARK: - Earmark invariant

    /// Total earmarked against one account must not exceed its balance.
    /// Returns the excess, or zero when the account is within its means.
    static func overCommitment(earmarked: Money, balance: Money) -> Money {
        (earmarked - balance).clampedToZero
    }
}
