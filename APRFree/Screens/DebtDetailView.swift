import Charts
import SwiftUI

/// The full-screen view for one card, pay-later plan or loan.
struct DebtDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID

    @State private var editing = false
    @State private var payment: PaymentRequest?
    @State private var charging = false
    @State private var confirmingDelete = false
    @State private var showingHistory = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                if let debt = store.debt(debtID) {
                    VStack(spacing: 12) {
                        switch debt.kind {
                        case .card:
                            CardDetail(debt: debt, pay: { payment = PaymentRequest(debtID: debtID) }, charge: { charging = true })
                        case .payLater:
                            PayLaterDetail(debt: debt) { payment = PaymentRequest(debtID: debtID) }
                        case .loan:
                            LoanDetail(debt: debt) { payment = PaymentRequest(debtID: debtID) }
                        }
                        HistoryTile(debt: debt) { showingHistory = true }
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .background(Theme.bg)
            .navigationDestination(isPresented: $showingHistory) { DebtHistoryView(debtID: debtID) }
            .focused($typing)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { typing = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("History", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let debt = store.debt(debtID) { DebtEditor(debt: debt).tint(Theme.primaryFill) }
        }
        .sheet(item: $payment) { PaymentSheet(request: $0).tint(Theme.primaryFill) }
        .sheet(isPresented: $charging) { ChargeSheet(debtID: debtID).tint(Theme.primaryFill) }
        .confirmationDialog("Delete this debt? Its past payments stay in your activity.", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                store.delete(debtID)
            }
        }
        // The celebration lives on the root view, so step out of the way when this debt is paid off.
        .onChange(of: store.celebration?.id) { _, id in
            if id != nil { dismiss() }
        }
    }
}

// MARK: - Shared tiles

