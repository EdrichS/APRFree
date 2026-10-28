import Foundation
import Observation
import WidgetKit

/// Everything the app knows, plus the numbers derived from it.
@Observable
final class AppStore {
    private(set) var data: AppData
    /// Set when a debt reaches zero; drives the celebration overlay.
    var celebration: Debt?
    /// The last few actions, for Undo and Redo.
    private(set) var journal = Journal()
    /// The day the derived numbers were last worked out for. Views that read `today` or `plan`
    /// redraw when it moves on.
    private var day = AppClock.today

    /// What Connected mode talks to. Nil when this build has no bank service, and then the mode is not shown.
    @ObservationIgnored var bank: BankService?
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var planCache: PlanResult?
    /// True when a saved file exists but could not be read at launch. Nothing is saved until it has been.
    @ObservationIgnored private var awaitingSavedData = false
    /// Set while several changes are being made as one action, so they are recorded as one.
    @ObservationIgnored private var inTransaction = false
    @ObservationIgnored private var journalDirty = false

    init(data: AppData, persists: Bool) {
        self.data = data
        self.persists = persists
        self.data.history = History.points(debts: data.debts, payments: data.payments, today: AppClock.today)
    }

    /// The store the app runs on. `-demo` loads the sample debts without touching saved data;
    /// in debug builds `-seedDemo` saves them as the real data.
    static func launch() -> AppStore {
        let store = load()
        store.bank = Connected.service(for: store)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-connected") {
            // Turns Connected mode on with the first two sample banks signed in, for screenshots.
            Task { @MainActor in
                store.turnOnConnected()
                for name in await store.banksToOffer().prefix(2) { try? await store.connectBank(name) }
            }
        }
        #endif
        return store
    }

    private static func load() -> AppStore {
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
            store.journal = Persistence.loadJournal()
            store.journalDirty = false
        case .none:
            store = AppStore(data: .empty(today: AppClock.today), persists: true)
        case .unavailable:
            // iOS can start the app before the iPhone is unlocked, when the file cannot be read yet.
            // `refreshForToday` loads it once the app is in front.
            store = AppStore(data: .empty(today: AppClock.today), persists: true)
            store.awaitingSavedData = true
        }
        store.rollPaydays()
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
                journal = Persistence.loadJournal()
                journalDirty = false
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
        if stale {
            planCache = nil
            data.history = History.points(debts: data.debts, payments: data.payments, today: today)
        }
        rollPaydays()
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

    // MARK: Income

    /// The paydays the plan runs on: every income, or the fixed monthly amount standing in for them.
    var schedule: PaySchedule { settings.schedule(today: today) }

    /// True when some payday brings money for debt. Without that there is no plan to show.
    var hasIncome: Bool { schedule.hasMoney }

    /// The next few paydays across every income.
    func upcomingPaydays(_ count: Int = 3) -> [PaySchedule.Event] {
        schedule.events(from: Day(today), count: count)
    }

    /// The first payday on or after today, and the one after it.
    var paydays: (current: Date, next: Date) {
        let window = schedule.window(from: Day(today))
        return (window.payday.date, window.next.date)
    }

    /// The amount Make a Payment opens with: what arrives on the next payday. The monthly extra rides
    /// on the first payday of each month, the same rule the plan uses.
    var suggestedPayment: Double {
        let pay = schedule
        guard let first = pay.events(from: Day(today), count: 1).first else { return 0 }
        let firstOfMonth = pay.cursor(from: Day(today)).previous.map { $0.monthIndex != first.day.monthIndex } ?? true
        return first.gross + (settings.extraMonthly > 0 && firstOfMonth ? settings.extraMonthly : 0)
    }

    /// Roughly what goes to debt in a month, for showing beside the incomes.
    var monthlyForDebt: Double {
        schedule.lines.reduce(0) { sum, line in
            let perMonth: Double
            switch line.frequency {
            case .weekly: perMonth = 52.0 / 12
            case .biweekly: perMonth = 26.0 / 12
            case .monthly: perMonth = Double(line.monthDays.count)
            }
            return sum + line.net * perMonth
        } + settings.extraMonthly
    }

    // MARK: Plan

    func planInput(strategy: Strategy? = nil, oneTime: Double = 0, extraMonthly: Double? = nil,
                   debts: [Debt]? = nil, totalsOnly: Bool = false) -> PlanInput {
        PlanInput(debts: debts ?? data.debts, today: today, pay: schedule, strategy: strategy ?? settings.strategy,
                  customOrder: settings.customOrder, promoMinimumOnly: settings.promoMinimumOnly,
                  oneTime: oneTime, extraMonthly: extraMonthly ?? settings.extraMonthly, totalsOnly: totalsOnly)
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

    // MARK: Writing

    /// Changes the data. With a `label` the change becomes a step that Undo can take back; with
    /// `merging`, a run of the same change counts as one step.
    func update(_ label: String? = nil, merging: Bool = false, _ change: (inout AppData) -> Void) {
        let before = data
        change(&data)
        if let label, !inTransaction, before != data {
            journal.record(label, before: before, merging: merging)
            journalDirty = true
        }
        changed()
    }

    func updateSettings(_ label: String? = nil, merging: Bool = false, _ change: (inout PlanSettings) -> Void) {
        update(label, merging: merging) { change(&$0.settings) }
    }

    /// Several changes recorded as a single step.
    func transaction(_ label: String, _ body: () -> Void) {
        guard !inTransaction else { return body() }
        let before = data
        inTransaction = true
        body()
        inTransaction = false
        if before != data {
            journal.record(label, before: before)
            journalDirty = true
        }
        saveJournal()
    }

    /// Money on a debt is kept to the cent, so what is in memory is exactly what gets saved.
    private func toTheCent(_ debt: Debt) -> Debt {
        var d = debt
        d.balance = max(0, d.balance).cents
        d.minimum = max(0, d.minimum).cents
        d.startingBalance = max(0, d.startingBalance).cents
        d.creditLimit = d.creditLimit.map { max(0, $0).cents }
        d.total = d.total.map { max(0, $0).cents }
        d.originalAmount = d.originalAmount.map { max(0, $0).cents }
        return d
    }

    func add(_ debt: Debt) {
        let debt = toTheCent(debt)
        update("Add \(debt.title)") {
            $0.debts.append(debt)
            $0.settings.customOrder.append(debt.id)
            $0.payments.append(PaymentRecord(debtID: debt.id, title: debt.shortTitle, date: today, amount: debt.balance,
                                             kind: .added, balanceAfter: debt.balance, debtKind: debt.kind))
        }
    }

    /// Saves an edited debt. A changed balance is logged, so the history shows corrections too.
    func save(_ debt: Debt) {
        update("Edit \(debt.title)") { data in
            guard let i = data.debts.firstIndex(where: { $0.id == debt.id }) else { return }
            let old = data.debts[i]
            var d = toTheCent(debt)
            if d.kind == .card { d.startingBalance = max(d.startingBalance, d.balance) }
            let change = (d.balance - old.balance).cents
            if abs(change) >= 0.005 {
                if old.isPaidOff && !d.isPaidOff {
                    d.paidOffAt = nil
                    d.restartCycle(today: today)
                }
                if d.isPaidOff { d.paidOffAt = d.paidOffAt ?? today }
                data.payments.append(PaymentRecord(debtID: d.id, title: d.shortTitle, date: today, amount: change,
                                                   kind: .adjustment, balanceAfter: d.balance, before: old.state, debtKind: d.kind))
            }
            data.debts[i] = d
        }
    }

    /// Removes a debt. Its past entries stay in the activity history, with one more that says it was
    /// deleted and keeps a copy of it, so the deletion can be undone from there at any time.
    func delete(_ id: UUID) {
        guard let debt = debt(id) else { return }
        update("Delete \(debt.title)") {
            $0.debts.removeAll { $0.id == id }
            $0.settings.customOrder.removeAll { $0 == id }
            $0.payments.append(PaymentRecord(debtID: id, title: debt.shortTitle, date: today, amount: debt.balance, kind: .removed,
                                             balanceAfter: 0, before: debt.state, debtKind: debt.kind, removed: debt))
        }
    }

    /// A new purchase on a card.
    func charge(_ id: UUID, amount: Double) {
        let amount = amount.cents
        guard amount > 0, let title = debt(id)?.title else { return }
        update("\(title) charge") { data in
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
            data.payments.append(PaymentRecord(debtID: id, title: d.shortTitle, date: today, amount: amount, kind: .charge,
                                               balanceAfter: d.balance, before: before, debtKind: d.kind))
        }
    }

    /// Records a payment. Whether it counts toward the due date, and whether that moves the date,
    /// is decided by `Debt.pay`; anything beyond what is owed is ignored.
    ///
    /// `scheduled` is for a payment that is known to be the scheduled one, such as a minimum ticked
    /// off in a paycheck split. It counts toward its due date even inside the nine-day wait, where a
    /// payment made on its own would be extra.
    func pay(_ id: UUID, amount requested: Double, scheduled: Bool = false) {
        guard requested > 0, let before = debt(id), !before.isPaidOff else { return }
        var finished: Debt?
        update("\(before.title) payment") { data in
            guard let i = data.debts.firstIndex(where: { $0.id == id }) else { return }
            var d = data.debts[i]
            let before = d.state
            let result = d.pay(requested, on: today, ignoringLock: scheduled)
            guard result.amount > 0 else { return }
            if d.isPaidOff {
                d.paidOffAt = today
                finished = d
            }
            data.debts[i] = d
            data.payments.append(PaymentRecord(debtID: id, title: d.shortTitle, date: today, amount: result.amount, kind: result.kind,
                                               interest: result.interest > 0 ? result.interest : nil, balanceAfter: d.balance,
                                               before: before, debtKind: d.kind, scheduled: scheduled ? true : nil))
        }
        if let finished { celebration = finished }
    }

    /// Applies the lines of a split that were marked paid, scheduled payments before extras. A
    /// paycheck split with every line paid uses up that payday; extra money never does.
    func apply(_ split: Split, paid: Set<UUID>) {
        let lines = split.lines.filter { paid.contains($0.id) }
        guard !lines.isEmpty else { return }
        transaction(split.isExtraMoney ? "Extra money" : "Payday split") {
            // A scheduled line was ticked off as that payment, so it counts toward its due date.
            for line in lines { pay(line.debtID, amount: line.amount, scheduled: !line.isExtra) }
            guard !split.isExtraMoney, lines.count == split.lines.count else { return }
            updateSettings { settings in
                if settings.useFixedAmount {
                    settings.fixedNext = split.nextPayday
                } else {
                    for i in settings.incomes.indices where split.incomes.contains(settings.incomes[i].id) {
                        settings.incomes[i].nextPayday = settings.incomes[i].payday(after: split.payday)
                    }
                }
            }
        }
    }

    // MARK: Statement check-in

    struct StatementEntry {
        var debtID: UUID
        /// What the statement says is owed.
        var balance: Double
        /// The minimum payment it asks for, if it changed.
        var minimum: Double?
        /// The interest it charged, if entered.
        var interest: Double?
    }

    /// The monthly check-in: each balance is set to what its statement says. The difference is the
    /// interest and anything else the app had not seen, which is how a card's balance keeps up with
    /// the real one.
    func checkIn(_ entries: [StatementEntry]) {
        guard !entries.isEmpty else { return }
        transaction("Statement check-in") {
            update { data in
                for entry in entries {
                    guard let i = data.debts.firstIndex(where: { $0.id == entry.debtID }) else { continue }
                    var d = data.debts[i]
                    let before = d.state
                    let balance = Limits.money(entry.balance).cents
                    let change = (balance - d.balance).cents
                    if d.isPaidOff && balance > 0.005 {
                        d.paidOffAt = nil
                        d.restartCycle(today: today)
                    }
                    d.balance = balance
                    // Interest on a card is new debt, like a charge, so it does not count against what has been paid.
                    if d.kind == .card, change > 0 { d.startingBalance = (d.startingBalance + change).cents }
                    if d.isPaidOff { d.paidOffAt = d.paidOffAt ?? today }
                    if let minimum = entry.minimum, minimum > 0 { d.minimum = Limits.money(minimum).cents }
                    d.statementThrough = today
                    data.debts[i] = d
                    data.payments.append(PaymentRecord(debtID: d.id, title: d.shortTitle, date: today, amount: change, kind: .statement,
                                                       interest: entry.interest.flatMap { $0 > 0 ? $0.cents : nil }, balanceAfter: d.balance,
                                                       before: before, debtKind: d.kind))
                }
            }
        }
    }

    /// The cards with a balance that have not been checked against a statement this month. Loans
    /// are not waited for: the app works out their interest itself, payment by payment.
    var awaitingCheckIn: [Debt] { data.awaitingCheckIn(today: today) }

    /// Everything a statement check-in can cover: every card, including one at zero that may have a
    /// new balance, and every loan still being paid.
    var checkInCandidates: [Debt] {
        data.debts.filter { $0.kind == .card || ($0.kind == .loan && !$0.isPaidOff) }
    }

    // MARK: Undo, redo and editing entries

    /// What Undo would take back, or nil when there is nothing.
    var undoLabel: String? { journal.undo.last?.label }
    /// What Redo would put back, or nil when there is nothing.
    var redoLabel: String? { journal.redo.last?.label }

    /// Takes back the last action, whatever it was: a payment, an edit, a deleted debt.
    func undoLast() {
        guard let step = journal.takeBack(current: data) else { return }
        journalDirty = true
        data = step.data.keepingDeviceSettings(of: data)
        celebration = nil
        changed()
        // The step may be from before a payday passed.
        rollPaydays()
    }

    /// Puts back the action that was last undone.
    func redo() {
        guard let step = journal.putBack(current: data) else { return }
        journalDirty = true
        data = step.data.keepingDeviceSettings(of: data)
        changed()
        rollPaydays()
    }

    /// Why an entry cannot be undone on its own, or nil when it can.
    func undoBlocker(_ record: PaymentRecord) -> String? {
        switch record.kind {
        case .added:
            return debt(record.debtID) == nil
                ? "This marks when \(record.title) was added."
                : "This marks when \(record.title) was added. To remove it, delete \(record.title) from its own screen."
        case .removed:
            return record.removed == nil ? "This marks when \(record.title) was deleted." : nil
        default:
            return nil
        }
    }

    /// Takes one entry back. The debt returns to how it stood just before the entry, then everything
    /// recorded after it for that debt is applied again in order, so later entries keep their meaning:
    /// undoing a minimum, for instance, lets the next payment count toward that due date instead.
    /// Undoing a "deleted" entry brings the debt back.
    func undo(_ id: UUID) {
        guard let record = data.payments.first(where: { $0.id == id }), record.kind != .added else { return }
        update("Remove \(record.label)") { data in
            if record.kind == .removed {
                guard let debt = record.removed, !data.debts.contains(where: { $0.id == debt.id }) else { return }
                data.payments.removeAll { $0.id == id }
                data.debts.append(debt)
                data.settings.customOrder.append(debt.id)
                return
            }
            // If the debt itself was deleted, only the entry can go.
            guard data.debts.contains(where: { $0.id == record.debtID }) else {
                data.payments.removeAll { $0.id == id }
                return
            }
            let mine = data.payments.filter { $0.debtID == record.debtID }
            guard let position = mine.firstIndex(where: { $0.id == id }) else { return }
            AppStore.rewrite(&data, debtID: record.debtID, from: position, with: Array(mine.dropFirst(position + 1)))
            // A bank update may also have changed the rate, the minimum, the due day or the limit.
            if let terms = record.termsBefore, let i = data.debts.firstIndex(where: { $0.id == record.debtID }) {
                data.debts[i].terms = terms
            }
        }
        if celebration?.id == record.debtID { celebration = nil }
    }

    /// Why an entry cannot be changed, or nil when it can.
    func editBlocker(_ record: PaymentRecord) -> String? {
        if !record.isEditable { return "This marks when \(record.title) was \(record.kind == .removed ? "deleted" : "added"), so there is nothing in it to change." }
        if debt(record.debtID) == nil { return "\(record.title) has been deleted, so its entries can no longer be changed." }
        return nil
    }

    /// Changes a payment's or a charge's amount or day. The debt is put back to how it stood before
    /// the earliest entry this touches, and everything from there on is applied again in date order.
    func edit(_ id: UUID, amount: Double, date: Date) {
        guard let record = data.payments.first(where: { $0.id == id }), !record.isSigned, editBlocker(record) == nil,
              let debt = debt(record.debtID) else { return }
        let amount = Limits.money(amount).cents
        let day = min(max(Cal.startOfDay(date), debt.addedAt), today)
        guard amount > 0, amount != record.amount || day != record.date else { return }
        update("Edit \(record.label)") { (data: inout AppData) in
            AppStore.replace(&data, entry: record) { entry in
                entry.amount = amount
                entry.date = day
            }
        }
    }

    /// Changes a balance update or a statement check-in: the balance it set, the interest a check-in
    /// reported, or the day. Everything recorded after it for that debt is applied again on top.
    func edit(_ id: UUID, balance: Double, interest: Double?, date: Date) {
        guard let record = data.payments.first(where: { $0.id == id }), record.isSigned, editBlocker(record) == nil,
              let debt = debt(record.debtID) else { return }
        let balance = Limits.money(balance).cents
        let day = min(max(Cal.startOfDay(date), debt.addedAt), today)
        let interest = record.kind == .statement ? interest.flatMap { $0 > 0.004 ? Limits.money($0).cents : nil } : record.interest
        guard balance != record.balanceAfter || day != record.date || interest != record.interest else { return }
        update("Edit \(record.label)") { (data: inout AppData) in
            AppStore.replace(&data, entry: record, setting: balance) { entry in
                entry.date = day
                entry.interest = interest
            }
        }
        if celebration?.id == record.debtID { celebration = nil }
    }

    /// Rewrites one entry of a debt and applies it, and everything after it, again. `balance` is for
    /// an entry that sets the balance rather than moving it: its amount becomes whatever gets there.
    private static func replace(_ data: inout AppData, entry record: PaymentRecord, setting balance: Double? = nil,
                                _ change: (inout PaymentRecord) -> Void) {
        let mine: [PaymentRecord] = data.payments.filter { $0.debtID == record.debtID }
        guard let position = mine.firstIndex(where: { $0.id == record.id }) else { return }
        var changed = mine
        change(&changed[position])
        // A new day can move the entry past its neighbours. Entries keep their order within a day.
        let sorted: [PaymentRecord] = AppStore.inDateOrder(changed)
        let moved: Int? = mine.indices.first { mine[$0].id != sorted[$0].id }
        let first: Int = min(position, moved ?? position)
        var targets: [UUID: Double] = [:]
        if let balance { targets[record.id] = balance }
        AppStore.rewrite(&data, debtID: record.debtID, from: first, with: Array(sorted.dropFirst(first)), setting: targets)
    }

    /// Entries oldest first. Ones on the same day keep the order they were in.
    private static func inDateOrder(_ entries: [PaymentRecord]) -> [PaymentRecord] {
        let numbered: [(offset: Int, element: PaymentRecord)] = Array(entries.enumerated())
        let sorted = numbered.sorted { (a, b) -> Bool in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }
        return sorted.map { $0.element }
    }

    /// Puts a debt back to how it stood before its entry number `position`, then applies `entries`
    /// in its place and after it. An entry that no longer does anything (a payment on a debt that is
    /// now already cleared) is dropped. `targets` names entries that set the balance to a figure.
    private static func rewrite(_ data: inout AppData, debtID: UUID, from position: Int, with entries: [PaymentRecord],
                                setting targets: [UUID: Double] = [:]) {
        guard let di = data.debts.firstIndex(where: { $0.id == debtID }) else { return }
        let slots = data.payments.indices.filter { data.payments[$0].debtID == debtID }
        guard position < slots.count else { return }
        var d = data.debts[di]
        // Walk back from the newest entry. An entry that kept the state before it gives that exactly;
        // one from before that was kept is reversed by its amount.
        for slot in slots[position...].reversed() {
            let record = data.payments[slot]
            if let before = record.before { d.state = before } else { d.reverse(record) }
        }
        var replayed = Array(slots[..<position].map { data.payments[$0] })
        for var entry in entries {
            if let target = targets[entry.id] {
                entry.amount = (target - d.balance).cents
                // A balance update that no longer changes anything has nothing left to say.
                if entry.kind == .adjustment, abs(entry.amount) < 0.005 { continue }
            }
            if let again = d.reapply(entry) { replayed.append(again) }
        }
        // The debt's entries go back into the places they held among everyone else's.
        for (slot, record) in zip(slots, replayed) { data.payments[slot] = record }
        for slot in slots.dropFirst(replayed.count).reversed() { data.payments.remove(at: slot) }
        data.debts[di] = d
    }

    // MARK: Whole-data changes

    /// Replaces everything with a backup. What was accepted on this iPhone stays accepted: a backup
    /// made before the policy existed should not ask for it again.
    func restore(_ restored: AppData) {
        update("Restore backup") { data in
            var incoming = restored
            if data.settings.hasAcceptedLegal {
                incoming.settings.acceptedPrivacy = data.settings.acceptedPrivacy
                incoming.settings.acceptedDisclaimer = data.settings.acceptedDisclaimer
                incoming.settings.acceptedLegalVersion = data.settings.acceptedLegalVersion
            }
            incoming.settings.onboarded = true
            // Bank sign-ins belong to this iPhone, not to the backup.
            incoming.settings.connected = data.settings.connected
            data = incoming
        }
        rollPaydays()
    }

    /// Moves every payday that has passed forward to the next one on the same rhythm.
    func rollPaydays() {
        let stale = settings.incomes.contains { $0.nextPayday < today } || (settings.fixedNext.map { $0 < today } ?? false)
        guard stale else { return }
        updateSettings { settings in
            for i in settings.incomes.indices where settings.incomes[i].nextPayday < today {
                settings.incomes[i].nextPayday = settings.incomes[i].paydays(from: today, count: 1).first ?? today
            }
            if let next = settings.fixedNext, next < today { settings.fixedNext = nil }
        }
    }

    /// Erases every debt, payment and setting, and goes back to the first-run setup.
    func reset() {
        // "Everything" includes the bank sign-ins: the server is told to forget each one.
        if let bank {
            let items = settings.connected.connections.filter { $0.status != .disconnected }.map(\.itemID)
            Task { for item in items { try? await bank.disconnect(itemID: item) } }
        }
        celebration = nil
        UserDefaults.standard.removeObject(forKey: "progressScope")
        journal = Journal()
        journalDirty = true
        update { $0 = .empty(today: today) }
        guard persists else { return }
        // "Everything" includes what sits beside the data: the copy kept from before an upgrade,
        // exports waiting to be shared, reminders already delivered, and the widget's hidden switch.
        Persistence.eraseSideFiles()
        Exporter.removeExports()
        WidgetSnapshot.balancesHidden = false
        Reminders.clearDelivered()
    }

    /// Marks the one-time notices as read.
    func dismissNotices() {
        guard !settings.notices.isEmpty else { return }
        updateSettings { $0.notices = [] }
    }

    private func changed() {
        planCache = nil
        data.history = History.points(debts: data.debts, payments: data.payments, today: today)
        guard persists, !awaitingSavedData else { return }
        Persistence.save(data)
        if !inTransaction { saveJournal() }
        syncOutputs()
    }

    private func saveJournal() {
        guard persists, !awaitingSavedData, journalDirty else { return }
        Persistence.save(journal)
        journalDirty = false
    }

    /// Brings everything outside the app in line with the data: the widget and the reminders.
    private func syncOutputs() {
        guard persists, !awaitingSavedData else { return }
        widgetSnapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        Reminders.reschedule(for: data, today: today)
    }

    var widgetSnapshot: WidgetSnapshot {
        func snapshot(_ scope: DebtScope) -> ScopeSnapshot {
            let coming = upcoming(days: 60, in: scope)
            let next = coming.first?.date
            let names = coming.filter { $0.date == next }.map(\.debt.shortTitle)
            let nextDue: Day? = next.map { Day($0) }
            let free: Day? = free(in: scope).map { Day($0) }
            return ScopeSnapshot(balance: balance(in: scope), changeThisMonth: changeThisMonth(in: scope), nextDue: nextDue,
                                 nextDueNames: names.joined(separator: ", "), free: free, fractionPaid: fractionPaid(in: scope))
        }
        return WidgetSnapshot(total: snapshot(.total), cards: snapshot(.cards), loans: snapshot(.loans))
    }
}
