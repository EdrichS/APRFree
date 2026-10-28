#!/usr/bin/env swift
//
// Draws APRFree's app icon, logo and wordmark and writes every file the project and the App Store need.
//
//     swift Brand/make-brand.swift            (run from the project folder)
//
// The drawings follow the design canvas, board "16 · App icon and logo · Direction A", measure for
// measure. Each picture is described once, below, in the board's own 180-point icon grid, and both
// the PNG and the SVG files are made from that one description. Lettering is turned into outlines,
// so the SVG files need no font installed.
//
// Writes:
//   APRFree/Assets.xcassets/AppIcon.appiconset   the app icon: every size, in default, dark and tinted
//   Brand/icon, Brand/logo, Brand/svg            the same artwork for the App Store page, a website or print

import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - A picture, described once

enum Mark {
    case path(CGPath, fill: UInt32)
    case stroke(CGPath, color: UInt32, width: CGFloat)
}

struct Picture {
    var size: CGSize
    var marks: [Mark] = []

    mutating func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0, _ fill: UInt32) {
        marks.append(.path(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil), fill: fill))
    }

    mutating func outline(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat, _ color: UInt32, width: CGFloat) {
        let inset = width / 2
        marks.append(.stroke(CGPath(roundedRect: CGRect(x: x + inset, y: y + inset, width: w - width, height: h - width), cornerWidth: r - inset, cornerHeight: r - inset, transform: nil), color: color, width: width))
    }

    mutating func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: UInt32, width: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        marks.append(.stroke(path, color: color, width: width))
    }

    mutating func circle(_ cx: CGFloat, _ cy: CGFloat, r: CGFloat, _ fill: UInt32) {
        marks.append(.path(CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil), fill: fill))
    }

    /// Lettering as outlines, with its left edge at `x` and its baseline at `y`. Returns the width.
    @discardableResult
    mutating func text(_ string: String, x: CGFloat, baseline y: CGFloat, font: NSFont, tracking: CGFloat = 0, _ fill: UInt32) -> CGFloat {
        let (path, width) = outlines(string, font: font, tracking: tracking, at: CGPoint(x: x, y: y))
        marks.append(.path(path, fill: fill))
        return width
    }

    /// Another picture placed inside this one.
    mutating func place(_ other: Picture, at origin: CGPoint, scale: CGFloat = 1) {
        var t = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
        for mark in other.marks {
            switch mark {
            case .path(let path, let fill):
                if let moved = path.copy(using: &t) { marks.append(.path(moved, fill: fill)) }
            case .stroke(let path, let color, let width):
                if let moved = path.copy(using: &t) { marks.append(.stroke(moved, color: color, width: width * scale)) }
            }
        }
    }
}

/// The outlines of a line of lettering. Pictures are drawn with y running down, so each glyph is flipped.
func outlines(_ string: String, font: NSFont, tracking: CGFloat, at origin: CGPoint) -> (CGPath, CGFloat) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .kern: tracking]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let runFont = attributes[kCTFontAttributeName as String] as! CTFont
        for (glyph, position) in zip(glyphs, positions) {
            var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x + position.x, ty: origin.y - position.y)
            if let shape = CTFontCreatePathForGlyph(runFont, glyph, &t) { path.addPath(shape) }
        }
    }
    return (path, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - tracking)
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// MARK: - Writing files

/// A PNG `pixels` wide. `opaque` leaves out the alpha channel, which the App Store icon must not have.
func png(_ picture: Picture, pixels: Int, opaque: Bool = false, backdrop: UInt32? = nil, to url: URL) {
    let scale = CGFloat(pixels) / picture.size.width
    let height = Int((picture.size.height * scale).rounded())
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: pixels, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { fatalError("no context for \(url.lastPathComponent)") }
    if let backdrop {
        ctx.setFillColor(color(backdrop))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: height))
    }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    for mark in picture.marks {
        switch mark {
        case .path(let path, let fill):
            ctx.addPath(path)
            ctx.setFillColor(color(fill))
            ctx.fillPath()
        case .stroke(let path, let stroke, let width):
            ctx.addPath(path)
            ctx.setStrokeColor(color(stroke))
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
    }
    guard let image = ctx.makeImage(), let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not write \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(out, image, nil)
    CGImageDestinationFinalize(out)
}

