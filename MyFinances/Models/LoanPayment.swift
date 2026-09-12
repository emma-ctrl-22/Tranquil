import Foundation
import SwiftData

@Model
final class LoanPayment {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var loan: Loan?
    var date: Date = Date()
    var amountMinorUnits: Int = 0
    var principalPortionMinorUnits: Int = 0
    var interestPortionMinorUnits: Int = 0
    var feePortionMinorUnits: Int = 0
    var isLate: Bool = false
    /// The ledger row this payment posted, when it was posted as a transaction.
    var transactionID: UUID?
    /// The date this payment was scheduled for, so lateness is measurable.
    var scheduledDate: Date?

    init(
        loan: Loan?,
        date: Date,
        amount: Money,
        principalPortion: Money,
        interestPortion: Money,
        feePortion: Money = .zero,
        isLate: Bool = false,
        scheduledDate: Date? = nil,
        transactionID: UUID? = nil,
        now: Date = Date()
    ) {
        precondition(
            principalPortion + interestPortion + feePortion == amount,
            "A loan payment's portions must sum exactly to its amount"
        )
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.loan = loan
        self.date = date
        self.amountMinorUnits = amount.minorUnits
        self.principalPortionMinorUnits = principalPortion.minorUnits
        self.interestPortionMinorUnits = interestPortion.minorUnits
        self.feePortionMinorUnits = feePortion.minorUnits
        self.isLate = isLate
        self.scheduledDate = scheduledDate
        self.transactionID = transactionID
    }

    var amount: Money {
        get { Money(minorUnits: amountMinorUnits) }
        set { amountMinorUnits = newValue.minorUnits }
    }
    var principalPortion: Money {
        get { Money(minorUnits: principalPortionMinorUnits) }
        set { principalPortionMinorUnits = newValue.minorUnits }
    }
    var interestPortion: Money {
        get { Money(minorUnits: interestPortionMinorUnits) }
        set { interestPortionMinorUnits = newValue.minorUnits }
    }
    var feePortion: Money {
        get { Money(minorUnits: feePortionMinorUnits) }
        set { feePortionMinorUnits = newValue.minorUnits }
    }
}
