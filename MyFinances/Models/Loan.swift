import Foundation
import SwiftData

@Model
final class Loan {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var name: String = ""
    var lender: String = ""
    var directionRaw: String = LoanDirection.iOwe.rawValue

    var principalMinorUnits: Int = 0

    /// Interest model, decomposed for SwiftData. `interestModel` is the façade.
    var interestKindRaw: String = LoanInterestKind.interestFree.rawValue
    /// APR in basis points (1200 = 12.00%). Rates are never `Double`.
    var aprBasisPoints: Int?
    /// Flat rate in basis points, applied per year over `flatRateYears`.
    var flatRateBasisPoints: Int?
    var flatRateYears: Int?

    var startDate: Date = Date()
    var termMonths: Int = 12
    var paymentFrequencyRaw: String = PaymentFrequency.monthly.rawValue
    var scheduledPaymentMinorUnits: Int = 0

    var statusRaw: String = LoanStatus.active.rawValue
    /// 0–5. 5 = borrowed from family; it costs sleep, and the Peace-of-mind
    /// payoff order pays it first.
    var socialWeight: Int = 0
    var lateFeeMinorUnits: Int?
    var notes: String?

    /// The account a payment is drawn from (or paid into, for `.owedToMe`).
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \LoanPayment.loan)
    var payments: [LoanPayment]? = []

    init(
        name: String,
        lender: String,
        direction: LoanDirection,
        principal: Money,
        interestModel: InterestModel,
        startDate: Date,
        termMonths: Int,
        paymentFrequency: PaymentFrequency = .monthly,
        scheduledPayment: Money = .zero,
        status: LoanStatus = .active,
        socialWeight: Int = 0,
        lateFee: Money? = nil,
        account: Account? = nil,
        notes: String? = nil,
        now: Date = Date()
    ) {
        precondition((0...5).contains(socialWeight), "socialWeight is 0...5")
        precondition(termMonths > 0, "A loan needs a term")
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.name = name
        self.lender = lender
        self.directionRaw = direction.rawValue
        self.principalMinorUnits = principal.minorUnits
        self.startDate = startDate
        self.termMonths = termMonths
        self.paymentFrequencyRaw = paymentFrequency.rawValue
        self.scheduledPaymentMinorUnits = scheduledPayment.minorUnits
        self.statusRaw = status.rawValue
        self.socialWeight = socialWeight
        self.lateFeeMinorUnits = lateFee?.minorUnits
        self.account = account
        self.notes = notes
        self.interestModel = interestModel
    }

    // MARK: - Façades

    enum InterestModel: Equatable, Sendable {
        /// Interest on the reducing balance. `payment = P*r / (1 - (1+r)^-n)`.
        case amortizing(apr: Decimal)
        /// Interest on the original principal for the whole term. `total = P*(1 + rate*years)`.
        case flatRate(rate: Decimal, years: Int)
        case interestFree
        /// Revolving credit — interest accrues on whatever balance is outstanding.
        case revolving(apr: Decimal)

        /// Annual rate as a `Decimal` fraction (0.28 for 28%), zero when interest-free.
        var annualRate: Decimal {
            switch self {
            case let .amortizing(apr): apr
            case let .revolving(apr): apr
            case let .flatRate(rate, _): rate
            case .interestFree: 0
            }
        }
    }

    var interestModel: InterestModel {
        get {
            switch LoanInterestKind(rawValue: interestKindRaw) ?? .interestFree {
            case .amortizing: return .amortizing(apr: Loan.rate(aprBasisPoints))
            case .revolving: return .revolving(apr: Loan.rate(aprBasisPoints))
            case .flatRate: return .flatRate(rate: Loan.rate(flatRateBasisPoints), years: flatRateYears ?? 1)
            case .interestFree: return .interestFree
            }
        }
        set {
            switch newValue {
            case let .amortizing(apr):
                interestKindRaw = LoanInterestKind.amortizing.rawValue
                aprBasisPoints = Loan.basisPoints(apr); flatRateBasisPoints = nil; flatRateYears = nil
            case let .revolving(apr):
                interestKindRaw = LoanInterestKind.revolving.rawValue
                aprBasisPoints = Loan.basisPoints(apr); flatRateBasisPoints = nil; flatRateYears = nil
            case let .flatRate(rate, years):
                interestKindRaw = LoanInterestKind.flatRate.rawValue
                flatRateBasisPoints = Loan.basisPoints(rate); flatRateYears = years; aprBasisPoints = nil
            case .interestFree:
                interestKindRaw = LoanInterestKind.interestFree.rawValue
                aprBasisPoints = nil; flatRateBasisPoints = nil; flatRateYears = nil
            }
        }
    }

    static func rate(_ basisPoints: Int?) -> Decimal {
        Decimal(basisPoints ?? 0) / 10_000
    }

    static func basisPoints(_ rate: Decimal) -> Int {
        Money.roundBankers(rate * 10_000)
    }

    var direction: LoanDirection {
        get { LoanDirection(rawValue: directionRaw) ?? .iOwe }
        set { directionRaw = newValue.rawValue }
    }

    var status: LoanStatus {
        get { LoanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var paymentFrequency: PaymentFrequency {
        get { PaymentFrequency(rawValue: paymentFrequencyRaw) ?? .monthly }
        set { paymentFrequencyRaw = newValue.rawValue }
    }

    var principal: Money {
        get { Money(minorUnits: principalMinorUnits) }
        set { principalMinorUnits = newValue.minorUnits }
    }

    var scheduledPayment: Money {
        get { Money(minorUnits: scheduledPaymentMinorUnits) }
        set { scheduledPaymentMinorUnits = newValue.minorUnits }
    }

    var lateFee: Money? {
        get { lateFeeMinorUnits.map(Money.init(minorUnits:)) }
        set { lateFeeMinorUnits = newValue?.minorUnits }
    }

    /// Annual rate as a fraction, e.g. 0.28.
    var annualRate: Decimal { interestModel.annualRate }

    /// Total number of scheduled payments over the term.
    var scheduledPaymentCount: Int {
        Swift.max(1, termMonths * paymentFrequency.periodsPerYear / 12)
    }
}
