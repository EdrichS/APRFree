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
                Picker("Schedule", selection: bind(\.payFrequency)) {
                    ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                }
                // Picking a date also records which day of the month monthly pay lands on.
                DatePicker("Next payday", selection: Binding(get: { store.settings.nextPayday },
                                                             set: { date in store.updateSettings { $0.setNextPayday(date) } }),
                           in: store.today..., displayedComponents: .date)
                MoneyField(title: "Usual amount", value: bind(\.payAmount))
            } header: {
                Text("Payday")
            } footer: {
                Text("Next paydays: \(store.upcomingPaydays().map(Fmt.weekday).joined(separator: " · "))")
            }
            Section("Plan") {
                MoneyField(title: "Safety buffer", value: bind(\.buffer))
                NavigationLink {
                    StrategyContent()
                        .navigationTitle("Strategy")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Strategy", value: store.settings.strategy.title)
                }
            }
            Section {
                Toggle("Due dates", isOn: reminder(\.remindDueDates))
                Toggle("Paydays", isOn: reminder(\.remindPaydays))
            } header: {
                Text("Reminders")
            } footer: {
                if denied {
                    Text("Notifications are turned off for APRFree. Turn them on in the Settings app first.")
                }
            }
            .toggleStyle(NeutralToggleStyle())
            Section("Backup") {
                NavigationLink {
                    ExportContent()
                        .navigationTitle("Export")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Backup and restore", value: store.settings.lastBackup.map(Fmt.monthDay) ?? "Never")
                }
            }
            Section {
                Button("Reset Everything", role: .destructive) { confirmingReset = true }
            } footer: {
                VStack(spacing: 12) {
                    Text("Erases every debt, payment and setting on this iPhone and starts setup again.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Everything stays on your iPhone.")
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

    private func bind<T>(_ keyPath: WritableKeyPath<PlanSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { value in store.updateSettings { $0[keyPath: keyPath] = value } })
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
