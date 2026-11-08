import Foundation
import Testing
@testable import ChirograCore

@Suite("Flujo de efectivo, presupuesto y deducibles")
struct CashFlowAndBudgetTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    let bank = LedgerAccount(id: UUID(), code: "1010", name: "Banco", subtype: .bank)
    let receivable = LedgerAccount(id: UUID(), code: "1100", name: "CxC", subtype: .accountsReceivable)
    let equipment = LedgerAccount(id: UUID(), code: "1500", name: "Equipo", subtype: .fixedAsset)
    let depreciation = LedgerAccount(id: UUID(), code: "1590", name: "Depreciación acumulada", subtype: .fixedAsset)
    let payable = LedgerAccount(id: UUID(), code: "2000", name: "CxP", subtype: .accountsPayable)
    let loan = LedgerAccount(id: UUID(), code: "2700", name: "Préstamo", subtype: .longTermLiability)
    let capital = LedgerAccount(id: UUID(), code: "3000", name: "Capital", subtype: .ownersEquity)
    let sales = LedgerAccount(id: UUID(), code: "4000", name: "Ventas", subtype: .sales)
    let supplies = LedgerAccount(id: UUID(), code: "6500", name: "Suministros", subtype: .operatingExpense)
    let depreciationExpense = LedgerAccount(id: UUID(), code: "6900", name: "Depreciación", subtype: .operatingExpense)
    let meals = LedgerAccount(id: UUID(), code: "6650", name: "Comidas", subtype: .operatingExpense)

    var accounts: [LedgerAccount] { [bank, receivable, equipment, depreciation, payable, loan, capital, sales, supplies, depreciationExpense, meals] }

    func entry(_ date: Date, _ lines: [(LedgerAccount, Int64, Int64)]) -> [LedgerLine] {
        let id = UUID()
        return lines.map { LedgerLine(accountID: $0.0.id, date: date, debit: $0.1, credit: $0.2, entryID: id) }
    }

    @Test("Flujo de efectivo indirecto: utilidad, depreciación, capital de trabajo, inversión y financiamiento")
    func cashFlow() {
        var lines = entry(day(2025, 12, 31), [(bank, 100_000, 0), (capital, 0, 100_000)])            // antes del periodo
        lines += entry(day(2026, 1, 5), [(receivable, 50_000, 0), (sales, 0, 50_000)])               // factura
        lines += entry(day(2026, 1, 20), [(bank, 30_000, 0), (receivable, 0, 30_000)])               // cobro
        lines += entry(day(2026, 2, 1), [(supplies, 8_000, 0), (payable, 0, 8_000)])                 // factura de proveedor
        lines += entry(day(2026, 3, 1), [(equipment, 60_000, 0), (bank, 0, 60_000)])                 // compra de equipo
        lines += entry(day(2026, 3, 2), [(bank, 40_000, 0), (loan, 0, 40_000)])                      // préstamo
        lines += entry(day(2026, 6, 30), [(depreciationExpense, 5_000, 0), (depreciation, 0, 5_000)]) // depreciación
        let report = ReportBuilder.cashFlow(accounts: accounts, lines: lines, from: day(2026, 1, 1), to: day(2026, 12, 31))
        #expect(report.netIncome == 50_000 - 8_000 - 5_000)
        #expect(report.nonCashAdjustments.map(\.amount) == [5_000])
        #expect(report.nonCashAdjustments.first?.account.id == depreciation.id)
        #expect(Dictionary(uniqueKeysWithValues: report.workingCapital.map { ($0.account.id, $0.amount) }) == [receivable.id: -20_000, payable.id: 8_000])
        #expect(report.operatingTotal == 37_000 + 5_000 - 20_000 + 8_000)
        #expect(report.investing.map(\.amount) == [-60_000])
        #expect(report.financing.map(\.amount) == [40_000])
        #expect(report.beginningCash == 100_000 && report.endingCash == 110_000)
        #expect(report.netCashChange == 10_000 && report.isReconciled)
    }

    @Test("Propiedad: con asientos aleatorios el flujo de efectivo siempre cuadra con la variación del efectivo", arguments: [3, 77])
    func randomCashFlowReconciles(seed: UInt64) throws {
        var rng = SeededGenerator(seed: seed)
        var lines: [LedgerLine] = []
        for _ in 0..<1_500 {
            let amount = Int64.random(in: 1...5_000_000, using: &rng)
            let split = Int64.random(in: 0...amount, using: &rng)
            let pick = Array(accounts.shuffled(using: &rng).prefix(3))
            let month = Int.random(in: 1...12, using: &rng)
            let dayOfMonth = Int.random(in: 1...28, using: &rng)
            var parts: [(LedgerAccount, Int64, Int64)] = [(pick[0], amount, 0)]
            if split > 0 && split < amount {
                parts.append((pick[1], 0, split))
                parts.append((pick[2], 0, amount - split))
            } else {
                parts.append((pick[1], 0, amount))
            }
            lines += entry(day(2026, month, dayOfMonth), parts)
        }
        for (from, to) in [(day(2026, 1, 1), day(2026, 12, 31)), (day(2026, 4, 1), day(2026, 6, 30)), (day(2026, 7, 15), day(2026, 7, 15))] {
            let report = ReportBuilder.cashFlow(accounts: accounts, lines: lines, from: from, to: to)
            #expect(report.isReconciled)
            let income = ReportBuilder.incomeStatement(accounts: accounts, lines: lines, from: from, to: to)
            #expect(report.netIncome == income.netIncome)
        }
    }

    @Test("Reparto con signo: exacto al centavo y con el signo de cada peso")
    func allocateSigned() {
        // Factura: ingreso −1000, sales tax −82.50, descuento +50 (neto −1032.50); se cobran 500.
        let shares = ReportBuilder.allocateSigned(-50_000, weights: [-100_000, -8_250, 5_000])
        #expect(shares.reduce(0, +) == -50_000)
        #expect(shares[0] < 0 && shares[1] < 0 && shares[2] > 0)
        #expect(ReportBuilder.allocateSigned(100, weights: [1, 1, 1]) == [34, 33, 33])
        #expect(ReportBuilder.allocateSigned(100, weights: [0, 0]) == [0, 0])
        #expect(ReportBuilder.allocateSigned(0, weights: [5]) == [0])
        var rng = SeededGenerator(seed: 5)
        for _ in 0..<500 {
            let weights = (0..<Int.random(in: 1...6, using: &rng)).map { _ in Int64.random(in: -100_000...100_000, using: &rng) }
            let total = Int64.random(in: -1_000_000...1_000_000, using: &rng)
            guard weights.reduce(0, +) != 0 else { continue }
            #expect(ReportBuilder.allocateSigned(total, weights: weights).reduce(0, +) == total)
        }
    }

    @Test("Real contra presupuesto por periodo, con la variación favorable o no")
    func budget() {
        var lines = entry(day(2026, 1, 10), [(receivable, 120_000, 0), (sales, 0, 120_000)])
        lines += entry(day(2026, 2, 10), [(supplies, 30_000, 0), (bank, 0, 30_000)])
        lines += entry(day(2026, 2, 11), [(supplies, 0, 5_000), (bank, 5_000, 0)])
        let periods = [BudgetReport.Period(start: day(2026, 1, 1), end: day(2026, 1, 31)), BudgetReport.Period(start: day(2026, 2, 1), end: day(2026, 2, 28))]
        let report = ReportBuilder.budgetVsActual(accounts: accounts, lines: lines,
                                                  budget: [sales.id: [100_000, 100_000], supplies.id: [20_000, 20_000], capital.id: [0, 1]],
                                                  periods: periods)
        let income = try! #require(report.income.first)
        #expect(income.actual == [120_000, 0] && income.variance == -80_000 && !income.isFavorable)
        let expense = try! #require(report.expenses.first)
        #expect(expense.actual == [0, 25_000] && expense.variance == -15_000 && expense.isFavorable)
        #expect(expense.percentOfBudget == 62.5)
        #expect(report.other.map(\.account.id) == [capital.id])
        #expect(report.budgetedNetIncome == [80_000, 80_000] && report.actualNetIncome == [120_000, -25_000])
        #expect(CSVExport.budget(report).contains("6500 · Suministros"))
    }

    @Test("Deducibles por línea: ingresos y deducciones con su signo, comidas al 50 % y cuentas excluidas")
    func taxSummary() throws {
        var lines = entry(day(2026, 3, 1), [(receivable, 100_000, 0), (sales, 0, 100_000)])
        lines += entry(day(2026, 3, 2), [(supplies, 10_000, 0), (meals, 3_001, 0), (bank, 0, 13_001)])
        lines += entry(day(2026, 3, 3), [(depreciationExpense, 2_000, 0), (depreciation, 0, 2_000)])
        let line = { (number: String) in TaxFormCatalog.line(number, in: .scheduleC)! }
        let mapping: [UUID: TaxFormLine] = [sales.id: line("1"), supplies.id: line("22"), meals.id: line("24b")]
        let report = ReportBuilder.taxFormSummary(form: .scheduleC, year: 2026, accounts: accounts, lines: lines,
                                                  from: day(2026, 1, 1), to: day(2026, 12, 31)) { mapping[$0.id] }
        #expect(report.rows.map(\.line.number) == ["1", "22", "24b"])
        #expect(report.rows.map(\.amount) == [100_000, 10_000, 3_001])
        #expect(report.rows.last?.deductibleAmount == 1_501)
        #expect(report.totalIncome == 100_000 && report.totalDeductions == 11_501)
        #expect(report.excluded.map(\.account.id) == [depreciationExpense.id])
        #expect(TaxFormCatalog.line(id: "scheduleC:24b")?.deductiblePercent == 50)
        #expect(TaxFormCatalog.line(id: "form1120S:20-meals")?.rollsUpTo == "20")
        #expect(TaxFormCatalog.line(id: "nada:1") == nil)
        #expect(Set(TaxFormCatalog.lines(for: .scheduleC).map(\.id)).count == TaxFormCatalog.lines(for: .scheduleC).count)
        #expect(CSVExport.taxSummary(report, locale: Locale(identifier: "en_US")).contains("Deductible meals"))
    }
}
