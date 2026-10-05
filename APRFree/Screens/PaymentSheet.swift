import SwiftUI

/// Text typed on the number pad, kept as the user entered it.
struct AmountEntry {
    private(set) var text: String
    /// A prefilled amount is replaced by the first key typed.
    private var fresh = true

    init(_ value: Double = 0) {
        text = value > 0 ? String(format: "%.2f", value) : "0"
    }

    var value: Double { Double(text) ?? 0 }

    var display: String {
        guard !fresh else { return value.usd }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = (Int(parts.first ?? "0") ?? 0).formatted(.number.locale(Locale(identifier: "en_US")))
        return parts.count > 1 ? "$\(whole).\(parts[1])" : "$\(whole)"
    }

    mutating func tap(_ key: String) {
        if key == "del" {
            fresh = false
            text = text.count > 1 ? String(text.dropLast()) : "0"
            return
        }
        if fresh {
            text = "0"
            fresh = false
        }
        if key == "." {
            if !text.contains(".") { text += "." }
            return
        }
        if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 2 { return }
        guard text.count < 9 else { return }
        text = text == "0" ? key : text + key
    }

    mutating func add(_ amount: Double) {
        text = String(format: "%.2f", value + amount)
        fresh = true
    }
}

/// The big amount and the number pad under it.
struct AmountPad<Accessory: View>: View {
    @Binding var entry: AmountEntry
    let caption: String
    var note: String?
    @ViewBuilder var accessory: Accessory

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "del"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            Text(caption).font(.subheadline).foregroundStyle(Theme.secondary)
            Text(entry.display)
                .font(.system(size: 56, weight: .bold))
                .monospacedDigit()
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 6)
                .accessibilityLabel(entry.value.usd)
            if let note {
                Text(note).font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 6)
            }
            accessory.padding(.top, 16)
            Spacer(minLength: 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { entry.tap(key) } label: {
                        Group {
                            if key == "del" {
                                Image(systemName: "delete.left").font(.system(size: 22))
                            } else {
                                Text(key).font(.system(size: 26, weight: .medium))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(key == "del" ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "del" ? "Delete" : key)
                }
            }
        }
    }
}

struct PaymentSheet: View {
    let request: PaymentRequest

    var body: some View {
        if let id = request.debtID {
            SinglePayment(debtID: id)
        } else {
            PaydayPayment()
        }
    }
}

