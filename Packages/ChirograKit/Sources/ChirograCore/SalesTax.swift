import Foundation

/// Componente de un grupo de sales tax (estatal, condado, ciudad, distrito), §4.8.
public struct TaxComponent: Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Tasa en millonésimas de la base: 6.25 % = 62_500. Admite 4 decimales de porcentaje sin `Double`.
    public var rateMillionths: Int64
    /// Subcuenta de Sales Tax Payable de la agencia que cobra este componente.
    public var liabilityAccountID: UUID

    public init(id: UUID = UUID(), name: String, rateMillionths: Int64, liabilityAccountID: UUID) {
        self.id = id
        self.name = name
        self.rateMillionths = rateMillionths
        self.liabilityAccountID = liabilityAccountID
    }

    /// Porcentaje legible: 62_500 → 6.25.
    public var percent: Decimal { Decimal(rateMillionths) / 10_000 }

    /// 6.25 → 62_500, redondeando a 4 decimales de porcentaje.
    public static func millionths(fromPercent percent: Decimal) -> Int64 {
        var scaled = percent * 10_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

public struct TaxComponentAmount: Hashable, Sendable {
    public var component: TaxComponent
    public var taxableBase: Int64
    public var amount: Int64
}

public enum SalesTaxCalculator {
    public static let millionth: Int64 = 1_000_000

    /// Impuesto sobre la base gravable, desglosado por componente.
    ///
    /// El total se redondea una vez sobre la tasa combinada; cada componente se redondea por separado
    /// y el residuo de redondeo se asigna al componente de mayor tasa, de modo que
    /// la suma del desglose es siempre igual al total del documento.
    public static func taxes(onTaxableBase base: Int64, components: [TaxComponent]) -> [TaxComponentAmount] {
        guard !components.isEmpty else { return [] }
        let combinedRate = components.reduce(0) { $0 + $1.rateMillionths }
        let total = (base * combinedRate).dividedRoundingHalfAwayFromZero(by: millionth)

        var amounts = components.map { component in
            TaxComponentAmount(
                component: component,
                taxableBase: base,
                amount: (base * component.rateMillionths).dividedRoundingHalfAwayFromZero(by: millionth)
            )
        }

        let residual = total - amounts.reduce(0) { $0 + $1.amount }
        if residual != 0, let largest = amounts.indices.max(by: { amounts[$0].component.rateMillionths < amounts[$1].component.rateMillionths }) {
            amounts[largest].amount += residual
        }
        return amounts
    }

    public static func totalTax(onTaxableBase base: Int64, components: [TaxComponent]) -> Int64 {
        taxes(onTaxableBase: base, components: components).reduce(0) { $0 + $1.amount }
    }
}
