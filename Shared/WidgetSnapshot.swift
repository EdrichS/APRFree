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
    var nextDue: Day?
    var nextDueNames: String
    /// The month this scope reaches zero on the current plan.
    var free: Day?
    var fractionPaid: Double

    static let empty = ScopeSnapshot(balance: 0, changeThisMonth: 0, nextDue: nil, nextDueNames: "", free: nil, fractionPaid: 0)
}

/// Everything the widgets show. The app writes it to the shared app group whenever
/// data changes; the widget extension only reads it.
struct WidgetSnapshot: Codable, Equatable {
    var total: ScopeSnapshot
    var cards: ScopeSnapshot
    var loans: ScopeSnapshot

    func scope(_ scope: DebtScope) -> ScopeSnapshot {
        switch scope {
        case .total: total
        case .cards: cards
        case .loans: loans
        }
    }

    static let appGroup = "group.com.edrichsilva.APRFree"
    private static let key = "widgetSnapshot.v3"
    private static let hiddenKey = "widgetBalancesHidden"

    /// Whether the widgets show dots in place of balances. Set from the widget itself with the eye button.
    static var balancesHidden: Bool {
        get { UserDefaults(suiteName: appGroup)?.bool(forKey: hiddenKey) ?? false }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: hiddenKey) }
    }

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
        // Snapshots in the formats earlier versions wrote.
        defaults?.removeObject(forKey: "widgetSnapshot")
        defaults?.removeObject(forKey: "widgetSnapshot.v2")
    }
}
