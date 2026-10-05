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
    case strategy, simulator, insights, export, settings, activity, breakdown

    var id: String {
        switch self {
        case .debt(let id): "debt-\(id)"
        case .addDebt: "addDebt"
        case .strategy: "strategy"
        case .simulator: "simulator"
        case .insights: "insights"
        case .export: "export"
        case .settings: "settings"
        case .activity: "activity"
        case .breakdown: "breakdown"
        }
    }
}

/// A request to open the payment sheet: the payday split, or one debt.
struct PaymentRequest: Identifiable {
    let id = UUID()
    var debtID: UUID?
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if store.settings.onboarded {
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
            if phase == .active { store.refreshForToday() }
        }
    }
}

/// Page 1 is the card stack, page 2 is Progress. Swipe between them.
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
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Theme.bg)
            .ignoresSafeArea(.container, edges: .bottom)

            PageDots(count: 2, index: page)
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
    /// `-screen <name>` opens straight on a screen, for screenshots: progress, strategy, simulator,
    /// insights, export, settings, add, pay, celebrate, or a debt's provider name such as "chase" or "klarna".
    fileprivate func openDebugRoute() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.count > i + 1 else { return }
        let name = args[i + 1].lowercased()
        switch name {
        case "progress": page = 1
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
        case .export: ToolScreen(title: "Export") { ExportContent() }
        case .settings: ToolScreen(title: "Settings") { SettingsContent() }
        case .activity: ToolScreen(title: "Activity") { ActivityContent() }
        case .breakdown: ToolScreen(title: "Balances") { BreakdownContent() }
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