/// The way into a debt's payment and balance history, with its latest entry as a preview.
private struct HistoryTile: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    let action: () -> Void

    var body: some View {
        let records = store.activity(for: debt.id)
        Button(action: action) {
            HStack(spacing: 12) {
                IconCircle(symbol: "clock.arrow.circlepath")
                VStack(alignment: .leading, spacing: 0) {
                    Text("History").font(.callout.weight(.semibold))
                    Text(records.first.map { "\($0.action) · \(Fmt.monthDay($0.date))" } ?? "Payments and balances will show here")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(records.count == 1 ? "1 entry" : "\(records.count) entries")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 68)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Payment Due" / "Next Payment": the date, the amount, how soon, and the pay button.
private struct DueTile: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    let label: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        Tile {
            TileLabel(label)
            if let due = debt.nextUnpaidDue() {
                let left = debt.scheduledPayment(on: store.today)
                let full = debt.requiredPayment(on: store.today)
                TileValue(Fmt.monthDay(due))
                if left < full - 0.004 {
                    // Part of it is paid: the date stays until the rest is.
                    TileNote("\(left.usd) left of \(full.usd)")
                } else {
                    TileNote(debt.kind == .card ? "Minimum \(left.usd)" : left.usd)
                }
                if let opens = debt.dueOpens(), !debt.countsTowardDue(on: store.today) {
                    // The last due date was just met. Payments are extra until the next statement posts.
                    Text("Counts from \(Fmt.monthDay(opens))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .foregroundStyle(Theme.secondary)
                        .background(Theme.fill, in: Capsule())
                        .padding(.top, 6)
                } else {
                    StatusBadge(status: DueStatus(due: due, today: store.today))
                        .padding(.top, 6)
                }
                Spacer(minLength: 12)
                Button(buttonTitle, action: action)
                    .buttonStyle(TileButtonStyle())
            } else {
                TileValue("Paid off", color: Theme.green)
            }
        }
    }
}

private struct PayoffTile: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    var label = "Payoff"
    var scheduleNote: String?

    var body: some View {
        Tile {
            TileLabel(label)
            if let date = store.plan.payoff[debt.id] {
                TileValue(Fmt.monthYear(date))
                if let scheduleNote {
                    TileNote(scheduleNote)
                } else if debt.hasPromo(on: store.today) && store.settings.promoMinimumOnly {
                    TileNote("Minimum only until the promo ends")
                } else {
                    TileNote("On your current plan")
                }
            } else {
                TileValue("Not yet")
                TileNote("Your payday amount doesn’t reach it")
            }
        }
    }
}

// MARK: - Credit card

private struct CardDetail: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    let pay: () -> Void
    let charge: () -> Void

    var body: some View {
        CardFace(debt: debt)
            .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
            .padding(.bottom, 4)
        TileRow(minHeight: 176) {
            Tile {
                TileLabel("Card Balance")
                TileValue(debt.balance.usd)
                if let available = debt.available { TileNote("\(available.usd) available") }
                Spacer(minLength: 12)
                if let limit = debt.creditLimit { TileNote("Limit \(limit.usd)") }
            }
            DueTile(debt: debt, label: "Payment Due", buttonTitle: "Pay This Card", action: pay)
        }
        TileRow(minHeight: 124) {
            aprTile
            Tile {
                TileLabel("Increase Balance")
                TileNote("Log a new purchase")
                Spacer(minLength: 12)
                Button("Add a Charge", action: charge)
                    .buttonStyle(TileButtonStyle(green: false))
            }
        }
        TileRow(minHeight: 124) {
            utilizationTile
            PayoffTile(debt: debt)
        }
        CardCostTile(debt: debt)
    }

    @ViewBuilder private var aprTile: some View {
        if let end = debt.promoEnd, debt.hasPromo(on: store.today) {
            Tile {
                TileLabel("APR")
                TileValue(Fmt.percent(debt.promoAPR ?? 0))
                TileNote("Until \(Fmt.full(end))")
                TileNote("Then \(Fmt.percent(debt.apr))")
            }
        } else {
            StatTile(label: "APR", value: Fmt.percent(debt.apr), note: "\(debt.dailyCost(on: store.today).usd) a day")
        }
    }

    private var utilizationTile: some View {
        Tile {
            TileLabel("Utilization")
            if let used = debt.utilization, let limit = debt.creditLimit {
                HStack(spacing: 10) {
                    ProgressRing(fraction: used) {
                        Text("\(Int((used * 100).rounded()))%").font(.footnote.weight(.bold)).monospacedDigit()
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(debt.balance.usd).font(.footnote.weight(.semibold))
                        Text("of \(limit.usd)").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.top, 12)
            } else {
                TileValue("Not set")
                TileNote("Add a credit limit to see it")
            }
        }
    }
}

/// What this card costs in interest: this month, so far, and from here to payoff, on the
/// current strategy and on minimums only.
private struct CardCostTile: View {
    @Environment(AppStore.self) private var store
    let debt: Debt

    private struct Path {
        var interest: Double
        var payoff: Date
    }

    /// The current plan, whatever strategy is chosen.
    private var plan: Path? {
        guard let interest = store.projectedInterest(for: debt), let payoff = store.plan.payoff[debt.id] else { return nil }
        return Path(interest: interest, payoff: payoff)
    }

    /// Paying only the minimum each month, starting with the next due date.
    private var minimumOnly: Path? {
        let start = debt.nextUnpaidDue() ?? store.today
        guard let result = PayoffEngine.fixedPayoff(debt: debt, payment: debt.minimum, from: start) else { return nil }
        return Path(interest: result.interest, payoff: Cal.addMonths(max(0, result.months - 1), to: start))
    }

    var body: some View {
        let soFar = PayoffEngine.interestPaid(debt: debt, payments: store.data.payments)
        let plan = plan, minimum = minimumOnly
        let months = store.plan.interestByMonth(for: debt.id)
        Tile {
            TileLabel("Total Cost of This Card")
            HStack(alignment: .top, spacing: 12) {
                figure("Interest this month", debt.monthlyInterest(on: store.today).usd, "\(debt.dailyCost(on: store.today).usd) a day at today’s balance")
                figure("Interest paid so far", soFar.usd, "estimated from your payments")
            }
            .padding(.top, 10)

            if debt.isPaidOff {
                TileNote("This card is paid off. Nothing more to pay.").padding(.top, 10)
            } else {
                Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, 12)
                Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        head("Your plan", store.settings.strategy.title)
                        head("Minimum only", "\(debt.minimum.usd) a month")
                    }
                    row("Interest still to come", plan?.interest.usd ?? "Not yet", minimum?.interest.usd ?? "Never ends")
                    row("Paid off", plan.map { Fmt.monthYear($0.payoff) } ?? "Not yet", minimum.map { Fmt.monthYear($0.payoff) } ?? "Never")
                    // Added from the figures as shown, so the column adds up to the cent.
                    row("Total interest", plan.map { (soFar.cents + $0.interest.cents).usd } ?? "Not yet",
                        minimum.map { (soFar.cents + $0.interest.cents).usd } ?? "Never ends")
                }
                bars(plan: plan, minimum: minimum)
                Text(summary(plan: plan, minimum: minimum))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if plan != nil, months.count > 1 {
                    monthly(months)
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption2).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func head(_ title: String, _ note: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(.caption.weight(.bold))
            Text(note).font(.caption2).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .lineLimit(1)
        .frame(width: 96, alignment: .trailing)
    }

    private func row(_ label: String, _ plan: String, _ minimum: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            Text(plan).font(.footnote.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(minimum).font(.footnote).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    /// What gets paid in total each way: the balance, plus the interest on top of it.
    @ViewBuilder private func bars(plan: Path?, minimum: Path?) -> some View {
        let longest = max(debt.balance + (plan?.interest ?? 0), debt.balance + (minimum?.interest ?? 0), 1)
        VStack(alignment: .leading, spacing: 8) {
            if let plan { bar("Your plan", plan.interest, longest) }
            if let minimum { bar("Minimum only", minimum.interest, longest) }
            HStack(spacing: 14) {
                legend("Balance", .primary)
                legend("Interest", Theme.tertiary)
            }
        }
        .padding(.top, 14)
        .accessibilityHidden(true)
    }

    private func bar(_ label: String, _ interest: Double, _ longest: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\((debt.balance + interest).usd) in all").font(.caption2).monospacedDigit().foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary)
                        .frame(width: max(2, geo.size.width * debt.balance / longest))
                    if interest > 0.005 {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.tertiary)
                            .frame(width: max(2, geo.size.width * interest / longest))
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }

    private func summary(plan: Path?, minimum: Path?) -> String {
        guard let plan else { return "Your payday amount does not reach this card yet. Raise it in Settings to see a payoff date." }
        guard let minimum else { return "The \(debt.minimum.usd) minimum never clears this card. Your plan does, in \(Fmt.monthYear(plan.payoff))." }
        // Taken from the two figures as they are shown in the table above, so the sentence agrees with them to the cent.
        let saved = (minimum.interest.cents - plan.interest.cents).cents
        let sooner = Cal.months(from: plan.payoff, to: minimum.payoff)
        if saved < 0.005 && sooner <= 0 {
            return "Your plan pays this card its minimum for now, so both columns match."
        }
        return "Your plan saves \(max(0, saved).usd) in interest and finishes \(Fmt.plural(max(0, sooner), "month")) sooner than paying only the minimum."
    }

    /// The interest charged in each month of the plan, until the card is paid off.
    private func monthly(_ months: [PlanPoint]) -> some View {
        let shown = Array(months.prefix(18))
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, 6)
            Text("Interest each month on your plan").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Chart(shown) { point in
                BarMark(x: .value("Month", point.date, unit: .month), y: .value("Interest", point.total), width: .ratio(0.7))
                    .foregroundStyle(Theme.tertiary)
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        if shown.count <= 6 {
                            Text(point.total.usd).font(.caption2).monospacedDigit().foregroundStyle(Theme.secondary)
                        }
                    }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(amount.usd) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: shown.count <= 6 ? 1 : 3)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) { Text(Fmt.monthShort(date)) }
                    }
                }
            }
            .chartPlotStyle { $0.clipped() }
            .frame(height: 120)
            .accessibilityLabel("Interest each month on your plan, \(shown.map { "\(Fmt.monthYear($0.date)) \($0.total.usd)" }.joined(separator: ", "))")
        }
    }
}

