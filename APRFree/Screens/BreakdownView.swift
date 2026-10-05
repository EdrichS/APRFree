import Charts
import SwiftUI

/// Where the total balance sits: one slice per debt, with what each one owes and what it costs a day.
/// Opened by tapping the Total Balance card on the home screen.
struct BreakdownContent: View {
    @Environment(AppStore.self) private var store

    /// The slice picked by touching the chart or a row. Nil shows the total.
    @State private var selectedID: UUID?

    private struct Slice: Identifiable {
        let debt: Debt
        let color: Color
        var id: UUID { debt.id }
    }

    /// Loans have no brand colour, so they take neutral shades that differ in lightness.
    private static let loanShades = [Color(light: 0x1C1C1E, dark: 0xF2F2F7), Color(light: 0x636366, dark: 0xAEAEB2),
                                     Color(light: 0x8E8E93, dark: 0x7C7C80), Color(light: 0xAEAEB2, dark: 0x545458)]

    /// Cards, then pay-later plans, then loans; within each, the order they were added.
    private var slices: [Slice] {
        var loans = 0
        return [DebtKind.card, .payLater, .loan].flatMap { kind in
            store.active.filter { $0.kind == kind }.map { debt in
                if kind == .loan {
                    loans += 1
                    return Slice(debt: debt, color: Self.loanShades[(loans - 1) % Self.loanShades.count])
                }
                return Slice(debt: debt, color: debt.brandStyle.bottom)
            }
        }
    }

    /// The slice under a touch. Slices run clockwise from twelve o'clock; the hole and the corners are no slice.
    private func slice(at point: CGPoint, in frame: CGRect, _ slices: [Slice]) -> Slice? {
        let dx = point.x - frame.midX, dy = point.y - frame.midY
        let radius = min(frame.width, frame.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= radius, distance >= radius * Self.hole else { return nil }
        var turn = atan2(dx, -dy) / (2 * .pi)
        if turn < 0 { turn += 1 }
        let target = turn * slices.reduce(0) { $0 + $1.debt.balance }
        var running = 0.0
        for slice in slices {
            running += slice.debt.balance
            if target <= running { return slice }
        }
        return slices.last
    }

    /// The ring's inner radius as a share of its outer radius.
    private static let hole = 0.64

    private func percent(_ fraction: Double) -> String {
        (fraction * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    var body: some View {
        let slices = slices
        let selected = slices.first { $0.id == selectedID }
        ScrollView {
            VStack(spacing: 12) {
                if slices.isEmpty {
                    Tile { TileNote("Nothing owed right now. Add a debt and its share will show here.") }
                } else {
                    pie(slices, selected)
                    TileRow(minHeight: 96) {
                        StatTile(label: "Interest a day", value: store.dailyCost.usd, note: "across every balance")
                        StatTile(label: "Interest a month", value: store.monthlyCost.usd, note: "\((store.dailyCost * 365).usd) a year")
                    }
                    ForEach([DebtKind.card, .payLater, .loan], id: \.self) { kind in
                        group(kind, slices.filter { $0.debt.kind == kind })
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
    }

    private func pie(_ slices: [Slice], _ selected: Slice?) -> some View {
        Tile {
            Chart(slices) { slice in
                SectorMark(angle: .value("Balance", slice.debt.balance), innerRadius: .ratio(Self.hole), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
                    .opacity(selected == nil || selected?.id == slice.id ? 1 : 0.3)
            }
            .chartLegend(.hidden)
            .frame(height: 260)
            // A tap on a slice picks it; a tap in the middle goes back to the total.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let anchor = proxy.plotFrame else { return }
                            selectedID = slice(at: location, in: geo[anchor], slices)?.id
                        }
                }
            }
            .chartBackground { _ in
                // The middle of the ring: the total, or the slice that is picked.
                VStack(spacing: 2) {
                    Text(selected?.debt.title ?? "Total balance")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Text((selected?.debt.balance ?? store.total).usd)
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let debt = selected?.debt {
                        Text("\(percent(store.share(of: debt))) of the total")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                        Text("\(debt.dailyCost(on: store.today).usd) a day")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("\(store.dailyCost.usd) a day in interest")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: 150)
            }
            .accessibilityLabel("Balance breakdown. Total \(store.total.usd).")
            if selected != nil {
                Button("Show Total") { selectedID = nil }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            } else {
                Text("Touch a slice or a row to see its share.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
    }

    @ViewBuilder private func group(_ kind: DebtKind, _ slices: [Slice]) -> some View {
        if !slices.isEmpty {
            let balance = slices.reduce(0) { $0 + $1.debt.balance }
            let daily = slices.reduce(0) { $0 + $1.debt.dailyCost(on: store.today) }
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: title(kind), detail: balance.usd)
                Text("\(percent(store.total > 0 ? balance / store.total : 0)) of the total · \(daily.usd) a day in interest")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 16)
            CardGroup {
                ForEach(slices) { slice in
                    if slice.id != slices.first?.id { RowDivider(inset: 42) }
                    Button { selectedID = selectedID == slice.id ? nil : slice.id } label: {
                        row(slice)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedID == slice.id ? .isSelected : [])
                }
            }
        }
    }

    private func row(_ slice: Slice) -> some View {
        let debt = slice.debt
        return HStack(spacing: 12) {
            Circle().fill(slice.color).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(debt.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text("\(percent(store.share(of: debt))) · \(debt.apr(on: store.today) == 0 ? "no interest" : "\(debt.dailyCost(on: store.today).usd) a day")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(debt.balance.usd).font(.callout).monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(selectedID == slice.id ? Theme.fill : Color.clear)
        .contentShape(Rectangle())
    }

    private func title(_ kind: DebtKind) -> String {
        switch kind {
        case .card: "Credit cards"
        case .payLater: "Pay later"
        case .loan: "Loans"
        }
    }
}
