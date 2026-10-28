import Foundation
import SwiftUI
import Testing
import UIKit
@testable import APRFree

/// Checks the payoff math three ways: against the numbers in the design brief, against an
/// independent model of the same rules (the expected figures below come from it), and against
/// the closed-form loan schedule.
@Suite(.serialized)
struct EngineTests {
    let today = DemoData.today
    let demo = DemoData.make()

    init() {
        AppClock.override = DemoData.today
    }

    private func debt(_ name: String, in data: AppData? = nil) throws -> Debt {
        try #require((data ?? demo).debts.first { $0.title == name })
    }

    private func plan(_ strategy: Strategy, oneTime: Double = 0, extraMonthly: Double = 0) -> PlanResult {
        PayoffEngine.simulate(PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday,
                                        frequency: .biweekly, perPayday: 1150, strategy: strategy,
                                        customOrder: demo.settings.customOrder, promoMinimumOnly: true,
                                        oneTime: oneTime, extraMonthly: extraMonthly))
    }

    // MARK: The brief

    @Test func totalsMatchTheBrief() {
        let store = AppStore(data: demo, persists: false)
        #expect(store.total.cents == 42274.73)
        #expect(store.total(of: .card).cents == 8774.75)
        #expect(store.total(of: .payLater).cents == 799.98)
        #expect(store.total(of: .loan).cents == 32700.00)
        #expect(store.dailyCost.cents == 10.43)
        #expect(store.monthlyCost.cents == 317.28)
        #expect(store.perPayday == 1150)
    }

    @Test func splitMatchesTheBrief() {
        let split = PayoffEngine.split(amount: 1200, debts: demo.debts, settings: demo.settings, today: today)
        let lines = split.lines.map { "\($0.title) \($0.amount.usd)\($0.isExtra ? " extra" : "")" }
        #expect(lines == ["Chase $35.00", "Citi $40.00", "Capital One $58.00", "Klarna $49.99", "Auto loan $412.00",
                          "Affirm $175.00", "Bank of America $85.00", "Chase $295.01 extra"])
        #expect(split.total == 1150.00)
        #expect(split.bufferKept == 50)
        #expect(split.shortBy == 0)
        #expect(split.summary == "Chase drops to $910.49.")
        #expect(Fmt.weekday(split.payday) == "Fri, Oct 9")
        #expect(Fmt.monthDay(split.nextPayday) == "Oct 23")
    }

    @Test func splitFallsShortGracefully() {
        let split = PayoffEngine.split(amount: 200, debts: demo.debts, settings: demo.settings, today: today)
        #expect(split.total == 150.00)
        #expect(split.shortBy == 704.99)
        #expect(split.lines.allSatisfy { !$0.isExtra })
    }

    // MARK: The plan, against the independent model

    @Test func planMatchesTheIndependentModel() throws {
        let avalanche = plan(.avalanche), snowball = plan(.snowball), custom = plan(.custom)
        #expect(avalanche.totalInterest.cents == 2018.62)
        #expect(snowball.totalInterest.cents == 2025.76)
        #expect(custom.totalInterest.cents == 2020.89)
        for result in [avalanche, snowball, custom] {
            #expect(result.finished)
            #expect(result.debtFree == Cal.date(2028, 4, 1))
            #expect(result.finalPayday == Cal.date(2028, 3, 24))
        }
        // Brief: Chase is gone in November 2026 and everything by April 2028.
        let chase = try debt("Chase")
        #expect(Fmt.monthYear(try #require(custom.payoff[chase.id])) == "Nov 2026")
        #expect(custom.paydaysToPayoff[chase.id] == 3)
        #expect(Cal.months(from: today, to: try #require(custom.debtFree)) == 18)

        let expected: [String: Date] = [
            "Klarna": Cal.date(2026, 10, 23), "Chase": Cal.date(2026, 11, 6), "Capital One": Cal.date(2026, 12, 18),
            "American Express": Cal.date(2026, 12, 18), "Affirm": Cal.date(2027, 1, 15), "Bank of America": Cal.date(2027, 2, 12),
            "Auto loan": Cal.date(2027, 8, 13), "Citi": Cal.date(2027, 12, 3), "Student loan": Cal.date(2028, 3, 24),
        ]
        for (name, payday) in expected {
            #expect(custom.payoffPayday[try debt(name).id] == payday, "\(name)")
        }
        #expect(avalanche.payoffPayday[try debt("Capital One").id] == Cal.date(2026, 11, 20))
        #expect(snowball.payoffPayday[try debt("American Express").id] == Cal.date(2026, 10, 23))
    }

    @Test func theStrategiesRankAsTheySay() throws {
        let debts = demo.debts.filter { $0.kind != .payLater }
        func order(_ strategy: Strategy) -> [String] {
            PayoffEngine.priority(debts, strategy: strategy, customOrder: demo.settings.customOrder, on: today).map(\.title)
        }
        // Avalanche: by rate. Citi's promo makes it 0% today.
        #expect(order(.avalanche) == ["Capital One", "Chase", "American Express", "Bank of America", "Auto loan", "Student loan", "Citi"])
        // Snowball: by balance, smallest first.
        #expect(order(.snowball) == ["American Express", "Chase", "Citi", "Capital One", "Bank of America", "Auto loan", "Student loan"])
        #expect(order(.custom) == ["Chase", "Capital One", "Citi", "American Express", "Bank of America", "Auto loan", "Student loan"])
        #expect(Strategy.allCases.map(\.title) == ["Avalanche", "Snowball", "Custom"])

        // A big balance at 20% against a small one at 30%: Avalanche goes by the rate, not the size.
        let big = Debt(kind: .card, provider: "Big", name: "", brand: "other", balance: 10000, apr: 20, minimum: 200, addedAt: today, startingBalance: 10000)
        let small = Debt(kind: .card, provider: "Small", name: "", brand: "other", balance: 500, apr: 30, minimum: 25, addedAt: today, startingBalance: 500)
        #expect(PayoffEngine.priority([big, small], strategy: .avalanche, customOrder: [], on: today).map(\.provider) == ["Small", "Big"])

        // The first extra dollars follow the strategy.
        func firstExtra(_ strategy: Strategy) -> String? {
            var settings = demo.settings
            settings.strategy = strategy
            return PayoffEngine.split(amount: 1200, debts: demo.debts, settings: settings, today: today).lines.first(where: \.isExtra)?.title
        }
        #expect(Strategy.allCases.map(firstExtra) == ["Capital One", "American Express", "Chase"])

        // "Highest Balance" was a fourth strategy once. Settings saved with it open as Avalanche.
        #expect(try JSONDecoder().decode([Strategy].self, from: Data(#"["highestBalance","snowball","custom","avalanche"]"#.utf8))
                == [.avalanche, .snowball, .custom, .avalanche])
    }

    @Test func anExtraDollarSavesAtTheRateOfTheDebtItLandsOn() throws {
        // Why highest rate first costs the least. Two cards, $100 extra for one month:
        // on the 20% card it saves $1.67 of interest, on the 30% card $2.50, whatever their sizes.
        let big = Debt(kind: .card, provider: "Big", name: "", brand: "other", balance: 10000, apr: 20, dueDay: 9, minimum: 200,
                       addedAt: today, startingBalance: 10000)
        let small = Debt(kind: .card, provider: "Small", name: "", brand: "other", balance: 500, apr: 30, dueDay: 9, minimum: 25,
                         addedAt: today, startingBalance: 500)
        #expect((big.monthlyInterest(on: today) - (big.balance - 100) * 20 / 1200).cents == 1.67)
        #expect((small.monthlyInterest(on: today) - (small.balance - 100) * 30 / 1200).cents == 2.50)
        // And over a whole payoff: the same $600.00 a month, two orders.
        func cost(_ strategy: Strategy, _ order: [UUID] = []) -> PlanResult {
            PayoffEngine.simulate(PlanInput(debts: [big, small], today: today, firstPayday: Cal.date(2026, 10, 9), frequency: .monthly,
                                            perPayday: 600, strategy: strategy, customOrder: order, promoMinimumOnly: true))
        }
        // By rate, against the big balance first (the one charging more dollars of interest a month).
        let byRate = cost(.avalanche), byDollars = cost(.custom, [big.id, small.id])
        #expect(byRate.finished && byDollars.finished)
        #expect(byRate.totalInterest < byDollars.totalInterest)
        #expect(byRate.debtFree! <= byDollars.debtFree!)
    }

    @Test func noOrderOfTheseDebtsBeatsAvalanche() throws {
        // Every one of the 720 ways to order the six interest-bearing debts, each run as a full plan.
        // (The independent model tried all 5,040 orders including Citi and found the same.)
        let names = ["Chase", "Capital One", "Bank of America", "American Express", "Auto loan", "Student loan"]
        let ids = try names.map { try debt($0).id }
        let rest = try ["Citi", "Klarna", "Affirm"].map { try debt($0).id }
        func permutations(_ items: [UUID]) -> [[UUID]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[UUID]] in
                var others = items
                let head = others.remove(at: i)
                return permutations(others).map { [head] + $0 }
            }
        }
        let best = plan(.avalanche).totalInterest
        var cheaper = 0, dearest = 0.0
        for order in permutations(ids) {
            let result = PayoffEngine.simulate(PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday,
                                                         frequency: .biweekly, perPayday: 1150, strategy: .custom,
                                                         customOrder: order + rest, promoMinimumOnly: true))
            if result.totalInterest < best - 0.005 { cheaper += 1 }
            dearest = max(dearest, result.totalInterest)
        }
        #expect(cheaper == 0)
        #expect(dearest > best + 1000)                          // and the order matters: the worst one costs far more
        #expect(plan(.avalanche).totalInterest <= plan(.snowball).totalInterest)
    }

    @Test func payingMoreFinishesSooner() throws {
        let base = plan(.custom), more = plan(.custom, oneTime: 1000, extraMonthly: 400)
        #expect((base.totalInterest - more.totalInterest).cents == 478.47)
        #expect(more.debtFree == Cal.date(2028, 1, 1))
        #expect(Cal.months(from: try #require(more.debtFree), to: try #require(base.debtFree)) == 3)
    }

    @Test func tooLittleNeverFinishes() {
        let result = PayoffEngine.simulate(PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday,
                                                     frequency: .monthly, perPayday: 100, strategy: .avalanche,
                                                     customOrder: [], promoMinimumOnly: true))
        #expect(!result.finished)
        #expect(result.debtFree == nil)
    }

    @Test func everyDollarIsAccountedFor() {
        // What goes in over the whole plan equals the starting balances plus every cent of interest.
        let result = plan(.custom)
        let paid = demo.debts.reduce(0.0) { sum, debt in sum + result.slices(for: debt.id).reduce(0) { $0 + $1.total } }
        let accruedOnLoans = 14200 * 6.9 / 36500 * 19 + 18500 * 5.5 / 36500 * 3   // owed since the last loan payments
        #expect(abs(paid - (42274.73 + result.totalInterest + accruedOnLoans)) < 0.05)
        // The plan's balances start where the debts are and end at zero, and the parts never exceed the whole.
        #expect(result.series.first?.total.cents == 42274.73)
        #expect(result.series.first?.cards.cents == 8774.75)
        #expect(result.series.first?.loans.cents == 32700.00)
        #expect(result.series.last?.total == 0)
        #expect(result.series.allSatisfy { $0.cards + $0.loans <= $0.total + 0.01 && $0.total >= 0 })
        // It only ever goes down: $1,150.00 a payday is far more than the interest.
        #expect(zip(result.series, result.series.dropFirst()).allSatisfy { $1.total < $0.total })
    }

    @Test func balancesCanBeReadOffThePlanOnAnyDate() {
        // What the Simulator shows under a held finger: a straight line between the paydays either side.
        let base = plan(.custom).series, more = plan(.custom, extraMonthly: 750).series
        #expect(base.balance(at: today).cents == 42274.73)
        #expect(base.balance(at: Cal.date(2026, 10, 9)).cents == 41213.98)
        #expect(base.balance(at: Cal.date(2027, 1, 1)).cents == 34986.13)
        #expect(more.balance(at: Cal.date(2027, 1, 1)).cents == 31966.34)
        #expect(base.balance(at: Cal.date(2030, 1, 1)) == 0)
        #expect(base.balance(at: Cal.date(2020, 1, 1)).cents == 42274.73)
        #expect(base.balance(at: Cal.date(2027, 1, 1), .cards) + base.balance(at: Cal.date(2027, 1, 1), .loans)
                <= base.balance(at: Cal.date(2027, 1, 1)) + 0.01)
    }

    @Test func aLoansProjectedInterestIsItsDailyCostAddedUpToPayoff() throws {
        let store = AppStore(data: demo, persists: false)
        let auto = try debt("Auto loan"), student = try debt("Student loan")
        // On the plan: $51.00 already accrued since September 15, plus every day from here to August 2027.
        #expect(try #require(store.projectedInterest(for: auto)).cents == 602.04)
        #expect(try #require(store.projectedInterest(for: student)).cents == 1142.44)
        // Paying only the scheduled $412.00 it would be the full amortization interest.
        #expect(try #require(PayoffEngine.amortize(balance: 14200, apr: 6.9, payment: 412)).interest.cents == 1671.61)
        // Nothing to project when the plan never clears the loan.
        store.updateSettings { $0.payAmount = 0 }
        #expect(store.projectedInterest(for: auto) == nil)
    }

    @Test func theBreakdownAddsUpToTheTotal() throws {
        let store = AppStore(data: demo, persists: false)
        #expect(abs(store.active.reduce(0) { $0 + store.share(of: $1) } - 1) < 0.000001)
        #expect(abs(store.active.reduce(0) { $0 + $1.dailyCost(on: today) } - store.dailyCost) < 0.000001)
        #expect((store.share(of: try debt("Student loan")) * 1000).rounded() / 10 == 43.8)
        #expect((store.share(of: try debt("Chase")) * 1000).rounded() / 10 == 2.9)
        #expect((store.dailyCost * 365).cents == 3807.31)   // each balance times its APR
    }

    @Test func aCardsTotalCostFollowsTheStrategy() throws {
        let chase = try debt("Chase"), citi = try debt("Citi"), bofa = try debt("Bank of America")
        // Interest still to come on the plan, strategy by strategy (independent model: 50.61, 27.35, 14.77).
        var expected: [Strategy: Double] = [.avalanche: 50.61, .snowball: 27.35, .custom: 14.77]
        for strategy in Strategy.allCases {
            var data = demo
            data.settings.strategy = strategy
            let store = AppStore(data: data, persists: false)
            #expect(try #require(store.projectedInterest(for: chase)).cents == expected[strategy], "\(strategy.title)")
            // Month by month it adds up to the same total.
            #expect(abs(store.plan.interestByMonth(for: chase.id).reduce(0) { $0 + $1.total } - (expected[strategy] ?? 0)) < 0.01)
        }
        expected = [:]
        let store = AppStore(data: demo, persists: false)
        #expect(store.plan.interestByMonth(for: chase.id).map { $0.total.cents } == [14.54, 0.24])
        #expect(store.plan.interestByMonth(for: chase.id).map(\.date) == [Cal.date(2026, 10, 1), Cal.date(2026, 11, 1)])
        #expect(try #require(store.projectedInterest(for: bofa)).cents == 206.76)
        #expect(try #require(store.projectedInterest(for: citi)).cents == 1.47)

        // Minimum only, from the next due date: Chase takes 72 months and $1,270.02.
        let minimum = try #require(PayoffEngine.fixedPayoff(debt: chase, payment: 35, from: Cal.date(2026, 10, 9)))
        #expect(minimum.months == 72)
        #expect(minimum.interest.cents == 1270.02)
        #expect(Cal.addMonths(minimum.months - 1, to: Cal.date(2026, 10, 9)) == Cal.date(2032, 9, 9))
        // Citi is free until its promo ends, then 25.49% on what is left.
        let promo = try #require(PayoffEngine.fixedPayoff(debt: citi, payment: 40, from: Cal.date(2026, 10, 9)))
        #expect(promo.months == 56)
        #expect(promo.interest.cents == 555.65)
        let bank = try #require(PayoffEngine.fixedPayoff(debt: bofa, payment: 85, from: Cal.date(2026, 10, 22)))
        #expect(bank.months == 64)
        #expect(bank.interest.cents == 2287.24)
        // A minimum below the month's interest never clears the card.
        #expect(PayoffEngine.fixedPayoff(debt: chase, payment: 20, from: today) == nil)

        // Interest already paid: each recorded minimum against the balance it was paid on; exact for loans.
        #expect(PayoffEngine.interestPaid(debt: chase, payments: demo.payments).cents == 183.94)
        #expect(PayoffEngine.interestPaid(debt: citi, payments: demo.payments) == 0)
        #expect(PayoffEngine.interestPaid(debt: try debt("Auto loan"), payments: demo.payments).cents == 529.19)
    }

    // MARK: Loans

    @Test func loanAmortization() throws {
        let regular = try #require(PayoffEngine.amortize(balance: 14200, apr: 6.9, payment: 412))
        let extra = try #require(PayoffEngine.amortize(balance: 14200, apr: 6.9, payment: 462))
        let custom = try #require(PayoffEngine.amortize(balance: 14200, apr: 6.9, payment: 412 + 1250))
        #expect(regular.months == 39)
        #expect(extra.months == 34)
        #expect((regular.interest - extra.interest).cents == 201.15)
        #expect(custom.months == 9)
        #expect(custom.interest.cents == 403.29)
        #expect(PayoffEngine.amortize(balance: 10000, apr: 30, payment: 100) == nil)
    }

    @Test func dailyInterestAgreesWithTheMonthlySchedule() throws {
        // One loan paid only its scheduled amount: the day-by-day simulation and the monthly
        // schedule must land on the same last payment and the same interest.
        let auto = try debt("Auto loan")
        let result = PayoffEngine.simulate(PlanInput(debts: [auto], today: today, firstPayday: Cal.date(2026, 10, 15),
                                                     frequency: .monthly, perPayday: 412, strategy: .avalanche,
                                                     customOrder: [], promoMinimumOnly: true))
        let schedule = try #require(PayoffEngine.amortize(balance: 14200, apr: 6.9, payment: 412))
        #expect(result.paydaysToPayoff[auto.id] == schedule.months)
        #expect(result.payoffPayday[auto.id] == Cal.date(2029, 12, 15))
        let accruedBeforeToday = 14200 * 6.9 / 36500 * 19
        #expect(abs(result.totalInterest + accruedBeforeToday - schedule.interest) < 1)
    }

    @Test func pastPaymentsSplitIntoInterestAndPrincipal() throws {
        // September's car payment: $412.00 against $14,528.46, so $83.54 interest and $328.46 principal.
        let auto = try debt("Auto loan"), chase = try debt("Chase"), citi = try debt("Citi")
        let september = try #require(PayoffEngine.pastSlices(debt: auto, payments: demo.payments, today: today).last)
        #expect(september.month == Cal.date(2026, 9, 1))
        #expect(september.interest.cents == 83.54)
        #expect(september.principal.cents == 328.46)
        // A card minimum: the month's interest on the $1,275.50 it was paid against.
        let chaseSeptember = try #require(PayoffEngine.pastSlices(debt: chase, payments: demo.payments, today: today).last)
        #expect(chaseSeptember.interest.cents == 28.69)
        #expect(chaseSeptember.total == 35)
        // At 0% every dollar is principal, and looking forward the minimum-only schedule says the same.
        #expect(PayoffEngine.pastSlices(debt: citi, payments: demo.payments, today: today).allSatisfy { $0.interest == 0 && $0.principal == 40 })
        let next = try #require(PayoffEngine.fixedSchedule(debt: chase, payment: 35, from: today).first)
        #expect(next.interest.cents == 27.90)
        #expect(next.principal.cents == 7.10)
        #expect(PayoffEngine.fixedSchedule(debt: citi, payment: 40, from: today).allSatisfy { $0.interest == 0 })
    }

    @Test func aLoansLastPaymentIncludesItsInterest() throws {
        var loan = Debt(kind: .loan, provider: "Lender", name: "", brand: "other", balance: 300, apr: 6, dueDay: 15,
                        minimum: 412, loanType: .personal, addedAt: today, startingBalance: 300)
        #expect(loan.scheduledPayment(on: today) == 301.50)
        let store = AppStore(data: AppData(debts: [loan], settings: PlanSettings(nextPayday: today)), persists: false)
        store.pay(loan.id, amount: 412)
        #expect(store.debt(loan.id)?.balance == 0)
        #expect(store.data.payments.last?.amount == 301.50)
        #expect(store.data.payments.last?.interest == 1.50)
        #expect(store.celebration?.id == loan.id)
        loan.balance = 14200
        loan.apr = 6.9
        #expect(loan.monthlyInterest(on: today).cents == 81.65)
        #expect(loan.dailyCost(on: today).cents == 2.68)
    }

    @Test func splitAndStoreAgreeWhenALoanGetsTheExtra() throws {
        var data = demo
        let auto = try debt("Auto loan")
        data.settings.customOrder = [auto.id] + data.settings.customOrder.filter { $0 != auto.id }
        let split = PayoffEngine.split(amount: 1200, debts: data.debts, settings: data.settings, today: today)
        #expect(split.total == 1150.00)
        #expect(split.lines.last?.title == "Auto loan")
        // $412.00 scheduled: $81.65 interest, $330.35 principal. Then $295.01 extra straight onto principal.
        #expect(split.summary == "Auto loan drops to $13,574.64.")
        let store = AppStore(data: data, persists: false)
        store.apply(split, paid: Set(split.lines.map(\.id)))
        #expect(store.debt(auto.id)?.balance == 13574.64)
        #expect(store.settings.nextPayday == Cal.date(2026, 10, 23))
        // Everything else fell by exactly what was paid to it.
        #expect(store.total.cents == (42274.73 - 1150 + 81.65).cents)
    }

    // MARK: Pay later

    @Test func unevenInstallmentsClearToTheCent() throws {
        // $100.00 in three: $33.33, $33.33, then $33.34.
        let plan3 = Debt(kind: .payLater, provider: "Klarna", name: "Lamp", brand: "klarna", balance: 100, apr: 0, minimum: 33.33,
                         total: 100, installments: 3, paidInstallments: 0, every: .biweekly, nextDue: Cal.date(2026, 10, 10),
                         addedAt: today, startingBalance: 100)
        let store = AppStore(data: AppData(debts: [plan3], settings: PlanSettings(nextPayday: Cal.date(2026, 10, 9), payAmount: 500)),
                             persists: false)
        var paid: [Double] = []
        for _ in 0..<3 {
            let now = try #require(store.debt(plan3.id))
            let amount = now.scheduledPayment(on: today)
            paid.append(amount)
            store.pay(plan3.id, amount: amount)
        }
        #expect(paid == [33.33, 33.33, 33.34])
        #expect(store.debt(plan3.id)?.balance == 0)
        #expect(store.debt(plan3.id)?.paidInstallments == 3)

        // The simulation clears it on the payday that covers the last installment, not one cent later.
        let result = PayoffEngine.simulate(PlanInput(debts: [plan3], today: today, firstPayday: Cal.date(2026, 10, 9),
                                                     frequency: .biweekly, perPayday: 33.34, strategy: .avalanche,
                                                     customOrder: [], promoMinimumOnly: true))
        #expect(result.finished)
        #expect(result.paydaysToPayoff[plan3.id] == 3)
        #expect(result.debtFree == Cal.date(2026, 11, 7))
    }

    // MARK: Total, credit cards, loans

    @Test func scopesAddUp() throws {
        let store = AppStore(data: demo, persists: false)
        #expect(store.balance(in: .total) == store.total)
        #expect((store.balance(in: .cards) + store.balance(in: .loans) + store.total(of: .payLater)).cents == 42274.73)

        // Six months of recorded payments, worked back into the starting balances.
        #expect(store.startTotal(in: .cards).cents == 10256.75)
        #expect(store.paidSoFar(in: .cards).cents == 1482.00)
        #expect(store.startTotal(in: .loans).cents == 40360.61)
        #expect(store.paidSoFar(in: .loans).cents == 7660.61)
        #expect(store.startTotal(in: .total).cents == 51867.32)
        #expect(store.paidSoFar(in: .total).cents == 9592.59)
        #expect([DebtScope.total, .cards, .loans].map { Int((store.fractionPaid(in: $0) * 100).rounded()) } == [18, 14, 19])

        #expect(Fmt.monthYear(try #require(store.free(in: .total))) == "Apr 2028")
        #expect(Fmt.monthYear(try #require(store.free(in: .cards))) == "Dec 2027")
        #expect(Fmt.monthYear(try #require(store.free(in: .loans))) == "Apr 2028")

        // October so far: a Klarna installment and the student loan's principal.
        #expect(store.changeThisMonth(in: .total).cents == -174.63)
        #expect(store.changeThisMonth(in: .cards).cents == 0)
        #expect(store.changeThisMonth(in: .loans).cents == -124.64)
        // September, from the recorded history: $924.52 of principal paid, less the $199.96 Klarna purchase made on the 3rd.
        let september = try #require(store.balance(in: .total, before: Cal.date(2026, 9, 1)))
        let october = try #require(store.balance(in: .total, before: Cal.date(2026, 10, 1)))
        #expect((september - october).cents == 724.56)

        // History and plan line up at today for every scope.
        for scope in DebtScope.allCases {
            #expect(store.data.history.last?.value(scope) == store.balance(in: scope).cents)
            #expect(store.plan.series.first?.value(scope).cents == store.balance(in: scope).cents)
        }
    }

    @Test func widgetsFollowEachScope() {
        let snapshot = AppStore(data: demo, persists: false).widgetSnapshot
        #expect(snapshot.total.balance.cents == 42274.73)
        #expect(snapshot.cards.balance.cents == 8774.75)
        #expect(snapshot.loans.balance.cents == 32700.00)
        #expect(snapshot.total.nextDue == Day(2026, 10, 9))
        #expect(snapshot.total.nextDueNames == "Chase, Citi")
        #expect(snapshot.cards.nextDueNames == "Chase, Citi")
        #expect(snapshot.loans.nextDue == Day(2026, 10, 15))
        #expect(snapshot.loans.nextDueNames == "Auto loan")
        #expect(snapshot.cards.free == Day(2027, 12, 9))
        #expect(snapshot.loans.free == Day(2028, 4, 1))
        #expect(snapshot.scope(.loans) == snapshot.loans)
    }

    // MARK: Dates and paydays

    @Test func dueDatesClampToShortMonths() {
        #expect(Cal.nextDue(day: 31, onOrAfter: Cal.date(2027, 2, 1)) == Cal.date(2027, 2, 28))
        #expect(Cal.nextDue(day: 9, onOrAfter: Cal.date(2026, 10, 10)) == Cal.date(2026, 11, 9))
        #expect(Cal.nextDue(day: 9, onOrAfter: Cal.date(2026, 10, 9)) == Cal.date(2026, 10, 9))
        #expect(Cal.nextDue(day: 15, onOrAfter: Cal.date(2026, 12, 20)) == Cal.date(2027, 1, 15))
        #expect(Cal.months(from: Cal.date(2026, 10, 4), to: Cal.date(2028, 4, 1)) == 18)
        #expect(Cal.days(from: Cal.date(2026, 10, 4), to: Cal.date(2026, 10, 9)) == 5)
        // A day count across the autumn clock change is still whole days.
        #expect(Cal.days(from: Cal.date(2026, 10, 30), to: Cal.date(2026, 11, 3)) == 4)
    }

    @Test func paydaysKeepTheirWeekdayOrTheirDayOfTheMonth() {
        // Friday, October 9, 2026.
        let friday = Cal.date(2026, 10, 9)
        func weekday(_ date: Date) -> Int { Cal.calendar.component(.weekday, from: date) }
        #expect(weekday(friday) == 6)

        // Weekly and every two weeks: always the same weekday, across month ends, year ends and both clock changes.
        let weekly = PaydaySequence(first: friday, frequency: .weekly)
        let biweekly = PaydaySequence(first: friday, frequency: .biweekly)
        #expect((0..<60).allSatisfy { weekday(weekly.date($0)) == 6 })
        #expect((0..<60).allSatisfy { weekday(biweekly.date($0)) == 6 })
        #expect((0..<4).map(weekly.date) == [friday, Cal.date(2026, 10, 16), Cal.date(2026, 10, 23), Cal.date(2026, 10, 30)])
        #expect((0..<4).map(biweekly.date) == [friday, Cal.date(2026, 10, 23), Cal.date(2026, 11, 6), Cal.date(2026, 11, 20)])
        #expect(biweekly.date(26) == Cal.date(2027, 10, 8))           // 52 weeks on, still a Friday
        #expect((0..<26).filter(biweekly.isFirstInMonth).count == 12)
        #expect((0..<4).map(biweekly.isFirstInMonth) == [true, false, true, false])

        // Monthly on an ordinary day: that day every month.
        let ninth = PaydaySequence(first: friday, frequency: .monthly)
        #expect((0..<4).map(ninth.date) == [friday, Cal.date(2026, 11, 9), Cal.date(2026, 12, 9), Cal.date(2027, 1, 9)])
        #expect((0..<4).allSatisfy(ninth.isFirstInMonth))

        // Monthly on the 31st: the last day of shorter months, and the 31st again whenever there is one.
        let thirtyFirst = PaydaySequence(first: Cal.date(2027, 1, 31), frequency: .monthly)
        #expect((0..<6).map(thirtyFirst.date) == [Cal.date(2027, 1, 31), Cal.date(2027, 2, 28), Cal.date(2027, 3, 31),
                                                  Cal.date(2027, 4, 30), Cal.date(2027, 5, 31), Cal.date(2027, 6, 30)])
        // A leap year gives February 29.
        #expect(PaydaySequence(first: Cal.date(2028, 1, 31), frequency: .monthly).date(1) == Cal.date(2028, 2, 29))
        #expect(PaydaySequence(first: Cal.date(2028, 1, 30), frequency: .monthly).date(1) == Cal.date(2028, 2, 29))
        // The 29th and 30th behave the same way.
        #expect(PaydaySequence(first: Cal.date(2027, 1, 30), frequency: .monthly).date(1) == Cal.date(2027, 2, 28))
        #expect(PaydaySequence(first: Cal.date(2027, 1, 30), frequency: .monthly).date(2) == Cal.date(2027, 3, 30))
    }

    @Test func aPassedPaydayMovesOnWithoutLosingItsRhythm() {
        // Every two weeks on Fridays. The app is opened on a Monday after the payday has passed:
        // the next payday is the next Friday in the rhythm, not "today" and not two weeks from today.
        var settings = demo.settings                       // biweekly, next payday Fri Oct 9
        #expect(settings.paydays(from: Cal.date(2026, 10, 12)).date(0) == Cal.date(2026, 10, 23))
        #expect(settings.paydays(from: Cal.date(2026, 10, 23)).date(0) == Cal.date(2026, 10, 23))
        #expect(settings.paydays(from: Cal.date(2026, 10, 24)).date(0) == Cal.date(2026, 11, 6))
        #expect(settings.paydays(from: Cal.date(2027, 3, 1)).date(0) == Cal.date(2027, 3, 12))     // months later, still a Friday
        // Before the first payday nothing is invented ahead of it.
        #expect(settings.paydays(from: Cal.date(2026, 9, 1)).date(0) == Cal.date(2026, 10, 9))

        // The split and the plan use the same rhythm even when the stored payday is stale.
        let late = Cal.date(2026, 10, 12)
        let split = PayoffEngine.split(amount: 1200, debts: demo.debts, settings: settings, today: late)
        #expect(split.payday == Cal.date(2026, 10, 23))
        #expect(split.nextPayday == Cal.date(2026, 11, 6))

        // Monthly on the 31st: once the stored payday has been shortened to Feb 28, the next one is Mar 31, not Mar 28.
        settings.payFrequency = .monthly
        settings.setNextPayday(Cal.date(2027, 1, 31))
        #expect(settings.paydayAnchorDay == 31)
        AppClock.override = Cal.date(2027, 2, 1)
        let store = AppStore(data: AppData(settings: settings), persists: false)
        store.refreshForToday()
        #expect(store.settings.nextPayday == Cal.date(2027, 2, 28))
        #expect(store.upcomingPaydays(3).map(\.day.date) == [Cal.date(2027, 2, 28), Cal.date(2027, 3, 31), Cal.date(2027, 4, 30)])
        AppClock.override = Cal.date(2027, 3, 1)
        store.refreshForToday()
        #expect(store.settings.nextPayday == Cal.date(2027, 3, 31))
        AppClock.override = Cal.date(2027, 4, 1)
        store.refreshForToday()
        #expect(store.settings.nextPayday == Cal.date(2027, 4, 30))
        AppClock.override = Cal.date(2027, 5, 1)
        store.refreshForToday()
        #expect(store.settings.nextPayday == Cal.date(2027, 5, 31))
        // Choosing a new date resets the day of the month.
        store.updateSettings { $0.setNextPayday(Cal.date(2027, 5, 15)) }
        #expect(store.upcomingPaydays(3).map(\.day.date) == [Cal.date(2027, 5, 15), Cal.date(2027, 6, 15), Cal.date(2027, 7, 15)])
        AppClock.override = DemoData.today
    }

    @Test func removedPayScheduleStillLoads() throws {
        // "Twice a month" is no longer offered. Settings saved with it, in the single-schedule form
        // from before there were several incomes, must still open: as one income, every two weeks.
        let old = #"{"payFrequency":"semimonthly","nextPayday":"2026-10-09T04:00:00Z","payAmount":1200,"buffer":50,"strategy":"snowball","onboarded":true}"#
        let reader = JSONDecoder()
        reader.dateDecodingStrategy = .iso8601
        let newYork: TimeZone = try #require(TimeZone(identifier: "America/New_York"))
        reader.userInfo[try #require(Day.legacyZone)] = newYork
        let loaded = try reader.decode(PlanSettings.self, from: Data(old.utf8))
        #expect(loaded.incomes.count == 1)
        #expect(loaded.incomes[0].frequency == .biweekly)
        #expect(loaded.incomes[0].amount == 1200)
        #expect(loaded.incomes[0].nextPayday == Cal.date(2026, 10, 9))
        #expect(loaded.buffer == 50)
        #expect(loaded.strategy == .snowball)
        #expect(loaded.onboarded)
        #expect(PayFrequency.allCases.map(\.title) == ["Weekly", "Every 2 weeks", "Monthly"])
        // A monthly schedule keeps the day of the month it remembered.
        let monthly = #"{"payFrequency":"monthly","nextPayday":"2027-02-28T05:00:00Z","payAmount":900,"paydayAnchorDay":31}"#
        let income = try #require(try reader.decode(PlanSettings.self, from: Data(monthly.utf8)).incomes.first)
        #expect(income.payDays == [31])
        #expect(income.paydays(from: Cal.date(2027, 2, 1), count: 3) == [Cal.date(2027, 2, 28), Cal.date(2027, 3, 31), Cal.date(2027, 4, 30)])
    }

    @Test func withNoIncomeThereIsNoPlanAndNothingRunsAway() throws {
        var data = demo
        data.settings.payAmount = 0
        let store = AppStore(data: data, persists: false)
        let clock = ContinuousClock()
        var plan = store.plan
        let took = clock.measure { plan = PayoffEngine.simulate(store.planInput()) }
        #expect(took < .milliseconds(50))                  // nothing to work out, so it returns at once
        #expect(!plan.finished)
        #expect(plan.debtFree == nil)
        #expect(plan.series.count == 1)                    // just today: no line to draw
        #expect(plan.series.first?.total.cents == 42274.73)
        #expect(store.projectedInterest(for: try debt("Chase")) == nil)
        #expect(store.free(in: .total) == nil)
        #expect(store.suggestedPayment == 0)

        // Too little to keep up with the interest: it gives up after a stretch with no progress
        // instead of following the balance upward for decades.
        let short = PayoffEngine.simulate(PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday,
                                                    frequency: .monthly, perPayday: 100, strategy: .avalanche,
                                                    customOrder: [], promoMinimumOnly: true))
        #expect(!short.finished)
        #expect(short.series.count <= 30)
        // A one-time payment with nothing after it also ends unfinished.
        let once = PayoffEngine.simulate(PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday,
                                                   frequency: .biweekly, perPayday: 0, strategy: .avalanche,
                                                   customOrder: [], promoMinimumOnly: true, oneTime: 500))
        #expect(!once.finished)
        // The split with nothing to split is empty, not negative.
        let split = PayoffEngine.split(amount: 0, debts: demo.debts, settings: data.settings, today: today)
        #expect(split.lines.isEmpty)
        #expect(split.total == 0)
        #expect(split.shortBy == 854.99)
    }

    @Test func resetClearsEverythingAndReturnsToSetup() throws {
        let store = AppStore(data: demo, persists: false)
        store.pay(try debt("Klarna").id, amount: 99.98)
        #expect(store.celebration != nil)
        store.reset()
        #expect(store.data.debts.isEmpty)
        #expect(store.data.payments.isEmpty)
        #expect(store.data.history.isEmpty)
        #expect(store.celebration == nil)
        #expect(!store.settings.onboarded)
        #expect(store.settings.payAmount == 0)
        #expect(store.settings.customOrder.isEmpty)
        #expect(store.total == 0)
        #expect(store.plan.finished)                       // nothing owed
        #expect(store.widgetSnapshot == WidgetSnapshot(total: .empty, cards: .empty, loans: .empty))
        #expect(store.undoLabel == nil)                    // and nothing left to undo back into
        // Setup can then add debts again from scratch.
        store.add(Debt.newLoan(type: .personal))
        #expect(store.data.debts.count == 1)
        #expect(store.activity.count == 1)
    }

    @Test func bankNamesAreSetInTheirOwnStyles() {
        #expect(Brand.chase.mark.text(Brand.chase.name) == "CHASE")
        #expect(Brand.citi.mark.text(Brand.citi.name) == "citi")
        #expect(Brand.affirm.mark.text(Brand.affirm.name) == "affirm")
        #expect(Brand.capitalOne.mark.text(Brand.capitalOne.name) == "Capital One")
        #expect(Brand.amex.mark.text(Brand.amex.name) == "AMERICAN EXPRESS")
        // Every named font is one that ships with iOS.
        for brand in Brand.all where !brand.mark.font.isEmpty {
            #expect(UIFont(name: brand.mark.font, size: 17) != nil, "\(brand.name): \(brand.mark.font)")
        }
    }

    @Test func theMonthlyExtraRidesOnTheFirstPaydayOfTheMonth() {
        var data = demo
        data.settings.extraMonthly = 200
        let store = AppStore(data: data, persists: false)
        #expect(store.suggestedPayment == 1400)      // Oct 9 is October's first payday
        store.updateSettings { $0.nextPayday = Cal.date(2026, 10, 23) }
        #expect(store.suggestedPayment == 1200)      // Oct 23 is its second
        // Over a year of biweekly paydays that is twelve extras, one per calendar month.
        let paydays = PaydaySequence(first: Cal.date(2026, 10, 9), frequency: .biweekly)
        #expect((0..<26).filter(paydays.isFirstInMonth).count == 12)
    }

    // MARK: Marking payments

    @Test func markingPaidMovesDueDatesAndBalances() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase"), klarna = try debt("Klarna"), auto = try debt("Auto loan")

        #expect(chase.nextUnpaidDue() == Cal.date(2026, 10, 9))
        store.pay(chase.id, amount: 35)
        store.pay(chase.id, amount: 295.01)
        let chaseAfter = try #require(store.debt(chase.id))
        #expect(chaseAfter.balance == 910.49)
        #expect(chaseAfter.nextUnpaidDue() == Cal.date(2026, 11, 9))

        store.pay(klarna.id, amount: 49.99)
        let klarnaAfter = try #require(store.debt(klarna.id))
        #expect(klarnaAfter.balance == 49.99)
        #expect(klarnaAfter.paidInstallments == 3)
        #expect(klarnaAfter.nextDue == Cal.date(2026, 10, 29))

        // A scheduled loan payment pays the month's interest before principal.
        store.pay(auto.id, amount: 412)
        #expect(try #require(store.debt(auto.id)).balance == 13869.65)
        #expect(store.data.payments.last?.interest == 81.65)

        #expect(store.celebration == nil)
        store.pay(klarna.id, amount: 49.99)
        #expect(store.celebration?.id == klarna.id)

        // Paying more than is owed only records what was owed.
        store.pay(chase.id, amount: 5000)
        #expect(store.debt(chase.id)?.balance == 0)
        #expect(store.data.payments.last?.amount == 910.49)
    }

    // MARK: Due dates, the way a bank runs them

    @Test func aDueDateStaysUntilItsMinimumIsMet() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        func now() throws -> Debt { try #require(store.debt(chase.id)) }

        // $20.00 of the $35.00 minimum: the date holds and the minimum shrinks to what is left.
        store.pay(chase.id, amount: 20)
        #expect(try now().nextUnpaidDue() == Cal.date(2026, 10, 9))
        #expect(try now().scheduledPayment(on: today) == 15)
        #expect(try now().requiredPayment(on: today) == 35)
        #expect(try now().balance == 1220.50)
        #expect(store.data.payments.last?.kind == .partial)
        // The upcoming list and the split ask for the remainder, not the full minimum.
        #expect(store.upcoming().first { $0.debt.id == chase.id }?.amount == 15)
        let split = PayoffEngine.split(amount: 1200, debts: store.data.debts, settings: store.settings, today: today)
        #expect(split.lines.first?.amount == 15)
        #expect(split.lines.first?.detail == "Minimum remainder · due Oct 9")

        // The other $15.00 meets it: the next due date is the same day next month, at the full minimum.
        store.pay(chase.id, amount: 15)
        #expect(try now().nextUnpaidDue() == Cal.date(2026, 11, 9))
        #expect(try now().scheduledPayment(on: today) == 35)
        #expect(try now().paidTowardDue == nil)
        #expect(store.data.payments.last?.kind == .minimum)
    }

    @Test func extraPaymentsDoNotPushTheDueDate() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        func due() throws -> Date? { try #require(store.debt(chase.id)).nextUnpaidDue() }

        // One payment well over the minimum meets October once. It does not also cover November.
        store.pay(chase.id, amount: 100)
        #expect(try due() == Cal.date(2026, 11, 9))
        #expect(store.debt(chase.id)?.balance == 1140.50)

        // More money the same day is extra: the balance falls, the date and the minimum stay.
        store.pay(chase.id, amount: 35)
        store.pay(chase.id, amount: 200)
        #expect(try due() == Cal.date(2026, 11, 9))
        #expect(store.debt(chase.id)?.scheduledPayment(on: today) == 35)
        #expect(store.debt(chase.id)?.balance == 905.50)
        #expect(store.data.payments.suffix(2).map(\.kind) == [.extra, .extra])

        // Still extra eight days after the October 9 due date...
        AppClock.override = Cal.date(2026, 10, 17)
        #expect(store.debt(chase.id)?.countsTowardDue(on: store.today) == false)
        #expect(store.debt(chase.id)?.dueOpens() == Cal.date(2026, 10, 18))
        store.pay(chase.id, amount: 35)
        #expect(try due() == Cal.date(2026, 11, 9))

        // ...and from the ninth day a payment counts toward November, which then moves to December.
        AppClock.override = Cal.date(2026, 10, 18)
        store.pay(chase.id, amount: 35)
        #expect(try due() == Cal.date(2026, 12, 9))
        #expect(store.data.payments.last?.kind == .minimum)
        AppClock.override = DemoData.today
    }

    @Test func anUnmetDueDateBecomesOverdueAndStillWaits() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        AppClock.override = Cal.date(2026, 10, 20)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 10, 9))
        #expect(DueStatus(due: Cal.date(2026, 10, 9), today: store.today).text == "11 days overdue")
        // Meeting it late moves to November 9. That cycle is already open (it is past October 18),
        // so a second minimum the same day does count, as it would at the bank.
        store.pay(chase.id, amount: 35)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 11, 9))
        store.pay(chase.id, amount: 35)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 12, 9))
        AppClock.override = DemoData.today
    }

    @Test func loansAndPlansFollowTheSameRules() throws {
        let store = AppStore(data: demo, persists: false)
        let auto = try debt("Auto loan"), klarna = try debt("Klarna")

        // $200.00 toward the $412.00 car payment: interest first ($81.65), the rest principal.
        store.pay(auto.id, amount: 200)
        var loan = try #require(store.debt(auto.id))
        #expect(loan.balance == 14081.65)
        #expect(loan.nextUnpaidDue() == Cal.date(2026, 10, 15))
        #expect(loan.scheduledPayment(on: today) == 212)
        // The remaining $212.00 lands exactly where one $412.00 payment would have.
        store.pay(auto.id, amount: 212)
        loan = try #require(store.debt(auto.id))
        #expect(loan.balance == 13869.65)
        #expect(loan.nextUnpaidDue() == Cal.date(2026, 11, 15))
        // Extra goes straight to principal and leaves November 15 alone.
        store.pay(auto.id, amount: 500)
        loan = try #require(store.debt(auto.id))
        #expect(loan.balance == 13369.65)
        #expect(loan.nextUnpaidDue() == Cal.date(2026, 11, 15))
        #expect(loan.scheduledPayment(on: today) == 412)

        // A pay-later installment: part of it holds the date, the rest moves to the next installment.
        store.pay(klarna.id, amount: 20)
        var plan = try #require(store.debt(klarna.id))
        #expect(plan.nextDue == Cal.date(2026, 10, 15))
        #expect(plan.scheduledPayment(on: today) == 29.99)
        store.pay(klarna.id, amount: 29.99)
        plan = try #require(store.debt(klarna.id))
        #expect(plan.nextDue == Cal.date(2026, 10, 29))
        #expect(plan.paidInstallments == 3)
        #expect(plan.balance == 49.99)
    }

    @Test func thePlanStartsFromWhatIsLeftOfAPartlyPaidMinimum() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        let before = store.plan.totalInterest
        store.pay(chase.id, amount: 20)
        // Same money overall: $20.00 now, so the first payday only owes Chase $15.00 and the extra grows by $20.00.
        #expect(store.plan.finished)
        #expect(store.plan.debtFree == Cal.date(2028, 4, 1))
        #expect(store.plan.totalInterest < before)
    }

    @Test func aDueDateCanBeCorrectedByHand() throws {
        // What the edit form's "Next due date" does: the cycle before the chosen date counts as met.
        let store = AppStore(data: demo, persists: false)
        var chase = try debt("Chase")
        chase.paidThrough = Cal.date(2026, 12, 9)        // pushed too far by mistake
        #expect(chase.nextUnpaidDue() == Cal.date(2027, 1, 9))
        chase.paidThrough = Cal.date(inMonthOf: Cal.date(2026, 10, 9), monthOffset: -1, day: chase.dueDay)
        store.save(chase)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 10, 9))
        #expect(store.debt(chase.id)?.countsTowardDue(on: today) == true)
        #expect(store.activity.count == 56)             // no balance change, so nothing is logged
    }

    // MARK: Undo

    @Test func undoingTheLatestEntryPutsTheDebtBackExactly() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase"), auto = try debt("Auto loan"), klarna = try debt("Klarna")
        func now(_ d: Debt) throws -> Debt { try #require(store.debt(d.id)) }

        store.pay(chase.id, amount: 20)      // partial
        store.pay(chase.id, amount: 15)      // meets the minimum
        store.pay(chase.id, amount: 100)     // extra
        #expect(store.activity.count == 59)

        // Undo the extra: only the balance moves.
        store.undo(try #require(store.activity.first).id)
        #expect(try now(chase).balance == 1205.50)
        #expect(try now(chase).nextUnpaidDue() == Cal.date(2026, 11, 9))
        // Undo the payment that met the minimum: back to October 9 with $15.00 still to pay.
        store.undo(try #require(store.activity.first).id)
        #expect(try now(chase).balance == 1220.50)
        #expect(try now(chase).nextUnpaidDue() == Cal.date(2026, 10, 9))
        #expect(try now(chase).scheduledPayment(on: today) == 15)
        // Undo the partial: exactly as the demo started.
        store.undo(try #require(store.activity.first).id)
        #expect(try now(chase) == chase)
        #expect(store.activity.count == 56)

        // A loan payment gives back its principal, not the interest it covered.
        store.pay(auto.id, amount: 412)
        #expect(try now(auto).balance == 13869.65)
        store.undo(try #require(store.activity.first).id)
        #expect(try now(auto) == auto)

        // Undoing the payment that finished a plan brings it back from the shelf.
        store.pay(klarna.id, amount: 49.99)
        store.pay(klarna.id, amount: 49.99)
        #expect(store.shelf.map(\.id) == [klarna.id])
        #expect(store.celebration?.id == klarna.id)
        store.undo(try #require(store.activity.first).id)
        #expect(store.shelf.isEmpty)
        #expect(store.celebration == nil)
        #expect(try now(klarna).balance == 49.99)
        #expect(try now(klarna).paidInstallments == 3)
        #expect(try now(klarna).nextDue == Cal.date(2026, 10, 29))
        #expect(try now(klarna).paidOffAt == nil)
        #expect(store.total.cents == (42274.73 - 49.99).cents)
    }

    @Test func undoingAnOlderEntryReappliesTheOnesAfterIt() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        store.pay(chase.id, amount: 20)      // partial
        store.pay(chase.id, amount: 15)      // meets the minimum
        store.pay(chase.id, amount: 100)     // extra
        let partial = try #require(store.activity(for: chase.id).first { $0.kind == .partial })

        // Without the $20.00: the $15.00 is now the partial, and the $100.00 is what meets October.
        store.undo(partial.id)
        let after = try #require(store.debt(chase.id))
        #expect(after.balance == 1125.50)
        #expect(after.nextUnpaidDue() == Cal.date(2026, 11, 9))
        #expect(after.paidTowardDue == nil)
        let entries = store.activity(for: chase.id)
        #expect(entries.prefix(2).map(\.kind) == [.payment, .partial])
        #expect(entries.prefix(2).map(\.amount) == [100, 15])
        #expect(entries.prefix(2).map(\.balanceAfter) == [1125.50, 1225.50])
        #expect(store.activity.count == 58)

        // A recorded payment from last month: September becomes unpaid again, and overdue.
        let september = try #require(store.activity(for: chase.id).first { $0.date == Cal.date(2026, 9, 9) })
        store.undo(september.id)
        let reopened = try #require(store.debt(chase.id))
        #expect(reopened.balance == 1160.50)                               // the $35.00 is back on the balance
        #expect(reopened.nextUnpaidDue() == Cal.date(2026, 10, 9))        // the $15.00 then met September, the $100.00 extra
        #expect(store.activity(for: chase.id).prefix(2).map(\.kind) == [.payment, .partial])
        #expect(store.activity(for: chase.id).first?.balanceAfter == 1160.50)
    }

    @Test func chargesEditsAndOldEntriesCanBeUndoneToo() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")

        store.charge(chase.id, amount: 60)
        store.undo(try #require(store.activity.first).id)
        #expect(try #require(store.debt(chase.id)) == chase)

        var edited = chase
        edited.balance = 1300
        store.save(edited)
        #expect(store.activity.first?.kind == .adjustment)
        store.undo(try #require(store.activity.first).id)
        #expect(store.debt(chase.id)?.balance == 1240.50)

        // "Added" entries explain themselves instead of undoing.
        let added = try #require(store.activity(for: chase.id).last)
        #expect(store.undoBlocker(added) != nil)
        store.undo(added.id)
        #expect(store.activity.count == 56)

        // An entry saved by an older version has no "before" state; it is reversed from its amount.
        store.pay(chase.id, amount: 35)
        store.update { $0.payments[$0.payments.count - 1].before = nil }
        store.undo(try #require(store.activity.first).id)
        #expect(store.debt(chase.id)?.balance == 1240.50)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 10, 9))

        // If the debt was deleted, undoing only removes the entry.
        store.pay(chase.id, amount: 35)
        let orphan = try #require(store.activity.first)
        store.delete(chase.id)
        let total = store.total
        store.undo(orphan.id)
        #expect(store.total == total)
        #expect(!store.activity.contains { $0.id == orphan.id })
    }

    // MARK: Where paid-off debts go, and the history they leave

    @Test func paidOffCardsStayHomeAndTheRestMoveToTheShelf() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase"), klarna = try debt("Klarna"), auto = try debt("Auto loan")
        #expect(store.shelf.isEmpty)
        #expect(store.nextForShelf?.id == klarna.id)

        store.pay(chase.id, amount: 5000)
        store.pay(klarna.id, amount: 5000)
        store.pay(auto.id, amount: 50000)
        // The card is still in the stack at $0.00; the plan and the loan are on the shelf instead.
        #expect(store.stack.contains { $0.id == chase.id && $0.balance == 0 })
        #expect(!store.stack.contains { $0.id == klarna.id })
        #expect(!store.loans.contains { $0.id == auto.id })
        #expect(Set(store.shelf.map(\.id)) == [klarna.id, auto.id])
        #expect(store.debt(chase.id)?.nextUnpaidDue() == nil)
        #expect(!store.active.contains { $0.id == chase.id })

        // A new charge months later puts the card back on its cycle with the next due date coming up, not a stale one.
        AppClock.override = Cal.date(2027, 3, 20)
        store.charge(chase.id, amount: 80)
        #expect(store.debt(chase.id)?.balance == 80)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2027, 4, 9))
        #expect(store.debt(chase.id)?.paidOffAt == nil)
        AppClock.override = DemoData.today
    }

    @Test func everyEntryKeepsTheBalanceItLeft() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase"), auto = try debt("Auto loan")
        let countBefore = store.activity.count
        #expect(countBefore == 56)      // 9 debts added, 30 card minimums, 13 loan payments, 4 installments

        // The demo's own records end on today's balances.
        for d in demo.debts {
            #expect(store.activity(for: d.id).first?.balanceAfter == d.balance, "\(d.title)")
            #expect(store.activity(for: d.id).last?.kind == .added, "\(d.title)")
        }
        #expect(store.activity(for: chase.id).count == 7)
        #expect(store.activity.prefix(5).map(\.label) == ["Klarna installment paid", "Student loan payment", "Amex minimum paid",
                                                          "BofA minimum paid", "Affirm installment paid"])

        // New entries are added on top; nothing older is dropped.
        store.pay(chase.id, amount: 35)
        store.charge(chase.id, amount: 12.40)
        store.pay(auto.id, amount: 412)
        var edited = try #require(store.debt(chase.id))
        edited.balance = 1250
        store.save(edited)
        #expect(store.activity.count == countBefore + 4)
        let history = store.activity(for: chase.id)
        #expect(history.prefix(3).map(\.kind) == [.adjustment, .charge, .minimum])
        #expect(history.prefix(3).map(\.balanceAfter) == [1250, 1217.90, 1205.50])
        #expect(history.prefix(3).map(\.signedAmount) == ["+$32.10", "+$12.40", "−$35.00"])
        #expect(store.activity(for: auto.id).first?.interest == 81.65)
        #expect(store.activity(for: auto.id).first?.balanceAfter == 13869.65)

        // Adding a debt starts its history; deleting it keeps what was already recorded.
        let loan = Debt(kind: .loan, provider: "Lender", name: "", brand: "other", balance: 900, apr: 5, dueDay: 20, minimum: 100,
                        loanType: .personal, addedAt: today, startingBalance: 900)
        store.add(loan)
        #expect(store.activity.first?.label == "Personal loan added")
        store.delete(loan.id)
        // The deletion is an entry too, and it keeps the debt so it can be brought back.
        #expect(store.activity.count == countBefore + 6)
        #expect(store.activity.first?.label == "Personal loan deleted")
        #expect(store.debt(loan.id) == nil)
        store.undo(try #require(store.activity.first).id)
        #expect(store.debt(loan.id)?.balance == 900)
        #expect(store.activity.count == countBefore + 5)
    }

    @Test func chargesRaiseTheBalanceWithoutCountingAsUnpaid() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        let paidBefore = store.paidSoFar(in: .cards)
        store.charge(chase.id, amount: 60.129)
        #expect(store.debt(chase.id)?.balance == 1300.63)
        #expect(store.paidSoFar(in: .cards).cents == paidBefore.cents)
        #expect(store.data.history.last?.cards == 8834.88)
    }

    // MARK: Conversions and formatting

    @Test func rateConversionsAgree() throws {
        let chase = try debt("Chase"), citi = try debt("Citi")
        // A year of daily interest, twelve months of monthly interest and the APR are the same amount.
        #expect(abs(chase.dailyCost(on: today) * 365 - 1240.50 * 0.2699) < 0.000001)
        #expect(abs(chase.monthlyInterest(on: today) * 12 - 1240.50 * 0.2699) < 0.000001)
        #expect(chase.dailyCost(on: today).cents == 0.92)
        #expect(chase.monthlyInterest(on: today).cents == 27.90)
        // The promo rate applies up to the day before it ends.
        #expect(citi.apr(on: Cal.date(2027, 11, 18)) == 0)
        #expect(citi.apr(on: Cal.date(2027, 11, 19)) == 25.49)
        #expect(citi.dailyCost(on: today) == 0)
        // Interest per $100 a month, as Insights shows it.
        #expect([28.49, 26.99, 24.49, 22.99].map { ($0 / 12).cents } == [2.37, 2.25, 2.04, 1.92])
        #expect(chase.utilization.map { Int(($0 * 100).rounded()) } == 41)
        #expect(chase.available == 1759.50)
    }

    @Test func moneyAndDatesFormatTheSameEverywhere() {
        #expect(1240.5.usd == "$1,240.50")
        #expect(0.0.usd == "$0.00")
        #expect(1_000_000.0.usd == "$1,000,000.00")
        #expect(0.005.usd == "$0.01")
        #expect(27.904.usd == "$27.90")
        #expect((0.1 + 0.2).cents == 0.3)
        #expect(Fmt.percent(26.99) == "26.99%")
        #expect(Fmt.percent(6.9) == "6.90%")
        #expect(Fmt.percent(0) == "0%")
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(Fmt.ordinal) == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
        #expect(Fmt.compact(25000) == "$25K")
        #expect(Fmt.compact(2500) == "$2.5K")
        #expect(Fmt.compact(500) == "$500")
        #expect([49524.71, 50617, 200, 1250, 0].map(Fmt.niceCeiling) == [50000, 60000, 200, 1500, 100])
        #expect(Fmt.full(Cal.date(2027, 11, 19)) == "Nov 19, 2027")
        #expect(DueStatus(due: Cal.date(2026, 10, 9), today: today).text == "Due in 5 days")
        #expect(DueStatus(due: Cal.date(2026, 10, 5), today: today).text == "Due tomorrow")
        #expect(DueStatus(due: today, today: today).text == "Due today")
        #expect(DueStatus(due: Cal.date(2026, 10, 15), today: today).text == "Due in 11 days")
        #expect(DueStatus(due: Cal.date(2026, 10, 2), today: today).text == "2 days overdue")
    }

    @Test func theNumberPadReadsWhatWasTyped() {
        var entry = AmountEntry(1200)
        #expect(entry.display == "$1,200.00")
        for key in ["1", "2", ".", "5", "0", "9"] { entry.tap(key) }   // a third decimal is ignored
        #expect(entry.value == 12.5)
        #expect(entry.display == "$12.50")
        entry.add(150)
        #expect(entry.value == 162.5)
        entry.tap("del")
        #expect(entry.display == "$162.5")
        var empty = AmountEntry()
        empty.tap("0")
        empty.tap("7")
        #expect(empty.value == 7)
    }

    // MARK: Saving

    @Test func backupRoundTrips() throws {
        let raw = try Persistence.encoder.encode(demo)
        #expect(try Persistence.decoder.decode(AppData.self, from: raw) == demo)
        #expect(Exporter.csv(demo).contains("Credit card,Chase,Freedom Unlimited,1240.50,26.99,9,35.00,3000.00"))
        // Balance history saved before card and loan totals were tracked still loads.
        let old = try Persistence.decoder.decode(BalancePoint.self, from: Data(#"{"date":"2026-10-04T07:00:00Z","total":42274.73}"#.utf8))
        #expect(old.total == 42274.73)
        #expect(old.value(.cards) == nil)
    }

    @Test func datesAreSavedAsCalendarDays() throws {
        // What is written is the day itself, with no time and no time zone.
        let raw = String(decoding: try Persistence.contents(of: demo), as: UTF8.self)
        #expect(raw.contains("\"paidThrough\" : \"2026-09-09\""))
        #expect(raw.contains("\"nextPayday\" : \"2026-10-09\""))
        #expect(raw.contains("\"date\" : \"2026-10-01\""))
        #expect(!raw.contains("timeZone"))
        #expect(try Persistence.read(Data(raw.utf8)) == demo)

        // An older file holds moments in time. Each is read as the day it fell on where it was
        // written. This one was written in Auckland or Los Angeles, whichever is not here, so its
        // midnights are a different day here: read plainly, the due date would shift.
        let there = try #require(TimeZone(identifier: Cal.zone.identifier == "Pacific/Auckland" ? "America/Los_Angeles" : "Pacific/Auckland"))
        var away = Calendar(identifier: .gregorian)
        away.timeZone = there
        func moment(_ y: Int, _ m: Int, _ d: Int) throws -> String {
            try #require(away.date(from: DateComponents(year: y, month: m, day: d))).formatted(.iso8601)
        }
        let old = """
        {"version":1,"timeZone":"\(there.identifier)","history":[{"date":"\(try moment(2026, 10, 4))","total":1100}],"payments":[],
         "settings":{"payFrequency":"weekly","nextPayday":"\(try moment(2026, 10, 9))","payAmount":500},
         "debts":[{"id":"11111111-1111-1111-1111-111111111111","kind":"card","provider":"Chase","name":"","brand":"chase","balance":1000,"apr":20,"dueDay":9,"minimum":35,
                   "addedAt":"\(try moment(2026, 9, 1))","startingBalance":1000,"paidThrough":"\(try moment(2026, 10, 9))"},
                  {"id":"22222222-2222-2222-2222-222222222222","kind":"payLater","provider":"Klarna","name":"","brand":"klarna","balance":100,"apr":0,"dueDay":1,"minimum":25,"total":100,
                   "installments":4,"paidInstallments":0,"every":"biweekly","nextDue":"\(try moment(2026, 10, 12))",
                   "addedAt":"\(try moment(2026, 9, 1))","startingBalance":100}]}
        """
        let read = try Persistence.read(Data(old.utf8))
        #expect(read.version == AppData.currentVersion)
        #expect(read.settings.incomes.first?.nextPayday == Cal.date(2026, 10, 9))
        #expect(read.settings.incomes.first?.frequency == .weekly)
        #expect(read.debts[0].addedAt == Cal.date(2026, 9, 1))
        #expect(read.debts[0].paidThrough == Cal.date(2026, 10, 9))
        #expect(read.debts[0].nextUnpaidDue() == Cal.date(2026, 11, 9))
        #expect(read.debts[1].nextDue == Cal.date(2026, 10, 12))
        // Saved again, it is in the new form, and reads back the same.
        let saved = String(decoding: try Persistence.contents(of: read), as: UTF8.self)
        #expect(saved.contains("\"paidThrough\" : \"2026-10-09\""))
        #expect(try Persistence.read(Data(saved.utf8)).debts == read.debts)

        // The day arithmetic itself, against the system calendar, across 80 years.
        var day = Day(1990, 1, 1)
        var date = Cal.date(1990, 1, 1)
        for _ in 0..<1500 {
            #expect(day.date == date)
            #expect(Day(date) == day)
            #expect(day.weekday == Cal.calendar.component(.weekday, from: date))
            #expect(Day.next(dayOfMonth: 31, onOrAfter: day).date == Cal.nextDue(day: 31, onOrAfter: date))
            #expect(day.adding(months: 1).date == Cal.addMonths(1, to: date))
            day = day.adding(days: 19)
            date = Cal.addDays(19, to: date)
        }
        #expect(Day(2028, 2, 31) == Day(2028, 2, 29))      // a day past the end of a month is its last day
        #expect("\(Day(2026, 10, 9))" == "2026-10-09")
        #expect(Day("2026-10-09") == Day(2026, 10, 9))
        #expect(Day("10/9/2026") == nil)
    }

    @Test func aDamagedBackupIsBroughtBackIntoRange() throws {
        var bad = demo
        bad.debts[0].balance = -50
        bad.debts[0].apr = 50_000
        bad.debts[0].dueDay = 99
        bad.debts[0].minimum = -1
        let k = try #require(bad.debts.firstIndex { $0.kind == .payLater })
        bad.debts[k].installments = 2_000_000_000
        bad.debts[k].paidInstallments = -3
        bad.settings.incomes[0].amount = -100
        bad.settings.buffer = 1e15
        bad.settings.fixedDay = 40

        let read = try Persistence.read(try Persistence.encoder.encode(bad))
        #expect(read.debts[0].balance == 0)
        #expect(read.debts[0].apr == Limits.percent)
        #expect(read.debts[0].dueDay == 31)
        #expect(read.debts[0].minimum == 0)
        #expect(read.debts[k].installments == Limits.installments)
        #expect(read.debts[k].paidInstallments == 0)
        #expect(read.debts[k].remainingInstallmentDates.count == Limits.installments)
        #expect(read.settings.incomes[0].amount == 0)
        #expect(read.settings.buffer == Limits.money)
        #expect(read.settings.fixedDay == 31)
        // The app still works out a plan from it without stalling.
        let store = AppStore(data: read, persists: false)
        _ = store.plan
        _ = store.widgetSnapshot
        // Good data is not touched.
        var same = demo
        same.sanitize()
        #expect(same == demo)
    }

    @Test func typedAmountsStayInRange() {
        final class Box { var value = 0.0; var optional: Double? }
        let box = Box()
        let amount = Binding(get: { box.value }, set: { box.value = $0 })
        #expect(amount.emptyWhenZero.wrappedValue == nil)
        amount.emptyWhenZero.wrappedValue = 1240.5
        #expect(box.value == 1240.5)
        amount.emptyWhenZero.wrappedValue = -5
        #expect(box.value == 0)
        amount.emptyWhenZero.wrappedValue = 1e15
        #expect(box.value == Limits.money)
        amount.emptyWhenZero.wrappedValue = nil
        #expect(box.value == 0)
        amount.emptyWhenZero(upTo: Limits.percent).wrappedValue = 5000
        #expect(box.value == Limits.percent)

        let limit = Binding(get: { box.optional }, set: { box.optional = $0 })
        limit.clamped(upTo: Limits.money).wrappedValue = -1
        #expect(box.optional == 0)
        limit.clamped(upTo: Limits.money).wrappedValue = nil
        #expect(box.optional == nil)
    }

    @Test func exportsAreSafeToOpenAndDatedByTheLocalDay() throws {
        // A date is written as its own calendar day, wherever the iPhone is.
        #expect(Fmt.isoDay(Cal.date(2026, 10, 9)) == "2026-10-09")
        #expect(Fmt.isoDay(Cal.date(2026, 1, 1)) == "2026-01-01")
        #expect(Fmt.monthAndShortYear(Cal.date(2026, 10, 9)) == "Oct ’26")
        #expect(Exporter.csv(demo).contains("2026-10-01,Klarna,installment,49.99,,99.98"))

        // A name that looks like a formula is exported as plain text; negative amounts stay numbers.
        var data = demo
        data.debts[0].name = "=HYPERLINK(\"x\")"
        data.payments.append(PaymentRecord(debtID: data.debts[0].id, title: "Chase", date: today, amount: -12, kind: .adjustment,
                                           balanceAfter: 1228.50))
        let csv = Exporter.csv(data)
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(csv.contains("Chase,adjustment,-12.00,,1228.50"))

        // The report opens as a PDF, and a long list of debts runs onto more pages instead of being cut off.
        var many = demo
        for i in 0..<60 {
            many.debts.append(Debt(kind: .card, provider: "Bank \(i)", name: "", brand: "other", balance: 100, apr: 20, dueDay: 5,
                                   minimum: 25, addedAt: today, startingBalance: 100))
        }
        func pages(_ data: AppData) throws -> Int {
            let pdf = Report.pdf(for: AppStore(data: data, persists: false))
            let provider = try #require(CGDataProvider(data: pdf as CFData))
            return try #require(CGPDFDocument(provider)).numberOfPages
        }
        let few = try pages(demo)
        #expect(few >= 2)
        #expect(try pages(many) > few)
        // With nothing in it there is still a page, not a crash.
        #expect(try pages(AppData.empty(today: today)) == 1)
    }

    // MARK: Income

    @Test func severalIncomesMakeOneCalendar() throws {
        // A weekly side job on Fridays and a salary on the 1st and the 15th.
        var settings = PlanSettings()
        settings.buffer = 50
        let side = Income(name: "Side job", amount: 200, frequency: .weekly, nextPayday: Cal.date(2026, 10, 9))
        let salary = Income(name: "Salary", amount: 1500, frequency: .monthly, nextPayday: Cal.date(2026, 10, 15), monthDays: [1, 15])
        settings.incomes = [side, salary]
        let events = settings.schedule(today: today).events(from: Day(today), count: 7)
        #expect(events.map(\.day) == [Day(2026, 10, 9), Day(2026, 10, 15), Day(2026, 10, 16), Day(2026, 10, 23), Day(2026, 10, 30),
                                      Day(2026, 11, 1), Day(2026, 11, 6)])
        #expect(events.map(\.gross) == [200, 1500, 200, 200, 200, 1500, 200])
        #expect(events.map(\.net) == [150, 1450, 150, 150, 150, 1450, 150])      // the buffer comes out of each paycheck
        #expect(events[1].lines == [salary.id])
        #expect(salary.rhythm == "The 1st and 15th of every month")
        #expect(side.rhythm == "Every Friday")
        // Two incomes landing on the same day are one payday with both amounts.
        settings.incomes[0].nextPayday = Cal.date(2026, 10, 15)
        let together = try #require(settings.schedule(today: today).events(from: Day(today), count: 1).first)
        #expect(together.gross == 1700 && together.net == 1600 && together.lines.count == 2)
        // The 30th and the 31st are one payday in February, not two.
        let ends = Income(amount: 100, frequency: .monthly, nextPayday: Cal.date(2027, 1, 30), monthDays: [30, 31])
        #expect(ends.paydays(from: Cal.date(2027, 1, 1), count: 4) == [Cal.date(2027, 1, 30), Cal.date(2027, 1, 31), Cal.date(2027, 2, 28), Cal.date(2027, 3, 30)])

        // More income clears the debt sooner, and the plan uses every payday.
        var data = demo
        let one = AppStore(data: data, persists: false).plan
        data.settings.incomes.append(Income(name: "Side job", amount: 250, frequency: .weekly, nextPayday: Cal.date(2026, 10, 9)))
        let store = AppStore(data: data, persists: false)
        let two = store.plan
        #expect(one.finished && two.finished)
        let soonerEnd = try #require(two.debtFree), laterEnd = try #require(one.debtFree)
        #expect(soonerEnd < laterEnd)
        #expect(two.totalInterest < one.totalInterest)
        #expect(store.suggestedPayment == 1450)            // Oct 9: the paycheck and the side job together
        let aMonth: Double = 1150 * 26.0 / 12 + 200 * 52.0 / 12
        #expect(store.monthlyForDebt.cents == aMonth.cents)

        // Marking a whole split paid uses up that payday for the incomes behind it, and only those.
        let split = PayoffEngine.split(amount: 1450, debts: data.debts, settings: data.settings, today: today)
        #expect(split.bufferKept == 50)
        #expect(split.nextPayday == Cal.date(2026, 10, 16))
        store.apply(split, paid: Set(split.lines.map(\.id)))
        #expect(store.settings.incomes.map(\.nextPayday) == [Cal.date(2026, 10, 23), Cal.date(2026, 10, 16)])
        #expect(store.undoLabel == "Payday split")
        // Leaving a line unpaid leaves the payday where it is.
        let part = PayoffEngine.split(amount: 400, debts: store.data.debts, settings: store.settings, today: today)
        #expect(part.lines.count > 1 && part.payday == Cal.date(2026, 10, 16))
        store.apply(part, paid: Set(part.lines.prefix(1).map(\.id)))
        #expect(store.settings.incomes.map(\.nextPayday) == [Cal.date(2026, 10, 23), Cal.date(2026, 10, 16)])
    }

    @Test func aFixedAmountCanStandInForPaydays() throws {
        var data = demo
        data.settings.useFixedAmount = true
        data.settings.fixedAmount = 2000
        data.settings.fixedDay = 20
        let store = AppStore(data: data, persists: false)
        #expect(store.upcomingPaydays(3).map(\.day) == [Day(2026, 10, 20), Day(2026, 11, 20), Day(2026, 12, 20)])
        #expect(store.upcomingPaydays(1).first?.net == 2000)   // all of it: no buffer is taken from a fixed amount
        #expect(store.suggestedPayment == 2000)
        #expect(store.plan.finished)
        let split = PayoffEngine.split(amount: 2000, debts: data.debts, settings: data.settings, today: today)
        #expect(split.bufferKept == 0)
        #expect(split.total == 2000)
        #expect(split.payday == Cal.date(2026, 10, 20) && split.nextPayday == Cal.date(2026, 11, 20))
        store.apply(split, paid: Set(split.lines.map(\.id)))
        #expect(store.upcomingPaydays(1).first?.day == Day(2026, 11, 20))   // this month's amount is used
        #expect(store.settings.incomes.first?.nextPayday == Cal.date(2026, 10, 9))   // the paydays are kept, untouched
        // With no income at all there are no paydays, and Make a Payment covers the next two weeks.
        var none = demo.settings
        none.incomes = []
        let bare = PayoffEngine.split(amount: 300, debts: demo.debts, settings: none, today: today)
        #expect(bare.payday == today && bare.nextPayday == Cal.date(2026, 10, 18))
        #expect(bare.incomes.isEmpty)
    }

    @Test func extraMoneyUsesNoPayday() throws {
        let store = AppStore(data: demo, persists: false)
        let extra = PayoffEngine.extraSplit(amount: 500, debts: demo.debts, settings: demo.settings, today: today)
        // Nothing is held back and nothing is overdue, so all of it goes to the first debt in the strategy.
        #expect(extra.isExtraMoney && extra.bufferKept == 0)
        let extraLines = extra.lines.map { "\($0.title) \($0.amount.usd)" }
        #expect(extraLines == ["Chase $500.00"])
        #expect(extra.lines.allSatisfy { $0.isExtra })
        store.apply(extra, paid: Set(extra.lines.map(\.id)))
        let chaseID = try debt("Chase").id
        #expect(store.debt(chaseID)?.balance == 740.50)
        #expect(store.settings.incomes.first?.nextPayday == Cal.date(2026, 10, 9))   // the paycheck is still to come
        #expect(store.undoLabel == "Extra money")
        // More than the first debt owes spills to the next.
        let large = PayoffEngine.extraSplit(amount: 2000, debts: demo.debts, settings: demo.settings, today: today)
        #expect(large.lines.map(\.title) == ["Chase", "Capital One"])
        #expect(large.total == 2000)
        // Something overdue comes first, because that is where late fees come from.
        var late = demo
        let b = try #require(late.debts.firstIndex { $0.title == "Bank of America" })
        late.debts[b].paidThrough = Cal.date(2026, 8, 22)   // September's minimum was missed
        let rescue = PayoffEngine.extraSplit(amount: 100, debts: late.debts, settings: late.settings, today: today)
        let rescueLines = rescue.lines.map { "\($0.title) \($0.amount.usd) \($0.isExtra)" }
        #expect(rescueLines == ["Bank of America $85.00 false", "Chase $15.00 true"])
    }

    // MARK: Undo, redo and editing

    @Test func theLastActionCanBeUndoneAndRedone() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        #expect(store.undoLabel == nil && store.redoLabel == nil)

        // Deleting a debt, the thing most worth being able to take back.
        store.delete(chase.id)
        #expect(store.debt(chase.id) == nil)
        #expect(store.undoLabel == "Delete Chase")
        store.undoLast()
        #expect(store.debt(chase.id) == chase)
        #expect(store.data.debts == demo.debts && store.data.payments == demo.payments && store.settings == demo.settings)
        #expect(store.undoLabel == nil && store.redoLabel == "Delete Chase")
        store.redo()
        #expect(store.debt(chase.id) == nil)
        #expect(store.redoLabel == nil)
        store.undoLast()

        // Several steps come back in reverse order, and a new action ends the chance to redo.
        store.pay(chase.id, amount: 35)
        store.charge(chase.id, amount: 20)
        store.updateSettings("Change strategy") { $0.strategy = .snowball }
        #expect(store.undoLabel == "Change strategy")
        store.undoLast()
        #expect(store.settings.strategy == .custom)
        #expect(store.undoLabel == "Chase charge")
        store.undoLast()
        #expect(store.debt(chase.id)?.balance == 1205.50)
        store.pay(chase.id, amount: 10)
        #expect(store.redoLabel == nil)
        // A change that changes nothing is not a step, and neither is housekeeping without a label.
        let steps = store.journal.undo.count
        store.updateSettings("Change strategy") { $0.strategy = .custom }
        store.updateSettings { $0.remindPaydays.toggle() }
        #expect(store.journal.undo.count == steps)
        // Only the last few steps are kept.
        for _ in 0..<40 { store.charge(chase.id, amount: 1) }
        #expect(store.journal.undo.count == Journal.limit)
        // Past balances follow: history is worked out from the entries, so it has no entry for what was undone.
        let before = store.data.history
        store.undoLast()
        #expect(store.data.history != before)
        #expect(store.data.history.last?.total == store.total.cents)
    }

    @Test func anEntryCanBeEditedInPlace() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        store.pay(chase.id, amount: 35)                    // a minimum, meeting October 9
        store.pay(chase.id, amount: 100)                   // then an extra
        var mine = store.activity(for: chase.id)
        #expect(mine.prefix(2).map(\.kind) == [.extra, .minimum])
        #expect(store.debt(chase.id)?.balance == 1105.50)

        // Change the first payment from $35.00 to $20.00: it no longer meets the minimum, so it becomes
        // a partial payment, and the next one finishes the minimum instead of being all extra.
        store.edit(mine[1].id, amount: 20, date: today)
        mine = store.activity(for: chase.id)
        #expect(mine.prefix(2).map(\.kind) == [.payment, .partial])
        #expect(mine.prefix(2).map(\.amount) == [100, 20])
        #expect(mine.prefix(2).map(\.balanceAfter) == [1120.50, 1220.50])
        #expect(store.debt(chase.id)?.balance == 1120.50)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 11, 9))
        #expect(store.undoLabel == "Edit Chase minimum paid")
        store.undoLast()
        #expect(store.debt(chase.id)?.balance == 1105.50)

        // Move an old payment to another day: September's minimum, paid on the 9th, to the 2nd.
        let september = try #require(store.activity(for: chase.id).first { $0.date == Cal.date(2026, 9, 9) })
        let entries = store.activity.count
        store.edit(september.id, amount: 35, date: Cal.date(2026, 9, 2))
        #expect(store.activity.count == entries)
        #expect(store.activity(for: chase.id).contains { $0.date == Cal.date(2026, 9, 2) && $0.amount == 35 })
        #expect(store.debt(chase.id)?.balance == 1105.50)  // the same money, on a different day
        // The past changed with it: the balance was already lower on September 5.
        let track = try #require(History.tracks(debts: store.data.debts, payments: store.data.payments, today: today).first { $0.id == chase.id })
        #expect(track.balance(on: Cal.date(2026, 9, 5)) == 1240.50)
        #expect(track.balance(on: Cal.date(2026, 9, 1)) == 1275.50)
        // Things that are not payments or charges cannot be edited, and say so.
        let added = try #require(store.activity(for: chase.id).last)
        #expect(store.editBlocker(added) != nil)
        // A day in the future, or before the debt existed, is brought back in range.
        store.edit(september.id, amount: 35, date: Cal.date(2031, 1, 1))
        #expect(store.activity(for: chase.id).allSatisfy { $0.date <= today })
    }

    @Test func entriesFromBeforeSnapshotsWereKeptUndoCleanly() throws {
        // The oldest data has entries with no record of the state before them or the balance after.
        var data = demo
        for i in data.payments.indices {
            data.payments[i].before = nil
            data.payments[i].balanceAfter = nil
        }
        data.version = 1
        Migration.run(&data)
        #expect(data.version == AppData.currentVersion)
        // The balances each entry left are worked back out, and match what the demo recorded: to the cent
        // for cards and pay-later plans, and within a cent for loans, whose interest was itself rounded.
        for (worked, recorded) in zip(data.payments, demo.payments) {
            let gap = abs((worked.balanceAfter ?? -1) - (recorded.balanceAfter ?? -2))
            #expect(gap < (worked.debtKind == .loan ? 0.011 : 0.001), "\(recorded.label) \(Fmt.isoDay(recorded.date))")
        }
        #expect(data.payments.allSatisfy { $0.debtKind != nil })

        // Undoing an old entry takes its amount back once, however many entries came after it.
        let store = AppStore(data: data, persists: false)
        let chase = try debt("Chase")
        let may = try #require(store.activity(for: chase.id).first { $0.date == Cal.date(2026, 5, 9) })
        store.undo(may.id)
        #expect(store.debt(chase.id)?.balance == 1275.50)
        #expect(store.activity(for: chase.id).count == 6)
        #expect(store.activity(for: chase.id).first?.balanceAfter == 1275.50)
        // And the history drawn from the entries agrees with the totals now.
        #expect(store.data.history.last?.total == store.total.cents)
        #expect(store.data.history.last?.cards == store.total(of: .card).cents)
    }

    @Test func dueDatesPushedTooFarAreRepairedOnce() throws {
        // An earlier version moved the due date on with every payment. Three payments in one week
        // pushed this card's date three months ahead.
        func card(_ title: String, due: Int, through: Date?, added: Date) -> Debt {
            Debt(kind: .card, provider: title, name: "", brand: "other", balance: 500, apr: 20, dueDay: due, minimum: 25,
                 addedAt: added, startingBalance: 600, paidThrough: through)
        }
        let pushed = card("Pushed", due: 9, through: Cal.date(2027, 1, 9), added: Cal.date(2026, 1, 1))
        let fine = card("Fine", due: 12, through: Cal.date(2026, 9, 12), added: Cal.date(2026, 1, 1))
        let fresh = card("Fresh", due: 1, through: Cal.date(2026, 11, 1), added: Cal.date(2026, 10, 4))   // added after this month's due day
        let quiet = card("Quiet", due: 20, through: Cal.date(2027, 3, 20), added: Cal.date(2026, 1, 1))   // no payments recorded at all
        func paid(_ debt: Debt, _ date: Date, _ kind: PaymentRecord.Kind = .minimum) -> PaymentRecord {
            PaymentRecord(debtID: debt.id, title: debt.title, date: date, amount: 25, kind: kind)
        }
        var data = AppData(version: 1, debts: [pushed, fine, fresh, quiet],
                           payments: [paid(pushed, Cal.date(2026, 9, 28)), paid(pushed, Cal.date(2026, 10, 1), .extra), paid(pushed, Cal.date(2026, 10, 4), .extra),
                                      paid(fine, Cal.date(2026, 9, 12)), paid(fresh, Cal.date(2026, 10, 4))],
                           settings: PlanSettings())
        Migration.run(&data)
        // The latest payment, October 4, could have met October 9 at the furthest: so next is November 9.
        #expect(data.debts[0].paidThrough == Cal.date(2026, 10, 9))
        #expect(data.debts[0].nextUnpaidDue() == Cal.date(2026, 11, 9))
        // Dates the rules allow are left exactly as they were.
        #expect(data.debts[1].paidThrough == Cal.date(2026, 9, 12))
        #expect(data.debts[2].paidThrough == Cal.date(2026, 11, 1))
        #expect(data.debts[3].paidThrough == Cal.date(2027, 3, 20))
        // The user is told what moved, once.
        #expect(data.settings.notices == ["Pushed: next due date moved from Feb 9, 2027 back to Nov 9, 2026."])
        let store = AppStore(data: data, persists: false)
        store.dismissNotices()
        #expect(store.settings.notices.isEmpty)
        // It does not run again on data that is already up to date.
        var again = store.data
        again.debts[0].paidThrough = Cal.date(2027, 1, 9)
        Migration.run(&again)
        #expect(again.debts[0].paidThrough == Cal.date(2027, 1, 9))
    }

    // MARK: Statements and utilization

    @Test func statementCheckInBringsABalanceUpToDate() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase"), auto = try debt("Auto loan")
        #expect(store.awaitingCheckIn.count == 5)          // the five cards; loans work out their own interest
        #expect(store.checkInCandidates.count == 7)        // loans can still be checked in; pay-later plans have no statements
        // Chase's statement says $1,268.40: $27.90 of interest the app had not seen.
        store.checkIn([.init(debtID: chase.id, balance: 1268.40, minimum: 40, interest: 27.90),
                       .init(debtID: auto.id, balance: 14200, minimum: nil, interest: nil)])
        let after = try #require(store.debt(chase.id))
        #expect(after.balance == 1268.40)
        #expect(after.minimum == 40)
        #expect(after.statementThrough == today)
        #expect(after.startingBalance == chase.startingBalance + 27.90)   // interest is new debt, not money un-paid
        #expect(store.paidSoFar(in: .cards).cents == AppStore(data: demo, persists: false).paidSoFar(in: .cards).cents)
        let entry = try #require(store.activity(for: chase.id).first)
        #expect(entry.kind == .statement && entry.amount == 27.90 && entry.interest == 27.90 && entry.balanceAfter == 1268.40)
        #expect(entry.signedAmount == "+$27.90")
        #expect(store.activity(for: auto.id).first?.amount == 0)          // unchanged, but checked
        #expect(store.awaitingCheckIn.count == 4)
        // The whole check-in is one step.
        #expect(store.undoLabel == "Statement check-in")
        store.undoLast()
        #expect(store.debt(chase.id) == chase)
        #expect(store.awaitingCheckIn.count == 5)
        store.redo()
        // One entry can be taken back on its own.
        store.undo(try #require(store.activity(for: chase.id).first).id)
        #expect(store.debt(chase.id)?.balance == 1240.50)
        #expect(store.debt(chase.id)?.statementThrough == nil)

        // A statement for every month since the first entry, oldest first.
        let statements = store.statements
        let months = statements.map { Fmt.monthNameYear($0.month) }
        #expect(months == ["March 2026", "April 2026", "May 2026", "June 2026", "July 2026", "August 2026", "September 2026", "October 2026"])
        let september = try #require(statements.first { $0.month == Cal.date(2026, 9, 1) })
        // Five card minimums, both loan payments, Affirm's installment and Klarna's first.
        #expect(september.paid == (35 + 58 + 85 + 40 + 29 + 412 + 210 + 175 + 49.99).cents)
        #expect(september.payments.count == 9)
        #expect(september.interest > 0)                    // the interest part of the two loan payments
        #expect(!september.isCurrent)
        // Each month starts where the last one ended, and the newest ends on today's total.
        for (earlier, later) in zip(statements, statements.dropFirst()) { #expect(earlier.closing == later.opening) }
        #expect(statements.last?.closing == store.total.cents)
        #expect(statements.last?.isCurrent == true)
        #expect(statements.first?.opening == 0)
    }

    @Test func utilizationAndTheDayEachCardDropsUnderThirtyPercent() throws {
        let store = AppStore(data: demo, persists: false)
        #expect(store.limitedCards.count == 5)
        // $8,774.75 owed against $19,500.00 of limits.
        #expect(try #require(store.utilization) == 8774.75 / 19500)
        #expect(store.utilizationHistory.last?.total == 8774.75 / 19500)
        #expect(store.utilizationHistory.first?.date == Cal.date(2026, 3, 31))
        let plan = store.utilizationPlan
        #expect(plan.first?.total == 8774.75 / 19500)
        #expect(plan.last?.total == 0)
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $1.total <= $0.total + 1e-9 })   // only ever down, with no new charges
        // Chase is at 41% of $3,000.00. It drops under 30% ($900.00) on the payday its balance first is.
        let chase = try debt("Chase")
        let day = try #require(store.under30Date(for: chase))
        let line = try #require(store.plan.balances[chase.id])
        let index = try #require(store.plan.series.firstIndex { $0.date == day })
        #expect(line[index] < 900 && line[index - 1] >= 900)
        #expect(day == Cal.date(2026, 10, 23))
        // A card already under 30% says so with today; one with no limit has no answer.
        var data = demo
        let a = try #require(data.debts.firstIndex { $0.title == "American Express" })
        data.debts[a].balance = 500                        // 20% of $2,500.00
        data.debts[0].creditLimit = nil
        let other = AppStore(data: data, persists: false)
        #expect(other.under30Date(for: data.debts[a]) == today)
        #expect(other.under30Date(for: data.debts[0]) == nil)
        #expect(other.limitedCards.count == 4)
    }

    // MARK: Speed and agreement

    @Test func everyOrderOfSevenDebtsRunsQuicklyAndNoneBeatsAvalanche() throws {
        // All 5,040 ways to order the seven debts that take extra payments, each run as a whole plan.
        let ids = try ["Chase", "Capital One", "Bank of America", "American Express", "Auto loan", "Student loan", "Citi"].map { try debt($0).id }
        let rest = try ["Klarna", "Affirm"].map { try debt($0).id }
        func permutations(_ items: [UUID]) -> [[UUID]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[UUID]] in
                var others = items
                let head = others.remove(at: i)
                return permutations(others).map { [head] + $0 }
            }
        }
        let orders = permutations(ids)
        #expect(orders.count == 5040)
        func input(_ strategy: Strategy, _ order: [UUID]) -> PlanInput {
            PlanInput(debts: demo.debts, today: today, firstPayday: demo.settings.nextPayday, frequency: .biweekly, perPayday: 1150,
                      strategy: strategy, customOrder: order, promoMinimumOnly: false, totalsOnly: true)
        }
        let best = PayoffEngine.simulate(input(.avalanche, [])).totalInterest
        var cheaper = 0
        let took = ContinuousClock().measure {
            for order in orders where PayoffEngine.simulate(input(.custom, order + rest)).totalInterest < best - 0.005 { cheaper += 1 }
        }
        #expect(cheaper == 0)
        print("5,040 plans in \(took)")
        #expect(took < .seconds(20))                       // an unoptimised test build; a release build is many times faster
        // The plan's own day arithmetic gives the same due dates and installment dates as the rest of the app.
        for d in demo.debts {
            let alone = PayoffEngine.simulate(PlanInput(debts: [d], today: today, firstPayday: today, frequency: .weekly, perPayday: 1,
                                                        strategy: .avalanche, customOrder: [], promoMinimumOnly: true, oneTime: 100_000))
            let covered = d.kind == .payLater ? d.remainingInstallmentDates.last : d.nextUnpaidDue().map { Cal.nextDue(day: d.dueDay, onOrAfter: max($0, today)) }
            #expect(alone.payoff[d.id] == covered.map { max($0, today) }, "\(d.title)")
        }
        // Leaving out the detail does not change the answer.
        var full = input(.avalanche, [])
        full.totalsOnly = false
        let detailed = PayoffEngine.simulate(full)
        #expect(detailed.totalInterest == best)
        #expect(detailed.debtFree == PayoffEngine.simulate(input(.avalanche, [])).debtFree)
        #expect(!detailed.series.isEmpty && PayoffEngine.simulate(input(.avalanche, [])).series.isEmpty)
    }

    @Test func interestInOneStepMatchesInterestDayByDay() throws {
        // The plan works out a stretch of days in one step. Check that against adding it up a day at
        // a time, the way it used to be done: a card compounds daily, a loan charges simple interest.
        let card = Debt(kind: .card, provider: "Card", name: "", brand: "other", balance: 5000, apr: 24.99, dueDay: 28, minimum: 100,
                        addedAt: today, startingBalance: 5000, paidThrough: Cal.date(2026, 9, 28))
        let loan = Debt(kind: .loan, provider: "Loan", name: "", brand: "other", balance: 8000, apr: 7.5, dueDay: 28, minimum: 300,
                        loanType: .personal, addedAt: today, startingBalance: 8000, paidThrough: today)
        // One payday 40 days out, big enough to clear both, so the only interest is those 40 days.
        func run(_ debt: Debt) -> Double {
            PayoffEngine.simulate(PlanInput(debts: [debt], today: today, firstPayday: Cal.addDays(40, to: today), frequency: .monthly,
                                            perPayday: 20000, strategy: .avalanche, customOrder: [], promoMinimumOnly: true)).totalInterest
        }
        var balance = 5000.0
        for _ in 0..<40 { balance += balance * 24.99 / 36500 }
        #expect(abs(run(card) - (balance - 5000)) < 1e-9)
        #expect(abs(run(loan) - 8000 * 7.5 / 36500 * 40) < 1e-9)
        // A promo that ends partway: 0% for the first 15 days, the regular rate for the other 25.
        var promo = card
        promo.promoAPR = 0
        promo.promoEnd = Cal.addDays(15, to: today)
        balance = 5000
        for _ in 0..<25 { balance += balance * 24.99 / 36500 }
        #expect(abs(run(promo) - (balance - 5000)) < 1e-9)
    }

    // MARK: Checks from the October 6 review

    @Test func undoLeavesTheIPhonesOwnSettingsAlone() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        store.pay(chase.id, amount: 35)
        // Things that are not part of the plan, changed after the payment.
        store.updateSettings {
            $0.remindDueDates = false
            $0.lastBackup = Cal.date(2026, 10, 4)
            $0.notices = ["A note"]
        }
        store.undoLast()
        #expect(store.debt(chase.id)?.balance == 1240.50)  // the payment is taken back
        #expect(store.settings.remindDueDates == false)    // the switch is not
        #expect(store.settings.lastBackup == Cal.date(2026, 10, 4))
        #expect(store.settings.notices == ["A note"])
        #expect(store.settings.hasAcceptedLegal)
        store.redo()
        #expect(store.settings.remindDueDates == false)
        #expect(store.debt(chase.id)?.balance == 1205.50)

        // A run of the same small change is one step, undone back to where it started.
        store.updateSettings("Change safety buffer", merging: true) { $0.buffer = 7 }
        store.updateSettings("Change safety buffer", merging: true) { $0.buffer = 75 }
        store.updateSettings("Change safety buffer", merging: true) { $0.buffer = 80 }
        #expect(store.undoLabel == "Change safety buffer")
        let steps = store.journal.undo.count
        store.undoLast()
        #expect(store.settings.buffer == 50)
        #expect(store.journal.undo.count == steps - 1)

        // A payday that passed while a step was waiting is moved on after the undo, not brought back.
        store.pay(chase.id, amount: 10)
        AppClock.override = Cal.date(2026, 10, 12)
        store.refreshForToday()
        #expect(store.settings.incomes.first?.nextPayday == Cal.date(2026, 10, 23))
        store.undoLast()
        #expect(store.settings.incomes.first?.nextPayday == Cal.date(2026, 10, 23))
        AppClock.override = DemoData.today
    }

    @Test func restoringABackupKeepsWhatWasAccepted() throws {
        let store = AppStore(data: demo, persists: false)
        var backup = demo
        backup.settings.acceptedPrivacy = nil              // a backup from before the policy existed
        backup.settings.acceptedDisclaimer = nil
        backup.settings.acceptedLegalVersion = nil
        backup.settings.onboarded = false
        backup.debts.removeLast()
        store.restore(backup)
        #expect(store.data.debts.count == 8)
        #expect(store.settings.hasAcceptedLegal)           // not asked again on this iPhone
        #expect(store.settings.onboarded)
        #expect(store.undoLabel == "Restore backup")
        store.undoLast()
        #expect(store.data.debts.count == 9)
        // On an iPhone that has accepted nothing, a backup's own acceptance is what counts.
        var fresh = AppData.empty(today: today)
        fresh.settings.onboarded = true
        let other = AppStore(data: fresh, persists: false)
        other.restore(backup)
        #expect(!other.settings.hasAcceptedLegal)
        other.restore(demo)
        #expect(other.settings.hasAcceptedLegal)
    }

    /// A small repeatable source of random numbers, so a failure can be run again exactly.
    private struct Dice: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
        mutating func money(_ most: Double) -> Double { (Double(next() % 1_000_000) / 1_000_000 * most).cents }
        mutating func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[int(items.count)] }
    }


    /// What must be true of the data whatever the user has just done.
    private func consistent(_ store: AppStore, _ place: String, thorough: Bool = true) throws {
        let data = store.data
        for d in data.debts {
            #expect(d.balance >= 0 && d.balance.isFinite && d.balance == d.balance.cents, "\(place): \(d.title) balance \(d.balance)")
            #expect(d.isPaidOff || d.paidOffAt == nil, "\(place): \(d.title) has a paid-off date but owes \(d.balance)")
            #expect((d.paidTowardDue ?? 1) > 0, "\(place): \(d.title) part-paid nothing")
            #expect((d.paidInstallments ?? 0) <= (d.installments ?? 0), "\(place): \(d.title) installments")
            if let last = data.payments.last(where: { $0.debtID == d.id }) {
                #expect(abs((last.balanceAfter ?? d.balance) - d.balance) < 0.006, "\(place): \(d.title) last entry left \(last.balanceAfter ?? -1), balance \(d.balance)")
            }
        }
        #expect(data.payments.allSatisfy { $0.amount.isFinite && ($0.isSigned || $0.amount >= 0) }, "\(place): an entry amount")
        // The history drawn from the entries ends today, on today's totals, and never runs backwards.
        #expect(data.debts.isEmpty && data.payments.isEmpty || data.history.last?.date == store.today, "\(place): history ends today")
        #expect((data.history.last?.total ?? 0) == store.total.cents || data.debts.isEmpty, "\(place): history total")
        #expect(zip(data.history, data.history.dropFirst()).allSatisfy { $0.date < $1.date }, "\(place): history order")
        #expect(data.history.allSatisfy { $0.total >= 0 }, "\(place): history below zero")
        // The rest is slower to work out, so it is looked at every few steps rather than every one.
        guard thorough else { return }
        // Saved and read back, it is the same data.
        let again = try Persistence.read(try Persistence.contents(of: data))
        #expect(again.debts == data.debts, "\(place): debts do not survive saving")
        #expect(again.payments == data.payments, "\(place): entries do not survive saving")
        #expect(again.history == data.history, "\(place): history does not survive saving")
        #expect(again.settings == data.settings, "\(place): settings do not survive saving")
        // The plan, the split and the statements can all be worked out from it.
        let plan = store.plan
        #expect(plan.totalInterest.isFinite && plan.totalInterest >= -0.001, "\(place): plan interest \(plan.totalInterest)")
        #expect(!plan.finished || store.active.isEmpty || plan.debtFree != nil, "\(place): finished without a date")
        #expect(plan.series.allSatisfy { $0.total > -0.01 && $0.total.isFinite }, "\(place): plan below zero")
        let split = PayoffEngine.split(amount: 900, debts: data.debts, settings: data.settings, today: store.today)
        #expect(split.total <= 900 - split.bufferKept + 0.005 && split.lines.allSatisfy { $0.amount > 0 }, "\(place): split")
        let statements = store.statements
        #expect(zip(statements, statements.dropFirst()).allSatisfy { abs($0.closing - $1.opening) < 0.006 }, "\(place): statements do not chain")
        #expect(statements.isEmpty || abs((statements.last?.closing ?? 0) - store.total) < 0.006, "\(place): newest statement total")
        #expect(store.upcoming().allSatisfy { $0.amount >= 0 }, "\(place): upcoming")
        #expect(store.journal.undo.count <= Journal.limit, "\(place): journal")
        _ = store.widgetSnapshot
    }

    @Test func randomUseKeepsEverythingConsistent() throws {
        defer { AppClock.override = DemoData.today }
        for seed in [11, 22, 33, 44, 55, 66] as [UInt64] {
            var dice = Dice(state: seed)
            AppClock.override = DemoData.today
            let store = AppStore(data: demo, persists: false)
            for step in 0..<220 {
                var did = ""
                switch dice.int(17) {
                case 0, 1, 2:
                    if let d = dice.pick(store.active) {
                        let amount = dice.int(4) == 0 ? d.balance + 50 : dice.money(min(600, d.balance + 20)) + 0.01
                        store.pay(d.id, amount: amount)
                        did = "pay \(d.title) \(amount)"
                    }
                case 3:
                    if let d = dice.pick(store.data.debts.filter { $0.kind == .card }) {
                        store.charge(d.id, amount: dice.money(400) + 0.01)
                        did = "charge \(d.title)"
                    }
                case 4:
                    if var d = dice.pick(store.data.debts) {
                        d.balance = dice.int(5) == 0 ? 0 : dice.money(5000)
                        d.dueDay = 1 + dice.int(31)
                        d.minimum = dice.money(300) + 1    // not always a whole number of cents: the store tidies it
                        store.save(d)
                        did = "edit \(d.title) to \(d.balance)"
                    }
                case 5:
                    if let record = dice.pick(store.activity) {
                        store.undo(record.id)
                        did = "undo entry \(record.label)"
                    }
                case 6, 7:
                    if let record = dice.pick(store.activity.filter { store.editBlocker($0) == nil }) {
                        let date = Cal.addDays(-dice.int(200), to: store.today)
                        store.edit(record.id, amount: dice.money(700) + 0.01, date: date)
                        did = "edit entry \(record.label) to \(Fmt.isoDay(date))"
                    }
                case 8:
                    let picked = store.checkInCandidates.filter { _ in dice.int(2) == 0 }
                    store.checkIn(picked.map { .init(debtID: $0.id, balance: dice.int(6) == 0 ? 0 : ($0.balance + dice.money(60)).cents, minimum: dice.int(3) == 0 ? dice.money(90) : nil, interest: dice.int(2) == 0 ? dice.money(40) : nil) })
                    did = "check in \(picked.count)"
                case 9:
                    let split = PayoffEngine.split(amount: dice.money(3000), debts: store.data.debts, settings: store.settings, today: store.today)
                    store.apply(split, paid: Set(split.lines.filter { _ in dice.int(4) != 0 }.map(\.id)))
                    did = "split \(split.amount)"
                case 10:
                    let split = PayoffEngine.extraSplit(amount: dice.money(2500), debts: store.data.debts, settings: store.settings, today: store.today)
                    store.apply(split, paid: Set(split.lines.map(\.id)))
                    did = "extra \(split.amount)"
                case 11:
                    store.undoLast()
                    did = "undo last"
                case 12:
                    store.redo()
                    did = "redo"
                case 13:
                    if dice.int(3) == 0, let d = dice.pick(store.data.debts) {
                        store.delete(d.id)
                        did = "delete \(d.title)"
                    } else {
                        let kind = dice.int(3)
                        let balance = dice.money(4000) + 1
                        var d = Debt(kind: kind == 0 ? .loan : .card, provider: "Fuzz \(step)", name: "", brand: "other", balance: balance,
                                     apr: Double(dice.int(3500)) / 100, dueDay: 1 + dice.int(31), minimum: dice.money(200) + 5,
                                     addedAt: store.today, startingBalance: balance)
                        if kind == 0 { d.loanType = .personal }
                        if kind == 1 { d.creditLimit = balance + dice.money(3000) }
                        if kind == 2 {
                            d.promoAPR = 0
                            d.promoEnd = Cal.addDays(dice.int(500) - 100, to: store.today)
                        }
                        store.add(d)
                        did = "add \(d.title)"
                    }
                case 14:
                    store.updateSettings("Change strategy") { $0.strategy = dice.pick(Strategy.allCases) ?? .avalanche }
                    store.updateSettings("Reorder strategy") { $0.customOrder.shuffle(using: &dice) }
                    did = "strategy"
                case 15:
                    store.updateSettings("Change income") { settings in
                        switch dice.int(4) {
                        case 0: settings.useFixedAmount.toggle(); settings.fixedAmount = dice.money(2500); settings.fixedDay = 1 + dice.int(31)
                        case 1: if settings.incomes.count > 0 { settings.incomes.remove(at: dice.int(settings.incomes.count)) }
                        default:
                            let frequency = dice.pick(PayFrequency.allCases) ?? .weekly
                            settings.incomes.append(Income(name: "Income \(step)", amount: dice.money(1500), frequency: frequency,
                                                           nextPayday: Cal.addDays(dice.int(25), to: AppClock.today),
                                                           monthDays: frequency == .monthly ? [1 + dice.int(31), 1 + dice.int(31)] : []))
                        }
                    }
                    did = "income"
                default:
                    AppClock.override = Cal.addDays(dice.int(24), to: AppClock.today)
                    store.refreshForToday()
                    did = "to \(Fmt.isoDay(AppClock.today))"
                }
                try consistent(store, "seed \(seed) step \(step) (\(did))", thorough: step % 4 == 0)
                // Whatever was just done can be taken back and put back, exactly.
                if store.undoLabel != nil, dice.int(5) == 0 {
                    let before = store.data
                    store.undoLast()
                    try consistent(store, "seed \(seed) step \(step) after undo of (\(did))")
                    store.redo()
                    #expect(store.data.debts == before.debts && store.data.payments == before.payments && store.data.settings == before.settings,
                            "seed \(seed) step \(step): undo then redo of (\(did)) is not where it started")
                }
            }
        }
    }

    /// The plan the way it was first written: one day at a time, with the system calendar. Slow, and
    /// kept only to check the fast one against.
    private func dayByDay(_ debts: [Debt], today: Date, first: Date, frequency: PayFrequency, perPayday: Double, strategy: Strategy,
                          order: [UUID], promoMinimumOnly: Bool) -> (interest: Double, finished: Bool, paydays: [UUID: Date]) {
        struct W {
            var debt: Debt
            var accrued = 0.0
            var due: Date?
            var installments: [Date]
            var firstDueLeft: Double?
            var owed: Double { debt.balance + accrued }
        }
        var work: [W] = debts.filter { !$0.isPaidOff }.map { d in
            var w = W(debt: d, due: d.kind == .payLater ? nil : d.nextUnpaidDue(), installments: d.remainingInstallmentDates)
            if d.kind == .loan, let due = w.due {
                let last = d.paidThrough ?? Cal.date(inMonthOf: due, monthOffset: -1, day: d.dueDay)
                let days = min(max(0, Cal.days(from: last, to: today)), 366)
                w.accrued = max(0, d.balance * d.apr(on: today) / 36500 * Double(days) - (d.interestTowardDue ?? 0))
            }
            if (d.paidTowardDue ?? 0) > 0 { w.firstDueLeft = d.scheduledPayment(on: today) }
            return w
        }
        let paydays = PaydaySequence(first: first, frequency: frequency).starting(onOrAfter: today)
        var day = today, index = 0, total = 0.0
        var paid: [UUID: Date] = [:]
        func owed() -> Double { work.reduce(0) { $0 + $1.owed } }
        func pay(_ i: Int, _ amount: Double) {
            let part = min(amount, work[i].accrued)
            work[i].accrued -= part
            work[i].debt.balance -= amount - part
        }
        var lowest = owed(), lowDay = today
        while owed() > 0.005 && index < 3000 {
            let payday = paydays.date(index), next = paydays.date(index + 1)
            while day < payday {
                for i in work.indices where work[i].debt.balance > 0 {
                    let rate = work[i].debt.apr(on: day)
                    guard rate > 0 else { continue }
                    let interest = work[i].debt.balance * rate / 36500
                    if work[i].debt.kind == .loan { work[i].accrued += interest } else { work[i].debt.balance += interest }
                    total += interest
                }
                day = Cal.addDays(1, to: day)
            }
            var pot = perPayday
            for i in work.indices where work[i].owed > 0.005 {
                var sum = 0.0
                func amount() -> Double {
                    defer { work[i].firstDueLeft = nil }
                    return work[i].firstDueLeft ?? work[i].debt.minimum
                }
                var dues = 0.0
                if work[i].debt.kind == .payLater {
                    while let f = work[i].installments.first, f < next {
                        sum += amount()
                        work[i].installments.removeFirst()
                    }
                    if sum > 0 { dues = work[i].installments.isEmpty ? work[i].owed : min(sum, work[i].owed) }
                } else {
                    while let d = work[i].due, d < next {
                        sum += amount()
                        work[i].due = Cal.nextDue(day: work[i].debt.dueDay, onOrAfter: Cal.addDays(1, to: d))
                    }
                    dues = min(sum, work[i].owed)
                }
                let amountPaid = min(dues, work[i].owed, pot)
                guard amountPaid > 0 else { continue }
                pay(i, amountPaid)
                pot -= amountPaid
            }
            let queue = PayoffEngine.extraQueue(work.map(\.debt), strategy: strategy, customOrder: order, promoMinimumOnly: promoMinimumOnly, on: payday)
            for target in queue {
                guard pot > 0.005, let i = work.firstIndex(where: { $0.debt.id == target.id }) else { continue }
                let amountPaid = min(pot, work[i].owed)
                pay(i, amountPaid)
                pot -= amountPaid
            }
            for i in work.indices where work[i].owed <= 0.005 && paid[work[i].debt.id] == nil {
                work[i].debt.balance = 0
                work[i].accrued = 0
                paid[work[i].debt.id] = payday
            }
            index += 1
            let now = owed()
            if now < lowest - 0.005 {
                lowest = now
                lowDay = payday
            } else if Cal.days(from: lowDay, to: payday) > 366 {
                break
            }
        }
        return (total, owed() <= 0.005, paid)
    }

    @Test func theFastPlanAgreesWithTheDayByDayOne() throws {
        // 160 made-up situations: balances, rates, due days, promos that end partway, part-paid
        // minimums, pay-later plans on every rhythm, each on a random payday schedule and strategy.
        var dice = Dice(state: 2026)
        var finishedCount = 0
        for round in 0..<160 {
            var debts = demo.debts.filter { _ in dice.int(4) != 0 }
            for i in debts.indices {
                var d = debts[i]
                d.dueDay = 1 + dice.int(31)
                d.apr = Double(dice.int(3400)) / 100
                d.minimum = dice.money(350) + 15
                d.balance = dice.int(9) == 0 ? 0 : dice.money(d.kind == .loan ? 20000 : 6000) + 1
                switch d.kind {
                case .card:
                    if dice.int(3) == 0 {
                        d.promoAPR = Double(dice.int(600)) / 100
                        d.promoEnd = Cal.addDays(dice.int(700) - 60, to: today)
                    } else {
                        d.promoAPR = nil
                        d.promoEnd = nil
                    }
                    d.paidThrough = dice.pick([nil, Cal.date(inMonthOf: today, monthOffset: -1, day: d.dueDay), Cal.date(inMonthOf: today, monthOffset: 0, day: d.dueDay)]) ?? nil
                    if dice.int(5) == 0 { d.paidTowardDue = min(d.minimum, d.balance) / 2 }
                case .loan:
                    d.paidThrough = dice.pick([nil, Cal.date(inMonthOf: today, monthOffset: -1, day: d.dueDay)]) ?? nil
                case .payLater:
                    let count = 2 + dice.int(11), done = dice.int(count)
                    d.installments = count
                    d.paidInstallments = done
                    d.every = dice.pick(InstallmentEvery.allCases)
                    d.nextDue = Cal.addDays(dice.int(50) - 15, to: today)
                    d.balance = (d.minimum * Double(count - done)).cents
                    d.apr = dice.int(4) == 0 ? d.apr : 0
                }
                debts[i] = d
            }
            let frequency = dice.pick(PayFrequency.allCases) ?? .biweekly
            let first = Cal.addDays(dice.int(22), to: today)
            let perPayday = dice.money(3500) + 50
            let strategy = dice.pick(Strategy.allCases) ?? .avalanche
            var order = debts.map(\.id)
            order.shuffle(using: &dice)
            let held = dice.int(2) == 0
            let fast = PayoffEngine.simulate(PlanInput(debts: debts, today: today, firstPayday: first, frequency: frequency, perPayday: perPayday,
                                                       strategy: strategy, customOrder: order, promoMinimumOnly: held))
            let slow = dayByDay(debts, today: today, first: first, frequency: frequency, perPayday: perPayday, strategy: strategy, order: order,
                                promoMinimumOnly: held)
            let place = "round \(round): \(debts.count) debts, \(frequency.rawValue), \(perPayday) a payday, \(strategy.rawValue)"
            #expect(fast.finished == slow.finished, "\(place)")
            guard fast.finished, slow.finished else { continue }
            finishedCount += 1
            #expect(abs(fast.totalInterest - slow.interest) < 0.01, "\(place): \(fast.totalInterest) against \(slow.interest)")
            #expect(fast.payoffPayday == slow.paydays, "\(place): payoff paydays")
        }
        #expect(finishedCount > 80)                        // most of them are plans that work, so the comparison means something
    }

    // MARK: October 6, second round

    @Test func aMinimumTickedOffInsideTheNineDayWaitStillCounts() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        // Paid monthly on the 10th: one paycheck has to cover Chase's October 9 and November 9 due dates.
        store.updateSettings {
            $0.incomes = [Income(amount: 1300, frequency: .monthly, nextPayday: Cal.date(2026, 10, 10), monthDays: [10])]
            $0.buffer = 0
        }
        // $1,300.00 covers everything due before November 10 and leaves a little extra, which goes to Chase.
        let split = PayoffEngine.split(amount: 1300, debts: store.data.debts, settings: store.settings, today: today)
        #expect(split.shortBy == 0 && split.lines.contains { $0.isExtra && $0.debtID == chase.id })
        let scheduled = split.lines.filter { $0.debtID == chase.id && !$0.isExtra }
        #expect(scheduled.map(\.dueDate) == [Cal.date(2026, 10, 9), Cal.date(2026, 11, 9)])
        // The second one falls inside the nine days after the first is met, and the split says so.
        #expect(scheduled.last?.detail.contains("pay from Oct 18") == true)

        store.apply(split, paid: Set(split.lines.map(\.id)))
        let minimums = store.activity(for: chase.id).filter { $0.date == today && $0.kind == .minimum }
        // Both were ticked off as minimums, so both count: neither is recorded as an extra payment.
        #expect(minimums.count == 2)
        #expect(minimums.allSatisfy { $0.scheduled == true && $0.amount == 35 })
        #expect(store.debt(chase.id)?.paidThrough == Cal.date(2026, 11, 9))
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 12, 9))

        // Taking the first one back leaves the other still counting as a minimum, now for October 9.
        store.undo(try #require(minimums.last).id)
        let left = store.activity(for: chase.id).filter { $0.date == today && $0.kind == .minimum }
        #expect(left.count == 1)
        #expect(store.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 11, 9))

        // A payment made on its own inside the wait is still what it was before: extra.
        let alone = AppStore(data: demo, persists: false)
        alone.pay(chase.id, amount: 35)
        alone.pay(chase.id, amount: 35)
        #expect(alone.activity(for: chase.id).prefix(2).map(\.kind) == [.extra, .minimum])
        #expect(alone.debt(chase.id)?.nextUnpaidDue() == Cal.date(2026, 11, 9))
    }

    @Test func balanceChangesAndCheckInsCanBeEdited() throws {
        let store = AppStore(data: demo, persists: false)
        let chase = try debt("Chase")
        store.checkIn([.init(debtID: chase.id, balance: 1268.40, minimum: nil, interest: 27.90)])
        store.pay(chase.id, amount: 35)
        #expect(store.debt(chase.id)?.balance == 1233.40)
        let checkIn = try #require(store.activity(for: chase.id).first { $0.kind == .statement })
        #expect(store.editBlocker(checkIn) == nil)

        // The statement actually said $1,280.00, with $30.00 of interest.
        store.edit(checkIn.id, balance: 1280, interest: 30, date: today)
        var entry = try #require(store.activity(for: chase.id).first { $0.kind == .statement })
        #expect(entry.amount == 39.50 && entry.balanceAfter == 1280 && entry.interest == 30)
        // The payment after it is applied again on top, and is still the minimum it was.
        #expect(store.debt(chase.id)?.balance == 1245)
        #expect(store.activity(for: chase.id).first?.kind == .minimum)
        #expect(store.debt(chase.id)?.startingBalance == chase.startingBalance + 39.50)
        #expect(store.undoLabel == "Edit Chase statement check-in")
        // October's statement shows the new figure, on top of the interest in the loan payment already made.
        let loanInterest = try #require(AppStore(data: demo, persists: false).statement(for: today)).interest
        #expect(store.statement(for: today)?.interest == (loanInterest + 30).cents)
        store.undoLast()
        #expect(store.debt(chase.id)?.balance == 1233.40)
        store.redo()

        // Its day can change too. Moved to October 2 it is still this month's check-in.
        store.edit(checkIn.id, balance: 1280, interest: 30, date: Cal.date(2026, 10, 2))
        entry = try #require(store.activity(for: chase.id).first { $0.kind == .statement })
        #expect(entry.date == Cal.date(2026, 10, 2) && entry.balanceAfter == 1280)
        #expect(store.debt(chase.id)?.balance == 1245)
        #expect(!store.awaitingCheckIn.contains { $0.id == chase.id })
        // The wrong kind of edit does nothing: a check-in has no "amount" to change.
        store.edit(checkIn.id, amount: 5, date: today)
        #expect(store.debt(chase.id)?.balance == 1245)

        // A balance corrected by hand can be corrected again.
        var amex = try debt("American Express")
        amex.balance = 800
        store.save(amex)
        let change = try #require(store.activity(for: amex.id).first)
        #expect(change.kind == .adjustment && change.amount == 39.80)
        store.edit(change.id, balance: 790, interest: nil, date: today)
        #expect(store.debt(amex.id)?.balance == 790)
        #expect(store.activity(for: amex.id).first?.amount == 29.80)
        // $0.00 is a real balance: the card is then paid off.
        store.edit(change.id, balance: 0, interest: nil, date: today)
        #expect(store.debt(amex.id)?.isPaidOff == true)
        #expect(store.debt(amex.id)?.paidOffAt == today)
        // Set back to what it was before the change, the entry has nothing left to say and goes.
        let entries = store.activity(for: amex.id).count
        store.edit(change.id, balance: 760.20, interest: nil, date: today)
        #expect(store.debt(amex.id)?.balance == 760.20)
        #expect(store.activity(for: amex.id).count == entries - 1)
        // Only the entries that mark a debt being added or deleted cannot be changed.
        #expect(store.editBlocker(try #require(store.activity(for: chase.id).last)) != nil)
    }

    @Test func insightsUseRecordedInterestOnceAMonthHasACheckIn() throws {
        let store = AppStore(data: demo, persists: false)
        let september = Cal.date(2026, 9, 1)
        // No check-in in September: Insights estimates, and its figure is more than the statement recorded.
        let estimate = store.interest(inMonth: september)
        let recorded = try #require(store.statement(for: september)).interest
        #expect(!estimate.isRecorded)
        #expect(estimate.amount > recorded)

        // Check Chase in, then say that statement was dated September 28.
        let chase = try debt("Chase")
        store.checkIn([.init(debtID: chase.id, balance: 1268.40, minimum: nil, interest: 27.90)])
        let entry = try #require(store.activity(for: chase.id).first)
        store.edit(entry.id, balance: 1268.40, interest: 27.90, date: Cal.date(2026, 9, 28))
        let statement = try #require(store.statement(for: september))
        #expect(statement.hasCheckIn)
        #expect(statement.interest == (recorded + 27.90).cents)
        // Now the two screens show the same number.
        let after = store.interest(inMonth: september)
        #expect(after.isRecorded)
        #expect(after.amount == statement.interest)
        // Every statement adds up: start, less paid, plus charges, interest and anything else, is the end.
        for month in store.statements {
            #expect((month.opening - month.paid + month.charged + month.interest + month.other).cents == month.closing)
        }
    }

    @Test func theCheckInReminderComesOnceAMonth() throws {
        var data = demo
        #expect(!PlanSettings().remindCheckIn && PlanSettings().checkInDay == 1)       // off unless turned on
        data.settings.checkInDay = 31
        var reminders = Reminders.checkIns(for: data, today: today)
        // The last day of each month, however long it is.
        #expect(reminders.map(\.day) == [Day(2026, 10, 31), Day(2026, 11, 30), Day(2026, 12, 31)])
        #expect(reminders.first?.body.contains("5 cards") == true)

        // Once every card has been checked in this month, this month's reminder is dropped.
        let store = AppStore(data: data, persists: false)
        store.checkIn(store.awaitingCheckIn.map { .init(debtID: $0.id, balance: $0.balance, minimum: nil, interest: nil) })
        reminders = Reminders.checkIns(for: store.data, today: today)
        #expect(reminders.map(\.day) == [Day(2026, 11, 30), Day(2026, 12, 31)])

        // With one card it is named; with no card left to pay there is nothing to remind about.
        data.debts.removeAll { $0.kind == .card && $0.title != "Chase" }
        #expect(Reminders.checkIns(for: data, today: today).first?.body.contains("Chase statement") == true)
        data.debts.removeAll { $0.kind == .card }
        #expect(Reminders.checkIns(for: data, today: today).isEmpty)
        // The day survives a round trip and a damaged file.
        data.settings.checkInDay = 99
        data.settings.remindCheckIn = true
        let back = try Persistence.read(Persistence.contents(of: data))
        #expect(back.settings.remindCheckIn && back.settings.checkInDay == 31)
    }

    @Test func utilizationIsKeptMonthByMonth() throws {
        let store = AppStore(data: demo, persists: false)
        let months = store.utilizationMonths
        #expect(months.map { Fmt.monthNameYear($0.month) }
                == ["March 2026", "April 2026", "May 2026", "June 2026", "July 2026", "August 2026", "September 2026", "October 2026"])
        #expect(months.first?.change == nil)
        #expect(months.last?.isCurrent == true)
        #expect(months.last?.share == store.utilization)
        // Each month's change is measured from the month before it.
        for (earlier, later) in zip(months, months.dropFirst()) {
            #expect(abs(try #require(later.change) - (later.share - earlier.share)) < 1e-12)
        }
        // Six months of minimums and no new charges: down every month from April to September.
        #expect(months[1...6].allSatisfy { ($0.change ?? 0) < 0 })
        // Each month the five minimums ($247.00) came off $19,500.00 of limits.
        #expect(abs(try #require(months[3].change) + 247.0 / 19500) < 1e-9)
        #expect(months.last?.change == 0)                   // nothing paid on a card yet in October
        // $8,774.75 owed; 30% of $19,500.00 is $5,850.00.
        #expect(store.toReachThirtyPercent == 2924.75)
        #expect(store.creditLimit == 19500)
        let chase = try debt("Chase")
        #expect(store.utilization(of: chase, on: Cal.date(2026, 8, 31)) == 1275.50 / 3000)
        #expect(store.utilization(of: chase, on: Cal.date(2026, 9, 30)) == 1240.50 / 3000)
        // A charge moves this month up, and the month list follows.
        store.charge(chase.id, amount: 300)
        #expect(abs(try #require(store.utilizationMonths.last?.change) - 300.0 / 19500) < 1e-9)
    }

    // MARK: Connected mode

    @MainActor @Test func connectedModeIsOffUntilItIsTurnedOn() async throws {
        #expect(!AppData.empty(today: today).settings.connected.isOn)
        #expect(!demo.settings.connected.isOn && demo.settings.connected.connections.isEmpty)
        // A build with no bank service shows nothing of the mode and cannot turn it on.
        let bare = AppStore(data: demo, persists: false)
        #expect(!bare.connectedAvailable)
        bare.turnOnConnected()
        #expect(!bare.connected.isOn && !bare.connectedOn)

        let store = AppStore(data: demo, persists: false)
        store.bank = SampleBank(data: { store.data }, today: { DemoData.today })
        #expect(store.connectedAvailable && !store.connectedOn)
        // With the mode off nothing connects, updates or changes.
        try await store.connectBank("Chase")
        #expect(store.connected.connections.isEmpty)
        #expect(await store.refreshBanks().entries == 0)
        #expect(store.applyBankFigures() == 0)
        #expect(store.data.payments == demo.payments)

        store.turnOnConnected()
        #expect(store.connectedOn)
        #expect(store.connected.acceptedVersion == Connected.termsVersion && store.connected.acceptedAt != nil)
        // The sample bank offers the lenders of the cards and loans that name one.
        #expect(await store.banksToOffer() == ["Chase", "Capital One", "Bank of America", "Citi", "American Express", "Federal · Dept. of Education"])
        // Turning it on is not something Undo takes back.
        #expect(store.undoLabel == nil)
    }

    @MainActor @Test func bankFiguresArriveAsEntriesAndOnlyAfterAChoice() async throws {
        let store = AppStore(data: demo, persists: false)
        let bank = SampleBank(data: { store.data }, today: { DemoData.today })
        store.bank = bank
        store.turnOnConnected()
        let chase = try debt("Chase")

        try await store.connectBank("Chase")
        var connection = try #require(store.connected.connections.first)
        var account = try #require(connection.accounts.first)
        #expect(connection.institution == "Chase" && connection.status == .connected && connection.lastUpdate != nil)
        #expect(account.debtID == chase.id && account.source == .undecided && account.isOn)
        #expect(account.name == "Freedom Unlimited" && account.mask?.count == 4)
        // The bank has charged a month of interest the app has not seen: $1,240.50 at 26.99% is $27.90.
        #expect(account.figures?.balance == 1268.40)
        // Nothing changes until the user has chosen. Both figures are shown.
        #expect(store.debt(chase.id) == chase)
        var questions = store.bankQuestions
        #expect(questions.count == 1)
        #expect(questions.first?.differences == [BankDifference(field: "Balance", mine: "$1,240.50", bank: "$1,268.40")])
        let update = await store.refreshBanks()
        #expect(update.entries == 0 && update.waiting == 1)
        #expect(store.debt(chase.id) == chase)
        #expect(store.undoLabel == nil)

        // "Keep mine": the question goes away and the debt stays as it is.
        store.follow(.mine, account: account.id, in: connection.id)
        #expect(store.bankQuestions.isEmpty)
        #expect(store.debt(chase.id) == chase)
        #expect(await store.refreshBanks().entries == 0)
        #expect(store.awaitingCheckIn.contains { $0.id == chase.id })          // still checked in by hand

        // "Use the bank's": the difference arrives as one entry, like a statement check-in.
        store.follow(.bank, account: account.id, in: connection.id)
        let entry = try #require(store.activity(for: chase.id).first)
        #expect(entry.kind == .statement && entry.bank == "Chase" && entry.amount == 27.90 && entry.interest == 27.90)
        #expect(entry.label == "Chase bank update" && entry.balanceAfter == 1268.40 && entry.termsBefore == nil)
        #expect(store.debt(chase.id)?.balance == 1268.40)
        let loanInterest = try #require(AppStore(data: demo, persists: false).statement(for: today)).interest
        #expect(store.statement(for: today)?.interest == (loanInterest + 27.90).cents)
        #expect(!store.awaitingCheckIn.contains { $0.id == chase.id })         // the bank keeps it up to date now
        #expect(store.awaitingCheckIn.count == 4)
        // Asking again changes nothing: the bank and the app agree.
        #expect(await store.refreshBanks().entries == 0)
        #expect(store.activity(for: chase.id).filter { $0.bank != nil }.count == 1)

        // The update is one step for Undo, and undoing it does not disconnect anything.
        #expect(store.undoLabel == "Bank update")
        store.undoLast()
        #expect(store.debt(chase.id) == chase)
        #expect(store.connected.connections.count == 1 && store.connectedOn)
        store.redo()
        #expect(store.debt(chase.id)?.balance == 1268.40)
        // The entry can also be taken back on its own, or edited like any check-in.
        store.edit(entry.id, balance: 1270, interest: 29.50, date: today)
        #expect(store.debt(chase.id)?.balance == 1270)
        store.undo(entry.id)
        #expect(store.debt(chase.id)?.balance == 1240.50)

        // A bank that also disagrees about the terms: every difference is listed, and the choice is one.
        let capitalOne = try debt("Capital One")
        bank.adjust = { debt, figures in
            guard debt.id == capitalOne.id else { return }
            figures.apr = 29.99
            figures.minimum = 61
            figures.creditLimit = 5000
            figures.nextDue = Day(2026, 10, 14)
        }
        try await store.connectBank("Capital One")
        questions = store.bankQuestions
        #expect(questions.first { $0.debt.id == capitalOne.id }?.differences.map(\.field)
                == ["Balance", "APR", "Minimum payment", "Due day", "Credit limit"])
        connection = try #require(store.connected.connections.last)
        account = try #require(connection.accounts.first)
        store.follow(.bank, account: account.id, in: connection.id)
        let changed = try #require(store.debt(capitalOne.id))
        #expect(changed.apr == 29.99 && changed.minimum == 61 && changed.creditLimit == 5000 && changed.dueDay == 14)
        #expect(changed.nextUnpaidDue() == Cal.date(2026, 10, 14))             // the same cycle, on its new day
        let terms = try #require(store.activity(for: capitalOne.id).first)
        #expect(terms.note == "APR 28.49% to 29.99%, minimum $58.00 to $61.00, due day 12th to 14th, limit $4,500.00 to $5,000.00")
        #expect(terms.termsBefore == capitalOne.terms)
        // Undoing that entry puts the terms back as well as the balance.
        store.undo(terms.id)
        #expect(store.debt(capitalOne.id) == capitalOne)

        // A due day of the 31st is not "different" in a month that has only 30 days.
        var late = capitalOne
        late.dueDay = 31
        let november = BankFigures(balance: late.balance, nextDue: Day(2026, 11, 30), asOf: Date())
        #expect(!november.dueDayDiffers(from: late))
        #expect(november.differences(from: late, on: today).isEmpty)
    }

    @MainActor @Test func banksCanBeDisconnectedAndStayOnThisIPhone() async throws {
        let store = AppStore(data: demo, persists: false)
        let bank = SampleBank(data: { store.data }, today: { DemoData.today })
        store.bank = bank
        store.turnOnConnected()
        try await store.connectBank("Chase")
        try await store.connectBank("Citi")
        let chase = try #require(store.connected.connections.first)
        let account = try #require(chase.accounts.first)
        store.follow(.bank, account: account.id, in: chase.id)
        #expect(store.connected.bankFedDebts.count == 1)

        // An account can be switched off, or pointed at a different debt, which asks the question again.
        store.setAccount(account.id, in: chase.id, isOn: false)
        #expect(store.connected.bankFedDebts.isEmpty)
        store.setAccount(account.id, in: chase.id, isOn: true)
        store.link(account.id, in: chase.id, to: nil)
        #expect(store.connected.connections.first?.accounts.first?.source == .undecided)
        #expect(store.debts(for: account).map(\.title).contains("Chase"))
        store.link(account.id, in: chase.id, to: try debt("Chase").id)
        store.follow(.bank, account: account.id, in: chase.id)

        // A bank that wants a new sign-in says so, and comes back once it has one.
        bank.expired = [chase.itemID]
        let update = await store.refreshBanks()
        #expect(update.problems == ["Chase wants you to sign in again"])
        #expect(store.connected.connections.first?.status == .needsSignIn)
        #expect(store.connected.bankFedDebts.isEmpty)
        bank.expired = []
        await store.refreshBanks()
        #expect(store.connected.connections.first?.status == .connected)

        // Bank sign-ins are left out of a backup, and a restored backup does not remove them.
        let backup = try Persistence.read(BackupDocument.contents(of: store.data))
        #expect(backup.settings.connected == ConnectedState())
        #expect(backup.payments.contains { $0.bank == "Chase" })              // the entries are the user's own
        store.restore(demo)
        #expect(store.connected.connections.count == 2 && store.connectedOn)

        // Disconnected, a bank stays in the list as a record until it is removed.
        try await store.disconnect(chase.id)
        let record = try #require(store.connected.connections.first)
        #expect(record.status == .disconnected && record.changedAt >= record.addedAt)
        #expect(store.connected.bankFedDebts.isEmpty)
        store.removeConnection(chase.id)
        #expect(store.connected.connections.map(\.institution) == ["Citi"])
        // A bank that is still connected cannot be removed, only disconnected.
        store.removeConnection(try #require(store.connected.connections.first).id)
        #expect(store.connected.connections.count == 1)

        // Turning the mode off disconnects everything.
        #expect(await store.turnOffConnected().isEmpty)
        #expect(!store.connected.isOn)
        #expect(store.connected.connections.allSatisfy { $0.status == .disconnected })
        #expect(await store.refreshBanks().entries == 0)
    }

    // MARK: Logo

    @MainActor @Test func theLogoDrawsAtEverySize() throws {
        for size in [29.0, 40, 60, 120, 256] as [CGFloat] {
            let mark = try #require(ImageRenderer(content: LogoMark(size: size)).uiImage)
            #expect(mark.size == CGSize(width: size, height: size))
        }
        let word = try #require(ImageRenderer(content: LogoWordmark(size: 40)).uiImage)
        // The lettering, the dot and the stroke: wider than the 170-point stroke alone, 56 points tall.
        #expect(word.size.width >= 170 && word.size.height == 56)
        let lockup = try #require(ImageRenderer(content: LogoLockup(height: 64)).uiImage)
        #expect(lockup.size.height == 64 && lockup.size.width == 64 + 18 + word.size.width)
        if let folder = ProcessInfo.processInfo.environment["APRFREE_LOGO_OUT"] {
            // For looking at them: set APRFREE_LOGO_OUT to a folder and the pictures are written there.
            let renderer = ImageRenderer(content: VStack(spacing: 24) { LogoLockup(height: 64); LogoWordmark(size: 40); LogoMark(size: 180) }.padding(24).background(Color.white))
            renderer.scale = 3
            try renderer.uiImage?.pngData()?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("logo-views.png"))
        }
        // The app icon is there in all three appearances, and its files are the square, opaque ones the App Store asks for.
        #expect(Logo.lettering == "APRfree")
    }

    // MARK: Setup

    @Test func thePolicyAndDisclaimerMustBothBeAccepted() {
        var settings = PlanSettings()
        #expect(!settings.hasAcceptedLegal)
        settings.acceptedPrivacy = Date()
        #expect(!settings.hasAcceptedLegal)
        settings.acceptedDisclaimer = Date()
        settings.acceptedLegalVersion = Legal.version
        #expect(settings.hasAcceptedLegal)
        // New wording means asking again.
        settings.acceptedLegalVersion = "2020-01-01"
        #expect(!settings.hasAcceptedLegal)
        #expect(demo.settings.hasAcceptedLegal)
        #expect(Legal.privacy.sections.count >= 8 && Legal.disclaimer.sections.count >= 8)
    }
}

