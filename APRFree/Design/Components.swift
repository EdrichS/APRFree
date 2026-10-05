import SwiftUI

// MARK: - Buttons

/// Full-width capsule. Green is for the Make a Payment flow only.
struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case primary, green, gray }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        Styled(kind: kind, configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isEnabled) private var isEnabled
        let kind: Kind
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .contentShape(Capsule())
        }

        private var background: Color {
            switch kind {
            case .primary: Theme.primaryFill
            case .green: Theme.green
            case .gray: Theme.fillOnBG
            }
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onPrimary
            case .green: Theme.onGreen
            case .gray: .primary
            }
        }
    }
}

/// The smaller capsule inside tiles: "Pay This Card", "Add a Charge".
struct TileButtonStyle: ButtonStyle {
    var green = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(green ? Theme.onGreen : Color.primary)
            .background(green ? Theme.green : Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// GreenPill: the Make a Payment button in the top bar.
struct GreenPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 15)
                .frame(height: 44)
                .foregroundStyle(Theme.onGreen)
                .background(Theme.green, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(Capsule())
        }
    }
}

/// Round Liquid Glass toolbar button.
struct GlassCircle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// The switch itself: neutral, so green keeps its one meaning.
struct NeutralSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.primaryFill : Theme.track)
            .frame(width: 51, height: 31)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Theme.onPrimary : Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct NeutralToggleStyle: ToggleStyle {
    /// Compact keeps the label right next to the switch instead of pushing them apart.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            configuration.label
            if !compact { Spacer(minLength: 0) }
            NeutralSwitch(isOn: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Tiles

/// StatTile container: a rounded card that fills its grid cell.
struct Tile<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Two tiles side by side, always the same height.
struct TileRow<Content: View>: View {
    var minHeight: CGFloat = 110
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) { content }
            .frame(minHeight: minHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TileLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

struct TileValue: View {
    let text: String
    var size: CGFloat = 24
    var color: Color = .primary
    init(_ text: String, size: CGFloat = 24, color: Color = .primary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .tracking(-0.3)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 4)
    }
}

struct TileNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var note: String?
    var valueColor: Color = .primary

    var body: some View {
        Tile {
            TileLabel(label)
            TileValue(value, color: valueColor)
            if let note { TileNote(note) }
        }
    }
}

// MARK: - Small pieces

struct StatusBadge: View {
    let status: DueStatus

    var body: some View {
        Text(status.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .overdue: Theme.red
        case .soon: Theme.orange
        case .later: Theme.secondary
        }
    }

    private var background: Color {
        switch status {
        case .overdue: Theme.redSoft
        case .soon: Theme.orangeSoft
        case .later: Theme.fill
        }
    }
}

struct InstallmentDots: View {
    let count: Int
    let paid: Int
    var filled: Color = Theme.green
    var empty: Color = Theme.tertiary
    var size: CGFloat = 7
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                if i < paid {
                    Circle().fill(filled).frame(width: size, height: size)
                } else {
                    Circle().strokeBorder(empty, lineWidth: 1.5).frame(width: size, height: size)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(paid) of \(count) paid")
    }
}

struct ProgressRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 6
    var color: Color = .primary
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var color: Color = Theme.green
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == index ? Theme.primaryFill : Theme.tertiary).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement()
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

/// Step dots for onboarding: plain, no capsule.
struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == index ? Color.primary : Theme.tertiary).frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SmallCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.secondary)
    }
}

/// A symbol in a soft circle, used at the start of rows.
struct IconCircle: View {
    let symbol: String
    var size: CGFloat = 40
    var background: Color = Theme.fill
    var color: Color = .primary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

/// Grouped rows on a card, with inset separators, for use outside a Form.
struct CardGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct RowDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, inset)
    }
}

// MARK: - Form fields

