import Testing
import Foundation
@testable import MyFinances

/// The gate that stops this app being muted. Every rule passes through `shouldDeliver`.
struct NotificationRulesTests {

    private let budget = NotificationRules.Budget(
        maxPerDay: 4, quietHoursStart: 22, quietHoursEnd: 8
    )

    private func rule(_ trigger: NotificationRules.Trigger) -> NotificationRules.Rule {
        NotificationRules.rule(for: trigger)!
    }

    @Test func everyTriggerHasExactlyOneRule() {
        // A trigger with no rule fails silently, which is the worst kind of bug here.
        for trigger in NotificationRules.Trigger.allCases {
            #expect(NotificationRules.all.filter { $0.id == trigger }.count == 1,
                    "missing or duplicated rule for \(trigger)")
        }
    }

    @Test func everyRuleHasAnInlineActionAndNeutralWording() {
        for rule in NotificationRules.all {
            #expect(!rule.title.isEmpty)
            #expect(!rule.body.isEmpty)
            // CLAUDE.md voice rules: no exclamation marks, no emoji, no cheerleading.
            #expect(!rule.title.contains("!"))
            #expect(!rule.body.contains("!"))
            #expect(!rule.body.lowercased().contains("you've got this"))
            #expect(rule.body.allSatisfy { $0.unicodeScalars.allSatisfy { !$0.properties.isEmoji } })
        }
    }

    // MARK: - Quiet hours

    @Test func quietHoursWrapMidnight() {
        #expect(NotificationRules.isWithinQuietHours(hour: 23, budget: budget))
        #expect(NotificationRules.isWithinQuietHours(hour: 2, budget: budget))
        #expect(NotificationRules.isWithinQuietHours(hour: 7, budget: budget))
        #expect(!NotificationRules.isWithinQuietHours(hour: 8, budget: budget))
        #expect(!NotificationRules.isWithinQuietHours(hour: 20, budget: budget))
        #expect(NotificationRules.isWithinQuietHours(hour: 22, budget: budget))
    }

    @Test func quietHoursWithinOneDayDoNotWrap() {
        let daytime = NotificationRules.Budget(maxPerDay: 4, quietHoursStart: 9, quietHoursEnd: 17)
        #expect(NotificationRules.isWithinQuietHours(hour: 12, budget: daytime))
        #expect(!NotificationRules.isWithinQuietHours(hour: 8, budget: daytime))
        #expect(!NotificationRules.isWithinQuietHours(hour: 17, budget: daytime))
    }

    @Test func quietHoursAreAbsoluteEvenForUrgentRules() {
        // Money about to go wrong still does not wake you at 03:00.
        #expect(!NotificationRules.shouldDeliver(
            rule: rule(.loanPaymentDue), hour: 3, deliveredToday: 0,
            daysSinceLastDelivery: nil, budget: budget, notificationsEnabled: true))
    }

    // MARK: - The daily cap

    @Test func theCapStopsOrdinaryRules() {
        #expect(!NotificationRules.shouldDeliver(
            rule: rule(.nothingLoggedToday), hour: 20, deliveredToday: 4,
            daysSinceLastDelivery: nil, budget: budget, notificationsEnabled: true))
        #expect(NotificationRules.shouldDeliver(
            rule: rule(.nothingLoggedToday), hour: 20, deliveredToday: 3,
            daysSinceLastDelivery: nil, budget: budget, notificationsEnabled: true))
    }

    @Test func onlyMoneyAboutToGoWrongBypassesTheCap() {
        let bypassing = NotificationRules.all.filter(\.bypassesDailyCap).map(\.id)
        #expect(Set(bypassing) == Set([.loanPaymentDue, .recurringBillDue,
                                       .accountBelowFloor, .projectedNegativeDay]))
        #expect(NotificationRules.shouldDeliver(
            rule: rule(.loanPaymentDue), hour: 9, deliveredToday: 9,
            daysSinceLastDelivery: nil, budget: budget, notificationsEnabled: true))
    }

    // MARK: - Cooldowns

    @Test func cooldownsStopRepeats() {
        // The weekly review has a six-day cooldown, so it cannot fire twice in a week.
        #expect(!NotificationRules.shouldDeliver(
            rule: rule(.weeklyReview), hour: 18, deliveredToday: 0,
            daysSinceLastDelivery: 3, budget: budget, notificationsEnabled: true))
        #expect(NotificationRules.shouldDeliver(
            rule: rule(.weeklyReview), hour: 18, deliveredToday: 0,
            daysSinceLastDelivery: 6, budget: budget, notificationsEnabled: true))
    }

    @Test func everyRepeatableRuleHasACooldown() {
        // Without one, a condition that stays true notifies forever.
        for rule in NotificationRules.all where rule.time != nil {
            #expect(rule.cooldownDays >= 1, "\(rule.id) can fire twice for one condition")
        }
    }

    @Test func nothingFiresWhenNotificationsAreOff() {
        for rule in NotificationRules.all {
            #expect(!NotificationRules.shouldDeliver(
                rule: rule, hour: 12, deliveredToday: 0, daysSinceLastDelivery: nil,
                budget: budget, notificationsEnabled: false))
        }
    }

    @Test func aFirstDeliveryIsNeverBlockedByACooldown() {
        #expect(NotificationRules.shouldDeliver(
            rule: rule(.nothingReconciled), hour: 10, deliveredToday: 0,
            daysSinceLastDelivery: nil, budget: budget, notificationsEnabled: true))
    }
}
