import Foundation
import UserNotifications

/// Local notifications for due dates and paydays. Rebuilt from scratch whenever data changes.
enum Reminders {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(for data: AppData, today: Date) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        var requests: [(fire: Date, request: UNNotificationRequest)] = []

        func add(_ id: String, on day: Date, title: String, body: String) {
            var parts = Cal.calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = 9
            guard let fire = Cal.calendar.date(from: parts), fire > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            requests.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
        }

        if data.settings.remindDueDates {
            for debt in data.debts where !debt.isPaidOff {
                var dues: [Date] = []
                if debt.kind == .payLater {
                    dues = Array(debt.remainingInstallmentDates.prefix(2))
                } else if let first = debt.nextUnpaidDue() {
                    dues = [first, Cal.nextDue(day: debt.dueDay, onOrAfter: Cal.addDays(1, to: first))]
                }
                for (index, due) in dues.enumerated() {
                    // Only the first due date can be part-paid already; the ones after it ask for the full amount.
                    let amount = index == 0 ? debt.scheduledPayment(on: today) : min(debt.minimum, debt.balance)
                    guard amount > 0 else { continue }
                    add("due-\(debt.id)-\(Int(due.timeIntervalSince1970))", on: Cal.addDays(-1, to: due),
                        title: "\(debt.title) is due tomorrow",
                        body: "\(amount.usd) \(debt.paymentWord.lowercased()), due \(Fmt.monthDay(due))")
                }
            }
        }

        if data.settings.remindPaydays, data.settings.payAmount > 0 {
            let paydays = data.settings.paydays(from: today)
            for i in 0..<4 {
                let day = paydays.date(i)
                add("payday-\(Int(day.timeIntervalSince1970))", on: day, title: "It’s payday",
                    body: "Split \(data.settings.payAmount.usd) with Make a Payment")
            }
        }

        // iOS keeps at most 64 pending requests per app, so the soonest ones go in first.
        for entry in requests.sorted(by: { $0.fire < $1.fire }).prefix(60) { center.add(entry.request) }
    }

    /// Clears reminders already showing in Notification Center, for when everything is erased.
    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
