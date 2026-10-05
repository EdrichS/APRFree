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
        let avalanche = plan(.avalanche), snowball = plan(.snowball), highest = plan(.highestBalance), custom = plan(.custom)
        #expect(avalanche.totalInterest.cents == 2018.62)
        #expect(snowball.totalInterest.cents == 2025.76)
        #expect(highest.totalInterest.cents == 3226.98)
        #expect(custom.totalInterest.cents == 2020.89)
        for result in [avalanche, snowball, custom] {
            #expect(result.finished)
            #expect(result.debtFree == Cal.date(2028, 4, 1))
            #expect(result.finalPayday == Cal.date(2028, 3, 24))
        }
        #expect(highest.finished)
        #expect(highest.debtFree == Cal.date(2028, 5, 1))
        #expect(highest.finalPayday == Cal.date(2028, 4, 7))
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
        #expect(highest.payoffPayday[try debt("Capital One").id] == Cal.date(2027, 12, 17))
        #expect(snowball.payoffPayday[try debt("American Express").id] == Cal.date(2026, 10, 23))
    }

    @Test func theFourStrategiesRankAsTheySay() throws {
        let debts = demo.debts.filter { $0.kind != .payLater }
        func order(_ strategy: Strategy) -> [String] {
            PayoffEngine.priority(debts, strategy: strategy, customOrder: demo.settings.customOrder, on: today).map(\.title)
        }
        // Avalanche: by rate. Citi's promo makes it 0% today.
        #expect(order(.avalanche) == ["Capital One", "Chase", "American Express", "Bank of America", "Auto loan", "Student loan", "Citi"])
        // Snowball: by balance, smallest first.
        #expect(order(.snowball) == ["American Express", "Chase", "Citi", "Capital One", "Bank of America", "Auto loan", "Student loan"])
        // Highest Balance: by the dollars of interest charged in a month (balance x APR / 12).
        #expect(order(.highestBalance) == ["Student loan", "Auto loan", "Bank of America", "Capital One", "Chase", "American Express", "Citi"])
        #expect(PayoffEngine.priority(debts, strategy: .highestBalance, customOrder: [], on: today)
            .map { $0.monthlyInterest(on: today).cents } == [84.79, 81.65, 59.50, 47.92, 27.90, 15.51, 0])
        #expect(order(.custom) == ["Chase", "Capital One", "Citi", "American Express", "Bank of America", "Auto loan", "Student loan"])
        #expect(Strategy.allCases.map(\.title) == ["Avalanche", "Snowball", "Highest Balance", "Custom"])

        // A big balance at 20% against a small one at 30%: the two strategies disagree, as intended.
        let big = Debt(kind: .card, provider: "Big", name: "", brand: "other", balance: 10000, apr: 20, minimum: 200, addedAt: today, startingBalance: 10000)
        let small = Debt(kind: .card, provider: "Small", name: "", brand: "other", balance: 500, apr: 30, minimum: 25, addedAt: today, startingBalance: 500)
        #expect(PayoffEngine.priority([small, big], strategy: .highestBalance, customOrder: [], on: today).map(\.provider) == ["Big", "Small"])
        #expect(PayoffEngine.priority([big, small], strategy: .avalanche, customOrder: [], on: today).map(\.provider) == ["Small", "Big"])

        // The first extra dollars follow the strategy.
        func firstExtra(_ strategy: Strategy) -> String? {
            var settings = demo.settings
            settings.strategy = strategy
            return PayoffEngine.split(amount: 1200, debts: demo.debts, settings: settings, today: today).lines.first(where: \.isExtra)?.title
        }
        #expect(Strategy.allCases.map(firstExtra) == ["Capital One", "American Express", "Student loan", "Chase"])
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
        func cost(_ strategy: Strategy) -> PlanResult {
            PayoffEngine.simulate(PlanInput(debts: [big, small], today: today, firstPayday: Cal.date(2026, 10, 9), frequency: .monthly,
                                            perPayday: 600, strategy: strategy, customOrder: [], promoMinimumOnly: true))
        }
        let byRate = cost(.avalanche), byDollars = cost(.highestBalance)
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
        #expect(dearest > plan(.highestBalance).totalInterest)   // Highest Balance is costly, but not the worst possible order
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
        // Interest still to come on the plan, strategy by strategy (independent model: 50.61, 27.35, 383.89, 14.77).
        var expected: [Strategy: Double] = [.avalanche: 50.61, .snowball: 27.35, .highestBalance: 383.89, .custom: 14.77]
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
        store.apply(split.lines, allPaid: true, nextPayday: split.nextPayday)
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
        #expect(snapshot.total.nextDue == Cal.date(2026, 10, 9))
        #expect(snapshot.total.nextDueNames == "Chase, Citi")
        #expect(snapshot.cards.nextDueNames == "Chase, Citi")
        #expect(snapshot.loans.nextDue == Cal.date(2026, 10, 15))
        #expect(snapshot.loans.nextDueNames == "Auto loan")
        #expect(snapshot.cards.free == Cal.date(2027, 12, 9))
        #expect(snapshot.loans.free == Cal.date(2028, 4, 1))
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
        #expect(store.upcomingPaydays(3) == [Cal.date(2027, 2, 28), Cal.date(2027, 3, 31), Cal.date(2027, 4, 30)])
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
        #expect(store.upcomingPaydays(3) == [Cal.date(2027, 5, 15), Cal.date(2027, 6, 15), Cal.date(2027, 7, 15)])
        AppClock.override = DemoData.today
    }

    @Test func removedPayScheduleStillLoads() throws {
        // "Twice a month" is no longer offered. Data saved with it must still open.
        var raw = String(decoding: try Persistence.encoder.encode(demo), as: UTF8.self)
        #expect(raw.contains("\"payFrequency\" : \"biweekly\""))
        raw = raw.replacingOccurrences(of: "\"payFrequency\" : \"biweekly\"", with: "\"payFrequency\" : \"semimonthly\"")
        let loaded = try Persistence.decoder.decode(AppData.self, from: Data(raw.utf8))
        #expect(loaded.settings.payFrequency == .biweekly)
        #expect(loaded.debts.count == 9)
        #expect(PayFrequency.allCases.map(\.title) == ["Weekly", "Every 2 weeks", "Monthly"])
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
        #expect(store.widgetSnapshot == WidgetSnapshot(total: .empty, cards: .empty, loans: .empty, zone: Cal.zone.identifier))
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

    @Test func savedDatesKeepTheirDayInAnotherTimeZone() throws {
        // A file written somewhere else, far enough away that midnight there is another day here.
        let there = try #require(TimeZone(identifier: Cal.zone.identifier == "Pacific/Auckland" ? "America/Los_Angeles" : "Pacific/Auckland"))
        var away = Calendar(identifier: .gregorian)
        away.timeZone = there
        func day(_ y: Int, _ m: Int, _ d: Int) throws -> Date { try #require(away.date(from: DateComponents(year: y, month: m, day: d))) }

        var card = Debt(kind: .card, provider: "Chase", name: "", brand: "chase", balance: 1000, apr: 20, dueDay: 9, minimum: 35,
                        addedAt: try day(2026, 9, 1), startingBalance: 1000)
        card.paidThrough = try day(2026, 10, 9)
        let plan = Debt(kind: .payLater, provider: "Klarna", name: "", brand: "klarna", balance: 100, apr: 0, minimum: 25,
                        total: 100, installments: 4, paidInstallments: 0, every: .biweekly, nextDue: try day(2026, 10, 12),
                        addedAt: try day(2026, 9, 1), startingBalance: 100)
        var written = AppData(debts: [card, plan], settings: PlanSettings(payFrequency: .weekly, nextPayday: try day(2026, 10, 9)))
        written.history = [BalancePoint(date: try day(2026, 10, 4), total: 1100, cards: 1000, loans: 0)]
        written.timeZone = there.identifier

        let read = try Persistence.read(try Persistence.encoder.encode(written))
        #expect(read.timeZone == nil)
        // Every date is the same calendar day here as it was there.
        #expect(read.settings.nextPayday == Cal.date(2026, 10, 9))
        #expect(read.settings.paydays(from: Cal.date(2026, 10, 10)).date(0) == Cal.date(2026, 10, 16))
        #expect(read.debts[0].paidThrough == Cal.date(2026, 10, 9))
        #expect(read.debts[0].nextUnpaidDue() == Cal.date(2026, 11, 9))
        #expect(read.debts[1].nextDue == Cal.date(2026, 10, 12))
        #expect(read.history[0].date == Cal.date(2026, 10, 4))
        // Read plainly, without the move, the met due date lands on another day: the bug this prevents.
        let plain = try Persistence.decoder.decode(AppData.self, from: try Persistence.encoder.encode(written))
        #expect(Cal.startOfDay(try #require(plain.debts[0].paidThrough)) != Cal.date(2026, 10, 9))

        // Files from this time zone, and older files with no time zone at all, are left exactly as they are.
        #expect(try Persistence.read(try Persistence.encoder.encode(demo)) == demo)
        let stamped = try Persistence.contents(of: demo)
        #expect(try Persistence.decoder.decode(AppData.self, from: stamped).timeZone == Cal.zone.identifier)
        #expect(try Persistence.read(stamped) == demo)

        // A moved date keeps its time of day too.
        let afternoon = try #require(away.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15, minute: 30)))
        let moved = Cal.rebase(afternoon, from: there, to: Cal.zone)
        #expect(Cal.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moved)
                == DateComponents(year: 2026, month: 10, day: 9, hour: 15, minute: 30))
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
        bad.settings.payAmount = -100
        bad.settings.buffer = 1e15
        bad.settings.paydayAnchorDay = 40

        let read = try Persistence.read(try Persistence.encoder.encode(bad))
        #expect(read.debts[0].balance == 0)
        #expect(read.debts[0].apr == Limits.percent)
        #expect(read.debts[0].dueDay == 31)
        #expect(read.debts[0].minimum == 0)
        #expect(read.debts[k].installments == Limits.installments)
        #expect(read.debts[k].paidInstallments == 0)
        #expect(read.debts[k].remainingInstallmentDates.count == Limits.installments)
        #expect(read.settings.payAmount == 0)
        #expect(read.settings.buffer == Limits.money)
        #expect(read.settings.paydayAnchorDay == 31)
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

        // A long list of debts runs onto more pages of the summary instead of being cut off.
        var many = demo
        for i in 0..<40 {
            many.debts.append(Debt(kind: .card, provider: "Bank \(i)", name: "", brand: "other", balance: 100, apr: 20, dueDay: 5,
                                   minimum: 25, addedAt: today, startingBalance: 100))
        }
        func pages(_ data: AppData) throws -> Int {
            let pdf = Exporter.pdf(data: data, plan: PayoffEngine.simulate(AppStore(data: data, persists: false).planInput()),
                                   strategy: "Avalanche", today: today)
            let provider = try #require(CGDataProvider(data: pdf as CFData))
            return try #require(CGPDFDocument(provider)).numberOfPages
        }
        #expect(try pages(demo) == 1)
        #expect(try pages(many) == 3)                      // 49 debts: 14 on the first page, 19 on each one after
    }
}
