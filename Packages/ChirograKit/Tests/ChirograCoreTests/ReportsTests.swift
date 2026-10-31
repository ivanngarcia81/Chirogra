import Foundation
import Testing
@testable import ChirograCore

@Suite("Reportes")
struct ReportsTests {
    let bank = LedgerAccount(id: UUID(), code: "1010", name: "Banco", subtype: .bank)
    let ar = LedgerAccount(id: UUID(), code: "1100", name: "Cuentas por cobrar", subtype: .accountsReceivable)
    let ap = LedgerAccount(id: UUID(), code: "2000", name: "Cuentas por pagar", subtype: .accountsPayable)
    let tax = LedgerAccount(id: UUID(), code: "2200", name: "Sales Tax Payable", subtype: .salesTaxPayable)
    let capital = LedgerAccount(id: UUID(), code: "3000", name: "Capital", subtype: .ownersEquity)
    let sales = LedgerAccount(id: UUID(), code: "4000", name: "Ventas", subtype: .sales)
    let cogs = LedgerAccount(id: UUID(), code: "5000", name: "Materiales", subtype: .costOfGoodsSold)
    let rent = LedgerAccount(id: UUID(), code: "6400", name: "Alquiler", subtype: .operatingExpense)

    var accounts: [LedgerAccount] { [bank, ar, ap, tax, capital, sales, cogs, rent] }
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func ledger(_ entries: [JournalEntryDraft]) -> [LedgerLine] {
        entries.flatMap { entry in entry.lines.map { LedgerLine(accountID: $0.accountID, date: entry.date, debit: $0.debit, credit: $0.credit) } }
    }

    var sampleEntries: [JournalEntryDraft] {
        get throws {
            [
                JournalEntryDraft(date: day(2025, 12, 1), lines: [.debit(bank.id, 1_000_000), .credit(capital.id, 1_000_000)]),
                JournalEntryDraft(date: day(2025, 12, 15), lines: [.debit(bank.id, 50_000), .credit(sales.id, 50_000)]),
                try PostingRules.invoice(date: day(2026, 10, 3), memo: "F-1", receivableAccountID: ar.id,
                                         lines: [SalesLine(incomeAccountID: sales.id, amount: 200_000)],
                                         taxComponents: [TaxComponent(name: "TX", rateMillionths: 82_500, liabilityAccountID: tax.id)]).entry,
                try PostingRules.paymentReceived(date: day(2026, 10, 10), memo: "", amount: 100_000, depositAccountID: bank.id, receivableAccountID: ar.id),
                try PostingRules.bill(date: day(2026, 10, 12), memo: "", payableAccountID: ap.id, lines: [CostLine(accountID: cogs.id, amount: 30_000)]),
                try PostingRules.expense(date: day(2026, 10, 20), memo: "", paymentAccountID: bank.id, lines: [CostLine(accountID: rent.id, amount: 120_000)]),
            ]
        }
    }

    @Test("Balanza de comprobación cuadra")
    func trialBalance() throws {
        let report = ReportBuilder.trialBalance(accounts: accounts, lines: ledger(try sampleEntries), asOf: day(2026, 10, 31))
        #expect(report.isBalanced)
        #expect(report.totalDebit == report.totalCredit)
        #expect(report.rows.first { $0.account == ar }?.debit == 116_500)
    }

    @Test("Estado de resultados de octubre")
    func incomeStatement() throws {
        let report = ReportBuilder.incomeStatement(accounts: accounts, lines: ledger(try sampleEntries),
                                                   from: day(2026, 10, 1), to: day(2026, 10, 31))
        #expect(report.totalIncome == 200_000)
        #expect(report.totalCostOfGoodsSold == 30_000)
        #expect(report.grossProfit == 170_000)
        #expect(report.totalExpenses == 120_000)
        #expect(report.netIncome == 50_000)
    }

    @Test("Balance general: Activo = Pasivo + Patrimonio, separando el resultado de años anteriores")
    func balanceSheet() throws {
        let report = ReportBuilder.balanceSheet(accounts: accounts, lines: ledger(try sampleEntries),
                                                asOf: day(2026, 10, 31), fiscalYearStart: day(2026, 1, 1))
        #expect(report.isBalanced)
        #expect(report.priorYearsEarnings == 50_000)
        #expect(report.currentYearEarnings == 50_000)
        // Banco 1,030,000 + CxC 116,500 = CxP 30,000 + Sales tax 16,500 + Capital 1,000,000 + resultados 100,000
        #expect(report.totalAssets == 1_146_500)
        #expect(report.totalLiabilities == 46_500)
    }

    @Test("Propiedad: con asientos aleatorios válidos la balanza y el balance siempre cuadran", arguments: [1, 99])
    func randomLedgerAlwaysBalances(seed: UInt64) throws {
        var rng = SeededGenerator(seed: seed)
        var entries: [JournalEntryDraft] = []
        for _ in 0..<2_000 {
            let amount = Int64.random(in: 1...10_000_000, using: &rng)
            let split = Int64.random(in: 0...amount, using: &rng)
            let pair = accounts.shuffled(using: &rng).prefix(3).map(\.id)
            var lines: [JournalLineDraft] = [.debit(pair[0], amount)]
            lines += split > 0 && split < amount ? [.credit(pair[1], split), .credit(pair[2], amount - split)] : [.credit(pair[1], amount)]
            let entry = JournalEntryDraft(date: day(2026, Int.random(in: 1...12, using: &rng), Int.random(in: 1...28, using: &rng)), lines: lines)
            try JournalValidator().validate(entry)
            entries.append(entry)
        }
        let lines = ledger(entries)
        let asOf = day(2026, 12, 31)
        #expect(ReportBuilder.trialBalance(accounts: accounts, lines: lines, asOf: asOf).isBalanced)
        #expect(ReportBuilder.balanceSheet(accounts: accounts, lines: lines, asOf: asOf).isBalanced)
        #expect(ReportBuilder.balanceSheet(accounts: accounts, lines: lines, asOf: day(2026, 6, 15), fiscalYearStart: day(2026, 4, 1)).isBalanced)
    }

    @Test("Antigüedad de cuentas por cobrar por tramos")
    func aging() {
        let asOf = day(2026, 10, 31)
        let report = ReportBuilder.aging(items: [
            .init(party: "Hotel Mirador", document: "F-1038", dueDate: day(2026, 10, 23), balance: 215_000),
            .init(party: "Café Aurora", document: "F-1047", dueDate: day(2026, 11, 12), balance: 240_000),
            .init(party: "Hotel Mirador", document: "F-1001", dueDate: day(2026, 7, 1), balance: 10_000),
        ], asOf: asOf, calendar: calendar)
        #expect(report.total(for: .current) == 240_000)
        #expect(report.total(for: .days1to30) == 215_000)
        #expect(report.total(for: .over90) == 10_000)
        #expect(report.rows.first { $0.party == "Hotel Mirador" }?.total == 225_000)
    }
}
