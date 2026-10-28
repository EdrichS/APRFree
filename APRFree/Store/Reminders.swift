import Foundation
import UserNotifications

/// Local notifications for due dates, paydays and the monthly statement check-in. Rebuilt from
/// scratch whenever data changes.
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

        if data.settings.remindPaydays {
            for event in data.settings.schedule(today: today).events(from: Day(today), count: 6) where event.gross > 0 {
                add("payday-\(event.day)", on: event.day.date, title: "It’s payday",
                    body: "Split \(event.gross.usd) with Make a Payment")
            }
        }

        if data.settings.remindCheckIn {
            for reminder in checkIns(for: data, today: today) {
                add("checkin-\(reminder.day)", on: reminder.day.date, title: "Statement check-in", body: reminder.body)
            }
        }

        // iOS keeps at most 64 pending requests per app, so the soonest ones go in first.
        for entry in requests.sorted(by: { $0.fire < $1.fire }).prefix(60) { center.add(entry.request) }
    }

    /// The monthly statement check-in reminders for this month and the two after it, on the chosen
    /// day. This month's is left out once every card has been checked in; later months ask about
    /// every card that still has a balance. A card its bank keeps up to date is never asked about.
    static func checkIns(for data: AppData, today: Date) -> [(day: Day, body: String)] {
        let month = Day(today).monthIndex
        var out: [(day: Day, body: String)] = []
        for offset in 0..<3 {
            let waiting = offset == 0 ? data.awaitingCheckIn(today: today) : data.checkInCards
            guard !waiting.isEmpty else { continue }
            let body = waiting.count == 1
                ? "Enter what this month’s \(waiting[0].title) statement says, so its interest is counted."
                : "Enter what this month’s statements say for \(Fmt.plural(waiting.count, "card")), so their interest is counted."
            out.append((Day.inMonth(month + offset, day: data.settings.checkInDay), body))
        }
        return out
    }

    /// Clears reminders already showing in Notification Center, for when everything is erased.
    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
