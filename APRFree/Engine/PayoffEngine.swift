import Foundation

struct PlanInput {
    var debts: [Debt]
    var today: Date
    /// Where the money comes from. Each payday already has the safety buffer taken out.
    var pay: PaySchedule
    var strategy: Strategy
    var customOrder: [UUID]
    var promoMinimumOnly: Bool
    /// Added to the first payday only.
    var oneTime: Double = 0
    /// Added to the first payday of every month.
    var extraMonthly: Double = 0
    /// Leaves out the month-by-month detail, the balances over time and each debt's own payoff date:
    /// what is left is the total interest and the debt-free date. Enough to compare one plan with
    /// another, and several times faster.
    var totalsOnly = false

    init(debts: [Debt], today: Date, pay: PaySchedule, strategy: Strategy, customOrder: [UUID], promoMinimumOnly: Bool,
         oneTime: Double = 0, extraMonthly: Double = 0, totalsOnly: Bool = false) {
        self.debts = debts
        self.today = today
        self.pay = pay
        self.strategy = strategy
        self.customOrder = customOrder
        self.promoMinimumOnly = promoMinimumOnly
        self.oneTime = oneTime
        self.extraMonthly = extraMonthly
        self.totalsOnly = totalsOnly
    }

    /// A plan fed by a single income. `perPayday` is what is left for debt each payday.
    init(debts: [Debt], today: Date, firstPayday: Date, frequency: PayFrequency, perPayday: Double, strategy: Strategy,
         customOrder: [UUID], promoMinimumOnly: Bool, oneTime: Double = 0, extraMonthly: Double = 0, anchorDay: Int? = nil,
         totalsOnly: Bool = false) {
        let first = Day(firstPayday)
        var monthDay = first.day
        if let anchorDay, anchorDay >= first.day, Day.inMonth(first.monthIndex, day: anchorDay) == first { monthDay = anchorDay }
        let line = PaySchedule.Line(first: first, frequency: frequency, monthDays: [monthDay], gross: perPayday, net: perPayday)
        self.init(debts: debts, today: today, pay: PaySchedule(lines: [line]), strategy: strategy, customOrder: customOrder,
                  promoMinimumOnly: promoMinimumOnly, oneTime: oneTime, extraMonthly: extraMonthly, totalsOnly: totalsOnly)
    }
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
    /// Per debt: its balance at each point of `series`.
    var balances: [UUID: [Double]] = [:]
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

