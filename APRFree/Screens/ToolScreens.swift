import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Strategy

struct StrategyContent: View {
    @Environment(AppStore.self) private var store

    /// The order extra money follows, pay-later plans left out because their schedules are fixed.
    private var order: [Debt] { store.extraOrder.filter { $0.kind != .payLater } }
    private var isCustom: Bool { store.settings.strategy == .custom }

    var body: some View {
        List {
            Section {
                ForEach(Strategy.allCases) { strategy in
                    Button { store.updateSettings("Change strategy") { $0.strategy = strategy } } label: {
                        HStack(spacing: 12) {
                            RadioMark(on: store.settings.strategy == strategy)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(strategy.title).font(.headline)
                                Text(strategy.blurb).font(.footnote).foregroundStyle(Theme.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, debt in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 16, alignment: .leading)
                        Swatch(debt: debt)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(debt.kind == .loan ? debt.title : debt.provider).font(.callout.weight(.semibold))
                            Text(orderNote(debt)).font(.caption).monospacedDigit().foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .onMove(perform: isCustom ? move : nil)
            } header: {
                Text(isCustom ? "Your order · drag to reorder" : "Order")
            } footer: {
                if store.active.contains(where: { $0.kind == .payLater }) {
                    Text("\(store.active.filter { $0.kind == .payLater }.map(\.provider).formatted(.list(type: .and))) follow their own schedules.")
                }
            }
            Section {
                Toggle("0% promo cards: minimum only until the promo ends",
                       isOn: Binding(get: { store.settings.promoMinimumOnly }, set: { on in store.updateSettings("Change promo setting") { $0.promoMinimumOnly = on } }))
                    .toggleStyle(NeutralToggleStyle())
            }
            Section("Compare") {
                StrategyComparison()
            }
        }
        .environment(\.editMode, .constant(isCustom ? .active : .inactive))
    }

    private func orderNote(_ debt: Debt) -> String {
        if debt.hasPromo(on: store.today) {
            return "\(Fmt.percent(debt.promoAPR ?? 0)) promo\(store.settings.promoMinimumOnly ? " · minimum only" : "")"
        }
        return "\(Fmt.percent(debt.apr)) · \(debt.balance.usd)"
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = order.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let rest = store.settings.customOrder.filter { !ids.contains($0) }
        store.updateSettings("Reorder strategy") { $0.customOrder = ids + rest }
    }
}

struct RadioMark: View {
    let on: Bool

    var body: some View {
        if on {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 24, height: 24)
                .background(Theme.primaryFill, in: Circle())
        } else {
            Circle().strokeBorder(Theme.tertiary, lineWidth: 1.5).frame(width: 24, height: 24)
        }
    }
}

/// Every strategy run on the user's own debts: what it costs, when it ends, and which card goes first.
private struct StrategyComparison: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let plans = Strategy.allCases.map { ($0, PayoffEngine.simulate(store.planInput(strategy: $0))) }
        let cheapest = plans.filter { $0.1.finished }.map { $0.1.totalInterest }.min() ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                head("Interest", 82)
                head("Debt-free", 66)
                head("Extra cost", 74)
            }
            .padding(.bottom, 6)
            ForEach(plans, id: \.0) { strategy, plan in
                let current = strategy == store.settings.strategy
                Rectangle().fill(Theme.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(strategy.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        cell(plan.finished ? plan.totalInterest.usd : "Never ends", 82)
                        cell(plan.debtFree.map(Fmt.monthYear) ?? "Not yet", 66)
                        cell(extraCost(plan, cheapest), 74)
                    }
                    .font(.footnote.weight(current ? .bold : .regular))
                    .monospacedDigit()
                    Text(firstCard(plan)).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func head(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).frame(width: width, alignment: .trailing)
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).lineLimit(1).minimumScaleFactor(0.75).frame(width: width, alignment: .trailing)
    }

    private func extraCost(_ plan: PlanResult, _ cheapest: Double) -> String {
        guard plan.finished else { return "Not yet" }
        let extra = plan.totalInterest - cheapest
        return extra < 0.005 ? "Lowest" : "+\(extra.usd)"
    }

