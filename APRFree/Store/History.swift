import Foundation

/// The balances over time, worked out from the recorded entries. Because it is always rebuilt from
/// them, undoing or editing an entry changes the past as well as today.
enum History {
    /// One debt's balance after each of its entries, oldest first.
    struct Track {
        var id: UUID
        var kind: DebtKind?
        var steps: [(day: Date, balance: Double)] = []

        /// The balance at the end of `day`: what the latest entry up to then left. Zero before the first.
        func balance(on day: Date) -> Double {
            steps.last { $0.day <= day }?.balance ?? 0
        }
    }

    static func tracks(debts: [Debt], payments: [PaymentRecord], today: Date) -> [Track] {
        let known = Dictionary(debts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var order: [UUID] = []
        var entries: [UUID: [PaymentRecord]] = [:]
        for record in payments {
            if entries[record.debtID] == nil { order.append(record.debtID) }
            entries[record.debtID, default: []].append(record)
        }
        var out: [Track] = []
        for id in order {
            // Entries are kept in the order they happened; sorting by day keeps that order within a day.
            let mine = (entries[id] ?? []).enumerated().sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
                .map(\.element)
            guard let first = mine.first else { continue }
            let debt = known[id]
            var track = Track(id: id, kind: debt?.kind ?? first.debtKind)
            var running = 0.0
            if first.kind != .added {
                // No "added" entry: the debt starts with whatever it held just before its first entry.
                running = first.before?.balance ?? debt.map { Migration.balance(before: first, after: first.balanceAfter ?? $0.balance, debt: $0) } ?? 0
                track.steps.append((debt.map { min($0.addedAt, first.date) } ?? first.date, running))
            }
            for record in mine {
                switch record.kind {
                case .added: running = record.balanceAfter ?? record.amount
                case .removed: running = 0
                case .charge, .adjustment, .statement: running = record.balanceAfter ?? running + record.amount
                case .minimum, .installment, .payment, .partial, .extra:
                    running = record.balanceAfter ?? running - (record.amount - (record.interest ?? 0))
                }
                track.steps.append((record.date, max(0, running)))
            }
            if let debt {
                // What the debt holds now is the last word, whatever the entries add up to.
                if abs(running - debt.balance) > 0.005 { track.steps.append((today, debt.balance)) }
            } else if mine.last?.kind != .removed, let last = mine.last {
                // Deleted before deletions were recorded: gone from the day after its last entry.
                track.steps.append((Cal.addDays(1, to: last.date), 0))
            }
            out.append(track)
        }
        // A debt with no entries at all still counts from the day it was added.
        for debt in debts where entries[debt.id] == nil {
            out.append(Track(id: debt.id, kind: debt.kind, steps: [(debt.addedAt, debt.balance)]))
        }
        return out
    }

    /// One point for every day the balances changed, and one for today.
    static func points(debts: [Debt], payments: [PaymentRecord], today: Date) -> [BalancePoint] {
        let tracks = tracks(debts: debts, payments: payments, today: today)
        guard !tracks.isEmpty else { return [] }
        let days = Set(tracks.flatMap { $0.steps.map(\.day) }.filter { $0 <= today }).union([today]).sorted()
        var out: [BalancePoint] = []
        for day in days {
            var total = 0.0, cards = 0.0, loans = 0.0
            for track in tracks {
                let balance = track.balance(on: day)
                total += balance
                if track.kind == .card { cards += balance }
                if track.kind == .loan { loans += balance }
            }
            let point = BalancePoint(date: day, total: total.cents, cards: cards.cents, loans: loans.cents)
            if let last = out.last, day != today, last.total == point.total, last.cards == point.cards, last.loans == point.loans { continue }
            out.append(point)
        }
        return out
    }
}
