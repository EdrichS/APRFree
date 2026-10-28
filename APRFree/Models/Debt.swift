import Foundation

enum DebtKind: String, Codable, CaseIterable, Identifiable {
    case card, payLater, loan
    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: "Credit card"
        case .payLater: "Buy now, pay later"
        case .loan: "Loan"
        }
    }
}

enum LoanType: String, Codable, CaseIterable, Identifiable {
    case auto, student, personal, other
    var id: String { rawValue }

    var short: String {
        switch self {
        case .auto: "Auto"
        case .student: "Student"
        case .personal: "Personal"
        case .other: "Other"
        }
    }

    var title: String { self == .other ? "Loan" : "\(short) loan" }

    var symbol: String {
        switch self {
        case .auto: "car"
        case .student: "graduationcap"
        case .personal: "person"
        case .other: "banknote"
        }
    }
}

enum InstallmentEvery: String, Codable, CaseIterable, Identifiable {
    case weekly, biweekly, monthly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }

    func advance(_ date: Date, by steps: Int = 1) -> Date {
        switch self {
        case .weekly: Cal.addDays(7 * steps, to: date)
        case .biweekly: Cal.addDays(14 * steps, to: date)
        case .monthly: Cal.addMonths(steps, to: date)
        }
    }
}

struct Debt: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: DebtKind
    /// Bank, pay-later provider, or lender.
    var provider: String
    /// Card name, the purchase, or blank for loans.
    var name: String
    /// Key into `Brand.all`; decides the card colours and logo slot.
    var brand: String
    /// What is still owed.
    var balance: Double
    /// Regular APR in percent. For a promo card this is the rate after the promo.
    var apr: Double
    /// Day of the month a card or loan is due.
    var dueDay: Int = 1
    /// Card minimum, loan monthly payment, or pay-later installment.
    var minimum: Double

    // Credit card
    var creditLimit: Double?
    var promoAPR: Double?
    @AsOptionalDay var promoEnd: Date? = nil

    // Buy now, pay later
    var total: Double?
    var installments: Int?
    var paidInstallments: Int?
    var every: InstallmentEvery?
    @AsOptionalDay var nextDue: Date? = nil
    var paidFrom: String?
    var autopay: Bool?

    // Loan
    var loanType: LoanType?
    @AsOptionalDay var endDate: Date? = nil
    var originalAmount: Double?
    @AsOptionalDay var startDate: Date? = nil

    // Bookkeeping
    /// The day the debt was added.
    @AsDay var addedAt: Date
    /// Balance when the debt was added, plus later charges. Progress is measured against it.
    var startingBalance: Double
    /// Latest card or loan due date whose minimum was met.
    @AsOptionalDay var paidThrough: Date? = nil
    /// Paid so far toward the current due date. Cleared when the minimum is met.
    var paidTowardDue: Double?
    /// For loans: how much of that went to the cycle's interest.
    var interestTowardDue: Double?
    @AsOptionalDay var paidOffAt: Date? = nil
    /// The day of the latest statement check-in.
    @AsOptionalDay var statementThrough: Date? = nil
}

extension Debt {
    var isPaidOff: Bool { balance <= 0.005 }

    /// The name used in lists: "Chase", "Klarna", "Auto loan".
    var title: String {
        kind == .loan ? (loanType ?? .other).title : provider
    }

    /// Secondary line: card name, purchase, or lender.
    var detail: String {
        kind == .loan ? provider : name
    }

    func hasPromo(on date: Date) -> Bool {
        guard promoAPR != nil, let end = promoEnd else { return false }
        return date < end
    }

    func apr(on date: Date) -> Double {
        hasPromo(on: date) ? (promoAPR ?? apr) : apr
    }

    /// The amount progress is measured against.
    var startAmount: Double {
        switch kind {
        case .card: max(startingBalance, balance)
        case .payLater: total ?? startingBalance
        case .loan: originalAmount ?? startingBalance
        }
    }

    var available: Double? {
        creditLimit.map { max(0, $0 - balance) }
    }

    var utilization: Double? {
        guard let limit = creditLimit, limit > 0 else { return nil }
        return balance / limit
    }

    /// One day of interest: APR spread over 365 days.
    func dailyCost(on date: Date) -> Double {
        balance * apr(on: date) / 36500
    }