func svg(_ picture: Picture, title: String, to url: URL) {
    func n(_ value: CGFloat) -> String {
        let text = String(format: "%.3f", value)
        return text.contains(".") ? text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression) : text
    }
    func d(_ path: CGPath) -> String {
        var out: [String] = []
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: out.append("M\(n(p[0].x)) \(n(p[0].y))")
            case .addLineToPoint: out.append("L\(n(p[0].x)) \(n(p[0].y))")
            case .addQuadCurveToPoint: out.append("Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))")
            case .addCurveToPoint: out.append("C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))")
            case .closeSubpath: out.append("Z")
            @unknown default: break
            }
        }
        return out.joined()
    }
    func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }
    var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(picture.size.width))\" height=\"\(n(picture.size.height))\" viewBox=\"0 0 \(n(picture.size.width)) \(n(picture.size.height))\" role=\"img\" aria-label=\"\(title)\">",
                 "<title>\(title)</title>"]
    for mark in picture.marks {
        switch mark {
        case .path(let path, let fill): lines.append("<path d=\"\(d(path))\" fill=\"\(hex(fill))\"/>")
        case .stroke(let path, let stroke, let width): lines.append("<path d=\"\(d(path))\" fill=\"none\" stroke=\"\(hex(stroke))\" stroke-width=\"\(n(width))\"/>")
        }
    }
    lines.append("</svg>")
    try! (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - The icon

enum Look: String, CaseIterable {
    /// The default icon: three cards on near-black.
    case primary
    /// The same on a light ground, with a white front card.
    case light
    /// On pure black, for the Home Screen's dark appearance.
    case dark
    /// Greys only. iOS lays the user's tint over this one.
    case tinted
}

/// How much of the drawing is kept. Detail drops away as the icon shrinks, as on the board.
enum Detail: Int {
    /// Everything: the stripes, the corner, the lettering, the dot, the chip and the number.
    case full
    /// 120 points: the lettering stays, the stripes and the number go.
    case large
    /// 60 points, the Home Screen: no lettering. A larger dot and chip.
    case home
    /// 40 points: the cards and the chip.
    case spot
    /// 29 points and under: the three cards alone.
    case tiny

    static func forPoints(_ points: CGFloat) -> Detail {
        switch points {
        case 300...: .full
        case 100...: .large
        case 50...: .home
        case 34...: .spot
        default: .tiny
        }
    }
}

struct Inks {
    var ground: UInt32, back: UInt32, stripe: UInt32, middle: UInt32, corner: UInt32
    var front: UInt32, frontEdge: UInt32? = nil
    var letters: UInt32 = 0x1C1C1E, dot: UInt32 = 0x34C759, chip: UInt32 = 0xC9A85C
    var number: UInt32 = 0x8E8E93, name: UInt32 = 0xAEAEB2

    static func of(_ look: Look) -> Inks {
        switch look {
        case .primary: Inks(ground: 0x1C1C1E, back: 0x2C2C2E, stripe: 0x48484A, middle: 0x0B2A5B, corner: 0x1D4A8F, front: 0xD9D9DE)
        case .dark: Inks(ground: 0x000000, back: 0x2C2C2E, stripe: 0x48484A, middle: 0x0B2A5B, corner: 0x1D4A8F, front: 0xD9D9DE)
        case .light: Inks(ground: 0xF2F2F7, back: 0x2C2C2E, stripe: 0x48484A, middle: 0x0B2A5B, corner: 0x1D4A8F, front: 0xFFFFFF, frontEdge: 0xD1D1D6,
                          number: 0xAEAEB2, name: 0xC7C7CC)
        case .tinted: Inks(ground: 0x000000, back: 0x3A3A3C, stripe: 0x3A3A3C, middle: 0x5A5A5E, corner: 0x5A5A5E, front: 0xE5E5EA,
                           dot: 0x1C1C1E, chip: 0x8E8E93)
        }
    }
}

let lettering = "APRfree"

/// The icon on the board's 180-point grid. `rounded` draws the corners in, for use outside iOS;
/// iOS and the App Store cut the corners themselves and need the full square.
func icon(_ look: Look, _ detail: Detail, rounded: Bool) -> Picture {
    let ink = Inks.of(look)
    // The tinted icon is the simple one at every size: no stripes, corner or number.
    let plain = look == .tinted
    var p = Picture(size: CGSize(width: 180, height: 180))
    p.rect(0, 0, 180, 180, r: rounded ? 40 : 0, ink.ground)

    p.rect(28, 27, 124, 78, r: 10, ink.back)
    if detail == .full && !plain {
        p.line(38, 35, 142, 35, ink.stripe, width: 0.8)
        p.line(38, 40, 142, 40, ink.stripe, width: 0.8)
    }

    p.rect(28, 51, 124, 78, r: 10, ink.middle)
    if detail.rawValue <= Detail.large.rawValue && !plain {
        // The lit corner: M116 51 h26 a10 10 0 0 1 10 10 v8 z
        let corner = CGMutablePath()
        corner.move(to: CGPoint(x: 116, y: 51))
        corner.addLine(to: CGPoint(x: 142, y: 51))
        corner.addCurve(to: CGPoint(x: 152, y: 61), control1: CGPoint(x: 147.523, y: 51), control2: CGPoint(x: 152, y: 55.477))
        corner.addLine(to: CGPoint(x: 152, y: 69))
        corner.closeSubpath()
        p.marks.append(.path(corner, fill: ink.corner))
    }

    p.rect(28, 75, 124, 78, r: 10, ink.front)
    if let edge = ink.frontEdge { p.outline(28, 75, 124, 78, r: 10, edge, width: 1) }

    switch detail {
    case .full, .large:
        let width = p.text(lettering, x: 40, baseline: 93, font: .systemFont(ofSize: 12, weight: .bold), ink.letters)
        // The dot sits at 93 on the board. It follows the lettering if that ever sets wider.
        p.circle(max(93, 40 + width + 4.5), 89, r: 3, ink.dot)
        p.rect(40, 103, 18, 13, r: 3, ink.chip)
    case .home:
        p.circle(93, 89, r: 5, ink.dot)
        p.rect(40, 103, 22, 16, r: 3, ink.chip)
    case .spot:
        p.rect(40, 103, 24, 18, r: 3, ink.chip)
    case .tiny:
        break
    }

    if detail == .full && !plain {
        for x in [40, 62, 84, 106] as [CGFloat] { p.rect(x, 131, 18, 3, r: 1.5, ink.number) }
        p.rect(40, 141, 40, 2.5, r: 1.25, ink.name)
    }
    return p
}

// MARK: - The wordmark, the lockup and the card

/// "APRfree", the green dot, and the stroke under it. `size` is the height of the lettering in points.
func wordmark(onDark: Bool, size: CGFloat = 40) -> Picture {
    let k = size / 40
    let green: UInt32 = onDark ? 0x30D158 : 0x34C759
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    // The line box on the board is 42 tall for 40-point lettering; the baseline sits where a browser puts it.
    let lineHeight = 42 * k
    let baseline = (lineHeight - (font.ascender - font.descender)) / 2 + font.ascender
    var p = Picture(size: .zero)
    let width = p.text(lettering, x: 0, baseline: baseline, font: font, tracking: -1 * k, onDark ? 0xFFFFFF : 0x1C1C1E)
    let dot = 13 * k
    p.circle(width + 4 * k + dot / 2, baseline - dot / 2, r: dot / 2, green)

    // The stroke: M0 10 Q120 16 240 0 L240 6 Q120 22 0 13 Z, drawn 170 by 12 under the lettering.
    let sx = 170 * k / 240, sy = 12 * k / 16, top = lineHeight + 2 * k
    let stroke = CGMutablePath()
    stroke.move(to: CGPoint(x: 0, y: top + 10 * sy))
    stroke.addQuadCurve(to: CGPoint(x: 240 * sx, y: top), control: CGPoint(x: 120 * sx, y: top + 16 * sy))
    stroke.addLine(to: CGPoint(x: 240 * sx, y: top + 6 * sy))
    stroke.addQuadCurve(to: CGPoint(x: 0, y: top + 13 * sy), control: CGPoint(x: 120 * sx, y: top + 22 * sy))
    stroke.closeSubpath()
    p.marks.append(.path(stroke, fill: green))

    p.size = CGSize(width: max(width + 4 * k + dot, 170 * k).rounded(.up), height: (top + 12 * k).rounded(.up))
    return p
}

/// The icon beside the wordmark. The icon here is the one drawn on the board's lockups: the lit
/// corner, the larger dot and chip, and no lettering of its own.
func lockup(onDark: Bool) -> Picture {
    var mark = icon(.primary, .home, rounded: true)
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: 116, y: 51))
    corner.addLine(to: CGPoint(x: 142, y: 51))
    corner.addCurve(to: CGPoint(x: 152, y: 61), control1: CGPoint(x: 147.523, y: 51), control2: CGPoint(x: 152, y: 55.477))
    corner.addLine(to: CGPoint(x: 152, y: 69))
    corner.closeSubpath()
    // Under the front card, where the board has it.
    mark.marks.insert(.path(corner, fill: Inks.of(.primary).corner), at: 3)

    let word = wordmark(onDark: onDark)
    var p = Picture(size: CGSize(width: 64 + 18 + word.size.width, height: 64))
    p.place(mark, at: .zero, scale: 64.0 / 180)
    p.place(word, at: CGPoint(x: 64 + 18, y: (64 - word.size.height) / 2))
    return p
}

