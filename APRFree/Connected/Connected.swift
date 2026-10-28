import Foundation

/// Connected mode: an optional way to let a bank fill in what is otherwise typed by hand.
///
/// It is off unless the user turns it on, and with it off the app talks to nothing. It only ever
/// reads: balances, rates, minimums, due dates and limits. It cannot move money, and nothing in the
/// app pays a bill.
///
/// What a bank reports never changes a debt quietly. It arrives as an entry in the activity
/// history, like a statement check-in, which can be seen, edited and undone. Where the bank and
/// the user disagree, both figures are shown and the user chooses once for that debt.
enum Connected {
    /// The date of the wording in `Legal.connected`. Turning the mode on records acceptance of it.
    static let termsVersion = "2026-10-06"

    /// The service this build talks to, or nil when it has none.
    ///
    /// A release build has none until the server described in PlaidPlan.txt exists. Until then the
    /// mode is not shown anywhere in it, and the app still makes no network request at all. Debug
    /// builds get a sample bank that makes its figures up on the iPhone, so the whole of the mode can
    /// be tried without a server or a real sign-in.
    static func service(for store: AppStore) -> BankService? {
        #if DEBUG
        return SampleBank(data: { [weak store] in store?.data ?? .empty(today: AppClock.today) }, today: { AppClock.today })
        #else
        return nil
        #endif
    }
}

/// Everything the app remembers about Connected mode. It belongs to this iPhone: it is left out of
/// backups, and undo never changes it.
struct ConnectedState: Codable, Equatable {
    /// Off by default.
    var isOn = false
    /// When the Connected mode terms were accepted, and which wording.
    var acceptedAt: Date?
    var acceptedVersion: String?
    var connections: [Connection] = []

    /// Debts a bank is keeping up to date right now, so they need no monthly check-in by hand.
    var bankFedDebts: Set<UUID> {
        guard isOn else { return [] }
        var out: Set<UUID> = []
        for connection in connections where connection.status == .connected {
            for account in connection.accounts where account.isOn && account.source == .bank {
                if let id = account.debtID { out.insert(id) }
            }
        }
        return out
    }
}

/// One sign-in at one bank. It holds no secret: the key that lets the bank be read stays on the
/// server and is never sent to the iPhone.
struct Connection: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case connected
        /// The bank wants the user to sign in again before it gives anything more.
        case needsSignIn
        /// Disconnected by the user. The server has been told to forget it.
        case disconnected

        var title: String {
            switch self {
            case .connected: "Connected"
            case .needsSignIn: "Sign in again"
            case .disconnected: "Disconnected"
            }
        }
    }

    var id = UUID()
    /// The server's name for this sign-in.
    var itemID: String
    var institution: String
    var status = Status.connected
    var addedAt: Date
    /// The last time the connection itself changed: connected, disconnected, signed in again.
    var changedAt: Date
    /// The last time figures were fetched for it.
    var lastUpdate: Date?
    var accounts: [LinkedAccount] = []
}

/// One account at the bank, and the debt in the app it feeds.
struct LinkedAccount: Identifiable, Codable, Hashable {
    /// Whose figures win for the debt this account feeds. Asked once, the first time they differ.
    enum Source: String, Codable {
        case undecided, bank, mine
    }

    /// The bank's own name for the account.
    var id: String
    var name: String
    /// The last few digits, as the bank shows them. Never the whole number.
    var mask: String?
    var kind: DebtKind
    /// Off means the account is listed but nothing is taken from it.
    var isOn = true
    var debtID: UUID?
    var source = Source.undecided
    /// The last time anything about this account was changed here: switched, linked, or the choice made.
    var changedAt: Date
    /// What the bank last reported.
    var figures: BankFigures?
}

/// What a bank reports about one account.
struct BankFigures: Codable, Hashable {
    var balance: Double
    var apr: Double?
    var minimum: Double?
    var nextDue: Day?
    var creditLimit: Double?
    var statementBalance: Double?
    var statementDay: Day?
    /// Interest charged on the last statement.
    var interestCharged: Double?
    var lastPayment: Double?
    var lastPaymentDay: Day?
    var asOf: Date

    /// The day of the month the account is due on, read off its next due date.
    var dueDay: Int? { nextDue?.day }

    /// True when the bank's next due date is not where the app's own due day would put it that
    /// month. Comparing whole dates keeps a due day of the 31st from looking wrong in a short month.
    func dueDayDiffers(from debt: Debt) -> Bool {
        guard let nextDue, debt.kind != .payLater else { return false }
        return Day.inMonth(nextDue.monthIndex, day: debt.dueDay) != nextDue
    }
}

/// An account as the service hands it over.
struct BankAccount: Hashable {
    var id: String
    var name: String
    var mask: String?
    var kind: DebtKind
    var figures: BankFigures
}

/// The result of a sign-in.
struct BankLink {
    var itemID: String
    var institution: String
    var accounts: [BankAccount]
}

enum BankError: LocalizedError {
    case needsSignIn
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .needsSignIn: "The bank wants you to sign in again."
        case .unavailable(let why): why
        }
    }
}

/// Whatever sits between the app and the banks. The real one will be a small server in front of
/// Plaid (see PlaidPlan.txt); the sample one below makes its figures up.
protocol BankService: AnyObject {
    /// "Plaid", "Sample bank".
    var name: String { get }
    /// True when nothing leaves the iPhone because there is no bank behind it.
    var isSample: Bool { get }
    /// Banks that can be offered in a list. Empty when the service shows its own picker.
    func institutions() async throws -> [String]
    /// Signs in and lists the accounts found. Nil lets the service ask which bank.
    func connect(institution: String?) async throws -> BankLink
    /// The current figures for every account of a sign-in.
    func refresh(itemID: String) async throws -> [BankAccount]
    /// Tells the server to forget a sign-in and the key that went with it.
    func disconnect(itemID: String) async throws
}

