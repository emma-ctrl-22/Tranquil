import Foundation

/// Every notification the app can send, as declarative data.
///
/// Adding a notification means adding a rule here — never a scheduling call scattered
/// through feature code. A muted app is a dead app, so the cap and the quiet hours are
/// enforced centrally, below, and when in doubt a rule does not fire.
nonisolated enum NotificationRules {

    enum Trigger: String, Codable, Sendable, CaseIterable {
        case nothingLoggedToday
        case nothingLoggedStreakAtRisk
        case envelopeBurnAhead
        case miscEnvelopePastSixtyPercent
        case loanPaymentDue
        case recurringBillDue
        case expectedIncomeMissing
        case unusuallyLargeExpense
        case accountBelowFloor
        case projectedNegativeDay
        case goalMilestone
        case weeklyReview
        case monthlyReview
        case nothingReconciled
        case ladderStageChanged
    }

    /// What tapping the notification does. Every rule has one.
    enum InlineAction: String, Codable, Sendable {
        case logNow, markPaid, snooze, openReview, openAccount, openLoan, openGoal, openLadder
    }

    struct Rule: Identifiable, Sendable {
        let id: Trigger
        let title: String
        /// Neutral wording. No shame language, no exclamation marks, no encouragement filler.
        let body: String
        /// Hour and minute in the user's timezone, when the rule is time-based.
        let time: (hour: Int, minute: Int)?
        /// A rule cannot fire twice for the same condition inside this window.
        let cooldownDays: Int
        let action: InlineAction
        /// Rules that must be delivered even when the daily cap is reached.
        /// Kept deliberately short: only money that is about to go wrong.
        let bypassesDailyCap: Bool

        var id_: Trigger { id }
    }

    static let all: [Rule] = [
        Rule(id: .nothingLoggedToday,
             title: "Nothing logged today",
             body: "Thirty seconds now beats reconstructing the week on Sunday.",
             time: (20, 30), cooldownDays: 1, action: .logNow, bypassesDailyCap: false),

        Rule(id: .nothingLoggedStreakAtRisk,
             title: "Five days unlogged",
             body: "The ledger is drifting from reality. Log what you remember; estimates are fine.",
             time: (22, 0), cooldownDays: 1, action: .logNow, bypassesDailyCap: false),

        Rule(id: .envelopeBurnAhead,
             title: "Envelope ahead of pace",
             body: "Spending here is running ahead of the week. Nothing is wrong yet.",
             time: nil, cooldownDays: 7, action: .openReview, bypassesDailyCap: false),

        Rule(id: .miscEnvelopePastSixtyPercent,
             title: "Miscellaneous past 60% before Wednesday",
             body: "This is usually where the week gets away. Worth a look.",
             time: nil, cooldownDays: 7, action: .openReview, bypassesDailyCap: false),

        Rule(id: .loanPaymentDue,
             title: "Loan payment due",
             body: "A scheduled payment is coming up.",
             time: (9, 0), cooldownDays: 1, action: .markPaid, bypassesDailyCap: true),

        Rule(id: .recurringBillDue,
             title: "Bill due in two days",
             body: "A recurring bill is due shortly.",
             time: (9, 0), cooldownDays: 1, action: .markPaid, bypassesDailyCap: true),

        Rule(id: .expectedIncomeMissing,
             title: "Expected income has not arrived",
             body: "It was due two days ago. Worth chasing, or adjusting the expectation.",
             time: (10, 0), cooldownDays: 3, action: .openReview, bypassesDailyCap: false),

        Rule(id: .unusuallyLargeExpense,
             title: "Larger than usual",
             body: "This is well above the usual amount for this category. Confirm it?",
             time: nil, cooldownDays: 0, action: .openReview, bypassesDailyCap: false),

        Rule(id: .accountBelowFloor,
             title: "Account below its floor",
             body: "The balance has dropped below the floor you set.",
             time: nil, cooldownDays: 1, action: .openAccount, bypassesDailyCap: true),

        Rule(id: .projectedNegativeDay,
             title: "A day ahead projects negative",
             body: "Based on what is scheduled, a day inside the next fortnight goes below zero.",
             time: nil, cooldownDays: 7, action: .openReview, bypassesDailyCap: true),

        Rule(id: .goalMilestone,
             title: "Goal milestone reached",
             body: "A goal has crossed a quarter mark.",
             time: nil, cooldownDays: 0, action: .openGoal, bypassesDailyCap: false),

        Rule(id: .weeklyReview,
             title: "Weekly review",
             body: "Last week in one screen.",
             time: (18, 0), cooldownDays: 6, action: .openReview, bypassesDailyCap: false),

        Rule(id: .monthlyReview,
             title: "Monthly review",
             body: "The month in one screen, with the letter.",
             time: (19, 0), cooldownDays: 27, action: .openReview, bypassesDailyCap: false),

        Rule(id: .nothingReconciled,
             title: "Nothing reconciled in two weeks",
             body: "Count one account and check it against the ledger. Small gaps compound.",
             time: (10, 0), cooldownDays: 14, action: .openAccount, bypassesDailyCap: false),

        Rule(id: .ladderStageChanged,
             title: "Ladder stage changed",
             body: "Your stage has moved.",
             time: nil, cooldownDays: 0, action: .openLadder, bypassesDailyCap: false),
    ]

    static func rule(for trigger: Trigger) -> Rule? {
        all.first { $0.id == trigger }
    }

    // MARK: - Central gating

    struct Budget: Sendable {
        let maxPerDay: Int
        let quietHoursStart: Int
        let quietHoursEnd: Int
    }

    /// Quiet hours are absolute. They can wrap midnight (22:00 → 08:00).
    static func isWithinQuietHours(hour: Int, budget: Budget) -> Bool {
        let start = budget.quietHoursStart
        let end = budget.quietHoursEnd
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }

    /// The single decision point: may this rule fire right now?
    static func shouldDeliver(
        rule: Rule,
        hour: Int,
        deliveredToday: Int,
        daysSinceLastDelivery: Int?,
        budget: Budget,
        notificationsEnabled: Bool
    ) -> Bool {
        guard notificationsEnabled else { return false }
        // Quiet hours are respected absolutely, by every rule without exception.
        if isWithinQuietHours(hour: hour, budget: budget) { return false }
        if let days = daysSinceLastDelivery, days < rule.cooldownDays { return false }
        if deliveredToday >= budget.maxPerDay && !rule.bypassesDailyCap { return false }
        return true
    }
}
