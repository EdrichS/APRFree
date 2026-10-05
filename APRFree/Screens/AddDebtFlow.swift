import SwiftUI

extension Debt {
    static func newCard(brand: Brand, name: String) -> Debt {
        Debt(kind: .card, provider: brand.id == "other" ? "" : brand.name, name: name, brand: brand.id, balance: 0, apr: 0,
             dueDay: 1, minimum: 0, addedAt: AppClock.now, startingBalance: 0)
    }

    static func newPayLater(brand: Brand?) -> Debt {
        Debt(kind: .payLater, provider: brand?.name ?? "", name: "", brand: brand?.id ?? "other", balance: 0, apr: 0, minimum: 0,
             total: 0, installments: 4, paidInstallments: 0, every: .biweekly, nextDue: AppClock.today, paidFrom: "",
             autopay: false, addedAt: AppClock.now, startingBalance: 0)
    }

    static func newLoan(type: LoanType) -> Debt {
        Debt(kind: .loan, provider: "", name: "", brand: "other", balance: 0, apr: 0, dueDay: 1, minimum: 0, loanType: type,
             endDate: Cal.addMonths(36, to: AppClock.today), addedAt: AppClock.now, startingBalance: 0)
    }
}

private enum AddStep: Hashable {
    case pickCard(String)
    case form(Debt)
}

/// Add a debt: pick a bank or provider, pick the card, fill in the form.
struct AddDebtFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var startKind: DebtKind?

    @State private var path: [AddStep] = []
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchField
                    ForEach(sections, id: \.self) { kind in
                        section(kind)
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.bg)
            .navigationTitle("Add a Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: AddStep.self) { step in
                switch step {
                case .pickCard(let id):
                    PickCardView(brand: Brand.named(id)) { path.append(.form(.newCard(brand: Brand.named(id), name: $0))) }
                case .form(let draft):
                    DebtForm(draft: draft, isNew: true) { debt in
                        store.add(debt)
                        dismiss()
                    }
                }
            }
        }
    }

    /// The kind chosen in onboarding leads; the others follow.
    private var sections: [DebtKind] {
        guard let startKind else { return DebtKind.allCases }
        return [startKind] + DebtKind.allCases.filter { $0 != startKind }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Search banks and lenders", text: $search)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.fillOnBG, in: Capsule())
    }

    private func matches(_ name: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder private func section(_ kind: DebtKind) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: kind == .loan ? 4 : 3)
        switch kind {
        case .card:
            let banks = Brand.banks.filter { matches($0.name) }
            group("Credit cards", columns) {
                ForEach(banks) { brand in
                    ProviderTile(name: brand.name, brand: brand) { path.append(.pickCard(brand.id)) }
                }
                ProviderTile(name: "Other bank", symbol: "plus") { path.append(.form(.newCard(brand: .other, name: ""))) }
            }
        case .payLater:
            let providers = Brand.payLater.filter { matches($0.name) }
            group("Buy now, pay later", columns) {
                ForEach(providers) { brand in
                    ProviderTile(name: brand.name, brand: brand) { path.append(.form(.newPayLater(brand: brand))) }
                }
                ProviderTile(name: "Other provider", symbol: "plus") { path.append(.form(.newPayLater(brand: nil))) }
            }
        case .loan:
            let types = LoanType.allCases.filter { matches($0.title) }
            if !types.isEmpty {
                group("Loans", columns) {
                    ForEach(types) { type in
                        ProviderTile(name: type.short, symbol: type.symbol) { path.append(.form(.newLoan(type: type))) }
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, _ columns: [GridItem], @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 10) { content() }
        }
    }
}

