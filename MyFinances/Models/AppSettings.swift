import Foundation
import SwiftData

/// One row. Everything configurable lives here, including every threshold the
/// advisor uses — thresholds are settings, not constants (ADVISOR_RULES §3).
@Model
final class AppSettings {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    // MARK: Money and time
    var currencyCode: String = "GHS"
    var currencySymbol: String = "₵"
    var currencyMinorUnitExponent: Int = 2
    /// 1 = Sunday … 7 = Saturday.
    var weekStartsOn: Int = 2
    /// A 01:00 taxi ride belongs to the previous day.
    var financialDayStartsAtHour: Int = 4

    // MARK: Owner profile (ADVISOR_RULES §1)
    /// Age is derived from this, never stored as a number that goes stale.
    var birthYear: Int = 2002
    var incomeTypeRaw: String = "mixed"
    var dependents: Int = 0
    var primaryIncomeSource: String = ""

    // MARK: Income baseline

    /// Net (after-tax) pay from the regular salary, per month. Editable — a raise is
    /// a normal event, and §4b handles it as a ratchet rather than a new baseline.
    var expectedMonthlyNetIncomeMinorUnits: Int = 350_000   // ₵3,500.00
    /// Day of the month the salary lands. Clamped at month end, never skipped.
    var salaryDayOfMonth: Int = 28

    // MARK: Thresholds
    /// R3 — the share of untaxed income held back. Confirm the rate with a local
    /// professional once a year; over-reserving is an inconvenience, under-reserving a crisis.
    var taxReserveRateBasisPoints: Int = 2_500          // 25.00%
    /// The line above which debt is cleared before investing (R5, Ladder stage 3).
    var highInterestThresholdAPRBasisPoints: Int = 2_500 // 25.00%
    /// R4 — above this a planned loan is Not affordable, not "tight".
    var maxDebtServiceRatioBasisPoints: Int = 3_000      // 30.00%
    /// R9 — speculative holdings cap, and only from Ladder stage 4.
    var speculationCapOfNetWorthBasisPoints: Int = 500   // 5.00%
    /// Months of essentials the emergency fund targets. Raised to 6 on income concentration.
    var emergencyFundMonths: Int = 6
    /// §4: an inflow above this multiple of median weekly income is intercepted.
    var windfallMultipleBasisPoints: Int = 15_000        // 1.50x
    /// Goals above this get a 7-day cool-off before they can be marked purchased.
    var coolOffThresholdMinorUnits: Int = 100_000
    /// Expenses above this get a cost-in-time preview.
    var costInTimeThresholdMinorUnits: Int = 20_000

    /// Alert when an envelope's burn exceeds its expected pace by more than this.
    var burnAlertMarginBasisPoints: Int = 2_500          // 25.00%
    /// How much of a `.maybe` scheduled event to carry into projections.
    var maybeEventWeightBasisPoints: Int = 5_000         // 50.00%
    /// Ladder stage 6: debt service must be at or under this.
    var stage6MaxDebtServiceBasisPoints: Int = 2_000     // 20.00%
    /// Ladder stage 6: no remaining loan above this APR.
    var stage6MaxAPRBasisPoints: Int = 1_500             // 15.00%
    /// Runway scoring reaches full marks at this many months.
    var runwayFullMarksMonths: Int = 6
    /// Debt-service scoring reaches zero at this ratio.
    var debtServiceZeroScoreBasisPoints: Int = 4_000     // 40.00%
    /// One income source above this share raises the emergency fund target.
    var concentrationThresholdBasisPoints: Int = 6_000   // 60.00%
    /// Days a gift waits before it can be allocated.
    var giftCoolOffDays: Int = 7
    /// Days a goal above the cool-off threshold waits before being marked bought.
    var goalCoolOffDays: Int = 7

    // MARK: Notifications
    var notificationsEnabled: Bool = true
    var quietHoursStartHour: Int = 22
    var quietHoursEndHour: Int = 8
    /// A muted app is a dead app.
    var maxNotificationsPerDay: Int = 4

    // MARK: Security and data
    var requireUnlockOnLaunch: Bool = false
    var requireUnlockOnWake: Bool = false
    var backupFolderBookmark: Data?
    var automaticWeeklyBackup: Bool = true
    var backupsToKeep: Int = 12

