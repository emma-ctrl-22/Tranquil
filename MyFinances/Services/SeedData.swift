import Foundation
import SwiftData

/// Sample data for development. Never runs automatically — it is invoked from the
/// debug menu only, and it refuses to touch a database that already has data.
enum SeedData {

    // MARK: - Defaults shipped on first run

    /// The categories a new, empty database starts with. Exactly one is Miscellaneous.
    static func defaultCategories(now: Date = Date()) -> [Category] {
        var sortOrder = 0
        func next() -> Int { defer { sortOrder += 1 }; return sortOrder }

        return [
            Category(name: "Trotro", group: "Transport", icon: "bus", colorHex: "#4E8FA8",
                     isEssential: true, isMicro: true, sortOrder: next(), now: now),
            Category(name: "Water", group: "Food & drink", icon: "drop", colorHex: "#5AA9C9",
                     isEssential: true, isMicro: true, sortOrder: next(), now: now),
            Category(name: "Lunch", group: "Food & drink", icon: "fork.knife", colorHex: "#C98B4E",
                     isEssential: true, isMicro: true, sortOrder: next(), now: now),
            Category(name: "Data", group: "Utilities", icon: "antenna.radiowaves.left.and.right",
                     colorHex: "#7B6FC9", isEssential: true, isMicro: true, sortOrder: next(), now: now),
            Category(name: "Airtime", group: "Utilities", icon: "phone", colorHex: "#8E7BC9",
                     isEssential: true, isMicro: true, sortOrder: next(), now: now),
            Category(name: "Snacks", group: "Food & drink", icon: "takeoutbag.and.cup.and.straw",
                     colorHex: "#C9A34E", isMicro: true, sortOrder: next(), now: now),
            Category(name: "Taxi", group: "Transport", icon: "car", colorHex: "#4E7CA8",
                     isMicro: true, sortOrder: next(), now: now),
            Category(name: "Groceries", group: "Food & drink", icon: "basket", colorHex: "#7AA84E",
                     isEssential: true, sortOrder: next(), now: now),

            Category(name: "Rent", group: "Living", icon: "house", colorHex: "#A8574E",
                     isEssential: true, sortOrder: next(), now: now),
            Category(name: "Electricity", group: "Utilities", icon: "bolt", colorHex: "#C9B24E",
                     isEssential: true, sortOrder: next(), now: now),
            Category(name: "Health", group: "Living", icon: "cross.case", colorHex: "#A84E7C",
                     isEssential: true, sortOrder: next(), now: now),

            // ADVISOR_RULES §1: skills and tools are investment, not discretionary.
            // The advisor defends this line during cutbacks.
            Category(name: "Skills & tools", group: "Earning power", icon: "graduationcap",
                     colorHex: "#3F8F6E", isEarningPower: true, sortOrder: next(), now: now),

            Category(name: "Social", group: "Discretionary", icon: "person.2", colorHex: "#B5739A",
                     sortOrder: next(), now: now),
            Category(name: "Gifts", group: "Discretionary", icon: "gift", colorHex: "#B57373",
                     sortOrder: next(), now: now),
            Category(name: "Subscriptions", group: "Utilities", icon: "repeat", colorHex: "#6F86C9",
                     sortOrder: next(), now: now),

            // First-class envelope, not a leftover. This is where discipline actually breaks.
            Category(name: "Miscellaneous", group: "Miscellaneous", icon: "questionmark.circle",
                     colorHex: "#8A8A8A", isMiscellaneous: true, sortOrder: next(), now: now),
        ]
    }

    /// The sinking funds every setup starts with (BUILD_PROMPT F10).
    static func defaultSinkingFunds(holdingAccount: Account?, now: Date = Date()) -> [SinkingFund] {
        let specs: [(String, String, Bool)] = [
            ("Emergency", "umbrella", true),
            ("Gifts", "gift", false),
            ("Social obligations", "person.2", false),
            ("Rent", "house", false),
            ("Repairs & replacements", "wrench.and.screwdriver", false),
            ("Health", "cross.case", false),
            ("Annual renewals", "calendar", false),
        ]
        return specs.enumerated().map { index, spec in
            SinkingFund(
                name: spec.0,
                targetAmount: .zero,
                cadence: .monthly,
                holdingAccount: holdingAccount,
                isEmergencyFund: spec.2,
                icon: spec.1,
                sortOrder: index,
                now: now
            )
        }
    }

    // MARK: - Demo dataset

    struct Summary {
        var accounts = 0
        var categories = 0
        var transactions = 0
        var loans = 0
        var goals = 0
        var sinkingFunds = 0
        var recurringRules = 0
    }

