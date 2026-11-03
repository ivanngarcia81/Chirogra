import Foundation
import Testing
@testable import ChirograCore

@Suite("Precios con impuesto incluido")
struct TaxIncludedTests {
    let liability = UUID()
    var austin: [TaxComponent] {
        [TaxComponent(name: "Texas", rateMillionths: 62_500, liabilityAccountID: liability),
         TaxComponent(name: "Austin", rateMillionths: 10_000, liabilityAccountID: liability),
         TaxComponent(name: "Austin MTA", rateMillionths: 10_000, liabilityAccountID: liability)]
    }

    @Test("$108.25 con 8.25 % incluido son $100.00 de base y $8.25 de impuesto, desglosado")
    func exactCase() {
        let result = SalesTaxCalculator.taxesIncluded(inGross: 10_825, components: austin)
        #expect(result.base == 10_000)
        #expect(result.taxes.map(\.amount) == [625, 100, 100])
        #expect(result.taxes.allSatisfy { $0.taxableBase == 10_000 })
    }

    @Test("Redondeo al centavo con varias tasas combinadas", arguments: [
        (Int64(1_000), Int64(924), [Int64(58), 9, 9]),   // $10.00 → base $9.24, impuesto $0.76
        (Int64(99), Int64(91), [Int64(6), 1, 1]),         // $0.99 → base $0.91, impuesto $0.08
        (Int64(1), Int64(1), [Int64(0), 0, 0]),           // un centavo: no da para impuesto
        (Int64(28_417), Int64(26_251), [Int64(1_640), 263, 263]),  // el residuo de redondeo va a la tasa mayor
    ])
    func rounding(gross: Int64, base: Int64, taxes: [Int64]) {
        let result = SalesTaxCalculator.taxesIncluded(inGross: gross, components: austin)
        #expect(result.base == base)
        #expect(result.taxes.map(\.amount) == taxes)
        #expect(result.base + result.taxes.reduce(0) { $0 + $1.amount } == gross)
    }

    @Test("Propiedad: base + impuesto = bruto y el desglose suma el impuesto, con tasas de 4 decimales")
    func property() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let components = (0..<Int.random(in: 1...4, using: &generator)).map { index in
                TaxComponent(name: "C\(index)", rateMillionths: Int64.random(in: 0...80_000, using: &generator), liabilityAccountID: liability)
            }
            let gross = Int64.random(in: 1...5_000_000, using: &generator)
            let result = SalesTaxCalculator.taxesIncluded(inGross: gross, components: components)
            let tax = result.taxes.reduce(0) { $0 + $1.amount }
            #expect(result.base + tax == gross)
            #expect(result.base >= 0 && result.base <= gross)
            // El impuesto separado no se aleja más de un centavo del que daría la base.
            let recomputed = SalesTaxCalculator.totalTax(onTaxableBase: result.base, components: components)
            #expect(abs(recomputed - tax) <= 1)
        }
    }

    @Test("Factura con impuesto incluido: total = líneas − descuento, ingresos netos y el asiento cuadra")
    func invoicePosting() throws {
        let receivable = UUID(), services = UUID(), materials = UUID(), discount = UUID()
        let posting = try PostingRules.invoice(
            date: Date(), memo: "", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: services, amount: 50_000, isTaxable: false),
                    SalesLine(incomeAccountID: materials, amount: 10_825, isTaxable: true)],
            taxComponents: austin, discount: 0, discountAccountID: discount, pricesIncludeTax: true)
        #expect(posting.total == 60_825)
        #expect(posting.totalTax == 825)
        #expect(posting.taxableBase == 10_000)
        #expect(posting.netSales == 60_000)
        #expect(posting.entry.isBalanced)
        #expect(posting.entry.lines.first { $0.accountID == materials }?.credit == 10_000)
        #expect(posting.entry.lines.first { $0.accountID == services }?.credit == 50_000)

        // Con descuento: la base gravable (bruta) se reduce en proporción y el impuesto sale de ahí.
        let discounted = try PostingRules.invoice(
            date: Date(), memo: "", receivableAccountID: receivable,
            lines: [SalesLine(incomeAccountID: services, amount: 50_000, isTaxable: false),
                    SalesLine(incomeAccountID: materials, amount: 10_825, isTaxable: true)],
            taxComponents: austin, discount: 6_083, discountAccountID: discount, pricesIncludeTax: true)
        #expect(discounted.total == 60_825 - 6_083)
        #expect(discounted.entry.isBalanced)
        #expect(discounted.taxableBase + discounted.totalTax == 10_825 - (6_083 * 10_825).dividedRoundingHalfAwayFromZero(by: 60_825))
    }

    @Test("Sin el ajuste, el cálculo de siempre no cambia")
    func exclusiveUnchanged() throws {
        let posting = try PostingRules.invoice(
            date: Date(), memo: "", receivableAccountID: UUID(),
            lines: [SalesLine(incomeAccountID: UUID(), amount: 10_000, isTaxable: true)], taxComponents: austin)
        #expect(posting.total == 10_825)
        #expect(posting.netSales == 10_000)
        #expect(!posting.pricesIncludeTax)
    }

    @Test("Reparto exacto por mayor resto")
    func allocate() {
        #expect(PostingRules.allocate(10, weights: [1, 1, 1]) == [4, 3, 3])
        #expect(PostingRules.allocate(825, weights: [10_825]) == [825])
        #expect(PostingRules.allocate(0, weights: [5, 5]) == [0, 0])
        #expect(PostingRules.allocate(7, weights: [3, 0, 4]).reduce(0, +) == 7)
    }
}
