import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// System grays plus one accent. Green is only for Make a Payment and paid or positive
/// states; orange and red only for due-soon and overdue.
enum Theme {
    static let bg = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemGroupedBackground)
    static let fillOnBG = Color(light: 0xE4E4E9, dark: 0x1C1C1E)

    static let secondary = Color(light: 0x636366, dark: 0xA1A1A6)
    static let tertiary = Color(light: 0x808085, dark: 0x7C7C80)
    static let separator = Color(light: 0xE3E3E8, dark: 0x38383A)
    static let track = Color(light: 0xE4E4E9, dark: 0x3A3A3C)

    static let green = Color(light: 0x1E8537, dark: 0x30D158)
    static let onGreen = Color(light: 0xFFFFFF, dark: 0x00250C)
    static let greenSoft = Color(light: 0xE2F3E6, dark: 0x12351B)
    static let greenText = Color(light: 0x14602A, dark: 0x30D158)

    static let orange = Color(light: 0xA84B00, dark: 0xFFB340)
    static let orangeSoft = Color(light: 0xFFEFD9, dark: 0x3D2A0A)
    static let red = Color(light: 0xD70015, dark: 0xFF6961)
    static let redSoft = Color(light: 0xFFE5E3, dark: 0x3D1513)

    /// Neutral primary button: near-black in light mode, white in dark.
    static let primaryFill = Color(light: 0x1C1C1E, dark: 0xFFFFFF)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x000000)

    static let totalCard = Color(light: 0x1C1C1E, dark: 0x2C2C2E)
    static let totalSecondary = Color(hex: 0xC7C7CC)

    static let cornerRadius: CGFloat = 20
    static let cardRadius: CGFloat = 18
    static let margin: CGFloat = 16
}

/// How a bank or provider's name is set on its card. The typefaces all ship with iOS; they are
/// chosen to suggest each brand's wordmark, not to reproduce it. The banks' own fonts are
/// proprietary and are not used, and no logo artwork appears anywhere in the app.
struct Wordmark: Hashable {
    /// One switch for the whole app. Set it to false and every bank and provider name is drawn in
    /// the plain system font, as written, with nothing that suggests the brand's own lettering.
    static let styled = true

    /// PostScript name of an iOS system font. Empty means the system font.
    var font = ""
    var scale: CGFloat = 1
    var casing = Casing.asWritten
    var tracking: CGFloat = 0

    enum Casing { case asWritten, upper, lower }

    func text(_ name: String) -> String {
        guard Wordmark.styled else { return name }
        switch casing {
        case .asWritten: return name
        case .upper: return name.uppercased()
        case .lower: return name.lowercased()
        }
    }

    func font(size: CGFloat) -> Font {
        font.isEmpty || !Wordmark.styled ? .system(size: size, weight: .semibold) : .custom(font, fixedSize: size * scale)
    }

    /// Letter spacing to use with `font(size:)`.
    var spacing: CGFloat { Wordmark.styled ? tracking : 0 }
}

/// A bank or provider: its card colours, how its name is set, and the cards it offers.
struct Brand: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let top: Color
    let bottom: Color
    let ink: Color
    let kind: DebtKind
    var mark = Wordmark()
    var cards: [String] = []

    var hasWhiteInk: Bool { ink == .white }

    static let chase = Brand(id: "chase", name: "Chase", short: "Chase", top: Color(hex: 0x1272BE), bottom: Color(hex: 0x0C5A9C),
                             ink: .white, kind: .card, mark: Wordmark(font: "AvenirNext-Bold", casing: .upper, tracking: 0.8),
                             cards: ["Freedom Unlimited", "Freedom Flex", "Sapphire Preferred", "Sapphire Reserve", "Slate Edge"])
    static let capitalOne = Brand(id: "capitalone", name: "Capital One", short: "Capital One", top: Color(hex: 0xD5D8DC),
                                  bottom: Color(hex: 0xB4B9C0), ink: Color(hex: 0x1C1C1E), kind: .card,
                                  mark: Wordmark(font: "AvenirNext-BoldItalic", tracking: -0.2),
                                  cards: ["Quicksilver", "QuicksilverOne", "Savor", "Venture", "Platinum"])
    static let bofa = Brand(id: "bofa", name: "Bank of America", short: "BofA", top: Color(hex: 0xD4152F), bottom: Color(hex: 0xA80F25),
                            ink: .white, kind: .card, mark: Wordmark(font: "AvenirNextCondensed-DemiBold", scale: 1.05, casing: .upper, tracking: 0.6),
                            cards: ["Customized Cash Rewards", "Unlimited Cash Rewards", "Travel Rewards", "BankAmericard"])
    static let citi = Brand(id: "citi", name: "Citi", short: "Citi", top: Color(hex: 0x0E4A8F), bottom: Color(hex: 0x093366),
                            ink: .white, kind: .card, mark: Wordmark(font: "DINAlternate-Bold", scale: 1.2, casing: .lower),
                            cards: ["Double Cash", "Custom Cash", "Simplicity", "Diamond Preferred"])
    static let amex = Brand(id: "amex", name: "American Express", short: "Amex", top: Color(hex: 0x7CC4EE), bottom: Color(hex: 0x55AADF),
                            ink: Color(hex: 0x06284A), kind: .card,
                            mark: Wordmark(font: "HelveticaNeue-CondensedBold", casing: .upper, tracking: 0.6),
                            cards: ["Blue Cash Everyday", "Blue Cash Preferred", "Gold Card", "Platinum Card"])
    static let klarna = Brand(id: "klarna", name: "Klarna", short: "Klarna", top: Color(hex: 0xFFB3C7), bottom: Color(hex: 0xFFA1BA),
                              ink: Color(hex: 0x17120F), kind: .payLater, mark: Wordmark(font: "AvenirNext-Heavy"))
    static let affirm = Brand(id: "affirm", name: "Affirm", short: "Affirm", top: Color(hex: 0x4A4AF4), bottom: Color(hex: 0x3A3AD6),
                              ink: .white, kind: .payLater, mark: Wordmark(font: "Avenir-Medium", scale: 1.1, casing: .lower))
    static let other = Brand(id: "other", name: "Other", short: "Bank", top: Color(hex: 0x5A5A5F), bottom: Color(hex: 0x3A3A3C),
                             ink: .white, kind: .card)

    static let banks = [chase, capitalOne, bofa, citi, amex]
    static let payLater = [klarna, affirm]
    static let all = banks + payLater + [other]

    static func named(_ id: String) -> Brand {
        all.first { $0.id == id } ?? other
    }
}

extension Debt {
    var brandStyle: Brand { Brand.named(brand) }

    /// A compact name for tight rows: "Amex", "BofA", "Auto loan".
    var shortTitle: String {
        kind == .card && brand != Brand.other.id ? brandStyle.short : title
    }
}
