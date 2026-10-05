import SwiftUI

/// A bank or provider's name, set in the typeface chosen for it (see `Wordmark`).
struct WordmarkText: View {
    let name: String
    let brand: Brand
    var size: CGFloat = 19

    init(debt: Debt, size: CGFloat = 19) {
        let brand = debt.brandStyle
        self.brand = brand
        name = brand.id == Brand.other.id ? debt.provider : brand.name
        self.size = size
    }

    init(brand: Brand, size: CGFloat = 19) {
        self.brand = brand
        name = brand.name
        self.size = size
    }

    var body: some View {
        Text(brand.mark.text(name))
            .font(brand.mark.font(size: size))
            .tracking(brand.mark.spacing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(name)
    }
}

/// CardStrip: the header row of a card, and all that shows of it inside the stack.
struct CardStrip: View {
    let debt: Debt
    var showDots = false

    var body: some View {
        HStack(spacing: 8) {
            WordmarkText(debt: debt)
            if showDots, debt.kind == .payLater {
                InstallmentDots(count: debt.installments ?? 0, paid: debt.paidInstallments ?? 0,
                                filled: debt.brandStyle.ink, empty: debt.brandStyle.ink)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(debt.isPaidOff ? "PAID OFF" : (debt.kind == .payLater ? "REMAINING" : "BALANCE"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Text(debt.balance.usd)
                    .font(.headline)
                    .monospacedDigit()
            }
            .layoutPriority(1)
        }
        .frame(height: 54)
    }
}

/// CardFace: bank name and card name on the bank's colour, with a generic chip and contactless mark.
struct CardFace: View {
    static let height: CGFloat = 228

    let debt: Debt
    /// Inside the stack only the strip shows, so pay-later cards carry their dots there.
    var inStack = false
    var stamped = false

    var body: some View {
        let brand = debt.brandStyle
        VStack(alignment: .leading, spacing: 0) {
            CardStrip(debt: debt, showDots: inStack)
            if debt.kind == .payLater { payLaterBody } else { cardBody }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.height, alignment: .top)
        .foregroundStyle(brand.ink)
        .background {
            LinearGradient(colors: [brand.top, brand.bottom], startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
            if stamped { PaidOffStamp(ink: brand.ink).padding(.trailing, 18).padding(.bottom, 46) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                .mask(alignment: .top) { Rectangle().frame(height: 20) }
        }
        .accessibilityElement(children: .combine)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CardChip(ink: debt.brandStyle.ink)
                Image(systemName: "wave.3.right")
                    .font(.system(size: 20, weight: .medium))
            }
            .padding(.top, 30)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text(debt.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let end = debt.promoEnd, debt.hasPromo(on: AppClock.today) {
                    Text("\(Fmt.percent(debt.promoAPR ?? 0)) until \(Fmt.full(end))")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .foregroundStyle(debt.brandStyle.bottom)
                        .background(.white.opacity(0.94), in: Capsule())
                        .fixedSize()
                }
            }
            .padding(.bottom, 14)
        }
    }

    private var payLaterBody: some View {
        let count = debt.installments ?? 0, paid = debt.paidInstallments ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(debt.name)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .padding(.top, 26)
            Text("\(paid) of \(count) paid")
                .font(.footnote.weight(.medium))
                .padding(.top, 2)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                InstallmentDots(count: count, paid: paid, filled: debt.brandStyle.ink, empty: debt.brandStyle.ink,
                                size: 14, spacing: 8)
                Spacer(minLength: 8)
                Text("\(count) payments of \(debt.minimum.usd)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.bottom, 16)
        }
    }
}

struct CardChip: View {
    let ink: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.25))
            .frame(width: 42, height: 30)
            .overlay {
                ZStack {
                    Rectangle().fill(ink.opacity(0.55)).frame(height: 1)
                    HStack(spacing: 14) {
                        Rectangle().fill(ink.opacity(0.55)).frame(width: 1)
                        Rectangle().fill(ink.opacity(0.55)).frame(width: 1)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ink.opacity(0.55), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct PaidOffStamp: View {
    let ink: Color
    var size: CGFloat = 18

    var body: some View {
        Text("PAID OFF")
            .font(.system(size: size, weight: .heavy))
            .tracking(size * 0.08)
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.2)
            .foregroundStyle(ink)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous).strokeBorder(ink, lineWidth: size * 0.14)
            }
            .rotationEffect(.degrees(-10))
    }
}

/// A small card for the Paid Off shelf and pickers.
struct MiniCard: View {
    let debt: Debt
    var stamped = false