    /// One month of interest: APR spread over 12 months.
    func monthlyInterest(on date: Date) -> Double {
        balance * apr(on: date) / 1200
    }

    // MARK: Due dates, the way a bank runs them
    //
    // A due date stays put until its minimum is met. Partial payments shrink what is left of it.
    // Once it is met the next due date is the same day next month, and anything paid beyond the
    // minimum is extra: it lowers the balance but does not push the date again. Payments only start
    // counting toward that next due date nine days after the one before it, about when the next
    // statement posts.

    /// Days after a met due date before payments count toward the next one.
    static let dueLockDays = 9

    /// The first day a payment counts toward the current due date. Nil when it already does.
    /// Pay-later installments have no lock: paying the next one early is how those plans work.
    func dueOpens() -> Date? {
        guard kind != .payLater, let met = paidThrough else { return nil }
        return Cal.addDays(Debt.dueLockDays, to: met)
    }

    func countsTowardDue(on today: Date) -> Bool {
        dueOpens().map { Cal.startOfDay(today) >= $0 } ?? true
    }

    /// The balance before anything was paid toward the current due date.
    private var cycleStart: Double {
        balance + (paidTowardDue ?? 0) - (interestTowardDue ?? 0)
    }

    /// A loan's interest for the current cycle: one month on the balance the cycle started with.
    private func cycleInterest(on date: Date) -> Double {
        kind == .loan ? cycleStart * apr(on: date) / 1200 : 0
    }

    /// What the current due date asks for in full. A loan's last payment is the balance plus that
    /// month's interest; a pay-later plan's last installment clears whatever is left.
    func requiredPayment(on date: Date) -> Double {
        switch kind {
        case .card:
            return min(minimum, cycleStart).cents
        case .loan:
            return min(minimum, cycleStart + cycleInterest(on: date)).cents
        case .payLater:
            let left = (installments ?? 0) - (paidInstallments ?? 0)
            return (left <= 1 ? cycleStart : min(minimum, cycleStart)).cents
        }
    }

    /// What is still owed toward the current due date: the minimum, less anything already paid toward it.
    func scheduledPayment(on date: Date) -> Double {
        isPaidOff ? 0 : max(0, requiredPayment(on: date) - (paidTowardDue ?? 0)).cents
    }

    /// What one payment did.
    struct Payment {
        /// What was actually taken; never more than was owed.
        var amount = 0.0
        /// The part that was loan interest.
        var interest = 0.0
        var kind = PaymentRecord.Kind.extra
        /// The due date this payment settled, if it met the minimum.
        var metDue: Date?
    }

    /// Applies a payment by the rules above. `ignoringLock` is for a payment that is known to be a
    /// scheduled one: a line of a paycheck split marked paid, or a projection that assumes each
    /// scheduled payment is made in its own cycle.
    @discardableResult
    mutating func pay(_ requested: Double, on today: Date, ignoringLock: Bool = false) -> Payment {
        var out = Payment()
        guard requested > 0.004, !isPaidOff else { return out }
        let due = nextUnpaidDue()
        let remaining = scheduledPayment(on: today)
        let counts = remaining > 0.004 && (ignoringLock || countsTowardDue(on: today))
        var toward = counts ? min(requested, remaining) : 0
        // What goes toward a loan's due date pays the cycle's interest before any principal.
        let interest = kind == .loan && toward > 0
            ? min(toward, max(0, cycleInterest(on: today) - (interestTowardDue ?? 0))).cents : 0
        let amount = min(requested, balance + interest).cents
        toward = min(toward, amount)
        balance = max(0, balance - (amount - interest)).cents
        out.amount = amount
        out.interest = interest

        if toward > 0 {
            paidTowardDue = ((paidTowardDue ?? 0) + toward).cents
            if kind == .loan { interestTowardDue = ((interestTowardDue ?? 0) + interest).cents }
            if isPaidOff || scheduledPayment(on: today) <= 0.004 {
                out.metDue = due
                paidTowardDue = nil
                interestTowardDue = nil
                switch kind {
                case .card:
                    if let due { paidThrough = max(paidThrough ?? due, due) }
                    out.kind = amount > toward + 0.004 ? .payment : .minimum
                case .loan:
                    if let due { paidThrough = max(paidThrough ?? due, due) }
                    out.kind = .payment
                case .payLater:
                    paidInstallments = min((paidInstallments ?? 0) + 1, installments ?? Int.max)
                    if let next = nextDue, let step = every { nextDue = step.advance(next) }
                    out.kind = .installment
                }
            } else {
                out.kind = .partial
            }
        }
        if isPaidOff {
            balance = 0
            paidTowardDue = nil
            interestTowardDue = nil
        }
        return out
    }

