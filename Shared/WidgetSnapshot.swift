import Foundation

/// Which debts a screen or widget is about.
enum DebtScope: String, Codable, CaseIterable, Identifiable {
    case total, cards, loans
    var id: String { rawValue }

    var title: String {
        switch self {
        case .total: "Total"
        case .cards: "Credit cards"
        case .loans: "Loans"
        }
    }

    var balanceLabel: String {
        switch self {
        case .total: "Total balance"
        case .cards: "Credit cards"
        case .loans: "Loans"
        }
    }

    /// The label over the month this scope reaches zero.
    var freeLabel: String {
        switch self {
        case .total: "Debt-free"
        case .cards: "Card-free"
        case .loans: "Loan-free"
        }
    }
}

/// The numbers a widget shows for one scope.
struct ScopeSnapshot: Codable, Equatable {
    var balance: Double
    /// Negative when the balance went down this month.
    var changeThisMonth: Double
    var nextDue: Date?
    var nextDueNames: String
    /// The month this scope reaches zero on the current plan.
    var free: Date?
    var fractionPaid: Double

    static let empty = ScopeSnapshot(balance: 0, changeThisMonth: 0, nextDue: nil, nextDueNames: "", free: nil, fractionPaid: 0)
}

/// Everything the widgets show. The app writes it to the shared app group whenever
/// data changes; the widget extension only reads it.
struct WidgetSnapshot: Codable, Equatable {
    var total: ScopeSnapshot
    var cards: ScopeSnapshot
    var loans: ScopeSnapshot
    /// The time zone the dates were written in, so the widget shows the same days the app does.
    var zone: String?

    /// The zone to show dates in.
    var timeZone: TimeZone { zone.flatMap(TimeZone.init(identifier:)) ?? .current }

    func scope(_ scope: DebtScope) -> ScopeSnapshot {
        switch scope {
        case .total: total
        case .cards: cards
        case .loans: loans
        }
    }

    static let appGroup = "group.com.edrichsilva.APRFree"
    private static let key = "widgetSnapshot.v2"

    static let empty = WidgetSnapshot(total: .empty, cards: .empty, loans: .empty)

    /// Shown in the widget gallery and before the app has saved anything.
    static let sample = WidgetSnapshot(
        total: ScopeSnapshot(balance: 42274.73, changeThisMonth: -174.63, nextDue: nil, nextDueNames: "Chase, Citi", free: nil, fractionPaid: 0.19),
        cards: ScopeSnapshot(balance: 8774.75, changeThisMonth: 0, nextDue: nil, nextDueNames: "Chase, Citi", free: nil, fractionPaid: 0.14),
        loans: ScopeSnapshot(balance: 32700.00, changeThisMonth: -124.64, nextDue: nil, nextDueNames: "Auto loan", free: nil, fractionPaid: 0.19))

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: raw)
    }

    func save() {
        guard let raw = try? JSONEncoder().encode(self) else { return }
        let defaults = UserDefaults(suiteName: Self.appGroup)
        defaults?.set(raw, forKey: Self.key)
        defaults?.removeObject(forKey: "widgetSnapshot")   // the single-scope snapshot from before widgets had options
    }
}
