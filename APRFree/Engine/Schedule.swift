import Foundation

/// Calendar helpers. Everything in the app works in whole local days.
enum Cal {
    /// The time zone is fixed when the app starts, so every date is read the same way for as long as
    /// it runs. Saved dates are moved to the new zone the next time the app starts somewhere else
    /// (see `Persistence.read`), which keeps a due date on the same calendar day after travelling.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static var zone: TimeZone { calendar.timeZone }

    /// The same calendar day and time of day, in another time zone.
    static func rebase(_ date: Date, from old: TimeZone, to new: TimeZone) -> Date {
        var there = Calendar(identifier: .gregorian), here = Calendar(identifier: .gregorian)
        there.timeZone = old
        here.timeZone = new
        let parts = there.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return here.date(from: parts) ?? date
    }

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    static func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    static func day(of date: Date) -> Int { calendar.component(.day, from: date) }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }

    /// Calendar months between two dates, ignoring the day: Oct 4 to Apr 1 is 6.
    static func months(from a: Date, to b: Date) -> Int {
        let x = calendar.dateComponents([.year, .month], from: a)
        let y = calendar.dateComponents([.year, .month], from: b)
        return ((y.year ?? 0) - (x.year ?? 0)) * 12 + ((y.month ?? 0) - (x.month ?? 0))
    }

    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// The given day of a month, clamped to the month's length.
    static func date(inMonthOf anchor: Date, monthOffset: Int, day: Int) -> Date {
        let first = addMonths(monthOffset, to: monthStart(anchor))
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return addDays(min(max(1, day), length) - 1, to: first)
    }

    /// The first date on or after `date` that falls on `day` of the month.
    static func nextDue(day: Int, onOrAfter date: Date) -> Date {
        let start = startOfDay(date)
        for offset in 0..<3 {
            let candidate = Cal.date(inMonthOf: start, monthOffset: offset, day: day)
            if candidate >= start { return candidate }
        }
        return start
    }
}

/// "Today" for the whole app. Overridable so demos and tests are reproducible.
enum AppClock {
    static var override: Date?
    static var today: Date { Cal.startOfDay(override ?? Date()) }
    /// The moment to stamp on a new record.
    static var now: Date { override ?? Date() }
}

/// Paydays on a fixed rhythm, worked out from the first one so nothing drifts.
///
/// - Weekly and every two weeks: every 7 or 14 days, so the weekday never changes. Paid on a
///   Friday means every payday is a Friday.
/// - Monthly: the same day of every month. In a month too short for it, the last day of that month
///   is used, and the following month goes back to the real day: the 31st gives Jan 31, Feb 28, Mar 31.
struct PaydaySequence {
    let first: Date
    let frequency: PayFrequency
    /// The day of the month monthly pay lands on.
    let anchorDay: Int
    /// Which payday `date(0)` is, counted from `first`.
    private var base = 0

    init(first: Date, frequency: PayFrequency, anchorDay: Int? = nil) {
        let start = Cal.startOfDay(first)
        self.first = start
        self.frequency = frequency
        // The remembered pay day only applies if `first` really is that day, or that day shortened
        // to fit its month. Otherwise the date itself says which day it is.
        let day = Cal.day(of: start)
        if let anchorDay, anchorDay >= day, Cal.date(inMonthOf: start, monthOffset: 0, day: anchorDay) == start {
            self.anchorDay = anchorDay
        } else {
            self.anchorDay = day
        }
    }

    func date(_ index: Int) -> Date {
        let n = base + index
        switch frequency {
        case .weekly:
            return Cal.addDays(7 * n, to: first)
        case .biweekly:
            return Cal.addDays(14 * n, to: first)
        case .monthly:
            return Cal.date(inMonthOf: first, monthOffset: n, day: anchorDay)
        }
    }

    /// The same rhythm, renumbered so `date(0)` is the first payday on or after `day`.
    /// Never earlier than `first`: that is the next payday the user gave, so nothing comes before it.
    func starting(onOrAfter day: Date) -> PaydaySequence {
        let target = Cal.startOfDay(day)
        var copy = self
        copy.base = 0
        var n: Int
        switch frequency {
        case .weekly: n = Cal.days(from: first, to: target) / 7
        case .biweekly: n = Cal.days(from: first, to: target) / 14
        case .monthly: n = Cal.months(from: first, to: target)
        }
        n = max(0, n - 1)
        while copy.date(n) < target && n < 100_000 { n += 1 }
        copy.base = n
        return copy
    }

    /// Whether the payday at `index` is the first one in its calendar month.
    func isFirstInMonth(_ index: Int) -> Bool {
        Cal.monthStart(date(index)) != Cal.monthStart(date(index - 1))
    }

    /// The first payday on or after `date`.
    func onOrAfter(_ date: Date) -> Date {
        starting(onOrAfter: date).date(0)
    }
}
