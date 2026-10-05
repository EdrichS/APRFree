import Foundation

struct PlanInput {
    var debts: [Debt]
    var today: Date
    var firstPayday: Date
    var frequency: PayFrequency
    /// Money toward debt each payday, with the safety buffer already taken out.
    var perPayday: Double
    var strategy: Strategy
    var customOrder: [UUID]
    var promoMinimumOnly: Bool
    /// Added to the first payday only.
    var oneTime: Double = 0
    /// Added to the first payday of every month.
    var extraMonthly: Double = 0
    /// For monthly pay: the day of the month, when the first payday was shortened to fit its month.
    var anchorDay: Int? = nil
}

/// Balances on one date of a plan: everything, the cards alone, the loans alone.
struct PlanPoint: Identifiable, Hashable {
    var date: Date
    var total: Double
    var cards: Double = 0
    var loans: Double = 0
    var id: Date { date }

    func value(_ scope: DebtScope) -> Double {
        switch scope {
        case .total: total
        case .cards: cards
        case .loans: loans
        }
    }
}

/// One month of payments to a single debt, split into interest and principal.
struct MonthSlice: Identifiable, Hashable {
    var month: Date
    var interest: Double
    var principal: Double
    var id: Date { month }
    var total: Double { interest + principal }
}

struct PlanResult {
    /// False when the payments never clear the debt.
    var finished = false
    var finalPayday: Date?
    /// The due date the very last payment covers. Its month is the debt-free month.
    var debtFree: Date?
    var totalInterest: Double = 0
    /// Per debt: the due date its final payment covers.
    var payoff: [UUID: Date] = [:]
    var payoffPayday: [UUID: Date] = [:]
    /// Per debt: how many paydays until it is gone.
    var paydaysToPayoff: [UUID: Int] = [:]
    /// Balances after each payday, starting with today.
    var series: [PlanPoint] = []
    fileprivate(set) var ledger: [UUID: [Date: MonthSlice]] = [:]
    fileprivate(set) var accruals: [UUID: [Date: Double]] = [:]