/// One figure the bank and the app do not agree on.
struct BankDifference: Identifiable, Hashable {
    var id: String { field }
    var field: String
    var mine: String
    var bank: String
}

extension BankFigures {
    /// Where these figures differ from what the app has for a debt.
    func differences(from debt: Debt, on today: Date) -> [BankDifference] {
        var out: [BankDifference] = []
        if abs(balance.cents - debt.balance.cents) >= 0.005 {
            out.append(BankDifference(field: "Balance", mine: debt.balance.usd, bank: balance.usd))
        }
        // While a promotional rate is running the bank reports that one, and the app keeps both.
        if let apr, !debt.hasPromo(on: today), abs(apr - debt.apr) >= 0.005 {
            out.append(BankDifference(field: "APR", mine: Fmt.percent(debt.apr), bank: Fmt.percent(apr)))
        }
        if let minimum, minimum > 0, abs(minimum.cents - debt.minimum.cents) >= 0.005 {
            out.append(BankDifference(field: debt.kind == .card ? "Minimum payment" : "Monthly payment", mine: debt.minimum.usd, bank: minimum.usd))
        }
        if let dueDay, dueDayDiffers(from: debt) {
            out.append(BankDifference(field: "Due day", mine: Fmt.ordinal(debt.dueDay), bank: Fmt.ordinal(dueDay)))
        }
        if debt.kind == .card, let creditLimit, creditLimit > 0, abs(creditLimit.cents - (debt.creditLimit ?? 0).cents) >= 0.005 {
            out.append(BankDifference(field: "Credit limit", mine: debt.creditLimit.map(\.usd) ?? "Not set", bank: creditLimit.usd))
        }
        return out
    }
}

// MARK: - Sample bank

#if DEBUG
/// A stand-in for a real bank, for trying Connected mode before the server exists. Nothing is sent
/// anywhere: it reads the debts already in the app and answers the way their banks might.
///
/// Its one habit is the thing the mode is for. Once a month it charges each card a month of
/// interest, and keeps reporting the higher balance until the app has taken it in.
///
/// Debug builds only: it is not compiled into a release build at all.
final class SampleBank: BankService {
    let name = "Sample bank"
    let isSample = true

    private let data: () -> AppData
    private let today: () -> Date
    /// Lets a test decide what the bank says about a debt.
    var adjust: ((Debt, inout BankFigures) -> Void)?
    /// Sign-ins that should be answered with "sign in again", for trying that state.
    var expired: Set<String> = []

    init(data: @escaping () -> AppData, today: @escaping () -> Date) {
        self.data = data
        self.today = today
    }

    private func offered(_ debt: Debt) -> Bool {
        debt.kind != .payLater && !institution(of: debt).isEmpty
    }

    private func institution(of debt: Debt) -> String {
        debt.provider.trimmingCharacters(in: .whitespaces)
    }

    func institutions() async throws -> [String] {
        var seen: [String] = []
        for debt in data().debts where offered(debt) && !seen.contains(institution(of: debt)) { seen.append(institution(of: debt)) }
        return seen
    }

    func connect(institution: String?) async throws -> BankLink {
        guard let institution, !institution.isEmpty else { throw BankError.unavailable("Choose a bank to sign in to.") }
        let accounts = accounts(at: institution)
        guard !accounts.isEmpty else { throw BankError.unavailable("The sample bank has no accounts for \(institution).") }
        return BankLink(itemID: "sample-\(institution.lowercased().filter { $0.isLetter || $0.isNumber })", institution: institution, accounts: accounts)
    }

    func refresh(itemID: String) async throws -> [BankAccount] {
        if expired.contains(itemID) { throw BankError.needsSignIn }
        let all = data().debts.filter(offered)
        guard let institution = all.map(institution(of:)).first(where: { "sample-\($0.lowercased().filter { $0.isLetter || $0.isNumber })" == itemID }) else {
            return []
        }
        return accounts(at: institution)
    }

    func disconnect(itemID: String) async throws {}

    private func accounts(at institution: String) -> [BankAccount] {
        let data = data()
        return data.debts.filter { offered($0) && self.institution(of: $0) == institution }.map { debt in
            BankAccount(id: "sample-\(debt.id.uuidString.prefix(8))", name: debt.kind == .loan ? debt.title : (debt.name.isEmpty ? "Credit card" : debt.name),
                        mask: String(debt.id.uuidString.filter(\.isNumber).suffix(4)), kind: debt.kind, figures: figures(for: debt, in: data))
        }
    }

    private func figures(for debt: Debt, in data: AppData) -> BankFigures {
        let today = today()
        let month = Cal.monthStart(today)
        // This month's interest is waiting until a check-in or a bank update has recorded it.
        let taken = data.payments.contains { $0.debtID == debt.id && $0.kind == .statement && $0.date >= month }
        let interest = debt.kind == .card && !debt.isPaidOff ? debt.monthlyInterest(on: today).cents : 0
        let lastPaid = data.payments.last { $0.debtID == debt.id && $0.isPayment }
        var out = BankFigures(balance: (debt.balance + (taken ? 0 : interest)).cents, apr: debt.apr(on: today), minimum: debt.minimum,
                              nextDue: debt.nextUnpaidDue().map { Day($0) }, creditLimit: debt.creditLimit,
                              statementBalance: (debt.balance + (taken ? 0 : interest)).cents, statementDay: Day(month),
                              interestCharged: interest > 0 ? interest : nil, lastPayment: lastPaid?.amount,
                              lastPaymentDay: lastPaid.map { Day($0.date) }, asOf: Date())
        adjust?(debt, &out)
        return out
    }
}
#endif
