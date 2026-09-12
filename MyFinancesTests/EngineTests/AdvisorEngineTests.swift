import Testing
import Foundation
@testable import MyFinances

struct AdvisorEngineTests {
    private let formatter = MoneyFormatter(currency: .ghs, locale: Locale(identifier: "en_GB"))

    private func situation(_ change: (inout AdvisorEngine.Situation) -> Void = { _ in })
    -> AdvisorEngine.Situation {
        var base = AdvisorEngine.Situation()
        base.liquidAvailable = Money(minorUnits: 500_000)
        base.essentialMonthlySpend = Money(minorUnits: 300_000)
        base.emergencyFundBalance = Money(minorUnits: 1_800_000)
        base.emergencyFundTargetMonths = 6
        base.netWorth = Money(minorUnits: 2_000_000)
        base.ladderStage = .emergencyFund
        base.investedThisMonth = true
        change(&base)
        return base
    }

    // MARK: - The rule book

    @Test func allElevenRulesArePresentAndUnique() {
        #expect(AdvisorEngine.rules.count == 11)
        let ids = AdvisorEngine.rules.map(\.id)
        #expect(Set(ids).count == 11)
        #expect(ids == (1...11).map { "R\($0)" })
    }

    @Test func onlyR2HasNoOverridePath() {
        // This is the one rule the spec says can never be overridden.
        let nonOverridable = AdvisorEngine.rules.filter { !$0.canOverride }
        #expect(nonOverridable.map(\.id) == ["R2"])
    }

    @Test func everyRuleStatesItsReasoning() {
        for rule in AdvisorEngine.rules {
            #expect(!rule.title.isEmpty)
            #expect(!rule.rationale.isEmpty)
            #expect(!rule.rationale.contains("!"))
        }
    }

    // MARK: - Order of Operations

    @Test func theTaxReserveComesBeforeEverything() {
        let position = AdvisorEngine.position(situation {
            $0.taxReserveOwed = Money(minorUnits: 50_000)
            $0.hasOverduePayments = true
            $0.highInterestDebtRemaining = Money(minorUnits: 500_000)
        })
        #expect(position.step == .taxReserve)
    }

    @Test func overduePaymentsOutrankEverythingBelowThem() {
        let position = AdvisorEngine.position(situation {
            $0.hasOverduePayments = true
            $0.highInterestDebtRemaining = Money(minorUnits: 500_000)
        })
        #expect(position.step == .minimumPayments)
    }

    @Test func theBufferComesBeforeDebtAndInvesting() {
        let position = AdvisorEngine.position(situation {
            $0.liquidAvailable = Money(minorUnits: 10_000)
            $0.highInterestDebtRemaining = Money(minorUnits: 500_000)
        })
        #expect(position.step == .starterBuffer)
    }

    @Test func theEmployerMatchOutranksClearingExpensiveDebt() {
        // A guaranteed 100% beats a guaranteed 30%.
        let position = AdvisorEngine.position(situation {
            $0.hasEmployerMatchAvailable = true
            $0.highInterestDebtRemaining = Money(minorUnits: 500_000)
        })
        #expect(position.step == .employerMatch)
    }

    @Test func expensiveDebtComesBeforeTheEmergencyFund() {
        let position = AdvisorEngine.position(situation {
            $0.highInterestDebtRemaining = Money(minorUnits: 500_000)
            $0.emergencyFundBalance = .zero
        })
        #expect(position.step == .highInterestDebt)
    }

    @Test func aCleanSituationReachesTheBottomOfTheList() {
        #expect(AdvisorEngine.position(situation()).step == .speculation)
    }

    @Test func theStepsAreOrderedAsTheSpecLists() {
        #expect(AdvisorEngine.Step.allCases.map(\.rawValue) == Array(1...11))
    }

    // MARK: - R2

