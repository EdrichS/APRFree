import SwiftUI
import UniformTypeIdentifiers

/// CSV, PDF and backup files. Each is written locally and handed to the system share or save sheet.
enum Exporter {
    static func csv(_ data: AppData) -> String {
        func cell(_ text: String) -> String {
            // A name that starts like a formula would be run as one by a spreadsheet. A leading
            // apostrophe makes it plain text; numbers such as -12.00 are left alone.
            var value = text
            if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil { value = "'" + value }
            return value.contains(where: { ",\"\n".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
        }
        func money(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "" }
        func day(_ date: Date?) -> String { date.map(Fmt.isoDay) ?? "" }

        var rows = ["Type,Provider,Name,Balance,APR,Due day,Payment,Credit limit,Promo APR,Promo ends,Next due,Payments,Payments made"]
        for d in data.debts {
            let due = d.kind == .payLater ? "" : String(d.dueDay)
            rows.append([d.kind.title, d.kind == .loan ? d.title : d.provider, d.detail, money(d.balance), money(d.apr), due,
                         money(d.minimum), money(d.creditLimit), money(d.promoAPR), day(d.promoEnd), day(d.nextUnpaidDue()),
                         d.installments.map(String.init) ?? "", d.paidInstallments.map(String.init) ?? ""].map(cell).joined(separator: ","))
        }
        rows.append("")
        rows.append("Date,Debt,Kind,Amount,Interest,Balance after")
        for p in data.payments.sorted(by: { $0.date < $1.date }) {
            rows.append([day(p.date), p.title, p.kind.rawValue, money(p.amount), money(p.interest), money(p.balanceAfter)]
                .map(cell).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Exports are written into a folder of their own in the temporary directory, so they can be
    /// found again and removed.
    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("APRFree exports", isDirectory: true)
    }

    /// Removes any export still waiting to be shared. Part of Reset Everything.
    static func removeExports() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func write(_ contents: Data, named name: String) -> URL? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        do {
            try contents.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
}

/// A backup is the app's data file, saved wherever the user chooses.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: AppData

    init(data: AppData) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let raw = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = try Persistence.read(raw)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Persistence.contents(of: data))
    }
}
