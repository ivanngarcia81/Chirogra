import Foundation

/// Línea de un documento de venta ya neta de descuentos.
public struct SalesLine: Hashable, Sendable {
    public var incomeAccountID: UUID
    public var amount: Int64
    public var isTaxable: Bool
    public var memo: String

    public init(incomeAccountID: UUID, amount: Int64, isTaxable: Bool = true, memo: String = "") {
        self.incomeAccountID = incomeAccountID
        self.amount = amount
        self.isTaxable = isTaxable
        self.memo = memo
    }
}

/// Línea de gasto o compra: cuenta de gasto/activo e importe (sales tax incluido, §4.4).
public struct CostLine: Hashable, Sendable {
    public var accountID: UUID
    public var amount: Int64
    public var memo: String

    public init(accountID: UUID, amount: Int64, memo: String = "") {
        self.accountID = accountID
        self.amount = amount
        self.memo = memo
    }
}

public struct InvoicePosting: Hashable, Sendable {
    public var entry: JournalEntryDraft
    /// Suma de las líneas antes del descuento.
    public var subtotal: Int64
    public var discount: Int64
    /// Líneas gravables antes del descuento.
    public var taxableSubtotal: Int64
    /// Base sobre la que se calcula el impuesto: gravable menos su parte del descuento.
    public var taxableBase: Int64
    public var taxes: [TaxComponentAmount]
    public var total: Int64
    /// Los importes de las líneas ya incluían el impuesto: `subtotal` es bruto y `total = subtotal − discount`.
    public var pricesIncludeTax: Bool = false

    public var totalTax: Int64 { taxes.reduce(0) { $0 + $1.amount } }
    /// Ventas sin impuesto: lo que va a ingresos netos de descuento.
    public var netSales: Int64 { subtotal - discount - (pricesIncludeTax ? totalTax : 0) }
}

public enum PostingError: Error, Hashable, Sendable {
    case noLines
    case nonPositiveAmount
    case sameAccount
    case invalidDiscount
}

/// Reglas que convierten documentos de negocio en asientos de doble partida (§4.3–4.5).
/// Todas devuelven asientos cuadrados por construcción; las pruebas lo verifican.
public enum PostingRules {

    /// Factura de venta: Debe CxC (total) + Descuentos (si hay) / Haber Ingresos (por cuenta) + Sales Tax Payable (por componente).
    ///
    /// El descuento es del documento y se aplica **antes** del impuesto (DISEÑO §4.8): la base gravable se reduce
    /// en la proporción de líneas gravables sobre el subtotal. Los ingresos se registran en bruto y el descuento
    /// va al debe de una cuenta de descuentos, que resta en el estado de resultados.
    public static func invoice(
        date: Date,
        memo: String,
        receivableAccountID: UUID,
        lines: [SalesLine],
        taxComponents: [TaxComponent],
        customerIsTaxExempt: Bool = false,
        discount: Int64 = 0,
        discountAccountID: UUID? = nil,
        pricesIncludeTax: Bool = false
    ) throws(PostingError) -> InvoicePosting {
        guard !lines.isEmpty else { throw .noLines }
        guard lines.allSatisfy({ $0.amount > 0 }) else { throw .nonPositiveAmount }

        let subtotal = lines.reduce(0) { $0 + $1.amount }
        guard discount >= 0, discount <= subtotal, discount == 0 || discountAccountID != nil else { throw .invalidDiscount }
        let taxableSubtotal = customerIsTaxExempt ? 0 : lines.filter(\.isTaxable).reduce(0) { $0 + $1.amount }
        let taxableDiscount = subtotal == 0 ? 0 : (discount * taxableSubtotal).dividedRoundingHalfAwayFromZero(by: subtotal)
        var taxableBase = taxableSubtotal - taxableDiscount
        let taxes: [TaxComponentAmount]
        var incomeLines = lines
        let total: Int64
        if pricesIncludeTax {
            // El bruto gravable ya trae el impuesto: se separa y se descuenta de los ingresos de las líneas gravables,
            // repartido en proporción a su importe. El cliente paga exactamente las líneas menos el descuento.
            let included = SalesTaxCalculator.taxesIncluded(inGross: taxableBase, components: taxComponents)
            taxes = included.taxes.filter { $0.amount != 0 }
            taxableBase = included.base
            let totalTax = taxes.reduce(0) { $0 + $1.amount }
            if totalTax > 0 {
                let taxableIndices = lines.indices.filter { lines[$0].isTaxable }
                let shares = allocate(totalTax, weights: taxableIndices.map { lines[$0].amount })
                for (index, share) in zip(taxableIndices, shares) { incomeLines[index].amount -= share }
            }
            total = subtotal - discount
        } else {
            taxes = taxableBase > 0
                ? SalesTaxCalculator.taxes(onTaxableBase: taxableBase, components: taxComponents).filter { $0.amount != 0 }
                : []
            total = subtotal - discount + taxes.reduce(0) { $0 + $1.amount }
        }

        var entryLines: [JournalLineDraft] = total > 0 ? [.debit(receivableAccountID, total)] : []
        if discount > 0, let discountAccountID { entryLines.append(.debit(discountAccountID, discount)) }
        entryLines += grouped(incomeLines.filter { $0.amount > 0 }.map { ($0.incomeAccountID, $0.amount) }).map { .credit($0.0, $0.1) }
        entryLines += grouped(taxes.map { ($0.component.liabilityAccountID, $0.amount) }).map { .credit($0.0, $0.1) }

        return InvoicePosting(
            entry: JournalEntryDraft(date: date, memo: memo, source: .invoice, lines: entryLines),
            subtotal: subtotal,
            discount: discount,
            taxableSubtotal: taxableSubtotal,
            taxableBase: taxableBase,
            taxes: taxes,
            total: total,
            pricesIncludeTax: pricesIncludeTax
        )
    }

