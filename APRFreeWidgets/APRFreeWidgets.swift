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

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let scope: DebtScope
    let numbers: ScopeSnapshot
    /// The time zone the app wrote the dates in.
    var zone = TimeZone.current
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
        return SnapshotEntry(date: .now, scope: scope, numbers: snapshot.scope(scope), zone: snapshot.timeZone)
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

    private static func dates(in zone: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
        style.timeZone = zone
        return style
    }

    static func monthDay(_ date: Date?, in zone: TimeZone) -> String {
        date.map { $0.formatted(dates(in: zone).month(.abbreviated).day()) } ?? "None"
    }

    static func monthYear(_ date: Date?, in zone: TimeZone) -> String {
        date.map { $0.formatted(dates(in: zone).month(.abbreviated).year()) } ?? "Not set"
    }
}

struct APRFreeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let scope: DebtScope
    let numbers: ScopeSnapshot
    var zone = TimeZone.current

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

    private var change: some View {
        let down = numbers.changeThisMonth <= 0
        return VStack(alignment: .leading, spacing: 0) {
            Label(WidgetStyle.money(abs(numbers.changeThisMonth)), systemImage: down ? "arrow.down" : "arrow.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(down ? WidgetStyle.green : Color.secondary)
                .labelStyle(.titleAndIcon)
            Text("this month")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APRFree").font(.caption.weight(.bold))
            Spacer(minLength: 0)
            Text(scope.balanceLabel).font(.caption).foregroundStyle(.secondary)
            Text(WidgetStyle.money(numbers.balance))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
            change.padding(.top, 6).privacySensitive()
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
                    Text("APRFree").font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                    Text(scope.balanceLabel).font(.caption).foregroundStyle(.secondary)
                    Text(WidgetStyle.money(numbers.balance))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 8) {
                    pair("Next due", WidgetStyle.monthDay(numbers.nextDue, in: zone))
                    pair(scope.freeLabel, WidgetStyle.monthYear(numbers.free, in: zone))
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
            Text("Next due \(WidgetStyle.monthDay(numbers.nextDue, in: zone))").font(.footnote.weight(.semibold))
            Text("\(scope.freeLabel) \(WidgetStyle.monthYear(numbers.free, in: zone))").font(.caption)
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
            APRFreeWidgetView(scope: entry.scope, numbers: entry.numbers, zone: entry.zone)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("APRFree")
        .description("A balance, its next due date and the month it is paid off. Edit the widget to pick total, credit cards or loans.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct APRFreeWidgetBundle: WidgetBundle {
    var body: some Widget {
        APRFreeWidget()
    }
}
