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

@MainActor
struct NotificationSchedulerTests {
    private let calendar = FinancialCalendar(timeZone: TimeZone(identifier: "UTC")!,
                                             now: { Date(timeIntervalSince1970: 1_789_000_000) })

    @Test func unloggedDaysAreCountedBackFromToday() {
        let today = calendar.today()
        let logs = [
            DailyLog(date: calendar.addDays(-3, to: today), entryCount: 2),
            DailyLog(date: calendar.addDays(-8, to: today), entryCount: 1),
        ]
        // Today, −1 and −2 are unlogged; −3 is logged.
        #expect(NotificationScheduler.consecutiveUnloggedDays(
            logs: logs, today: today, calendar: calendar) == 3)
    }

    @Test func loggingTodayMeansNoUnloggedRun() {
        let today = calendar.today()
        #expect(NotificationScheduler.consecutiveUnloggedDays(
            logs: [DailyLog(date: today, entryCount: 1)],
            today: today, calendar: calendar) == 0)
    }

    @Test func anEmptyHistoryDoesNotLoopForever() {
        // The guard rail matters: an empty database must not spin.
        let count = NotificationScheduler.consecutiveUnloggedDays(
            logs: [], today: calendar.today(), calendar: calendar)
        #expect(count == 60)
    }
}
