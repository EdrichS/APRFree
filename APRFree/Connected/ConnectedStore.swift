import Foundation

/// A debt whose figures differ from its bank's, waiting for the one choice of which to follow.
struct BankQuestion: Identifiable, Hashable {
    var id: String { account.id }
    var connectionID: UUID
    var institution: String
    var account: LinkedAccount
    var debt: Debt
    var differences: [BankDifference]
}

/// What one update from the banks did.
struct BankUpdate {
    /// Entries added to the activity history.
    var entries = 0
    /// Debts still waiting for a choice.
    var waiting = 0
    var problems: [String] = []

    var summary: String {
        var parts: [String] = []
        if entries > 0 { parts.append("\(Fmt.plural(entries, "bank update")) added to Activity") }
        if waiting > 0 { parts.append("\(Fmt.plural(waiting, "debt")) waiting for your choice") }
        if parts.isEmpty { parts.append("Nothing new from your banks") }
        return (parts + problems).joined(separator: ". ") + "."
    }
}

extension AppStore {
    /// True when this build has a bank service at all. When it has none, nothing about the mode is shown.
    var connectedAvailable: Bool { bank != nil }

    var connected: ConnectedState { settings.connected }

    /// The mode is on and there is a service behind it.
    var connectedOn: Bool { bank != nil && settings.connected.isOn }

    /// Changes what the app remembers about its connections. Never a step for Undo: it belongs to
    /// the iPhone, not to the plan.
    private func updateConnected(_ change: (inout ConnectedState) -> Void) {
        updateSettings { change(&$0.connected) }
    }

    private func withAccount(_ accountID: String, in connectionID: UUID, _ change: (inout LinkedAccount) -> Void) {
        updateConnected { state in
            guard let c = state.connections.firstIndex(where: { $0.id == connectionID }),
                  let a = state.connections[c].accounts.firstIndex(where: { $0.id == accountID }) else { return }
            change(&state.connections[c].accounts[a])
            state.connections[c].accounts[a].changedAt = Date()
        }
    }

    // MARK: The mode itself

    /// Turns the mode on, which records that its terms were accepted.
    func turnOnConnected() {
        guard bank != nil else { return }
        updateConnected {
            $0.isOn = true
            $0.acceptedAt = Date()
            $0.acceptedVersion = Connected.termsVersion
        }
    }

    /// Turns the mode off. Every bank is disconnected first, so nothing stays signed in on the server.
    /// Returns the banks that could not be reached; the mode stays on while any is still connected.
    @MainActor @discardableResult
    func turnOffConnected() async -> [String] {
        var failed: [String] = []
        for connection in connected.connections where connection.status != .disconnected {
            do { try await disconnect(connection.id) } catch { failed.append(connection.institution) }
        }
        if failed.isEmpty { updateConnected { $0.isOn = false } }
        return failed
    }

    // MARK: Banks

    /// Banks the service can list, less the ones already connected.
    @MainActor
    func banksToOffer() async -> [String] {
        guard connectedOn, let bank else { return [] }
        let live = Set(connected.connections.filter { $0.status == .connected }.map(\.institution))
        return ((try? await bank.institutions()) ?? []).filter { !live.contains($0) }
    }

    /// Signs in to a bank and lists its accounts. Each is linked to the debt it looks like, if there
    /// is exactly one; nothing is changed until the user has said whose figures to follow.
    @MainActor
    func connectBank(_ institution: String?) async throws {
        guard connectedOn, let bank else { return }
        let link = try await bank.connect(institution: institution)
        let now = Date()
        let debts = data.debts
        var taken = Set(connected.connections.flatMap(\.accounts).compactMap(\.debtID))
        updateConnected { state in
            let existing = state.connections.firstIndex { $0.itemID == link.itemID }
            let known = existing.map { state.connections[$0].accounts } ?? []
            let accounts = link.accounts.map { found -> LinkedAccount in
                // Signing in again to a bank already listed keeps what was set up for each account.
                if var old = known.first(where: { $0.id == found.id }) {
                    old.name = found.name
                    old.mask = found.mask
                    old.figures = found.figures
                    return old
                }
                let match = AppStore.match(found, at: link.institution, among: debts, taken: taken)
                if let match { taken.insert(match) }
                return LinkedAccount(id: found.id, name: found.name, mask: found.mask, kind: found.kind, debtID: match, changedAt: now,
                                     figures: found.figures)
            }
            if let existing {
                state.connections[existing].status = .connected
                state.connections[existing].changedAt = now
                state.connections[existing].lastUpdate = now
                state.connections[existing].accounts = accounts
            } else {
                state.connections.append(Connection(itemID: link.itemID, institution: link.institution, addedAt: now, changedAt: now,
                                                    lastUpdate: now, accounts: accounts))
            }
        }
        applyBankFigures()
    }