    /// The interest a debt is charged in each month of this plan, from now until it is paid off.
    func interestByMonth(for id: UUID) -> [PlanPoint] {
        (accruals[id] ?? [:]).map { PlanPoint(date: $0.key, total: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Month-by-month payments to one debt under this plan.
    func slices(for id: UUID) -> [MonthSlice] {
        (ledger[id] ?? [:]).values.sorted { $0.month < $1.month }
    }

    /// The month a group of debts is cleared: the latest of their payoff dates. Nil if any never clears.
    func free(_ debts: [Debt]) -> Date? {
        let live = debts.filter { !$0.isPaidOff }
        let dates = live.compactMap { payoff[$0.id] }
        return dates.count == live.count ? dates.max() : nil
    }
}

extension Array where Element == PlanPoint {
    /// The balance on any date: a straight line between the paydays either side of it.
    func balance(at date: Date, _ scope: DebtScope = .total) -> Double {
        guard let first, let last else { return 0 }
        if date <= first.date { return first.value(scope) }
        if date >= last.date { return last.value(scope) }
        for (a, b) in zip(self, dropFirst()) where date >= a.date && date <= b.date {
            let span = b.date.timeIntervalSince(a.date)
            guard span > 0 else { return b.value(scope) }
            return a.value(scope) + (b.value(scope) - a.value(scope)) * date.timeIntervalSince(a.date) / span
        }
        return last.value(scope)
    }
}

struct SplitLine: Identifiable, Hashable {
    var id = UUID()
    var debtID: UUID
    var title: String
    var detail: String
    var amount: Double
    var isExtra: Bool
    var dueDate: Date?
}

struct Split {
    var payday: Date
    var nextPayday: Date
    var amount: Double
    var bufferKept: Double
    var lines: [SplitLine] = []
    /// How far the amount falls short of the minimums due.
    var shortBy: Double = 0
    var summary: String?

    var total: Double { lines.reduce(0) { $0 + $1.amount }.cents }
}

/// The payoff math.
///
/// Interest is APR / 365 a day. Cards compound it into the balance daily; loans charge it on
/// the principal and take it out of the next payment, the way an amortizing loan does. Money
/// goes out on paydays: every scheduled payment due before the next payday, then the rest as
/// extra in strategy order.
enum PayoffEngine {

    // MARK: Order

    /// Debts in the order a strategy sends extra money to them.
    static func priority(_ debts: [Debt], strategy: Strategy, customOrder: [UUID], on date: Date) -> [Debt] {
        switch strategy {
        case .avalanche:
            // By rate. A dollar of extra payment saves interest at the rate of the debt it lands on,
            // whatever that debt's size, so the highest rate first costs the least overall.
            return debts.sorted { a, b in
                let x = a.apr(on: date), y = b.apr(on: date)
                return x != y ? x > y : a.balance < b.balance
            }
        case .highestBalance:
            // By the interest each debt charges in a month (balance x APR / 12): a large balance at 20%
            // comes ahead of a small one at 30%. It clears the biggest charges first but costs more overall.
            return debts.sorted { a, b in
                let x = a.monthlyInterest(on: date), y = b.monthlyInterest(on: date)
                if x != y { return x > y }
                let p = a.apr(on: date), q = b.apr(on: date)
                return p != q ? p > q : a.balance < b.balance
            }
        case .snowball:
            return debts.sorted { a, b in
                a.balance != b.balance ? a.balance < b.balance : a.apr(on: date) > b.apr(on: date)
            }
        case .custom:
            var rank: [UUID: Int] = [:]
            for (i, id) in customOrder.enumerated() where rank[id] == nil { rank[id] = i }
            return debts.sorted { a, b in
                let x = rank[a.id] ?? Int.max, y = rank[b.id] ?? Int.max
                return x != y ? x < y : a.apr(on: date) > b.apr(on: date)
            }
        }
    }

    /// Where extra money goes: the strategy order first, then held promo cards, then pay-later plans.
    static func extraQueue(_ debts: [Debt], strategy: Strategy, customOrder: [UUID], promoMinimumOnly: Bool,
                           on date: Date) -> [Debt] {
        let live = debts.filter { !$0.isPaidOff }
        let payLater = live.filter { $0.kind == .payLater }
        let rest = live.filter { $0.kind != .payLater }
        let held = promoMinimumOnly ? rest.filter { $0.hasPromo(on: date) } : []
        let main = rest.filter { d in !held.contains { $0.id == d.id } }
        return priority(main, strategy: strategy, customOrder: customOrder, on: date) + held + payLater
    }

    // MARK: Simulation

    private struct Work {
        /// `debt.balance` is the running balance: principal for a loan, everything for a card.
        var debt: Debt
        /// Loan interest charged but not yet paid.
        var accrued = 0.0
        var due: Date?
        var installments: [Date]
        /// What is left of the first due date when part of it has already been paid.
        var firstDueLeft: Double?

        var owed: Double { debt.balance + accrued }

        init(_ debt: Debt, today: Date) {
            self.debt = debt
            installments = debt.remainingInstallmentDates
            due = debt.kind == .payLater ? nil : debt.nextUnpaidDue()
            if debt.kind == .loan, let due {
                // The stored loan balance is principal as of the last payment, so the interest
                // that has built up since then is owed on top of it.
                let last = debt.paidThrough ?? Cal.date(inMonthOf: due, monthOffset: -1, day: debt.dueDay)
                let days = min(max(0, Cal.days(from: last, to: today)), 366)
                accrued = max(0, debt.balance * debt.apr(on: today) / 36500 * Double(days) - (debt.interestTowardDue ?? 0))
            }
            if (debt.paidTowardDue ?? 0) > 0 { firstDueLeft = debt.scheduledPayment(on: today) }
        }

        /// The size of the next scheduled payment: the minimum, or what is left of a partly paid one.
        private mutating func nextAmount() -> Double {
            defer { firstDueLeft = nil }
            return firstDueLeft ?? debt.minimum
        }

        /// What is due before `limit`, removed from the schedule.
        mutating func takeDues(before limit: Date) -> Double {
            if debt.kind == .payLater {
                var sum = 0.0
                while let first = installments.first, first < limit {
                    sum += nextAmount()
                    installments.removeFirst()
                }
                guard sum > 0 else { return 0 }
                // The last installment clears whatever is left, odd cents included.
                return installments.isEmpty ? owed : min(sum, owed)
            }
            var sum = 0.0
            while let d = due, d < limit {
                sum += nextAmount()
                due = Cal.nextDue(day: debt.dueDay, onOrAfter: Cal.addDays(1, to: d))
            }
            return min(sum, owed)
        }

        /// Interest first, then principal.
        mutating func pay(_ amount: Double) {
            let interest = min(amount, accrued)
            accrued -= interest
            debt.balance -= amount - interest
        }

        /// The due date a final payment made on `payday` covers.
        func coveredDue(payday: Date) -> Date {
            if debt.kind == .payLater { return max(payday, debt.remainingInstallmentDates.last ?? payday) }
            return Cal.nextDue(day: debt.dueDay, onOrAfter: payday)
        }
    }

    static func simulate(_ input: PlanInput) -> PlanResult {
        var result = PlanResult()
        var work = input.debts.filter { !$0.isPaidOff }.map { Work($0, today: input.today) }
        func owed() -> Double { work.reduce(0) { $0 + $1.owed } }
        func point(_ date: Date) -> PlanPoint {
            var p = PlanPoint(date: date, total: 0)
            for w in work {
                p.total += w.debt.balance
                if w.debt.kind == .card { p.cards += w.debt.balance }
                if w.debt.kind == .loan { p.loans += w.debt.balance }
            }
            return p
        }

        result.series = [point(input.today)]
        guard !work.isEmpty else {
            result.finished = true
            return result
        }
        // With no money going in, nothing is ever paid: there is no plan to work out.
        guard input.perPayday + input.oneTime + input.extraMonthly > 0.005 else { return result }
        let paydays = PaydaySequence(first: input.firstPayday, frequency: input.frequency, anchorDay: input.anchorDay)
            .starting(onOrAfter: input.today)
        var day = input.today
        var index = 0
        // A plan that works shrinks what is owed every payday. If a whole stretch of paydays goes by
        // without a new low, the payments are not keeping up with the interest and never will.
        var lowest = owed()
        var paydaysSinceLow = 0

        func record(_ i: Int, month: Date, paid: Double = 0, interest: Double = 0) {
            let id = work[i].debt.id
            var slice = result.ledger[id]?[month] ?? MonthSlice(month: month, interest: 0, principal: 0)
            // `principal` holds everything paid until the slices are finalized below.
            slice.principal += paid
            slice.interest += interest
            result.ledger[id, default: [:]][month] = slice
        }

        while owed() > 0.005 && index < 720 {
            let payday = paydays.date(index)
            let next = paydays.date(index + 1)

            while day < payday {
                let month = Cal.monthStart(day)
                for i in work.indices where work[i].debt.balance > 0 {
                    let rate = work[i].debt.apr(on: day)
                    guard rate > 0 else { continue }
                    let interest = work[i].debt.balance * rate / 36500
                    if work[i].debt.kind == .loan {
                        work[i].accrued += interest
                    } else {
                        work[i].debt.balance += interest
                    }
                    result.totalInterest += interest
                    result.accruals[work[i].debt.id, default: [:]][month, default: 0] += interest
                    record(i, month: month, interest: interest)
                }
                day = Cal.addDays(1, to: day)
            }

            var pot = input.perPayday
            if index == 0 { pot += input.oneTime }
            if input.extraMonthly > 0 && paydays.isFirstInMonth(index) { pot += input.extraMonthly }
            let month = Cal.monthStart(payday)

            for i in work.indices where work[i].owed > 0.005 {
                let pay = min(work[i].takeDues(before: next), work[i].owed, pot)
                guard pay > 0 else { continue }
                work[i].pay(pay)
                pot -= pay
                record(i, month: month, paid: pay)
            }

            let queue = extraQueue(work.map(\.debt), strategy: input.strategy, customOrder: input.customOrder,
                                   promoMinimumOnly: input.promoMinimumOnly, on: payday)
            for target in queue {
                guard pot > 0.005, let i = work.firstIndex(where: { $0.debt.id == target.id }) else { continue }
                let pay = min(pot, work[i].owed)
                work[i].pay(pay)
                pot -= pay
                record(i, month: month, paid: pay)
            }

            for i in work.indices where work[i].owed <= 0.005 && result.payoffPayday[work[i].debt.id] == nil {
                let id = work[i].debt.id
                work[i].debt.balance = 0
                work[i].accrued = 0
                result.payoffPayday[id] = payday
                result.payoff[id] = max(payday, work[i].coveredDue(payday: payday))
                result.paydaysToPayoff[id] = index + 1
            }

            result.series.append(point(payday))
            index += 1

            let now = owed()
            if now < lowest - 0.005 {
                lowest = now
                paydaysSinceLow = 0
            } else {
                paydaysSinceLow += 1
                if paydaysSinceLow >= 26 { break }
            }
        }

        // Turn "everything paid" into principal by taking the month's interest out of it.
        for (id, months) in result.ledger {
            for (month, slice) in months {
                let interest = min(slice.interest, slice.principal)
                result.ledger[id]?[month] = MonthSlice(month: month, interest: interest, principal: slice.principal - interest)
            }
        }

        if owed() <= 0.005 {
            result.finished = true
            result.finalPayday = result.payoffPayday.values.max()
            result.debtFree = result.payoff.values.max()
        }
        return result
    }

    // MARK: Make a Payment

    /// Splits a payday amount: every scheduled payment due before the next payday, then the rest as extra.
    static func split(amount: Double, debts: [Debt], settings: PlanSettings, today: Date) -> Split {
        let paydays = settings.paydays(from: today)
        let payday = paydays.date(0), next = paydays.date(1)
        let buffer = min(settings.buffer, amount)
        var pot = max(0, amount - buffer).cents
        var split = Split(payday: payday, nextPayday: next, amount: amount, bufferKept: buffer)

        // Running copies, so a second payment to the same debt sees the first.
        var live = debts.filter { !$0.isPaidOff }
        func index(_ id: UUID) -> Int? { live.firstIndex { $0.id == id } }

        // Every scheduled payment due before the next payday, soonest first.
        var dues: [(debt: UUID, date: Date, order: Int)] = []
        for (order, d) in live.enumerated() {
            if d.kind == .payLater {
                dues += d.remainingInstallmentDates.filter { $0 < next }.map { (d.id, $0, order) }
            } else {
                var x = d.nextUnpaidDue()
                while let date = x, date < next {
                    dues.append((d.id, date, order))
                    x = Cal.nextDue(day: d.dueDay, onOrAfter: Cal.addDays(1, to: date))
                }
            }
        }
        dues.sort { $0.date != $1.date ? $0.date < $1.date : $0.order < $1.order }

        for due in dues {
            guard let i = index(due.debt), !live[i].isPaidOff else { continue }
            let d = live[i]
            let wanted = d.scheduledPayment(on: today)
            guard wanted > 0 else { continue }
            let pay = min(wanted, pot).cents
            split.shortBy += wanted - pay
            guard pay > 0 else { continue }
            pot = (pot - pay).cents
            var detail = "\(d.paymentWord)\((d.paidTowardDue ?? 0) > 0 ? " remainder" : "") · due \(Fmt.monthDay(due.date))"
            // A due date whose statement has not posted by payday: the money is set aside, but it has to be paid later to count.
            if let opens = d.dueOpens(), opens > payday { detail += " · pay from \(Fmt.monthDay(opens))" }
            live[i].pay(pay, on: today, ignoringLock: true)
            split.lines.append(SplitLine(debtID: d.id, title: d.title, detail: detail, amount: pay, isExtra: false, dueDate: due.date))
        }

        // Whatever is left goes down the strategy order, straight onto the balance.
        let queue = extraQueue(live, strategy: settings.strategy, customOrder: settings.customOrder,
                               promoMinimumOnly: settings.promoMinimumOnly, on: payday)
        var first = true
        for target in queue {
            guard pot > 0.005, let i = index(target.id), live[i].balance > 0.005 else { continue }
            let pay = min(pot, live[i].balance).cents
            live[i].pay(pay, on: today)
            pot = (pot - pay).cents
            split.lines.append(SplitLine(debtID: target.id, title: target.title,
                                         detail: first ? "First in your strategy" : "Next in your strategy",
                                         amount: pay, isExtra: true, dueDate: nil))
            if first {
                let left = live[i].balance
                split.summary = left > 0.005 ? "\(target.title) drops to \(left.usd)." : "\(target.title) is paid off."
                first = false
            }
        }
        split.shortBy = split.shortBy.cents
        return split
    }

    // MARK: One debt at a time

    /// Months and total interest to clear a balance with a fixed monthly payment, interest at APR / 12
    /// a month. Nil if the payment never gets ahead of the interest.
    static func amortize(balance: Double, apr: Double, payment: Double) -> (months: Int, interest: Double)? {
        var bal = balance, months = 0, interest = 0.0
        let rate = apr / 1200
        while bal > 0.005 {
            let i = bal * rate
            guard payment > i + 0.005, months < 1200 else { return nil }
            interest += i
            bal = bal + i - min(payment, bal + i)
            months += 1
        }
        return (months, interest)
    }

    /// The next `months` months of paying only a fixed amount.
    static func fixedSchedule(debt: Debt, payment: Double, from start: Date, months: Int = 12) -> [MonthSlice] {
        var bal = debt.balance
        var out: [MonthSlice] = []
        for m in 0..<months {
            let month = Cal.addMonths(m, to: Cal.monthStart(start))
            guard bal > 0.005 else { break }
            let interest = bal * debt.apr(on: month) / 1200
            let pay = min(payment, bal + interest)
            out.append(MonthSlice(month: month, interest: min(interest, pay), principal: max(0, pay - interest)))
            bal = bal + interest - pay
        }
        return out
    }

    /// Paying one fixed amount a month from `start`, with the rate following any promo: how many
    /// months it takes and what it costs in interest. Nil if the payment never gets ahead of the interest.
    static func fixedPayoff(debt: Debt, payment: Double, from start: Date) -> (months: Int, interest: Double)? {
        var bal = debt.balance, months = 0, interest = 0.0
        while bal > 0.005 {
            guard months < 1200 else { return nil }
            let month = Cal.addMonths(months, to: start)
            let i = bal * debt.apr(on: month) / 1200
            // Stuck for good only once no promo is left to end and change the rate.
            if payment <= i + 0.005 && !debt.hasPromo(on: month) { return nil }
            interest += i
            bal = bal + i - min(payment, bal + i)
            months += 1
        }
        return (months, interest)
    }

    /// What the recorded payments went to, by month, worked backwards from today's balance.
    /// A loan payment's interest is exact: recorded when it was made, or worked out from the balance
    /// before it. A card's is the month's interest on the balance its payment was made against.
    private static func recorded(debt: Debt, payments: [PaymentRecord]) -> (paid: [Date: Double], interest: [Date: Double]) {
        var balance = debt.balance
        var paid: [Date: Double] = [:], interest: [Date: Double] = [:]
        let mine = payments.enumerated().filter { $0.element.debtID == debt.id }
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset > $1.offset }
            .map(\.element)
        for record in mine {
            let month = Cal.monthStart(record.date)
            let rate = debt.apr(on: record.date) / 1200
            switch record.kind {
            case .added:
                continue
            case .charge, .adjustment:
                balance -= record.amount
                continue
            case .minimum, .installment, .payment, .partial, .extra:
                break
            }
            if debt.kind == .loan {
                // A scheduled payment took its interest first: balance before = (balance after + payment) / (1 + rate).
                let part = record.interest ?? (record.kind == .payment ? record.amount - ((balance + record.amount) / (1 + rate) - balance) : 0)
                interest[month, default: 0] += part
                balance += record.amount - part
            } else {
                balance += record.amount
                // One month's interest per month, on the highest balance a payment was made against.
                if record.kind != .extra { interest[month] = max(interest[month] ?? 0, balance * rate) }
            }
            paid[month, default: 0] += record.amount
        }
        return (paid, interest)
    }

    /// What the last few months of recorded payments went to.
    static func pastSlices(debt: Debt, payments: [PaymentRecord], today: Date, months: Int = 6) -> [MonthSlice] {
        let (paid, interest) = recorded(debt: debt, payments: payments)
        return stride(from: months, through: 1, by: -1).map { back in
            let month = Cal.addMonths(-back, to: Cal.monthStart(today))
            let total = paid[month] ?? 0
            let part = min(total, interest[month] ?? 0)
            return MonthSlice(month: month, interest: part, principal: total - part)
        }
    }

    /// Interest paid so far according to the recorded payments. Exact for loans, estimated for cards.
    static func interestPaid(debt: Debt, payments: [PaymentRecord]) -> Double {
        let (paid, interest) = recorded(debt: debt, payments: payments)
        return interest.reduce(0) { $0 + min($1.value, paid[$1.key] ?? 0) }
    }
}
