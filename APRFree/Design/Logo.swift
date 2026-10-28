import SwiftUI

/// APRFree's own mark, wordmark and lockup, drawn in vectors so they stay sharp at any size.
///
/// These follow the design canvas board "16 · App icon and logo · Direction A", and so do the image
/// files made by `Brand/make-brand.swift`. A change to the design belongs in both places.
enum Logo {
    /// The wordmark is set "APRfree", with a lower-case f. Everywhere else the name is APRFree.
    static let lettering = "APRfree"

    static let ground = Color(hex: 0x1C1C1E)
    static let backCard = Color(hex: 0x2C2C2E)
    static let middleCard = Color(hex: 0x0B2A5B)
    static let middleCorner = Color(hex: 0x1D4A8F)
    static let frontCard = Color(hex: 0xD9D9DE)
    static let chip = Color(hex: 0xC9A85C)
    /// The dot and the stroke. This green belongs to the logo; `Theme.green` is the one for paid and positive states.
    static let green = Color(light: 0x34C759, dark: 0x30D158)
    static let ink = Color(light: 0x1C1C1E, dark: 0xFFFFFF)
}

/// The app icon as a picture inside the app: three stacked cards on a near-black square.
/// Detail drops away as it shrinks, the same way the icon's own small sizes do.
struct LogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        Canvas { context, canvas in
            // Drawn on the icon's 180-point grid.
            context.scaleBy(x: canvas.width / 180, y: canvas.height / 180)
            func card(_ y: CGFloat, _ color: Color) {
                context.fill(Path(roundedRect: CGRect(x: 28, y: y, width: 124, height: 78), cornerRadius: 10), with: .color(color))
            }
            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 180, height: 180), cornerRadius: 40, style: .continuous), with: .color(Logo.ground))
            card(27, Logo.backCard)
            card(51, Logo.middleCard)
            if size >= 56 {
                var corner = Path()
                corner.move(to: CGPoint(x: 116, y: 51))
                corner.addLine(to: CGPoint(x: 142, y: 51))
                corner.addCurve(to: CGPoint(x: 152, y: 61), control1: CGPoint(x: 147.523, y: 51), control2: CGPoint(x: 152, y: 55.477))
                corner.addLine(to: CGPoint(x: 152, y: 69))
                corner.closeSubpath()
                context.fill(corner, with: .color(Logo.middleCorner))
            }
            card(75, Logo.frontCard)
            if size >= 100 {
                let letters = context.resolve(Text(Logo.lettering).font(.system(size: 12, weight: .bold)).foregroundStyle(Logo.ground))
                let box = letters.measure(in: CGSize(width: 180, height: 40))
                context.draw(letters, at: CGPoint(x: 40, y: 93 - letters.firstBaseline(in: CGSize(width: 180, height: 40))), anchor: .topLeading)
                context.fill(Path(ellipseIn: CGRect(x: max(90, 40 + box.width + 1.5), y: 86, width: 6, height: 6)), with: .color(Color(hex: 0x34C759)))
                context.fill(Path(roundedRect: CGRect(x: 40, y: 103, width: 18, height: 13), cornerRadius: 3), with: .color(Logo.chip))
            } else if size >= 34 {
                if size >= 50 { context.fill(Path(ellipseIn: CGRect(x: 88, y: 84, width: 10, height: 10)), with: .color(Color(hex: 0x34C759))) }
                context.fill(Path(roundedRect: CGRect(x: 40, y: 103, width: size >= 50 ? 22 : 24, height: size >= 50 ? 16 : 18), cornerRadius: 3),
                             with: .color(Logo.chip))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("APRFree")
        .accessibilityAddTraits(.isImage)
    }
}

/// The stroke under the wordmark: thin at the left, rising and thickening to the right.
struct LogoStroke: Shape {
    func path(in rect: CGRect) -> Path {
        // M0 10 Q120 16 240 0 L240 6 Q120 22 0 13 Z, in a 240 by 16 box.
        let sx = rect.width / 240, sy = rect.height / 16
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: point(0, 10))
        path.addQuadCurve(to: point(240, 0), control: point(120, 16))
        path.addLine(to: point(240, 6))
        path.addQuadCurve(to: point(0, 13), control: point(120, 22))
        path.closeSubpath()
        return path
    }
}

/// "APRfree", the green dot, and the stroke under it. `size` is the size of the lettering.
/// It is a picture of the name, not text to read at a chosen size, so it does not grow with Dynamic Type.
struct LogoWordmark: View {
    var size: CGFloat = 40

    var body: some View {
        let k = size / 40
        VStack(alignment: .leading, spacing: 2 * k) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * k) {
                Text(Logo.lettering)
                    .font(.system(size: size, weight: .bold))
                    .tracking(-1 * k)
                    .foregroundStyle(Logo.ink)
                    .fixedSize()
                Circle()
                    .fill(Logo.green)
                    .frame(width: 13 * k, height: 13 * k)
                    // The dot sits on the baseline of the lettering.
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            }
            .frame(height: 42 * k)
            LogoStroke()
                .fill(Logo.green)
                .frame(width: 170 * k, height: 12 * k)
        }
        .accessibilityElement()
        .accessibilityLabel("APRFree")
        .accessibilityAddTraits(.isImage)
    }
}

/// The mark beside the wordmark. `height` is the height of the mark.
struct LogoLockup: View {
    var height: CGFloat = 64

    var body: some View {
        let k = height / 64
        HStack(spacing: 18 * k) {
            LogoMark(size: height)
            LogoWordmark(size: 40 * k)
        }
        .accessibilityElement()
        .accessibilityLabel("APRFree")
        .accessibilityAddTraits(.isImage)
    }
}
