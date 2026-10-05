import SwiftUI

/// Shown over everything when a debt reaches zero.
struct CelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let debt: Debt
    let done: () -> Void

    /// What this balance cost in interest each year, at the rate it was charged.
    private var savedPerYear: Double { debt.startAmount * debt.apr / 100 }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Confetti(colors: [Theme.green, debt.kind == .loan ? Theme.tertiary : debt.brandStyle.top, Theme.tertiary, .primary],
                     animated: !reduceMotion)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                hero
                Text("\(debt.title) is paid off!")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 36)
                if savedPerYear > 0.005 {
                    Text(savedPerYear.usd)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.greenText)
                        .padding(.top, 14)
                    Text("a year in interest saved")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                if debt.kind == .card {
                    HStack(spacing: 12) {
                        IconCircle(symbol: "lightbulb")
                        Text("Keep the card open, but don’t charge it.").font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .padding(.top, 24)
                }
                Spacer(minLength: 24)
                Button("Done", action: done)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var hero: some View {
        if debt.kind == .loan {
            VStack(spacing: 14) {
                IconCircle(symbol: (debt.loanType ?? .other).symbol, size: 96, background: Theme.card)
                PaidOffStamp(ink: .primary)
            }
        } else {
            CardFace(debt: debt, stamped: true)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .padding(.horizontal, 12)
        }
    }
}

/// Falling paper, drawn on a canvas. Each piece's path is fixed by its index, so it needs no state.
private struct Confetti: View {
    let colors: [Color]
    let animated: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            Canvas { context, size in
                let t = animated ? timeline.date.timeIntervalSince(start) : 1.6
                for i in 0..<64 {
                    let seed = Double(i)
                    let column = noise(seed * 12.9898)
                    let speed = 70 + 110 * noise(seed * 78.233)
                    let delay = 1.2 * noise(seed * 37.719)
                    let travel = max(0, t - delay) * speed
                    let y = -20 + travel.truncatingRemainder(dividingBy: size.height + 40)
                    let x = column * size.width + sin(t * 1.6 + seed) * 14
                    let w = 5 + 4 * noise(seed * 3.17), h = 9 + 6 * noise(seed * 9.71)
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(t * (1 + noise(seed * 5.3) * 2) + seed))
                    piece.opacity = 0.9
                    piece.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 1.5),
                               with: .color(colors[i % colors.count]))
                }
            }
        }
    }

    /// A repeatable value in 0..<1.
    private func noise(_ x: Double) -> Double {
        let v = sin(x) * 43758.5453
        return v - v.rounded(.down)
    }
}
