import Foundation

enum PayFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly, biweekly, monthly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }

    /// "Twice a month" used to be an option. Data saved with it loads as every two weeks
    /// instead of failing to load at all.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PayFrequency(rawValue: raw) ?? .biweekly
    }
}

/// Where extra money goes first.
enum Strategy: String, Codable, CaseIterable, Identifiable {
    /// Highest APR first. For a fixed amount paid, no order costs less interest.
    case avalanche
    /// Smallest balance first.
    case snowball
    /// Biggest monthly interest charge in dollars first (balance x APR / 12), so large balances lead.
    case highestBalance
    /// The user's own order.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avalanche: "Avalanche"
        case .snowball: "Snowball"
        case .highestBalance: "Highest Balance"
        case .custom: "Custom"
        }
    }

    var blurb: String {
        switch self {
        case .avalanche: "Highest APR first. Saves the most."
        case .snowball: "Smallest balance first. Quickest wins."
        case .highestBalance: "Biggest monthly interest charge first."
        case .custom: "Your own order."
        }
    }

    var symbol: String {
        switch self {
        case .avalanche: "percent"
        case .snowball: "flag"
        case .highestBalance: "dollarsign"
        case .custom: "line.3.horizontal"
        }
    }
}

struct PlanSettings: Codable, Equatable {
    var payFrequency: PayFrequency = .biweekly
    var nextPayday: Date
    var payAmount: Double = 0
    /// Money Make a Payment always leaves alone.
    var buffer: Double = 0
    var strategy: Strategy = .avalanche
    /// Extra-payment order when the strategy is Custom.
    var customOrder: [UUID] = []
    /// 0% promo cards get the minimum only until the promo ends.
    var promoMinimumOnly = true
    /// Added on the first payday of each month (set from the Simulator).
    var extraMonthly: Double = 0
    var remindDueDates = false
    var remindPaydays = false
    var lastBackup: Date?
    var onboarded = false
    /// For monthly pay: the day of the month the user is paid on. Kept separately because the stored
    /// next payday gets shortened in short months (the 31st is paid on Feb 28, then on Mar 31 again).
    var paydayAnchorDay: Int?
}

extension PlanSettings {
    /// The payday rhythm, numbered so `date(0)` is the first payday on or after `today`.
    func paydays(from today: Date) -> PaydaySequence {
        PaydaySequence(first: nextPayday, frequency: payFrequency, anchorDay: paydayAnchorDay).starting(onOrAfter: today)
    }

    /// Records the next payday the user picked, and with it the day of the month they are paid on.
    mutating func setNextPayday(_ date: Date) {
        nextPayday = Cal.startOfDay(date)
        paydayAnchorDay = Cal.day(of: date)
    }
}

/// The largest values a field accepts: far beyond any real debt, small enough that the math stays finite.
enum Limits {
    static let money = 999_999_999.99
    static let percent = 999.99
    static let installments = 600

    static func money(_ value: Double) -> Double { min(max(0, value), money) }
    static func percent(_ value: Double) -> Double { min(max(0, value), percent) }
}

struct AppData: Codable, Equatable {
    var version = 1
    var debts: [Debt] = []
    var payments: [PaymentRecord] = []
    /// Total balance over time, one point per day it changed.
    var history: [BalancePoint] = []
    var settings: PlanSettings
    /// The time zone the dates above were written in. Only set in a saved file or a backup;
    /// `Persistence.read` uses it and clears it.
    var timeZone: String?

    static func empty(today: Date) -> AppData {
        AppData(settings: PlanSettings(nextPayday: today))
    }

    /// Keeps numbers read from a file inside the ranges the forms allow, so a damaged or hand-edited
    /// backup cannot stall the app or send the math somewhere it was never meant to go.
    mutating func sanitize() {
        for i in debts.indices {
            var d = debts[i]
            d.balance = Limits.money(d.balance).cents
            d.startingBalance = Limits.money(d.startingBalance).cents
            d.minimum = Limits.money(d.minimum).cents
            d.apr = Limits.percent(d.apr)
            d.dueDay = min(max(1, d.dueDay), 31)
            d.creditLimit = d.creditLimit.map(Limits.money)
            d.promoAPR = d.promoAPR.map(Limits.percent)
            d.total = d.total.map(Limits.money)
            d.originalAmount = d.originalAmount.map(Limits.money)
            d.installments = d.installments.map { min(max(1, $0), Limits.installments) }
            d.paidInstallments = d.paidInstallments.map { min(max(0, $0), d.installments ?? Limits.installments) }
            d.paidTowardDue = d.paidTowardDue.map(Limits.money)
            d.interestTowardDue = d.interestTowardDue.map(Limits.money)
            debts[i] = d
        }
        settings.payAmount = Limits.money(settings.payAmount)
        settings.buffer = Limits.money(settings.buffer)
        settings.extraMonthly = Limits.money(settings.extraMonthly)
        settings.paydayAnchorDay = settings.paydayAnchorDay.map { min(max(1, $0), 31) }
    }
}
