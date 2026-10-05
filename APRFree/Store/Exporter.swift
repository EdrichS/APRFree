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

    static func write(_ contents: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    /// A snapshot: totals, every debt, and the current plan. Runs onto more pages when the list is long.
    static func pdf(data: AppData, plan: PlanResult, strategy: String, today: Date) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 54
            func draw(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black,
                      x: CGFloat = 54, right: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight),
                                                            .foregroundColor: color]
                let string = NSAttributedString(string: text, attributes: attrs)
                let origin = right ? CGPoint(x: page.width - 54 - string.size().width, y: y) : CGPoint(x: x, y: y)
                string.draw(at: origin)
            }
            func rule() {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 54, y: y))
                path.addLine(to: CGPoint(x: page.width - 54, y: y))
                UIColor(white: 0.85, alpha: 1).setStroke()
                path.stroke()
            }

            draw("APRFree summary", size: 24, weight: .bold)
            draw(Fmt.full(today), size: 11, color: .darkGray, right: true)
            y += 44
            let total = data.debts.reduce(0) { $0 + $1.balance }
            draw("Total balance", size: 11, color: .darkGray)
            y += 16
            draw(total.usd, size: 28, weight: .bold)
            y += 44
            draw("Strategy: \(strategy)", size: 12)
            draw("Debt-free: \(plan.debtFree.map(Fmt.monthYear) ?? "Not on this plan")", size: 12, right: true)
            y += 18
            draw("Interest still to pay on this plan: \(plan.totalInterest.usd)", size: 12)
            y += 30
            rule()
            y += 10
            draw("Debt", size: 10, weight: .semibold, color: .darkGray)
            draw("APR", size: 10, weight: .semibold, color: .darkGray, x: 300)
            draw("Payment", size: 10, weight: .semibold, color: .darkGray, x: 380)
            draw("Balance", size: 10, weight: .semibold, color: .darkGray, right: true)
            y += 18
            for d in data.debts where !d.isPaidOff {
                if y > page.height - 110 {
                    context.beginPage()
                    y = 54
                }
                draw(d.title, size: 12, weight: .semibold)
                draw(Fmt.percent(d.apr(on: today)), size: 12, x: 300)
                draw(d.minimum.usd, size: 12, x: 380)
                draw(d.balance.usd, size: 12, right: true)
                y += 15
                draw(d.detail, size: 10, color: .darkGray)
                y += 19
            }
            y += 6
            rule()
            y += 12
            draw("Made on this iPhone. Nothing was uploaded.", size: 10, color: .darkGray)
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
