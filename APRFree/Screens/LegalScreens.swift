import SwiftUI

/// The privacy policy and the disclaimer shown during setup, and again from Settings.
///
/// Both have to be accepted before the app can be used. Changing the wording means changing
/// `version`: everyone is then shown the new text and asked again.
enum Legal {
    /// The date of the wording below. Acceptance is recorded against it.
    static let version = "2026-10-06"

    struct Section: Identifiable {
        let id = UUID()
        var title: String
        var paragraphs: [String] = []
        var points: [String] = []
    }

    struct Document {
        var title: String
        var summary: String
        var accept: String
        var sections: [Section]
    }

    static let privacy = Document(
        title: "Privacy Policy",
        summary: "APRFree keeps everything you enter on this iPhone. There is no account and no server, and nothing is sent to the developer or to anyone else.",
        accept: "I have read and accept the Privacy Policy",
        sections: [
            Section(title: "What you enter, and where it is kept",
                    paragraphs: ["APRFree stores only what you type into it:"],
                    points: ["Your debts: the bank, lender or provider names you pick or type, card and loan names, balances, interest rates, credit limits, due days, minimum payments, promotional terms, and pay-later schedules.",
                             "What you record: payments, charges, balance changes and monthly statement check-ins, with their dates.",
                             "Your income: the names, amounts and paydays you enter, your safety buffer, and your other settings.",
                             "All of it is kept in a single file in APRFree’s own private storage on this iPhone. iOS encrypts that file whenever the iPhone is locked.",
                             "A small summary (totals, the next due date and the names due then) is kept in storage shared only between APRFree and its own widget, so the widget has something to show."]),
            Section(title: "What APRFree never does",
                    points: ["It has no account, sign-in or password.",
                             "It does not connect to your bank, card issuer or lender, and it never asks for a bank login, a full card or account number, a Social Security number or any other government ID. Please do not type any of those into a name or note field.",
                             "It does not use the internet at all. Nothing you enter is sent to the developer, to Apple by the app, or to any third party.",
                             "It contains no advertising, no analytics, no tracking and no third-party code.",
                             "Because nothing leaves your iPhone, the developer cannot see your data, and cannot recover it for you if it is lost."]),
            Section(title: "When information leaves the app",
                    paragraphs: ["Only when you choose to send it somewhere:"],
                    points: ["Exports and backups. The CSV file, the PDF report and the backup file are created on your iPhone and handed to the place you pick: Files, AirDrop, Mail, a cloud drive or another app. APRFree does not encrypt these files. Anyone who has one can read it, and from that point how it is kept and who can see it depends on where you put it.",
                             "iPhone backups. If you back up your iPhone to iCloud or to a computer, APRFree’s data is part of that backup, under your Apple settings and Apple’s own terms.",
                             "Screenshots, screen sharing and screen recording, if you use them."]),
            Section(title: "Widgets and reminders",
                    points: ["Widgets show balances on your Home Screen, where anyone looking at your iPhone can see them. The eye button on the widget hides the amounts, and iOS can hide them while the iPhone is locked.",
                             "Reminders are scheduled on this iPhone and never pass through a server. Their text, which names a debt and an amount, can appear on your Lock Screen depending on your notification settings.",
                             "You can turn reminders off in APRFree’s Settings and remove the widget at any time."]),
            Section(title: "Keeping and deleting your data",
                    points: ["Your data stays on this iPhone until you remove it.",
                             "Settings, then Reset Everything, erases every debt, payment and setting.",
                             "Deleting the app erases its data from this iPhone. It does not erase files you exported, or older iPhone backups that include it."]),
            Section(title: "Keeping it safe",
                    points: ["APRFree has no lock of its own. Anyone who can unlock your iPhone can open it, so protect your iPhone with a passcode and Face ID or Touch ID.",
                             "Your iPhone holds the only copy. Use Back Up Now from time to time and keep the file somewhere you trust."]),
            Section(title: "Children",
                    paragraphs: ["APRFree is not directed to children under 13, and it collects no personal information from anyone."]),
            Section(title: "Changes to this policy",
                    paragraphs: ["If this policy changes, APRFree will show the new version and ask you to accept it before you continue. The date at the top says which version you are reading."]),
            Section(title: "Questions",
                    paragraphs: ["Use the support link on APRFree’s App Store page."]),
        ])