    private func firstCard(_ plan: PlanResult) -> String {
        let cards = store.active.filter { $0.kind == .card }.compactMap { card in plan.payoffPayday[card.id].map { (card, $0) } }
        guard let first = cards.min(by: { $0.1 < $1.1 }), let month = plan.payoff[first.0.id] else { return "No card paid off" }
        return "First card paid off: \(first.0.brandStyle.short), \(Fmt.monthYear(month))"
    }
}

// MARK: - Simulator

struct SimulatorContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var oneTime = 0.0
    @State private var monthly = 0.0
    @State private var purchase = 0.0
    @State private var strategy = Strategy.avalanche
    @State private var loaded = false
    /// The date under the finger while the chart is held.
    @State private var scrub: Date?
    @FocusState private var focused: Bool

    /// A new purchase lands on the card that costs the most.
    private var purchaseCard: Debt? {
        store.active.filter { $0.kind == .card }.max { $0.apr(on: store.today) < $1.apr(on: store.today) }
    }

    private var whatIf: PlanResult {
        var debts = store.data.debts
        if purchase > 0, let card = purchaseCard, let i = debts.firstIndex(where: { $0.id == card.id }) {
            debts[i].balance += purchase
        }
        return PayoffEngine.simulate(store.planInput(strategy: strategy, oneTime: oneTime, extraMonthly: monthly, debts: debts))
    }

    private var changed: Bool {
        strategy != store.settings.strategy || monthly != store.settings.extraMonthly
    }

    var body: some View {
        let base = store.plan
        let test = whatIf
        ScrollView {
            VStack(spacing: 12) {
                inputs
                chart(base: base, test: test)
                results(base: base, test: test)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .focused($focused)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Use This Plan") {
                store.updateSettings("Use simulator plan") {
                    $0.strategy = strategy
                    $0.extraMonthly = monthly
                }
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!changed)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 10)
            .padding(.bottom, 8)
            // Solid behind the button, so the tiles scroll under it instead of showing through.
            .background { Theme.bg.ignoresSafeArea(edges: .bottom) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            strategy = store.settings.strategy
            monthly = store.settings.extraMonthly
        }
    }

    private var inputs: some View {
        CardGroup {
            MoneyField(title: "One-time payment", value: $oneTime)
                .padding(.horizontal, 16)
                .frame(height: 52)
            RowDivider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly amount")
                ExtraAmountControl(amount: $monthly, baseMax: 500, step: 25, valueSize: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider()
            MoneyField(title: "New purchase", value: $purchase)
                .padding(.horizontal, 16)
                .frame(height: 52)
            RowDivider()
            HStack {
                Text("Strategy")
                Spacer()
                Picker("Strategy", selection: $strategy) {
                    ForEach(Strategy.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(height: 52)
        }
    }

    /// True once any input differs from the current plan, so there is a second line worth reading.
    private var hasWhatIf: Bool {
        oneTime > 0 || purchase > 0 || changed
    }

    /// Touch and hold the chart, then drag: the balance on that date is read off both lines.
    private func chart(base: PlanResult, test: PlanResult) -> some View {
        // A plan that never finishes is drawn only as far as the one that does (or two years, if neither
        // does), so a balance that keeps growing cannot stretch the chart or run out of it.
        let ends = [base, test].filter(\.finished).compactMap { $0.series.last?.date }
        let last = max(ends.max() ?? Cal.addMonths(24, to: store.today), Cal.addMonths(1, to: store.today))
        let baseLine = base.series.filter { $0.date <= last }
        let testLine = test.series.filter { $0.date <= last }
        let top = max((baseLine + testLine).map(\.total).max() ?? 0, 1)
        let held = scrub.map { min(max($0, store.today), last) }
        return Tile {
            HStack {
                TileLabel("Total balance")
                Spacer()
                LegendMark(text: "Current plan", dashed: true, color: Theme.tertiary)
                LegendMark(text: "What-if", dashed: false, color: .primary)
            }
            Group {
                if let held {
                    HStack(alignment: .center, spacing: 14) {
                        Text(Fmt.full(held)).font(.footnote.weight(.semibold))
                        Spacer(minLength: 0)
                        readout("Current plan", base.series.balance(at: held), Theme.secondary)
                        if hasWhatIf { readout("What-if", test.series.balance(at: held), .primary) }
                    }
                } else {
                    Text("Hold and drag the chart to read a balance.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 6)
            Chart {
                ForEach(baseLine) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.total), series: .value("Plan", "Current plan"))
                        .foregroundStyle(Theme.tertiary)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5, 5]))
                }
                ForEach(testLine) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.total), series: .value("Plan", "What-if"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                if let held {
                    RuleMark(x: .value("Date", held))
                        .foregroundStyle(Theme.tertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Date", held), y: .value("Balance", base.series.balance(at: held)))
                        .foregroundStyle(Theme.tertiary)
                        .symbolSize(70)
                    if hasWhatIf {
                        PointMark(x: .value("Date", held), y: .value("Balance", test.series.balance(at: held)))
                            .foregroundStyle(Color.primary)
                            .symbolSize(70)
                    }
                }
            }
            .chartXSelection(value: $scrub)
            .chartXScale(domain: store.today...last)
            .balanceAxes(top: top, from: store.today, to: last)
            .frame(height: 160)
            .padding(.top, 4)
            // Nothing drawn can leave the tile. The margin each side keeps the end axis labels and the
            // dots that follow a finger whole.
            .padding(.horizontal, 12)
            .clipped()
            .padding(.horizontal, -12)
            .accessibilityLabel("Total balance over time. Current plan ends \(base.debtFree.map(Fmt.monthYear) ?? "never"), what-if ends \(test.debtFree.map(Fmt.monthYear) ?? "never").")
            if purchase > 0, let card = purchaseCard {
                TileNote("The purchase is added to \(card.title), your highest APR.")
            }
            if !base.finished {
                TileNote(store.hasIncome
                         ? "Your current plan never clears the debt. Try a larger monthly amount."
                         : "There is no current plan yet: add your income under Tools, or try a monthly amount here.")
            }
        }
    }

    private func readout(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(Theme.secondary)
            Text(value.usd).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func results(base: PlanResult, test: PlanResult) -> some View {
        let saved = base.totalInterest - test.totalInterest
        let sooner = Cal.months(from: test.debtFree ?? store.today, to: base.debtFree ?? store.today)
        return TileRow(minHeight: 100) {
            if !test.finished || !base.finished {
                StatTile(label: "Interest", value: "Not yet", note: "This plan never clears the debt")
            } else if saved >= 0 {
                StatTile(label: "Interest saved", value: saved.usd, note: "over the whole plan", valueColor: saved > 0.005 ? Theme.green : .primary)
            } else {
                StatTile(label: "Extra interest", value: (-saved).usd, note: "over the whole plan")
            }
            if sooner == 0 {
                StatTile(label: "Debt-free", value: test.debtFree.map(Fmt.monthYear) ?? "Not yet", note: "Same month as your current plan")
            } else {
                StatTile(label: "Debt-free", value: Fmt.plural(abs(sooner), "month"),
                         note: "\(sooner > 0 ? "sooner" : "later"), in \(test.debtFree.map(Fmt.monthYear) ?? "no month yet")")
            }
        }
    }
}

struct LegendMark: View {
    let text: String
    var dashed = false
    var dot = false
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(color).frame(width: 8, height: 8)
            } else {
                Rectangle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [4, 3] : []))
                    .frame(width: 14, height: 1)
            }
            Text(text).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}

