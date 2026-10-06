import UIKit

/// The PDF report: the totals, the plan, every debt, and the charts, laid out for printing.
/// Everything is drawn on the iPhone; nothing is uploaded.
enum Report {
    static func pdf(for store: AppStore) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var sheet = Sheet(context: context, page: page)
            sheet.start()
            summary(&sheet, store)
            balanceChart(&sheet, store)
            breakdown(&sheet, store)
            debts(&sheet, store)
            strategies(&sheet, store)
            interestChart(&sheet, store)
            utilization(&sheet, store)
            month(&sheet, store)
            upcoming(&sheet, store)
            sheet.finish()
        }
    }

    // MARK: Page

    /// A page being filled from the top down. Asking for more room than is left starts a new page.
    private struct Sheet {
        let context: UIGraphicsPDFRendererContext
        let page: CGRect
        let margin: CGFloat = 54
        var y: CGFloat = 0
        var number = 0

        var left: CGFloat { margin }
        var right: CGFloat { page.width - margin }
        var width: CGFloat { page.width - margin * 2 }
        var bottom: CGFloat { page.height - 64 }

        static let ink = UIColor.black
        static let soft = UIColor(white: 0.38, alpha: 1)
        static let faint = UIColor(white: 0.86, alpha: 1)
        static let green = UIColor(red: 0x1E / 255, green: 0x85 / 255, blue: 0x37 / 255, alpha: 1)

        mutating func start() {
            context.beginPage()
            number += 1
            y = margin
        }

        mutating func finish() { footer() }

        /// Makes sure `height` points fit on this page, moving to a new one if they do not.
        mutating func need(_ height: CGFloat) {
            guard y + height > bottom else { return }
            footer()
            start()
        }

        private func footer() {
            let note = "Made by APRFree on this iPhone. Nothing was uploaded. Dates and interest are estimates from the numbers entered, not financial advice."
            draw(note, at: CGPoint(x: left, y: page.height - 44), size: 8, color: Sheet.soft, maxWidth: width - 40)
            draw("\(number)", at: CGPoint(x: right, y: page.height - 44), size: 8, color: Sheet.soft, align: .right)
        }

        enum Align { case left, right, center }

        @discardableResult
        func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = Sheet.ink,
                  align: Align = .left, maxWidth: CGFloat? = nil) -> CGSize {
            let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            if let maxWidth {
                let box = string.boundingRect(with: CGSize(width: maxWidth, height: 400), options: [.usesLineFragmentOrigin], context: nil)
                string.draw(with: CGRect(x: point.x, y: point.y, width: maxWidth, height: ceil(box.height)), options: [.usesLineFragmentOrigin], context: nil)
                return box.size
            }
            let measured = string.size()
            let x = align == .left ? point.x : align == .right ? point.x - measured.width : point.x - measured.width / 2
            string.draw(at: CGPoint(x: x, y: point.y))
            return measured
        }

        func rule(_ y: CGFloat, color: UIColor = Sheet.faint) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: left, y: y))
            path.addLine(to: CGPoint(x: right, y: y))
            color.setStroke()
            path.lineWidth = 0.75
            path.stroke()
        }

        /// A section heading, with room checked for it and for the first of what follows.
        mutating func heading(_ title: String, room: CGFloat) {
            need(room + 34)
            y += 18
            draw(title, at: CGPoint(x: left, y: y), size: 14, weight: .bold)
            y += 24
        }
    }

    // MARK: Sections

    private static func summary(_ sheet: inout Sheet, _ store: AppStore) {
        sheet.draw("APRFree report", at: CGPoint(x: sheet.left, y: sheet.y), size: 24, weight: .bold)
        sheet.draw(Fmt.full(store.today), at: CGPoint(x: sheet.right, y: sheet.y + 10), size: 11, color: Sheet.soft, align: .right)
        sheet.y += 46
        sheet.draw("Total balance", at: CGPoint(x: sheet.left, y: sheet.y), size: 10, color: Sheet.soft)
        sheet.y += 14
        sheet.draw(store.total.usd, at: CGPoint(x: sheet.left, y: sheet.y), size: 30, weight: .bold)
        sheet.y += 44

        let plan = store.plan
        let facts: [(String, String)] = [
            ("Strategy", "\(store.settings.strategy.title): \(store.strategySummary)"),
            ("Debt-free", plan.debtFree.map(Fmt.monthYear) ?? "Not on this plan"),
            ("Interest still to pay", plan.finished ? plan.totalInterest.usd : "Never ends on this plan"),
            ("Paid so far", "\(store.paidSoFar.usd) of \(store.startTotal.usd) (\(Int((store.fractionPaid * 100).rounded()))%)"),
            ("Interest right now", "\(store.dailyCost.usd) a day, \(store.monthlyCost.usd) a month"),
        ]
        for (label, value) in facts {
            sheet.draw(label, at: CGPoint(x: sheet.left, y: sheet.y), size: 11, color: Sheet.soft)
            sheet.draw(value, at: CGPoint(x: sheet.left + 150, y: sheet.y), size: 11, weight: .semibold)
            sheet.y += 17
        }
        sheet.y += 4
    }

    /// History as a solid line, the plan as a dashed one, with today marked.
    private static func balanceChart(_ sheet: inout Sheet, _ store: AppStore) {
        let history = store.data.history.map { ($0.date, $0.total) }
        let plan = store.plan
        let planned = plan.finished ? plan.series.map { ($0.date, $0.total) } : []
        guard history.count + planned.count > 1 else { return }
        sheet.heading("Balance over time", room: 190)
        let start = history.first?.0 ?? store.today
        let end = max(planned.last?.0 ?? store.today, Cal.addMonths(1, to: store.today))
        let top = Fmt.niceCeiling(max((history + planned).map(\.1).max() ?? 0, 1))
        let plot = frame(&sheet, height: 150, top: top, start: start, end: end) { Fmt.compact($0) }
        line(history, in: plot, top: top, start: start, end: end, dashed: false, stepped: true)
        line(planned, in: plot, top: top, start: start, end: end, dashed: true)
        marker(store.today, "Today", in: plot, start: start, end: end)
        legend(&sheet, [("Recorded", false), (plan.finished ? "Plan" : "No plan: add income to see one", true)])
    }

    /// Each debt as a bar, largest first, with its share of the total.
    private static func breakdown(_ sheet: inout Sheet, _ store: AppStore) {
        let debts = store.active.sorted { $0.balance > $1.balance }
        guard let largest = debts.first?.balance, largest > 0 else { return }
        sheet.heading("Where the balance is", room: 40)
        for debt in debts {
            sheet.need(20)
            sheet.draw(debt.title, at: CGPoint(x: sheet.left, y: sheet.y), size: 10, maxWidth: 118)
            let track = CGRect(x: sheet.left + 124, y: sheet.y + 2, width: sheet.width - 124 - 150, height: 9)
            Sheet.faint.setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 2).fill()
            Sheet.ink.setFill()
            UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: max(1.5, track.width * debt.balance / largest), height: track.height),
                         cornerRadius: 2).fill()
            sheet.draw("\(Int((store.share(of: debt) * 100).rounded()))%", at: CGPoint(x: sheet.right - 96, y: sheet.y), size: 10, color: Sheet.soft, align: .right)
            sheet.draw(debt.balance.usd, at: CGPoint(x: sheet.right, y: sheet.y), size: 10, weight: .semibold, align: .right)
            sheet.y += 18
        }
    }

    private static func debts(_ sheet: inout Sheet, _ store: AppStore) {
        let debts = store.active
        guard !debts.isEmpty else { return }
        let plan = store.plan
        sheet.heading("Debts", room: 60)
        let columns: [(String, CGFloat)] = [("APR", 204), ("Payment", 272), ("Balance", 352), ("Paid off", 420), ("Interest left", sheet.width)]
        func header() {
            sheet.draw("Debt", at: CGPoint(x: sheet.left, y: sheet.y), size: 9, weight: .semibold, color: Sheet.soft)
            for (title, x) in columns { sheet.draw(title, at: CGPoint(x: sheet.left + x, y: sheet.y), size: 9, weight: .semibold, color: Sheet.soft, align: .right) }
            sheet.y += 14
            sheet.rule(sheet.y)
            sheet.y += 6
        }
        header()
        for debt in debts {
            if sheet.y + 34 > sheet.bottom {
                sheet.need(1000)
                header()
            }
            let cells = [Fmt.percent(debt.apr(on: store.today)), debt.minimum.usd, debt.balance.usd,
                         plan.payoff[debt.id].map(Fmt.monthYear) ?? "Not yet", store.projectedInterest(for: debt)?.usd ?? "Not yet"]
            sheet.draw(debt.title, at: CGPoint(x: sheet.left, y: sheet.y), size: 11, weight: .semibold, maxWidth: 160)
            for (cell, column) in zip(cells, columns) {
                sheet.draw(cell, at: CGPoint(x: sheet.left + column.1, y: sheet.y), size: 11, align: .right)
            }
            sheet.y += 14
            sheet.draw(debt.detail.isEmpty ? debt.kind.title : debt.detail, at: CGPoint(x: sheet.left, y: sheet.y), size: 9, color: Sheet.soft, maxWidth: 170)
            sheet.y += 18
        }
    }

    private static func strategies(_ sheet: inout Sheet, _ store: AppStore) {
        guard !store.active.isEmpty, store.hasIncome else { return }
        let plans = Strategy.allCases.map { ($0, PayoffEngine.simulate(store.planInput(strategy: $0, totalsOnly: true))) }
        let cheapest = plans.filter { $0.1.finished }.map(\.1.totalInterest).min() ?? 0
        sheet.heading("Strategies compared", room: 24 + CGFloat(plans.count) * 18)
        let columns: [(String, CGFloat)] = [("Interest", 300), ("Debt-free", 400), ("Extra cost", sheet.width)]
        sheet.draw("Strategy", at: CGPoint(x: sheet.left, y: sheet.y), size: 9, weight: .semibold, color: Sheet.soft)
        for (title, x) in columns { sheet.draw(title, at: CGPoint(x: sheet.left + x, y: sheet.y), size: 9, weight: .semibold, color: Sheet.soft, align: .right) }
        sheet.y += 14
        sheet.rule(sheet.y)
        sheet.y += 6
        for (strategy, plan) in plans {
            let current = strategy == store.settings.strategy
            let extra = plan.totalInterest - cheapest
            sheet.draw(strategy.title + (current ? " (yours)" : ""), at: CGPoint(x: sheet.left, y: sheet.y), size: 11, weight: current ? .bold : .regular)
            let cells = [plan.finished ? plan.totalInterest.usd : "Never ends", plan.debtFree.map(Fmt.monthYear) ?? "Not yet",
                         !plan.finished ? "Not yet" : extra < 0.005 ? "Lowest" : "+\(extra.usd)"]
            for (cell, column) in zip(cells, columns) {
                sheet.draw(cell, at: CGPoint(x: sheet.left + column.1, y: sheet.y), size: 11, weight: current ? .bold : .regular, align: .right)
            }
            sheet.y += 18
        }
    }

    /// The interest the whole plan charges in each of its months.
    private static func interestChart(_ sheet: inout Sheet, _ store: AppStore) {
        let plan = store.plan
        guard plan.finished else { return }
        var byMonth: [Date: Double] = [:]
        for debt in store.active {
            for point in plan.interestByMonth(for: debt.id) { byMonth[point.date, default: 0] += point.total }
        }
        let months = byMonth.keys.sorted()
        guard months.count > 1, let largest = byMonth.values.max(), largest > 0 else { return }
        sheet.heading("Interest each month on this plan", room: 150)
        let top = Fmt.niceCeiling(largest)
        let start = months[0], end = Cal.addMonths(1, to: months[months.count - 1])
        let plot = frame(&sheet, height: 110, top: top, start: start, end: end) { Fmt.compact($0) }
        let slot = plot.width / CGFloat(months.count)
        Sheet.soft.setFill()
        for (index, month) in months.enumerated() {
            let height = plot.height * CGFloat((byMonth[month] ?? 0) / top)
            UIBezierPath(rect: CGRect(x: plot.minX + CGFloat(index) * slot + slot * 0.15, y: plot.maxY - height, width: max(0.8, slot * 0.7), height: height)).fill()
        }
        sheet.y += 4
    }

    private static func utilization(_ sheet: inout Sheet, _ store: AppStore) {
        let cards = store.limitedCards
        guard !cards.isEmpty, let now = store.utilization else { return }
        let history = store.utilizationHistory.map { ($0.date, $0.total) }
        let planned = store.utilizationPlan.map { ($0.date, $0.total) }
        sheet.heading("Credit utilization", room: 170)
        sheet.draw("\(Int((now * 100).rounded()))% of \(cards.reduce(0) { $0 + ($1.creditLimit ?? 0) }.usd) in use across \(Fmt.plural(cards.count, "card")).",
                   at: CGPoint(x: sheet.left, y: sheet.y), size: 11)
        sheet.y += 20
        if history.count + planned.count > 1 {
            let start = history.first?.0 ?? store.today
            let end = max(planned.last?.0 ?? store.today, Cal.addMonths(1, to: store.today))
            // A round top, a multiple of 20%, so the middle line of the chart is a round number too.
            let top = max(0.4, (((history + planned).map(\.1).max() ?? 0) * 1.05 / 0.2).rounded(.up) * 0.2)
            let plot = frame(&sheet, height: 100, top: top, start: start, end: end) { "\(Int(($0 * 100).rounded()))%" }
            line(history, in: plot, top: top, start: start, end: end, dashed: false, stepped: true)
            line(planned, in: plot, top: top, start: start, end: end, dashed: true)
            // The 30% line.
            let y = plot.maxY - plot.height * CGFloat(0.3 / top)
            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: plot.minX, y: y))
            rule.addLine(to: CGPoint(x: plot.maxX, y: y))
            rule.setLineDash([2, 2], count: 2, phase: 0)
            Sheet.soft.setStroke()
            rule.lineWidth = 0.75
            rule.stroke()
            sheet.draw("30%", at: CGPoint(x: plot.maxX, y: y - 11), size: 8, color: Sheet.soft, align: .right)
            sheet.y += 6
        }
        for card in cards {
            sheet.need(16)
            let share = card.utilization ?? 0
            let limit = card.creditLimit ?? 0
            let when = share < 0.3 ? "already under 30%" : store.under30Date(for: card).map { "under 30% by \(Fmt.full($0))" } ?? "not under 30% on this plan"
            sheet.draw(card.title, at: CGPoint(x: sheet.left, y: sheet.y), size: 10, weight: .semibold, maxWidth: 150)
            sheet.draw("\(Int((share * 100).rounded()))%", at: CGPoint(x: sheet.left + 200, y: sheet.y), size: 10, align: .right)
            sheet.draw("\(card.balance.usd) of \(limit.usd), \(when)", at: CGPoint(x: sheet.left + 214, y: sheet.y), size: 10, color: Sheet.soft)
            sheet.y += 15
        }
    }

    /// The month so far, from its statement.
    private static func month(_ sheet: inout Sheet, _ store: AppStore) {
        guard let statement = store.statement(for: store.today) else { return }
        sheet.heading("\(Fmt.monthNameYear(statement.month)) so far", room: 90)
        let facts: [(String, String)] = [
            ("Balance at the start", statement.opening.usd), ("Paid", "\(statement.paid.usd) in \(Fmt.plural(statement.payments.count, "payment"))"),
            ("Charges added", statement.charged.usd), ("Interest recorded", statement.interest.usd), ("Balance today", statement.closing.usd),
        ]
        for (label, value) in facts {
            sheet.draw(label, at: CGPoint(x: sheet.left, y: sheet.y), size: 11, color: Sheet.soft)
            sheet.draw(value, at: CGPoint(x: sheet.left + 150, y: sheet.y), size: 11, weight: .semibold)
            sheet.y += 16
        }
    }

    private static func upcoming(_ sheet: inout Sheet, _ store: AppStore) {
        let coming = store.upcoming()
        guard !coming.isEmpty else { return }
        sheet.heading("Due in the next 30 days", room: 40)
        for item in coming.prefix(40) {
            sheet.need(16)
            sheet.draw(Fmt.weekday(item.date), at: CGPoint(x: sheet.left, y: sheet.y), size: 11)
            sheet.draw(item.debt.title, at: CGPoint(x: sheet.left + 110, y: sheet.y), size: 11, weight: .semibold, maxWidth: 260)
            sheet.draw(item.amount.usd, at: CGPoint(x: sheet.right, y: sheet.y), size: 11, align: .right)
            sheet.y += 16
        }
    }

    // MARK: Chart drawing

    /// Draws the axes for a chart over dates and returns the area to plot in.
    private static func frame(_ sheet: inout Sheet, height: CGFloat, top: Double, start: Date, end: Date, label: (Double) -> String) -> CGRect {
        let plot = CGRect(x: sheet.left + 38, y: sheet.y + 4, width: sheet.width - 38, height: height)
        for step in 0...2 {
            let y = plot.maxY - plot.height * CGFloat(step) / 2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            Sheet.faint.setStroke()
            path.lineWidth = 0.6
            path.stroke()
            sheet.draw(label(top * Double(step) / 2), at: CGPoint(x: plot.minX - 5, y: y - 5), size: 8, color: Sheet.soft, align: .right)
        }
        // A few dates along the bottom: days for a short span, months for a long one.
        let span = end.timeIntervalSince(start)
        let short = Cal.days(from: start, to: end) <= 100
        if span > 0 {
            for step in 1...3 {
                let date = start.addingTimeInterval(span * Double(step) / 4)
                sheet.draw(short ? Fmt.monthDay(date) : Fmt.monthYear(date), at: CGPoint(x: plot.minX + plot.width * CGFloat(step) / 4, y: plot.maxY + 4),
                           size: 8, color: Sheet.soft, align: .center)
            }
        }
        sheet.y = plot.maxY + 18
        return plot
    }

    private static func point(_ date: Date, _ value: Double, in plot: CGRect, top: Double, start: Date, end: Date) -> CGPoint {
        let span = max(end.timeIntervalSince(start), 1)
        let x = plot.minX + plot.width * CGFloat(min(max(date.timeIntervalSince(start) / span, 0), 1))
        return CGPoint(x: x, y: plot.maxY - plot.height * CGFloat(min(max(value / top, 0), 1)))
    }

    /// A line through the points. `stepped` holds each value until the next one, which is how a
    /// recorded balance behaves.
    private static func line(_ points: [(Date, Double)], in plot: CGRect, top: Double, start: Date, end: Date, dashed: Bool, stepped: Bool = false) {
        guard points.count > 1 else { return }
        let path = UIBezierPath()
        var last: CGPoint?
        for (date, value) in points {
            let p = point(date, value, in: plot, top: top, start: start, end: end)
            if let last {
                if stepped { path.addLine(to: CGPoint(x: p.x, y: last.y)) }
                path.addLine(to: p)
            } else {
                path.move(to: p)
            }
            last = p
        }
        if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
        Sheet.ink.setStroke()
        path.lineWidth = dashed ? 1.3 : 1.6
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func marker(_ date: Date, _ text: String, in plot: CGRect, start: Date, end: Date) {
        let x = point(date, 0, in: plot, top: 1, start: start, end: end).x
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: plot.minY))
        path.addLine(to: CGPoint(x: x, y: plot.maxY))
        path.setLineDash([1.5, 2], count: 2, phase: 0)
        Sheet.soft.setStroke()
        path.lineWidth = 0.6
        path.stroke()
        let font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Sheet.ink])
        string.draw(at: CGPoint(x: min(x + 3, plot.maxX - string.size().width), y: plot.minY + 1))
    }

    private static func legend(_ sheet: inout Sheet, _ items: [(String, Bool)]) {
        var x = sheet.left + 38
        for (text, dashed) in items {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: sheet.y + 5))
            path.addLine(to: CGPoint(x: x + 16, y: sheet.y + 5))
            if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
            Sheet.ink.setStroke()
            path.lineWidth = 1.4
            path.stroke()
            x += 21
            x += sheet.draw(text, at: CGPoint(x: x, y: sheet.y), size: 8, color: Sheet.soft).width + 16
        }
        sheet.y += 14
    }
}
