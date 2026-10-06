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
    /// The user's own order.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avalanche: "Avalanche"
        case .snowball: "Snowball"
        case .custom: "Custom"
        }
    }

    var blurb: String {
        switch self {
        case .avalanche: "Highest APR first. Saves the most."
        case .snowball: "Smallest balance first. Quickest wins."
        case .custom: "Your own order."
        }
    }

    var symbol: String {
        switch self {
        case .avalanche: "percent"
        case .snowball: "flag"
        case .custom: "line.3.horizontal"
        }
    }

    /// "Highest Balance" used to be a fourth strategy. Data saved with it loads as Avalanche.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Strategy(rawValue: raw) ?? .avalanche
    }
}

/// One source of income and the rhythm it arrives on.
struct Income: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "Paycheck"
    /// What arrives each payday.
    var amount = 0.0
    var frequency = PayFrequency.biweekly
    /// The next payday that has not been split yet. Weekly and every-two-weeks pay repeats from it,
    /// so the weekday never changes.
    @AsDay var nextPayday: Date
    /// Monthly pay: the days of the month it lands on, one or more. A day past the end of a short
    /// month means that month's last day. Empty means the day of `nextPayday`.
    var monthDays: [Int] = []

    /// The days of the month a monthly income is paid on, in order.
    var payDays: [Int] {
        let days = monthDays.isEmpty ? [Cal.day(of: nextPayday)] : monthDays
        return Array(Set(days.map { min(max(1, $0), 31) })).sorted()
    }

    /// "Every other Friday", "The 1st and 15th of every month".
    var rhythm: String {
        switch frequency {
        case .weekly: return "Every \(Fmt.weekdayName(nextPayday))"
        case .biweekly: return "Every other \(Fmt.weekdayName(nextPayday))"
        case .monthly:
            let days = payDays.map { $0 >= 31 ? "last day" : Fmt.ordinal($0) }
            let list = days.count > 1 ? days.dropLast().joined(separator: ", ") + " and " + (days.last ?? "") : (days.first ?? "")
            return list == "last day" ? "The last day of every month" : "The \(list) of every month"
        }
    }
}

struct PlanSettings: Codable, Equatable {
    /// Every income, each on its own rhythm.
    var incomes: [Income] = []
    /// When on, the plan uses one fixed amount a month instead of the incomes above.
    var useFixedAmount = false
    var fixedAmount = 0.0
    /// The day of the month the fixed amount is paid on.
    var fixedDay = 1
    /// The next fixed-amount date that has not been used yet.
    @AsOptionalDay var fixedNext: Date? = nil
    /// Money Make a Payment leaves alone out of every paycheck.
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
    /// When the privacy policy and the disclaimer were accepted, and which wording.
    var acceptedPrivacy: Date?
    var acceptedDisclaimer: Date?
    var acceptedLegalVersion: String?
    /// Things the app changed on its own and still has to tell the user about, shown once.
    var notices: [String] = []

    init() {}

    /// Settings with a single income: what first-run setup produces.
    init(nextPayday: Date, payFrequency: PayFrequency = .biweekly, payAmount: Double = 0, buffer: Double = 0) {
        incomes = [Income(amount: payAmount, frequency: payFrequency, nextPayday: nextPayday)]
        self.buffer = buffer
    }