extension View {
    /// Axes for the balance-over-time charts: three dollar ticks from zero and a few date labels.
    /// A chart that covers only a few months labels days ("Oct 12"), because month names alone would
    /// repeat across it; a longer one labels months ("Oct ’26").
    func balanceAxes(top: Double, from start: Date, to end: Date) -> some View {
        let ceiling = Fmt.niceCeiling(top)
        let short = Cal.days(from: start, to: end) <= 100
        let span = end.timeIntervalSince(start)
        return chartYScale(domain: 0...ceiling)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, ceiling / 2, ceiling]) { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(Fmt.compact(amount)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                    // A label is centred on its tick, so one at the very edge would hang off the chart. Leave that one out.
                    if let date = value.as(Date.self), span > 0, (0.07...0.93).contains(date.timeIntervalSince(start) / span) {
                        AxisValueLabel { Text(short ? Fmt.monthDay(date) : Fmt.monthAndShortYear(date)) }
                    }
                }
            }
    }
}

// MARK: - Insights

struct InsightsContent: View {
    @Environment(AppStore.self) private var store

    private struct Alert: Identifiable {
        let id = UUID()
        var symbol: String
        var title: String
        var detail: String
        var level: Level
        enum Level { case info, soon, overdue }
    }

    private var alerts: [Alert] {
        var out: [Alert] = []
        let today = store.today
        for debt in store.active {
            if let due = debt.nextUnpaidDue(), due < today {
                out.append(Alert(symbol: "exclamationmark.triangle", title: "\(debt.title) is overdue",
                                 detail: "Was due \(Fmt.monthDay(due))", level: .overdue))
            }
        }
        let payday = store.paydays.current
        let before = store.upcoming(days: 60).filter { $0.date >= today && $0.date < payday }
        if !before.isEmpty {
            out.append(Alert(symbol: "exclamationmark.triangle", title: "\(Fmt.plural(before.count, "payment")) due before payday",
                             detail: "Next payday is \(Fmt.weekday(payday))", level: .soon))
        }
        for debt in store.active {
            if let end = debt.promoEnd, debt.hasPromo(on: today) {
                out.append(Alert(symbol: "tag", title: "\(debt.provider) promo ends \(Fmt.full(end))",
                                 detail: "Then \(Fmt.percent(debt.apr)) APR", level: .info))
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Tile {
                    TileLabel("Daily cost of all debt")
                    TileValue("\(store.dailyCost.usd) a day", size: 34)
                    TileNote("\(store.monthlyCost.usd) a month at today’s balances")
                }
                ranking
                quickWin
                SectionHeader(title: "Alerts").padding(.top, 16)
                alertList
                recap
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
    }

    private var ranking: some View {
        let cards = store.active.filter { $0.kind == .card }.sorted { $0.apr(on: store.today) > $1.apr(on: store.today) }
        let top = max(cards.first?.apr(on: store.today) ?? 0, 0.01)
        return Tile {
            TileLabel("Cost ranking")
            TileNote("Interest per $100 a month")
            VStack(spacing: 0) {
                ForEach(cards) { card in
                    let rate = card.apr(on: store.today)
                    HStack(spacing: 10) {
                        Text(card.brandStyle.id == "other" ? card.provider : card.brandStyle.short)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(width: 92, alignment: .leading)
                        ProgressBar(fraction: rate / top, color: Theme.primaryFill, height: 8)
                        Text((rate / 12).usd)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(height: 34)
                }
            }
            .padding(.top, 10)
            if cards.isEmpty { TileNote("Add a credit card to see how they compare.") }
        }
    }

    @ViewBuilder private var quickWin: some View {
        if let next = store.extraOrder.first {
            Tile {
                HStack(spacing: 12) {
                    IconCircle(symbol: "flag", background: Theme.greenSoft, color: Theme.greenText)
                    VStack(alignment: .leading, spacing: 0) {
                        SmallCaption("Quick win")
                        Text("Finish \(next.title) next").font(.headline)
                        Text(winNote(next))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private func winNote(_ debt: Debt) -> String {
        guard let paydays = store.plan.paydaysToPayoff[debt.id] else { return "\(debt.balance.usd) left." }
        return "\(debt.balance.usd) left. Gone in \(Fmt.plural(paydays, "payday"))."
    }

    @ViewBuilder private var alertList: some View {
        let items = alerts
        if items.isEmpty {
            Tile { TileNote("Nothing needs your attention.") }
        } else {
            CardGroup {
                ForEach(items) { alert in
                    if alert.id != items.first?.id { RowDivider(inset: 68) }
                    HStack(spacing: 12) {
                        IconCircle(symbol: alert.symbol,
                                   background: alert.level == .overdue ? Theme.redSoft : (alert.level == .soon ? Theme.orangeSoft : Theme.fill),
                                   color: alert.level == .overdue ? Theme.red : (alert.level == .soon ? Theme.orange : .primary))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(alert.title).font(.callout.weight(.semibold))
                            Text(alert.detail).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                }
            }
        }
    }

    @ViewBuilder private var recap: some View {
        let start = Cal.addMonths(-1, to: Cal.monthStart(store.today))
        let end = Cal.monthStart(store.today)
        let paid = store.data.payments.filter { $0.isPayment && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
        if paid > 0 {
            let interest = store.data.debts.reduce(0.0) { sum, debt in
                sum + (PayoffEngine.pastSlices(debt: debt, payments: store.data.payments, today: store.today, months: 1).first?.interest ?? 0)
            }
            // The balance change comes from the recorded history when it covers the month; otherwise it is estimated.
            let before = store.balance(in: .total, before: start), after = store.balance(in: .total, before: end)
            let down = before.flatMap { b in after.map { b - $0 } } ?? (paid - interest)
            SectionHeader(title: "\(Fmt.monthName(start)) recap").padding(.top, 16)
            Tile {
                HStack {
                    recapPart("Paid", paid.usd, .primary)
                    Spacer()
                    recapPart("Interest, about", interest.usd, .primary)
                    Spacer()
                    if down >= 0 {
                        recapPart("Balance down", down.usd, Theme.green)
                    } else {
                        recapPart("Balance up", (-down).usd, .primary)
                    }
                }
            }
        }
    }

    private func recapPart(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Export

struct ExportContent: View {
    @Environment(AppStore.self) private var store

    @State private var csvURL: URL?
    @State private var pdfURL: URL?
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: AppData?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CardGroup {
                    shareRow("tablecells", "CSV export", "Debts and payments as a spreadsheet", csvURL)
                    RowDivider(inset: 68)
                    shareRow("doc.text", "PDF report", "Your debts, plan and charts, ready to print", pdfURL)
                }
                SectionHeader(title: "Backup").padding(.top, 18)
                CardGroup {
                    Button { exporting = true } label: {
                        ExportRow(symbol: "arrow.down.to.line", title: "Back Up Now", detail: "Saves a file you choose where to keep")
                    }
                    RowDivider(inset: 68)
                    Button { importing = true } label: {
                        ExportRow(symbol: "clock.arrow.circlepath", title: "Restore from Backup", detail: "Replaces what is on this iPhone")
                    }
                }
                .buttonStyle(.plain)
                Text(store.settings.lastBackup.map { "Last backup: \(Fmt.full($0))" } ?? "No backup yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .onAppear(perform: prepare)
        .fileExporter(isPresented: $exporting, document: BackupDocument(data: store.data), contentType: .json,
                      defaultFilename: "APRFree backup \(Fmt.isoDay(store.today))") { result in
            if case .success = result { store.updateSettings { $0.lastBackup = AppClock.now } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let raw = try? Data(contentsOf: url), let data = try? Persistence.read(raw) {
                pending = data
            } else {
                failed = true
            }
        }
        .confirmationDialog("Replace everything on this iPhone with the backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let pending { store.restore(pending) }
                pending = nil
            }
        }
        .alert("That file isn’t an APRFree backup.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func prepare() {
        csvURL = Exporter.write(Data(Exporter.csv(store.data).utf8), named: "APRFree.csv")
        pdfURL = Exporter.write(Report.pdf(for: store), named: "APRFree report.pdf")
    }

    @ViewBuilder private func shareRow(_ symbol: String, _ title: String, _ detail: String, _ url: URL?) -> some View {
        if let url {
            ShareLink(item: url) { ExportRow(symbol: symbol, title: title, detail: detail) }
                .buttonStyle(.plain)
        } else {
            ExportRow(symbol: symbol, title: title, detail: detail).opacity(0.5)
        }
    }
}

private struct ExportRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            IconCircle(symbol: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }
}