    /// Puts a card or loan that was sitting at zero back on its normal cycle, so the next due
    /// date is the next one coming up rather than one from months ago.
    mutating func restartCycle(today: Date) {
        guard kind != .payLater else { return }
        let next = Cal.nextDue(day: dueDay, onOrAfter: today)
        paidThrough = Cal.date(inMonthOf: next, monthOffset: -1, day: dueDay)
        paidTowardDue = nil
        interestTowardDue = nil
    }

    /// Changes the day of the month a card or loan is due on and keeps it on the cycle it is on: the
    /// due date already met moves to the new day in its own month, so the next one is a month after.
    mutating func moveDueDay(to day: Int) {
        let day = min(max(1, day), 31)
        guard kind != .payLater, day != dueDay else { return }
        if let through = paidThrough { paidThrough = Cal.date(inMonthOf: through, monthOffset: 0, day: day) }
        dueDay = day
    }

    /// The next due date whose minimum has not been met. In the past when overdue.
    func nextUnpaidDue() -> Date? {
        guard !isPaidOff else { return nil }
        switch kind {
        case .payLater:
            return nextDue.map(Cal.startOfDay)
        case .card, .loan:
            let from = paidThrough.map { Cal.addDays(1, to: $0) } ?? Cal.startOfDay(addedAt)
            return Cal.nextDue(day: dueDay, onOrAfter: from)
        }
    }

    /// Dates of the pay-later installments still to come.
    var remainingInstallmentDates: [Date] {
        guard kind == .payLater, let first = nextDue, let step = every else { return [] }
        let left = max(0, (installments ?? 0) - (paidInstallments ?? 0))
        return (0..<left).map { step.advance(Cal.startOfDay(first), by: $0) }
    }

    /// Every pay-later installment date, paid ones included.
    var allInstallmentDates: [Date] {
        guard kind == .payLater, let first = nextDue, let step = every else { return [] }
        let paid = paidInstallments ?? 0
        return (0..<(installments ?? 0)).map { step.advance(Cal.startOfDay(first), by: $0 - paid) }
    }

    /// What a scheduled payment is called in a split or the activity list.
    var paymentWord: String {
        switch kind {
        case .card: "Minimum"
        case .payLater: "Installment"
        case .loan: "Payment"
        }
    }
}

/// The part of a debt that payments, charges and balance edits change.
struct DebtState: Codable, Hashable {
    var balance: Double
    var startingBalance: Double
    @AsOptionalDay var paidThrough: Date? = nil
    var paidTowardDue: Double?
    var interestTowardDue: Double?
    var paidInstallments: Int?
    @AsOptionalDay var nextDue: Date? = nil
    @AsOptionalDay var paidOffAt: Date? = nil
    @AsOptionalDay var statementThrough: Date? = nil
}

extension Debt {
    var state: DebtState {
        get {
            DebtState(balance: balance, startingBalance: startingBalance, paidThrough: paidThrough, paidTowardDue: paidTowardDue,
                      interestTowardDue: interestTowardDue, paidInstallments: paidInstallments, nextDue: nextDue, paidOffAt: paidOffAt,
                      statementThrough: statementThrough)
        }
        set {
            balance = newValue.balance
            startingBalance = newValue.startingBalance
            paidThrough = newValue.paidThrough
            paidTowardDue = newValue.paidTowardDue
            interestTowardDue = newValue.interestTowardDue
            paidInstallments = newValue.paidInstallments
            nextDue = newValue.nextDue
            paidOffAt = newValue.paidOffAt
            statementThrough = newValue.statementThrough
        }
    }

