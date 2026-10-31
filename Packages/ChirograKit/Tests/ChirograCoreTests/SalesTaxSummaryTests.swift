import Foundation
import Testing
@testable import ChirograCore

@Suite("Resumen de sales tax")
struct SalesTaxSummaryTests {
    let texas = UUID(), austin = UUID()
    func day(_ d: Int) -> Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: d))! }

    @Test("Gravables, no gravables y exentas; impuesto por tasa; las notas de crédito restan")
    func summary() {
        let docs = [
            // Factura: $2,000 netos, $400 gravables, Texas 6.25 % y Austin 2 %.
            SalesTaxDocument(date: day(3), netSales: 200_000, taxableBase: 40_000, isExempt: false, taxes: [
                .init(rateID: texas, name: "Texas", rateMillionths: 62_500, taxableBase: 40_000, amount: 2_500),
                .init(rateID: austin, name: "Austin", rateMillionths: 20_000, taxableBase: 40_000, amount: 800),
            ]),
            // Cliente exento: $500.
            SalesTaxDocument(date: day(10), netSales: 50_000, taxableBase: 0, isExempt: true, taxes: []),
            // Nota de crédito de $100 gravables.
            SalesTaxDocument(date: day(20), netSales: -10_000, taxableBase: -10_000, isExempt: false, taxes: [
                .init(rateID: texas, name: "Texas", rateMillionths: 62_500, taxableBase: -10_000, amount: -625),
                .init(rateID: austin, name: "Austin", rateMillionths: 20_000, taxableBase: -10_000, amount: -200),
            ]),
            // Fuera del periodo.
            SalesTaxDocument(date: day(31).addingTimeInterval(86_400 * 2), netSales: 99_999, taxableBase: 99_999, isExempt: false, taxes: []),
        ]
        let report = ReportBuilder.salesTaxSummary(documents: docs, from: day(1), to: day(31))
        #expect(report.totalSales == 240_000)
        #expect(report.taxableSales == 30_000)
        #expect(report.exemptSales == 50_000)
        #expect(report.nonTaxableSales == 160_000)
        #expect(report.rows.map(\.name) == ["Texas", "Austin"])
        #expect(report.rows.map(\.tax) == [1_875, 600])
        #expect(report.totalTax == 2_475)
        #expect(CSVExport.salesTaxSummary(report).contains("Total impuesto,,,24.75"))
    }
}
