import Foundation
import Testing
@testable import ChirograCore

@Suite("Exportación CSV")
struct CSVExportTests {
    let bank = LedgerAccount(id: UUID(), code: "1010", name: "Banco", subtype: .bank)
    let ap = LedgerAccount(id: UUID(), code: "2000", name: "Cuentas por pagar", subtype: .accountsPayable)
    let capital = LedgerAccount(id: UUID(), code: "3000", name: "Capital", subtype: .ownersEquity)
    let sales = LedgerAccount(id: UUID(), code: "4000", name: "Ventas, servicios", subtype: .sales)
    let rent = LedgerAccount(id: UUID(), code: "6400", name: "Alquiler", subtype: .operatingExpense)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    var accounts: [LedgerAccount] { [bank, ap, capital, sales, rent] }
    func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }
    var lines: [LedgerLine] {
        [
            LedgerLine(accountID: bank.id, date: day(1), debit: 1_000_000, credit: 0),
            LedgerLine(accountID: capital.id, date: day(1), debit: 0, credit: 1_000_000),
            LedgerLine(accountID: bank.id, date: day(5), debit: 125_050, credit: 0),
            LedgerLine(accountID: sales.id, date: day(5), debit: 0, credit: 125_050),
            LedgerLine(accountID: rent.id, date: day(9), debit: 120_000, credit: 0),
            LedgerLine(accountID: ap.id, date: day(9), debit: 0, credit: 120_000),
        ]
    }

    @Test("Importes con dos decimales y signo")
    func amounts() {
        #expect(CSVExport.amount(125_050) == "1250.50")
        #expect(CSVExport.amount(5) == "0.05")
        #expect(CSVExport.amount(-1_840) == "-18.40")
        #expect(CSVExport.amount(0) == "0.00")
    }

    @Test("El balance general exporta el balance, no la balanza de comprobación")
    func balanceSheetIsNotTrialBalance() {
        let report = ReportBuilder.balanceSheet(accounts: accounts, lines: lines, asOf: day(31))
        let csv = CSVExport.balanceSheet(report, calendar: calendar)
        #expect(csv.hasPrefix("Balance general\n"))
        #expect(csv.contains("Al,2026-10-31"))
        #expect(csv.contains("Total activos,,11250.50"))
        #expect(csv.contains("Total pasivo + patrimonio,,11250.50"))
        #expect(!csv.contains("Debe"))
        #expect(csv != CSVExport.trialBalance(ReportBuilder.trialBalance(accounts: accounts, lines: lines, asOf: day(31)), calendar: calendar))
    }

    @Test("El plan de cuentas lleva tipo, tipo de detalle y saldo")
    func chartOfAccounts() {
        let csv = CSVExport.chartOfAccounts([("1010", "Banco, corriente", "Activos", "Banco", 125_050)], asOf: day(31), calendar: calendar)
        #expect(csv.contains("Al,2026-10-31"))
        #expect(csv.contains("Código,Cuenta,Tipo,Tipo de detalle,Saldo"))
        #expect(csv.contains("1010,\"Banco, corriente\",Activos,Banco,1250.50"))
    }

    @Test("La balanza lleva Debe y Haber con totales iguales")
    func trialBalance() {
        let csv = CSVExport.trialBalance(ReportBuilder.trialBalance(accounts: accounts, lines: lines, asOf: day(31)), calendar: calendar)
        #expect(csv.contains("Código,Cuenta,Debe,Haber"))
        #expect(csv.contains("Totales,,12450.50,12450.50"))
    }

    @Test("Estado de resultados con periodo, secciones, comillas y comparativo")
    func incomeStatement() {
        let current = ReportBuilder.incomeStatement(accounts: accounts, lines: lines, from: day(1), to: day(31))
        let empty = ReportBuilder.incomeStatement(accounts: accounts, lines: [], from: day(1), to: day(31))
        let csv = CSVExport.incomeStatement(current, previous: empty, calendar: calendar)
        #expect(csv.contains("Periodo,2026-10-01,2026-10-31"))
        #expect(csv.contains("Cuenta,Actual,Anterior"))
        #expect(csv.contains("\"  Ventas, servicios\",1250.50,0.00"))
        #expect(csv.contains("Ganancia neta,50.50,0.00"))
    }

    @Test("El comparativo incluye cuentas que solo tienen saldo en el periodo anterior")
    func previousOnlyAccounts() {
        let current = ReportBuilder.incomeStatement(accounts: accounts, lines: [], from: day(1), to: day(31))
        let previous = ReportBuilder.incomeStatement(accounts: accounts, lines: lines, from: day(1), to: day(31))
        let csv = CSVExport.incomeStatement(current, previous: previous, calendar: calendar)
        #expect(csv.contains("  Alquiler,0.00,1200.00"))
    }

    @Test("El libro mayor exporta saldo inicial, movimientos con saldo acumulado y saldo final")
    func accountLedger() {
        let deposit = LedgerMovement(date: day(5), memo: "Cobro F-1001, Café", debit: 125_050, credit: 0)
        let rentPaid = LedgerMovement(date: day(9), memo: "Renta", debit: 0, credit: 120_000)
        let opening = LedgerMovement(date: day(1), memo: "Saldos iniciales", debit: 1_000_000, credit: 0)
        let ledger = ReportBuilder.accountLedger(account: bank, movements: [opening, deposit, rentPaid], from: day(2), to: day(31))
        let rows = CSVExport.accountLedger(ledger, kinds: [deposit.id: "Cobro"], calendar: calendar)
            .split(separator: "\n").map(String.init)
        #expect(rows.contains(",,Saldo inicial,,,10000.00"))
        #expect(rows.contains("2026-10-05,Cobro,\"Cobro F-1001, Café\",1250.50,,11250.50"))
        #expect(rows.contains("2026-10-09,,Renta,,1200.00,10050.50"))
        #expect(rows.last == ",,Saldo final,1250.50,1200.00,10050.50")
    }
}
