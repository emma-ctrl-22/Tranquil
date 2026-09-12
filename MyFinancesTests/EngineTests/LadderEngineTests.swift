import Testing
import Foundation
@testable import MyFinances

struct LadderEngineTests {

    /// A snapshot that clears every stage, which individual tests then break one at a time.
    private func perfect() -> LadderEngine.Snapshot {
        LadderEngine.Snapshot(
            liquidAvailable: Money(minorUnits: 3_000_000),      // ₵30,000
            essentialMonthlySpend: Money(minorUnits: 300_000),  // ₵3,000 → 10 months runway
            daysLoggedLast28: 27,
            daysSinceReconciliation: 2,
            overdueLoanCount: 0,
            daysSinceLastLatePayment: nil,
            billsDueNext30Days: Money(minorUnits: 100_000),
            projectedLowNext30Days: Money(minorUnits: 50_000),
            toxicDebtRemaining: .zero,
            emergencyFundBalance: Money(minorUnits: 1_800_000),  // 6 months
            daysSinceEmergencyFundWithdrawal: nil,
            sinkingFundsOnTrack: 4,
            sinkingFundsTotal: 4,
            debtServiceRatio: Decimal(string: "0.05")!,
            highestRemainingAPR: Decimal(string: "0.08")!,
            investmentMonthsLast12: 12,
            investmentMonthsLast6: 6,
            monthsAllStagesHeld: 8,
            onTimePaymentsRatio: 1,
            budgetAdherenceRatio: 1,
            emergencyFundTargetMonths: 6
        )
    }

    private func modified(_ change: (inout LadderEngine.Snapshot) -> Void)
    -> LadderEngine.Snapshot {
        var snapshot = perfect()
        change(&snapshot)
        return snapshot
    }

    // MARK: - Stage 0

