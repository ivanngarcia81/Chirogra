import Foundation
import Testing
@testable import ChirograCore

@Suite("Sales tax y dinero")
struct SalesTaxAndMoneyTests {
    let account = UUID()

    @Test("Redondeo mitad lejos de cero")
    func rounding() {
        #expect(Int64(125).dividedRoundingHalfAwayFromZero(by: 10) == 13)
        #expect(Int64(124).dividedRoundingHalfAwayFromZero(by: 10) == 12)
        #expect(Int64(-125).dividedRoundingHalfAwayFromZero(by: 10) == -13)
        #expect(Int64(-124).dividedRoundingHalfAwayFromZero(by: 10) == -12)
    }

    @Test("El desglose por componente suma exactamente el impuesto total")
    func residualGoesToLargestComponent() {
        // Base $0.10 a 3 × 3.3333 %: cada componente redondea a 0, el total combinado (9.9999 %) a 1 centavo.
        let components = (0..<3).map { _ in TaxComponent(name: "c", rateMillionths: 33_333, liabilityAccountID: account) }
        let taxes = SalesTaxCalculator.taxes(onTaxableBase: 10, components: components)
        #expect(taxes.reduce(0) { $0 + $1.amount } == 1)
        #expect(taxes.map(\.amount).sorted() == [0, 0, 1])
    }

    @Test("8.25 % de $19.99 = $1.65")
    func typicalRate() {
        let components = [TaxComponent(name: "TX", rateMillionths: 82_500, liabilityAccountID: account)]
        #expect(SalesTaxCalculator.totalTax(onTaxableBase: 1_999, components: components) == 165)
    }

    @Test("Conversión de porcentaje a millonésimas")
    func percentConversion() {
        #expect(TaxComponent.millionths(fromPercent: 6.25) == 62_500)
        #expect(TaxComponent.millionths(fromPercent: Decimal(string: "8.2575")!) == 82_575)
        #expect(TaxComponent(name: "", rateMillionths: 62_500, liabilityAccountID: account).percent == 6.25)
    }

    @Test("Money desde Decimal redondea a centavos sin errores binarios")
    func moneyFromDecimal() {
        #expect(Money(decimal: Decimal(string: "1250.005")!).minorUnits == 125_001)
        #expect(Money(decimal: Decimal(string: "0.1")! + Decimal(string: "0.2")!).minorUnits == 30)
        #expect(Money(minorUnits: 4_821_540).decimalValue == Decimal(string: "48215.4")!)
        #expect((Money(minorUnits: 100) + Money(minorUnits: 250) - Money(minorUnits: 50)).minorUnits == 300)
    }

    @Test("Formato en dólares de EE. UU.")
    func formatting() {
        #expect(Money(minorUnits: 4_821_540).formatted(locale: Locale(identifier: "en_US")) == "$48,215.40")
    }
}