/// Make a Payment: the amount, the split, then marking each line paid.
private struct PaydayPayment: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step { case amount, split, mark }
    @State private var step = Step.amount
    @State private var entry = AmountEntry()
    @State private var split: Split?
    @State private var paid: Set<UUID> = []
    @State private var committed = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .amount: amountStep
                case .split: splitStep
                case .mark: markStep
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 8)
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .amount {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { step = step == .mark ? .split : .amount } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { finish() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .onAppear { entry = AmountEntry(store.suggestedPayment) }
        .onDisappear { commit() }
    }

    private var title: String {
        switch step {
        case .amount: "Make a Payment"
        case .split: "The Split"
        case .mark: "Mark as Paid"
        }
    }

    private var amountStep: some View {
        VStack(spacing: 16) {
            AmountPad(entry: $entry, caption: "Amount to pay", note: "Payday \(Fmt.weekday(store.paydays.current))") {
                Button("+ $150") { entry.add(150) }
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.card, in: Capsule())
                    .buttonStyle(.plain)
            }
            Button("See the Split") {
                split = PayoffEngine.split(amount: entry.value, debts: store.data.debts, settings: store.settings, today: store.today)
                paid = []
                step = .split
            }
            .buttonStyle(PrimaryButtonStyle(kind: .green))
            .disabled(entry.value <= 0)
        }
    }

    @ViewBuilder private var splitStep: some View {
        if let split {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fmt.weekday(split.payday)).font(.title.weight(.bold))
                            Text("Next payday \(Fmt.monthDay(split.nextPayday)) · \(split.bufferKept.usd) buffer kept")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 4)
                        CardGroup {
                            ForEach(split.lines) { line in
                                SplitRow(line: line) { store.debt(line.debtID).map { Swatch(debt: $0) } }
                                Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, line.id == split.lines.last?.id ? 0 : 54)
                            }
                            HStack {
                                Text("Total")
                                Spacer()
                                Text(split.total.usd).monospacedDigit()
                            }
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            if split.shortBy > 0 {
                                Label("\(split.shortBy.usd) short of the minimums due before \(Fmt.monthDay(split.nextPayday))",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.orange)
                            }
                            if let summary = split.summary {
                                Text(summary).font(.headline).monospacedDigit()
                            }
                            Text("Pay in each bank’s app, then mark it paid here.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                Button("Mark as Paid") { step = .mark }
                    .buttonStyle(PrimaryButtonStyle(kind: .green))
                    .disabled(split.lines.isEmpty)
            }
        }
    }

    @ViewBuilder private var markStep: some View {
        if let split {
            let amount = split.lines.filter { paid.contains($0.id) }.reduce(0) { $0 + $1.amount }
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(paid.count) of \(split.lines.count) paid").font(.title.weight(.bold))
                            Text("\(amount.usd) of \(split.total.usd)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 4)
                        CardGroup {
                            ForEach(split.lines) { line in
                                if line.id != split.lines.first?.id { RowDivider(inset: 54) }
                                let on = paid.contains(line.id)
                                SplitRow(line: line, paid: on, leadingInset: 4) {
                                    Button {
                                        if on { paid.remove(line.id) } else { paid.insert(line.id) }
                                    } label: {
                                        CheckCircle(on: on).frame(width: 44, height: 44).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(line.title) \(line.amount.usd)")
                                    .accessibilityValue(on ? "Paid" : "Not paid")
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                Button("Mark All Paid") { paid = Set(split.lines.map(\.id)) }
                    .buttonStyle(PrimaryButtonStyle(kind: .green))
                    .disabled(paid.count == split.lines.count)
                Button("Done") { finish() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
    }

    private func finish() {
        commit()
        dismiss()
    }

    /// Applies whatever was marked paid, once.
    private func commit() {
        guard !committed, let split, !paid.isEmpty else { return }
        committed = true
        store.apply(split.lines.filter { paid.contains($0.id) }, allPaid: paid.count == split.lines.count,
                    nextPayday: split.nextPayday)
    }
}

struct CheckCircle: View {
    let on: Bool

    var body: some View {
        if on {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.onGreen)
                .frame(width: 26, height: 26)
                .background(Theme.green, in: Circle())
        } else {
            Circle().strokeBorder(Theme.tertiary, lineWidth: 2).frame(width: 26, height: 26)
        }
    }
}

private struct SplitRow<Leading: View>: View {
    let line: SplitLine
    var paid = false
    var leadingInset: CGFloat = 14
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: leadingInset < 14 ? 2 : 10) {
            leading
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(line.title).font(.callout.weight(.semibold)).lineLimit(1)
                    if line.isExtra {
                        Text("EXTRA")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .foregroundStyle(Theme.greenText)
                            .background(Theme.greenSoft, in: Capsule())
                    }
                }
                Text(paid ? "Paid" : line.detail)
                    .font(.caption)
                    .foregroundStyle(paid ? Theme.green : Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(line.amount.usd)
                .font(.callout.weight(line.isExtra ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(line.isExtra ? Theme.green : Color.primary)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 14)
        .frame(height: 52)
    }
}

/// "Pay This Card", "Pay This Installment", "Pay This Loan".
private struct SinglePayment: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID
    @State private var entry = AmountEntry()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let debt = store.debt(debtID) {
                    AmountPad(entry: $entry, caption: "\(debt.title) payment", note: note(debt)) { EmptyView() }
                    Button("Mark Paid") {
                        store.pay(debtID, amount: entry.value)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(kind: .green))
                    .disabled(entry.value <= 0)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 8)
            .background(Theme.bg)
            .navigationTitle("Mark a Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .onAppear {
            // Open on what is still due. If nothing counts toward the due date yet, start empty: it will be extra.
            if let debt = store.debt(debtID) {
                entry = AmountEntry(debt.countsTowardDue(on: store.today) ? debt.scheduledPayment(on: store.today) : 0)
            }
        }
    }

    private func note(_ debt: Debt) -> String {
        guard let due = debt.nextUnpaidDue() else { return "Balance \(debt.balance.usd)" }
        if let opens = debt.dueOpens(), !debt.countsTowardDue(on: store.today) {
            return "Extra payment. Counts toward \(Fmt.monthDay(due)) from \(Fmt.monthDay(opens))."
        }
        return "\(debt.scheduledPayment(on: store.today).usd) due \(Fmt.monthDay(due)) · balance \(debt.balance.usd)"
    }
}

/// Increase Balance: log a new purchase on a card.
struct ChargeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID
    @State private var entry = AmountEntry()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AmountPad(entry: $entry, caption: "New purchase on \(store.debt(debtID)?.title ?? "this card")") { EmptyView() }
                Button("Add Charge") {
                    store.charge(debtID, amount: entry.value)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(entry.value <= 0)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 8)
            .background(Theme.bg)
            .navigationTitle("Add a Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}
