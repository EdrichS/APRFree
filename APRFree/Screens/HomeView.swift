import SwiftUI

/// Page 1: total balance, the card stack, loans and the tool passes.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var route: Route?
    @Binding var payment: PaymentRequest?
    @State private var confirming: HistoryStep?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.data.debts.isEmpty {
                    emptyState
                } else {
                    // Cards are drawn at a fixed size, like the real thing, so their text stops growing where it would collide.
                    CardStack(debts: store.stack, openTotal: { route = .breakdown }) { route = .debt($0.id) }
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    loans
                    tools
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .background(Theme.bg)
        .historyStepAlert($confirming)
        // Anything the app corrected on its own is said once, then forgotten.
        .alert("Due dates corrected", isPresented: Binding(get: { !store.settings.notices.isEmpty }, set: { if !$0 { store.dismissNotices() } })) {
            Button("OK") { store.dismissNotices() }
        } message: {
            Text("An earlier version moved a due date forward with every payment. Dates that went further than your payments allow were pulled back:\n\n\(store.settings.notices.joined(separator: "\n"))\n\nIf one is still not right, change it under Edit on that card or loan.")
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Text("APRFree")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button("Make a Payment") { payment = PaymentRequest() }
                .buttonStyle(GreenPillStyle())
                .disabled(store.active.isEmpty)
                .layoutPriority(1)
            Button { route = .addDebt(nil) } label: { GlassCircle(symbol: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a debt")
            Menu {
                // The last action, whatever it was, can be taken back from here, and put back again.
                Button(store.undoLabel.map { "Undo \($0)" } ?? "Undo", systemImage: "arrow.uturn.backward") { confirming = .undo }
                    .disabled(store.undoLabel == nil)
                Button(store.redoLabel.map { "Redo \($0)" } ?? "Redo", systemImage: "arrow.uturn.forward") { confirming = .redo }
                    .disabled(store.redoLabel == nil)
                Divider()
                Button("Strategy", systemImage: "list.number") { route = .strategy }
                Button("Simulator", systemImage: "slider.horizontal.3") { route = .simulator }
                Button("Insights", systemImage: "lightbulb") { route = .insights }
                Button("Income", systemImage: "banknote") { route = .income }
                Button("Extra Money", systemImage: "plus.circle") { route = .extraMoney }
                Button("Export", systemImage: "square.and.arrow.up") { route = .export }
                // Only in a build that has a bank service behind it.
                if store.connectedAvailable {
                    Button("Connected", systemImage: "link") { route = .connected }
                }
                Divider()
                Button("Settings", systemImage: "gearshape") { route = .settings }
            } label: {
                GlassCircle(symbol: "ellipsis")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .background { TopBarFade() }
        // The bar is one fixed row. Past this size the main button's name would be cut short.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder private var loans: some View {
        if !store.loans.isEmpty {
            SectionHeader(title: "Loans", detail: store.total(of: .loan).usd)
                .padding(.top, 28)
            ForEach(store.loans) { loan in
                Button { route = .debt(loan.id) } label: { LoanPass(debt: loan) }
                    .buttonStyle(.plain)
                    .padding(.top, loan.id == store.loans.first?.id ? 10 : 12)
            }
        }
    }

    private var tools: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Tools")
                .padding(.top, 28)
                .padding(.bottom, -2)
            HStack(spacing: 12) {
                ToolPass(symbol: "list.number", title: "Strategy", detail: store.strategySummary) { route = .strategy }
                ToolPass(symbol: "slider.horizontal.3", title: "Simulator", detail: debtFreeText) { route = .simulator }
            }
            HStack(spacing: 12) {
                ToolPass(symbol: "lightbulb", title: "Insights", detail: quickWinText) { route = .insights }
                ToolPass(symbol: "banknote", title: "Income", detail: incomeText) { route = .income }
            }
            HStack(spacing: 12) {
                ToolPass(symbol: "plus.circle", title: "Extra Money", detail: "Where should it go?") { route = .extraMoney }
                ToolPass(symbol: "square.and.arrow.up", title: "Export", detail: backupText) { route = .export }
            }
        }
    }

    private var incomeText: String {
        if store.settings.useFixedAmount { return "\(store.settings.fixedAmount.usd) a month" }
        guard let next = store.upcomingPaydays(1).first, store.hasIncome else { return "Add your income" }
        return "Next payday \(Fmt.monthDay(next.day.date))"
    }

    private var debtFreeText: String {
        store.plan.debtFree.map { "Debt-free \(Fmt.monthYear($0))" } ?? "Try a what-if"
    }

    private var quickWinText: String {
        store.extraOrder.first.map { "Finish \($0.title) next" } ?? "Nothing left to pay"
    }

    private var backupText: String {
        store.settings.lastBackup.map { "Last backup: \(Fmt.monthDay($0))" } ?? "No backup yet"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Button { route = .addDebt(nil) } label: {
                VStack(spacing: 10) {
                    IconCircle(symbol: "plus", size: 48, background: Theme.card)
                    Text("Add your first card").font(.headline)
                    Text("Credit card, pay later plan or loan")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: CardFace.height)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Everything stays on your iPhone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 8)
    }
}

/// The Total Balance card with every card and pay-later plan stacked on it, top strips showing.
struct CardStack: View {
    let debts: [Debt]
    let openTotal: () -> Void
    let open: (Debt) -> Void

    private let strip: CGFloat = 54
    private let totalVisible: CGFloat = 140

    private var height: CGFloat {
        debts.isEmpty ? totalVisible : totalVisible + CGFloat(debts.count - 1) * strip + CardFace.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: openTotal) {
                TotalBalanceCard(height: debts.isEmpty ? totalVisible : totalVisible + 32)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the breakdown of your balances")
            ForEach(Array(debts.enumerated()), id: \.element.id) { index, debt in
                Button { open(debt) } label: {
                    CardFace(debt: debt, inStack: index < debts.count - 1)
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.16), radius: 5, y: -3)
                .offset(y: totalVisible + CGFloat(index) * strip)
            }
        }
        .frame(height: height, alignment: .top)
    }
}

struct TotalBalanceCard: View {
    @Environment(AppStore.self) private var store
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOTAL BALANCE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                Spacer()
                // Tapping the card opens the breakdown.
                Image(systemName: "chart.pie").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.totalSecondary)
            Text(store.total.usd)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
            HStack(spacing: 14) {
                part("Cards", store.total(of: .card))
                divider
                part("Pay later", store.total(of: .payLater))
                divider
                part("Loans", store.total(of: .loan))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .top)
        .foregroundStyle(.white)
        .background(Theme.totalCard, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
    }

    private func part(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.totalSecondary)
            Text(value.usd).font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
