import Foundation

/// Envelopes, burn rate and free-to-spend.
///
/// Weekly is the primary unit: a monthly envelope is shown at its weekly pace rather
/// than as a number you have to divide in your head. Miscellaneous is a first-class
/// envelope here, not a leftover — it is where discipline actually breaks.
nonisolated enum BudgetEngine {

    // MARK: - Inputs

    struct EnvelopeInput: Identifiable, Sendable {
        let id: UUID
        /// nil for the Miscellaneous catch-all.
        let categoryID: UUID?
        let name: String
        let icon: String
        let colorHex: String
        let period: BudgetPeriod
        let amount: Money
        let rollover: Bool
        let rolloverCapMultiple: Decimal
        let isMiscellaneous: Bool
        let isEssential: Bool
        /// Unspent from the previous period, already computed by the caller.
        let carriedIn: Money

        init(
            id: UUID, categoryID: UUID?, name: String, icon: String = "circle",
            colorHex: String = "#7C8B9A", period: BudgetPeriod, amount: Money,
            rollover: Bool = false, rolloverCapMultiple: Decimal = 2,
            isMiscellaneous: Bool = false, isEssential: Bool = false,
            carriedIn: Money = .zero
        ) {
            self.id = id
            self.categoryID = categoryID
            self.name = name
            self.icon = icon
            self.colorHex = colorHex
            self.period = period
            self.amount = amount
            self.rollover = rollover
            self.rolloverCapMultiple = rolloverCapMultiple
            self.isMiscellaneous = isMiscellaneous
            self.isEssential = isEssential
            self.carriedIn = carriedIn
        }
    }

    struct CommitmentInput: Identifiable, Sendable {
        let id: UUID
        let label: String
        let amount: Money
        /// How many times a year this falls due, for prorating onto one week.
        let occurrencesPerYear: Int
    }

    // MARK: - Outputs

    /// The state of one envelope at a moment inside its period.
    struct EnvelopeState: Identifiable, Sendable {
        let input: EnvelopeInput
        /// The budget for this week, including any capped rollover.
        let budget: Money
        let spent: Money
        /// 0…1+ of the elapsed period, for the pace marker.
        let expectedFraction: Decimal
        /// How far past pace counts as "ahead". A setting, not a constant.
        let alertMargin: Decimal

        var id: UUID { input.id }
        var name: String { input.name }
        var remaining: Money { budget - spent }
        var isOverspent: Bool { spent > budget }

        /// `spent / budget`. Nil when there is no budget to burn through.
        var burn: Decimal? { spent.ratio(to: budget) }

        /// The spec's alert: `burn - expected > 0.25`.
        /// An envelope with no budget cannot be ahead of pace.
        var isAheadOfPace: Bool {
            guard let burn else { return false }
            return burn - expectedFraction > alertMargin
        }

        /// How far ahead or behind pace, as a fraction. Negative means under pace.
        var paceDelta: Decimal? {
            guard let burn else { return nil }
            return burn - expectedFraction
        }
    }

    struct FreeToSpend: Sendable {
        let expectedIncome: Money
        let committedOutflows: Money
        let goalAllocations: Money
        let alreadySpent: Money

        /// The number actually looked at:
        /// `income − committed − goals − spent`.
        var amount: Money {
            expectedIncome - committedOutflows - goalAllocations - alreadySpent
        }

        var isNegative: Bool { amount.isNegative }
    }

    // MARK: - Envelopes

    /// The budget for one week, including rollover capped so unspent weeks do not
    /// become a licence to splurge.
    static func weeklyBudget(for envelope: EnvelopeInput, daysInMonth: Int) -> Money {
        let base: Money
        switch envelope.period {
        case .weekly:
            base = envelope.amount
        case .monthly:
            // A monthly envelope displays a weekly pace of `monthly x 7 / daysInMonth`.
            guard daysInMonth > 0 else { return .zero }
            base = envelope.amount.scaled(by: Decimal(7) / Decimal(daysInMonth))
        }
        guard envelope.rollover, envelope.carriedIn.isPositive else { return base }
        let ceiling = base.scaled(by: envelope.rolloverCapMultiple)
        return Money.min(base + envelope.carriedIn, ceiling)
    }

    /// Unspent budget to carry into the next period, zero when the envelope does not
    /// roll over or was overspent.
    static func carryOut(for state: EnvelopeState) -> Money {
        guard state.input.rollover else { return .zero }
        return state.remaining.clampedToZero
    }

    static func state(
        for envelope: EnvelopeInput,
        spent: Money,
        elapsedDaysInWeek: Int,
        daysInMonth: Int,
        alertMargin: Decimal = Decimal(string: "0.25")!
    ) -> EnvelopeState {
        EnvelopeState(
            input: envelope,
            budget: weeklyBudget(for: envelope, daysInMonth: daysInMonth),
            spent: spent,
            expectedFraction: expectedFraction(elapsedDaysInWeek: elapsedDaysInWeek),
            alertMargin: alertMargin
        )
    }

    /// `elapsedDaysInWeek / 7`, clamped to the week.
    static func expectedFraction(elapsedDaysInWeek: Int) -> Decimal {
        let days = Swift.max(0, Swift.min(7, elapsedDaysInWeek))
        return Decimal(days) / Decimal(7)
    }

    // MARK: - Commitments

    /// Loan payments, investments, sinking funds and recurring bills, prorated onto one
    /// week. These come off the top, before anything is called free.
    static func weeklyCommitted(_ commitments: [CommitmentInput]) -> Money {
        Money.sum(
            commitments.map { commitment in
                guard commitment.occurrencesPerYear > 0 else { return .zero }
                return commitment.amount.scaled(
                    by: Decimal(commitment.occurrencesPerYear) / Decimal(52)
                )
            }
        )
    }

    // MARK: - Free to spend

    static func freeToSpend(
        expectedIncomeThisWeek: Money,
        commitments: [CommitmentInput],
        goalAllocationsThisWeek: Money,
        alreadySpentThisWeek: Money
    ) -> FreeToSpend {
        FreeToSpend(
            expectedIncome: expectedIncomeThisWeek,
            committedOutflows: weeklyCommitted(commitments),
            goalAllocations: goalAllocationsThisWeek,
            alreadySpent: alreadySpentThisWeek
        )
    }

    // MARK: - Income expectation

    /// Lumpy income uses a **median**, never a mean — one good month should not inflate
    /// every projection. Returns zero for an empty history.
    static func medianWeeklyIncome(trailingWeeks amounts: [Money]) -> Money {
        guard !amounts.isEmpty else { return .zero }
        let sorted = amounts.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            // Mean of the two middles, rounded once.
            return (sorted[middle - 1] + sorted[middle]).split(into: 2).first ?? .zero
        }
        return sorted[middle]
    }

    /// A regular monthly salary spread across the year.
    ///
    /// ASSUMPTION: a monthly salary is regular but lumpy — three weeks in four show no
    /// income, so a trailing weekly median would read zero and free-to-spend would
    /// collapse in every week the salary has not landed. The salaried component is
    /// spread as `monthly x 12 / 52`; genuinely irregular income still uses the median.
    static func weeklyFromMonthly(_ monthly: Money) -> Money {
        monthly.scaled(by: Decimal(12) / Decimal(52))
    }

    /// Combines a steady salary with irregular extras.
    static func expectedWeeklyIncome(
        monthlySalary: Money,
        irregularTrailingWeeks: [Money]
    ) -> Money {
        weeklyFromMonthly(monthlySalary) + medianWeeklyIncome(trailingWeeks: irregularTrailingWeeks)
    }
}
