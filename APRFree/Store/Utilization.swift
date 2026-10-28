import Foundation

/// One month of credit utilization: where it ended, and how far it moved.
struct UtilizationMonth: Identifiable, Hashable {
    /// The first day of the month.
    var month: Date
    var id: Date { month }
    /// The share of the credit limits in use at the end of the month, or today for the month in progress.
    var share: Double
    /// The change from the end of the month before, as a share. Nil for the first month on record.
    var change: Double?
    var isCurrent: Bool
}

// Credit utilization is measured against today's limits; past limits are not kept. A month from
// before a limit was raised or lowered is therefore shown against the limit the card has now.
extension AppStore {
    /// Cards that have a credit limit, which is what utilization is measured against.
    var limitedCards: [Debt] {
        data.debts.filter { $0.kind == .card && ($0.creditLimit ?? 0) > 0 }
    }

    /// The combined limit of those cards.
    var creditLimit: Double { limitedCards.reduce(0) { $0 + ($1.creditLimit ?? 0) } }

    /// The share of the combined credit limit in use, from 0 to 1. Nil when no card has a limit.
    var utilization: Double? {
        let limit = creditLimit
        return limit > 0 ? limitedCards.reduce(0) { $0 + $1.balance } / limit : nil
    }

    /// What would have to come off the cards, together, to bring them under 30% of their limits.
    var toReachThirtyPercent: Double {
        max(0, limitedCards.reduce(0) { $0 + $1.balance } - creditLimit * 0.3).cents
    }

    /// Each limited card's balance over time, from the recorded entries.
    private var cardTracks: [History.Track] {
        let ids = Set(limitedCards.map(\.id))
        return History.tracks(debts: data.debts, payments: data.payments, today: today).filter { ids.contains($0.id) }
    }

    /// Utilization on each day a card balance changed, from the recorded entries. Measured against
    /// today's limits, since past limits are not kept.
    var utilizationHistory: [PlanPoint] {
        let limit = creditLimit
        guard limit > 0 else { return [] }
        let tracks = cardTracks
        let days = Set(tracks.flatMap { $0.steps.map(\.day) }.filter { $0 <= today }).union([today]).sorted()
        return days.map { day in PlanPoint(date: day, total: tracks.reduce(0) { $0 + $1.balance(on: day) } / limit) }
    }

    /// Utilization at the end of every month since the first card entry, oldest first, with how far
    /// each moved from the month before. Measured against today's limits.
    var utilizationMonths: [UtilizationMonth] {
        let limit = creditLimit
        let tracks = cardTracks
        guard limit > 0, let first = tracks.compactMap({ $0.steps.first?.day }).min() else { return [] }
        let current = Cal.monthStart(today)
        var out: [UtilizationMonth] = []
        var month = Cal.monthStart(first)
        while month <= current && out.count < 600 {
            let next = Cal.addMonths(1, to: month)
            let day = month == current ? today : Cal.addDays(-1, to: next)
            let share = tracks.reduce(0) { $0 + $1.balance(on: day) } / limit
            out.append(UtilizationMonth(month: month, share: share, change: out.last.map { share - $0.share }, isCurrent: month == current))
            month = next
        }
        return out
    }

    /// One card's utilization at the end of a day, against the limit it has now.
    func utilization(of card: Debt, on day: Date) -> Double? {
        guard let limit = card.creditLimit, limit > 0 else { return nil }
        guard let track = cardTracks.first(where: { $0.id == card.id }) else { return card.balance / limit }
        return track.balance(on: day) / limit
    }

    /// Utilization after each payday of the current plan.
    var utilizationPlan: [PlanPoint] {
        let cards = limitedCards
        let limit = creditLimit
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
