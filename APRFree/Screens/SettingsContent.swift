import SwiftUI

struct SettingsContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false
    @State private var confirmingReset = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    IncomeContent()
                        .navigationTitle("Income")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Income", value: store.settings.useFixedAmount ? "Fixed amount" : Fmt.plural(store.settings.incomes.count, "income"))
                }
                MoneyField(title: "Safety buffer", value: bind(\.buffer))
                NavigationLink {
                    StrategyContent()
                        .navigationTitle("Strategy")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Strategy", value: store.settings.strategy.title)
                }
            } header: {
                Text("Plan")
            } footer: {
                Text("The safety buffer is held back out of every paycheck. Paydays and amounts are under Income.")
            }
            Section {
                Toggle("Due dates", isOn: reminder(\.remindDueDates))
                Toggle("Paydays", isOn: reminder(\.remindPaydays))
                Toggle("Statement check-in", isOn: reminder(\.remindCheckIn))
                if store.settings.remindCheckIn {
                    Picker("Each month on the", selection: Binding(get: { store.settings.checkInDay },
                                                                    set: { day in store.updateSettings { $0.checkInDay = day } })) {
                        ForEach(1...31, id: \.self) { Text($0 == 31 ? "31st or last day" : Fmt.ordinal($0)).tag($0) }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if denied {
                    Text("Notifications are turned off for APRFree. Turn them on in the Settings app first.")
                } else if store.settings.remindCheckIn {
                    Text("The check-in reminder arrives at 9:00 on that day. It is skipped in a month where every card has already been checked in.")
                }
            }
            .toggleStyle(NeutralToggleStyle())
            if store.connectedAvailable {
                Section {
                    NavigationLink {
                        ConnectedContent()
                            .navigationTitle("Connected")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Connected mode", value: connectedSummary)
                    }
                } header: {
                    Text("Connected")
                } footer: {
                    Text("Optional, and off unless you turn it on. Lets a bank fill in balances and terms. It never moves money.")
                }
            }
            Section("Backup") {
                NavigationLink {
                    ExportContent()
                        .navigationTitle("Export")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Backup and restore", value: store.settings.lastBackup.map(Fmt.monthDay) ?? "Never")
                }
            }
            Section("About") {
                HStack(spacing: 12) {
                    LogoMark(size: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("APRFree").font(.headline)
                        Text(version).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                NavigationLink("Privacy Policy") { LegalReader(document: Legal.privacy) }
                NavigationLink("Disclaimer") { LegalReader(document: Legal.disclaimer) }
            }
            Section {
                Button("Reset Everything", role: .destructive) { confirmingReset = true }
            } footer: {
                VStack(spacing: 12) {
                    Text("Erases every debt, payment and setting on this iPhone and starts setup again.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(store.connected.isOn ? "Everything you enter stays on your iPhone. Connected mode is on." : "Everything stays on your iPhone.")
                        .frame(maxWidth: .infinity)
                    Text("APRFree is a planning tool, not financial advice. Payoff dates and interest are estimates worked out from the numbers you enter. It is not affiliated with or endorsed by any bank or lender whose name appears in it.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .focused($focused)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .alert("Reset everything?", isPresented: $confirmingReset) {
            Button("Reset Everything", role: .destructive) {
                dismiss()
                store.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All debts, payments, history and settings will be erased. This cannot be undone. Back up first if you want to keep a copy.")
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let number = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(number)" : "Version \(number) (\(build))"
    }

    private var connectedSummary: String {
        guard store.connected.isOn else { return "Off" }
        let live = store.connected.connections.filter { $0.status != .disconnected }.count
        return live == 0 ? "On" : "On · \(Fmt.plural(live, "bank"))"
    }

    private func bind<T>(_ keyPath: WritableKeyPath<PlanSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { value in store.updateSettings("Change safety buffer", merging: true) { $0[keyPath: keyPath] = value } })
    }

    /// Turning a reminder on asks for notification permission, and turns it back off if that is refused.
    private func reminder(_ keyPath: WritableKeyPath<PlanSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { on in
            store.updateSettings { $0[keyPath: keyPath] = on }
            guard on else { return }
            Task { @MainActor in
                if await Reminders.requestAuthorization() {
                    denied = false
                    store.updateSettings { _ in }   // reschedule now that permission exists
                } else {
                    denied = true
                    store.updateSettings { $0[keyPath: keyPath] = false }
                }
            }
        })
    }
}
