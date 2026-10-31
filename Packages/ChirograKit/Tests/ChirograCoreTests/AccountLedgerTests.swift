import Foundation
import Testing
@testable import ChirograCore

@Suite("Libro mayor por cuenta")
struct AccountLedgerTests {
    let calendar = Calendar(identifier: .gregorian)
    func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }

    @Test("En una cuenta de ingreso el crédito aumenta el saldo y el débito lo reduce")
    func incomeCreditIncreases() {
        let sales = LedgerAccount(id: UUID(), code: "4000", name: "Ventas", subtype: .sales)
        let ledger = ReportBuilder.accountLedger(account: sales, movements: [
            LedgerMovement(date: day(1), debit: 0, credit: 50_000),
            LedgerMovement(date: day(2), debit: 10_000, credit: 0),
        ])
        #expect(ledger.rows.map(\.effect) == [50_000, -10_000])
        #expect(ledger.rows.map(\.increasesBalance) == [true, false])
        #expect(ledger.closingBalance == 40_000)
    }

    @Test("En pasivo y patrimonio el crédito es positivo; en activo y gasto, el débito",
          arguments: [AccountSubtype.accountsPayable, .salesTaxPayable, .ownersEquity, .bank, .operatingExpense])
    func signFollowsNormalBalance(subtype: AccountSubtype) {
        let account = LedgerAccount(id: UUID(), code: "X", name: "X", subtype: subtype)
        let ledger = ReportBuilder.accountLedger(account: account, movements: [LedgerMovement(date: day(1), debit: 0, credit: 1_000)])
        #expect(ledger.rows[0].increasesBalance == (subtype.accountType.normalBalance == .credit))
    }

    @Test("El filtro de fechas lleva lo anterior al saldo inicial y conserva el saldo acumulado")
    func dateRange() {
        let bank = LedgerAccount(id: UUID(), code: "1010", name: "Banco", subtype: .bank)
        let movements = [
            LedgerMovement(date: day(1), debit: 100_000, credit: 0),
            LedgerMovement(date: day(10), debit: 0, credit: 30_000),
            LedgerMovement(date: day(20), debit: 5_000, credit: 0),
            LedgerMovement(date: day(30), debit: 0, credit: 1_000),
        ]
        let ledger = ReportBuilder.accountLedger(account: bank, movements: movements, from: day(5), to: day(25))
        #expect(ledger.openingBalance == 100_000)
        #expect(ledger.rows.map(\.balance) == [70_000, 75_000])
        #expect(ledger.closingBalance == 75_000)
        #expect(ledger.totalDebit == 5_000)
        #expect(ledger.totalCredit == 30_000)
    }
}
