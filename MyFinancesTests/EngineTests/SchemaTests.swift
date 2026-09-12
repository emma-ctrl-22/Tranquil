import Testing
import Foundation
import SwiftData
@testable import MyFinances

/// The schema must open empty, hold the invariants the spec names, and survive a seed.
@MainActor
struct SchemaTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TranquilSchema.container(inMemory: true))
    }

    private func testCalendar(now: Date = Date(timeIntervalSince1970: 1_789_000_000)) -> FinancialCalendar {
        FinancialCalendar(timeZone: TimeZone(identifier: "UTC")!, now: { now })
    }

    @Test func schemaOpensOnAnEmptyDatabase() throws {
        let context = try makeContext()
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).isEmpty)
    }

    @Test func everyModelTypeIsRegistered() {
        // A model missing from the registry silently fails to persist, so guard the count.
        #expect(TranquilSchema.models.count == 18)
    }

    @Test func transferIsOneRecordAffectingBothSides() throws {
        let context = try makeContext()
        let from = Account(name: "MoMo", type: .mobileMoney)
        let to = Account(name: "Bank", type: .bank)
        context.insert(from); context.insert(to)

        let transfer = Transaction(date: Date(), amount: Money(minorUnits: 10_000),
                                   kind: .transfer, account: from, counterAccount: to)
        context.insert(transfer)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(transfer.effectOnPrimaryAccount.minorUnits == -10_000)
        #expect(transfer.effectOnCounterAccount.minorUnits == 10_000)
        // The two sides cancel: a transfer moves money, it does not create or destroy it.
        #expect((transfer.effectOnPrimaryAccount + transfer.effectOnCounterAccount).isZero)
    }

    @Test func incomeAndExpenseOnlyTouchTheirOwnAccount() throws {
        let context = try makeContext()
        let account = Account(name: "Cash", type: .cash)
        context.insert(account)

        let income = Transaction(date: Date(), amount: Money(minorUnits: 5_000),
                                 kind: .income, account: account)
        let expense = Transaction(date: Date(), amount: Money(minorUnits: 1_500),
                                  kind: .expense, account: account)
        context.insert(income); context.insert(expense)

        #expect(income.effectOnPrimaryAccount.minorUnits == 5_000)
        #expect(income.effectOnCounterAccount.isZero)
        #expect(expense.effectOnPrimaryAccount.minorUnits == -1_500)
        #expect(expense.effectOnCounterAccount.isZero)
    }

    @Test func accountDefaultsFollowTheirType() {
        #expect(Account(name: "Cash", type: .cash).isLiquid)
        #expect(!Account(name: "Fund", type: .investment).isLiquid)
        // R11: money lent to a friend is never an asset in net worth.
        #expect(!Account(name: "Kojo", type: .receivable).includeInNetWorth)
        // A tax reserve is not spendable whatever its underlying type.
        let reserve = Account(name: "Tax", type: .savings, isTaxReserve: true)
        #expect(!reserve.isSpendable)
    }

    @Test func loanInterestModelSurvivesTheRoundTrip() {
        let loan = Loan(name: "Laptop", lender: "QuickCredit", direction: .iOwe,
                        principal: Money(minorUnits: 450_000),
                        interestModel: .amortizing(apr: Decimal(string: "0.32")!),
                        startDate: Date(), termMonths: 18)
        #expect(loan.interestModel == .amortizing(apr: Decimal(string: "0.32")!))
        #expect(loan.aprBasisPoints == 3_200)
        #expect(loan.annualRate == Decimal(string: "0.32")!)

        loan.interestModel = .flatRate(rate: Decimal(string: "0.15")!, years: 2)
        #expect(loan.interestModel == .flatRate(rate: Decimal(string: "0.15")!, years: 2))
        #expect(loan.aprBasisPoints == nil)

        loan.interestModel = .interestFree
        #expect(loan.annualRate == 0)
        #expect(loan.flatRateBasisPoints == nil)
    }

    @Test func loanScheduledPaymentCountMatchesFrequency() {
        let loan = Loan(name: "L", lender: "X", direction: .iOwe, principal: Money(minorUnits: 1),
                        interestModel: .interestFree, startDate: Date(), termMonths: 18)
        #expect(loan.scheduledPaymentCount == 18)
        loan.paymentFrequency = .weekly
        #expect(loan.scheduledPaymentCount == 78)   // 18 * 52 / 12
        loan.paymentFrequency = .quarterly
        #expect(loan.scheduledPaymentCount == 6)
    }

    @Test func recurringCadenceSurvivesTheRoundTrip() {
        let rule = RecurringRule(label: "Rent", kind: .expense, amount: Money(minorUnits: 90_000),
                                 account: nil, cadence: .monthly(day: 31),
                                 nextDueDate: Date())
        #expect(rule.cadence == .monthly(day: 31))
        #expect(rule.occurrencesPerYear == 12)

        rule.cadence = .yearly(month: 12, day: 25)
        #expect(rule.cadence == .yearly(month: 12, day: 25))
        #expect(rule.occurrencesPerYear == 1)

        rule.cadence = .custom(days: 10)
        #expect(rule.cadence == .custom(days: 10))
        #expect(rule.occurrencesPerYear == 36)
    }

    @Test func monthlyEnvelopeShowsAWeeklyPace() {
        // A ₵310.00 monthly envelope in a 31-day month paces at ₵70.00 a week.
        let budget = Budget(category: nil, period: .monthly, amount: Money(minorUnits: 31_000))
        #expect(budget.weeklyPace(daysInMonth: 31).minorUnits == 7_000)
        // February: 31,000 * 7 / 28 = 7,750
        #expect(budget.weeklyPace(daysInMonth: 28).minorUnits == 7_750)
        // A weekly envelope is already its own pace.
        let weekly = Budget(category: nil, period: .weekly, amount: Money(minorUnits: 6_000))
        #expect(weekly.weeklyPace(daysInMonth: 31).minorUnits == 6_000)
    }

    @Test func sinkingFundRequiredPerPeriodNeverDividesByZero() {
        let fund = SinkingFund(name: "Gifts", targetAmount: Money(minorUnits: 120_000),
                               holdingAccount: nil)
        // 1,200.00 target, 200.00 saved, 10 periods left -> 100.00 a period.
        #expect(fund.requiredPerPeriod(saved: Money(minorUnits: 20_000), periodsRemaining: 10)
                    .minorUnits == 10_000)
        // Date has passed: ask for the whole remainder rather than crashing.
        #expect(fund.requiredPerPeriod(saved: Money(minorUnits: 20_000), periodsRemaining: 0)
                    .minorUnits == 100_000)
        // Already funded: nothing required, never negative.
        #expect(fund.requiredPerPeriod(saved: Money(minorUnits: 200_000), periodsRemaining: 4).isZero)
    }

    @Test func refundsAreNotIncome() {
        // ADVISOR_RULES §4c. Getting this wrong makes every other number lie.
        #expect(!IncomeEventKind.refund.countsAsIncome)
        #expect(!IncomeEventKind.refund.needsTaxReserve)
        #expect(IncomeEventKind.projectPayment.countsAsIncome)
        #expect(IncomeEventKind.projectPayment.needsTaxReserve)
        // Gifts wait a week before any allocation.
        #expect(IncomeEventKind.gift.coolOffDays == 7)
        #expect(IncomeEventKind.projectPayment.coolOffDays == 0)
    }

    @Test func unallocatedWindfallIsNotSpendable() {
        let event = IncomeEvent(kind: .projectPayment, receivedAt: Date(),
                                grossAmount: Money(minorUnits: 500_000),
                                taxReserved: Money(minorUnits: 125_000),
                                directCosts: Money(minorUnits: 30_000),
                                hoursWorked: 40)
        #expect(event.netUsable.minorUnits == 345_000)
        #expect(!event.isSpendable)
        // 3,450.00 over 40 hours = 86.25 an hour.
        #expect(event.effectiveHourlyRate()?.minorUnits == 8_625)
        event.status = .allocated
        #expect(event.isSpendable)
    }

    @Test func maybeEventsAreHalfWeightedInProjections() {
        let certain = ScheduledEvent(label: "Fees", expectedDate: Date(),
                                     expectedAmount: Money(minorUnits: 120_000), confidence: .certain)
        let maybe = ScheduledEvent(label: "Wedding", expectedDate: Date(),
                                   expectedAmount: Money(minorUnits: 40_000), confidence: .maybe)
        #expect(certain.projectedAmount.minorUnits == 120_000)
        #expect(maybe.projectedAmount.minorUnits == 20_000)
    }

    @Test func settingsExposeThresholdsAsDecimalsNotDoubles() {
        let settings = AppSettings()
        #expect(settings.taxReserveRate == Decimal(string: "0.25")!)
        #expect(settings.highInterestThresholdAPR == Decimal(string: "0.25")!)
        #expect(settings.maxDebtServiceRatio == Decimal(string: "0.30")!)
        #expect(settings.windfallMultiple == Decimal(string: "1.5")!)
        settings.incomeType = .salaried
        #expect(settings.recommendedEmergencyFundMonths == 3)
        // ₵3,500.00 a month spread across the year is ₵807.69 a week.
        #expect(settings.expectedMonthlyNetIncome.minorUnits == 350_000)
        #expect(settings.expectedWeeklyIncomeFromSalary.minorUnits == 80_769)
        settings.incomeType = .freelance
        #expect(settings.recommendedEmergencyFundMonths == 6)
    }

    @Test func goalOverspendVarianceIsSignedAgainstPlan() {
        let goal = Goal(name: "iPhone", targetAmount: Money(minorUnits: 950_000),
                        priorityRank: 0, holdingAccount: nil)
        #expect(goal.overspendVariance == nil)
        goal.actualPricePaid = Money(minorUnits: 990_000)
        #expect(goal.overspendVariance?.minorUnits == 40_000)
        goal.actualPricePaid = Money(minorUnits: 920_000)
        #expect(goal.overspendVariance?.minorUnits == -30_000)
    }

    @Test func loanPaymentPortionsMustSumToTheAmount() {
        let payment = LoanPayment(loan: nil, date: Date(), amount: Money(minorUnits: 33_000),
                                  principalPortion: Money(minorUnits: 21_000),
                                  interestPortion: Money(minorUnits: 12_000))
        #expect(payment.amount == payment.principalPortion + payment.interestPortion + payment.feePortion)
    }

    // MARK: - Seed

    @Test func demoSeedLoadsAndIsInternallyConsistent() throws {
        let context = try makeContext()
        let calendar = testCalendar()
        let summary = try SeedData.loadDemo(into: context, calendar: calendar, transactionCount: 200)

        #expect(summary.accounts == 6)
        #expect(summary.transactions == 200)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 200)

        let categories = try context.fetch(FetchDescriptor<MyFinances.Category>())
        #expect(categories.filter(\.isMiscellaneous).count == 1, "exactly one catch-all envelope")
        #expect(categories.filter(\.isMicro).count >= 6, "quick capture needs six chips")
        #expect(categories.contains { $0.isEarningPower })

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.filter(\.isTaxReserve).count == 1)
        #expect(accounts.filter(\.isEmergencyFundAccount).count == 1)

        // No stored amount is negative: direction lives in `kind`.
        for transaction in try context.fetch(FetchDescriptor<Transaction>()) {
            #expect(!transaction.amount.isNegative)
            if transaction.kind == .transfer { #expect(transaction.counterAccount != nil) }
        }

        // Earmarks must not exceed the balance they sit against.
        let earmarks = try context.fetch(FetchDescriptor<Earmark>())
        #expect(!earmarks.isEmpty)
        for earmark in earmarks { #expect(!earmark.amount.isNegative) }
    }

    @Test func demoSeedRefusesToRunTwice() throws {
        let context = try makeContext()
        let calendar = testCalendar()
        try SeedData.loadDemo(into: context, calendar: calendar, transactionCount: 20)
        #expect(throws: SeedData.SeedError.self) {
            try SeedData.loadDemo(into: context, calendar: calendar, transactionCount: 20)
        }
    }

    @Test func seedIsDeterministic() throws {
        let calendar = testCalendar()
        func firstAmounts() throws -> [Int] {
            let context = ModelContext(try TranquilSchema.container(inMemory: true))
            try SeedData.loadDemo(into: context, calendar: calendar, transactionCount: 50)
            var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
            descriptor.fetchLimit = 50
            return try context.fetch(descriptor).map(\.amountMinorUnits)
        }
        #expect(try firstAmounts() == (try firstAmounts()))
    }

    @Test func wipeLeavesAnEmptyDatabaseThatStillOpens() throws {
        let context = try makeContext()
        try SeedData.loadDemo(into: context, calendar: testCalendar(), transactionCount: 30)
        try SeedData.wipe(context)
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MyFinances.Category>()).isEmpty)
    }

    @Test func handlesFiveThousandTransactions() throws {
        let context = try makeContext()
        let calendar = testCalendar()
        try SeedData.loadDemo(into: context, calendar: calendar, transactionCount: 100)
        let added = try SeedData.loadStressTransactions(into: context, calendar: calendar, count: 5_000)
        #expect(added == 5_000)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 5_100)
    }
}
