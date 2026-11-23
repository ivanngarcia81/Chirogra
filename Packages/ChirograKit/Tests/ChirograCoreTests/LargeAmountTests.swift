import Foundation
import Testing
@testable import ChirograCore

/// Importes extremos y diferencias de un centavo (auditoría del 23-nov): la multiplicación de importes va en 128 bits
/// (`Int64.multiplied(by:dividedRoundingHalfAwayFromZeroBy:)`); antes una factura de $100 millones con $10 millones de
/// descuento cerraba la app.
@Suite("Importes extremos y centavos")
struct LargeAmountTests {
    let income = UUID(), receivable = UUID(), discountAccount = UUID(), stateTax = UUID(), cityTax = UUID()

    var texas: [TaxComponent] {
        [TaxComponent(name: "Texas", rateMillionths: 62_500, liabilityAccountID: stateTax),
         TaxComponent(name: "Austin", rateMillionths: 20_000, liabilityAccountID: cityTax)]
    }

    @Test("Mismo resultado que la fórmula de 64 bits donde esa no desborda, también con negativos y medios exactos")
    func matchesOldFormula() {
        var random = SystemRandomNumberGenerator()
        let cases: [(Int64, Int64, Int64)] = [(5, 1, 2), (-5, 1, 2), (5, -1, 2), (15, 1, 10), (-15, 1, 10), (25, 1, 10), (1, 1, 3),
                                              (2, 1, 3), (-2, 1, 3), (0, 7, 3), (1_999, 82_500, 1_000_000)]
        for (a, b, c) in cases {
            #expect(a.multiplied(by: b, dividedRoundingHalfAwayFromZeroBy: c) == (a * b).dividedRoundingHalfAwayFromZero(by: c), "\(a)·\(b)/\(c)")
        }
        for _ in 0..<5_000 {
            let a = Int64.random(in: -3_000_000_000...3_000_000_000, using: &random)
            let b = Int64.random(in: -3_000_000_000...3_000_000_000, using: &random)
            let c = Int64.random(in: 1...3_000_000_000, using: &random)
            #expect(a.multiplied(by: b, dividedRoundingHalfAwayFromZeroBy: c) == (a * b).dividedRoundingHalfAwayFromZero(by: c))
        }
    }

    @Test("Factura de $100 millones con $10 millones de descuento y 8.25 %: exacta y cuadrada")
    func largeInvoiceWithDiscount() throws {
        let posting = try PostingRules.invoice(date: Date(), memo: "Obra", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: income, amount: 10_000_000_000, isTaxable: true)],
            taxComponents: texas, discount: 1_000_000_000, discountAccountID: discountAccount)
        #expect(posting.taxableBase == 9_000_000_000)
        #expect(posting.totalTax == 742_500_000)                            // 8.25 % de $90 millones
        #expect(posting.total == 9_742_500_000)
        #expect(posting.taxes.map(\.amount).sorted() == [180_000_000, 562_500_000])
        #expect(posting.entry.totalDebits == posting.entry.totalCredits)
    }

    @Test("Precios con impuesto incluido de $50 mil millones: base + impuesto = precio exacto")
    func largeTaxIncluded() {
        let gross: Int64 = 5_000_000_000_000
        let included = SalesTaxCalculator.taxesIncluded(inGross: gross, components: texas)
        #expect(included.base + included.taxes.reduce(0) { $0 + $1.amount } == gross)
        #expect(included.base == 4_618_937_644_342)                        // 50 000 000 000 / 1.0825, redondeado
    }

    @Test("Medio centavo: 8.25 % de $0.06 = $0.005 → $0.01; de $0.02 → $0.00; con descuento que deja $0.01")
    func halfCent() throws {
        #expect(SalesTaxCalculator.totalTax(onTaxableBase: 6, components: texas) == 0)          // 0.495 ¢ → 0
        #expect(SalesTaxCalculator.totalTax(onTaxableBase: 7, components: texas) == 1)          // 0.5775 ¢ → 1
        let posting = try PostingRules.invoice(date: Date(), memo: "x", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: income, amount: 3, isTaxable: true), SalesLine(incomeAccountID: income, amount: 3, isTaxable: false)],
            taxComponents: texas, discount: 5, discountAccountID: discountAccount)
        // Descuento gravable: 5 × 3/6 = 2.5 → 3 (mitad lejos de cero); base 0; total 1 ¢.
        #expect(posting.taxableBase == 0 && posting.totalTax == 0 && posting.total == 1)
        #expect(posting.entry.totalDebits == posting.entry.totalCredits)
    }

    @Test("Asignación proporcional exacta con importes del orden de billones")
    func allocationAtScale() {
        let shares = PostingRules.allocate(999_999_999_999, weights: [3_333_333_333_333, 3_333_333_333_333, 3_333_333_333_334])
        #expect(shares.reduce(0, +) == 999_999_999_999)
        let signed = ReportBuilder.allocateSigned(-999_999_999_999, weights: [-9_000_000_000_000, 1_000_000_000_000])
        #expect(signed.reduce(0, +) == -999_999_999_999)
    }
}
