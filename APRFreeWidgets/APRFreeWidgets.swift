import AppIntents
import SwiftUI
import WidgetKit

/// The choice offered when you edit a widget: which balance it follows.
enum WidgetScope: String, AppEnum {
    case total, cards, loans

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Balance"
    static let caseDisplayRepresentations: [WidgetScope: DisplayRepresentation] = [
        .total: "Total", .cards: "Credit cards", .loans: "Loans",
    ]

    var scope: DebtScope {
        switch self {
        case .total: .total
        case .cards: .cards
        case .loans: .loans
        }
    }
}

struct BalanceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Balance"
    static let description: IntentDescription? = IntentDescription("Choose which balance the widget follows.")

    @Parameter(title: "Show", default: .total)
    var show: WidgetScope
}

/// The eye button on the widget: hides the balances, or shows them again. It runs without opening the app.
struct ToggleBalancesIntent: AppIntent {
    static let title: LocalizedStringResource = "Hide or Show Balances"
    static let description: IntentDescription? = IntentDescription("Hides the balances on the APRFree widgets, or shows them again.")

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.balancesHidden.toggle()
        // Every APRFree widget follows, not only the one that was tapped.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let scope: DebtScope
    let numbers: ScopeSnapshot
    var hidden = false
}

struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, scope: .total, numbers: WidgetSnapshot.sample.total)
    }

    func snapshot(for configuration: BalanceWidgetIntent, in context: Context) async -> SnapshotEntry {
        entry(for: configuration, sample: context.isPreview)
    }

    func timeline(for configuration: BalanceWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        // The app reloads the timeline whenever data changes; this refresh only keeps dates current.
        let tomorrow = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        return Timeline(entries: [entry(for: configuration, sample: false)], policy: .after(tomorrow))
    }

    private func entry(for configuration: BalanceWidgetIntent, sample: Bool) -> SnapshotEntry {
        let scope = configuration.show.scope
        let snapshot = sample ? WidgetSnapshot.sample : WidgetSnapshot.load() ?? .empty
        return SnapshotEntry(date: .now, scope: scope, numbers: snapshot.scope(scope), hidden: !sample && WidgetSnapshot.balancesHidden)
    }
}

private enum WidgetStyle {
    /// The app's one accent. Green means paid, or the balance going down.
    static let green = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        : UIColor(red: 0x1E / 255, green: 0x85 / 255, blue: 0x37 / 255, alpha: 1) })

    static func money(_ value: Double) -> String {
        ((value * 100).rounded() / 100).formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    /// What stands in for an amount while balances are hidden.
    static let dots = "$ • • • •"

    /// Dates arrive as calendar days, so they read the same wherever the iPhone is. A day is a
    /// Gregorian year, month and day, so it is turned into a date with that calendar even when the
    /// iPhone is set to another one.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func monthDay(_ day: Day?) -> String {
        day.map { $0.date(in: calendar).formatted(.dateTime.month(.abbreviated).day()) } ?? "None"
    }

    static func monthYear(_ day: Day?) -> String {
        day.map { $0.date(in: calendar).formatted(.dateTime.month(.abbreviated).year()) } ?? "Not set"
    }
}

struct APRFreeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let scope: DebtScope
    let numbers: ScopeSnapshot
    var hidden = false

    private var percent: Int { Int((numbers.fractionPaid * 100).rounded()) }
    private var fraction: Double { min(max(numbers.fractionPaid, 0), 1) }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        default: small
        }
    }

    /// An open eye while balances show; tapping it hides them and it becomes an eye with a slash.
    private var eye: some View {
        Button(intent: ToggleBalancesIntent()) {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidden ? "Show balances" : "Hide balances")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("APRFree").font(.caption.weight(.bold))
            Spacer(minLength: 0)
            eye
        }
    }

    private var balance: some View {
        Text(hidden ? WidgetStyle.dots : WidgetStyle.money(numbers.balance))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .privacySensitive()
            .accessibilityLabel(hidden ? "Balance hidden" : WidgetStyle.money(numbers.balance))
    }

    private var change: some View {
        let down = numbers.changeThisMonth <= 0
        return VStack(alignment: .leading, spacing: 0) {
            if hidden {
                Text("Hidden").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Label(WidgetStyle.money(abs(numbers.changeThisMonth)), systemImage: down ? "arrow.down" : "arrow.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(down ? WidgetStyle.green : Color.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Text("this month")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .privacySensitive()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            Text(scope.balanceLabel).font(.caption).foregroundStyle(.secondary)
            balance.font(.title2.weight(.bold))
            change.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func pair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    Text(scope.balanceLabel).font(.caption).foregroundStyle(.secondary)
                    balance.font(.title.weight(.bold))
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 8) {
                    pair("Next due", WidgetStyle.monthDay(numbers.nextDue))
                    pair(scope.freeLabel, WidgetStyle.monthYear(numbers.free))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                    .tint(WidgetStyle.green)
                Text("\(percent)% paid").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(scope == .total ? "APRFree" : scope.title).font(.caption.weight(.bold))
            Text("Next due \(WidgetStyle.monthDay(numbers.nextDue))").font(.footnote.weight(.semibold))
            Text("\(scope.freeLabel) \(WidgetStyle.monthYear(numbers.free))").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: fraction) {
            Text("Paid")
        } currentValueLabel: {
            Text("\(percent)%")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct APRFreeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "APRFreeWidget", intent: BalanceWidgetIntent.self, provider: SnapshotProvider()) { entry in
            APRFreeWidgetView(scope: entry.scope, numbers: entry.numbers, hidden: entry.hidden)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("APRFree")
        .description("A balance, its next due date and the month it is paid off. Edit the widget to pick total, credit cards or loans. Tap the eye to hide the amounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct APRFreeWidgetBundle: WidgetBundle {
    var body: some Widget {
        APRFreeWidget()
    }
}
