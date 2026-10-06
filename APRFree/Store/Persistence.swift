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
    private static var journalURL: URL? { folder?.appendingPathComponent("journal.json") }

    // MARK: Reading and writing a file's contents

    /// The data as it is written to disk or to a backup. Every date in it is a calendar day
    /// ("2026-10-09"), which reads the same in any time zone.
    static func contents(of data: AppData) throws -> Data {
        try encoder.encode(data)
    }

    /// Reads saved data or a backup, and brings anything written by an earlier version up to date.
    ///
    /// Older files hold moments in time rather than calendar days. Each of those is read as the day it
    /// fell on in the time zone the file was written in. Files from October 5, 2026 name that zone;
    /// earlier ones do not, and `zone` (here, by default) is used for them.
    static func read(_ raw: Data, zone: TimeZone = Cal.zone) throws -> AppData {
        struct Stamp: Decodable { var timeZone: String? }
        let written = (try? JSONDecoder().decode(Stamp.self, from: raw))?.timeZone.flatMap(TimeZone.init(identifier:))
        let reader = JSONDecoder()
        reader.dateDecodingStrategy = .iso8601
        if let key = Day.legacyZone { reader.userInfo[key] = written ?? zone }
        var data = try reader.decode(AppData.self, from: raw)
        Migration.run(&data)
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
        keepPreviousVersion(of: url)
        try? raw.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private struct Version: Decodable { var version: Int }
    private static var checkedPrevious = false

    /// Before this version first saves over a file an earlier version wrote, that file is copied
    /// aside, so the upgrade can always be gone back on. Looked at once each time the app runs.
    private static func keepPreviousVersion(of url: URL) {
        guard !checkedPrevious else { return }
        checkedPrevious = true
        guard let aside = folder?.appendingPathComponent("data-before-v\(AppData.currentVersion).json"),
              !FileManager.default.fileExists(atPath: aside.path), let old = try? Data(contentsOf: url),
              let version = (try? JSONDecoder().decode(Version.self, from: old))?.version, version < AppData.currentVersion else { return }
        try? old.write(to: aside, options: [.atomic, .completeFileProtection])
    }

    /// Removes everything kept beside the data file: the copy from before an upgrade and a file that
    /// could not be read. Part of Reset Everything.
    static func eraseSideFiles() {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name != "data.json" {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Undo history

    static func loadJournal() -> Journal {
        guard let url = journalURL, let raw = try? Data(contentsOf: url), let journal = try? decoder.decode(Journal.self, from: raw) else {
            return Journal()
        }
        return journal
    }

    static func save(_ journal: Journal) {
        guard let url = journalURL else { return }
        if journal.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let raw = try? JSONEncoder.compact.encode(journal) {
            try? raw.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}

private extension JSONEncoder {
    /// Dates the same way as the main file, without the pretty printing.
    static let compact: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
