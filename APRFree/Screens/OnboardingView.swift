import SwiftUI

/// First-run setup, eight steps: welcome, privacy policy, disclaimer, debts, payday, safety buffer,
/// strategy, reminders. The policy and the disclaimer each have to be accepted to go on.
/// Every value asked for can be typed in here; nothing is deferred to after setup.
/// All movement comes from `OnboardingMotion`.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    /// Which way the last step change went, so the transition can follow it.
    @State private var forward = true
    @State private var frequency = PayFrequency.biweekly
    @State private var nextPayday = AppClock.today
    @State private var payAmount = 0.0
    @State private var buffer = 0.0
    @State private var strategy = Strategy.avalanche
    @State private var adding: AddRequest?
    @State private var editing: Debt?
    @State private var heroShown = false
    @State private var acceptedPrivacy = false
    @State private var acceptedDisclaimer = false
    @FocusState private var focused: Bool

    private struct AddRequest: Identifiable {
        let id = UUID()
        let kind: DebtKind
    }

    private let stepCount = 8
    private var hasDebts: Bool { !store.data.debts.isEmpty }

    /// What still stops the main button on this step.
    private var blocked: Bool {
        switch step {
        case 1: !acceptedPrivacy
        case 2: !acceptedDisclaimer
        case 3: !hasDebts
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .top) {
                    ScrollView {
                        stepContent
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .id(step)
                    .transition(OnboardingMotion.stepTransition(forward: forward, reduceMotion: reduceMotion))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                bottomBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .fullScreenCover(item: $adding) { request in
            AddDebtFlow(startKind: request.kind).tint(Theme.primaryFill)
        }
        .sheet(item: $editing) { debt in
            DebtEditor(debt: debt).tint(Theme.primaryFill)
        }
    }

    // MARK: Frame

    private var topBar: some View {
        HStack {
            if step > 0 {
                Button { go(-1) } label: { GlassCircle(symbol: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.margin)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            StepDots(count: stepCount, index: step)
                .animation(OnboardingMotion.progress, value: step)
                .padding(.bottom, 10)
            // Accepting sits here, above the button, so the text does not have to be scrolled to its end first.
            if step == 1 { LegalAcceptRow(text: Legal.privacy.accept, accepted: $acceptedPrivacy) }
            if step == 2 { LegalAcceptRow(text: Legal.disclaimer.accept, accepted: $acceptedDisclaimer) }
            Button(primaryTitle) { primary() }
                .buttonStyle(SetupButtonStyle())
                .disabled(blocked)
            if let secondaryTitle {
                Button(secondaryTitle) { secondary() }
                    .buttonStyle(SetupButtonStyle(kind: .gray))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var primaryTitle: String {
        switch step {
        case 3: "Done"
        case 7: "Allow Notifications"
        default: "Continue"
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case 3: hasDebts ? nil : "Skip"
        case 5: "Skip"
        case 7: "Not Now"
        default: nil
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: welcome
        case 1: legal(Legal.privacy, "How APRFree handles what you enter. Please read it, then accept below to continue.")
        case 2: legal(Legal.disclaimer, "What APRFree is, and what it is not. Please read it, then accept below to continue.")
        case 3: debts
        case 4: payday
        case 5: safetyBuffer
        case 6: strategyStep
        default: reminders
        }
    }

    private func heading(_ title: String, _ note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.weight(.bold))
            if let note { Text(note).foregroundStyle(Theme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
        .transition(OnboardingMotion.headlineTransition(reduceMotion: reduceMotion))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 1. Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ForEach(Array([Brand.bofa, Brand.klarna, Brand.chase].enumerated()), id: \.element.id) { index, brand in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [brand.top, brand.bottom], startPoint: .top, endPoint: .bottom))
                        .frame(width: 220, height: 138)
                        .overlay(alignment: .topLeading) {
                            if index == 2 { CardChip(ink: brand.ink).padding(.leading, 16).padding(.top, 48) }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 5, y: -3)
                        .offset(y: CGFloat(index) * 30 + (heroShown ? 0 : OnboardingMotion.heroStartOffset(reduceMotion: reduceMotion)))
                        .opacity(heroShown ? 1 : 0)
                        .animation(OnboardingMotion.heroAnimation.delay(OnboardingMotion.heroDelay(index: index)), value: heroShown)
                }
            }
            .frame(height: 198, alignment: .top)
            .padding(.top, 48)
            .accessibilityHidden(true)
            .onAppear { heroShown = true }
            Text("APRFree")
                .font(.system(size: 44, weight: .bold))
                .tracking(-0.6)
                .padding(.top, 40)
            Text("See every debt in one place. Everything stays on your iPhone.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 2 and 3. Privacy policy and disclaimer

    private func legal(_ document: Legal.Document, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            heading(document.title, note)
            LegalText(document: document)
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    // MARK: 4. Debts

    /// Pick a type, fill in its details, and repeat for as many debts as you like. Done moves on.
    private var debts: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(hasDebts ? "Add your debts" : "Add your first debt",
                    "Pick a type and fill in its details. Add as many as you like now, then tap Done. You can add more later.")
            addRow("creditcard", "Credit card", "Balance, APR and minimum", .card)
            addRow("bag", "Buy now, pay later", "A purchase split into set payments", .payLater)
            addRow("banknote", "Loan", "Auto, student, personal or other", .loan)

            if hasDebts {
                HStack(alignment: .lastTextBaseline) {
                    SmallCaption("Added")
                    Spacer()
                    Text(store.total.usd).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 14)
                CardGroup {
                    ForEach(store.data.debts) { debt in
                        if debt.id != store.data.debts.first?.id { RowDivider(inset: 58) }
                        addedRow(debt)
                            .transition(OnboardingMotion.listRowTransition(reduceMotion: reduceMotion))
                    }
                }
            }
        }
        .animation(OnboardingMotion.list, value: store.data.debts.map(\.id))
    }

    private func addRow(_ symbol: String, _ title: String, _ note: String, _ kind: DebtKind) -> some View {
        Button { adding = AddRequest(kind: kind) } label: {
            HStack(spacing: 12) {
                IconCircle(symbol: symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline)
                    Text(note).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.primaryFill)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a \(title.lowercased())")
    }

    private func addedRow(_ debt: Debt) -> some View {
        HStack(spacing: 12) {
            Swatch(debt: debt)
            VStack(alignment: .leading, spacing: 0) {
                Text(debt.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(debt.detail.isEmpty ? debt.kind.title : debt.detail).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(debt.balance.usd).font(.callout).monospacedDigit()
            Menu {
                Button("Edit", systemImage: "pencil") { editing = debt }
                Button("Remove", systemImage: "trash", role: .destructive) { store.delete(debt.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit or remove \(debt.title)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 56)
    }

    // MARK: 5. Payday

    private var payday: some View {
        let preview = PaydaySequence(first: nextPayday, frequency: frequency)
        return VStack(alignment: .leading, spacing: 0) {
            heading("When do you get paid?")
            SmallCaption("How often").padding(.horizontal, 4)
            HStack(spacing: 8) {
                ForEach(PayFrequency.allCases) { option in
                    let on = frequency == option
                    Button { withAnimation(OnboardingMotion.selection) { frequency = option } } label: {
                        Text(option.title)
                            .font(.subheadline.weight(on ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(on ? Theme.onPrimary : Color.primary)
                            .background(on ? Theme.primaryFill : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            CardGroup {
                DatePicker("Next payday", selection: $nextPayday, in: AppClock.today..., displayedComponents: .date)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                RowDivider()
                HStack(spacing: 12) {
                    Text("Usual amount")
                    Spacer(minLength: 0)
                    amountWell($payAmount)
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .frame(height: 56)
            }
            .padding(.top, 20)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your paydays: \((0..<3).map { Fmt.weekday(preview.date($0)) }.joined(separator: " · "))")
                    .font(.footnote.weight(.semibold))
                Text(rhythm)
                Text("Used for payday reminders and to split each paycheck. You can change it, or add more incomes, under Income later.")
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 12)
        }
    }

    /// Says in words how the chosen rhythm repeats, including what happens in short months.
    private var rhythm: String {
        let weekday = Fmt.weekdayName(nextPayday)
        let day = Cal.day(of: nextPayday)
        switch frequency {
        case .weekly: return "Every \(weekday)."
        case .biweekly: return "Every other \(weekday)."
        case .monthly:
            return day > 28
                ? "The \(Fmt.ordinal(day)) of every month, or the last day when the month is shorter."
                : "The \(Fmt.ordinal(day)) of every month."
        }
    }

    /// A money field that looks like somewhere to type.
    private func amountWell(_ value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(Theme.secondary)
            TextField("0.00", value: value.emptyWhenZero, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .frame(minWidth: 84)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 6. Safety buffer

    private var safetyBuffer: some View {
        VStack(spacing: 0) {
            heading("Safety buffer", "Money Make a Payment always leaves alone, like gas and groceries.")
            VStack(spacing: 6) {
                Text("Buffer amount").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                HStack(spacing: 2) {
                    Spacer()
                    Text("$").foregroundStyle(Theme.secondary)
                    TextField("0.00", value: $buffer.emptyWhenZero, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .fixedSize()
                    Spacer()
                }
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                Text("Tap to type an amount").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .padding(.top, 10)
        }
    }

    // MARK: 7. Strategy

    private var strategyStep: some View {
        VStack(spacing: 10) {
            heading("Pick a strategy", "This decides where your extra money goes first. You can change it anytime.")
            ForEach(Strategy.allCases) { option in
                let on = strategy == option
                Button { withAnimation(OnboardingMotion.selection) { strategy = option } } label: {
                    HStack(spacing: 12) {
                        IconCircle(symbol: option.symbol)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(option.title).font(.headline)
                            Text(option.blurb).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        RadioMark(on: on)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 72)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .strokeBorder(on ? Theme.primaryFill : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: 8. Reminders

    private var reminders: some View {
        VStack(spacing: 10) {
            heading("Reminders", "Allow notifications for due dates, paydays and the monthly statement check-in.")
            sample("calendar", "\(dueExample?.debt.title ?? "Your card") is due tomorrow", dueExample?.note ?? "The day before each due date")
            sample("dollarsign", "It’s payday", "Split your paycheck with Make a Payment")
            sample("doc.text", "Statement check-in", "Once a month: enter what your statements say")
        }
    }

    /// The due-date reminder as it will read for the first debt added during setup, if there is one.
    private var dueExample: (debt: Debt, note: String)? {
        for debt in store.data.debts where !debt.isPaidOff {
            let amount = debt.scheduledPayment(on: store.today)
            guard amount > 0, let due = debt.kind == .payLater ? debt.remainingInstallmentDates.first : debt.nextUnpaidDue() else { continue }
            return (debt, "\(amount.usd) \(debt.paymentWord.lowercased()), due \(Fmt.monthDay(due))")
        }
        return nil
    }

    private func sample(_ symbol: String, _ title: String, _ note: String) -> some View {
        HStack(spacing: 12) {
            IconCircle(symbol: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(note).font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: \(title). \(note)")
    }

    // MARK: Actions

    private func go(_ delta: Int) {
        focused = false
        forward = delta > 0
        withAnimation(OnboardingMotion.stepAnimation) { step = min(max(step + delta, 0), stepCount - 1) }
    }

    private func primary() {
        if step < stepCount - 1 {
            go(1)
            return
        }
        Task { @MainActor in
            let granted = await Reminders.requestAuthorization()
            finish(reminders: granted)
        }
    }

    private func secondary() {
        switch step {
        case 5:
            buffer = 0
            go(1)
        case 7:
            finish(reminders: false)
        default:
            go(1)
        }
    }

    private func finish(reminders: Bool) {
        focused = false
        withAnimation(OnboardingMotion.finish) {
            store.updateSettings {
                // The payday step becomes the first income. More can be added later under Income.
                $0.incomes = [Income(amount: max(0, payAmount), frequency: frequency, nextPayday: nextPayday,
                                     monthDays: frequency == .monthly ? [Cal.day(of: nextPayday)] : [])]
                $0.acceptedPrivacy = Date()
                $0.acceptedDisclaimer = Date()
                $0.acceptedLegalVersion = Legal.version
                $0.buffer = max(0, buffer)
                $0.strategy = strategy
                $0.remindDueDates = reminders
                $0.remindPaydays = reminders
                $0.remindCheckIn = reminders
                $0.onboarded = true
            }
        }
    }
}
