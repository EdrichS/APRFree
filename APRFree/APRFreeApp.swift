import SwiftUI

@main
struct APRFreeApp: App {
    @State private var store = AppStore.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

/// Everything that opens from the two pages as a full-screen view.
enum Route: Identifiable, Hashable {
    case debt(UUID)
    case addDebt(DebtKind?)
    case strategy, simulator, insights, income, extraMoney, export, settings, activity, breakdown, connected
    /// One month's statement, by the first day of the month.
    case statement(Date)

    var id: String {
        switch self {
        case .debt(let id): "debt-\(id)"
        case .statement(let month): "statement-\(month.timeIntervalSince1970)"
        case .income: "income"
        case .extraMoney: "extraMoney"
        case .addDebt: "addDebt"
        case .strategy: "strategy"
        case .simulator: "simulator"
        case .insights: "insights"
        case .export: "export"
        case .settings: "settings"
        case .activity: "activity"
        case .breakdown: "breakdown"
        case .connected: "connected"
        }
    }
}

/// A request to open the payment sheet: the payday split, extra money that is not a paycheck, or one debt.
struct PaymentRequest: Identifiable {
    let id = UUID()
    var debtID: UUID?
    var extraMoney = false
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if store.settings.onboarded && !store.settings.hasAcceptedLegal {
                // Data set up before the privacy policy and the disclaimer existed: they are shown once.
                LegalGate()
                    .transition(OnboardingMotion.finishTransition)
            } else if store.settings.onboarded {
                MainPager()
                    .transition(OnboardingMotion.finishTransition)
            } else {
                OnboardingView()
                    .transition(OnboardingMotion.finishTransition)
            }
            if let debt = store.celebration {
                CelebrationView(debt: debt) { store.celebration = nil }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.celebration?.id)
        .animation(OnboardingMotion.finish, value: store.settings.onboarded)
        .tint(Theme.primaryFill)
        // Date pickers and charts read dates in the same time zone as the app's own calendar math.
        .environment(\.calendar, Cal.calendar)
        .environment(\.timeZone, Cal.zone)
        // The app can sit in memory overnight. Coming back to the front, the date may have changed.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            store.refreshForToday()
            // With Connected mode on, the banks are asked for new figures at most once a day.
            Task { await store.refreshBanksIfDue() }
        }
        // And it can be open on screen as midnight passes.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refreshForToday()
        }
    }
}

/// Page 1 is the card stack, page 2 is Progress, page 3 is Statements, page 4 is Credit
/// Utilization. Swipe between them.
struct MainPager: View {
    @Environment(AppStore.self) private var store
    @State fileprivate var page = 0
    @State fileprivate var route: Route?
    @State fileprivate var payment: PaymentRequest?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                HomeView(route: $route, payment: $payment).tag(0)
                ProgressPage(route: $route).tag(1)
                StatementsPage(route: $route).tag(2)
                UtilizationPage().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Theme.bg)
            .ignoresSafeArea(.container, edges: .bottom)

            PageDots(count: 4, index: page)
                .padding(.bottom, 4)
        }
        .background(Theme.bg.ignoresSafeArea())
        .fullScreenCover(item: $route) { route in
            RouteView(route: route)
                .tint(Theme.primaryFill)
        }
        .sheet(item: $payment) { request in
            PaymentSheet(request: request)
                .tint(Theme.primaryFill)
        }
        #if DEBUG
        .onAppear { openDebugRoute() }
        #endif
    }
}

#if DEBUG
extension MainPager {
    /// `-screen <name>` opens straight on a screen, for screenshots: progress, statements, utilization,
    /// strategy, simulator, insights, income, extra, export, settings, connected, activity, breakdown,
    /// add, pay, celebrate, or a debt's provider name such as "chase" or "klarna".
    fileprivate func openDebugRoute() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.count > i + 1 else { return }
        let name = args[i + 1].lowercased()
        switch name {
        case "progress": page = 1
        case "statements": page = 2
        case "utilization": page = 3
        case "connected": route = .connected
        case "income": route = .income
        case "extra": payment = PaymentRequest(extraMoney: true)
        case "strategy": route = .strategy
        case "simulator": route = .simulator
        case "insights": route = .insights
        case "export": route = .export
        case "settings": route = .settings
        case "activity": route = .activity
        case "breakdown": route = .breakdown
        case "add": route = .addDebt(nil)
        case "pay": payment = PaymentRequest()
        case "celebrate": store.celebration = store.data.debts.first
        default:
            if let debt = store.data.debts.first(where: { $0.title.lowercased().hasPrefix(name) }) { route = .debt(debt.id) }
        }
    }
}
#endif

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .debt(let id): DebtDetailView(debtID: id)
        case .addDebt(let kind): AddDebtFlow(startKind: kind)
        case .strategy: ToolScreen(title: "Strategy") { StrategyContent() }
        case .simulator: ToolScreen(title: "Simulator") { SimulatorContent() }
        case .insights: ToolScreen(title: "Insights") { InsightsContent() }
        case .income: ToolScreen(title: "Income") { IncomeContent() }
        case .extraMoney: PaymentSheet(request: PaymentRequest(extraMoney: true))
        case .statement(let month): ToolScreen(title: "Statement") { StatementDetail(month: month) }
        case .export: ToolScreen(title: "Export") { ExportContent() }
        case .settings: ToolScreen(title: "Settings") { SettingsContent() }
        case .activity: ToolScreen(title: "Activity") { ActivityContent() }
        case .breakdown: ToolScreen(title: "Balances") { BreakdownContent() }
        case .connected: ToolScreen(title: "Connected") { ConnectedContent() }
        }
    }
}

/// The shared frame for full-screen tools: a title and a close button.
struct ToolScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
        }
    }
}
