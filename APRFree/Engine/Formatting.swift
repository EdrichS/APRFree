import Foundation

extension Double {
    /// Money always shows cents: $1,240.50
    var usd: String {
        // Round to cents the same way the math does (half away from zero) before formatting.
        cents.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    var cents: Double { (self * 100).rounded() / 100 }
}

enum Fmt {
    static func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.2f%%", value)
    }

    /// Dates are written in the app's own time zone, the one its calendar math uses.
    private static var dates: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
        style.timeZone = Cal.zone
        return style
    }

    /// Oct 9
    static func monthDay(_ date: Date) -> String {
        date.formatted(dates.month(.abbreviated).day())
    }

    /// Apr 2028
    static func monthYear(_ date: Date) -> String {
        date.formatted(dates.month(.abbreviated).year())
    }

    /// Fri, Oct 9
    static func weekday(_ date: Date) -> String {
        date.formatted(dates.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Oct 9, 2026
    static func full(_ date: Date) -> String {
        date.formatted(dates.month(.abbreviated).day().year())
    }

    /// Friday
    static func weekdayName(_ date: Date) -> String {
        date.formatted(dates.weekday(.wide))
    }

    /// October
    static func monthName(_ date: Date) -> String {
        date.formatted(dates.month(.wide))
    }

    /// October 2026
    static func monthNameYear(_ date: Date) -> String {
        date.formatted(dates.month(.wide).year())
    }

    /// Oct, for a chart axis that shows one label a month.
    static func monthShort(_ date: Date) -> String {
        date.formatted(dates.month(.abbreviated))
    }

    /// Oct ’26, for a chart axis that covers more than one year.
    static func monthAndShortYear(_ date: Date) -> String {
        "\(monthShort(date)) ’\(date.formatted(dates.year(.twoDigits)))"
    }

    /// 2026-10-09, for file names and exports.
    static func isoDay(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: Cal.zone).year().month().day())
    }

    /// 9th
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }

    /// $42K for chart axes.
    static func compact(_ value: Double) -> String {
        guard value >= 1000 else { return "$\(Int(value.rounded()))" }
        let thousands = value / 1000
        return thousands == thousands.rounded() ? "$\(Int(thousands))K" : String(format: "$%.1fK", thousands)
    }

    /// The next round number at or above a value, for chart and slider ceilings: 50,617 becomes 60,000.
    static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 100 }
        let magnitude = pow(10, floor(log10(value)))
        return ([1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].first { $0 * magnitude >= value } ?? 10) * magnitude
    }
}

/// How urgent a due date is. Orange and red are reserved for these.
enum DueStatus: Equatable {
    case overdue(days: Int)
    case soon(days: Int)
    case later(days: Int)

    init(due: Date, today: Date) {
        let days = Cal.days(from: today, to: due)
        if days < 0 {
            self = .overdue(days: -days)
        } else if days <= 7 {
            self = .soon(days: days)
        } else {
            self = .later(days: days)
        }
    }

    var text: String {
        switch self {
        case .overdue(let days): days == 1 ? "1 day overdue" : "\(days) days overdue"
        case .soon(0): "Due today"
        case .soon(1): "Due tomorrow"
        case .soon(let days), .later(let days): "Due in \(days) days"
        }
    }
}