    /// Reparte `amount` según `weights` (mayor resto; a igualdad, el primero). La suma es exacta.
    public static func allocate(_ amount: Int64, weights: [Int64]) -> [Int64] {
        let total = weights.reduce(0, +)
        guard amount > 0, total > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { weight -> (amount: Int64, remainder: Int64) in
            let (share, remainder) = total.dividingFullWidth(amount.multipliedFullWidth(by: weight))
            return (share, remainder)
        }
        var leftover = amount - shares.reduce(0) { $0 + $1.amount }
        for index in shares.indices.sorted(by: { shares[$0].remainder > shares[$1].remainder }) where leftover > 0 {
            shares[index].amount += 1
            leftover -= 1
        }
        return shares.map(\.amount)
    }

    /// Nota de crédito: el asiento inverso de una factura con esas mismas líneas.
    public static func creditNote(
        date: Date,
        memo: String,
        receivableAccountID: UUID,
        lines: [SalesLine],
        taxComponents: [TaxComponent],
        customerIsTaxExempt: Bool = false,
        discount: Int64 = 0,
        discountAccountID: UUID? = nil
    ) throws(PostingError) -> InvoicePosting {
        var posting = try invoice(
            date: date, memo: memo, receivableAccountID: receivableAccountID,
            lines: lines, taxComponents: taxComponents, customerIsTaxExempt: customerIsTaxExempt,
            discount: discount, discountAccountID: discountAccountID
        )
        posting.entry.lines = posting.entry.lines.map(\.swapped)
        posting.entry.source = .creditNote
        return posting
    }

    /// Reparte `amount` entre las líneas en proporción a su importe, para que una nota de crédito sobre varias
    /// líneas rebaje cada cuenta de ingresos en su parte. Los centavos sobrantes van a las líneas con mayor
    /// resto (a igualdad, la primera), así la suma es exacta. Las partes de cero se omiten.
    public static func prorated(_ amount: Int64, across lines: [SalesLine]) -> [SalesLine] {
        let total = lines.reduce(0) { $0 + $1.amount }
        guard amount > 0, total > 0 else { return [] }
        var shares = lines.map { line -> (line: SalesLine, amount: Int64, remainder: Int64) in
            let (share, remainder) = total.dividingFullWidth(amount.multipliedFullWidth(by: line.amount))
            return (line, share, remainder)
        }
        var leftover = amount - shares.reduce(0) { $0 + $1.amount }
        for index in shares.indices.sorted(by: { shares[$0].remainder > shares[$1].remainder }) where leftover > 0 {
            shares[index].amount += 1
            leftover -= 1
        }
        return shares.filter { $0.amount > 0 }.map { share in
            var line = share.line
            line.amount = share.amount
            return line
        }
    }