    /// A realistic 6-month dataset. Refuses to run if any accounts already exist.
    @discardableResult
    static func loadDemo(
        into context: ModelContext,
        calendar: FinancialCalendar,
        transactionCount: Int = 320
    ) throws -> Summary {
        let existing = try context.fetch(FetchDescriptor<Account>())
        guard existing.isEmpty else {
            throw SeedError.databaseNotEmpty
        }

        var summary = Summary()
        let now = calendar.currentDate()
        let today = calendar.today()
        var random = SeededGenerator(seed: 20_260_912)

        // Settings
        let settings = AppSettings(now: now)
        settings.applyCurrency(.ghs)
        settings.incomeType = .mixed
        settings.birthYear = 2002
        settings.hasCompletedSetup = true
        context.insert(settings)

        // Accounts
        let cash = Account(name: "Cash", type: .cash, openingBalance: cedis(120),
                           colorHex: "#7AA84E", sortOrder: 0, lowBalanceFloor: cedis(20), now: now)
        let momo = Account(name: "MTN MoMo", type: .mobileMoney, openingBalance: cedis(430),
                           colorHex: "#C9B24E", sortOrder: 1, lowBalanceFloor: cedis(50), now: now)
        let bank = Account(name: "GCB Current", type: .bank, openingBalance: cedis(1_850),
                           colorHex: "#4E8FA8", sortOrder: 2, lowBalanceFloor: cedis(200), now: now)
        let savings = Account(name: "Savings", type: .savings, openingBalance: cedis(2_400),
                              colorHex: "#3F8F6E", sortOrder: 3, isEmergencyFundAccount: true, now: now)
        let investment = Account(name: "Investment", type: .investment, openingBalance: cedis(3_100),
                                 colorHex: "#7B6FC9", sortOrder: 4, now: now)
        let taxReserve = Account(name: "Tax reserve", type: .savings, openingBalance: cedis(640),
                                 colorHex: "#8A8A8A", sortOrder: 5, isTaxReserve: true, now: now)
        let accounts = [cash, momo, bank, savings, investment, taxReserve]
        accounts.forEach(context.insert)
        summary.accounts = accounts.count

        // Categories
        let categories = defaultCategories(now: now)
        categories.forEach(context.insert)
        summary.categories = categories.count
        func category(_ name: String) -> Category? { categories.first { $0.name == name } }

        // Envelopes — weekly is the primary unit, and Miscellaneous gets a real number.
        let envelopes: [(String, Int)] = [
            ("Trotro", 60), ("Lunch", 120), ("Data", 40), ("Snacks", 35),
            ("Groceries", 150), ("Social", 80), ("Skills & tools", 100), ("Miscellaneous", 90),
        ]
        for (name, weekly) in envelopes {
            guard let target = category(name) else { continue }
            context.insert(Budget(category: target, period: .weekly, amount: cedis(weekly),
                                  rollover: name == "Skills & tools", now: now))
        }

        // Recurring rules
        let rules = [
            RecurringRule(label: "Salary", kind: .income, amount: cedis(3_200), account: bank,
                          cadence: .monthly(day: 28),
                          nextDueDate: calendar.nextMonthly(dayOfMonth: 28, after: today) ?? today,
                          mode: .remindOnly, now: now),
            RecurringRule(label: "Rent", kind: .expense, amount: cedis(900), account: bank,
                          category: category("Rent"), cadence: .monthly(day: 1),
                          nextDueDate: calendar.nextMonthly(dayOfMonth: 1, after: today) ?? today,
                          isCommittedOutflow: true, now: now),
            RecurringRule(label: "Electricity", kind: .expense, amount: cedis(180), account: momo,
                          category: category("Electricity"), cadence: .monthly(day: 12),
                          nextDueDate: calendar.nextMonthly(dayOfMonth: 12, after: today) ?? today,
                          isVariableAmount: true, isCommittedOutflow: true, now: now),
            RecurringRule(label: "Monthly investment", kind: .transfer, amount: cedis(400),
                          account: bank, counterAccount: investment, cadence: .monthly(day: 2),
                          nextDueDate: calendar.nextMonthly(dayOfMonth: 2, after: today) ?? today,
                          mode: .autoPost, isCommittedOutflow: true, now: now),
        ]
        rules.forEach(context.insert)
        summary.recurringRules = rules.count

        // Loans
        let schoolLoan = Loan(
            name: "Top-up fees", lender: "Cousin Ama", direction: .iOwe,
            principal: cedis(2_000), interestModel: .interestFree,
            startDate: calendar.addMonths(-4, to: today), termMonths: 10,
            scheduledPayment: cedis(200), socialWeight: 5, account: momo,
            notes: "Family. Pay this before anything cheaper.", now: now
        )
        let phoneLoan = Loan(
            name: "Laptop financing", lender: "QuickCredit", direction: .iOwe,
            principal: cedis(4_500), interestModel: .amortizing(apr: Decimal(0.32)),
            startDate: calendar.addMonths(-6, to: today), termMonths: 18,
            scheduledPayment: cedis(330), socialWeight: 1, account: bank, now: now
        )
        let lentOut = Loan(
            name: "Lent to Kojo", lender: "Kojo", direction: .owedToMe,
            principal: cedis(500), interestModel: .interestFree,
            startDate: calendar.addMonths(-2, to: today), termMonths: 6,
            scheduledPayment: .zero, socialWeight: 3, account: momo,
            notes: "R11: receivable at zero expected return. Not an asset.", now: now
        )
        [schoolLoan, phoneLoan, lentOut].forEach(context.insert)
        summary.loans = 3

        // Sinking funds
        let funds = defaultSinkingFunds(holdingAccount: savings, now: now)
        funds.forEach(context.insert)
        summary.sinkingFunds = funds.count
        if let emergency = funds.first(where: { $0.isEmergencyFund }) {
            emergency.targetAmount = cedis(9_000)
            context.insert(Earmark(ownerType: .emergencyFund, ownerID: emergency.id,
                                   account: savings, amount: cedis(1_600), now: now))
        }
        if let gifts = funds.first(where: { $0.name == "Gifts" }) {
            gifts.targetAmount = cedis(1_200)
            gifts.targetDate = calendar.addMonths(12, to: today)
        }

        // Goals
        let phone = Goal(name: "iPhone 15", targetAmount: cedis(9_500),
                         targetDate: calendar.addMonths(8, to: today), priorityRank: 0,
                         holdingAccount: savings, monthlyCap: cedis(600), desireLevel: 5, now: now)
        let course = Goal(name: "Backend course", targetAmount: cedis(1_800), priorityRank: 1,
                          holdingAccount: savings, desireLevel: 4, now: now)
        [phone, course].forEach(context.insert)
        summary.goals = 2
        context.insert(Earmark(ownerType: .goal, ownerID: phone.id, account: savings,
                               amount: cedis(480), now: now))
        context.insert(Earmark(ownerType: .goal, ownerID: course.id, account: savings,
                               amount: cedis(300), now: now))

        // Scheduled events
        let events: [(String, Int, Int)] = [
            ("Mum's birthday", 40, 150), ("Kofi's wedding", 75, 400), ("School fees", 110, 1_200),
        ]
        for (label, dayOffset, amount) in events {
            context.insert(ScheduledEvent(
                label: label, expectedDate: calendar.addDays(dayOffset, to: today),
                expectedAmount: cedis(amount),
                sinkingFund: funds.first { $0.name == "Gifts" },
                confidence: dayOffset > 100 ? .likely : .certain, now: now
            ))
        }

        // Transactions across the last 180 financial days
        summary.transactions = try generateTransactions(
            count: transactionCount, into: context, calendar: calendar,
            spanDays: 180, accounts: [cash, momo, bank], categories: categories,
            incomeAccount: bank, investmentAccount: investment, random: &random, now: now
        )

        try context.save()
        return summary
    }