    var body: some View {
        let brand = debt.brandStyle
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if debt.kind == .loan {
                    Image(systemName: (debt.loanType ?? .other).symbol).font(.footnote.weight(.semibold))
                    Text(debt.title).font(.footnote.weight(.semibold)).lineLimit(1)
                } else {
                    WordmarkText(debt: debt, size: 15)
                }
            }
            Spacer(minLength: 0)
            Text(debt.detail).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 190, height: 120, alignment: .topLeading)
        .foregroundStyle(brand.ink)
        .background(LinearGradient(colors: [brand.top, brand.bottom], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottomTrailing) {
            if stamped { PaidOffStamp(ink: brand.ink, size: 13).padding(.trailing, 12).padding(.bottom, 32) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The small colour chip that stands for a debt in lists.
struct Swatch: View {
    let debt: Debt
    var width: CGFloat = 30
    var height: CGFloat = 20

    var body: some View {
        if debt.kind == .loan {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.fill)
                .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.tertiary, lineWidth: 1) }
                .frame(width: width, height: height)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [debt.brandStyle.top, debt.brandStyle.bottom], startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)
        }
    }
}

/// How far through its schedule a loan is, when its start and end are known.
struct LoanRoute {
    var start: Date
    var end: Date
    var paymentNumber: Int
    var paymentCount: Int

    var fraction: Double { paymentCount > 0 ? Double(max(0, paymentNumber - 1)) / Double(paymentCount) : 0 }

    init?(_ debt: Debt) {
        guard debt.kind == .loan, let start = debt.startDate, let end = debt.endDate, end > start else { return nil }
        self.start = start
        self.end = end
        paymentCount = Cal.months(from: start, to: end) + 1
        let next = debt.nextUnpaidDue() ?? end
        paymentNumber = min(paymentCount, max(1, Cal.months(from: start, to: next) + 1))
    }
}

/// LoanPass: a boarding-pass tile with the lender, the balance, and the route from start to payoff.
struct LoanPass: View {
    let debt: Debt

    var body: some View {
        let route = LoanRoute(debt)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconCircle(symbol: (debt.loanType ?? .other).symbol, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(debt.provider.isEmpty ? "Lender not set" : debt.provider)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Text(debt.title).font(.headline).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    passCaption("BALANCE")
                    Text(debt.balance.usd).font(.headline).monospacedDigit()
                }
                .layoutPriority(1)
            }
            .frame(height: 40)

            Line()
                .stroke(Theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5)
                .padding(.vertical, 13)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    passCaption("START")
                    Text(route.map { Fmt.monthYear($0.start) } ?? "Not set").font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    passCaption("PAYOFF")
                    Text((route?.end ?? debt.endDate).map(Fmt.monthYear) ?? "Not set").font(.subheadline.weight(.semibold))
                }
            }
            ProgressBar(fraction: route?.fraction ?? 0).padding(.top, 8)
            HStack {
                Text(route.map { "Payment \($0.paymentNumber) of \($0.paymentCount)" } ?? Fmt.percent(debt.apr) + " APR")
                Spacer()
                Text("\(debt.minimum.usd) a month")
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Theme.secondary)
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card)
        .overlay(alignment: .topLeading) { notch.offset(x: -9, y: 59) }
        .overlay(alignment: .topTrailing) { notch.offset(x: 9, y: 59) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var notch: some View {
        Circle().fill(Theme.bg).frame(width: 18, height: 18)
    }

    private func passCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.secondary)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// ToolPass: a tile that opens one of the tools and previews its headline.
struct ToolPass: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
                .frame(height: 24)
                Text(title).font(.callout.weight(.semibold)).padding(.top, 10)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