    static let disclaimer = Document(
        title: "Disclaimer",
        summary: "APRFree is a planning and record-keeping tool. It is not financial advice, it is not connected to any bank, and its predictions are estimates that can be wrong.",
        accept: "I understand and accept this Disclaimer",
        sections: [
            Section(title: "Not financial advice",
                    points: ["APRFree is not a financial adviser, credit counselor, lender, bank, debt-settlement company or credit-repair service.",
                             "Nothing in the app is financial, legal, tax or credit advice, and using it creates no advisory or fiduciary relationship.",
                             "A strategy, a split or a suggestion in the app is arithmetic on the numbers you entered. Whether it suits your situation is your decision. If you are unsure, talk to a qualified professional."]),
            Section(title: "Not affiliated with any bank or lender",
                    points: ["Bank, lender, provider and card names in the app belong to their owners and are used only so you can label your own debts.",
                             "APRFree is not affiliated with, endorsed by, sponsored by or connected to any of them, and it does not exchange information with them."]),
            Section(title: "APRFree does not pay anything",
                    points: ["Marking a payment as paid only records it in the app. You still have to make the payment with your bank or lender.",
                             "Make a Payment, the split and Extra Money are suggestions for where money could go. Nothing is moved for you."]),
            Section(title: "Estimates and predictions can be wrong",
                    paragraphs: ["Payoff dates, the debt-free month, interest still to come, what a strategy saves, the next paydays, statements and credit utilization are all worked out from what you entered, using simplified rules. They can differ from what your lender actually charges or requires, sometimes by a lot. In particular:"],
                    points: ["Interest is estimated as the APR divided by 365 for each day. Lenders use their own methods, such as average daily balance, grace periods and different compounding.",
                             "Fees are not predicted: late fees, annual fees, over-limit fees, balance-transfer fees and others.",
                             "Rates are assumed to stay as entered. Real rates can be variable, can change, and a missed payment can trigger a penalty rate.",
                             "Promotional terms vary, and some charge deferred interest if the balance is not cleared in time. The app does not model that.",
                             "Minimum payments are assumed to stay as entered. On a real card they change with the balance.",
                             "A card’s balance in the app only changes when you record something or check in a statement. Until then it does not include the interest your card is adding.",
                             "Due dates follow a simple rule: a payment counts toward the next due date from nine days after the previous one. Your statement cycle may not match.",
                             "Your income and paydays are assumed to continue exactly as entered.",
                             "Amounts are rounded to the cent, and totals can differ by a cent or two from the sum of their parts.",
                             "Software has bugs, and information can be typed in wrong. Either can make a figure wrong for a reason nobody foresaw."]),
            Section(title: "Always check with your lender",
                    points: ["Your statements and your lender’s own figures are the ones that count. Confirm every due date, minimum payment and balance with them.",
                             "A late or missed payment can mean fees, a higher rate and harm to your credit. APRFree is not responsible for a payment that is late, missed or the wrong amount.",
                             "Reminders are a convenience. Notifications are not guaranteed to arrive, so do not rely on them alone."]),
            Section(title: "Credit utilization",
                    paragraphs: ["The 30 percent line is a common rule of thumb. It is not a statement about your credit score, which APRFree does not know and does not calculate."]),
            Section(title: "No warranty",
                    points: ["APRFree is provided as it is, without warranties of any kind, including accuracy, fitness for a particular purpose and uninterrupted availability.",
                             "To the fullest extent the law allows, the developer is not liable for any loss arising from use of the app, including fees, interest, effects on your credit, and lost data.",
                             "Some places do not allow some of these limits, so parts of this may not apply to you."]),
            Section(title: "Your records are yours to keep safe",
                    paragraphs: ["The only copy of your data is on this iPhone. Back it up. The developer cannot restore it."]),
            Section(title: "If your debts feel unmanageable",
                    paragraphs: ["Contact your lenders early, since many have hardship options, and consider a nonprofit credit counseling agency. An app is not a substitute for that help."]),
        ])
}

/// The full text of one document.
struct LegalText: View {
    let document: Legal.Document

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(document.summary)
                .font(.callout.weight(.semibold))
            ForEach(document.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title).font(.headline)
                    ForEach(section.paragraphs, id: \.self) { Text($0) }
                    ForEach(section.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(Theme.secondary)
                            Text(point)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Version of \(Legal.version)")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The row that has to be ticked before Continue works. It sits above the button, so there is no
/// need to scroll to the end of the text to reach it.
struct LegalAcceptRow: View {
    let text: String
    @Binding var accepted: Bool

    var body: some View {
        Button { accepted.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundStyle(accepted ? Theme.primaryFill : Theme.tertiary)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(accepted ? .isSelected : [])
    }
}

/// Shown once to anyone whose data was set up before the policy and the disclaimer existed, or
/// whenever their wording changes: the two documents, each to be accepted, then on into the app.
struct LegalGate: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var acceptedPrivacy = false
    @State private var acceptedDisclaimer = false

    private var document: Legal.Document { step == 0 ? Legal.privacy : Legal.disclaimer }
    private var accepted: Binding<Bool> { step == 0 ? $acceptedPrivacy : $acceptedDisclaimer }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(document.title).font(.title.weight(.bold))
                    Text(step == 0 ? "Before you carry on, please read how APRFree handles what you enter."
                                   : "And what APRFree is, and is not.")
                        .foregroundStyle(Theme.secondary)
                    LegalText(document: document)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .id(step)
            VStack(spacing: 10) {
                LegalAcceptRow(text: document.accept, accepted: accepted)
                Button("Continue") {
                    if step == 0 {
                        step = 1
                    } else {
                        store.updateSettings {
                            $0.acceptedPrivacy = Date()
                            $0.acceptedDisclaimer = Date()
                            $0.acceptedLegalVersion = Legal.version
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!accepted.wrappedValue)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// One document to read again later, from Settings.
struct LegalReader: View {
    let document: Legal.Document

    var body: some View {
        ScrollView {
            LegalText(document: document)
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
