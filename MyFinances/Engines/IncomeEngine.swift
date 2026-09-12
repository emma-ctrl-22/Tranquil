import Foundation

/// Windfall interception, allocation splits, the salary-rise ratchet and creep detection.
///
/// ADVISOR_RULES §4 calls interception the highest-value behaviour in the app: money
/// above the threshold does not merge into spendable balance until it has been allocated.
nonisolated enum IncomeEngine {

    // MARK: - Interception

    /// Any inflow above `multiple x medianWeeklyIncome` is intercepted.
    static func isWindfall(
        _ amount: Money, medianWeeklyIncome: Money, multiple: Decimal
    ) -> Bool {
        guard medianWeeklyIncome.isPositive else {
            // With no income history there is no baseline to be unusual against.
            // Intercepting everything would make the app unusable on day one.
            return false
        }
        return amount > medianWeeklyIncome.scaled(by: multiple)
    }

    /// R3 — the tax reserve comes off the top of untaxed income. It was never your money.
    static func taxReserve(on gross: Money, rate: Decimal, kind: IncomeEventKind) -> Money {
        guard kind.needsTaxReserve, gross.isPositive else { return .zero }
        return gross.scaled(by: rate)
    }

    static func netUsable(gross: Money, taxReserved: Money, directCosts: Money) -> Money {
        (gross - taxReserved - directCosts).clampedToZero
    }

    // MARK: - Allocation splits

    struct Slice: Identifiable, Sendable {
        let id: String
        let label: String
        let kind: AllocationDestinationKind
        /// Percentage share, 0–100.
        let share: Decimal
        let rationale: String
    }

    /// §4a defaults for a project payment or bonus.
    static let projectPaymentSplit: [Slice] = [
        .init(id: "ladder", label: "Ladder gap", kind: .ladderGap, share: 40,
              rationale: "Whichever step of the Order of Operations you are on."),
        .init(id: "goals", label: "Goals", kind: .goal, share: 25,
              rationale: "Top-ranked goals, respecting their caps."),
        .init(id: "investment", label: "Investment", kind: .investment, share: 20,
              rationale: "Committed and boring. Time is the asset you have most of."),
        .init(id: "free", label: "Free", kind: .free, share: 15,
              rationale: "Yours. No questions, not tracked against any budget."),
    ]

    /// §4b defaults for the *increase* only — never the whole salary.
    static let salaryRiseSplit: [Slice] = [
        .init(id: "investment", label: "Investment rate increase", kind: .investment, share: 40,
              rationale: "The raise is the cheapest moment to raise your savings rate."),
        .init(id: "ladder", label: "Ladder gap or debt", kind: .ladderGap, share: 30,
              rationale: "Whatever step you are on, or the most expensive debt."),
        .init(id: "lifestyle", label: "Lifestyle", kind: .free, share: 20,
              rationale: "Explicit and logged. A raise you never feel is a raise you resent."),
        .init(id: "goals", label: "Goals", kind: .goal, share: 10,
              rationale: "Brings the things you want closer."),
    ]

    static func defaultSplit(for kind: IncomeEventKind) -> [Slice] {
        kind == .salaryRise ? salaryRiseSplit : projectPaymentSplit
    }

    /// Divide an amount by the split, losing nothing.
    static func allocate(_ amount: Money, across slices: [Slice]) -> [(slice: Slice, amount: Money)] {
        guard !slices.isEmpty else { return [] }
        let amounts = amount.allocate(by: slices.map(\.share))
        return zip(slices, amounts).map { (slice: $0, amount: $1) }
    }

    /// Shares must total 100 before an allocation sheet can be completed.
    static func sharesAreComplete(_ slices: [Slice]) -> Bool {
        slices.reduce(Decimal(0)) { $0 + $1.share } == 100
    }

    // MARK: - Effective hourly rate

    /// `net usable / hours`. At 24 this is the highest-leverage number in the app:
    /// it says which work to take more of and which to stop taking.
    static func effectiveHourlyRate(netUsable: Money, hoursWorked: Int?) -> Money? {
        guard let hours = hoursWorked, hours > 0, netUsable.isPositive else { return nil }
        return netUsable.split(into: hours).first
    }

    struct ClientRate: Identifiable, Sendable {
        let id: String
        let client: String
        let totalNet: Money
        let totalHours: Int
        var hourlyRate: Money? {
            totalHours > 0 ? totalNet.split(into: totalHours).first : nil
        }
    }

    /// Rolled up per client over the trailing twelve months.
    static func clientRates(
        _ events: [(client: String?, netUsable: Money, hours: Int?)]
    ) -> [ClientRate] {
        var totals: [String: (net: Money, hours: Int)] = [:]
        for event in events {
            guard let client = event.client, let hours = event.hours, hours > 0 else { continue }
            var entry = totals[client] ?? (net: .zero, hours: 0)
            entry.net += event.netUsable
            entry.hours += hours
            totals[client] = entry
        }
        return totals
            .map { ClientRate(id: $0.key, client: $0.key,
                              totalNet: $0.value.net, totalHours: $0.value.hours) }
            .sorted { ($0.hourlyRate ?? .zero) > ($1.hourlyRate ?? .zero) }
    }

    // MARK: - Income concentration

    struct Concentration: Sendable {
        let topSource: String?
        let share: Decimal
        let isConcentrated: Bool
        /// 6 months when concentrated, otherwise the configured target.
        let recommendedEmergencyMonths: Int
    }

    /// If one source produced more than 60% of trailing 12-month income, the emergency
    /// fund target rises from 3 months to 6. Concentration is a risk you can see coming.
    static func concentration(
        _ bySource: [String: Money], baseEmergencyMonths: Int
    ) -> Concentration {
        let total = Money.sum(Array(bySource.values))
        guard total.isPositive, let top = bySource.max(by: { $0.value < $1.value }) else {
            return Concentration(topSource: nil, share: 0, isConcentrated: false,
                                 recommendedEmergencyMonths: baseEmergencyMonths)
        }
        let share = top.value.ratio(to: total) ?? 0
        let concentrated = share > Decimal(string: "0.6")!
        return Concentration(
            topSource: top.key, share: share, isConcentrated: concentrated,
            recommendedEmergencyMonths: concentrated ? 6 : baseEmergencyMonths
        )
    }

    // MARK: - Salary rise

    struct SalaryRise: Sendable {
        let previous: Money
        let current: Money
        var delta: Money { current - previous }
        var percentage: Decimal? { delta.ratio(to: previous) }
    }

    /// A rise is only a rise if it went up. The delta is what gets allocated —
    /// never the whole salary.
    static func salaryRise(previous: Money?, current: Money) -> SalaryRise? {
        guard let previous, previous.isPositive, current > previous else { return nil }
        return SalaryRise(previous: previous, current: current)
    }

    // MARK: - Lifestyle creep

    struct CreepPoint: Identifiable, Sendable {
        let monthStart: Date
        let essentialSpend: Money
        let netIncome: Money

        var id: Date { monthStart }
        /// Essential spend as a share of income. Nil in a month with no income.
        var ratio: Decimal? { essentialSpend.ratio(to: netIncome) }
    }

    struct CreepVerdict: Sendable {
        let points: [CreepPoint]
        /// True when essentials grew as a share of income for two consecutive quarters.
        let isCreeping: Bool
        let firstQuarterAverage: Decimal?
        let latestQuarterAverage: Decimal?
        /// Categories that moved most, named by the caller.
        let drivers: [String]
    }

    /// The chart that would have saved most of the people the advisor has watched fail.
    ///
    /// Compares three consecutive quarters; creeping means each was higher than the last.
    static func creep(points: [CreepPoint], drivers: [String] = []) -> CreepVerdict {
        let ordered = points.sorted { $0.monthStart < $1.monthStart }
        let quarters = stride(from: 0, to: ordered.count, by: 3).map { start in
            Array(ordered[start..<Swift.min(start + 3, ordered.count)])
        }.filter { !$0.isEmpty }

        func average(_ quarter: [CreepPoint]) -> Decimal? {
            let ratios = quarter.compactMap(\.ratio)
            guard !ratios.isEmpty else { return nil }
            return ratios.reduce(Decimal(0), +) / Decimal(ratios.count)
        }

        let averages = quarters.compactMap(average)
        var creeping = false
        if averages.count >= 3 {
            let recent = Array(averages.suffix(3))
            creeping = recent[1] > recent[0] && recent[2] > recent[1]
        }

        return CreepVerdict(
            points: ordered,
            isCreeping: creeping,
            firstQuarterAverage: averages.first,
            latestQuarterAverage: averages.last,
            drivers: creeping ? drivers : []
        )
    }

    // MARK: - Refunds

    /// §4c: a refund is a return of capital. It reverses the original expense and never
    /// counts toward income, savings rate, or a good month. Getting this wrong makes
    /// every other number lie.
    static func countsTowardIncome(_ kind: IncomeEventKind) -> Bool {
        kind.countsAsIncome
    }
}