    /// The debt a bank account most likely is: the same kind, at the same bank, and either the same
    /// name or the only one there.
    static func match(_ account: BankAccount, at institution: String, among debts: [Debt], taken: Set<UUID>) -> UUID? {
        func same(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }
        let there = debts.filter { $0.kind == account.kind && !taken.contains($0.id) && same($0.provider, institution) }
        if let named = there.first(where: { same($0.name, account.name) || same($0.title, account.name) }) { return named.id }
        return there.count == 1 ? there[0].id : nil
    }

    /// Tells the server to forget a bank, and marks it disconnected here. It stays in the list, with
    /// the day it was disconnected, until it is removed.
    @MainActor
    func disconnect(_ id: UUID) async throws {
        guard let connection = connected.connections.first(where: { $0.id == id }), connection.status != .disconnected else { return }
        try await bank?.disconnect(itemID: connection.itemID)
        updateConnected { state in
            guard let c = state.connections.firstIndex(where: { $0.id == id }) else { return }
            state.connections[c].status = .disconnected
            state.connections[c].changedAt = Date()
        }
    }

    /// Takes a disconnected bank off the list.
    func removeConnection(_ id: UUID) {
        updateConnected { $0.connections.removeAll { $0.id == id && $0.status == .disconnected } }
    }

    // MARK: Accounts

    func setAccount(_ accountID: String, in connectionID: UUID, isOn: Bool) {
        withAccount(accountID, in: connectionID) { $0.isOn = isOn }
        if isOn { applyBankFigures() }
    }

    /// Points an account at a debt, or at none. A new pairing is a new question: whose figures to
    /// follow is asked again.
    func link(_ accountID: String, in connectionID: UUID, to debtID: UUID?) {
        withAccount(accountID, in: connectionID) {
            guard $0.debtID != debtID else { return }
            $0.debtID = debtID
            $0.source = .undecided
        }
    }

    /// The one choice for a debt: follow the bank's figures, or keep the user's own.
    func follow(_ source: LinkedAccount.Source, account accountID: String, in connectionID: UUID) {
        withAccount(accountID, in: connectionID) { $0.source = source }
        if source == .bank { applyBankFigures() }
    }

    /// The accounts that could feed a debt: every account of the right kind that is not feeding another.
    func debts(for account: LinkedAccount) -> [Debt] {
        let taken = Set(connected.connections.flatMap(\.accounts).filter { $0.id != account.id }.compactMap(\.debtID))
        return data.debts.filter { $0.kind == account.kind && !taken.contains($0.id) }
    }

    /// Debts whose figures differ from their bank's and whose owner has not yet said which to follow.
    var bankQuestions: [BankQuestion] {
        guard connectedOn else { return [] }
        var out: [BankQuestion] = []
        for connection in connected.connections where connection.status == .connected {
            for account in connection.accounts where account.isOn && account.source == .undecided {
                guard let id = account.debtID, let debt = debt(id), let figures = account.figures else { continue }
                let differences = figures.differences(from: debt, on: today)
                if !differences.isEmpty {
                    out.append(BankQuestion(connectionID: connection.id, institution: connection.institution, account: account, debt: debt,
                                            differences: differences))
                }
            }
        }
        return out
    }

    // MARK: Updates

    /// Asks every connected bank for its current figures, then takes them into the debts that follow
    /// their bank.
    @MainActor @discardableResult
    func refreshBanks() async -> BankUpdate {
        var result = BankUpdate()
        guard connectedOn, let bank else { return result }
        for connection in connected.connections where connection.status != .disconnected {
            do {
                let found = try await bank.refresh(itemID: connection.itemID)
                let now = Date()
                let debts = data.debts
                var taken = Set(connected.connections.flatMap(\.accounts).compactMap(\.debtID))
                updateConnected { state in
                    guard let c = state.connections.firstIndex(where: { $0.id == connection.id }) else { return }
                    state.connections[c].lastUpdate = now
                    if state.connections[c].status == .needsSignIn {
                        state.connections[c].status = .connected
                        state.connections[c].changedAt = now
                    }
                    for account in found {
                        if let a = state.connections[c].accounts.firstIndex(where: { $0.id == account.id }) {
                            state.connections[c].accounts[a].name = account.name
                            state.connections[c].accounts[a].mask = account.mask
                            state.connections[c].accounts[a].figures = account.figures
                        } else {
                            // An account opened at the bank since the sign-in.
                            let match = AppStore.match(account, at: connection.institution, among: debts, taken: taken)
                            if let match { taken.insert(match) }
                            state.connections[c].accounts.append(LinkedAccount(id: account.id, name: account.name, mask: account.mask,
                                                                               kind: account.kind, debtID: match, changedAt: now,
                                                                               figures: account.figures))
                        }
                    }
                }
            } catch BankError.needsSignIn {
                updateConnected { state in
                    guard let c = state.connections.firstIndex(where: { $0.id == connection.id }), state.connections[c].status == .connected else { return }
                    state.connections[c].status = .needsSignIn
                    state.connections[c].changedAt = Date()
                }
                result.problems.append("\(connection.institution) wants you to sign in again")
            } catch {
                result.problems.append("\(connection.institution) could not be reached")
            }
        }
        result.entries = applyBankFigures()
        result.waiting = bankQuestions.count
        return result
    }

