import SwiftUI

/// Page 1: total balance, the card stack, loans and the tool passes.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var route: Route?
    @Binding var payment: PaymentRequest?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.data.debts.isEmpty {
                    emptyState
                } else {
                    CardStack(debts: store.stack, openTotal: { route = .breakdown }) { route = .debt($0.id) }
                    loans
                    tools
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .background(Theme.bg)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Text("APRFree")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Make a Payment") { payment = PaymentRequest() }
                .buttonStyle(GreenPillStyle())
                .disabled(store.active.isEmpty)
            Button { route = .addDebt(nil) } label: { GlassCircle(symbol: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a debt")
            Menu {
                Button("Strategy", systemImage: "list.number") { route = .strategy }
                Button("Simulator", systemImage: "slider.horizontal.3") { route = .simulator }
                Button("Insights", systemImage: "lightbulb") { route = .insights }
                Button("Export", systemImage: "square.and.arrow.up") { route = .export }
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
                ToolPass(symbol: "square.and.arrow.up", title: "Export", detail: backupText) { route = .export }
            }
        }
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