// MARK: - Buy now, pay later

private struct PayLaterDetail: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    let pay: () -> Void

    var body: some View {
        let count = debt.installments ?? 0, paid = debt.paidInstallments ?? 0
        CardFace(debt: debt)
            .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
            .padding(.bottom, 4)
        TileRow(minHeight: 176) {
            Tile {
                TileLabel("Remaining")
                TileValue(debt.balance.usd)
                TileNote("of \((debt.total ?? debt.startingBalance).usd)")
                Spacer(minLength: 12)
                ProgressBar(fraction: count > 0 ? Double(paid) / Double(count) : 0)
                TileNote("\(paid) of \(count) paid").padding(.top, 4)
            }
            DueTile(debt: debt, label: "Next Payment", buttonTitle: "Pay This Installment", action: pay)
        }
        Tile {
            TileLabel("Schedule")
            VStack(spacing: 0) {
                ForEach(Array(debt.allInstallmentDates.enumerated()), id: \.offset) { index, date in
                    scheduleRow(date, state: index < paid ? .paid : (index == paid ? .next : .later))
                }
            }
            .padding(.top, 6)
        }
        TileRow {
            StatTile(label: "APR", value: Fmt.percent(debt.apr), note: debt.apr == 0 ? "No interest" : "\(debt.dailyCost(on: store.today).usd) a day")
            Tile {
                TileLabel("Paid From")
                Text((debt.paidFrom ?? "").isEmpty ? "Not set" : (debt.paidFrom ?? ""))
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.top, 6)
                TileNote(debt.autopay == true ? "Autopay on" : "Autopay off")
            }
        }
    }

    private enum RowState { case paid, next, later }

    private func scheduleRow(_ date: Date, state: RowState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .paid:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.onGreen)
                    .frame(width: 22, height: 22)
                    .background(Theme.green, in: Circle())
            case .next:
                Circle().strokeBorder(Color.primary, lineWidth: 2).frame(width: 22, height: 22)
            case .later:
                Circle().strokeBorder(Theme.tertiary, lineWidth: 2).frame(width: 22, height: 22)
            }
            Text(Fmt.monthDay(date)).font(.subheadline.weight(.semibold)).frame(width: 58, alignment: .leading)
            switch state {
            case .paid: Text("Paid").font(.footnote.weight(.semibold)).foregroundStyle(Theme.green)
            case .next: Text("Next").font(.footnote).foregroundStyle(Theme.secondary)
            case .later: Text("Upcoming").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(debt.minimum.usd).font(.subheadline).monospacedDigit()
        }
        .frame(height: 44)
    }
}

