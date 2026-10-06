import Foundation

/// The fictional debts from the design brief. Loaded with the `-demo` launch argument and used by the tests.
///
/// The story: tracking began on March 31, 2026. Six months of payments are on record (April to
/// September, plus the two made on October 1). Every record carries the balance it left behind, and
/// the starting balances and balance history are worked back from today's balances so every screen agrees.
enum DemoData {
    static let today = Cal.date(2026, 10, 4)

    static func make() -> AppData {
        let added = Cal.date(2026, 3, 31)
        let monthsPaid = 6

        func card(_ brand: String, _ provider: String, _ name: String, _ balance: Double, _ limit: Double,
                  _ apr: Double, _ dueDay: Int, _ minimum: Double) -> Debt {
            // Each recorded minimum came straight off the balance, so six months ago it was that much higher.
            Debt(kind: .card, provider: provider, name: name, brand: brand, balance: balance, apr: apr, dueDay: dueDay,
                 minimum: minimum, creditLimit: limit, addedAt: added, startingBalance: balance + minimum * Double(monthsPaid),
                 paidThrough: Cal.date(2026, 9, dueDay))
        }

        let chase = card("chase", "Chase", "Freedom Unlimited", 1240.50, 3000, 26.99, 9, 35)
        let capitalOne = card("capitalone", "Capital One", "Quicksilver", 2018.33, 4500, 28.49, 12, 58)
        let bofa = card("bofa", "Bank of America", "Customized Cash Rewards", 3105.72, 6000, 22.99, 22, 85)
        var citi = card("citi", "Citi", "Double Cash", 1650.00, 3500, 25.49, 9, 40)
        citi.promoAPR = 0
        citi.promoEnd = Cal.date(2027, 11, 19)
        let amex = card("amex", "American Express", "Blue Cash Everyday", 760.20, 2500, 24.49, 27, 29)
        let cards = [chase, capitalOne, bofa, citi, amex]

        let klarna = Debt(kind: .payLater, provider: "Klarna", name: "Headphones", brand: "klarna", balance: 99.98, apr: 0,
                          minimum: 49.99, total: 199.96, installments: 4, paidInstallments: 2, every: .biweekly,
                          nextDue: Cal.date(2026, 10, 15), paidFrom: "", autopay: true, addedAt: Cal.date(2026, 9, 3),
                          startingBalance: 199.96)
        let affirm = Debt(kind: .payLater, provider: "Affirm", name: "Laptop", brand: "affirm", balance: 700.00, apr: 0,
                          minimum: 175.00, total: 1050.00, installments: 6, paidInstallments: 2, every: .monthly,
                          nextDue: Cal.date(2026, 10, 20), paidFrom: "", autopay: false, addedAt: Cal.date(2026, 7, 20),
                          startingBalance: 1050.00)

        /// A loan's principal before each of its last `count` scheduled payments, oldest first, then today's.
        func principalChain(_ balance: Double, apr: Double, payment: Double, count: Int) -> [Double] {
            var chain = [balance]
            for _ in 0..<count { chain.insert((chain[0] + payment) / (1 + apr / 1200), at: 0) }
            return chain
        }
        let autoChain = principalChain(14200.00, apr: 6.90, payment: 412.00, count: 6)       // April 15 to September 15
        let studentChain = principalChain(18500.00, apr: 5.50, payment: 210.00, count: 7)    // April 1 to October 1
        let studentStart = studentChain[0].cents

        let auto = Debt(kind: .loan, provider: "", name: "", brand: "other", balance: 14200.00, apr: 6.90, dueDay: 15,
                        minimum: 412.00, loanType: .auto, endDate: Cal.date(2029, 12, 15), originalAmount: 21000.00,
                        startDate: Cal.date(2025, 1, 15), addedAt: added, startingBalance: autoChain[0].cents,
                        paidThrough: Cal.date(2026, 9, 15))
        let student = Debt(kind: .loan, provider: "Federal · Dept. of Education", name: "", brand: "other", balance: 18500.00,
                           apr: 5.50, dueDay: 1, minimum: 210.00, loanType: .student, endDate: Cal.date(2036, 3, 1),
                           originalAmount: studentStart, startDate: Cal.date(2026, 4, 1), addedAt: added,
                           startingBalance: studentStart, paidThrough: Cal.date(2026, 10, 1))

        let debts = cards + [klarna, affirm, auto, student]

        // The record of everything so far. Each entry keeps the balance it left and the state just
        // before it (the balance, and which due date or installment was next), so any of them can be undone.
        var payments: [PaymentRecord] = []
        func log(_ d: Debt, _ date: Date, _ kind: PaymentRecord.Kind, _ amount: Double, interest: Double? = nil, after: Double,
                 paidThrough: Date? = nil, installmentsPaid: Int? = nil, nextDue: Date? = nil) {
            var before: DebtState?
            if kind != .added {
                before = DebtState(balance: (after + amount - (interest ?? 0)).cents, startingBalance: d.startingBalance,
                                   paidThrough: paidThrough, paidInstallments: installmentsPaid, nextDue: nextDue)
            }
            payments.append(PaymentRecord(debtID: d.id, title: d.shortTitle, date: date, amount: amount.cents, kind: kind,
                                          interest: interest?.cents, balanceAfter: after.cents, before: before))
        }
        for c in cards {
            log(c, added, .added, c.startingBalance, after: c.startingBalance)
            for n in 1...monthsPaid {
                log(c, Cal.date(2026, 3 + n, c.dueDay), .minimum, c.minimum, after: c.startingBalance - c.minimum * Double(n),
                    paidThrough: Cal.date(2026, 2 + n, c.dueDay))
            }
        }
        log(auto, added, .added, autoChain[0], after: autoChain[0])
        for n in 1...6 {
            log(auto, Cal.date(2026, 3 + n, 15), .payment, 412.00, interest: 412.00 - (autoChain[n - 1] - autoChain[n]), after: autoChain[n],
                paidThrough: Cal.date(2026, 2 + n, 15))
        }
        log(student, added, .added, studentChain[0], after: studentChain[0])
        for n in 1...7 {
            log(student, Cal.date(2026, 3 + n, 1), .payment, 210.00, interest: 210.00 - (studentChain[n - 1] - studentChain[n]),
                after: studentChain[n], paidThrough: Cal.date(2026, 2 + n, 1))
        }
        log(affirm, Cal.date(2026, 7, 20), .added, 1050.00, after: 1050.00)
        log(affirm, Cal.date(2026, 8, 20), .installment, 175.00, after: 875.00, installmentsPaid: 0, nextDue: Cal.date(2026, 8, 20))
        log(affirm, Cal.date(2026, 9, 20), .installment, 175.00, after: 700.00, installmentsPaid: 1, nextDue: Cal.date(2026, 9, 20))
        log(klarna, Cal.date(2026, 9, 3), .added, 199.96, after: 199.96)
        log(klarna, Cal.date(2026, 9, 17), .installment, 49.99, after: 149.97, installmentsPaid: 0, nextDue: Cal.date(2026, 9, 17))
        log(klarna, Cal.date(2026, 10, 1), .installment, 49.99, after: 99.98, installmentsPaid: 1, nextDue: Cal.date(2026, 10, 1))
        payments.sort { $0.date < $1.date }

        var settings = PlanSettings(nextPayday: Cal.date(2026, 10, 9), payFrequency: .biweekly, payAmount: 1200, buffer: 50)
        settings.strategy = .custom
        // Citi is ranked by the APR it will have once its promo ends; until then it is held at the minimum.
        settings.customOrder = [chase, capitalOne, citi, amex, bofa, auto, student, klarna, affirm].map(\.id)
        settings.remindDueDates = true
        settings.remindPaydays = true
        settings.lastBackup = Cal.date(2026, 10, 1)
        settings.onboarded = true
        settings.acceptedPrivacy = Cal.date(2026, 3, 31)
        settings.acceptedDisclaimer = Cal.date(2026, 3, 31)
        settings.acceptedLegalVersion = Legal.version

        // Balance history is worked out from the records, the same way the app does it.
        let history = History.points(debts: debts, payments: payments, today: today)
        return AppData(debts: debts, payments: payments, history: history, settings: settings)
    }
}