    /// Takes back an entry that has no saved "before" state (recorded by an older version):
    /// the amount comes off or goes back on, and a met due date steps back one cycle.
    mutating func reverse(_ record: PaymentRecord) {
        switch record.kind {
        case .added, .removed:
            return
        case .charge:
            balance = max(0, balance - record.amount).cents
            startingBalance = max(balance, startingBalance - record.amount).cents
        case .adjustment, .statement:
            balance = max(0, balance - record.amount).cents
        case .minimum, .installment, .payment, .partial, .extra:
            balance = (balance + record.amount - (record.interest ?? 0)).cents
            switch record.kind {
            case .installment:
                paidInstallments = max(0, (paidInstallments ?? 0) - 1)
                if let next = nextDue, let step = every { nextDue = step.advance(next, by: -1) }
            case .minimum, .payment:
                if kind != .payLater, let through = paidThrough {
                    paidThrough = Cal.date(inMonthOf: through, monthOffset: -1, day: dueDay)
                }
                paidTowardDue = nil
                interestTowardDue = nil
            case .partial:
                let left = max(0, (paidTowardDue ?? 0) - record.amount).cents
                paidTowardDue = left > 0 ? left : nil
                let interest = max(0, (interestTowardDue ?? 0) - (record.interest ?? 0)).cents
                interestTowardDue = interest > 0 ? interest : nil
            default:
                break
            }
        }
        if !isPaidOff { paidOffAt = nil }
    }

    /// Applies an entry again on top of the current state, as part of undoing an earlier one.
    /// Returns the entry as it now reads, or nil if it no longer does anything.
    mutating func reapply(_ record: PaymentRecord) -> PaymentRecord? {
        var r = record
        r.before = state
        switch record.kind {
        case .added, .removed:
            return record
        case .charge:
            if isPaidOff {
                paidOffAt = nil
                restartCycle(today: Cal.startOfDay(record.date))
            }
            balance = (balance + record.amount).cents
            startingBalance = (startingBalance + record.amount).cents
        case .adjustment, .statement:
            let wasPaidOff = isPaidOff
            let rise = (max(0, balance + record.amount) - balance).cents
            balance = max(0, balance + record.amount).cents
            if wasPaidOff && !isPaidOff { restartCycle(today: Cal.startOfDay(record.date)) }
            if kind == .card {
                // What a statement adds is new debt, like a charge, so it does not count against what
                // has been paid. A correction made by hand only ever raises the starting point to match.
                startingBalance = record.kind == .statement && rise > 0 ? (startingBalance + rise).cents : max(startingBalance, balance)
            }
            if record.kind == .statement { statementThrough = max(statementThrough ?? record.date, record.date) }
            // A bank update that moved the due day also moved the cycle onto it.
            if record.termsBefore != nil, kind != .payLater, let through = paidThrough {
                paidThrough = Cal.date(inMonthOf: through, monthOffset: 0, day: dueDay)
            }
            r.amount = (balance - (r.before?.balance ?? balance)).cents
        case .minimum, .installment, .payment, .partial, .extra:
            let result = pay(record.amount, on: Cal.startOfDay(record.date), ignoringLock: record.scheduled == true)
            guard result.amount > 0 else { return nil }
            r.amount = result.amount
            r.kind = result.kind
            r.interest = result.interest > 0 ? result.interest : nil
        }
        paidOffAt = isPaidOff ? (paidOffAt ?? Cal.startOfDay(record.date)) : nil
        r.balanceAfter = balance
        return r
    }
}

/// The terms of a debt that a bank can report and a bank update can change.
struct DebtTerms: Codable, Hashable {
    var apr: Double
    var minimum: Double
    var dueDay: Int
    var creditLimit: Double?
}

extension Debt {
    var terms: DebtTerms {
        get { DebtTerms(apr: apr, minimum: minimum, dueDay: dueDay, creditLimit: creditLimit) }
        set {
            apr = newValue.apr
            minimum = newValue.minimum
            dueDay = newValue.dueDay
            creditLimit = newValue.creditLimit
        }
    }
}

