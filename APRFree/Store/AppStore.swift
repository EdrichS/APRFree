import Foundation
import Observation
import WidgetKit

/// Everything the app knows, plus the numbers derived from it.
@Observable
final class AppStore {
    private(set) var data: AppData
    /// Set when a debt reaches zero; drives the celebration overlay.
    var celebration: Debt?
    /// The day the derived numbers were last worked out for. Views that read `today` or `plan`
    /// redraw when it moves on.
    private var day = AppClock.today

    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var planCache: PlanResult?
    /// True when a saved file exists but could not be read at launch. Nothing is saved until it has been.
    @ObservationIgnored private var awaitingSavedData = false

    init(data: AppData, persists: Bool) {
        self.data = data
        self.persists = persists
    }

    /// The store the app runs on. `-demo` loads the sample debts without touching saved data;
    /// in debug builds `-seedDemo` saves them as the real data.
    static func launch() -> AppStore {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") {
            // The sample debts are dated around Oct 4, 2026, so the clock is pinned there.
            AppClock.override = DemoData.today
            return AppStore(data: DemoData.make(), persists: false)
        }
        #if DEBUG
        if args.contains("-onboarding") {
            // A fresh, unsaved start: shows the setup flow without touching saved data.
            return AppStore(data: .empty(today: AppClock.today), persists: false)
        }
        if args.contains("-seedDemo") {
            // Replaces the saved data with the sample debts, so widgets and reminders have something real to show.
            let seeded = AppStore(data: DemoData.make(), persists: true)
            seeded.update { _ in }
            return seeded
        }
        #endif
        let store: AppStore
        switch Persistence.load() {
        case .data(let saved):
            store = AppStore(data: saved, persists: true)
        case .none:
            store = AppStore(data: .empty(today: AppClock.today), persists: true)
        case .unavailable:
            // iOS can start the app before the iPhone is unlocked, when the file cannot be read yet.
            // `refreshForToday` loads it once the app is in front.
            store = AppStore(data: .empty(today: AppClock.today), persists: true)
            store.awaitingSavedData = true
        }
        store.rollPayday()
        store.syncOutputs()
        return store
    }

    var today: Date {
        _ = day
        return AppClock.today
    }

    /// Call when the app comes back to the front. If the date has moved on, the plan is worked out
    /// again and a payday that has passed moves forward on its rhythm.
    func refreshForToday() {
        var stale = false
        if awaitingSavedData {
            switch Persistence.load() {
            case .data(let saved):
                data = saved
                awaitingSavedData = false
                stale = true
            case .none:
                awaitingSavedData = false
            case .unavailable:
                break
            }
        }
        if day != AppClock.today {
            day = AppClock.today
            stale = true
        }
        if stale { planCache = nil }
        rollPayday()
        // A new day changes what the widget and the reminders should say, even if no data did.
        if stale { syncOutputs() }
    }

    // MARK: Reading

    var settings: PlanSettings { data.settings }
    var active: [Debt] { data.debts.filter { !$0.isPaidOff } }
    var paidOff: [Debt] { data.debts.filter(\.isPaidOff) }
    /// The home stack. A credit card stays here at $0.00 once it is paid off, because the account
    /// is still open; a pay-later plan leaves when it is finished.
    var stack: [Debt] { data.debts.filter { $0.kind == .card } + active.filter { $0.kind == .payLater } }
    var loans: [Debt] { active.filter { $0.kind == .loan } }
    /// The Paid Off shelf: finished loans and pay-later plans. Cards are not here; they stay in the stack.
    var shelf: [Debt] { data.debts.filter { $0.isPaidOff && $0.kind != .card } }
    /// The loan or pay-later plan that will reach the shelf first on the current plan.
    var nextForShelf: Debt? {
        active.filter { $0.kind != .card }
            .compactMap { debt in plan.payoff[debt.id].map { (debt, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Every recorded payment, charge and balance change, newest first.
    var activity: [PaymentRecord] {
        data.payments.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset > $1.offset }
            .map(\.element)
    }

    func activity(for id: UUID) -> [PaymentRecord] { activity.filter { $0.debtID == id } }

    var total: Double { data.debts.reduce(0) { $0 + $1.balance } }

    func total(of kind: DebtKind) -> Double {
        data.debts.filter { $0.kind == kind }.reduce(0) { $0 + $1.balance }
    }

    func debt(_ id: UUID) -> Debt? { data.debts.first { $0.id == id } }

    /// What goes to debt each payday once the buffer is set aside.
    var perPayday: Double { max(0, settings.payAmount - settings.buffer) }

    var dailyCost: Double { active.reduce(0) { $0 + $1.dailyCost(on: today) } }

    /// A debt's part of the total balance, from 0 to 1.
    func share(of debt: Debt) -> Double { total > 0 ? debt.balance / total : 0 }

    /// Interest still to be paid on one debt under the current plan: its daily cost added up from the
    /// last payment to the day it is paid off. Nil when the plan never clears it.
    func projectedInterest(for debt: Debt) -> Double? {
        guard plan.payoff[debt.id] != nil else { return nil }
        return max(0, plan.slices(for: debt.id).reduce(0) { $0 + $1.total } - debt.balance)
    }
    /// A month of interest at today's balances: each APR spread over 12 months.
    var monthlyCost: Double { active.reduce(0) { $0 + $1.monthlyInterest(on: today) } }

    // MARK: Scopes (total, credit cards, loans)

    func debts(in scope: DebtScope) -> [Debt] { data.debts.filter(scope.includes) }
    func balance(in scope: DebtScope) -> Double { debts(in: scope).reduce(0) { $0 + $1.balance } }
    func startTotal(in scope: DebtScope) -> Double { debts(in: scope).reduce(0) { $0 + $1.startAmount } }
    func paidSoFar(in scope: DebtScope) -> Double { max(0, startTotal(in: scope) - balance(in: scope)) }

    func fractionPaid(in scope: DebtScope) -> Double {
        let start = startTotal(in: scope)
        return start > 0 ? min(1, paidSoFar(in: scope) / start) : 0
    }

    /// The month everything in a scope is cleared on the current plan.
    func free(in scope: DebtScope) -> Date? {
        let live = debts(in: scope).filter { !$0.isPaidOff }
        return live.isEmpty ? nil : plan.free(live)
    }

    /// Balance change since the start of this month. Negative means it went down.
    func changeThisMonth(in scope: DebtScope) -> Double {
        let start = Cal.monthStart(today)
        let points = data.history.filter { $0.value(scope) != nil }
        let before = points.last { $0.date < start } ?? points.first { $0.date >= start }
        let now = balance(in: scope)
        return now - (before?.value(scope) ?? now)
    }

    /// A scope's balance at the end of the day before `date`, from the recorded history.
    func balance(in scope: DebtScope, before date: Date) -> Double? {
        data.history.last { $0.date < date && $0.value(scope) != nil }?.value(scope)
    }

    var startTotal: Double { startTotal(in: .total) }
    var paidSoFar: Double { paidSoFar(in: .total) }
    var fractionPaid: Double { fractionPaid(in: .total) }
    var changeThisMonth: Double { changeThisMonth(in: .total) }

    // MARK: Plan

    func planInput(strategy: Strategy? = nil, oneTime: Double = 0, extraMonthly: Double? = nil,
                   debts: [Debt]? = nil) -> PlanInput {
        PlanInput(debts: debts ?? data.debts, today: today, firstPayday: settings.nextPayday,
                  frequency: settings.payFrequency, perPayday: perPayday, strategy: strategy ?? settings.strategy,
                  customOrder: settings.customOrder, promoMinimumOnly: settings.promoMinimumOnly,
                  oneTime: oneTime, extraMonthly: extraMonthly ?? settings.extraMonthly, anchorDay: settings.paydayAnchorDay)
    }

    /// The current plan, recomputed only after data changes.
    var plan: PlanResult {
        _ = day
        if let cached = planCache { return cached }
        let result = PayoffEngine.simulate(planInput())
        planCache = result
        return result
    }

    /// Active debts in the order extra money reaches them.
    var extraOrder: [Debt] {
        PayoffEngine.extraQueue(data.debts, strategy: settings.strategy, customOrder: settings.customOrder,
                                promoMinimumOnly: settings.promoMinimumOnly, on: today)
    }

    var strategySummary: String {
        switch settings.strategy {
        case .avalanche: return "Highest APR first"
        case .snowball: return "Smallest balance first"
        case .highestBalance: return "Biggest monthly interest first"
        case .custom:
            let order = extraOrder.filter { $0.kind != .payLater && !$0.hasPromo(on: today) }
            guard let first = order.first else { return "Your own order" }
            let rest = Array(order.dropFirst())
            let byAPR = rest.sorted { $0.apr(on: today) > $1.apr(on: today) }
            return rest.map(\.id) == byAPR.map(\.id) ? "\(first.title) first, then highest APR" : "\(first.title) first, then your order"
        }
    }

    struct Upcoming: Identifiable, Hashable {
        var debt: Debt
        var date: Date
        var amount: Double
        var id: String { "\(debt.id)-\(date.timeIntervalSince1970)" }
    }

    /// Scheduled payments from the earliest unpaid one through `days` from today.
    func upcoming(days: Int = 30, in scope: DebtScope = .total) -> [Upcoming] {
        let limit = Cal.addDays(days, to: today)
        var out: [Upcoming] = []
        for d in active where scope.includes(d) {
            // Later payments in the window are sized as if the earlier ones were made.
            var running = d
            var dates: [Date] = []
            if d.kind == .payLater {
                dates = d.remainingInstallmentDates.filter { $0 <= limit }
            } else {
                var x = d.nextUnpaidDue()
                while let date = x, date <= limit {
                    dates.append(date)
                    x = Cal.nextDue(day: d.dueDay, onOrAfter: Cal.addDays(1, to: date))
                }
            }
            for date in dates where !running.isPaidOff {
                let amount = running.scheduledPayment(on: today)
                out.append(Upcoming(debt: d, date: date, amount: amount))
                running.pay(amount, on: today, ignoringLock: true)
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private var paydaySequence: PaydaySequence { settings.paydays(from: today) }

    /// The next few paydays, for showing the rhythm back to the user.
    func upcomingPaydays(_ count: Int = 3) -> [Date] {
        (0..<count).map(paydaySequence.date)
    }

    /// The first payday on or after today, and the one after it.
    var paydays: (current: Date, next: Date) {
        (paydaySequence.date(0), paydaySequence.date(1))
    }

    /// The amount Make a Payment opens with. The monthly extra rides on the first payday of each month,
    /// the same rule the plan uses.
    var suggestedPayment: Double {
        settings.payAmount + (settings.extraMonthly > 0 && paydaySequence.isFirstInMonth(0) ? settings.extraMonthly : 0)
    }

    // MARK: Writing

    func update(_ change: (inout AppData) -> Void) {
        change(&data)
        changed()
    }

    func updateSettings(_ change: (inout PlanSettings) -> Void) {
        update { change(&$0.settings) }
    }

    func add(_ debt: Debt) {
        update {
            $0.debts.append(debt)
            $0.settings.customOrder.append(debt.id)
            $0.payments.append(PaymentRecord(debtID: debt.id, title: debt.shortTitle, date: AppClock.now, amount: debt.balance,
                                             kind: .added, balanceAfter: debt.balance))
        }
    }

    /// Saves an edited debt. A changed balance is logged, so the history shows statement corrections too.
    func save(_ debt: Debt) {
        update { data in
            guard let i = data.debts.firstIndex(where: { $0.id == debt.id }) else { return }
            let old = data.debts[i]
            var d = debt
            d.balance = max(0, d.balance).cents
            if d.kind == .card { d.startingBalance = max(d.startingBalance, d.balance) }
            let change = (d.balance - old.balance).cents
            if abs(change) >= 0.005 {
                if old.isPaidOff && !d.isPaidOff {
                    d.paidOffAt = nil
                    d.restartCycle(today: today)
                }
                if d.isPaidOff { d.paidOffAt = d.paidOffAt ?? today }
                data.payments.append(PaymentRecord(debtID: d.id, title: d.shortTitle, date: AppClock.now, amount: change,
                                                   kind: .adjustment, balanceAfter: d.balance, before: old.state))
            }
            data.debts[i] = d
        }
    }

    /// Removes a debt. Its past payments stay in the activity history.
    func delete(_ id: UUID) {
        update {
            $0.debts.removeAll { $0.id == id }
            $0.settings.customOrder.removeAll { $0 == id }
        }
    }

    /// A new purchase on a card.
    func charge(_ id: UUID, amount: Double) {
        let amount = amount.cents
        guard amount > 0 else { return }
        update { data in
            guard let i = data.debts.firstIndex(where: { $0.id == id }) else { return }
            var d = data.debts[i]
            let before = d.state
            if d.isPaidOff {
                d.paidOffAt = nil
                d.restartCycle(today: today)
            }
            d.balance = (d.balance + amount).cents
            d.startingBalance = (d.startingBalance + amount).cents
            data.debts[i] = d
            data.payments.append(PaymentRecord(debtID: id, title: d.shortTitle, date: AppClock.now, amount: amount, kind: .charge,
                                               balanceAfter: d.balance, before: before))
        }
    }

    /// Records a payment. Whether it counts toward the due date, and whether that moves the date,
    /// is decided by `Debt.pay`; anything beyond what is owed is ignored.
    func pay(_ id: UUID, amount requested: Double) {
        guard requested > 0, let before = debt(id), !before.isPaidOff else { return }
        var finished: Debt?
        update { data in
            guard let i = data.debts.firstIndex(where: { $0.id == id }) else { return }
            var d = data.debts[i]
            let before = d.state
            let result = d.pay(requested, on: today)
            guard result.amount > 0 else { return }
            if d.isPaidOff {
                d.paidOffAt = today
                finished = d
            }
            data.debts[i] = d
            data.payments.append(PaymentRecord(debtID: id, title: d.shortTitle, date: AppClock.now, amount: result.amount, kind: result.kind,
                                               interest: result.interest > 0 ? result.interest : nil, balanceAfter: d.balance,
                                               before: before))
        }
        if let finished { celebration = finished }
    }

    /// Applies the lines of a split that were marked paid, scheduled payments before extras.
    func apply(_ lines: [SplitLine], allPaid: Bool, nextPayday: Date) {
        for line in lines { pay(line.debtID, amount: line.amount) }
        if allPaid { updateSettings { $0.nextPayday = nextPayday } }
    }

    // MARK: Undo

    /// Why an entry cannot be undone, or nil when it can.
    func undoBlocker(_ record: PaymentRecord) -> String? {
        guard record.kind == .added else { return nil }
        return debt(record.debtID) == nil
            ? "This marks when \(record.title) was added."
            : "This marks when \(record.title) was added. To remove it, delete \(record.title) from its own screen."
    }

    /// Takes one entry back. The debt returns to how it stood just before the entry, then everything
    /// recorded after it for that debt is applied again in order, so later entries keep their meaning:
    /// undoing a minimum, for instance, lets the next payment count toward that due date instead.
    func undo(_ id: UUID) {
        guard let record = data.payments.first(where: { $0.id == id }), record.kind != .added else { return }
        update { data in
            guard let index = data.payments.firstIndex(where: { $0.id == id }) else { return }
            data.payments.remove(at: index)
            // If the debt itself was deleted, only the entry can go.
            guard let di = data.debts.firstIndex(where: { $0.id == record.debtID }) else { return }
            var d = data.debts[di]
            if let before = record.before {
                d.state = before
            } else {
                d.reverse(record)
            }
            var dropped: [UUID] = []
            for i in data.payments.indices where i >= index && data.payments[i].debtID == d.id {
                if let again = d.reapply(data.payments[i]) {
                    data.payments[i] = again
                } else {
                    dropped.append(data.payments[i].id)
                }
            }
            data.payments.removeAll { dropped.contains($0.id) }
            data.debts[di] = d
        }
        if celebration?.id == record.debtID { celebration = nil }
    }

    func restore(_ restored: AppData) {
        update { $0 = restored }
        rollPayday()
    }

    /// Moves a payday that has passed forward to the next one on the same rhythm.
    func rollPayday() {
        guard settings.nextPayday < today else { return }
        let next = settings.paydays(from: today).date(0)
        updateSettings { $0.nextPayday = next }
    }

    /// Erases every debt, payment and setting, and goes back to the first-run setup.
    func reset() {
        celebration = nil
        UserDefaults.standard.removeObject(forKey: "progressScope")
        update { $0 = .empty(today: today) }
        if persists { Reminders.clearDelivered() }
    }

    private func changed() {
        planCache = nil
        recordHistory()
        guard persists, !awaitingSavedData else { return }
        Persistence.save(data)
        syncOutputs()
    }

    /// Brings everything outside the app in line with the data: the widget and the reminders.
    private func syncOutputs() {
        guard persists, !awaitingSavedData else { return }
        widgetSnapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        Reminders.reschedule(for: data, today: today)
    }

    /// Keeps one balance point per day, written whenever any of the three totals moves.
    private func recordHistory() {
        let now = BalancePoint(date: today, total: total.cents, cards: total(of: .card).cents, loans: total(of: .loan).cents)
        if let last = data.history.last {
            let same = abs(last.total - now.total) < 0.005 && abs((last.cards ?? -1) - (now.cards ?? 0)) < 0.005
                && abs((last.loans ?? -1) - (now.loans ?? 0)) < 0.005
            guard !same else { return }
            if Cal.startOfDay(last.date) == today {
                data.history[data.history.count - 1] = now
                return
            }
        } else if data.debts.isEmpty {
            return
        }
        data.history.append(now)
    }

    var widgetSnapshot: WidgetSnapshot {
        func snapshot(_ scope: DebtScope) -> ScopeSnapshot {
            let coming = upcoming(days: 60, in: scope)
            let next = coming.first?.date
            let names = coming.filter { $0.date == next }.map(\.debt.shortTitle)
            return ScopeSnapshot(balance: balance(in: scope), changeThisMonth: changeThisMonth(in: scope), nextDue: next,
                                 nextDueNames: names.joined(separator: ", "), free: free(in: scope),
                                 fractionPaid: fractionPaid(in: scope))
        }
        return WidgetSnapshot(total: snapshot(.total), cards: snapshot(.cards), loans: snapshot(.loans), zone: Cal.zone.identifier)
    }
}
