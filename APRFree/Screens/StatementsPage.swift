import SwiftUI

/// The typeface for a statement's month and year.
///
/// Apple Chancery is the face asked for. It ships with macOS but not with iOS, and its licence does
/// not allow copying it into an app, so on an iPhone the first name below is not found and the
/// next face that iOS does ship is used. To change the look, change this list.
enum StatementFont {
    static let names = ["Apple-Chancery", "SnellRoundhand-Bold"]

    /// The first of `names` this device has, or nil when it has none of them.
    static let available = names.first { UIFont(name: $0, size: 12) != nil }

    static func font(size: CGFloat) -> Font {
        available.map { .custom($0, fixedSize: size) } ?? .system(size: size * 0.9, weight: .semibold, design: .serif).italic()
    }
}

/// Page 3: a statement for every month, stacked like passes from the oldest to the newest.
struct StatementsPage: View {
    @Environment(AppStore.self) private var store
    @Binding var route: Route?
    @State private var checkingIn = false

    var body: some View {
        let statements = store.statements
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if statements.isEmpty {
                        Tile { TileNote("Add a debt to start your first statement. Each month gets its own, with everything you paid.") }
                    } else {
                        StatementStack(statements: statements, checkIn: { checkingIn = true }) { route = .statement($0.month) }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 84)
            }
            // The stack runs from the oldest month down to the newest. With many months the newest,
            // which is the one in use, would start off the bottom of the screen, so it opens there.
            .onAppear {
                if statements.count > 5 { proxy.scrollTo("newest", anchor: .center) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Statements")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .background { TopBarFade() }
        }
        .background(Theme.bg)
        .sheet(isPresented: $checkingIn) {
            StatementCheckIn().tint(Theme.primaryFill)
        }
    }
}

/// Every statement as a pass, oldest at the top with only its strip showing, newest at the bottom
/// and open.
private struct StatementStack: View {
    let statements: [MonthStatement]
    let checkIn: () -> Void
    let open: (MonthStatement) -> Void

    private let strip: CGFloat = 58

    var body: some View {
        let older = Array(statements.dropLast())
        VStack(spacing: 0) {
            // The older months overlap like passes in a stack. Each is a little taller than the strip
            // that shows, so the one below it, and the open statement at the end, cover its bottom edge.
            ZStack(alignment: .top) {
                ForEach(Array(older.enumerated()), id: \.element.id) { index, statement in
                    Button { open(statement) } label: { StatementStrip(statement: statement) }
                        .buttonStyle(.plain)
                        .frame(height: strip + 28, alignment: .top)
                        .statementCard()
                        .offset(y: CGFloat(index) * strip)
                        .accessibilityLabel("\(Fmt.monthNameYear(statement.month)) statement, \(statement.paid.usd) paid")
                        .accessibilityHint("Opens the statement")
                }
            }
            .frame(height: CGFloat(older.count) * strip, alignment: .top)
            if let newest = statements.last {
                OpenStatement(statement: newest, checkIn: checkIn) { open(newest) }
                    .id("newest")
            }
        }
    }
}

private extension View {
    /// The look of one statement: a pass with a hairline edge and a soft shadow above it.
    func statementCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: -3)
    }
}

/// The top of a statement: the month and year, and what was paid.
private struct StatementStrip: View {
    let statement: MonthStatement

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Fmt.monthNameYear(statement.month))
                .font(StatementFont.font(size: 24))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("PAID").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.secondary)
                Text(statement.paid.usd).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

/// The newest statement, open: its figures and, while the month is in progress, the check-in.
/// It grows with its contents, so larger text is never cut off.
private struct OpenStatement: View {
    @Environment(AppStore.self) private var store
    let statement: MonthStatement
    let checkIn: () -> Void
    let open: () -> Void