private struct ProviderTile: View {
    let name: String
    var brand: Brand?
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let brand {
                        // A small card in the brand's colour with its name on it.
                        WordmarkText(brand: brand, size: 13)
                            .foregroundStyle(brand.ink)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(LinearGradient(colors: [brand.top, brand.bottom], startPoint: .top, endPoint: .bottom),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: symbol ?? "plus")
                            .font(.system(size: 19, weight: .medium))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(height: 40)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PickCardView: View {
    let brand: Brand
    let onContinue: (String) -> Void
    @State private var selected: String?

    private var other: String { "Other \(brand.name) card" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pick your card").font(.title.weight(.bold))
                Text("Choose the \(brand.name) card you carry.")
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 6)
                CardGroup {
                    ForEach(brand.cards + [other], id: \.self) { name in
                        if name != brand.cards.first { RowDivider() }
                        Button { selected = name } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(LinearGradient(colors: name == other ? [Theme.fill, Theme.fill] : [brand.top, brand.bottom],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 44, height: 28)
                                Text(name).fontWeight(selected == name ? .semibold : .regular)
                                Spacer()
                                if selected == name { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") { onContinue(selected == other ? "" : (selected ?? "")) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected == nil)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 8)
        }
        .onAppear { if selected == nil { selected = brand.cards.first } }
    }
}

/// Editing an existing debt, presented as a sheet.
struct DebtEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debt: Debt

    var body: some View {
        NavigationStack {
            DebtForm(draft: debt, isNew: false) { saved in
                store.save(saved)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The form for a card, a pay-later plan or a loan. Used for both adding and editing.
struct DebtForm: View {
    @State var draft: Debt
    let isNew: Bool
    let onSave: (Debt) -> Void

    @State private var chargesInterest = false
    @State private var hasStart = false
    /// The debt as it was when the form opened.
    @State private var original: Debt?
    @FocusState private var focused: Bool

    private var brand: Brand { draft.brandStyle }

    var body: some View {
        Form {
            switch draft.kind {
            case .card: cardFields
            case .payLater: payLaterFields
            case .loan: loanFields
            }
        }
        .focused($focused)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                // Says why the button is not ready yet, instead of leaving it greyed out without a reason.
                if let missing {
                    Text(missing)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(saveTitle) { onSave(finished) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(missing != nil)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background { Theme.bg.ignoresSafeArea(edges: .bottom) }
        }
        .onAppear {
            guard original == nil else { return }
            original = draft
            chargesInterest = draft.apr > 0
            hasStart = draft.startDate != nil
        }
    }

    private var title: String {
        switch draft.kind {
        case .card: draft.name.isEmpty ? (draft.provider.isEmpty ? "Credit Card" : draft.provider) : draft.name
        case .payLater: "Buy Now, Pay Later"
        case .loan: "Loan"
        }
    }

    private var saveTitle: String {
        guard isNew else { return "Save" }
        switch draft.kind {
        case .card: return "Add Card"
        case .payLater: return "Add Plan"
        case .loan: return "Add Loan"
        }
    }

    /// What still has to be filled in before the debt can be saved, or nil when it is ready.
    /// A debt already at zero can be edited and saved as it is; a new one needs a balance.
    private var missing: String? {
        let unnamed = draft.provider.trimmingCharacters(in: .whitespaces).isEmpty
        let needsBalance = isNew && draft.balance <= 0
        switch draft.kind {
        case .card:
            if unnamed { return "Add the bank’s name to continue." }
            if needsBalance { return "Add the balance to continue." }
            // Without a minimum a due date could never be met, so it would sit there as overdue.
            if draft.balance > 0 && draft.minimum <= 0 { return "Add the minimum payment to continue. It is on your statement; a close estimate is fine." }
        case .payLater:
            if unnamed { return "Add the provider’s name to continue." }
            if (draft.total ?? 0) <= 0 { return "Add the total to continue." }
        case .loan:
            if needsBalance { return "Add the balance to continue." }
            if draft.balance > 0 && draft.minimum <= 0 { return "Add the monthly payment to continue." }
        }
        return nil
    }

    /// The draft with its derived fields filled in.
    private var finished: Debt {
        var d = draft
        d.provider = d.provider.trimmingCharacters(in: .whitespaces)
        d.name = d.name.trimmingCharacters(in: .whitespaces)
        switch d.kind {
        case .card:
            if d.promoAPR == nil { d.promoEnd = nil }
            if d.promoAPR != nil && d.promoEnd == nil { d.promoEnd = Cal.addMonths(12, to: AppClock.today) }
            if isNew { d.startingBalance = d.balance }
        case .payLater:
            let count = max(1, d.installments ?? 1)
            let paid = min(max(0, d.paidInstallments ?? 0), count - 1)
            let each = ((d.total ?? 0) / Double(count)).cents
            d.installments = count
            d.paidInstallments = paid
            d.minimum = each
            // The balance follows from the schedule. When only other fields were edited, keep the balance
            // as it is, so money already paid toward the next installment is not lost.
            let sameSchedule = !isNew && original?.total == d.total && original?.installments == count
                && original?.paidInstallments == paid
            if !sameSchedule {
                d.balance = ((d.total ?? 0) - each * Double(paid)).cents
                d.paidTowardDue = nil
            }
            d.apr = chargesInterest ? d.apr : 0
            d.startingBalance = d.total ?? d.balance
        case .loan:
            if !hasStart { d.startDate = nil }
            if isNew { d.startingBalance = d.balance }
        }
        return d
    }

    /// Lets an existing card or loan be put on the right cycle: for example when this month's
    /// minimum was already paid before the debt was added, or a due date needs correcting.
    @ViewBuilder private var nextDuePicker: some View {
        if !isNew, let current = draft.nextUnpaidDue() {
            let nearby = (-1...2).map { Cal.date(inMonthOf: AppClock.today, monthOffset: $0, day: draft.dueDay) }
            let options = nearby.contains(current) ? nearby : (nearby + [current]).sorted()
            Picker("Next due date", selection: Binding(get: { current }, set: { date in
                // The cycle before the chosen date counts as met, and nothing is part-paid toward the new one.
                draft.paidThrough = Cal.date(inMonthOf: date, monthOffset: -1, day: draft.dueDay)
                draft.paidTowardDue = nil
                draft.interestTowardDue = nil
            })) {
                ForEach(options, id: \.self) { Text(Fmt.full($0)).tag($0) }
            }
        }
    }

    // MARK: Credit card

    @ViewBuilder private var cardFields: some View {
        Section {
            CardStrip(debt: draft)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(brand.ink)
                .background(LinearGradient(colors: [brand.top, brand.bottom], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        if draft.brand == "other" {
            Section {
                LabeledContent("Bank") {
                    TextField("Bank name", text: $draft.provider).multilineTextAlignment(.trailing)
                }
            }
        }
        Section {
            LabeledContent("Card name") {
                TextField("Optional", text: $draft.name).multilineTextAlignment(.trailing)
            }
            MoneyField(title: "Balance", value: $draft.balance)
            OptionalMoneyField(title: "Credit limit", value: $draft.creditLimit)
            PercentField(title: "APR", value: $draft.apr)
            DueDayPicker(title: "Due day", day: $draft.dueDay)
            nextDuePicker
            MoneyField(title: "Minimum payment", value: $draft.minimum)
        }
        Section {
            LabeledContent("Promo APR") {
                HStack(spacing: 2) {
                    TextField("Optional", value: $draft.promoAPR.clamped(upTo: Limits.percent), format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                    Text("%").foregroundStyle(Theme.secondary)
                }
            }
            if draft.promoAPR != nil {
                DatePicker("Promo ends", selection: Binding(get: { draft.promoEnd ?? Cal.addMonths(12, to: AppClock.today) },
                                                            set: { draft.promoEnd = $0 }), displayedComponents: .date)
            }
        } header: {
            Text("Promo APR (optional)")
        } footer: {
            Text("With a promo, APR above is the rate once the promo ends.")
        }
    }

    // MARK: Buy now, pay later

    @ViewBuilder private var payLaterFields: some View {
        Section {
            Picker("Provider", selection: $draft.brand) {
                ForEach(Brand.payLater) { Text($0.name).tag($0.id) }
                Text("Other").tag("other")
            }
            .onChange(of: draft.brand) { _, id in
                if id != "other" { draft.provider = Brand.named(id).name } else { draft.provider = "" }
            }
            if draft.brand == "other" {
                LabeledContent("Name") {
                    TextField("Provider name", text: $draft.provider).multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Purchase") {
                TextField("What you bought", text: $draft.name).multilineTextAlignment(.trailing)
            }
            MoneyField(title: "Total", value: Binding(get: { draft.total ?? 0 }, set: { draft.total = $0 }))
        }
        Section {
            Stepper(value: Binding(get: { draft.installments ?? 4 }, set: { draft.installments = $0 }), in: 2...60) {
                LabeledContent("Number of payments", value: "\(draft.installments ?? 4)")
            }
            Picker("How often", selection: Binding(get: { draft.every ?? .biweekly }, set: { draft.every = $0 })) {
                ForEach(InstallmentEvery.allCases) { Text($0.title).tag($0) }
            }
            DatePicker("Next due date", selection: Binding(get: { draft.nextDue ?? AppClock.today }, set: { draft.nextDue = $0 }),
                       displayedComponents: .date)
            Stepper(value: Binding(get: { draft.paidInstallments ?? 0 }, set: { draft.paidInstallments = $0 }),
                    in: 0...max(0, (draft.installments ?? 4) - 1)) {
                LabeledContent("Payments already made", value: "\(draft.paidInstallments ?? 0)")
            }
        }
        Section {
            Picker("Interest", selection: $chargesInterest) {
                Text("None").tag(false)
                Text("APR").tag(true)
            }
            .pickerStyle(.segmented)
            if chargesInterest {
                PercentField(title: "APR", value: $draft.apr)
            }
        } header: {
            Text("Interest")
        }
        Section {
            LabeledContent("Paid from") {
                TextField("Bank account", text: Binding(get: { draft.paidFrom ?? "" }, set: { draft.paidFrom = $0 }))
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Autopay", isOn: Binding(get: { draft.autopay ?? false }, set: { draft.autopay = $0 }))
                .toggleStyle(NeutralToggleStyle())
        }
    }

    // MARK: Loan

    @ViewBuilder private var loanFields: some View {
        Section {
            Picker("Type", selection: Binding(get: { draft.loanType ?? .other }, set: { draft.loanType = $0 })) {
                ForEach(LoanType.allCases) { Text($0.short).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        Section {
            LabeledContent("Lender") {
                TextField("Lender name", text: $draft.provider).multilineTextAlignment(.trailing)
            }
            MoneyField(title: "Balance", value: $draft.balance)
            PercentField(title: "APR", value: $draft.apr)
            MoneyField(title: "Monthly payment", value: $draft.minimum)
            DueDayPicker(title: "Due day", day: $draft.dueDay)
            nextDuePicker
            DatePicker("End date", selection: Binding(get: { draft.endDate ?? Cal.addMonths(36, to: AppClock.today) },
                                                      set: { draft.endDate = $0 }), displayedComponents: .date)
        }
        Section {
            OptionalMoneyField(title: "Original amount", value: $draft.originalAmount)
            Toggle("First payment date", isOn: $hasStart)
                .toggleStyle(NeutralToggleStyle())
            if hasStart {
                DatePicker("First payment", selection: Binding(get: { draft.startDate ?? AppClock.today }, set: { draft.startDate = $0 }),
                           displayedComponents: .date)
            }
        } header: {
            Text("Optional")
        } footer: {
            Text("These fill in the progress bar and the payment count on the loan pass.")
        }
    }
}
