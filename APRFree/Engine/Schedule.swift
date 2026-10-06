import Foundation

/// Calendar helpers. Everything in the app works in whole local days.
enum Cal {
    /// The time zone is fixed when the app starts, so every date is read the same way for as long as
    /// it runs. Saved dates are calendar days ("2026-10-09"), so they are the same day in any zone.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static var zone: TimeZone { calendar.timeZone }

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

/// Where the money comes from: every income as a line of paydays, merged into one calendar.
///
/// - Weekly and every two weeks: every 7 or 14 days from the first payday, so the weekday never
///   changes. Paid on a Friday means every payday is a Friday.
/// - Monthly: the same day or days of every month. In a month too short for a day, the last day of
///   that month is used, and the next month goes back to the real day: the 31st gives Jan 31,
///   Feb 28, Mar 31.
struct PaySchedule: Hashable {
    struct Line: Hashable {
        var id = UUID()
        var name = ""
        /// The first payday. Nothing comes before it.
        var first: Day
        var frequency: PayFrequency
        /// Monthly pay: the days of the month, in order, at least one.
        var monthDays: [Int] = []
        /// What arrives.
        var gross = 0.0
        /// What is left for debt once the safety buffer is held back.
        var net = 0.0

        init(id: UUID = UUID(), name: String = "", first: Day, frequency: PayFrequency, monthDays: [Int] = [], gross: Double = 0, net: Double = 0) {
            self.id = id
            self.name = name
            self.first = first
            self.frequency = frequency
            let days = Array(Set(monthDays.map { min(max(1, $0), 31) })).sorted()
            self.monthDays = days.isEmpty ? [first.day] : days
            self.gross = gross
            self.net = net
        }

        /// Which of the month's pay days `first` is: the earliest one that has not passed by then.
        private var firstSlot: Int {
            monthDays.firstIndex { Day.inMonth(first.monthIndex, day: $0) >= first } ?? monthDays.count
        }

        /// Payday number `n`, counted from `first`. Negative numbers are the paydays before it.
        func day(_ n: Int) -> Day {
            switch frequency {
            case .weekly: return first.adding(days: 7 * n)
            case .biweekly: return first.adding(days: 14 * n)
            case .monthly:
                let count = monthDays.count
                let slot = firstSlot + n
                let month = slot >= 0 ? slot / count : (slot - count + 1) / count
                return Day.inMonth(first.monthIndex + month, day: monthDays[slot - month * count])
            }
        }

        /// The number of the first payday on or after `start`. Never below zero: nothing comes before `first`.
        func index(onOrAfter start: Day) -> Int {
            guard start > first else { return 0 }
            var n: Int
            switch frequency {
            case .weekly: n = first.days(to: start) / 7
            case .biweekly: n = first.days(to: start) / 14
            case .monthly: n = max(0, (start.monthIndex - first.monthIndex - 1) * monthDays.count)
            }
            while day(n) < start { n += 1 }
            return n
        }

        /// The next payday number after `n` that lands on a later day. Two pay days can share a date
        /// in a short month (the 30th and the 31st are both Feb 28); that is one payday, not two.
        func index(after n: Int) -> Int {
            var m = n + 1
            while day(m) == day(n) { m += 1 }
            return m
        }

        /// The latest payday of this line before `limit`, counting back from payday `n`.
        func day(before limit: Day, from n: Int) -> Day {
            var m = n
            while day(m) >= limit { m -= 1 }
            return day(m)
        }
    }

    struct Event: Hashable {
        var day: Day
        var gross: Double
        var net: Double
        /// The incomes that pay on this day.
        var lines: [UUID]
    }

    var lines: [Line] = []

    init(lines: [Line] = []) { self.lines = lines }

    init(incomes: [Income], buffer: Double) {
        lines = incomes.map {
            Line(id: $0.id, name: $0.name, first: Day($0.nextPayday), frequency: $0.frequency,
                 monthDays: $0.frequency == .monthly ? $0.payDays : [], gross: $0.amount, net: max(0, $0.amount - buffer))
        }
    }

    /// True when any payday brings money for debt.
    var hasMoney: Bool { lines.contains { $0.net > 0.005 } }

    /// Walks the merged paydays in order.
    struct Cursor {
        private let lines: [Line]
        private var index: [Int]
        /// The latest payday before the first one this cursor gives: tells whether that first one
        /// is also the first payday of its month.
        let previous: Day?