/// One line of history: a payment, a charge, or a change to a balance.
struct PaymentRecord: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        /// A card minimum, pay-later installment or loan payment that met its due date.
        case minimum, installment, payment
        /// Part of a minimum: the due date stays until the rest is paid.
        case partial
        /// Money beyond what was due.
        case extra
        case charge
        /// The balance was edited by hand. `amount` is signed.
        case adjustment
        /// A monthly statement check-in: the balance was set to what the statement says. `amount` is the
        /// signed difference, which is the interest and anything else the app had not seen.
        case statement
        /// The debt was added. `amount` is the balance it came in with.
        case added
        /// The debt was deleted. `amount` is the balance it left with.
        case removed
    }

    var id = UUID()
    var debtID: UUID
    var title: String
    /// The day it happened.
    @AsDay var date: Date
    var amount: Double
    var kind: Kind
    /// For loan payments: the part that was interest. For a statement: the interest it reported, if entered.
    var interest: Double?
    /// The debt's balance right after this entry.
    var balanceAfter: Double?
    /// The debt as it stood just before this entry. Undo puts it back.
    var before: DebtState?
    /// What kind of debt this was, kept so history still adds up after the debt is deleted.
    var debtKind: DebtKind?
    /// For a "deleted" entry: the debt as it was, so the deletion can be undone.
    var removed: Debt?
    /// True for a payment marked paid as a scheduled line of a paycheck split. It counts toward its
    /// due date even inside the nine-day wait, and keeps doing so when entries are applied again.
    var scheduled: Bool?
    /// The bank an entry came from, for one that arrived through Connected mode.
    var bank: String?
    /// What else the entry changed besides the balance, in words: "APR 24.99% to 26.24%".
    var note: String?
    /// The debt's terms just before a bank update changed them, so undoing the entry puts them back.
    var termsBefore: DebtTerms?

    /// True for money paid toward the debt, as opposed to charges and bookkeeping entries.
    var isPayment: Bool {
        switch kind {
        case .minimum, .installment, .payment, .partial, .extra: true
        case .charge, .adjustment, .statement, .added, .removed: false
        }
    }

    /// Entries whose amount can go either way, so it is shown with its sign.
    var isSigned: Bool { kind == .adjustment || kind == .statement }

    /// Entries that can be changed afterwards: the amount or the day of a payment or a charge, and
    /// the balance or the day of a balance change or a statement check-in.
    var isEditable: Bool {
        switch kind {
        case .minimum, .installment, .payment, .partial, .extra, .charge, .adjustment, .statement: true
        case .added, .removed: false
        }
    }

    /// What happened, without the debt's name: "Minimum paid".
    var action: String {
        switch kind {
        case .minimum: "Minimum paid"
        case .installment: "Installment paid"
        case .payment: "Payment"
        case .partial: "Partial payment"
        case .extra: "Extra payment"
        case .charge: "Charge added"
        case .adjustment: "Balance updated"
        case .statement: bank == nil ? "Statement check-in" : "Bank update"
        case .added: "Added"
        case .removed: "Deleted"
        }
    }

    var label: String {
        switch kind {
        case .minimum: "\(title) minimum paid"
        case .installment: "\(title) installment paid"
        case .payment: "\(title) payment"
        case .partial: "\(title) partial payment"
        case .extra: "\(title) extra payment"
        case .charge: "\(title) charge added"
        case .adjustment: "\(title) balance updated"
        case .statement: bank == nil ? "\(title) statement check-in" : "\(title) bank update"
        case .added: "\(title) added"
        case .removed: "\(title) deleted"
        }
    }

    /// The amount as it moved the balance: payments down, charges up.
    var signedAmount: String {
        switch kind {
        case .charge: "+\(amount.usd)"
        case .adjustment, .statement: amount >= 0 ? "+\(amount.usd)" : "−\((-amount).usd)"
        case .added, .removed: amount.usd
        default: "−\(amount.usd)"
        }
    }
}

/// The balances on one day. Card and loan totals are optional because older saved data only has the total.
struct BalancePoint: Codable, Hashable {
    @AsDay var date: Date
    var total: Double
    var cards: Double?
    var loans: Double?

    func value(_ scope: DebtScope) -> Double? {
        switch scope {
        case .total: total
        case .cards: cards
        case .loans: loans
        }
    }
}

extension DebtScope {
    func includes(_ debt: Debt) -> Bool {
        switch self {
        case .total: true
        case .cards: debt.kind == .card
        case .loans: debt.kind == .loan
        }
    }
}
