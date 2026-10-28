import Charts
import SwiftUI

/// Page 4, the last: how much of the credit limits is in use, how that has moved month by month,
/// and where the plan takes it.
///
/// Everything here is measured against today's limits; past limits are not kept.
struct UtilizationPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let cards = store.limitedCards
        ScrollView {
            VStack(spacing: 12) {
                if cards.isEmpty {
                    Tile {
                        TileNote(store.data.debts.contains { $0.kind == .card }
                                 ? "Add a credit limit to a card (Edit on its screen) to see how much of it is in use."
                                 : "Add a credit card with its limit to see how much of it is in use.")
                    }
                } else {
                    let months = store.utilizationMonths
                    chart
                    changes(months)
                    SectionHeader(title: "By Month", detail: months.count > 1 ? Fmt.plural(months.count, "month") : nil).padding(.top, 16)
                    monthList(months)
                    SectionHeader(title: "By Card").padding(.top, 16)
                    cardList(cards)
                    notes
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Credit Utilization")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .background { TopBarFade() }
        }
        .background(Theme.bg)
    }

    /// Whole percents, except close to the 30% line, where "30%" could mean either side of it.
    private func percent(_ value: Double) -> String {
        abs(value - 0.3) < 0.01 && abs(value - 0.3) > 0.00005 ? String(format: "%.1f%%", value * 100) : "\(Int((value * 100).rounded()))%"
    }

    /// A change in utilization, in percentage points: "Down 2.1 pts".
    private func points(_ change: Double) -> String {
        let size = abs(change * 100)
        if size < 0.05 { return "No change" }
        return "\(change < 0 ? "Down" : "Up") \(String(format: "%.1f", size)) pts"
    }

    /// Lower is the good direction, so only a fall is green.
    private func color(_ change: Double) -> Color {
        change * 100 <= -0.05 ? Theme.green : Color.primary
    }

    // MARK: Now, over time, and on the plan

    private var chart: some View {
        let history = store.utilizationHistory
        let planned = store.utilizationPlan
        let now = store.utilization ?? 0
        let start = history.first?.date ?? store.today
        let end = max(planned.last?.date ?? store.today, Cal.addMonths(1, to: store.today))
        let top = max(0.4, ((history + planned).map(\.total).max() ?? 0) * 1.1, now * 1.1)
        let under = planned.first { $0.total < 0.3 }?.date
        return Tile {
            HStack {
                TileLabel("All cards")
                Spacer()
                LegendMark(text: "History", color: .primary)
                LegendMark(text: "Plan", dashed: true, color: .primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(percent(now))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(now < 0.3 ? Theme.green : Color.primary)
                Text("of \(store.creditLimit.usd) in use")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 2)
            Chart {
                ForEach(history) { point in
                    LineMark(x: .value("Date", point.date), y: .value("In use", point.total), series: .value("Line", "History"))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                ForEach(planned) { point in
                    LineMark(x: .value("Date", point.date), y: .value("In use", point.total), series: .value("Line", "Plan"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5, 5]))
                }
                RuleMark(y: .value("Line", 0.3))
                    .foregroundStyle(Theme.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("30%").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...top)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let share = value.as(Double.self) { Text(percent(share)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                    let span = end.timeIntervalSince(start)
                    if let date = value.as(Date.self), span > 0, (0.07...0.93).contains(date.timeIntervalSince(start) / span) {
                        AxisValueLabel { Text(Cal.days(from: start, to: end) <= 100 ? Fmt.monthDay(date) : Fmt.monthAndShortYear(date)) }
                    }
                }
            }
            .frame(height: 170)
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .clipped()
            .padding(.horizontal, -12)
            .accessibilityLabel("Credit utilization over time. Now \(percent(now)).")
            TileNote(summary(now: now, under: under))
        }
    }

    private func summary(now: Double, under: Date?) -> String {
        if now < 0.3 { return "Under 30% across your cards." }
        if let under { return "On your plan, your cards together drop under 30% on \(Fmt.full(under))." }
        return store.hasIncome ? "Your current plan does not bring your cards under 30%." : "Add your income to see when this drops under 30%."
    }

    // MARK: Change

    @ViewBuilder private func changes(_ months: [UtilizationMonth]) -> some View {
        let now = store.utilization ?? 0
        let thisMonth = months.last?.change
        let first = months.first
        // Where two months tie, the later one is named.
        let lowest = months.reversed().min { $0.share < $1.share - 1e-9 }
        TileRow(minHeight: 96) {
            if let thisMonth {
                StatTile(label: "This month", value: points(thisMonth), note: "since \(Fmt.monthDay(Cal.monthStart(store.today)))",
                         valueColor: color(thisMonth))
            } else {
                StatTile(label: "This month", value: percent(now), note: "the first month on record")
            }
            if let first, months.count > 1 {
                StatTile(label: "Since \(Fmt.monthAndShortYear(first.month))", value: points(now - first.share),
                         note: "from \(percent(first.share)) to \(percent(now))", valueColor: color(now - first.share))
            } else {
                StatTile(label: "Available credit", value: max(0, store.creditLimit - store.limitedCards.reduce(0) { $0 + $1.balance }).usd,
                         note: "left across your cards")
            }
        }
        TileRow(minHeight: 96) {
            let owed = store.toReachThirtyPercent
            StatTile(label: "To get under 30%", value: owed > 0 ? owed.usd : "Done",
                     note: owed > 0 ? "off your cards together" : "your cards are under it", valueColor: owed > 0 ? .primary : Theme.green)
            if let lowest, months.count > 1 {
                StatTile(label: "Lowest month", value: percent(lowest.share), note: lowest.isCurrent ? "this month" : Fmt.monthNameYear(lowest.month))
            } else {
                StatTile(label: "Credit limits", value: store.creditLimit.usd, note: Fmt.plural(store.limitedCards.count, "card"))
            }
        }
    }

    /// Every month on record, newest first, with how far it moved from the month before.
    private func monthList(_ months: [UtilizationMonth]) -> some View {
        CardGroup {
            let rows = Array(months.reversed())
            ForEach(rows) { month in
                if month.id != rows.first?.id { RowDivider() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.monthNameYear(month.month)).font(.callout.weight(.semibold)).lineLimit(1)
                        if month.isCurrent { Text("so far").font(.caption).foregroundStyle(Theme.secondary) }
                        Spacer(minLength: 8)
                        Text(percent(month.share))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(month.share < 0.3 ? Theme.green : Color.primary)
                    }
                    ProgressBar(fraction: min(1, month.share), color: month.share < 0.3 ? Theme.green : Theme.primaryFill, height: 6)
                    if let change = month.change {
                        HStack(spacing: 4) {
                            if abs(change * 100) >= 0.05 {
                                Image(systemName: change < 0 ? "arrow.down" : "arrow.up").font(.caption2.weight(.bold))
                            }
                            Text("\(points(change)) from \(Fmt.monthName(Cal.addMonths(-1, to: month.month)))")
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(change * 100 <= -0.05 ? Theme.green : Theme.secondary)
                    } else {
                        Text("Where your record starts").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Card by card

    private func cardList(_ cards: [Debt]) -> some View {
        CardGroup {
            let monthStart = Cal.addDays(-1, to: Cal.monthStart(store.today))
            ForEach(cards) { card in
                if card.id != cards.first?.id { RowDivider() }
                let share = card.utilization ?? 0
                let before = store.utilization(of: card, on: monthStart)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(percent(share))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(share < 0.3 ? Theme.green : Color.primary)
                    }
                    ProgressBar(fraction: min(1, share), color: share < 0.3 ? Theme.green : Theme.primaryFill, height: 6)
                    Text(note(card, share))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                    if let before, card.addedAt <= monthStart {
                        Text("\(points(share - before)) this month")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle((share - before) * 100 <= -0.05 ? Theme.green : Theme.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func note(_ card: Debt, _ share: Double) -> String {
        let limit = card.creditLimit ?? 0
        let base = "\(card.balance.usd) of \(limit.usd)"
        if share < 0.3 { return "\(base) · already under 30%" }
        guard let date = store.under30Date(for: card) else { return "\(base) · not under 30% on your current plan" }
        return "\(base) · under 30% (\((limit * 0.3).usd)) by \(Fmt.full(date))"
    }

    // MARK: What this is measured against

    @ViewBuilder private var notes: some View {
        let missing = store.data.debts.filter { $0.kind == .card && ($0.creditLimit ?? 0) <= 0 }
        VStack(alignment: .leading, spacing: 8) {
            Text("Measured against today’s limits. Past limits are not kept, so an earlier month is shown against the limit each card has now.")
            if !missing.isEmpty {
                Text("\(missing.map(\.title).formatted(.list(type: .and))) \(missing.count == 1 ? "has" : "have") no credit limit set, so \(missing.count == 1 ? "it is" : "they are") left out.")
            }
            Text("30% is a common rule of thumb, not a statement about your credit score.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