// MARK: - Loan

private struct LoanDetail: View {
    @Environment(AppStore.self) private var store
    let debt: Debt
    let pay: () -> Void
    @State private var extra = 50.0

    private var regular: (months: Int, interest: Double)? {
        PayoffEngine.amortize(balance: debt.balance, apr: debt.apr, payment: debt.minimum)
    }

    private var boosted: (months: Int, interest: Double)? {
        PayoffEngine.amortize(balance: debt.balance, apr: debt.apr, payment: debt.minimum + extra)
    }

    /// The month the regular payment alone would finish the loan.
    private var scheduledPayoff: Date? {
        guard let regular, let next = debt.nextUnpaidDue() else { return debt.endDate }
        return Cal.addMonths(regular.months - 1, to: next)
    }

    var body: some View {
        LoanPass(debt: debt)
            .padding(.bottom, 4)
        TileRow(minHeight: 176) {
            Tile {
                TileLabel("Balance")
                TileValue(debt.balance.usd)
                if let original = debt.originalAmount, original > 0 {
                    let paid = max(0, 1 - debt.balance / original)
                    TileNote("of \(original.usd)")
                    Spacer(minLength: 12)
                    ProgressBar(fraction: paid)
                    TileNote("\(Int((paid * 100).rounded()))% paid").padding(.top, 4)
                } else {
                    TileNote("\(debt.minimum.usd) a month")
                }
            }
            DueTile(debt: debt, label: "Payment Due", buttonTitle: "Pay This Loan", action: pay)
        }
        TileRow(minHeight: 124) {
            StatTile(label: "APR", value: Fmt.percent(debt.apr), note: "\((debt.balance * debt.apr / 1200).usd) interest this month")
            PayoffTile(debt: debt, label: "Payoff Date",
                       scheduleNote: scheduledPayoff.map { "With your plan. \(Fmt.monthYear($0)) on schedule." })
        }
        dailyCost
        extraTile
    }

    /// What the loan costs a day, and what that adds up to from here to the day it is paid off.
    private var dailyCost: some View {
        let onPlan = store.projectedInterest(for: debt)
        let payoff = store.plan.payoff[debt.id]
        return Tile {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    TileLabel("Daily Cost")
                    TileValue("\(debt.dailyCost(on: store.today).usd) a day")
                    TileNote("Falls as the balance drops")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.separator).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Projected total interest to be paid")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onPlan, let payoff {
                        TileValue(onPlan.usd)
                        TileNote("through \(Fmt.monthYear(payoff)), on your plan")
                    } else if let regular, let scheduledPayoff {
                        TileValue(regular.interest.usd)
                        TileNote("through \(Fmt.monthYear(scheduledPayoff)), on schedule")
                    } else {
                        TileValue("Not yet")
                        TileNote("The payment does not cover the interest")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if onPlan != nil, let regular, let scheduledPayoff {
                Text("The daily cost added up until payoff. Paying only \(debt.minimum.usd) a month it would be \(regular.interest.usd), through \(Fmt.monthYear(scheduledPayoff)).")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private var extraTile: some View {
        Tile {
            TileLabel("Pay a Bit Extra")
            ExtraAmountControl(amount: $extra, baseMax: 200, step: 10)
                .padding(.top, 6)
            HStack(spacing: 10) {
                if let regular, let boosted {
                    mini("Interest saved", (regular.interest - boosted.interest).usd, Theme.green)
                    mini("Finished", regular.months == boosted.months ? "Same month" : "\(Fmt.plural(regular.months - boosted.months, "month")) sooner", .primary)
                } else {
                    mini("Interest saved", "Not set", .primary)
                    mini("Finished", "Payment too low", .primary)
                }
            }
            .padding(.top, 12)
            Text("Type any amount or drag the slider. Compared with paying \(debt.minimum.usd) a month.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)
        }
    }

    private func mini(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(Theme.secondary)
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
