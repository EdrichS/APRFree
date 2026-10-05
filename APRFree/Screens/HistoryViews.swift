import Charts
import SwiftUI

/// One line of activity. In a single debt's history the name is left out and the balance the
/// entry left behind is shown under the amount.
struct ActivityRow: View {
    let record: PaymentRecord
    var forOneDebt = false

    private var detail: String {
        let date = forOneDebt ? Fmt.full(record.date) : Fmt.monthDay(record.date)
        guard let interest = record.interest, interest > 0 else { return date }
        return "\(date) · \(interest.usd) interest"
    }

    var body: some View {
        HStack(spacing: 12) {
            switch record.kind {
            case .minimum, .installment, .payment, .extra:
                IconCircle(symbol: "checkmark", size: 36, background: Theme.greenSoft, color: Theme.greenText)
            case .partial:
                IconCircle(symbol: "circle.lefthalf.filled", size: 36)
            case .charge:
                IconCircle(symbol: "plus", size: 36)
            case .adjustment:
                IconCircle(symbol: "pencil", size: 36)
            case .added:
                IconCircle(symbol: "tray.and.arrow.down", size: 36)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(forOneDebt ? record.action : record.label).font(.callout).lineLimit(1)
                Text(detail).font(.caption).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(forOneDebt ? record.signedAmount : (record.kind == .adjustment ? record.signedAmount : record.amount.usd))
                    .font(.callout)
                    .monospacedDigit()
                if forOneDebt, let after = record.balanceAfter {
                    Text("Balance \(after.usd)").font(.caption).monospacedDigit().foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// An activity row you can tap. A pop-up offers to undo the entry or back out.
struct ActivityEntry: View {
    @Environment(AppStore.self) private var store
    let record: PaymentRecord
    var forOneDebt = false
    @State private var asking = false

    private var blocker: String? { store.undoBlocker(record) }

    private var title: String {
        let amount = record.kind == .adjustment ? record.signedAmount : record.amount.usd
        return "\(record.label) · \(amount)"
    }

    /// What undoing will do, in plain terms.
    private var message: String {
        if let blocker { return blocker }
        guard store.debt(record.debtID) != nil else {
            return "\(record.title) has been deleted, so this only removes the entry from your activity."
        }
        let later = store.data.payments.drop { $0.id != record.id }.dropFirst().contains { $0.debtID == record.debtID }
        var text: String
        switch record.kind {
        case .charge:
            text = "The \(record.amount.usd) charge comes off \(record.title)."
        case .adjustment:
            text = "\(record.title) goes back to the balance it had before this edit."
        default:
            text = "\(record.title) goes back to how it was before this payment: the balance, and the due date it counted toward."
        }
        if later { text += " Later \(record.title) entries are kept and applied again." }
        return text
    }

    var body: some View {
        Button { asking = true } label: {
            ActivityRow(record: record, forOneDebt: forOneDebt)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Offers to undo this entry")
        .alert(title, isPresented: $asking) {
            if blocker == nil {
                Button("Undo Activity", role: .destructive) { store.undo(record.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

/// The complete activity history: every payment, charge and balance change, grouped by month.
struct ActivityContent: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let all = store.activity
        // Grouping keeps each month's entries in the order they arrive: newest first.
        let groups = Dictionary(grouping: all) { Cal.monthStart($0.date) }
        let months = groups.keys.sorted(by: >)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if all.isEmpty {
                    Tile { TileNote("Payments you mark as paid show up here.") }
                } else {
                    Text("\(all.count) \(all.count == 1 ? "entry" : "entries") since \(Fmt.full(all.last?.date ?? store.today)). Tap one to undo it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }
                ForEach(months, id: \.self) { month in
                    let records = groups[month] ?? []
                    let paid = records.filter(\.isPayment).reduce(0) { $0 + $1.amount }
                    SectionHeader(title: Fmt.monthNameYear(month), detail: paid > 0 ? "\(paid.usd) paid" : nil)
                        .padding(.top, 14)
                    CardGroup {
                        ForEach(records) { record in
                            if record.id != records.first?.id { RowDivider(inset: 64) }
                            ActivityEntry(record: record)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
    }
}

/// One debt's history: its balance over time and every entry with the balance it left.
struct DebtHistoryView: View {
    @Environment(AppStore.self) private var store
    let debtID: UUID

    var body: some View {
        ScrollView {
            if let debt = store.debt(debtID) {
                let records = store.activity(for: debtID)
                VStack(spacing: 12) {
                    balanceTile(debt, records)
                    totals(debt, records)
                    if records.isEmpty {
                        Tile { TileNote("Nothing recorded yet. Payments, charges and balance changes will show here.") }
                    } else {
                        CardGroup {
                            ForEach(records) { record in
                                if record.id != records.first?.id { RowDivider(inset: 64) }
                                ActivityEntry(record: record, forOneDebt: true)
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
        .navigationTitle("\(store.debt(debtID)?.title ?? "") History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The balance each entry left, as steps: it holds until the next entry changes it.
    private func balanceTile(_ debt: Debt, _ records: [PaymentRecord]) -> some View {
        var points = records.reversed().compactMap { record in
            record.balanceAfter.map { PlanPoint(date: record.date, total: $0) }
        }
        if let last = points.last, Cal.startOfDay(last.date) < store.today {
            points.append(PlanPoint(date: store.today, total: debt.balance))
        }
        let top = max(points.map(\.total).max() ?? 0, debt.balance, 1)
        return Tile {
            TileLabel("Balance")
            TileValue(debt.balance.usd, size: 34)
            if points.count > 1 {
                Chart(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.total))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                .balanceAxes(top: top, from: points.first?.date ?? store.today, to: points.last?.date ?? store.today)
                .frame(height: 140)
                .padding(.top, 14)
                .accessibilityLabel("Balance over time, from \(points.first?.total.usd ?? "") to \(debt.balance.usd)")
            }
        }
    }

    private func totals(_ debt: Debt, _ records: [PaymentRecord]) -> some View {
        let payments = records.filter(\.isPayment)
        let paid = payments.reduce(0) { $0 + $1.amount }
        return TileRow(minHeight: 96) {
            StatTile(label: "Paid in total", value: paid.usd, note: Fmt.plural(payments.count, "payment"))
            if debt.kind == .card {
                let charges = records.filter { $0.kind == .charge }
                StatTile(label: "Charges added", value: charges.reduce(0) { $0 + $1.amount }.usd, note: Fmt.plural(charges.count, "charge"))
            } else {
                let interest = payments.reduce(0) { $0 + ($1.interest ?? 0) }
                StatTile(label: "Of that, interest", value: interest.usd, note: "\((paid - interest).usd) off the balance")
            }
        }
    }
}