        fileprivate init(_ lines: [Line], from start: Day) {
            self.lines = lines
            let begin = lines.map { $0.index(onOrAfter: start) }
            index = begin
            if let first = zip(lines, begin).map({ $0.day($1) }).min() {
                previous = zip(lines, begin).map { $0.day(before: first, from: $1) }.max()
            } else {
                previous = nil
            }
        }

        /// The next payday: its date, and what arrives and what is left for debt across every
        /// income paying that day. Nil when there is no income at all.
        mutating func next() -> (day: Day, gross: Double, net: Double)? {
            var soonest: Day?
            for i in lines.indices {
                let day = lines[i].day(index[i])
                if soonest.map({ day < $0 }) ?? true { soonest = day }
            }
            guard let day = soonest else { return nil }
            var gross = 0.0, net = 0.0
            for i in lines.indices where lines[i].day(index[i]) == day {
                gross += lines[i].gross
                net += lines[i].net
                index[i] = lines[i].index(after: index[i])
            }
            return (day, gross, net)
        }
    }

    func cursor(from start: Day) -> Cursor { Cursor(lines, from: start) }

    /// The next `count` paydays on or after `start`, with the incomes behind each.
    func events(from start: Day, count: Int) -> [Event] {
        guard !lines.isEmpty, count > 0 else { return [] }
        var index = lines.map { $0.index(onOrAfter: start) }
        var out: [Event] = []
        while out.count < count {
            guard let day = zip(lines, index).map({ $0.day($1) }).min() else { break }
            var event = Event(day: day, gross: 0, net: 0, lines: [])
            for i in lines.indices where lines[i].day(index[i]) == day {
                event.gross += lines[i].gross
                event.net += lines[i].net
                event.lines.append(lines[i].id)
                index[i] = lines[i].index(after: index[i])
            }
            out.append(event)
        }
        return out
    }

    /// The first payday on or after `start` and the one after it. With no income there are no
    /// paydays, so the stretch covered is the two weeks from `start`.
    func window(from start: Day) -> (payday: Day, next: Day, event: Event?) {
        let coming = events(from: start, count: 2)
        guard let first = coming.first else { return (start, start.adding(days: 14), nil) }
        return (first.day, coming.count > 1 ? coming[1].day : first.day.adding(days: 14), first)
    }
}

extension Income {
    /// This income's own paydays from `today`, for showing its rhythm back to the user.
    func paydays(from today: Date, count: Int = 3) -> [Date] {
        PaySchedule(incomes: [self], buffer: 0).events(from: Day(today), count: count).map(\.day.date)
    }

    /// The payday after `day`, on this income's rhythm.
    func payday(after day: Date) -> Date {
        PaySchedule(incomes: [self], buffer: 0).events(from: Day(day).adding(days: 1), count: 1).first?.day.date ?? day
    }
}

/// One income's paydays by number. `date(0)` is the first one.
struct PaydaySequence {
    private let line: PaySchedule.Line
    /// Which payday `date(0)` is, counted from the first.
    private var base = 0

    /// `anchorDay` is the day of the month monthly pay lands on, when `first` was shortened to fit its
    /// month. It only applies if `first` really is that day, or that day shortened.
    init(first: Date, frequency: PayFrequency, anchorDay: Int? = nil) {
        let day = Day(first)
        var monthDay = day.day
        if let anchorDay, anchorDay >= day.day, Day.inMonth(day.monthIndex, day: anchorDay) == day { monthDay = anchorDay }
        line = PaySchedule.Line(first: day, frequency: frequency, monthDays: [monthDay])
    }

    func date(_ index: Int) -> Date { line.day(base + index).date }

    /// The same rhythm, renumbered so `date(0)` is the first payday on or after `day`.
    func starting(onOrAfter day: Date) -> PaydaySequence {
        var copy = self
        copy.base = line.index(onOrAfter: Day(day))
        return copy
    }

    /// Whether the payday at `index` is the first one in its calendar month.
    func isFirstInMonth(_ index: Int) -> Bool {
        line.day(base + index).monthIndex != line.day(base + index - 1).monthIndex
    }

    /// The first payday on or after `date`.
    func onOrAfter(_ date: Date) -> Date {
        starting(onOrAfter: date).date(0)
    }
}
