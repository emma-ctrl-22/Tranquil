import Foundation
import SwiftData

/// Keeps one `DailyLog` row per financial day. It powers the heatmap, the streak, and
/// the "nothing logged today" nudge, so it has to be updated wherever an entry is saved.
enum DailyLogService {

    /// Record that an entry was logged on the financial day `date` falls in.
    static func recordEntry(on date: Date, in context: ModelContext, calendar: FinancialCalendar) {
        let day = calendar.financialDay(for: date)
        let log = fetchOrCreate(day: day, in: context, calendar: calendar)
        log.entryCount += 1
        log.updatedAt = calendar.currentDate()
    }

    static func markReconciled(on date: Date, in context: ModelContext, calendar: FinancialCalendar) {
        let day = calendar.financialDay(for: date)
        let log = fetchOrCreate(day: day, in: context, calendar: calendar)
        log.wasReconciled = true
        log.updatedAt = calendar.currentDate()
    }

    /// Consecutive financial days logged, counting back from today.
    /// Today not yet being logged does not break the streak — the day is not over.
    static func currentStreak(logs: [DailyLog], today: Date, calendar: FinancialCalendar) -> Int {
        let logged = Set(logs.filter { $0.entryCount > 0 && $0.deletedAt == nil }.map(\.date))
        guard !logged.isEmpty else { return 0 }
        var streak = 0
        var cursor = logged.contains(today) ? today : calendar.addDays(-1, to: today)
        while logged.contains(cursor) {
            streak += 1
            cursor = calendar.addDays(-1, to: cursor)
        }
        return streak
    }

    private static func fetchOrCreate(
        day: Date, in context: ModelContext, calendar: FinancialCalendar
    ) -> DailyLog {
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = DailyLog(date: day, now: calendar.currentDate())
        context.insert(created)
        return created
    }
}