/// The front card of the icon at full size, as on the board. The number and the name are made up.
func cardFront() -> Picture {
    var p = Picture(size: CGSize(width: 428, height: 270))
    p.rect(0, 0, 428, 270, r: 22, 0xD9D9DE)
    p.place(wordmark(onDark: false, size: 32), at: CGPoint(x: 30, y: 28))
    p.rect(30, 104, 52, 40, r: 7, 0xC9A85C)
    p.rect(30, 123, 52, 1, 0xA88A45)
    p.rect(47, 104, 1, 40, 0xA88A45)
    p.rect(64, 104, 1, 40, 0xA88A45)
    let mono = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
    p.text("4503 0405 1314 4413", x: 30, baseline: 172 + (26 - (mono.ascender - mono.descender)) / 2 + mono.ascender, font: mono, tracking: 1.5, 0x48484A)
    let small = NSFont.systemFont(ofSize: 13, weight: .regular)
    let line = 270 - 24 - 16 + (16 - (small.ascender - small.descender)) / 2 + small.ascender
    p.text("LEVI BAR ALPHAEUS", x: 30, baseline: line, font: small, tracking: 1.2, 0x48484A)
    let (_, expiry) = outlines("05/30", font: small, tracking: 1.2, at: .zero)
    p.text("05/30", x: 428 - 30 - expiry, baseline: line, font: small, tracking: 1.2, 0x48484A)
    return p
}