    /// The same, at most once a day, for when the app comes to the front.
    @MainActor
    func refreshBanksIfDue() async {
        guard connectedOn else { return }
        let cutoff = Date().addingTimeInterval(-20 * 3600)
        let due = connected.connections.contains { $0.status == .connected && ($0.lastUpdate ?? .distantPast) < cutoff }
        if due { await refreshBanks() }
    }

    /// Takes the latest figures into every debt that follows its bank. Each change is one entry in the
    /// activity history, and the whole update is one step for Undo. Returns how many entries it added.
    @discardableResult
    func applyBankFigures() -> Int {
        guard connectedOn else { return 0 }
        var count = 0
        let today = today
        transaction("Bank update") {
            update { data in
                for connection in data.settings.connected.connections where connection.status == .connected {
                    for account in connection.accounts where account.isOn && account.source == .bank {
                        guard let debtID = account.debtID, let figures = account.figures else { continue }
                        if AppStore.take(figures, into: debtID, from: connection.institution, data: &data, today: today) { count += 1 }
                    }
                }
            }
        }
        return count
    }

    /// Sets one debt to what its bank reports, the way a statement check-in does, and records it.
    /// Returns false, and records nothing, when the bank and the app already agree.
    private static func take(_ figures: BankFigures, into debtID: UUID, from institution: String, data: inout AppData, today: Date) -> Bool {
        guard let i = data.debts.firstIndex(where: { $0.id == debtID }) else { return false }
        var d = data.debts[i]
        let before = d.state, terms = d.terms
        let balance = Limits.money(figures.balance).cents
        let change = (balance - d.balance).cents
        var notes: [String] = []

        // While a promotional rate is running the bank reports that one, and the app keeps both.
        if let apr = figures.apr, !d.hasPromo(on: today), abs(apr - d.apr) >= 0.005 {
            notes.append("APR \(Fmt.percent(d.apr)) to \(Fmt.percent(Limits.percent(apr)))")
            d.apr = Limits.percent(apr)
        }
        if let minimum = figures.minimum, minimum > 0, abs(minimum.cents - d.minimum.cents) >= 0.005 {
            notes.append("\(d.kind == .card ? "minimum" : "payment") \(d.minimum.usd) to \(Limits.money(minimum).cents.usd)")
            d.minimum = Limits.money(minimum).cents
        }
        if let day = figures.dueDay, figures.dueDayDiffers(from: d) {
            notes.append("due day \(Fmt.ordinal(d.dueDay)) to \(Fmt.ordinal(day))")
            d.moveDueDay(to: day)
        }
        if d.kind == .card, let limit = figures.creditLimit, limit > 0, abs(limit.cents - (d.creditLimit ?? 0).cents) >= 0.005 {
            notes.append("limit \(d.creditLimit.map(\.usd) ?? "not set") to \(Limits.money(limit).cents.usd)")
            d.creditLimit = Limits.money(limit).cents
        }
        guard abs(change) >= 0.005 || !notes.isEmpty else { return false }

        if d.isPaidOff && balance > 0.005 {
            d.paidOffAt = nil
            d.restartCycle(today: today)
        }
        d.balance = balance
        // What a statement adds to a card is new debt, like a charge, so it does not count against what has been paid.
        if d.kind == .card, change > 0 { d.startingBalance = (d.startingBalance + change).cents }
        if d.isPaidOff { d.paidOffAt = d.paidOffAt ?? today }
        d.statementThrough = today
        data.debts[i] = d

        // A statement's interest is named once, in the first update that sees that statement.
        var interest: Double?
        if let charged = figures.interestCharged, charged > 0.004 {
            let since = figures.statementDay.map(\.date) ?? Cal.monthStart(today)
            let counted = data.payments.contains { $0.debtID == debtID && $0.kind == .statement && $0.date >= since && ($0.interest ?? 0) > 0 }
            if !counted { interest = charged.cents }
        }
        data.payments.append(PaymentRecord(debtID: d.id, title: d.shortTitle, date: today, amount: change, kind: .statement, interest: interest,
                                           balanceAfter: d.balance, before: before, debtKind: d.kind, bank: institution,
                                           note: notes.isEmpty ? nil : notes.joined(separator: ", "), termsBefore: notes.isEmpty ? nil : terms))
        return true
    }
}