    // Settings saved before there could be more than one income.
    private enum Legacy: String, CodingKey {
        case payFrequency, nextPayday, payAmount, paydayAnchorDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useFixedAmount = try c.decodeIfPresent(Bool.self, forKey: .useFixedAmount) ?? false
        fixedAmount = try c.decodeIfPresent(Double.self, forKey: .fixedAmount) ?? 0
        fixedDay = try c.decodeIfPresent(Int.self, forKey: .fixedDay) ?? 1
        _fixedNext = try c.decode(AsOptionalDay.self, forKey: .fixedNext)
        buffer = try c.decodeIfPresent(Double.self, forKey: .buffer) ?? 0
        strategy = try c.decodeIfPresent(Strategy.self, forKey: .strategy) ?? .avalanche
        customOrder = try c.decodeIfPresent([UUID].self, forKey: .customOrder) ?? []
        promoMinimumOnly = try c.decodeIfPresent(Bool.self, forKey: .promoMinimumOnly) ?? true
        extraMonthly = try c.decodeIfPresent(Double.self, forKey: .extraMonthly) ?? 0
        remindDueDates = try c.decodeIfPresent(Bool.self, forKey: .remindDueDates) ?? false
        remindPaydays = try c.decodeIfPresent(Bool.self, forKey: .remindPaydays) ?? false
        lastBackup = try c.decodeIfPresent(Date.self, forKey: .lastBackup)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        acceptedPrivacy = try c.decodeIfPresent(Date.self, forKey: .acceptedPrivacy)
        acceptedDisclaimer = try c.decodeIfPresent(Date.self, forKey: .acceptedDisclaimer)
        acceptedLegalVersion = try c.decodeIfPresent(String.self, forKey: .acceptedLegalVersion)
        notices = try c.decodeIfPresent([String].self, forKey: .notices) ?? []
        if let saved = try c.decodeIfPresent([Income].self, forKey: .incomes) {
            incomes = saved
        } else {
            // One payday schedule becomes one income, keeping its rhythm and the day of the month it lands on.
            let old = try decoder.container(keyedBy: Legacy.self)
            guard let next = try old.decodeIfPresent(Day.self, forKey: .nextPayday) else { return }
            let frequency = try old.decodeIfPresent(PayFrequency.self, forKey: .payFrequency) ?? .biweekly
            let anchor = try old.decodeIfPresent(Int.self, forKey: .paydayAnchorDay)
            var income = Income(amount: try old.decodeIfPresent(Double.self, forKey: .payAmount) ?? 0, frequency: frequency,
                                nextPayday: next.date)
            if frequency == .monthly { income.monthDays = [max(anchor ?? next.day, next.day)] }
            incomes = [income]
        }
    }
}

extension PlanSettings {
    static let fixedIncomeID = UUID(uuidString: "00000000-0000-0000-0000-00000000F1ED") ?? UUID()

    /// The income the plan runs on: every income, or the one fixed monthly amount standing in for them.
    func activeIncomes(today: Date) -> [Income] {
        guard useFixedAmount else { return incomes }
        let first = fixedNext.map { max($0, today) } ?? today
        return [Income(id: PlanSettings.fixedIncomeID, name: "Monthly amount", amount: fixedAmount, frequency: .monthly,
                       nextPayday: Day.next(dayOfMonth: fixedDay, onOrAfter: Day(first)).date, monthDays: [fixedDay])]
    }

    /// What is held back out of each paycheck. A fixed monthly amount is already the amount for debt.
    var activeBuffer: Double { useFixedAmount ? 0 : buffer }

    /// The paydays the plan and Make a Payment work from, with the buffer taken out of each one.
    func schedule(today: Date) -> PaySchedule {
        PaySchedule(incomes: activeIncomes(today: today), buffer: activeBuffer)
    }

    /// True when both the privacy policy and the disclaimer have been accepted in their current wording.
    var hasAcceptedLegal: Bool {
        acceptedPrivacy != nil && acceptedDisclaimer != nil && acceptedLegalVersion == Legal.version
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
    /// 2: dates saved as calendar days, incomes, complete records. See `Migration`.
    static let currentVersion = 2

    var version = AppData.currentVersion
    var debts: [Debt] = []
    var payments: [PaymentRecord] = []
    /// Balances over time, one point per day they changed. Rebuilt from `payments` whenever they change.
    var history: [BalancePoint] = []
    var settings: PlanSettings

    static func empty(today: Date) -> AppData {
        AppData(settings: PlanSettings())
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
        for i in settings.incomes.indices {
            settings.incomes[i].amount = Limits.money(settings.incomes[i].amount)
            settings.incomes[i].monthDays = settings.incomes[i].monthDays.map { min(max(1, $0), 31) }
        }
        settings.incomes = Array(settings.incomes.prefix(12))
        settings.fixedAmount = Limits.money(settings.fixedAmount)
        settings.fixedDay = min(max(1, settings.fixedDay), 31)
        settings.buffer = Limits.money(settings.buffer)
        settings.extraMonthly = Limits.money(settings.extraMonthly)
    }
}