// MARK: - Everything, written out

let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = project.appendingPathComponent("Brand")
let appIcon = project.appendingPathComponent("APRFree/Assets.xcassets/AppIcon.appiconset")
guard FileManager.default.fileExists(atPath: appIcon.deletingLastPathComponent().path) else {
    fatalError("Run this from the project folder: swift Brand/make-brand.swift")
}
for folder in [appIcon, brand.appendingPathComponent("icon"), brand.appendingPathComponent("logo"), brand.appendingPathComponent("svg")] {
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
}

// 1. The app icon. One 1024-pixel square for each appearance is all Xcode and the App Store ask
// for, and it is what the Home Screen uses. The smaller sizes are listed as well so that Settings,
// Spotlight and notifications get the board's simpler drawings instead of a shrunken large one.
struct Slot { var points: CGFloat; var scales: [Int] }
let slots = [Slot(points: 20, scales: [2, 3]), Slot(points: 29, scales: [2, 3]), Slot(points: 38, scales: [2, 3]), Slot(points: 40, scales: [2, 3]),
             Slot(points: 60, scales: [2, 3]), Slot(points: 64, scales: [2, 3]), Slot(points: 68, scales: [2]), Slot(points: 76, scales: [2]),
             Slot(points: 83.5, scales: [2])]
let appearances: [(look: Look, suffix: String, value: String?)] = [(.primary, "", nil), (.dark, "-dark", "dark"), (.tinted, "-tinted", "tinted")]

