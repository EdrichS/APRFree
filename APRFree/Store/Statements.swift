import Foundation

/// One calendar month of the user's own record: what was paid, what was added, and where the
/// balances went.
struct MonthStatement: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        var id: UUID
        var title: String
        var paid: Double
        var charged: Double
        /// The balance the debt ended the month with. Nil when it could not be worked out.
        var closing: Double?
    }

    /// The first day of the month.
    var month: Date
    var id: Date { month }
    /// Everything recorded that month, newest first.
    var entries: [PaymentRecord]
    var lines: [Line]
    /// Everything owed at the start of the month, and at its end (or today, for the month in progress).
    var opening: Double
    var closing: Double
    var isCurrent: Bool

    var payments: [PaymentRecord] { entries.filter(\.isPayment) }
    var paid: Double { payments.reduce(0) { $0 + $1.amount }.cents }
    var charged: Double { entries.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }.cents }

    /// Interest recorded this month: the interest part of loan payments, and what statement
    /// check-ins and bank updates reported or, when no figure was entered, how far a check-in
    /// raised a balance.
    var interest: Double {
        entries.reduce(0) { sum, entry in
            switch entry.kind {
            // A check-in with no figure typed counts whatever it added. A bank update only counts
            // interest the bank named, because the rest of what it added may be new purchases.
            case .statement: sum + (entry.interest ?? (entry.bank == nil ? max(0, entry.amount) : 0))
            case .minimum, .installment, .payment, .partial, .extra: sum + (entry.interest ?? 0)
            default: sum
            }
        }.cents
    }

    var change: Double { (closing - opening).cents }

    /// What moved the balance besides payments, charges and interest: debts added or deleted,
    /// corrections made by hand, and the part of a check-in or bank update that was not interest.
    var other: Double { (closing - opening + paid - charged - interest).cents }

    /// True once a statement check-in or a bank update was recorded in the month. From then on
    /// the recorded interest is the figure to show for it, everywhere.
    var hasCheckIn: Bool { entries.contains { $0.kind == .statement } }
}

extension AppData {
    /// The cards a monthly check-in is asked for: every card with a balance, except one a bank
    /// keeps up to date through Connected mode.
    var checkInCards: [Debt] {
        let fed = settings.connected.bankFedDebts
        return debts.filter { $0.kind == .card && !$0.isPaidOff && !fed.contains($0.id) }
    }

    /// Those of them not yet checked against a statement this month.
    func awaitingCheckIn(today: Date) -> [Debt] {
        let month = Cal.monthStart(today)
        return checkInCards.filter { $0.statementThrough.map { Cal.monthStart($0) < month } ?? true }
    }
}

extension AppStore {
    /// A statement for every month since the first entry, oldest first.
    var statements: [MonthStatement] {
        let current = Cal.monthStart(today)
        guard let earliest = (data.payments.map(\.date) + data.debts.map(\.addedAt)).min() else { return [] }
        let tracks = History.tracks(debts: data.debts, payments: data.payments, today: today)
        let byMonth = Dictionary(grouping: activity) { Cal.monthStart($0.date) }
        var out: [MonthStatement] = []
        var month = Cal.monthStart(earliest)
        // Far more months than anyone will have, as a stop in case a date is badly wrong.
        while month <= current && out.count < 600 {
            let next = Cal.addMonths(1, to: month)
            let lastDay = Cal.addDays(-1, to: next)
            let entries = byMonth[month] ?? []
            var order: [UUID] = []
            for entry in entries.reversed() where !order.contains(entry.debtID) { order.append(entry.debtID) }
            let lines = order.map { id -> MonthStatement.Line in
                let mine = entries.filter { $0.debtID == id }
                return MonthStatement.Line(id: id, title: debt(id)?.title ?? mine.first?.title ?? "",
                                           paid: mine.filter(\.isPayment).reduce(0) { $0 + $1.amount }.cents,
                                           charged: mine.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }.cents,
                                           closing: month == current ? debt(id)?.balance : tracks.first { $0.id == id }?.balance(on: lastDay))
            }
            let opening = tracks.reduce(0) { $0 + $1.balance(on: Cal.addDays(-1, to: month)) }.cents
            let closing = month == current ? total.cents : tracks.reduce(0) { $0 + $1.balance(on: lastDay) }.cents
            out.append(MonthStatement(month: month, entries: entries, lines: lines, opening: opening, closing: closing, isCurrent: month == current))
            month = next
        }
        return out
    }

    func statement(for month: Date) -> MonthStatement? {
        statements.first { $0.month == Cal.monthStart(month) }
    }

    /// A month's interest, for anywhere outside its statement. Once the month has a statement
    /// check-in this is the recorded figure, the same one the statement shows. Before that it is
    /// an estimate of what the cards charged, plus the interest part of the loan payments.
    func interest(inMonth month: Date) -> (amount: Double, isRecorded: Bool) {
        let start = Cal.monthStart(month)
        if let statement = statement(for: start), statement.hasCheckIn { return (statement.interest, true) }
        let months = Cal.months(from: start, to: Cal.monthStart(today))
        guard months >= 1 else { return (statement(for: start)?.interest ?? 0, false) }
        let estimate = data.debts.reduce(0.0) { sum, debt in
            sum + (PayoffEngine.pastSlices(debt: debt, payments: data.payments, today: today, months: months).first?.interest ?? 0)
        }
        return (estimate.cents, false)
    }
}
