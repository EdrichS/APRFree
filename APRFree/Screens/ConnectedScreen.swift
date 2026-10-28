import SwiftUI

extension Legal {
    /// What turning Connected mode on means. Shown, and accepted, before the mode is switched on.
    static func connected(sample: Bool) -> Document {
        var sections: [Section] = []
        if sample {
            sections.append(Section(title: "This build: a sample bank",
                                    paragraphs: ["This build has no server, so it connects to nothing. The “banks” it offers are made up on this iPhone from the debts you entered, to let you try the mode. Nothing is sent anywhere. The rest of this page describes the mode as it will work with real banks."]))
        }
        sections += [
            Section(title: "What changes when it is on",
                    points: ["You sign in to your bank in a window run by Plaid, a service banks use for this. APRFree never sees or keeps your bank user name or password.",
                             "A small server run by the developer keeps one thing for each bank you connect: the key Plaid gives it to read your accounts. It passes your figures to this iPhone when the app asks, and keeps no copy of your balances, payments or transactions.",
                             "What is read, for credit cards and loans: the account’s name and the last digits of its number, its balance, credit limit, interest rates, minimum payment, next due date, and its last statement and last payment. Nothing else is asked for.",
                             "Plaid handles what passes through it under its own privacy policy, which you are shown when you sign in."]),
            Section(title: "What does not change",
                    points: ["Everything you enter still lives on this iPhone.",
                             "APRFree still cannot pay anything or move money. Connected mode only reads.",
                             "There is still no advertising, no analytics and no selling or sharing of your information."]),
            Section(title: "How a bank’s figures are used",
                    points: ["Nothing a bank reports changes a debt quietly. Each change arrives as a “Bank update” entry in Activity, which you can see, edit or undo.",
                             "The first time a bank’s figures differ from yours, APRFree shows both and asks once, for that debt, whose to follow. You can change the answer at any time.",
                             "A card that follows its bank no longer needs a monthly statement check-in."]),
            Section(title: "Stopping",
                    points: ["Disconnect a bank on the Connected screen and the server is told to delete its key for that bank.",
                             "Turning Connected mode off disconnects every bank. Entries already recorded stay in your history.",
                             "Reset Everything disconnects every bank too."]),
            Section(title: "Accuracy",
                    paragraphs: ["A bank’s figures can be late, incomplete or wrong, and some banks do not report every figure. Your statement is still the one that counts."]),
        ]
        return Document(title: "Connected Mode",
                        summary: "Connected mode is optional and off until you turn it on. With it on, APRFree reads balances and terms from the banks you sign in to. It cannot move money.",
                        accept: "I understand, and want to turn on Connected mode", sections: sections)
    }
}

private extension Date {
    /// "Oct 6, 2026, 9:41 AM"
    var stamp: String { formatted(.dateTime.month(.abbreviated).day().year().hour().minute()) }
}

/// Connected: the switch for the mode, every bank that is or was connected, and anything waiting
/// for a choice.
struct ConnectedContent: View {
    @Environment(AppStore.self) private var store
    @State private var showingTerms = false
    @State private var confirmingOff = false
    @State private var offering: [String]?
    @State private var busy = false
    @State private var result: String?
    @State private var problem: String?

    private var state: ConnectedState { store.connected }