for old in (try? FileManager.default.contentsOfDirectory(at: appIcon, includingPropertiesForKeys: nil)) ?? [] where old.pathExtension == "png" {
    try? FileManager.default.removeItem(at: old)
}
var images: [[String: Any]] = []
func entry(_ file: String, size: String, scale: Int?, appearance: String?) -> [String: Any] {
    var out: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": size]
    if let scale { out["scale"] = "\(scale)x" }
    if let appearance { out["appearances"] = [["appearance": "luminosity", "value": appearance]] }
    return out
}
func label(_ points: CGFloat) -> String { points == points.rounded() ? "\(Int(points))" : "\(points)" }

for (look, suffix, value) in appearances {
    for slot in slots {
        for scale in slot.scales {
            let file = "icon-\(label(slot.points))@\(scale)x\(suffix).png"
            png(icon(look, .forPoints(slot.points), rounded: false), pixels: Int((slot.points * CGFloat(scale)).rounded()), opaque: true,
                to: appIcon.appendingPathComponent(file))
            images.append(entry(file, size: "\(label(slot.points))x\(label(slot.points))", scale: scale, appearance: value))
        }
    }
    let file = "icon-1024\(suffix).png"
    png(icon(look, .full, rounded: false), pixels: 1024, opaque: true, to: appIcon.appendingPathComponent(file))
    images.append(entry(file, size: "1024x1024", scale: nil, appearance: value))
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: appIcon.appendingPathComponent("Contents.json"))

// 2. The same icon for everywhere else. Square and opaque for the App Store and for stores that cut
// the corners themselves; with the corners drawn in, on a clear ground, for a website or a document.
for look in Look.allCases {
    png(icon(look, .full, rounded: false), pixels: 1024, opaque: true, to: brand.appendingPathComponent("icon/AppIcon-\(look.rawValue)-1024.png"))
    svg(icon(look, .full, rounded: true), title: "APRFree app icon, \(look.rawValue)", to: brand.appendingPathComponent("svg/icon-\(look.rawValue).svg"))
}
for pixels in [1024, 512, 256, 180, 120, 60, 40, 29] {
    // Drawn for the size it will be seen at: a 60-pixel file is the 60-point drawing.
    png(icon(.primary, .forPoints(CGFloat(pixels) >= 256 ? 1024 : CGFloat(pixels)), rounded: true), pixels: pixels,
        to: brand.appendingPathComponent("icon/icon-rounded-\(pixels).png"))
}
for (detail, name) in [(Detail.large, "120"), (.home, "60"), (.spot, "40"), (.tiny, "29")] {
    svg(icon(.primary, detail, rounded: true), title: "APRFree app icon, \(name)-point drawing", to: brand.appendingPathComponent("svg/icon-small-\(name).svg"))
}

// 3. The wordmark, the lockup and the card. "light" files are for light backgrounds, "dark" for dark ones.
for onDark in [false, true] {
    let tone = onDark ? "dark" : "light"
    let word = wordmark(onDark: onDark), lock = lockup(onDark: onDark)
    svg(word, title: "APRFree wordmark", to: brand.appendingPathComponent("svg/wordmark-\(tone).svg"))
    svg(lock, title: "APRFree logo", to: brand.appendingPathComponent("svg/lockup-\(tone).svg"))
    for scale in [1, 2, 3, 6] {
        let at = scale == 1 ? "" : "@\(scale)x"
        png(word, pixels: Int(word.size.width) * scale, to: brand.appendingPathComponent("logo/wordmark-\(tone)\(at).png"))
        png(lock, pixels: Int(lock.size.width.rounded(.up)) * scale, to: brand.appendingPathComponent("logo/lockup-\(tone)\(at).png"))
    }
}
let card = cardFront()
svg(card, title: "APRFree card", to: brand.appendingPathComponent("svg/card-front.svg"))
for scale in [1, 2, 3] {
    png(card, pixels: 428 * scale, to: brand.appendingPathComponent("logo/card-front\(scale == 1 ? "" : "@\(scale)x").png"))
}

print("App icon: \(images.count) images in \(appIcon.path)")
print("Brand files in \(brand.path)")
