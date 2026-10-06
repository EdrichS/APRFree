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
    /// check-ins reported or, when no figure was entered, how far they raised a balance.
    var interest: Double {
        entries.reduce(0) { sum, entry in
            switch entry.kind {
            case .statement: sum + (entry.interest ?? max(0, entry.amount))
            case .minimum, .installment, .payment, .partial, .extra: sum + (entry.interest ?? 0)
            default: sum
            }
        }.cents
    }

    var change: Double { (closing - opening).cents }
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

    // MARK: Credit utilization

    /// Cards that have a credit limit, which is what utilization is measured against.
    var limitedCards: [Debt] {
        data.debts.filter { $0.kind == .card && ($0.creditLimit ?? 0) > 0 }
    }

    /// The share of the combined credit limit in use, from 0 to 1. Nil when no card has a limit.
    var utilization: Double? {
        let limit = limitedCards.reduce(0) { $0 + ($1.creditLimit ?? 0) }
        return limit > 0 ? limitedCards.reduce(0) { $0 + $1.balance } / limit : nil
    }

    /// Utilization on each day a card balance changed, from the recorded entries. Measured against
    /// today's limits, since past limits are not kept.
    var utilizationHistory: [PlanPoint] {
        let cards = limitedCards
        let limit = cards.reduce(0) { $0 + ($1.creditLimit ?? 0) }
        guard limit > 0 else { return [] }
        let ids = Set(cards.map(\.id))
        let tracks = History.tracks(debts: data.debts, payments: data.payments, today: today).filter { ids.contains($0.id) }
        let days = Set(tracks.flatMap { $0.steps.map(\.day) }.filter { $0 <= today }).union([today]).sorted()
        return days.map { day in PlanPoint(date: day, total: tracks.reduce(0) { $0 + $1.balance(on: day) } / limit) }
    }

    /// Utilization after each payday of the current plan.
    var utilizationPlan: [PlanPoint] {
        let cards = limitedCards
        let limit = cards.reduce(0) { $0 + ($1.creditLimit ?? 0) }
        let plan = plan
        guard limit > 0, plan.finished else { return [] }
        return plan.series.enumerated().map { index, point in
            let owed = cards.reduce(0.0) { sum, card in
                // A card already at zero is not in the plan at all.
                sum + (plan.balances[card.id].flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? 0)
            }
            return PlanPoint(date: point.date, total: owed / limit)
        }
    }

    /// The day a card's balance drops under 30% of its limit on the current plan. Today if it
    /// already is; nil if the plan never gets it there.
    func under30Date(for card: Debt) -> Date? {
        guard let limit = card.creditLimit, limit > 0 else { return nil }
        if card.balance < limit * 0.3 { return today }
        return plan.firstDate(card.id, under: limit * 0.3)
    }
}
