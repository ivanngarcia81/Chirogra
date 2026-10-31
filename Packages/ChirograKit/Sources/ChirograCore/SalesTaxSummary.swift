import Foundation

/// Documento de venta visto por el resumen de sales tax (factura o nota de crédito).
public struct SalesTaxDocument: Hashable, Sendable {
    public struct Tax: Hashable, Sendable {
        public var rateID: UUID?
        public var name: String
        public var rateMillionths: Int64
        public var taxableBase: Int64
        public var amount: Int64

        public init(rateID: UUID?, name: String, rateMillionths: Int64, taxableBase: Int64, amount: Int64) {
            self.rateID = rateID
            self.name = name
            self.rateMillionths = rateMillionths
            self.taxableBase = taxableBase
            self.amount = amount
        }
    }

    public var date: Date
    /// Ventas netas del documento (líneas menos descuento), sin impuesto. Negativo en notas de crédito.
    public var netSales: Int64
    /// Base gravable del documento. Negativa en notas de crédito.
    public var taxableBase: Int64
    /// Cliente exento: toda la venta cuenta como exenta.
    public var isExempt: Bool
    public var taxes: [Tax]

    public init(date: Date, netSales: Int64, taxableBase: Int64, isExempt: Bool, taxes: [Tax]) {
        self.date = date
        self.netSales = netSales
        self.taxableBase = taxableBase
        self.isExempt = isExempt
        self.taxes = taxes
    }
}

/// Resumen de sales tax del periodo (DISEÑO §4.7): ventas gravables, no gravables y exentas,
/// e impuesto cobrado por tasa (jurisdicción).
public struct SalesTaxSummary: Hashable, Sendable {
    public struct RateRow: Hashable, Sendable, Identifiable {
        public var name: String
        public var rateMillionths: Int64
        public var taxableSales: Int64
        public var tax: Int64
        public var id: String { "\(name)-\(rateMillionths)" }
        public var percent: Decimal { Decimal(rateMillionths) / 10_000 }
    }

    public var from: Date
    public var to: Date
    public var totalSales: Int64
    public var taxableSales: Int64
    public var exemptSales: Int64
    public var rows: [RateRow]

    /// Ventas de artículos o servicios no gravables (ni gravables ni de clientes exentos).
    public var nonTaxableSales: Int64 { totalSales - taxableSales - exemptSales }
    public var totalTax: Int64 { rows.reduce(0) { $0 + $1.tax } }
}

extension ReportBuilder {
    public static func salesTaxSummary(documents: [SalesTaxDocument], from: Date, to: Date) -> SalesTaxSummary {
        let inRange = documents.filter { $0.date >= from && $0.date <= to }
        var rows: [String: SalesTaxSummary.RateRow] = [:]
        var order: [String] = []
        for tax in inRange.flatMap(\.taxes) {
            let key = tax.rateID?.uuidString ?? "\(tax.name)-\(tax.rateMillionths)"
            if rows[key] == nil {
                order.append(key)
                rows[key] = SalesTaxSummary.RateRow(name: tax.name, rateMillionths: tax.rateMillionths, taxableSales: 0, tax: 0)
            }
            rows[key]?.taxableSales += tax.taxableBase
            rows[key]?.tax += tax.amount
        }
        return SalesTaxSummary(
            from: from, to: to,
            totalSales: inRange.reduce(0) { $0 + $1.netSales },
            taxableSales: inRange.filter { !$0.isExempt }.reduce(0) { $0 + $1.taxableBase },
            exemptSales: inRange.filter(\.isExempt).reduce(0) { $0 + $1.netSales },
            rows: order.compactMap { rows[$0] }
        )
    }
}
