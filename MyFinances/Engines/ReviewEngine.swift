import Foundation

/// The weekly and monthly reviews. Deterministic, offline, templated from real numbers.
///
/// Tone rules are enforced here as much as in the copy: state the facts and the
/// consequence, no exclamation marks, no encouragement filler, never moralise.
nonisolated enum ReviewEngine {

    struct EnvelopeLine: Identifiable, Sendable {
        let id: UUID
        let name: String
        let budget: Money
        let spent: Money
        var variance: Money { budget - spent }
        var isOver: Bool { spent > budget }
    }

    struct ExpenseLine: Identifiable, Sendable {
        let id: UUID
        let label: String
        let amount: Money
        let date: Date
    }

    struct Weekly: Sendable {
        let weekStart: Date
        let envelopes: [EnvelopeLine]
        let biggestExpenses: [ExpenseLine]
        let totalSpent: Money
        let totalIncome: Money
        let streak: Int
        let daysLogged: Int
        let needsReviewCount: Int
        let goalsMoved: [String]
        /// One suggestion. Not a list.
        let suggestion: String

        var envelopesOver: [EnvelopeLine] { envelopes.filter(\.isOver) }
        var net: Money { totalIncome - totalSpent }
    }

    struct Monthly: Sendable {
        let monthStart: Date
        let netWorth: Money
        let netWorthChange: Money
        let income: Money
        let spend: Money
        let savingsRate: Decimal?
        let debtCleared: Money
        let stageNow: LadderStage
        let stagePrevious: LadderStage?
        let score: LadderEngine.Score
        let overspendTotal: Money
        let sinkingFundsOnTrack: Int
        let sinkingFundsTotal: Int
        let overrideCount: Int
        let overrideCost: Money
    }

    // MARK: - Weekly

    static func weekly(
        weekStart: Date,
        envelopes: [EnvelopeLine],
        expenses: [ExpenseLine],
        totalIncome: Money,
        streak: Int,
        daysLogged: Int,
        needsReviewCount: Int,
        goalsMoved: [String]
    ) -> Weekly {
        let totalSpent = Money.sum(expenses.map(\.amount))
        let biggest = expenses.sorted { $0.amount > $1.amount }.prefix(3).map { $0 }
        return Weekly(
            weekStart: weekStart,
            envelopes: envelopes,
            biggestExpenses: Array(biggest),
            totalSpent: totalSpent,
            totalIncome: totalIncome,
            streak: streak,
            daysLogged: daysLogged,
            needsReviewCount: needsReviewCount,
            goalsMoved: goalsMoved,
            suggestion: suggestion(envelopes: envelopes, daysLogged: daysLogged,
                                   needsReviewCount: needsReviewCount)
        )
    }

    /// One suggestion, chosen by the largest thing that actually moved.
    static func suggestion(
        envelopes: [EnvelopeLine], daysLogged: Int, needsReviewCount: Int
    ) -> String {
        if daysLogged < 4 {
            return "Only \(daysLogged) of 7 days were logged. The numbers here are only as "
                 + "good as what goes in."
        }
        let worst = envelopes.filter(\.isOver).max { a, b in
            a.spent - a.budget < b.spent - b.budget
        }
        if let worst {
            return "\(worst.name) went over by its largest margin this week. If that is the "
                 + "normal cost of the week, the envelope is too small; if it is not, that is "
                 + "the one to watch."
        }
        if needsReviewCount > 3 {
            return "\(needsReviewCount) entries are still estimates. Correcting them takes a "
                 + "few minutes and makes everything downstream true."
        }
        return "Every envelope held this week. Nothing needs changing."
    }

    // MARK: - Monthly

    /// `(income − spend) / income`. Nil when there was no income to divide by.
    static func savingsRate(income: Money, spend: Money) -> Decimal? {
        guard income.isPositive else { return nil }
        return (income - spend).ratio(to: income)
    }

    /// The one figure that moved most this month, chosen by rule rather than by feel.
    static func headlineFigure(_ monthly: Monthly, formatter: MoneyFormatter) -> (String, String) {
        if monthly.stagePrevious != nil && monthly.stagePrevious != monthly.stageNow {
            return ("Ladder stage", monthly.stageNow.title)
        }
        if monthly.debtCleared.isPositive {
            return ("Debt cleared", formatter.string(monthly.debtCleared))
        }
        if let rate = monthly.savingsRate, rate > 0 {
            return ("Savings rate", "\(Money.roundBankers(rate * 100))%")
        }
        return ("Net worth", formatter.string(monthly.netWorth))
    }

    // MARK: - Copy

    /// Plain text for the "copy as text" button.
    static func weeklyText(_ review: Weekly, formatter: MoneyFormatter) -> String {
        var lines: [String] = []
        lines.append("Week of \(review.weekStart.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")
        lines.append("Spent: \(formatter.string(review.totalSpent))")
        if review.totalIncome.isPositive {
            lines.append("In: \(formatter.string(review.totalIncome))")
        }
        lines.append("Logged: \(review.daysLogged) of 7 days, streak \(review.streak)")
        lines.append("")
        if !review.envelopes.isEmpty {
            lines.append("Envelopes")
            for envelope in review.envelopes {
                let state = envelope.isOver
                    ? "over by \(formatter.string(envelope.variance.magnitude))"
                    : "\(formatter.string(envelope.variance)) left"
                lines.append("  \(envelope.name): \(formatter.string(envelope.spent)) of "
                             + "\(formatter.string(envelope.budget)) — \(state)")
            }
            lines.append("")
        }
        if !review.biggestExpenses.isEmpty {
            lines.append("Biggest three")
            for expense in review.biggestExpenses {
                lines.append("  \(expense.label): \(formatter.string(expense.amount))")
            }
            lines.append("")
        }
        lines.append(review.suggestion)
        return lines.joined(separator: "\n")
    }

    static func monthlyText(_ review: Monthly, formatter: MoneyFormatter) -> String {
        var lines: [String] = []
        lines.append(review.monthStart.formatted(.dateTime.month(.wide).year()))
        lines.append("")
        let headline = headlineFigure(review, formatter: formatter)
        lines.append("\(headline.0): \(headline.1)")
        lines.append("")
        lines.append("Net worth: \(formatter.string(review.netWorth)) "
                     + "(\(formatter.string(review.netWorthChange, style: .signed)))")
        lines.append("In: \(formatter.string(review.income))")
        lines.append("Out: \(formatter.string(review.spend))")
        if let rate = review.savingsRate {
            lines.append("Savings rate: \(Money.roundBankers(rate * 100))%")
        }
        if review.debtCleared.isPositive {
            lines.append("Debt cleared: \(formatter.string(review.debtCleared))")
        }
        lines.append("")
        lines.append("Ladder: \(review.stageNow.title)")
        lines.append("Stability score: \(review.score.total) / 100")
        for component in review.score.components {
            lines.append("  \(component.name): \(component.earned)/\(component.available) "
                         + "— \(component.detail)")
        }
        lines.append("")
        lines.append("Sinking funds on track: \(review.sinkingFundsOnTrack) of "
                     + "\(review.sinkingFundsTotal)")
        if !review.overspendTotal.isZero {
            lines.append("Wishlist against plan: "
                         + formatter.string(review.overspendTotal, style: .signed))
        }
        if review.overrideCount > 0 {
            lines.append("Advisor overrides: \(review.overrideCount)")
        }
        return lines.joined(separator: "\n")
    }
}