    /// The first date in the plan on which a debt's balance is under `ceiling`. Nil if it never is.
    func firstDate(_ id: UUID, under ceiling: Double) -> Date? {
        guard let line = balances[id] else { return nil }
        return zip(series, line).first { $0.1 < ceiling }?.0.date
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
    /// The incomes this paycheck split uses up. Empty for extra money, which uses up none.
    var incomes: [UUID] = []
    /// True for money that is not a paycheck: nothing is held back and no payday is used up.
    var isExtraMoney = false

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

    /// One ordering rule for every caller, whatever it is ordering.
    private static func ordered<T>(_ items: [T], strategy: Strategy, rank: [UUID: Int], id: (T) -> UUID,
                                   balance: (T) -> Double, rate: (T) -> Double) -> [T] {
        switch strategy {
        case .avalanche:
            // By rate. A dollar of extra payment saves interest at the rate of the debt it lands on,
            // whatever that debt's size, so the highest rate first costs the least overall.
            return items.sorted { a, b in
                let x = rate(a), y = rate(b)
                return x != y ? x > y : balance(a) < balance(b)
            }
        case .snowball:
            return items.sorted { a, b in
                let x = balance(a), y = balance(b)
                return x != y ? x < y : rate(a) > rate(b)
            }
        case .custom:
            return items.sorted { a, b in
                let x = rank[id(a)] ?? Int.max, y = rank[id(b)] ?? Int.max
                return x != y ? x < y : rate(a) > rate(b)
            }
        }
    }

    private static func ranks(_ customOrder: [UUID]) -> [UUID: Int] {
        var rank: [UUID: Int] = [:]
        for (i, id) in customOrder.enumerated() where rank[id] == nil { rank[id] = i }
        return rank
    }

    /// Debts in the order a strategy sends extra money to them.
    static func priority(_ debts: [Debt], strategy: Strategy, customOrder: [UUID], on date: Date) -> [Debt] {
        ordered(debts, strategy: strategy, rank: ranks(customOrder), id: \.id, balance: \.balance) { $0.apr(on: date) }
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

    /// One debt as the simulation runs. Everything is in whole calendar days.
    private struct Work {
        let id: UUID
        let isLoan: Bool
        let isPayLater: Bool
        let isCard: Bool
        let apr: Double
        let promoRate: Double
        /// The first day the regular rate applies. Nil when there is no promo.
        let promoEnd: Day?
        let dueDay: Int
        let minimum: Double
        /// The running balance: principal for a loan, everything for a card.
        var balance: Double
        /// Loan interest charged but not yet paid.
        var accrued = 0.0
        var due: Day?
        let installments: [Day]
        var nextInstallment = 0
        /// What is left of the first due date when part of it has already been paid.
        var firstDueLeft: Double?
        // Month by month, keyed by month index: what was paid, and the interest charged.
        var paid: [Int: Double] = [:]
        var interest: [Int: Double] = [:]

        var owed: Double { balance + accrued }

        init(_ debt: Debt, today: Day, todayDate: Date) {
            id = debt.id
            isLoan = debt.kind == .loan
            isPayLater = debt.kind == .payLater
            isCard = debt.kind == .card
            apr = debt.apr
            promoRate = debt.promoAPR ?? debt.apr
            promoEnd = debt.promoAPR != nil ? debt.promoEnd.map { Day($0) } : nil
            dueDay = debt.dueDay
            minimum = debt.minimum
            balance = debt.balance
            // The same dates as `remainingInstallmentDates` and `nextUnpaidDue`, worked out in whole days.
            if isPayLater, let first = debt.nextDue.map({ Day($0) }), let step = debt.every {
                let left = max(0, (debt.installments ?? 0) - (debt.paidInstallments ?? 0))
                installments = (0..<left).map { n in
                    switch step {
                    case .weekly: first.adding(days: 7 * n)
                    case .biweekly: first.adding(days: 14 * n)
                    case .monthly: first.adding(months: n)
                    }
                }
            } else {
                installments = []
            }
            if isPayLater || debt.isPaidOff {
                due = nil
            } else {
                due = Day.next(dayOfMonth: debt.dueDay, onOrAfter: debt.paidThrough.map { Day($0).adding(days: 1) } ?? Day(debt.addedAt))
            }
            if isLoan, let due {
                // The stored loan balance is principal as of the last payment, so the interest
                // that has built up since then is owed on top of it.
                let last = debt.paidThrough.map { Day($0) } ?? Day.inMonth(due.monthIndex - 1, day: debt.dueDay)
                let days = min(max(0, last.days(to: today)), 366)
                accrued = max(0, debt.balance * rate(on: today) / 36500 * Double(days) - (debt.interestTowardDue ?? 0))
            }
            if (debt.paidTowardDue ?? 0) > 0 { firstDueLeft = debt.scheduledPayment(on: todayDate) }
        }

        func rate(on day: Day) -> Double {
            if let promoEnd, day < promoEnd { return promoRate }
            return apr
        }

        func hasPromo(on day: Day) -> Bool { promoEnd.map { day < $0 } ?? false }

        /// The size of the next scheduled payment: the minimum, or what is left of a partly paid one.
        private mutating func nextAmount() -> Double {
            defer { firstDueLeft = nil }
            return firstDueLeft ?? minimum
        }

        /// What is due before `limit`, removed from the schedule.
        mutating func takeDues(before limit: Day) -> Double {
            var sum = 0.0
            if isPayLater {
                while nextInstallment < installments.count, installments[nextInstallment] < limit {
                    sum += nextAmount()
                    nextInstallment += 1
                }
                guard sum > 0 else { return 0 }
                // The last installment clears whatever is left, odd cents included.
                return nextInstallment >= installments.count ? owed : min(sum, owed)
            }
            while let d = due, d < limit {
                sum += nextAmount()
                due = Day.next(dayOfMonth: dueDay, onOrAfter: d.adding(days: 1))
            }
            return min(sum, owed)
        }

        /// Interest first, then principal.
        mutating func pay(_ amount: Double) {
            let part = min(amount, accrued)
            accrued -= part
            balance -= amount - part
        }

        /// Interest for the days from `from` up to but not including `to`, at the one rate that holds
        /// across them. A card compounds daily, so n days multiply the balance by (1 + rate)^n; a
        /// loan charges simple interest on its principal.
        mutating func accrue(from: Day, to: Day) -> Double {
            let rate = rate(on: from)
            guard rate > 0, to > from else { return 0 }
            let days = Double(from.days(to: to))
            let charged: Double
            if isLoan {
                charged = balance * rate / 36500 * days
                accrued += charged
            } else {
                charged = balance * (pow(1 + rate / 36500, days) - 1)
                balance += charged
            }
            return charged
        }

        /// The due date a final payment made on `payday` covers.
        func coveredDue(payday: Day) -> Day {
            if isPayLater { return max(payday, installments.last ?? payday) }
            return Day.next(dayOfMonth: dueDay, onOrAfter: payday)
        }
    }

    static func simulate(_ input: PlanInput) -> PlanResult {
        var result = PlanResult()
        let today = Day(input.today)
        let detail = !input.totalsOnly
        var work = input.debts.filter { !$0.isPaidOff }.map { Work($0, today: today, todayDate: input.today) }
        func owed() -> Double { work.reduce(0) { $0 + $1.owed } }
        func point(_ day: Day) -> PlanPoint {
            var p = PlanPoint(date: day.date, total: 0)
            for w in work {
                p.total += w.balance
                if w.isCard { p.cards += w.balance }
                if w.isLoan { p.loans += w.balance }
            }
            return p
        }
        func note(_ day: Day) {
            guard detail else { return }
            result.series.append(point(day))
            for w in work { result.balances[w.id, default: []].append(w.balance) }
        }

        note(today)
        guard !work.isEmpty else {
            result.finished = true
            return result
        }
        // With no money going in, nothing is ever paid: there is no plan to work out.
        guard input.pay.hasMoney || input.oneTime + input.extraMonthly > 0.005 else { return result }
        // An amount to try with no income behind it still needs dates to land on: once a month, from today.
        let schedule = input.pay.lines.isEmpty ? PaySchedule(lines: [.init(first: today, frequency: .monthly)]) : input.pay
        var cursor = schedule.cursor(from: today)
        guard var event = cursor.next() else { return result }
        var previous = cursor.previous
        let rank = ranks(input.customOrder)

        var day = today
        var index = 0
        var payoffPayday: [UUID: Day] = [:], payoff: [UUID: Day] = [:]
        // A plan that works shrinks what is owed. If a whole year of paydays goes by without a new
        // low, the payments are not keeping up with the interest and never will.
        var lowest = owed()
        var lowestDay = today
        let horizon = today.adding(days: 366 * 60)

        while owed() > 0.005 && index < 5000 && event.day <= horizon {
            guard let next = cursor.next() else { break }
            let payday = event.day

            // Interest up to this payday, a calendar month at a time so each month gets its own share,
            // and split again where a promo rate ends.
            while day < payday {
                let end = min(payday, Day.inMonth(day.monthIndex + 1, day: 1))
                let month = day.monthIndex
                for i in work.indices where work[i].balance > 0 {
                    var charged = 0.0
                    if let cut = work[i].promoEnd, cut > day, cut < end {
                        charged = work[i].accrue(from: day, to: cut) + work[i].accrue(from: cut, to: end)
                    } else {
                        charged = work[i].accrue(from: day, to: end)
                    }
                    guard charged != 0 else { continue }
                    result.totalInterest += charged
                    if detail { work[i].interest[month, default: 0] += charged }
                }
                day = end
            }

            var pot = event.net
            if index == 0 { pot += input.oneTime }
            if input.extraMonthly > 0, previous.map({ $0.monthIndex != payday.monthIndex }) ?? true { pot += input.extraMonthly }
            let month = payday.monthIndex

            // Everything due before the next payday.
            for i in work.indices where work[i].owed > 0.005 {
                let pay = min(work[i].takeDues(before: next.day), work[i].owed, pot)
                guard pay > 0 else { continue }
                work[i].pay(pay)
                pot -= pay
                if detail { work[i].paid[month, default: 0] += pay }
            }

            // The rest, down the strategy order: held promo cards after it, pay-later plans last.
            if pot > 0.005 {
                var main: [Int] = [], held: [Int] = [], later: [Int] = []
                for i in work.indices where work[i].balance > 0.005 {
                    if work[i].isPayLater {
                        later.append(i)
                    } else if input.promoMinimumOnly && work[i].hasPromo(on: payday) {
                        held.append(i)
                    } else {
                        main.append(i)
                    }
                }
                let queue = ordered(main, strategy: input.strategy, rank: rank, id: { work[$0].id }, balance: { work[$0].balance },
                                    rate: { work[$0].rate(on: payday) }) + held + later
                for i in queue {
                    guard pot > 0.005 else { break }
                    let pay = min(pot, work[i].owed)
                    work[i].pay(pay)
                    pot -= pay
                    if detail { work[i].paid[month, default: 0] += pay }
                }
            }

            for i in work.indices where work[i].owed <= 0.005 && payoffPayday[work[i].id] == nil {
                work[i].balance = 0
                work[i].accrued = 0
                payoffPayday[work[i].id] = payday
                payoff[work[i].id] = max(payday, work[i].coveredDue(payday: payday))
                result.paydaysToPayoff[work[i].id] = index + 1
            }

            note(payday)
            index += 1
            previous = payday
            event = next

            let now = owed()
            if now < lowest - 0.005 {
                lowest = now
                lowestDay = payday
            } else if lowestDay.days(to: payday) > 366 {
                break
            }
        }

        if detail {
            // Each month's slice: what was paid, with the interest charged that month taken out of it first.
            for w in work {
                for month in Set(w.paid.keys).union(w.interest.keys) {
                    let date = Day.inMonth(month, day: 1).date
                    let paid = w.paid[month] ?? 0, charged = w.interest[month] ?? 0
                    let part = min(charged, paid)
                    result.ledger[w.id, default: [:]][date] = MonthSlice(month: date, interest: part, principal: paid - part)
                    if charged != 0 { result.accruals[w.id, default: [:]][date] = charged }
                }
            }
        }
        if detail {
            for (id, day) in payoffPayday { result.payoffPayday[id] = day.date }
            for (id, day) in payoff { result.payoff[id] = day.date }
        }

        if owed() <= 0.005 {
            result.finished = true
            result.finalPayday = payoffPayday.values.max()?.date
            result.debtFree = payoff.values.max()?.date
        }
        return result
    }

    // MARK: Make a Payment

    /// Splits a payday amount: every scheduled payment due before the next payday, then the rest as extra.
    static func split(amount: Double, debts: [Debt], settings: PlanSettings, today: Date) -> Split {
        let window = settings.schedule(today: today).window(from: Day(today))
        let payday = window.payday.date, next = window.next.date
        let buffer = min(settings.activeBuffer, amount)
        var pot = max(0, amount - buffer).cents
        var split = Split(payday: payday, nextPayday: next, amount: amount, bufferKept: buffer, incomes: window.event?.lines ?? [])

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

        addExtras(&split, pot: pot, live: &live, settings: settings, on: payday, today: today)
        split.shortBy = split.shortBy.cents
        return split
    }

    /// What to do with money that is not a paycheck: anything already overdue first, because that is
    /// where late fees come from, then all of the rest down the strategy order. Nothing is held back,
    /// and no payday is used up.
    static func extraSplit(amount: Double, debts: [Debt], settings: PlanSettings, today: Date) -> Split {
        let window = settings.schedule(today: today).window(from: Day(today))
        var pot = max(0, amount).cents
        var split = Split(payday: today, nextPayday: window.payday.date, amount: amount, bufferKept: 0, isExtraMoney: true)
        var live = debts.filter { !$0.isPaidOff }

        let overdue = live.enumerated()
            .compactMap { offset, d -> (Int, Date)? in
                guard let due = d.kind == .payLater ? d.remainingInstallmentDates.first : d.nextUnpaidDue(), due < today,
                      d.countsTowardDue(on: today) else { return nil }
                return (offset, due)
            }
            .sorted { $0.1 < $1.1 }
        for (i, due) in overdue {
            let d = live[i]
            let pay = min(d.scheduledPayment(on: today), pot).cents
            guard pay > 0 else { continue }
            pot = (pot - pay).cents
            live[i].pay(pay, on: today)
            split.lines.append(SplitLine(debtID: d.id, title: d.title, detail: "Overdue since \(Fmt.monthDay(due))", amount: pay,
                                         isExtra: false, dueDate: due))
        }

        addExtras(&split, pot: pot, live: &live, settings: settings, on: today, today: today)
        return split
    }

    /// Sends what is left of a split down the strategy order, straight onto the balances.
    private static func addExtras(_ split: inout Split, pot: Double, live: inout [Debt], settings: PlanSettings, on date: Date,
                                  today: Date) {
        var pot = pot
        let queue = extraQueue(live, strategy: settings.strategy, customOrder: settings.customOrder,
                               promoMinimumOnly: settings.promoMinimumOnly, on: date)
        var first = true
        for target in queue {
            guard pot > 0.005, let i = live.firstIndex(where: { $0.id == target.id }), live[i].balance > 0.005 else { continue }
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
            case .added, .removed:
                continue
            case .charge, .adjustment, .statement:
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