    @Test func borrowingToInvestIsBlockedWithNoWayPast() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 100_000)
        proposal.isBorrowedToInvest = true
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        #expect(assessment.verdict == .blocked)
        #expect(assessment.isAbsolutelyBlocked)
        #expect(assessment.findings.contains { $0.ruleID == "R2" && !$0.canOverride })
    }

    @Test func everyOtherBlockCanBeOverridden() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 100_000)
        proposal.instalmentMonths = 24
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        #expect(assessment.verdict == .blocked)
        #expect(!assessment.isAbsolutelyBlocked)
        #expect(assessment.requiresOverride)
    }

    // MARK: - Individual rules

    @Test func r1FiresOnDepreciatingAssetsWhileExpensiveDebtRemains() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 100_000)
        proposal.isDepreciatingAsset = true
        let withDebt = AdvisorEngine.assess(
            proposal, situation: situation { $0.highInterestDebtRemaining = Money(minorUnits: 200_000) },
            formatter: formatter
        )
        #expect(withDebt.findings.contains { $0.ruleID == "R1" })
        let withoutDebt = AdvisorEngine.assess(proposal, situation: situation(),
                                               formatter: formatter)
        #expect(!withoutDebt.findings.contains { $0.ruleID == "R1" })
    }

    @Test func r5BlocksInvestingWhileExpensiveDebtRemains() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 100_000)
        proposal.isInvestment = true
        let assessment = AdvisorEngine.assess(
            proposal,
            situation: situation { $0.highInterestDebtRemaining = Money(minorUnits: 200_000) },
            formatter: formatter
        )
        #expect(assessment.findings.contains { $0.ruleID == "R5" })
    }

    @Test func r6ProtectsTheLastMonthOfTheEmergencyFund() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 1_700_000)
        proposal.fromEmergencyFund = true
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        // ₵18,000 less ₵17,000 leaves ₵1,000, under one month of ₵3,000 essentials.
        #expect(assessment.findings.contains { $0.ruleID == "R6" })

        var small = proposal
        small.amount = Money(minorUnits: 100_000)
        let fine = AdvisorEngine.assess(small, situation: situation(), formatter: formatter)
        #expect(!fine.findings.contains { $0.ruleID == "R6" })
    }

    @Test func r7FiresWhenAPurchaseCostsYouAStage() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 400_000)
        // ₵5,000 liquid less ₵4,000 leaves ₵1,000, under the ₵1,500 two-week buffer.
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        #expect(assessment.findings.contains { $0.ruleID == "R7" })
    }

    @Test func r8FiresOnlyAboveSixMonths() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 50_000)
        proposal.instalmentMonths = 6
        #expect(!AdvisorEngine.assess(proposal, situation: situation(), formatter: formatter)
            .findings.contains { $0.ruleID == "R8" })
        proposal.instalmentMonths = 7
        #expect(AdvisorEngine.assess(proposal, situation: situation(), formatter: formatter)
            .findings.contains { $0.ruleID == "R8" })
    }

    @Test func r9GatesSpeculationOnStageAndOnTheCap() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 50_000)
        proposal.isSpeculative = true

        let tooEarly = AdvisorEngine.assess(
            proposal, situation: situation { $0.ladderStage = .twoWeekBuffer },
            formatter: formatter
        )
        #expect(tooEarly.findings.contains { $0.ruleID == "R9" })

        // At stage 4 with ₵20,000 net worth the cap is ₵1,000; ₵500 is inside it.
        let withinCap = AdvisorEngine.assess(proposal, situation: situation(),
                                             formatter: formatter)
        #expect(!withinCap.findings.contains { $0.ruleID == "R9" })

        var large = proposal
        large.amount = Money(minorUnits: 200_000)
        let overCap = AdvisorEngine.assess(large, situation: situation(), formatter: formatter)
        #expect(overCap.findings.contains { $0.ruleID == "R9" })
    }

    @Test func r10BlocksLockedProductsBeforeTheEmergencyFundExists() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 50_000)
        proposal.isIlliquidOrLocked = true
        let assessment = AdvisorEngine.assess(
            proposal, situation: situation { $0.emergencyFundBalance = Money(minorUnits: 100_000) },
            formatter: formatter
        )
        #expect(assessment.findings.contains { $0.ruleID == "R10" })
    }

    // MARK: - Verdicts and voice

    @Test func acleanProposalIsApproved() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 20_000)
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        #expect(assessment.verdict == .approved)
        #expect(assessment.findings.isEmpty)
    }

    @Test func anOwedTaxReserveMakesEverythingConditional() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 20_000)
        let assessment = AdvisorEngine.assess(
            proposal, situation: situation { $0.taxReserveOwed = Money(minorUnits: 50_000) },
            formatter: formatter
        )
        #expect(assessment.verdict == .approvedWithConditions)
    }

    @Test func theArithmeticIsAlwaysShown() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 100_000)
        let assessment = AdvisorEngine.assess(proposal, situation: situation(),
                                              formatter: formatter)
        #expect(!assessment.arithmetic.isEmpty)
        #expect(assessment.arithmetic.contains { $0.label == "Runway after" })
    }

    @Test func theAdvisorNeverSaysYouCannotAffordIt() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 400_000)
        for situationCase in [situation(), situation { $0.highInterestDebtRemaining = Money(minorUnits: 1) }] {
            let assessment = AdvisorEngine.assess(proposal, situation: situationCase,
                                                  formatter: formatter)
            let text = assessment.summary + assessment.findings.map(\.detail).joined()
            #expect(!text.lowercased().contains("can't afford"))
            #expect(!text.lowercased().contains("cannot afford"))
            #expect(!text.contains("!"))
        }
    }

    @Test func assessmentIsDeterministic() {
        var proposal = AdvisorEngine.Proposal()
        proposal.amount = Money(minorUnits: 400_000)
        proposal.isDepreciatingAsset = true
        let context = situation { $0.highInterestDebtRemaining = Money(minorUnits: 200_000) }
        let first = AdvisorEngine.assess(proposal, situation: context, formatter: formatter)
        let second = AdvisorEngine.assess(proposal, situation: context, formatter: formatter)
        #expect(first.verdict == second.verdict)
        #expect(first.findings.map(\.ruleID) == second.findings.map(\.ruleID))
        #expect(first.summary == second.summary)
    }

    // MARK: - Cost in time

    @Test func costInTimeSpeaksInWeeksOfTheGoal() {
        let text = AdvisorEngine.costInTime(of: Money(minorUnits: 120_000), goalName: "the iPhone",
                                            weeklyRate: Money(minorUnits: 40_000),
                                            formatter: formatter)
        #expect(text == "₵1,200.00 = 3 weeks of the iPhone")
        #expect(AdvisorEngine.costInTime(of: Money(minorUnits: 120_000), goalName: "x",
                                         weeklyRate: .zero, formatter: formatter) == nil)
    }

    // MARK: - The monthly letter

    @Test func theLetterFollowsTheStructureAndTheVoice() {
        var input = AdvisorEngine.LetterInput()
        input.monthName = "September 2026"
        input.headlineLabel = "Savings rate"
        input.headlineValue = "20%"
        input.whatWentRight = ["Every envelope held."]
        input.whatToChange = ["Misc ran over three weeks running.", "Two loans still late.",
                              "A third thing that should not appear."]
        input.creepRatio = Decimal(string: "0.42")!
        input.creepIsRising = true
        input.creepDrivers = ["Rent", "Lunch"]
        input.instruction = "Reconcile the MoMo account on Sunday."
        input.overrideCount = 2
        input.overrideCost = Money(minorUnits: 40_000)

        let letter = AdvisorEngine.monthlyLetter(input, formatter: formatter)
        #expect(letter.contains("The number that matters"))
        #expect(letter.contains("Savings rate: 20%"))
        #expect(letter.contains("The creep check"))
        #expect(letter.contains("42% of net income"))
        #expect(letter.contains("Rent, Lunch"))
        #expect(letter.contains("One thing for next month"))
        // At most two things to change.
        #expect(!letter.contains("A third thing"))
        // Tone rules.
        #expect(!letter.contains("!"))
        #expect(!letter.lowercased().contains("you've got this"))
        #expect(!letter.lowercased().contains("well done"))
    }

    @Test func theLetterHandlesAMonthWithNoIncomeHistory() {
        var input = AdvisorEngine.LetterInput()
        input.monthName = "September 2026"
        input.headlineLabel = "Net worth"
        input.headlineValue = "₵0.00"
        input.instruction = "Log for seven days straight."
        let letter = AdvisorEngine.monthlyLetter(input, formatter: formatter)
        #expect(letter.contains("Not enough income history yet"))
        #expect(!letter.contains("Overrides"))
    }
}
