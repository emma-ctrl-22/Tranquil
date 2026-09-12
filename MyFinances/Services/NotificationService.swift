import Foundation
import UserNotifications

/// Delivers the rules in `NotificationRules`. Local only — `UNUserNotificationCenter`
/// makes no network call, and nothing about a notification leaves the machine.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Delivery

    /// Schedules a rule, after the central gate has approved it.
    func schedule(
        _ trigger: NotificationRules.Trigger,
        at date: DateComponents,
        bodyOverride: String? = nil,
        budget: NotificationRules.Budget,
        notificationsEnabled: Bool,
        calendar: FinancialCalendar
    ) {
        guard let rule = NotificationRules.rule(for: trigger) else { return }
        let hour = date.hour ?? 12
        guard NotificationRules.shouldDeliver(
            rule: rule,
            hour: hour,
            deliveredToday: deliveredCount(on: calendar.today()),
            daysSinceLastDelivery: daysSinceLastDelivery(of: trigger, today: calendar.today(),
                                                         calendar: calendar),
            budget: budget,
            notificationsEnabled: notificationsEnabled
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = rule.title
        content.body = bodyOverride ?? rule.body
        content.sound = nil
        content.userInfo = ["trigger": trigger.rawValue, "action": rule.action.rawValue]
        content.categoryIdentifier = rule.action.rawValue

        let request = UNNotificationRequest(
            identifier: trigger.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        )
        center.add(request)
        recordDelivery(of: trigger, on: calendar.today())
    }

    /// The one daily nudge M2 ships: "nothing logged today", at 20:30.
    func scheduleDailyNudgeIfNeeded(
        hasLoggedToday: Bool,
        settings: AppSettings,
        calendar: FinancialCalendar
    ) {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationRules.Trigger.nothingLoggedToday.rawValue]
        )
        guard !hasLoggedToday else { return }
        guard let rule = NotificationRules.rule(for: .nothingLoggedToday),
              let time = rule.time else { return }

        var components = calendar.calendar.dateComponents(
            [.year, .month, .day], from: calendar.currentDate()
        )
        components.hour = time.hour
        components.minute = time.minute

        schedule(.nothingLoggedToday, at: components,
                 budget: budget(from: settings),
                 notificationsEnabled: settings.notificationsEnabled,
                 calendar: calendar)
    }

    func budget(from settings: AppSettings) -> NotificationRules.Budget {
        NotificationRules.Budget(
            maxPerDay: settings.maxNotificationsPerDay,
            quietHoursStart: settings.quietHoursStartHour,
            quietHoursEnd: settings.quietHoursEndHour
        )
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Bookkeeping
    //
    // Delivery counts live in UserDefaults rather than the store: they are throwaway
    // scheduling state, not part of the user's financial record.

    private func deliveredCount(on day: Date) -> Int {
        defaults.integer(forKey: "notif.count." + key(day))
    }

    private func recordDelivery(of trigger: NotificationRules.Trigger, on day: Date) {
        defaults.set(deliveredCount(on: day) + 1, forKey: "notif.count." + key(day))
        defaults.set(day, forKey: "notif.last." + trigger.rawValue)
    }

    private func daysSinceLastDelivery(
        of trigger: NotificationRules.Trigger, today: Date, calendar: FinancialCalendar
    ) -> Int? {
        guard let last = defaults.object(forKey: "notif.last." + trigger.rawValue) as? Date
        else { return nil }
        return calendar.daysBetween(last, today)
    }

    private func key(_ day: Date) -> String {
        String(Int(day.timeIntervalSince1970 / 86_400))
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Show the banner even when the app is frontmost — otherwise a menu bar app's
    /// reminders are invisible exactly when they matter.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["action"] as? String,
              let action = NotificationRules.InlineAction(rawValue: raw) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .notificationAction, object: action)
        }
    }
}

extension Notification.Name {
    static let notificationAction = Notification.Name("tranquil.notificationAction")
}
