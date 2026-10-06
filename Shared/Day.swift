import Foundation

/// A calendar day: a year, a month and a day. It has no time of day and no time zone, so it means
/// the same thing wherever the iPhone is. Saved as "2026-10-09".
///
/// All of the arithmetic is whole numbers, which keeps it exact and fast.
struct Day: Hashable, Comparable, Codable, CustomStringConvertible {
    /// Days since January 1, 1970.
    var ordinal: Int

    init(ordinal: Int) { self.ordinal = ordinal }

    /// A month or day outside its range is brought back in: month 13 is January of the next year,
    /// and a day past the end of the month is that month's last day.
    init(_ year: Int, _ month: Int, _ day: Int) {
        let index = year * 12 + (month - 1)
        self = Day.inMonth(index, day: day)
    }

    // MARK: Parts

    var year: Int { civil.year }
    var month: Int { civil.month }
    var day: Int { civil.day }

    /// The month as one number, so months can be compared and stepped: year x 12 + (month - 1).
    var monthIndex: Int {
        let c = civil
        return c.year * 12 + (c.month - 1)
    }

    /// 1 is Sunday, 7 is Saturday.
    var weekday: Int { ((ordinal % 7) + 7 + 4) % 7 + 1 }

    var monthStart: Day { Day.inMonth(monthIndex, day: 1) }

    private var civil: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    private static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    // MARK: Months

    static func length(ofMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// A day of a month given as a month index. The day is kept inside the month: the 31st of a
    /// 30-day month is the 30th.
    static func inMonth(_ monthIndex: Int, day: Int) -> Day {
        let year = monthIndex >= 0 ? monthIndex / 12 : (monthIndex - 11) / 12
        let month = monthIndex - year * 12 + 1
        let clamped = Swift.min(Swift.max(1, day), length(ofMonth: month, year: year))
        return Day(ordinal: ordinal(year: year, month: month, day: clamped))
    }

    /// The first date on or after `start` that falls on `dayOfMonth`.
    static func next(dayOfMonth: Int, onOrAfter start: Day) -> Day {
        let here = inMonth(start.monthIndex, day: dayOfMonth)
        return here >= start ? here : inMonth(start.monthIndex + 1, day: dayOfMonth)
    }

    // MARK: Stepping

    func adding(days: Int) -> Day { Day(ordinal: ordinal + days) }

    /// The same day of the month, `months` later, or that month's last day if it is shorter.
    func adding(months: Int) -> Day { Day.inMonth(monthIndex + months, day: day) }

    func days(to other: Day) -> Int { other.ordinal - ordinal }

    static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }

    // MARK: Dates

    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// The start of this day in a calendar's time zone.
    func date(in calendar: Calendar) -> Date {
        let c = civil
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? Date(timeIntervalSince1970: Double(ordinal) * 86_400)
    }

    // MARK: Saving

    var description: String {
        let c = civil
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.count == 10, parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(y, m, d)
    }

    /// Files saved before dates were kept as calendar days hold moments in time instead. When one is
    /// read, the decoder is told which time zone those moments were written in.
    static let legacyZone = CodingUserInfoKey(rawValue: "aprfree.legacyZone")

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        if let day = Day(text) {
            self = day
            return
        }
        // An older file: a moment such as 2026-10-09T04:00:00Z. Its day is the one it fell on where it was written.
        guard let moment = try? Date(text, strategy: .iso8601) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a day: \(text)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Day.legacyZone.flatMap { decoder.userInfo[$0] as? TimeZone } ?? .current
        self.init(moment, in: calendar)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
