import Charts
import SwiftUI

/// Page 2: the payoff countdown and balance chart for everything, the credit cards or the loans,
/// then what is paid off and what is coming up.
struct ProgressPage: View {
    @Environment(AppStore.self) private var store
    @Binding var route: Route?

    @AppStorage("progressScope") private var savedScope = DebtScope.total.rawValue
    /// The page showing in the swipeable countdown. Optional because that is what scroll position binds to.
    @State private var scope: DebtScope? = .total
    @State private var showAllUpcoming = false

    private var current: DebtScope { scope ?? .total }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                scopePager
                Group {
                    SectionHeader(title: "Paid Off").padding(.top, 16)
                    shelf
                    SectionHeader(title: "Upcoming", detail: "Next 30 days").padding(.top, 16)
                    upcoming
                    SectionHeader(title: "Activity").padding(.top, 16)
                    activity
                    CardGroup {
                        Button { route = .settings } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gearshape").font(.system(size: 19))
                                Text("Settings")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Progress")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
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
        .onAppear { scope = DebtScope(rawValue: savedScope) ?? .total }
        .onChange(of: scope) { _, value in savedScope = (value ?? .total).rawValue }
    }

    // MARK: Total / Credit cards / Loans

    /// Tap a segment or swipe the cards, like a widget stack. The countdown and its chart move together.
    private var scopePager: some View {
        VStack(spacing: 12) {
            Picker("Show", selection: Binding(get: { current }, set: { value in withAnimation { scope = value } })) {
                ForEach(DebtScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.margin)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(DebtScope.allCases) { item in
                        VStack(spacing: 12) {
                            countdown(item)
                            chart(item)
                        }
                        .padding(.horizontal, Theme.margin)
                        .containerRelativeFrame(.horizontal)
                        .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scope)
            .scrollIndicators(.hidden)

            StepDots(count: DebtScope.allCases.count, index: DebtScope.allCases.firstIndex(of: current) ?? 0)
        }
    }

    private func countdown(_ scope: DebtScope) -> some View {
        let fraction = store.fractionPaid(in: scope)
        let percent = Int((fraction * 100).rounded())
        return Tile(padding: 16) {
            HStack(spacing: 16) {
                ProgressRing(fraction: fraction, lineWidth: 10, color: Theme.green) {
                    VStack(spacing: 0) {
                        Text("\(percent)%").font(.system(size: 22, weight: .bold)).monospacedDigit()
                        Text("paid").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(percent) percent paid")
                VStack(alignment: .leading, spacing: 0) {
                    Text(scope.freeLabel.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.secondary)
                    Text(headline(scope))
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subline(scope)).font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("\(store.paidSoFar(in: scope).usd) of \(store.startTotal(in: scope).usd) paid")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 132)
    }

    private func noun(_ scope: DebtScope) -> String {
        switch scope {
        case .total: "debts"
        case .cards: "credit cards"
        case .loans: "loans"
        }
    }

    private func headline(_ scope: DebtScope) -> String {
        let debts = store.debts(in: scope)
        if debts.isEmpty { return "No \(noun(scope)) yet" }
        if debts.allSatisfy(\.isPaidOff) { return "Paid off" }
        return store.free(in: scope).map(Fmt.monthYear) ?? "Not yet"
    }

    private func subline(_ scope: DebtScope) -> String {
        let debts = store.debts(in: scope)
        if debts.isEmpty { return "Add one to see your date" }
        if debts.allSatisfy(\.isPaidOff) { return "Nothing left to pay here" }
        guard let free = store.free(in: scope) else {
            return store.hasIncome ? "Raise what goes to debt" : "Add your income"
        }
        return "\(Fmt.plural(max(0, Cal.months(from: store.today, to: free)), "month")) to go"
    }

    /// History is solid, the plan is dashed, and a dot marks each payoff in this scope.
    private func chart(_ scope: DebtScope) -> some View {
        let plan = store.plan
        let history = store.data.history.compactMap { point in point.value(scope).map { PlanPoint(date: point.date, total: $0) } }
        // A plan that never finishes has no payoff to draw toward: without enough money going in, the
        // balance only grows, and that line would run off the chart. Show the history alone instead.
        // Otherwise stop the line where this scope reaches zero rather than running flat to the end.
        var planned: [PlanPoint] = []
        for point in plan.finished ? plan.series : [] {
            planned.append(PlanPoint(date: point.date, total: point.value(scope)))
            if point.value(scope) <= 0.005 { break }
        }
        let ids = Set(store.debts(in: scope).map(\.id))
        let balanceAt = Dictionary(planned.map { ($0.date, $0.total) }, uniquingKeysWith: { first, _ in first })
        let payoffs = Set(plan.payoffPayday.filter { ids.contains($0.key) }.values).sorted()
            .map { PlanPoint(date: $0, total: balanceAt[$0] ?? 0) }
        // All three charts share one time axis, so swiping between them compares like with like.
        let start = store.data.history.first?.date ?? store.today
        let end = max(planned.last?.date ?? store.today, plan.finished ? plan.series.last?.date ?? store.today : store.today,
                      Cal.addMonths(1, to: store.today))
        let top = max(history.map(\.total).max() ?? 0, planned.map(\.total).max() ?? 0, store.balance(in: scope), 1)
        // A little room past the last date, so the final payoff dot is drawn whole.
        let edge = end.addingTimeInterval(end.timeIntervalSince(start) * 0.025)
        let empty = store.debts(in: scope).isEmpty
        let noPlan = !empty && !plan.finished && store.balance(in: scope) > 0.005

        return Tile {
            HStack {
                TileLabel(scope == .total ? "Balance over time" : "\(scope.title) over time")
                Spacer()
                LegendMark(text: "History", color: .primary)
                LegendMark(text: "Plan", dashed: true, color: .primary)
                LegendMark(text: "Payoff", dot: true, color: Theme.green)
            }
            Chart {
                ForEach(history) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.total), series: .value("Line", "History"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                if history.count == 1, let only = history.first {
                    // One day of history has no line to draw yet, so mark where it starts.
                    PointMark(x: .value("Date", only.date), y: .value("Balance", only.total))
                        .foregroundStyle(Color.primary)
                        .symbolSize(40)
                }
                ForEach(planned) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.total), series: .value("Line", "Plan"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5, 5]))
                }
                ForEach(payoffs) { point in
                    PointMark(x: .value("Date", point.date), y: .value("Balance", point.total))
                        .foregroundStyle(Theme.green)
                        .symbolSize(46)
                }
                RuleMark(x: .value("Today", store.today))
                    .foregroundStyle(Theme.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("Today").font(.caption2.weight(.semibold))
                    }
            }
            .chartXScale(domain: start...edge)
            .balanceAxes(top: top, from: start, to: end)
            .frame(height: 170)
            .padding(.top, 26)
            // Nothing drawn can leave the tile. The clip takes in the band above the plot, where the
            // "Today" label sits, and a margin each side for the first and last axis labels; clipping
            // the plot alone would cut those off.
            .padding(.horizontal, 12)
            .clipped()
            .padding(.horizontal, -12)
            .overlay {
                if empty {
                    Text("Add \(scope == .cards ? "a credit card" : scope == .loans ? "a loan" : "a debt") to see it here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            if noPlan {
                TileNote(store.hasIncome
                         ? "No payoff plan yet: what goes to debt does not keep up with the interest. Raise it under Income."
                         : "No payoff plan yet. Add your income under Tools on the first page to see one.")
            }
        }
        .frame(minHeight: 252)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scope.title) balance over time. Now \(store.balance(in: scope).usd).")
    }

    // MARK: Paid Off shelf

    /// Finished loans and pay-later plans. A paid-off credit card is not here: it stays on the home screen at $0.00.
    private var shelf: some View {
        Tile {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.shelf) { debt in
                        Button { route = .debt(debt.id) } label: { MiniCard(debt: debt, stamped: true) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(debt.title), paid off")
                    }
                    if let next = store.nextForShelf {
                        VStack(spacing: 2) {
                            Text("Next up").font(.caption).foregroundStyle(Theme.secondary)
                            Text(next.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 8)
                        .frame(width: store.shelf.isEmpty ? 190 : 120, height: 120)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    if store.shelf.isEmpty {
                        Text("Paid-off loans and pay-later plans land here with a stamp.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 120, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: Upcoming

    @ViewBuilder private var upcoming: some View {
        let all = store.upcoming(days: 30)
        let shown = showAllUpcoming ? all : Array(all.prefix(5))
        if all.isEmpty {
            Tile { TileNote("Nothing due in the next 30 days.") }
        } else {
            CardGroup {
                ForEach(shown) { item in
                    if item.id != shown.first?.id { RowDivider() }
                    let status = DueStatus(due: item.date, today: store.today)
                    HStack(spacing: 10) {
                        Text(Fmt.monthDay(item.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(dateColor(status))
                            .frame(width: 54, alignment: .leading)
                        Swatch(debt: item.debt)
                        Text(item.debt.title).font(.callout).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.amount.usd).font(.callout).monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(status.text)
                }
                if all.count > 5 {
                    RowDivider()
                    Button(showAllUpcoming ? "Show fewer" : "See all \(all.count)") { showAllUpcoming.toggle() }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
            }
        }
    }

    private func dateColor(_ status: DueStatus) -> Color {
        switch status {
        case .overdue: Theme.red
        case .soon: Theme.orange
        case .later: .primary
        }
    }

    // MARK: Activity

    /// The five most recent entries. Everything older is one tap away.
    @ViewBuilder private var activity: some View {
        let all = store.activity
        let recent = Array(all.prefix(5))
        if recent.isEmpty {
            Tile { TileNote("Payments you mark as paid show up here.") }
        } else {
            CardGroup {
                ForEach(recent) { record in
                    if record.id != recent.first?.id { RowDivider(inset: 64) }
                    ActivityEntry(record: record)
                }
                RowDivider()
                Button { route = .activity } label: {
                    HStack(spacing: 6) {
                        Text("Show All Activity")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tertiary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("\(all.count) entries")
            }
        }
    }
}
