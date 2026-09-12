import Foundation

/// Loan schedules, payoff ordering, simulation and the planned-loan verdict.
///
/// Every schedule is built so the payments sum **exactly** to the total owed: the final
/// instalment absorbs the rounding rather than leaving a stray pesewa behind.
nonisolated enum LoanEngine {

    // MARK: - Inputs

    struct LoanInput: Identifiable, Sendable {
        let id: UUID
        let name: String
        let lender: String
        let direction: LoanDirection
        let principal: Money
        let interestModel: Loan.InterestModel
        let startDate: Date
        let termMonths: Int
        let paymentFrequency: PaymentFrequency
        /// 0–5. Five is money borrowed from family.
        let socialWeight: Int
        let status: LoanStatus
        /// Payments already made, for the remaining balance.
        let paidPrincipal: Money
        let paidInterest: Money
        let paymentsMade: Int
        let lateCount: Int

        init(
            id: UUID, name: String, lender: String, direction: LoanDirection,
            principal: Money, interestModel: Loan.InterestModel, startDate: Date,
            termMonths: Int, paymentFrequency: PaymentFrequency = .monthly,
            socialWeight: Int = 0, status: LoanStatus = .active,
            paidPrincipal: Money = .zero, paidInterest: Money = .zero,
            paymentsMade: Int = 0, lateCount: Int = 0
        ) {
            self.id = id
            self.name = name
            self.lender = lender
            self.direction = direction
            self.principal = principal
            self.interestModel = interestModel
            self.startDate = startDate
            self.termMonths = termMonths
            self.paymentFrequency = paymentFrequency
            self.socialWeight = socialWeight
            self.status = status
            self.paidPrincipal = paidPrincipal
            self.paidInterest = paidInterest
            self.paymentsMade = paymentsMade
            self.lateCount = lateCount
        }

        var periodCount: Int {
            Swift.max(1, termMonths * paymentFrequency.periodsPerYear / 12)
        }

        /// The rate applied to one period's balance.
        var periodicRate: Decimal {
            interestModel.annualRate / Decimal(paymentFrequency.periodsPerYear)
        }

        var annualRate: Decimal { interestModel.annualRate }

        var remainingPrincipal: Money { (principal - paidPrincipal).clampedToZero }
    }

    // MARK: - Outputs

    struct Instalment: Identifiable, Sendable {
        let number: Int
        let date: Date
        let payment: Money
        let principal: Money
        let interest: Money
        /// Balance after this instalment.
        let balance: Money

        var id: Int { number }
    }

    struct Schedule: Sendable {
        let instalments: [Instalment]
        let regularPayment: Money

        var totalPaid: Money { Money.sum(instalments.map(\.payment)) }
        var totalInterest: Money { Money.sum(instalments.map(\.interest)) }
        var totalPrincipal: Money { Money.sum(instalments.map(\.principal)) }
        var payoffDate: Date? { instalments.last?.date }
        var periodCount: Int { instalments.count }
    }

    // MARK: - Payment formulas

    /// Amortising: `payment = P·r / (1 − (1+r)^−n)`.
    /// With a zero rate this degrades to `P / n` rather than dividing by zero.
    static func amortisingPayment(principal: Money, periodicRate: Decimal, periods: Int) -> Money {
        guard periods > 0 else { return principal }
        guard periodicRate > 0 else {
            return principal.split(into: periods).first ?? .zero
        }
        let growth = power(Decimal(1) + periodicRate, periods)
        guard growth > 1 else { return principal.split(into: periods).first ?? .zero }
        // P·r·(1+r)^n / ((1+r)^n − 1) — the same formula without a negative exponent.
        let numerator = principal.decimalMinorUnits * periodicRate * growth
        let denominator = growth - 1
        return Money(minorUnits: Money.roundBankers(numerator / denominator))
    }

    /// Flat rate: `total = P·(1 + rate·years)`, `payment = total / n`.
    static func flatRateTotal(principal: Money, rate: Decimal, years: Int) -> Money {
        principal.scaled(by: Decimal(1) + rate * Decimal(Swift.max(0, years)))
    }

    /// `(1 + r)^n` for a whole exponent, in `Decimal` — never `pow` on a `Double`.
    static func power(_ base: Decimal, _ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        var input = base
        var remaining = exponent
        while remaining > 0 {
            if remaining % 2 == 1 { result *= input }
            input *= input
            remaining /= 2
        }
        return result
    }

    // MARK: - Schedules

    /// The full instalment schedule from the original principal.
    ///
    /// The final instalment is adjusted so principal sums exactly to the amount borrowed.
    static func schedule(
        for loan: LoanInput,
        calendar: FinancialCalendar,
        extraPerPeriod: Money = .zero
    ) -> Schedule {
        switch loan.interestModel {
        case .interestFree:
            return evenSchedule(loan: loan, total: loan.principal,
                                calendar: calendar, extraPerPeriod: extraPerPeriod)
        case let .flatRate(rate, years):
            let total = flatRateTotal(principal: loan.principal, rate: rate, years: years)
            return evenSchedule(loan: loan, total: total, interestTotal: total - loan.principal,
                                calendar: calendar, extraPerPeriod: extraPerPeriod)
        case .amortizing, .revolving:
            return reducingBalanceSchedule(loan: loan, calendar: calendar,
                                           extraPerPeriod: extraPerPeriod)
        }
    }

    /// Interest-free and flat-rate: the total divides evenly, losing nothing.
    ///
    /// On a flat-rate loan the interest is fixed at signing. Paying early shortens the
    /// term but you still owe every pesewa of interest — which is exactly why flat-rate
    /// borrowing is expensive, and the app must not pretend otherwise. So the final
    /// instalment absorbs whatever interest has not yet been charged.
    private static func evenSchedule(
        loan: LoanInput,
        total: Money,
        interestTotal: Money = .zero,
        calendar: FinancialCalendar,
        extraPerPeriod: Money
    ) -> Schedule {
        let periods = loan.periodCount
        let payments = total.split(into: periods)
        let scheduledInterest = interestTotal.split(into: periods)

        var instalments: [Instalment] = []
        var balance = total
        var interestRemaining = interestTotal

        for period in 0..<periods {
            guard balance.isPositive else { break }

            var payment = payments[period] + extraPerPeriod
            let settlesNow = payment >= balance
            if settlesNow { payment = balance }

            // The settling instalment carries all the interest still owed.
            let interest = settlesNow
                ? interestRemaining
                : Money.min(scheduledInterest[period], interestRemaining)
            let principal = payment - interest

            interestRemaining = (interestRemaining - interest).clampedToZero
            balance = (balance - payment).clampedToZero

            instalments.append(Instalment(
                number: period + 1,
                date: date(for: period + 1, loan: loan, calendar: calendar),
                payment: payment, principal: principal, interest: interest, balance: balance
            ))
            if balance.isZero { break }
        }
        return Schedule(instalments: instalments, regularPayment: payments.first ?? .zero)
    }

    /// Amortising and revolving: interest accrues on the balance that is actually left.
    private static func reducingBalanceSchedule(
        loan: LoanInput,
        calendar: FinancialCalendar,
        extraPerPeriod: Money
    ) -> Schedule {
        let periods = loan.periodCount
        let rate = loan.periodicRate
        let regular = amortisingPayment(principal: loan.principal,
                                        periodicRate: rate, periods: periods)
        var instalments: [Instalment] = []
        var balance = loan.principal
        var index = 0

        // A guard rail: extra payments shorten the term, but a pathological rate must
        // never spin forever.
        let limit = periods + 600

        while balance.isPositive && index < limit {
            index += 1
            let interest = Money(minorUnits: Money.roundBankers(balance.decimalMinorUnits * rate))
            var payment = regular + extraPerPeriod

            // The last instalment settles the balance exactly.
            if payment >= balance + interest {
                payment = balance + interest
            }
            var principal = payment - interest

            // If the payment cannot even cover interest the loan never clears; stop
            // rather than looping, and surface it by ending the schedule.
            if !principal.isPositive && extraPerPeriod.isZero { break }
            if principal > balance { principal = balance }

            balance = (balance - principal).clampedToZero
            instalments.append(Instalment(
                number: index,
                date: date(for: index, loan: loan, calendar: calendar),
                payment: payment, principal: principal, interest: interest, balance: balance
            ))
        }
        return Schedule(instalments: instalments, regularPayment: regular)
    }

    private static func date(for index: Int, loan: LoanInput, calendar: FinancialCalendar) -> Date {
        let start = calendar.financialDay(for: loan.startDate)
        switch loan.paymentFrequency {
        case .weekly: return calendar.addDays(7 * index, to: start)
        case .biweekly: return calendar.addDays(14 * index, to: start)
        case .monthly: return calendar.addMonths(index, to: start)
        case .quarterly: return calendar.addMonths(3 * index, to: start)
        }
    }

    // MARK: - Position

    struct Position: Identifiable, Sendable {
        let loan: LoanInput

        var id: UUID { loan.id }

        let schedule: Schedule
        let remainingBalance: Money
        let interestRemaining: Money
        let payoffDate: Date?
        let paymentsRemaining: Int

        var paymentsMade: Int { loan.paymentsMade }
        var scheduledPayments: Int { schedule.periodCount }
        var isPaidOff: Bool { remainingBalance.isZero }
        var regularPayment: Money { schedule.regularPayment }

        /// A loan that is expensive, owed to family, or both.
        func isToxic(highInterestThreshold: Decimal) -> Bool {
            loan.annualRate > highInterestThreshold || loan.socialWeight >= 4
        }
    }

    static func position(for loan: LoanInput, calendar: FinancialCalendar) -> Position {
        let schedule = schedule(for: loan, calendar: calendar)
        let remainingInstalments = schedule.instalments.dropFirst(loan.paymentsMade)
        let remainingBalance = remainingInstalments.first.map { instalment in
            instalment.balance + instalment.principal
        } ?? .zero
        return Position(
            loan: loan,
            schedule: schedule,
            remainingBalance: remainingBalance,
            interestRemaining: Money.sum(remainingInstalments.map(\.interest)),
            payoffDate: remainingInstalments.last?.date ?? schedule.payoffDate,
            paymentsRemaining: remainingInstalments.count
        )
    }

    // MARK: - Extra payment simulator

    struct Simulation: Sendable {
        let extraPerPeriod: Money
        let basePayoffDate: Date?
        let newPayoffDate: Date?
        let periodsSaved: Int
        let interestSaved: Money
        let baseTotalInterest: Money
        let newTotalInterest: Money
    }

    /// "If I add X a month → payoff moves from A to B, saves Y in interest."
    static func simulateExtra(
        _ extra: Money, on loan: LoanInput, calendar: FinancialCalendar
    ) -> Simulation {
        let base = schedule(for: loan, calendar: calendar)
        let accelerated = schedule(for: loan, calendar: calendar, extraPerPeriod: extra)
        return Simulation(
            extraPerPeriod: extra,
            basePayoffDate: base.payoffDate,
            newPayoffDate: accelerated.payoffDate,
            periodsSaved: Swift.max(0, base.periodCount - accelerated.periodCount),
            interestSaved: (base.totalInterest - accelerated.totalInterest).clampedToZero,
            baseTotalInterest: base.totalInterest,
            newTotalInterest: accelerated.totalInterest
        )
    }

    // MARK: - Payoff order

    enum PayoffStrategy: String, CaseIterable, Identifiable, Sendable {
        case avalanche, snowball, peaceOfMind, balanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .avalanche: "Avalanche"
            case .snowball: "Snowball"
            case .peaceOfMind: "Peace of mind"
            case .balanced: "Balanced"
            }
        }

        var explanation: String {
            switch self {
            case .avalanche: "Highest rate first. Costs the least."
            case .snowball: "Smallest balance first. Clears one the soonest."
            case .peaceOfMind: "What you owe people first, whatever it costs."
            case .balanced: "Rate, who it is owed to, size and urgency, weighted."
            }
        }
    }

    struct Weights: Sendable {
        var apr: Decimal = Decimal(string: "0.4")!
        var social: Decimal = Decimal(string: "0.3")!
        var smallBalance: Decimal = Decimal(string: "0.2")!
        var urgency: Decimal = Decimal(string: "0.1")!

        static let `default` = Weights()
    }

    /// The order to clear debts in. Only loans you owe are ordered; a receivable is not
    /// a debt, and a paid loan is not in the queue.
    static func payoffOrder(
        _ positions: [Position],
        strategy: PayoffStrategy,
        weights: Weights = .default,
        today: Date = Date(),
        calendar: FinancialCalendar = FinancialCalendar()
    ) -> [Position] {
        let queue = positions.filter {
            $0.loan.direction == .iOwe && !$0.isPaidOff && $0.loan.status != .paid
        }
        switch strategy {
        case .avalanche:
            return queue.sorted { a, b in
                a.loan.annualRate == b.loan.annualRate
                    ? a.remainingBalance < b.remainingBalance
                    : a.loan.annualRate > b.loan.annualRate
            }
        case .snowball:
            return queue.sorted { a, b in
                a.remainingBalance == b.remainingBalance
                    ? a.loan.annualRate > b.loan.annualRate
                    : a.remainingBalance < b.remainingBalance
            }
        case .peaceOfMind:
            return queue.sorted { a, b in
                a.loan.socialWeight == b.loan.socialWeight
                    ? a.loan.annualRate > b.loan.annualRate
                    : a.loan.socialWeight > b.loan.socialWeight
            }
        case .balanced:
            let scored = queue.map { position in
                (position, score(position, in: queue, weights: weights,
                                 today: today, calendar: calendar))
            }
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// `w1·normAPR + w2·(socialWeight/5) + w3·smallBalanceBonus + w4·dueUrgency`.
    static func score(
        _ position: Position,
        in queue: [Position],
        weights: Weights,
        today: Date,
        calendar: FinancialCalendar
    ) -> Decimal {
        let maxRate = queue.map(\.loan.annualRate).max() ?? 0
        let normAPR = maxRate > 0 ? position.loan.annualRate / maxRate : 0

        let social = Decimal(position.loan.socialWeight) / 5

        let maxBalance = queue.map(\.remainingBalance).max() ?? .zero
        let smallBalanceBonus: Decimal = maxBalance.isPositive
            ? 1 - (position.remainingBalance.ratio(to: maxBalance) ?? 0)
            : 0

        // Urgency rises as the payoff date approaches; a loan already due scores 1.
        let urgency: Decimal
        if let payoff = position.payoffDate {
            let days = calendar.daysBetween(today, payoff)
            urgency = days <= 0 ? 1 : Decimal(1) / Decimal(1 + days / 30)
        } else {
            urgency = 0
        }

        return weights.apr * normAPR
            + weights.social * social
            + weights.smallBalance * smallBalanceBonus
            + weights.urgency * urgency
    }

    /// What choosing peace over arithmetic costs, stated plainly and without argument.
    static func costOfStrategy(
        _ strategy: PayoffStrategy,
        positions: [Position],
        calendar: FinancialCalendar
    ) -> Money {
        Money.sum(payoffOrder(positions, strategy: strategy, calendar: calendar)
            .map(\.interestRemaining))
    }

    // MARK: - Planned loan verdict

    enum Affordability: String, Sendable {
        case comfortable, tight, notAffordable

        var title: String {
            switch self {
            case .comfortable: "Comfortable"
            case .tight: "Tight"
            case .notAffordable: "Not affordable"
            }
        }
    }

    struct LoanVerdict: Sendable {
        let affordability: Affordability
        let verdict: Verdict
        /// `monthlyDebtPayments / medianMonthlyNetIncome`.
        let debtServiceRatio: Decimal
        let existingMonthlyDebt: Money
        let newMonthlyPayment: Money
        let totalInterestOverLife: Money
        let ruleIDs: [String]
    }

    /// Converts any payment frequency to a monthly figure.
    static func monthlyEquivalent(_ payment: Money, frequency: PaymentFrequency) -> Money {
        payment.scaled(by: Decimal(frequency.periodsPerYear) / Decimal(12))
    }

    /// The verdict before you sign, with its arithmetic.
    ///
    /// R4: above the ratio cap this is **Not affordable**, not "tight".
    static func verdict(
        for planned: LoanInput,
        existingPositions: [Position],
        medianMonthlyNetIncome: Money,
        maxDebtServiceRatio: Decimal,
        highInterestThreshold: Decimal,
        calendar: FinancialCalendar
    ) -> LoanVerdict {
        let schedule = schedule(for: planned, calendar: calendar)
        let newMonthly = monthlyEquivalent(schedule.regularPayment,
                                           frequency: planned.paymentFrequency)
        let existingMonthly = Money.sum(
            existingPositions
                .filter { $0.loan.direction == .iOwe && !$0.isPaidOff }
                .map { monthlyEquivalent($0.regularPayment, frequency: $0.loan.paymentFrequency) }
        )
        let totalMonthly = existingMonthly + newMonthly
        let ratio = medianMonthlyNetIncome.isPositive
            ? (totalMonthly.ratio(to: medianMonthlyNetIncome) ?? 0)
            : Decimal(1)

        var rules: [String] = []

        // R1 — no new debt for a depreciating asset while toxic debt is outstanding.
        let hasToxicDebt = existingPositions.contains {
            $0.loan.direction == .iOwe && !$0.isPaidOff
                && $0.isToxic(highInterestThreshold: highInterestThreshold)
        }
        if hasToxicDebt { rules.append("R1") }

        let affordability: Affordability
        if ratio > maxDebtServiceRatio {
            affordability = .notAffordable
            rules.append("R4")
        } else if ratio > Decimal(string: "0.15")! {
            affordability = .tight
        } else {
            affordability = .comfortable
        }

        let verdict: Verdict
        switch affordability {
        case .notAffordable: verdict = .blocked
        case .tight: verdict = hasToxicDebt ? .notAdvised : .approvedWithConditions
        case .comfortable: verdict = hasToxicDebt ? .approvedWithConditions : .approved
        }

        return LoanVerdict(
            affordability: affordability,
            verdict: verdict,
            debtServiceRatio: ratio,
            existingMonthlyDebt: existingMonthly,
            newMonthlyPayment: newMonthly,
            totalInterestOverLife: schedule.totalInterest,
            ruleIDs: rules
        )
    }
}