    // MARK: First run
    var hasCompletedSetup: Bool = false

    init(now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
    }

    var currency: Currency {
        Currency(code: currencyCode, symbol: currencySymbol, minorUnitExponent: currencyMinorUnitExponent)
    }

    func applyCurrency(_ currency: Currency) {
        currencyCode = currency.code
        currencySymbol = currency.symbol
        currencyMinorUnitExponent = currency.minorUnitExponent
    }

    var calendar: FinancialCalendar {
        FinancialCalendar(dayBoundaryHour: financialDayStartsAtHour, weekStartsOn: weekStartsOn)
    }

    var formatter: MoneyFormatter { MoneyFormatter(currency: currency) }

    var taxReserveRate: Decimal { Decimal(taxReserveRateBasisPoints) / 10_000 }
    var highInterestThresholdAPR: Decimal { Decimal(highInterestThresholdAPRBasisPoints) / 10_000 }
    var maxDebtServiceRatio: Decimal { Decimal(maxDebtServiceRatioBasisPoints) / 10_000 }
    var speculationCapOfNetWorth: Decimal { Decimal(speculationCapOfNetWorthBasisPoints) / 10_000 }
    var windfallMultiple: Decimal { Decimal(windfallMultipleBasisPoints) / 10_000 }

    var coolOffThreshold: Money { Money(minorUnits: coolOffThresholdMinorUnits) }
    var burnAlertMargin: Decimal { Decimal(burnAlertMarginBasisPoints) / 10_000 }
    var maybeEventWeight: Decimal { Decimal(maybeEventWeightBasisPoints) / 10_000 }
    var stage6MaxDebtService: Decimal { Decimal(stage6MaxDebtServiceBasisPoints) / 10_000 }
    var stage6MaxAPR: Decimal { Decimal(stage6MaxAPRBasisPoints) / 10_000 }
    var debtServiceZeroScore: Decimal { Decimal(debtServiceZeroScoreBasisPoints) / 10_000 }
    var concentrationThreshold: Decimal { Decimal(concentrationThresholdBasisPoints) / 10_000 }
    var costInTimeThreshold: Money { Money(minorUnits: costInTimeThresholdMinorUnits) }

    var age: Int { calendar.age(birthYear: birthYear) }

    var expectedMonthlyNetIncome: Money {
        get { Money(minorUnits: expectedMonthlyNetIncomeMinorUnits) }
        set { expectedMonthlyNetIncomeMinorUnits = newValue.minorUnits }
    }

    /// What a week of income is worth, for free-to-spend and every weekly projection.
    ///
    /// ASSUMPTION: a monthly salary is *regular but lumpy* — three weeks of the month
    /// show zero income, so F4's trailing 8-week median would read ₵0 and free-to-spend
    /// would collapse in every week the salary does not land. So for the salaried
    /// component we spread the known monthly figure evenly: `monthly x 12 / 52`.
    /// The 8-week median still governs genuinely irregular income (freelance, side work),
    /// and `IncomeEngine` will combine the two in M4. Flagged in the summary.
    var expectedWeeklyIncomeFromSalary: Money {
        expectedMonthlyNetIncome.scaled(by: Decimal(12) / Decimal(52))
    }

    enum IncomeType: String, Codable, CaseIterable, Sendable {
        case salaried, freelance, mixed
    }

    var incomeType: IncomeType {
        get { IncomeType(rawValue: incomeTypeRaw) ?? .mixed }
        set { incomeTypeRaw = newValue.rawValue }
    }

    /// What the Order of Operations would suggest: 6 months for freelance or mixed
    /// income, 3 for salaried. Advice, not the setting — `emergencyFundMonths` is what
    /// the Ladder and the Advisor actually use, so changing it in Settings changes
    /// the app rather than being quietly ignored.
    var recommendedEmergencyFundMonths: Int {
        incomeType == .salaried ? 3 : 6
    }

    var emergencyFundMonthsMatchesRecommendation: Bool {
        emergencyFundMonths == recommendedEmergencyFundMonths
    }
}
