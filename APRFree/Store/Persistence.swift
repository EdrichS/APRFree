import Foundation

/// The whole app saves to one JSON file in Application Support. Nothing leaves the device.
enum Persistence {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    enum Loaded {
        case data(AppData)
        /// Nothing has been saved yet.
        case none
        /// The file is there but cannot be read right now, for instance because the iPhone is
        /// still locked. It must not be saved over; try again later.
        case unavailable
    }

    private static var folder: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("APRFree", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var fileURL: URL? { folder?.appendingPathComponent("data.json") }

    // MARK: Reading and writing a file's contents

    /// The data as it is written to disk or to a backup: stamped with the time zone its dates are in.
    static func contents(of data: AppData) throws -> Data {
        var stamped = data
        stamped.timeZone = Cal.zone.identifier
        return try encoder.encode(stamped)
    }

    /// Reads saved data or a backup. Dates written in another time zone are moved to this one, so
    /// each keeps its calendar day: a due date of Oct 9 saved in New York is still Oct 9 in Los Angeles.
    static func read(_ raw: Data, zone: TimeZone = Cal.zone) throws -> AppData {
        var data = try decoder.decode(AppData.self, from: raw)
        if let id = data.timeZone, id != zone.identifier, let written = TimeZone(identifier: id) {
            let moving = JSONDecoder()
            moving.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                return Cal.rebase(try Date(text, strategy: .iso8601), from: written, to: zone)
            }
            data = try moving.decode(AppData.self, from: raw)
        }
        data.timeZone = nil
        data.sanitize()
        return data
    }

    // MARK: The app's own file

    static func load() -> Loaded {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return .none }
        guard let raw = try? Data(contentsOf: url) else { return .unavailable }
        if let data = try? read(raw) { return .data(data) }
        // The file cannot be understood. Keep it beside the data file instead of saving over it,
        // so nothing is lost for good, and start fresh.
        if let aside = folder?.appendingPathComponent("data-unreadable.json") {
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return .none
    }

    static func save(_ data: AppData) {
        guard let url = fileURL, let raw = try? contents(of: data) else { return }
        try? raw.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