// The older tests were written when there was one payday schedule. These read and write the first
// income, which is the same thing.
extension PlanSettings {
    var nextPayday: Date {
        get { incomes.first?.nextPayday ?? AppClock.today }
        set { if !incomes.isEmpty { incomes[0].nextPayday = newValue } }
    }
    var paydayAnchorDay: Int? { incomes.first.flatMap { $0.frequency == .monthly ? $0.payDays.first : nil } }

    var payAmount: Double {
        get { incomes.first?.amount ?? 0 }
        set { if incomes.isEmpty { incomes = [Income(amount: newValue, nextPayday: AppClock.today)] } else { incomes[0].amount = newValue } }
    }

    var payFrequency: PayFrequency {
        get { incomes.first?.frequency ?? .biweekly }
        set {
            guard !incomes.isEmpty else { return }
            incomes[0].frequency = newValue
            incomes[0].monthDays = newValue == .monthly ? [Cal.day(of: incomes[0].nextPayday)] : []
        }
    }

    mutating func setNextPayday(_ date: Date) {
        guard !incomes.isEmpty else { return }
        incomes[0].nextPayday = date
        if incomes[0].frequency == .monthly { incomes[0].monthDays = [Cal.day(of: date)] }
    }

    struct Paydays {
        let days: [Date]
        func date(_ index: Int) -> Date { days[index] }
    }

    func paydays(from today: Date) -> Paydays {
        Paydays(days: schedule(today: today).events(from: Day(today), count: 8).map(\.day.date))
    }
}

extension AppStore {
    /// What is left for debt out of the next paycheck.
    var perPayday: Double { upcomingPaydays(1).first?.net ?? 0 }
}