extension Binding where Value == Double {
    /// Shows zero as an empty field, so typing starts from the placeholder instead of "0.00".
    /// Whatever is typed or pasted is kept between zero and `ceiling`.
    func emptyWhenZero(upTo ceiling: Double) -> Binding<Double?> {
        Binding<Double?>(get: { wrappedValue == 0 ? nil : wrappedValue }, set: { wrappedValue = Swift.min(Swift.max(0, $0 ?? 0), ceiling) })
    }

    var emptyWhenZero: Binding<Double?> { emptyWhenZero(upTo: Limits.money) }
}

extension Binding where Value == Double? {
    /// Keeps an optional amount between zero and `ceiling`.
    func clamped(upTo ceiling: Double) -> Binding<Double?> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0.map { Swift.min(Swift.max(0, $0), ceiling) } })
    }
}

struct MoneyField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Theme.secondary)
                TextField("0.00", value: $value.emptyWhenZero, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }
}

struct OptionalMoneyField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Theme.secondary)
                TextField("Optional", value: $value.clamped(upTo: Limits.money), format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }
}

struct PercentField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                TextField("0.00", value: $value.emptyWhenZero(upTo: Limits.percent), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize()
                Text("%").foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct DueDayPicker: View {
    let title: String
    @Binding var day: Int

    var body: some View {
        Picker(title, selection: $day) {
            ForEach(1...31, id: \.self) { Text(Fmt.ordinal($0)).tag($0) }
        }
    }
}

/// The soft fade behind the pinned top bar on the two pages.
struct TopBarFade: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Theme.bg, location: 0), .init(color: Theme.bg, location: 0.7),
                               .init(color: Theme.bg.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .top)
    }
}

/// "+$50 a month": tap the number to type any amount, or drag the slider for a quick one.
/// The slider starts at `baseMax` and stretches to fit whatever is typed.
struct ExtraAmountControl: View {
    @Binding var amount: Double
    let baseMax: Double
    let step: Double
    var valueSize: CGFloat = 24

    @State private var upper = 0.0
    @State private var text = ""
    /// The amount when typing began, restored if the field is left empty.
    @State private var before = 0.0
    @FocusState private var typing: Bool

    /// The slider keeps the same number of stops however far it stretches.
    private var sliderMax: Double { max(upper, baseMax) }

    private func shown(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }

    /// The number pad types the decimal mark of the iPhone's region, which is a comma in many of them.
    private func parsed(_ text: String) -> Double? {
        let mark = Locale.current.decimalSeparator ?? "."
        let plain = mark == "." ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: mark, with: ".")
        return Double(plain).map { Limits.money($0).cents }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 1) {
                    Text("+$")
                    // Tapping clears the field so the first key starts a new amount; the old one shows as the placeholder.
                    TextField(shown(before), text: $text)
                        .keyboardType(.decimalPad)
                        .focused($typing)
                        .fixedSize()
                        .accessibilityLabel("Extra each month")
                        .accessibilityValue(amount.usd)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { typing = true }
                Text("a month")
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.system(size: valueSize, weight: .bold))
            .monospacedDigit()
            Slider(value: Binding(get: { min(max(amount, 0), sliderMax) }, set: { amount = $0 }), in: 0...sliderMax, step: sliderMax / (baseMax / step)) {
                Text("Extra each month")
            } minimumValueLabel: {
                Text("+$0").font(.caption).foregroundStyle(Theme.secondary)
            } maximumValueLabel: {
                Text("+$\(shown(sliderMax))").font(.caption).foregroundStyle(Theme.secondary)
            }
            .tint(Theme.primaryFill)
        }
        .onAppear {
            upper = max(baseMax, Fmt.niceCeiling(amount))
            before = amount
            text = shown(amount)
        }
        .onChange(of: typing) { _, isTyping in
            if isTyping {
                before = amount
                text = ""
            } else {
                text = shown(amount)
            }
        }
        .onChange(of: text) { _, value in
            guard typing else { return }
            amount = parsed(value) ?? before
        }
        .onChange(of: amount) { _, value in
            // Grow to fit a typed amount, but never shrink mid-drag.
            if value > sliderMax { upper = Fmt.niceCeiling(value) }
            if !typing { text = shown(value) }
        }
    }
}