    /// A large dataset for the "5,000 transactions without lag" requirement.
    /// Appends to whatever is already there, so run `loadDemo` first.
    @discardableResult
    static func loadStressTransactions(
        into context: ModelContext,
        calendar: FinancialCalendar,
        count: Int = 5_000
    ) throws -> Int {
        let accounts = try context.fetch(FetchDescriptor<Account>())
            .filter { $0.deletedAt == nil && $0.isSpendable && $0.isLiquid }
        let categories = try context.fetch(FetchDescriptor<Category>()).filter { $0.deletedAt == nil }
        guard !accounts.isEmpty, !categories.isEmpty else { throw SeedError.databaseEmpty }

        var random = SeededGenerator(seed: 777)
        let inserted = try generateTransactions(
            count: count, into: context, calendar: calendar, spanDays: 1_095,
            accounts: accounts, categories: categories,
            incomeAccount: accounts.first { $0.type == .bank } ?? accounts[0],
            investmentAccount: try context.fetch(FetchDescriptor<Account>())
                .first { $0.type == .investment },
            random: &random, now: calendar.currentDate()
        )
        try context.save()
        return inserted
    }

    /// Deletes everything. Used by the debug menu only, behind a confirmation.
    static func wipe(_ context: ModelContext) throws {
        try context.delete(model: Transaction.self)
        try context.delete(model: LoanPayment.self)
        try context.delete(model: IncomeAllocation.self)
        try context.delete(model: IncomeEvent.self)
        try context.delete(model: Earmark.self)
        try context.delete(model: Goal.self)
        try context.delete(model: SinkingFund.self)
        try context.delete(model: ScheduledEvent.self)
        try context.delete(model: Loan.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: Budget.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.delete(model: DailyLog.self)
        try context.delete(model: LadderState.self)
        try context.delete(model: BalanceSnapshot.self)
        try context.delete(model: OverrideLog.self)
        try context.delete(model: AppSettings.self)
        try context.save()
    }

    enum SeedError: LocalizedError {
        case databaseNotEmpty
        case databaseEmpty

        var errorDescription: String? {
            switch self {
            case .databaseNotEmpty: "Seed data only loads into an empty database. Wipe first."
            case .databaseEmpty: "Load the demo data before adding stress transactions."
            }
        }
    }

    // MARK: - Internals

    /// `₵n.00` — seed amounts only. Nothing outside this file builds Money from a literal count of major units.
    private static func cedis(_ major: Int) -> Money { Money(minorUnits: major * 100) }

    private static func generateTransactions(
        count: Int,
        into context: ModelContext,
        calendar: FinancialCalendar,
        spanDays: Int,
        accounts: [Account],
        categories: [Category],
        incomeAccount: Account?,
        investmentAccount: Account?,
        random: inout SeededGenerator,
        now: Date
    ) throws -> Int {
        let today = calendar.today()
        let micro = categories.filter { $0.isMicro }
        let regular = categories.filter { !$0.isMicro && !$0.isMiscellaneous }
        let miscellaneous = categories.first { $0.isMiscellaneous }
        guard !micro.isEmpty || !regular.isEmpty else { return 0 }

        var inserted = 0
        for index in 0..<count {
            let dayOffset = -random.nextInt(below: spanDays)
            let day = calendar.addDays(dayOffset, to: today)
            // Spread entries across the day, including a few after midnight so the
            // 04:00 day boundary actually gets exercised by the demo data.
            let minuteOfDay = random.nextInt(below: 1_440)
            let date = calendar.calendar.date(byAdding: .minute, value: minuteOfDay,
                                              to: calendar.startOfFinancialDay(day)) ?? day
            let account = accounts[random.nextInt(below: accounts.count)]

            let roll = random.nextInt(below: 100)
            let transaction: Transaction
            switch roll {
            case 0..<4 where incomeAccount != nil:
                transaction = Transaction(
                    date: date, amount: cedis(400 + random.nextInt(below: 2_800)),
                    kind: .income, account: incomeAccount,
                    note: ["Project payment", "Salary", "Side gig"][random.nextInt(below: 3)],
                    now: now
                )
            case 4..<7 where investmentAccount != nil:
                transaction = Transaction(
                    date: date, amount: cedis(100 + random.nextInt(below: 400)),
                    kind: .transfer, account: incomeAccount ?? account,
                    counterAccount: investmentAccount, note: "Monthly investment", now: now
                )
            case 7..<12 where miscellaneous != nil:
                // "I spent something, not sure what" — estimates land in Needs review.
                transaction = Transaction(
                    date: date, amount: Money(minorUnits: 200 + random.nextInt(below: 4_000)),
                    kind: .expense, account: account, category: miscellaneous,
                    isEstimate: true, now: now
                )
            case 12..<70 where !micro.isEmpty:
                let chosen = micro[random.nextInt(below: micro.count)]
                transaction = Transaction(
                    date: date, amount: Money(minorUnits: 200 + random.nextInt(below: 2_300)),
                    kind: .expense, account: account, category: chosen, now: now
                )
            default:
                let pool = regular.isEmpty ? micro : regular
                guard !pool.isEmpty else { continue }
                let chosen = pool[random.nextInt(below: pool.count)]
                transaction = Transaction(
                    date: date, amount: Money(minorUnits: 1_500 + random.nextInt(below: 18_000)),
                    kind: .expense, account: account, category: chosen, now: now
                )
            }

            context.insert(transaction)
            inserted += 1
            if index % 500 == 499 { try context.save() }
        }
        return inserted
    }
}

/// Deterministic PRNG, so seeded databases are reproducible and screenshots don't churn.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    /// A value in `0..<upperBound`, as an `Int`, which is what the seed generator wants.
    mutating func nextInt(below upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        return Int(next(upperBound: UInt64(upperBound)))
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