    /// Cobro de cliente: Debe Banco/Caja/Fondos no depositados / Haber CxC.
    public static func paymentReceived(
        date: Date, memo: String, amount: Int64, depositAccountID: UUID, receivableAccountID: UUID
    ) throws(PostingError) -> JournalEntryDraft {
        try transfer(date: date, memo: memo, source: .paymentReceived, amount: amount,
                     debit: depositAccountID, credit: receivableAccountID)
    }

    /// Reembolso de un saldo a favor del cliente: Debe CxC / Haber Banco.
    public static func customerRefund(
        date: Date, memo: String, amount: Int64, receivableAccountID: UUID, paymentAccountID: UUID
    ) throws(PostingError) -> JournalEntryDraft {
        try transfer(date: date, memo: memo, source: .customerRefund, amount: amount,
                     debit: receivableAccountID, credit: paymentAccountID)
    }

    /// Factura de proveedor: Debe Gastos/Activos / Haber CxP (total).
    public static func bill(
        date: Date, memo: String, payableAccountID: UUID, lines: [CostLine]
    ) throws(PostingError) -> JournalEntryDraft {
        try costDocument(date: date, memo: memo, source: .bill, creditAccountID: payableAccountID, lines: lines)
    }

    /// Pago a proveedor: Debe CxP / Haber Banco/Caja/Tarjeta.
    public static func billPayment(
        date: Date, memo: String, amount: Int64, payableAccountID: UUID, paymentAccountID: UUID
    ) throws(PostingError) -> JournalEntryDraft {
        try transfer(date: date, memo: memo, source: .billPayment, amount: amount,
                     debit: payableAccountID, credit: paymentAccountID)
    }

    /// Gasto pagado al momento: Debe Gastos / Haber cuenta de pago.
    public static func expense(
        date: Date, memo: String, paymentAccountID: UUID, lines: [CostLine]
    ) throws(PostingError) -> JournalEntryDraft {
        try costDocument(date: date, memo: memo, source: .expense, creditAccountID: paymentAccountID, lines: lines)
    }

    /// Pago de sales tax a la agencia: Debe Sales Tax Payable / Haber Banco.
    public static func salesTaxPayment(
        date: Date, memo: String, amount: Int64, liabilityAccountID: UUID, paymentAccountID: UUID
    ) throws(PostingError) -> JournalEntryDraft {
        try transfer(date: date, memo: memo, source: .salesTaxPayment, amount: amount,
                     debit: liabilityAccountID, credit: paymentAccountID)
    }

    // MARK: - Auxiliares

    private static func transfer(
        date: Date, memo: String, source: EntrySource, amount: Int64, debit: UUID, credit: UUID
    ) throws(PostingError) -> JournalEntryDraft {
        guard amount > 0 else { throw .nonPositiveAmount }
        guard debit != credit else { throw .sameAccount }
        return JournalEntryDraft(date: date, memo: memo, source: source,
                                 lines: [.debit(debit, amount), .credit(credit, amount)])
    }

    private static func costDocument(
        date: Date, memo: String, source: EntrySource, creditAccountID: UUID, lines: [CostLine]
    ) throws(PostingError) -> JournalEntryDraft {
        guard !lines.isEmpty else { throw .noLines }
        guard lines.allSatisfy({ $0.amount > 0 }) else { throw .nonPositiveAmount }
        guard lines.contains(where: { $0.accountID != creditAccountID }) else { throw .sameAccount }
        let total = lines.reduce(0) { $0 + $1.amount }
        let debits: [JournalLineDraft] = lines.map { .debit($0.accountID, $0.amount, memo: $0.memo) }
        return JournalEntryDraft(date: date, memo: memo, source: source,
                                 lines: debits + [.credit(creditAccountID, total)])
    }

    /// Suma importes por cuenta conservando el orden de primera aparición.
    private static func grouped(_ pairs: [(UUID, Int64)]) -> [(UUID, Int64)] {
        var order: [UUID] = []
        var sums: [UUID: Int64] = [:]
        for (account, amount) in pairs {
            if sums[account] == nil { order.append(account) }
            sums[account, default: 0] += amount
        }
        return order.map { ($0, sums[$0]!) }
    }
}