    var body: some View {
        let waiting = store.awaitingCheckIn.count
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 0) {
                    StatementStrip(statement: statement)
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.horizontal, 18)
                    Group {
                        row("Balance at the start", statement.opening.usd)
                        row("Paid", "−\(statement.paid.usd)", color: statement.paid > 0 ? Theme.green : .primary)
                        row("Charges added", "+\(statement.charged.usd)")
                        row("Interest recorded", "+\(statement.interest.usd)")
                        if abs(statement.other) >= 0.005 {
                            row("Other changes", statement.other > 0 ? "+\(statement.other.usd)" : "−\((-statement.other).usd)")
                        }
                        row(statement.isCurrent ? "Balance today" : "Balance at the end", statement.closing.usd, bold: true)
                    }
                    .padding(.horizontal, 18)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the statement")
            HStack(spacing: 10) {
                if statement.isCurrent {
                    Button(action: checkIn) {
                        Text(waiting > 0 ? "Check In \(Fmt.plural(waiting, "Card"))" : "Check In Again")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .foregroundStyle(Theme.onPrimary)
                            .background(Theme.primaryFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: open) {
                    HStack(spacing: 6) {
                        Text("\(Fmt.plural(statement.payments.count, "payment"))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiary)
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(Fmt.plural(statement.payments.count, "payment"))")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            if statement.isCurrent {
                Text(waiting > 0 ? "Enter what each card’s statement says this month, so its interest is counted."
                                 : "Every card has been checked against its statement this month.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 16)
        .statementCard()
    }

    private func row(_ label: String, _ value: String, color: Color = .primary, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(bold ? Color.primary : Theme.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
        }
        .font(.subheadline.weight(bold ? .semibold : .regular))
        .frame(minHeight: 30)
    }
}

// MARK: - One statement

/// A month in full: the totals, each debt's part, and every entry.
struct StatementDetail: View {
    @Environment(AppStore.self) private var store
    let month: Date
    @State private var checkingIn = false

    var body: some View {
        ScrollView {
            if let statement = store.statement(for: month) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Fmt.monthNameYear(statement.month))
                        .font(StatementFont.font(size: 34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    TileRow(minHeight: 96) {
                        StatTile(label: "Paid", value: statement.paid.usd, note: Fmt.plural(statement.payments.count, "payment"),
                                 valueColor: statement.paid > 0 ? Theme.green : .primary)
                        StatTile(label: statement.isCurrent ? "Balance today" : "Balance at the end", value: statement.closing.usd,
                                 note: changeNote(statement))
                    }
                    TileRow(minHeight: 96) {
                        StatTile(label: "Charges added", value: statement.charged.usd, note: "new purchases")
                        StatTile(label: "Interest recorded", value: statement.interest.usd, note: "loans and check-ins")
                    }
                    if abs(statement.other) >= 0.005 {
                        Text("Other changes \(statement.other > 0 ? "+\(statement.other.usd)" : "−\((-statement.other).usd)"): debts added or deleted, balances corrected by hand, and the part of a check-in or bank update that was not interest.")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if statement.isCurrent {
                        Button(store.awaitingCheckIn.isEmpty ? "Check In Again" : "Check In This Month’s Statements") { checkingIn = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if !statement.lines.isEmpty {
                        SectionHeader(title: "By Debt").padding(.top, 12)
                        CardGroup {
                            ForEach(statement.lines) { line in
                                if line.id != statement.lines.first?.id { RowDivider() }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(line.title).font(.callout.weight(.semibold)).lineLimit(1)
                                        Text(lineNote(line)).font(.caption).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(line.closing?.usd ?? "").font(.callout).monospacedDigit()
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    SectionHeader(title: "Entries", detail: "\(statement.entries.count)").padding(.top, 12)
                    if statement.entries.isEmpty {
                        Tile { TileNote("Nothing was recorded this month.") }
                    } else {
                        CardGroup {
                            ForEach(statement.entries) { record in
                                if record.id != statement.entries.first?.id { RowDivider(inset: 64) }
                                ActivityEntry(record: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $checkingIn) {
            StatementCheckIn().tint(Theme.primaryFill)
        }
    }

    private func changeNote(_ statement: MonthStatement) -> String {
        let change = statement.change
        if abs(change) < 0.005 { return "no change from the start" }
        return change < 0 ? "down \((-change).usd) from the start" : "up \(change.usd) from the start"
    }

    private func lineNote(_ line: MonthStatement.Line) -> String {
        var parts: [String] = []
        if line.paid > 0 { parts.append("\(line.paid.usd) paid") }
        if line.charged > 0 { parts.append("\(line.charged.usd) charged") }
        return parts.isEmpty ? "No payments" : parts.joined(separator: " · ")
    }
}

// MARK: - Check-in

/// The monthly check-in: type in what each statement says. The app's balance moves to match, and
/// the difference is recorded as that month's interest and anything else it had not seen.
struct StatementCheckIn: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Draft: Identifiable {
        let id: UUID
        var title: String
        var detail: String
        var isCard: Bool
        /// What the app has now. Shown in the empty fields, and used if they are left empty.
        var current: Double
        var currentMinimum: Double
        var include: Bool
        // Nil means the field was left empty: no change.
        var balance: Double?
        var minimum: Double?
        var interest: Double?
    }

    @State private var drafts: [Draft] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Open each statement and type the balance it shows. The difference from what APRFree has is recorded as interest and anything else it had not seen. Leave a field empty where the statement agrees.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .listRowBackground(Color.clear)
                }
                if drafts.isEmpty {
                    Section { Text("There are no cards or loans to check in.").foregroundStyle(Theme.secondary) }
                }
                ForEach($drafts) { $draft in
                    Section {
                        Toggle(isOn: $draft.include) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(draft.title).font(.callout.weight(.semibold))
                                Text(draft.detail).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                        .toggleStyle(NeutralToggleStyle())
                        if draft.include {
                            // Each field starts empty and shows what APRFree has, so the first key typed starts the new figure.
                            field("Statement balance", $draft.balance, shows: draft.current)
                            field(draft.isCard ? "Minimum payment" : "Monthly payment", $draft.minimum, shows: draft.currentMinimum)
                            field("Interest charged", $draft.interest, shows: nil)
                        }
                    } footer: {
                        if draft.include {
                            Text(note(draft))
                        }
                    }
                }
            }
            .focused($focused)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Statement Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!drafts.contains(where: \.include))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .onAppear {
            guard drafts.isEmpty else { return }
            let waiting = Set(store.awaitingCheckIn.map(\.id))
            drafts = store.checkInCandidates.map { debt in
                Draft(id: debt.id, title: debt.title, detail: debt.detail.isEmpty ? debt.kind.title : debt.detail, isCard: debt.kind == .card,
                      current: debt.balance, currentMinimum: debt.minimum, include: waiting.contains(debt.id))
            }
        }
    }

    private func field(_ title: String, _ value: Binding<Double?>, shows current: Double?) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text("$").foregroundStyle(Theme.secondary)
                TextField(current.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "Optional", value: value.clamped(upTo: Limits.money),
                          format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    private func note(_ draft: Draft) -> String {
        guard let balance = draft.balance else { return "Empty means the statement agrees with APRFree: \(draft.current.usd). It is still marked as checked this month." }
        let change = (balance - draft.current).cents
        if abs(change) < 0.005 { return "The same as APRFree has now. It is still marked as checked this month." }
        return change > 0 ? "\(change.usd) more than APRFree has (\(draft.current.usd)). That is added to the balance."
                          : "\((-change).usd) less than APRFree has (\(draft.current.usd)). The balance comes down to match."
    }

    private func save() {
        store.checkIn(drafts.filter(\.include).map {
            AppStore.StatementEntry(debtID: $0.id, balance: $0.balance ?? $0.current, minimum: $0.minimum.flatMap { $0 > 0 ? $0 : nil },
                                    interest: $0.interest.flatMap { $0 > 0 ? $0 : nil })
        })
        dismiss()
    }
}
