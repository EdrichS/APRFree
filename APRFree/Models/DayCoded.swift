import Foundation

extension Day {
    /// The calendar day a date falls on, here.
    init(_ date: Date) { self.init(date, in: Cal.calendar) }

    /// The start of this day, here.
    var date: Date { date(in: Cal.calendar) }
}

/// A date that is saved as a calendar day ("2026-10-09") rather than a moment in time. In memory it
/// is the start of that day wherever the iPhone is now, so the app's date math works on it directly.
@propertyWrapper
struct AsDay: Codable, Hashable {
    var wrappedValue: Date {
        didSet { wrappedValue = Cal.startOfDay(wrappedValue) }
    }

    init(wrappedValue: Date) {
        self.wrappedValue = Cal.startOfDay(wrappedValue)
    }

    init(from decoder: Decoder) throws {
        wrappedValue = try Day(from: decoder).date
    }

    func encode(to encoder: Encoder) throws {
        try Day(wrappedValue).encode(to: encoder)
    }
}

/// The same for a date that may be missing.
@propertyWrapper
struct AsOptionalDay: Codable, Hashable {
    var wrappedValue: Date? {
        didSet { wrappedValue = wrappedValue.map(Cal.startOfDay) }
    }

    init(wrappedValue: Date?) {
        self.wrappedValue = wrappedValue.map(Cal.startOfDay)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try Day(from: decoder).date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(Day(wrappedValue))
        } else {
            try container.encodeNil()
        }
    }
}

// A missing key means "no date", and no date is left out of the file instead of being written as null.
extension KeyedDecodingContainer {
    func decode(_ type: AsOptionalDay.Type, forKey key: Key) throws -> AsOptionalDay {
        try decodeIfPresent(type, forKey: key) ?? AsOptionalDay(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    mutating func encode(_ value: AsOptionalDay, forKey key: Key) throws {
        guard let date = value.wrappedValue else { return }
        try encode(Day(date), forKey: key)
    }
}
