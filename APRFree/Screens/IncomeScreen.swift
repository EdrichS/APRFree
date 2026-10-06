import SwiftUI

/// Income: every source of pay on its own schedule, or one fixed amount a month in their place,
/// and the paydays that follow from them.
struct IncomeContent: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Income?
    @State private var adding: Income?
    @FocusState private var focused: Bool

    private var settings: PlanSettings { store.settings }

    var body: some View {
        Form {
            Section {
                Picker("Plan from", selection: Binding(get: { settings.useFixedAmount },
                                                       set: { on in store.updateSettings("Change income") { $0.useFixedAmount = on } })) {
                    Text("My paydays").tag(false)
                    Text("A fixed amount").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(settings.useFixedAmount
                     ? "The plan uses one amount a month that you set aside for debt, whatever your paydays are."
                     : "The plan follows your paydays: each paycheck covers what is due before the next one, and the rest goes to your strategy.")
            }
            if settings.useFixedAmount { fixed } else { paydays }
            predictor
        }
        .focused($focused)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .sheet(item: $editing) { income in
            IncomeEditor(draft: income, isNew: false).tint(Theme.primaryFill)
        }
        .sheet(item: $adding) { income in
            IncomeEditor(draft: income, isNew: true).tint(Theme.primaryFill)
        }
    }

    // MARK: Paydays

    @ViewBuilder private var paydays: some View {
        Section {
            ForEach(settings.incomes) { income in
                Button { editing = income } label: { IncomeRow(income: income, today: store.today) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this income to change it")
            }
            .onDelete { offsets in
                store.updateSettings("Delete income") { $0.incomes.remove(atOffsets: offsets) }
            }
            Button {
                adding = Income(name: settings.incomes.isEmpty ? "Paycheck" : "Income \(settings.incomes.count + 1)", nextPayday: store.today)
            } label: {
                Label("Add Income", systemImage: "plus")
            }
            .disabled(settings.incomes.count >= 12)
        } header: {
            Text("Your income")
        } footer: {
            if settings.incomes.isEmpty {
                Text("Add what you are paid and when. Without an income there is no payoff plan to show.")
            } else {
                Text("Tap an income to change its amount or its paydays. Swipe one left to delete it.")
            }
        }
        Section {
            MoneyField(title: "Safety buffer", value: Binding(get: { settings.buffer }, set: { value in store.updateSettings("Change safety buffer", merging: true) { $0.buffer = value } }))
        } footer: {
            Text("Held back out of every paycheck. About \(store.monthlyForDebt.usd) a month goes to debt after it.")
        }
    }

    // MARK: Fixed amount

    @ViewBuilder private var fixed: some View {
        Section {
            MoneyField(title: "For debt each month", value: Binding(get: { settings.fixedAmount },
                                                                    set: { value in store.updateSettings("Change fixed amount", merging: true) { $0.fixedAmount = value } }))
            Picker("On the", selection: Binding(get: { settings.fixedDay }, set: { day in
                store.updateSettings("Change income") {
                    $0.fixedDay = day
                    $0.fixedNext = nil
                }
            })) {
                ForEach(1...31, id: \.self) { Text($0 == 31 ? "31st or last day" : Fmt.ordinal($0)).tag($0) }
            }
        } header: {
            Text("Fixed amount")
        } footer: {
            Text("All of it goes to debt: no safety buffer is taken out. Your incomes are kept and come back if you switch to paydays.")
        }
    }

    // MARK: Next paydays

    /// The next paydays across every income, with what arrives on each.
    private var predictor: some View {
        let coming = store.upcomingPaydays(6)
        let names = Dictionary(store.schedule.lines.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return Section {
            if coming.isEmpty {
                Text("None yet.").foregroundStyle(Theme.secondary)
            }
            ForEach(coming, id: \.day) { event in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Fmt.weekday(event.day.date)).font(.callout.weight(.semibold))
                        Text(when(event.day.date) + " · " + event.lines.compactMap { names[$0] }.filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(event.gross.usd).font(.callout).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        if event.net < event.gross - 0.005 {
                            Text("\(event.net.usd) to debt").font(.caption).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(settings.useFixedAmount ? "Next dates" : "Next paydays")
        } footer: {
            if !coming.isEmpty {
                Text("Worked out from the schedule above. A payday that passes moves on by itself.")
            }
        }
    }

    private func when(_ date: Date) -> String {
        let days = Cal.days(from: store.today, to: date)
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
    }
}

/// One income in the list: its name and rhythm, and what arrives. At the largest text sizes the
/// amount moves under the name instead of squeezing it.
private struct IncomeRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let income: Income
    let today: Date

    private var name: some View {
        Text(income.name.isEmpty ? "Income" : income.name).font(.callout.weight(.semibold))
    }

    private var rhythm: some View {
        Text("\(income.rhythm) · next \(Fmt.weekday(income.paydays(from: today, count: 1).first ?? income.nextPayday))")
            .font(.caption)
            .foregroundStyle(Theme.secondary)
    }

    private var amount: some View {
        Text(income.amount.usd).font(.callout).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
    }

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        rhythm
                        amount
                    }
                    Spacer(minLength: 8)
                    chevron
                }
            } else {
                HStack(spacing: 12) {
                    IconCircle(symbol: "banknote")
                    VStack(alignment: .leading, spacing: 0) {
                        name.lineLimit(1)
                        rhythm.lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    amount.layoutPriority(1)
                    chevron
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One income: its name, its amount, and exactly which days it is paid on.
struct IncomeEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: Income
    let isNew: Bool
    @FocusState private var focused: Bool

    private var today: Date { store.today }

    /// The next seven days, one for each weekday, to pick a payday from.
    private var week: [Date] { (0..<7).map { Cal.addDays($0, to: today) } }

    /// The soonest date on or after today that falls on the income's weekday.
    private var soonest: Date {
        week.first { Day($0).weekday == Day(draft.nextPayday).weekday } ?? today
    }

    private var preview: [Date] { draft.paydays(from: today, count: 4) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Paycheck", text: $draft.name).multilineTextAlignment(.trailing)
                    }
                    MoneyField(title: "Amount each payday", value: $draft.amount)
                }
                Section {
                    Picker("How often", selection: Binding(get: { draft.frequency }, set: setFrequency)) {
                        ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                switch draft.frequency {
                case .weekly: weekly
                case .biweekly: biweekly
                case .monthly: monthly
                }
                Section {
                    ForEach(preview, id: \.self) { date in
                        LabeledContent(Fmt.weekday(date), value: when(date))
                    }
                } header: {
                    Text("Next paydays")
                } footer: {
                    Text("\(draft.rhythm).")
                }
                if !isNew {
                    Section {
                        Button("Delete Income", role: .destructive) {
                            store.updateSettings("Delete income") { $0.incomes.removeAll { $0.id == draft.id } }
                            dismiss()
                        }
                    }
                }
            }
            .focused($focused)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "Add Income" : "Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isNew ? "Add" : "Save") { save() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    private func when(_ date: Date) -> String {
        let days = Cal.days(from: today, to: date)
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
    }

    // MARK: Which days

    private var weekdayPicker: some View {
        Picker("Paid on", selection: Binding(get: { soonest }, set: { draft.nextPayday = $0 })) {
            ForEach(week, id: \.self) { Text(Fmt.weekdayName($0)).tag($0) }
        }
    }

    private var weekly: some View {
        Section {
            weekdayPicker
        } footer: {
            Text("Paid every week on that day.")
        }
    }

    /// Every two weeks there are two possible runs of paydays for a weekday. This picks which one.
    private var biweekly: some View {
        let later = Cal.addDays(7, to: soonest)
        return Section {
            weekdayPicker
            Picker("Next payday", selection: Binding(
                get: { Cal.days(from: soonest, to: draft.nextPayday) % 14 == 0 ? soonest : later },
                set: { draft.nextPayday = $0 })) {
                Text(Fmt.weekday(soonest)).tag(soonest)
                Text(Fmt.weekday(later)).tag(later)
            }
        } footer: {
            Text("Pick the weekday, then which of the two weeks your next payday falls in. Every payday after it follows two weeks apart.")
        }
    }

    /// One or more days of the month: the 1st, or the 1st and the 15th, and so on.
    private var monthly: some View {
        let days: [Int] = draft.payDays
        return Section {
            ForEach(days.indices, id: \.self) { index in
                monthDayRow(index, of: days)
            }
            if days.count < 4 {
                Button { setMonthDays(days + [anotherDay(after: days)]) } label: {
                    Label("Add Another Pay Day", systemImage: "plus")
                }
            }
        } footer: {
            Text("Paid on the same day or days every month. In a month too short for a day, the last day of that month is used.")
        }
    }

    private func monthDayRow(_ index: Int, of days: [Int]) -> some View {
        let selection = Binding<Int>(get: { days[index] }, set: { setMonthDay(index, $0) })
        return HStack {
            Picker(days.count > 1 ? "Pay day \(index + 1)" : "Pay day", selection: selection) {
                ForEach(1...31, id: \.self) { day in
                    Text(day == 31 ? "31st or last day" : Fmt.ordinal(day)).tag(day)
                }
            }
            if days.count > 1 {
                Button {
                    var rest = days
                    rest.remove(at: index)
                    setMonthDays(rest)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove pay day \(index + 1)")
            }
        }
    }

    /// A day to offer as the next pay day: half a month on from the last one, which is the usual
    /// pairing (the 1st and the 15th), or failing that the first day not already taken.
    private func anotherDay(after days: [Int]) -> Int {
        let half = ((days.last ?? 1) + 13) % 31 + 1
        if !days.contains(half) { return half }
        return (1...31).first { !days.contains($0) } ?? 15
    }

    // MARK: Changes

    private func setFrequency(_ frequency: PayFrequency) {
        draft.frequency = frequency
        if frequency == .monthly {
            setMonthDays([Cal.day(of: max(draft.nextPayday, today))])
        } else {
            draft.monthDays = []
            if draft.nextPayday < today { draft.nextPayday = today }
        }
    }

    private func setMonthDay(_ index: Int, _ day: Int) {
        var days = draft.payDays
        guard days.indices.contains(index) else { return }
        days[index] = day
        setMonthDays(days)
    }

    /// The next payday of a monthly income follows from its pay days: the first one today or later.
    private func setMonthDays(_ days: [Int]) {
        let clean = Array(Set(days.map { min(max(1, $0), 31) })).sorted()
        draft.monthDays = clean.isEmpty ? [1] : clean
        draft.nextPayday = PaySchedule.Line(first: Day(today), frequency: .monthly, monthDays: draft.monthDays).day(0).date
    }

    private func save() {
        var income = draft
        income.name = income.name.trimmingCharacters(in: .whitespaces)
        income.amount = Limits.money(income.amount).cents
        if income.frequency == .monthly {
            income.monthDays = income.payDays
        } else {
            income.monthDays = []
            if income.nextPayday < today { income.nextPayday = income.paydays(from: today, count: 1).first ?? today }
        }
        store.updateSettings(isNew ? "Add income" : "Edit income") { settings in
            if let i = settings.incomes.firstIndex(where: { $0.id == income.id }) {
                settings.incomes[i] = income
            } else {
                settings.incomes.append(income)
            }
        }
        dismiss()
    }
}