    @Test func visibilityNeedsBothLoggingAndReconciliation() {
        #expect(LadderEngine.isMet(.visibility, snapshot: perfect()))
        // 20 of 28 is one short of the bar.
        #expect(!LadderEngine.isMet(.visibility, snapshot: modified { $0.daysLoggedLast28 = 20 }))
        #expect(LadderEngine.isMet(.visibility, snapshot: modified { $0.daysLoggedLast28 = 21 }))
        // Reconciled eight days ago is outside the seven-day window.
        #expect(!LadderEngine.isMet(.visibility,
                                    snapshot: modified { $0.daysSinceReconciliation = 8 }))
        // Never reconciled does not pass.
        #expect(!LadderEngine.isMet(.visibility,
                                    snapshot: modified { $0.daysSinceReconciliation = nil }))
    }

    // MARK: - Stage 1

    @Test func theBufferIsTwoWeeksOfEssentials() {
        // ₵3,000 a month → two weeks is ₵1,500.
        let snapshot = perfect()
        #expect(LadderEngine.twoWeeksOfEssentials(snapshot).minorUnits == 150_000)
        #expect(LadderEngine.isMet(.twoWeekBuffer,
                                   snapshot: modified { $0.liquidAvailable = Money(minorUnits: 150_000) }))
        #expect(!LadderEngine.isMet(.twoWeekBuffer,
                                    snapshot: modified { $0.liquidAvailable = Money(minorUnits: 149_999) }))
    }

    @Test func withNoSpendHistoryTheBufferCannotBeClaimed() {
        // Unknown, not passed. Claiming a buffer against zero known essentials would
        // let stage 1 pass for someone who has logged nothing.
        let snapshot = modified { $0.essentialMonthlySpend = .zero }
        #expect(!LadderEngine.isMet(.twoWeekBuffer, snapshot: snapshot))
        #expect(LadderEngine.runwayMonths(snapshot) == nil)
    }

    // MARK: - Stage 2

    @Test func nothingLateNeedsCleanHistoryAndCoveredBills() {
        #expect(LadderEngine.isMet(.nothingLate, snapshot: perfect()))
        #expect(!LadderEngine.isMet(.nothingLate, snapshot: modified { $0.overdueLoanCount = 1 }))
        // A late payment 59 days ago is inside the 60-day window.
        #expect(!LadderEngine.isMet(.nothingLate,
                                    snapshot: modified { $0.daysSinceLastLatePayment = 59 }))
        #expect(LadderEngine.isMet(.nothingLate,
                                   snapshot: modified { $0.daysSinceLastLatePayment = 60 }))
        // Bills not covered by the projection.
        #expect(!LadderEngine.isMet(.nothingLate, snapshot: modified {
            $0.projectedLowNext30Days = Money(minorUnits: -1)
        }))
    }

    // MARK: - Stages 3 to 6

    @Test func toxicDebtMustBeExactlyZero() {
        #expect(LadderEngine.isMet(.toxicDebtGone, snapshot: perfect()))
        #expect(!LadderEngine.isMet(.toxicDebtGone, snapshot: modified {
            $0.toxicDebtRemaining = Money(minorUnits: 1)
        }))
    }

    @Test func theEmergencyFundMustBeBigEnoughAndUntouched() {
        #expect(LadderEngine.isMet(.emergencyFund, snapshot: perfect()))
        // Six months of ₵3,000 is ₵18,000; a pesewa under does not pass.
        #expect(!LadderEngine.isMet(.emergencyFund, snapshot: modified {
            $0.emergencyFundBalance = Money(minorUnits: 1_799_999)
        }))
        // Raided 89 days ago — the 90-day clock has not run out.
        #expect(!LadderEngine.isMet(.emergencyFund, snapshot: modified {
            $0.daysSinceEmergencyFundWithdrawal = 89
        }))
        #expect(LadderEngine.isMet(.emergencyFund, snapshot: modified {
            $0.daysSinceEmergencyFundWithdrawal = 90
        }))
    }

    @Test func aSalariedTargetOfThreeMonthsIsLowerThanFreelanceSix() {
        let threeMonths = modified {
            $0.emergencyFundTargetMonths = 3
            $0.emergencyFundBalance = Money(minorUnits: 900_000)
        }
        #expect(LadderEngine.isMet(.emergencyFund, snapshot: threeMonths))
        let sixMonths = modified {
            $0.emergencyFundTargetMonths = 6
            $0.emergencyFundBalance = Money(minorUnits: 900_000)
        }
        #expect(!LadderEngine.isMet(.emergencyFund, snapshot: sixMonths))
    }

    @Test func everySinkingFundMustBeOnTrackNotMost() {
        #expect(LadderEngine.isMet(.sinkingFundsCurrent, snapshot: perfect()))
        #expect(!LadderEngine.isMet(.sinkingFundsCurrent,
                                    snapshot: modified { $0.sinkingFundsOnTrack = 3 }))
        // With no funds at all the stage is not claimable.
        #expect(!LadderEngine.isMet(.sinkingFundsCurrent, snapshot: modified {
            $0.sinkingFundsOnTrack = 0
            $0.sinkingFundsTotal = 0
        }))
    }

    @Test func debtSmallAndCheapUsesBothThresholds() {
        #expect(LadderEngine.isMet(.debtSmallAndCheap, snapshot: perfect()))
        #expect(!LadderEngine.isMet(.debtSmallAndCheap, snapshot: modified {
            $0.debtServiceRatio = Decimal(string: "0.21")!
        }))
        #expect(LadderEngine.isMet(.debtSmallAndCheap, snapshot: modified {
            $0.debtServiceRatio = Decimal(string: "0.20")!
        }))
        #expect(!LadderEngine.isMet(.debtSmallAndCheap, snapshot: modified {
            $0.highestRemainingAPR = Decimal(string: "0.16")!
        }))
    }

    // MARK: - Stage 7

    @Test func tranquilityIsSixMonthsOfEverythingElseHolding() {
        #expect(LadderEngine.isMet(.tranquil, snapshot: perfect()))
        // Five months is not six.
        #expect(!LadderEngine.isMet(.tranquil, snapshot: modified { $0.monthsAllStagesHeld = 5 }))
        // Invested in only four of the last six.
        #expect(!LadderEngine.isMet(.tranquil, snapshot: modified { $0.investmentMonthsLast6 = 4 }))
        // One lower stage broken takes it away, however long it has held.
        #expect(!LadderEngine.isMet(.tranquil, snapshot: modified { $0.overdueLoanCount = 1 }))
    }

    // MARK: - Current stage

    @Test func theCurrentStageIsTheLowestUnmetOne() {
        let evaluation = LadderEngine.evaluate(modified { $0.toxicDebtRemaining = Money(minorUnits: 50_000) })
        #expect(evaluation.currentStage == .toxicDebtGone)
        #expect(evaluation.clearedStages.count == 3)
    }

    @Test func aPerfectSnapshotSitsAtTranquil() {
        #expect(LadderEngine.evaluate(perfect()).currentStage == .tranquil)
    }

    @Test func someoneWhoHasLoggedNothingStartsAtStageZero() {
        let beginner = LadderEngine.Snapshot(
            liquidAvailable: .zero, essentialMonthlySpend: .zero, daysLoggedLast28: 0,
            daysSinceReconciliation: nil, overdueLoanCount: 0, daysSinceLastLatePayment: nil,
            billsDueNext30Days: .zero, projectedLowNext30Days: .zero,
            toxicDebtRemaining: .zero, emergencyFundBalance: .zero,
            daysSinceEmergencyFundWithdrawal: nil, sinkingFundsOnTrack: 0,
            sinkingFundsTotal: 0, debtServiceRatio: 0, highestRemainingAPR: 0,
            investmentMonthsLast12: 0, investmentMonthsLast6: 0, monthsAllStagesHeld: 0,
            onTimePaymentsRatio: 0, budgetAdherenceRatio: 0, emergencyFundTargetMonths: 6
        )
        let evaluation = LadderEngine.evaluate(beginner)
        #expect(evaluation.currentStage == .visibility)
        #expect(evaluation.clearedStages.isEmpty)
        #expect(evaluation.runwayMonths == nil)
        // An empty database must not crash or claim progress.
        #expect(evaluation.stabilityScore.total >= 0)
    }

    @Test func fallingBackIsReportedWithoutShameLanguage() {
        let evaluation = LadderEngine.evaluate(modified {
            $0.liquidAvailable = Money(minorUnits: 10_000)
        })
        #expect(evaluation.currentStage == .twoWeekBuffer)
        let words = ["fail", "should have", "bad", "lazy", "!"]
        for stage in evaluation.stages {
            for word in words {
                #expect(!stage.evidence.lowercased().contains(word), "\(stage.evidence)")
            }
        }
        #expect(!evaluation.nextAction.detail.contains("!"))
    }

    // MARK: - Runway

    @Test func runwayIsLiquidOverEssentialMonthlySpend() {
        // ₵30,000 available against ₵3,000 a month is ten months.
        #expect(LadderEngine.runwayMonths(perfect()) == 10)
        let lean = modified { $0.liquidAvailable = Money(minorUnits: 450_000) }
        #expect(LadderEngine.runwayMonths(lean) == Decimal(string: "1.5"))
    }

    // MARK: - Stability score

    @Test func theScoreWeightsMatchTheSpec() {
        let score = LadderEngine.score(perfect())
        let expected: [(String, Int)] = [
            ("Runway", 30), ("Debt service", 20), ("Paid on time", 15), ("Logging", 10),
            ("Sinking funds", 10), ("Budget adherence", 10), ("Investing", 5),
        ]
        #expect(score.components.map { ($0.name, $0.available) }.elementsEqual(expected) { $0 == $1 })
        #expect(score.available == 100)
    }

    @Test func aStrongSnapshotScoresNearTheTop() {
        let score = LadderEngine.score(perfect())
        #expect(score.total > 90)
        #expect(score.total <= 100)
    }

    @Test func anEmptySnapshotScoresZeroWithoutCrashing() {
        let empty = LadderEngine.Snapshot(
            liquidAvailable: .zero, essentialMonthlySpend: .zero, daysLoggedLast28: 0,
            daysSinceReconciliation: nil, overdueLoanCount: 0, daysSinceLastLatePayment: nil,
            billsDueNext30Days: .zero, projectedLowNext30Days: .zero, toxicDebtRemaining: .zero,
            emergencyFundBalance: .zero, daysSinceEmergencyFundWithdrawal: nil,
            sinkingFundsOnTrack: 0, sinkingFundsTotal: 0, debtServiceRatio: 0,
            highestRemainingAPR: 0, investmentMonthsLast12: 0, investmentMonthsLast6: 0,
            monthsAllStagesHeld: 0, onTimePaymentsRatio: 0, budgetAdherenceRatio: 0,
            emergencyFundTargetMonths: 6
        )
        let score = LadderEngine.score(empty)
        // Debt service scores full marks at zero debt, which is correct.
        #expect(score.components.first { $0.name == "Debt service" }?.earned == 20)
        #expect(score.components.first { $0.name == "Runway" }?.earned == 0)
        #expect(score.total == 20)
    }

    @Test func theScoreAlwaysBreaksDownIntoItsParts() {
        // It must never be a mystery number.
        let score = LadderEngine.score(perfect())
        #expect(score.total == score.components.reduce(0) { $0 + $1.earned })
        for component in score.components {
            #expect(!component.detail.isEmpty)
            #expect(component.earned <= component.available)
            #expect(component.earned >= 0)
        }
    }

    @Test func heavyDebtServiceCostsPointsProportionally() {
        let none = LadderEngine.score(modified { $0.debtServiceRatio = 0 })
        let heavy = LadderEngine.score(modified { $0.debtServiceRatio = Decimal(string: "0.20")! })
        let crushing = LadderEngine.score(modified {
            $0.debtServiceRatio = Decimal(string: "0.45")!
        })
        #expect(none.components.first { $0.name == "Debt service" }?.earned == 20)
        #expect(heavy.components.first { $0.name == "Debt service" }?.earned == 10)
        // Beyond 40% it floors at zero rather than going negative.
        #expect(crushing.components.first { $0.name == "Debt service" }?.earned == 0)
    }

    @Test func investingScoresConsistencyNotAmount() {
        // Consistency beats size: this reads months contributed, never how much.
        let steady = LadderEngine.score(modified { $0.investmentMonthsLast12 = 12 })
        let sporadic = LadderEngine.score(modified { $0.investmentMonthsLast12 = 3 })
        #expect(steady.components.first { $0.name == "Investing" }?.earned == 5)
        #expect(sporadic.components.first { $0.name == "Investing" }?.earned == 1)
    }

    // MARK: - Next action

    @Test func exactlyOneActionIsOfferedAtATime() {
        for stage in LadderStage.allCases {
            let action = LadderEngine.action(for: stage, snapshot: perfect())
            #expect(!action.title.isEmpty)
            #expect(!action.detail.isEmpty)
            // One action, not a list.
            #expect(!action.title.contains(","))
        }
    }

    @Test func theActionAtStageZeroDependsOnWhatIsActuallyMissing() {
        let unlogged = LadderEngine.action(for: .visibility,
                                           snapshot: modified { $0.daysLoggedLast28 = 5 })
        #expect(unlogged.screen == .ledger)
        let unreconciled = LadderEngine.action(for: .visibility,
                                               snapshot: modified { $0.daysSinceReconciliation = 30 })
        #expect(unreconciled.screen == .accounts)
    }

    @Test func theActionPointsAtTheRightScreen() {
        #expect(LadderEngine.action(for: .toxicDebtGone, snapshot: perfect()).screen == .debt)
        #expect(LadderEngine.action(for: .emergencyFund, snapshot: perfect()).screen == .goals)
        #expect(LadderEngine.action(for: .sinkingFundsCurrent, snapshot: perfect()).screen == .plan)
    }
}