    var body: some View {
        Form {
            Section {
                Toggle("Connected mode", isOn: Binding(get: { state.isOn }, set: { on in
                    if on {
                        showingTerms = true
                    } else if state.connections.contains(where: { $0.status != .disconnected }) {
                        confirmingOff = true
                    } else {
                        Task { await store.turnOffConnected() }
                    }
                }))
                .toggleStyle(NeutralToggleStyle())
            } footer: {
                Text(state.isOn
                     ? "On. APRFree reads balances and terms from the banks below. It never moves money."
                     : "Off, as it is unless you turn it on. With it off APRFree talks to nothing, and everything works the way it always has.")
            }
            if store.bank?.isSample == true {
                Section {
                    Label("Sample bank. This build has no server: the figures are made up on this iPhone from the debts you entered, and nothing is sent anywhere.", systemImage: "testtube.2")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            if state.isOn { questions }
            banks
            if state.isOn { actions }
            Section {
                NavigationLink("How Connected Mode Works") { LegalReader(document: Legal.connected(sample: store.bank?.isSample == true)) }
            }
        }
        .sheet(isPresented: $showingTerms) {
            ConnectedTerms().tint(Theme.primaryFill)
        }
        .sheet(isPresented: Binding(get: { offering != nil }, set: { if !$0 { offering = nil } })) {
            BankPicker(banks: offering ?? []) { name in
                offering = nil
                connect(name)
            }
            .tint(Theme.primaryFill)
        }
        .alert("Turn off Connected mode?", isPresented: $confirmingOff) {
            Button("Turn Off and Disconnect", role: .destructive) {
                Task {
                    let failed = await store.turnOffConnected()
                    if !failed.isEmpty { problem = "\(failed.formatted(.list(type: .and))) could not be disconnected just now, so Connected mode is still on. Try again when you are online." }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every bank is disconnected and the server is told to forget them. Entries already in your history stay.")
        }
        .alert("Connected", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: Waiting for a choice

    @ViewBuilder private var questions: some View {
        let waiting = store.bankQuestions
        if !waiting.isEmpty {
            Section {
                ForEach(waiting) { question in
                    QuestionCard(question: question)
                }
            } header: {
                Text("Your figures and the bank’s differ")
            } footer: {
                Text("Choose once for each debt. Following the bank adds a “Bank update” entry to Activity each time its figures change; you can undo any of them. Keeping yours leaves the debt exactly as it is.")
            }
        }
    }

    // MARK: Banks

    @ViewBuilder private var banks: some View {
        if !state.connections.isEmpty {
            Section {
                ForEach(state.connections) { connection in
                    NavigationLink {
                        ConnectionDetail(connectionID: connection.id)
                    } label: {
                        ConnectionRow(connection: connection)
                    }
                }
            } header: {
                Text("Banks")
            } footer: {
                Text("Tap a bank to see its accounts, which debt each one feeds, and when it was added and last changed.")
            }
        }
    }

    private var actions: some View {
        Section {
            Button {
                Task {
                    let names = await store.banksToOffer()
                    // A service with its own picker, as Plaid has, is simply asked to connect.
                    if names.isEmpty && store.bank?.isSample != true { connect(nil) } else { offering = names }
                }
            } label: {
                Label("Connect a Bank", systemImage: "plus")
            }
            .disabled(busy)
            if state.connections.contains(where: { $0.status != .disconnected }) {
                Button {
                    busy = true
                    Task {
                        result = await store.refreshBanks().summary
                        busy = false
                    }
                } label: {
                    Label("Update Now", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            }
        } footer: {
            if let result { Text(result) }
        }
    }

    private func connect(_ name: String?) {
        busy = true
        Task {
            do {
                try await store.connectBank(name)
                let waiting = store.bankQuestions.count
                result = waiting > 0 ? "Connected. \(Fmt.plural(waiting, "debt")) waiting for your choice above." : "Connected."
            } catch {
                problem = error.localizedDescription
            }
            busy = false
        }
    }
}

/// One bank in the list: its name, how it stands, and when it last gave figures.
private struct ConnectionRow: View {
    let connection: Connection

    private var symbol: String {
        switch connection.status {
        case .connected: "checkmark.circle"
        case .needsSignIn: "exclamationmark.circle"
        case .disconnected: "minus.circle"
        }
    }

    private var detail: String {
        let accounts = Fmt.plural(connection.accounts.count, "account")
        switch connection.status {
        case .connected: return "\(accounts) · updated \(connection.lastUpdate?.stamp ?? "never")"
        case .needsSignIn: return "\(accounts) · sign in again to carry on"
        case .disconnected: return "Disconnected \(connection.changedAt.stamp)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(connection.status == .disconnected ? Theme.tertiary : Color.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(connection.institution).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(connection.institution), \(connection.status.title). \(detail)")
    }
}

/// A debt whose figures differ from its bank's: both, side by side, and the one choice.
private struct QuestionCard: View {
    @Environment(AppStore.self) private var store
    let question: BankQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(question.debt.title).font(.callout.weight(.semibold))
                Text("\(question.institution) · \(question.account.name)").font(.caption).foregroundStyle(Theme.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Yours").gridColumnAlignment(.trailing)
                    Text("Bank").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                ForEach(question.differences) { difference in
                    GridRow {
                        Text(difference.field).frame(maxWidth: .infinity, alignment: .leading)
                        Text(difference.mine).monospacedDigit()
                        Text(difference.bank).monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(difference.field): yours \(difference.mine), the bank’s \(difference.bank)")
                }
            }
            HStack(spacing: 10) {
                Button("Keep Mine") { store.follow(.mine, account: question.account.id, in: question.connectionID) }
                    .buttonStyle(ChoiceButtonStyle(filled: false))
                Button("Use the Bank’s") { store.follow(.bank, account: question.account.id, in: question.connectionID) }
                    .buttonStyle(ChoiceButtonStyle(filled: true))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ChoiceButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(filled ? Theme.onPrimary : Color.primary)
            .background(filled ? Theme.primaryFill : Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - One bank

/// One bank: how it stands, when it was added and changed, and each of its accounts.
struct ConnectionDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let connectionID: UUID
    @State private var confirmingDisconnect = false
    @State private var problem: String?
    @State private var busy = false

    private var connection: Connection? { store.connected.connections.first { $0.id == connectionID } }

    var body: some View {
        Form {
            if let connection {
                Section {
                    LabeledContent("Status", value: connection.status.title)
                    LabeledContent("Added", value: connection.addedAt.stamp)
                    LabeledContent(connection.status == .disconnected ? "Disconnected" : "Changed", value: connection.changedAt.stamp)
                    LabeledContent("Last update", value: connection.lastUpdate?.stamp ?? "Never")
                    LabeledContent("Through", value: store.bank?.name ?? "Not available")
                } footer: {
                    Text(note(connection))
                }
                ForEach(connection.accounts) { account in
                    AccountSection(connection: connection, account: account)
                }
                Section {
                    switch connection.status {
                    case .connected:
                        Button("Disconnect \(connection.institution)", role: .destructive) { confirmingDisconnect = true }
                    case .needsSignIn:
                        Button("Sign In Again") { reconnect(connection) }
                        Button("Disconnect \(connection.institution)", role: .destructive) { confirmingDisconnect = true }
                    case .disconnected:
                        if store.connected.isOn { Button("Connect Again") { reconnect(connection) } }
                        Button("Remove from This List", role: .destructive) {
                            store.removeConnection(connection.id)
                            dismiss()
                        }
                    }
                }
                .disabled(busy)
            }
        }
        .navigationTitle(connection?.institution ?? "Bank")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disconnect \(connection?.institution ?? "this bank")?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                busy = true
                Task {
                    do { try await store.disconnect(connectionID) } catch { problem = "The server could not be reached, so the bank is still connected. Try again when you are online." }
                    busy = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server is told to forget this bank. Its debts stay as they are, and entries already in your history are kept.")
        }
        .alert("Connected", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    private func note(_ connection: Connection) -> String {
        switch connection.status {
        case .connected: "APRFree can read the accounts below. It cannot move money."
        case .needsSignIn: "The bank has stopped giving figures until you sign in again. Nothing has been lost."
        case .disconnected: "Nothing is read from this bank. It is kept here as a record until you remove it."
        }
    }

    private func reconnect(_ connection: Connection) {
        busy = true
        Task {
            do { try await store.connectBank(connection.institution) } catch { problem = error.localizedDescription }
            busy = false
        }
    }
}

/// One account at a bank: whether it is used, the debt it feeds, whose figures win, and what the
/// bank last said.
private struct AccountSection: View {
    @Environment(AppStore.self) private var store
    let connection: Connection
    let account: LinkedAccount

    private var live: Bool { connection.status == .connected && store.connected.isOn }

    var body: some View {
        Section {
            Toggle("Use this account", isOn: Binding(get: { account.isOn }, set: { store.setAccount(account.id, in: connection.id, isOn: $0) }))
                .toggleStyle(NeutralToggleStyle())
                .disabled(!live)
            if account.isOn {
                Picker("Feeds", selection: Binding(get: { account.debtID }, set: { store.link(account.id, in: connection.id, to: $0) })) {
                    Text("Nothing yet").tag(UUID?.none)
                    ForEach(store.debts(for: account)) { debt in
                        Text(debt.detail.isEmpty ? debt.title : "\(debt.title) · \(debt.detail)").tag(UUID?.some(debt.id))
                    }
                }
                .disabled(!live)
                if account.debtID.flatMap(store.debt) != nil {
                    Picker("Follow", selection: Binding(get: { account.source }, set: { store.follow($0, account: account.id, in: connection.id) })) {
                        if account.source == .undecided { Text("Not chosen yet").tag(LinkedAccount.Source.undecided) }
                        Text("The bank’s figures").tag(LinkedAccount.Source.bank)
                        Text("My own figures").tag(LinkedAccount.Source.mine)
                    }
                    .disabled(!live)
                }
            }
            if let figures = account.figures {
                LabeledContent("Balance at the bank", value: figures.balance.usd)
                if let minimum = figures.minimum, minimum > 0 {
                    LabeledContent(account.kind == .card ? "Minimum" : "Payment",
                                   value: figures.nextDue.map { "\(minimum.usd), due \(Fmt.monthDay($0.date))" } ?? minimum.usd)
                }
                if let apr = figures.apr { LabeledContent("APR", value: Fmt.percent(apr)) }
                if let limit = figures.creditLimit, limit > 0 { LabeledContent("Credit limit", value: limit.usd) }
                if let interest = figures.interestCharged, interest > 0 { LabeledContent("Interest on the last statement", value: interest.usd) }
            }
        } header: {
            Text([account.name, account.mask.map { "•••• \($0)" }].compactMap { $0 }.joined(separator: " "))
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let changed = "Changed \(account.changedAt.stamp)."
        guard account.isOn else { return "Not used: nothing is taken from this account. \(changed)" }
        guard let debt = account.debtID.flatMap(store.debt) else { return "Not linked to a debt yet, so nothing is taken from it. \(changed)" }
        switch account.source {
        case .bank: return "\(debt.title) follows the bank: each change arrives as a Bank update in Activity. \(changed)"
        case .mine: return "\(debt.title) keeps your own figures. The bank’s are shown here for reference only. \(changed)"
        case .undecided: return "\(debt.title) is waiting for you to choose whose figures to follow. \(changed)"
        }
    }
}

// MARK: - Sheets

/// What the mode means, to be accepted before it is turned on.
private struct ConnectedTerms: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false

    var body: some View {
        let document = Legal.connected(sample: store.bank?.isSample == true)
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LegalText(document: document)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .padding(.horizontal, Theme.margin)
                        .padding(.vertical, 8)
                }
                VStack(spacing: 10) {
                    LegalAcceptRow(text: document.accept, accepted: $accepted)
                    Button("Turn On Connected Mode") {
                        store.turnOnConnected()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!accepted)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 8)
            }
            .background(Theme.bg)
            .navigationTitle("Connected Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The list of banks a service can offer, for one that has no picker of its own.
private struct BankPicker: View {
    @Environment(\.dismiss) private var dismiss
    let banks: [String]
    let choose: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if banks.isEmpty {
                    Text("There is no other bank to connect. The sample bank offers the lenders of the cards and loans you have entered.")
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(banks, id: \.self) { name in
                    Button(name) { choose(name) }
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Connect a Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
