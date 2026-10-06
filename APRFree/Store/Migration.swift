import Foundation

/// Brings data saved by an earlier version of the app up to date. Runs once per file.
enum Migration {
    static func run(_ data: inout AppData) {
        guard data.version < AppData.currentVersion else { return }
        if data.version < 2 {
            completeRecords(&data)
            let notes = repairDueDates(&data)
            if !notes.isEmpty { data.settings.notices += notes }
        }
        data.version = AppData.currentVersion
    }

    // MARK: Entries

    /// Earlier entries did not say what kind of debt they belonged to or what balance they left.
    /// Both are needed to draw the balance history from the entries alone, so they are filled in
    /// here: the kind from the debt, the balances by working back from where each debt stands now.
    static func completeRecords(_ data: inout AppData) {
        let debts = Dictionary(data.debts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byDebt: [UUID: [Int]] = [:]
        for (i, record) in data.payments.enumerated() {
            byDebt[record.debtID, default: []].append(i)
            if record.debtKind == nil { data.payments[i].debtKind = debts[record.debtID]?.kind ?? kind(named: record.title) }
        }
        for (id, slots) in byDebt {
            if let debt = debts[id] {
                // Newest to oldest, undoing each entry's effect on the balance.
                var running = debt.balance
                for i in slots.reversed() {
                    let record = data.payments[i]
                    if let known = record.balanceAfter { running = known } else { data.payments[i].balanceAfter = running.cents }
                    running = balance(before: record, after: running, debt: debt)
                }
            } else if let first = slots.first, data.payments[first].kind == .added {
                // A debt that has since been deleted: forwards from the balance it was added with.
                var running = 0.0
                for i in slots {
                    let record = data.payments[i]
                    switch record.kind {
                    case .added: running = record.amount
                    case .removed: running = 0
                    case .charge, .adjustment, .statement: running += record.amount
                    case .minimum, .installment, .payment, .partial, .extra: running -= record.amount - (record.interest ?? 0)
                    }
                    if record.balanceAfter == nil { data.payments[i].balanceAfter = max(0, running).cents }
                }
            }
        }
    }

    /// The balance just before an entry, given the balance just after it.
    static func balance(before record: PaymentRecord, after: Double, debt: Debt) -> Double {
        switch record.kind {
        case .added, .removed:
            return after
        case .charge, .adjustment, .statement:
            return after - record.amount
        case .minimum, .installment, .payment, .partial, .extra:
            guard debt.kind == .loan else { return after + record.amount }
            // A loan payment took its interest first. When that was not recorded it is worked out the
            // way the loan charges it: balance before = (balance after + payment) / (1 + monthly rate).
            let rate = debt.apr(on: record.date) / 1200
            let interest = record.interest ?? (record.kind == .payment ? record.amount - ((after + record.amount) / (1 + rate) - after) : 0)
            return after + record.amount - interest
        }
    }

    /// What kind of debt an entry's title names, for entries whose debt is gone.
    static func kind(named title: String) -> DebtKind? {
        if title.localizedCaseInsensitiveContains("loan") { return .loan }
        return Brand.all.first { $0.id != Brand.other.id && ($0.name == title || $0.short == title) }?.kind
    }

    // MARK: Due dates

    /// An earlier version moved a card's or loan's due date on by a month with every payment, extra
    /// ones included, so a few payments could push it months ahead. Under the rules the app follows
    /// now, a payment counts toward the first due date that falls more than nine days after the one
    /// before it. So the furthest a due date can have been met is the first one after (the latest
    /// payment minus nine days). Anything beyond that is pulled back to it.
    ///
    /// Dates are only ever moved back, never forward, and a debt with no payments is left alone.
    @discardableResult
    static func repairDueDates(_ data: inout AppData) -> [String] {
        var notes: [String] = []
        for i in data.debts.indices {
            let debt = data.debts[i]
            guard debt.kind != .payLater, !debt.isPaidOff, let through = debt.paidThrough,
                  let latest = data.payments.filter({ $0.debtID == debt.id && $0.isPayment }).map(\.date).max() else { continue }
            let first = Cal.nextDue(day: debt.dueDay, onOrAfter: debt.addedAt)
            let furthest = max(first, Cal.nextDue(day: debt.dueDay, onOrAfter: Cal.addDays(1 - Debt.dueLockDays, to: latest)))
            guard through > furthest else { continue }
            let before = debt.nextUnpaidDue()
            data.debts[i].paidThrough = furthest
            data.debts[i].paidTowardDue = nil
            data.debts[i].interestTowardDue = nil
            if let before, let after = data.debts[i].nextUnpaidDue() {
                notes.append("\(debt.title): next due date moved from \(Fmt.full(before)) back to \(Fmt.full(after)).")
            }
        }
        return notes
    }
}
