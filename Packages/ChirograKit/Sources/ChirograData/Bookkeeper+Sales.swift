import ChirograCore
import Foundation
import SwiftData

// MARK: - Clientes: notas fechadas (canvas `ClienteFicha`, `MacClienteFicha`)

extension Bookkeeper {

    /// Añade una nota fechada a la ficha del cliente. El autor es el `actor` de este `Bookkeeper`.
    @discardableResult
    public func addNote(to customer: Customer, text: String, date: Date = Date()) throws -> CustomerNote {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La nota está vacía.")) }
        let note = CustomerNote(customer: customer, date: date, text: text, author: actor)
        insert(note)
        try saveOrRollback()
        return note
    }

    public func updateNote(_ note: CustomerNote, text: String, date: Date? = nil) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La nota está vacía.")) }
        note.text = text
        if let date { note.date = date }
        try saveOrRollback()
    }

    public func deleteNote(_ note: CustomerNote) throws {
        context.delete(note)
        try saveOrRollback()
    }
}

// MARK: - Facturas: historial de envíos y recordatorios (canvas `FacturaEnviar`, `MacClienteFicha`, `MacInicio`)

extension Bookkeeper {

    /// Registra que la factura se envió (hoja «Para / Asunto»). La app no manda correos: abre el redactor del sistema
    /// y, al volver, anota el envío aquí.
    @discardableResult
    public func recordInvoiceSent(_ invoice: Invoice, to recipient: String, subject: String, message: String = "",
                                  date: Date = Date()) throws -> InvoiceEvent {
        try recordInvoiceEvent(.sent, invoice: invoice, recipient: recipient, subject: subject, message: message, date: date)
    }

    /// Registra un recordatorio de pago («Recordatorio enviado hoy»). Solo para facturas pendientes de cobro.
    @discardableResult
    public func recordReminder(_ invoice: Invoice, to recipient: String, subject: String, message: String = "",
                               date: Date = Date()) throws -> InvoiceEvent {
        guard invoice.isOpen else { throw BookkeepingError.invalidState(String(localized: "La factura no está pendiente de cobro.")) }
        return try recordInvoiceEvent(.reminder, invoice: invoice, recipient: recipient, subject: subject, message: message, date: date)
    }

    private func recordInvoiceEvent(_ kind: InvoiceEventKind, invoice: Invoice, recipient: String, subject: String,
                                    message: String, date: Date) throws -> InvoiceEvent {
        guard invoice.status != .draft, invoice.status != .void else {
            throw BookkeepingError.invalidState(String(localized: "Solo se envían facturas emitidas."))
        }
        let event = InvoiceEvent(invoice: invoice, kind: kind, date: date, recipient: recipient, subject: subject, message: message)
        insert(event)
        audit("Invoice", invoice.id, kind.rawValue,
              kind == .sent ? String(localized: "Factura \(invoice.number) enviada a \(recipient)") : String(localized: "Recordatorio de \(invoice.number) a \(recipient)"))
        try saveOrRollback()
        return event
    }
}

// MARK: - Facturas: corregir una emitida (como los gastos contabilizados, `updateExpense`)

extension Bookkeeper {

    /// Se puede editar una factura emitida mientras no tenga cobros ni notas de crédito: con ellos el asiento ya
    /// tiene otros que dependen de él, y se corrige con una nota de crédito (o se anula, si no tiene cobros).
    public func canEditIssued(_ invoice: Invoice) -> Bool {
        invoice.status == .sent && invoice.amountPaid == 0 && invoice.creditsApplied == 0
            && (invoice.creditNotes ?? []).isEmpty && (invoice.paymentApplications ?? []).isEmpty
    }

    /// Corrige una factura emitida sin cobros ni créditos y **conserva su número**.
    ///
    /// - Si cambia el asiento (cliente, fecha, líneas, impuesto, descuento): el asiento de emisión **no se toca**
    ///   (es inmutable); se revierte con un asiento espejo en su misma fecha y se contabiliza uno nuevo con los datos
    ///   corregidos. Quedan enlazados (`replacesEntryID` / `replacedByEntryID`) y la factura apunta al nuevo.
    /// - Si solo cambia el texto (vencimiento, mensaje, descripciones con el mismo importe): se guarda sin asientos.
    ///
    /// Si se mantiene el impuesto, se usan las tasas con que se emitió (como las notas de crédito), aunque después se
    /// haya editado alguna; si se elige otro, las vigentes. En los dos casos queda un `AuditEvent` de la factura
    /// («edit» con asientos, «editText» sin ellos) que la actividad muestra como «Editada». Si la fecha original o la
    /// nueva caen en un periodo cerrado falla; usa `unlockedForClosedPeriod(password:)`. Devuelve el asiento nuevo, o
    /// `nil` si no hizo falta.
    @discardableResult
    public func updateIssuedInvoice(_ invoice: Invoice, with input: InvoiceDraftInput) throws -> JournalEntry? {
        guard canEditIssued(invoice) else {
            throw BookkeepingError.invalidState(invoice.status == .sent || invoice.status == .partiallyPaid || invoice.status == .paid
                ? String(localized: "La factura tiene cobros o créditos: corrígela con una nota de crédito.")
                : String(localized: "Solo se editan facturas emitidas sin cobros ni créditos."))
        }
        guard input.customer != nil else { throw BookkeepingError.invalidState(String(localized: "La factura necesita un cliente.")) }
        guard let original = try entry(id: invoice.journalEntryID), original.status == .posted, !original.isReversed else {
            throw BookkeepingError.invalidState(String(localized: "El asiento de la factura ya fue revertido."))
        }
        let keptTax = input.taxGroupID == invoice.taxGroupID && !(invoice.taxLines ?? []).isEmpty
        let components = keptTax ? try issuedTaxComponents(of: invoice) : try taxComponents(groupID: input.taxGroupID, on: input.issueDate)
        let pricesIncludeTax = input.pricesIncludeTax ?? invoice.pricesIncludeTax
        // Todo se valida antes de tocar la factura: con sus líneas cambiadas, `rollback()` deja la relación en un estado
        // que SwiftData no sabe leer, y un segundo intento (p. ej. tras desbloquear el periodo) se caía.
        let posting = try invoicePosting(number: invoice.number, customer: input.customer, date: input.issueDate,
                                         lines: input.lines.map { ($0.incomeAccountID, $0.amount, $0.isTaxable, $0.details) },
                                         discount: input.discount, pricesIncludeTax: pricesIncludeTax, taxComponents: components)
        let accountingChanged = !Calendar.current.isDate(original.date, inSameDayAs: posting.entry.date)
            || invoice.customer?.id != input.customer?.id
            || Self.netByAccount(original.draft.lines) != Self.netByAccount(posting.entry.lines)
        // Solo texto: como en los gastos, se guarda aunque la factura esté en un periodo cerrado.
        if accountingChanged {
            try validate(posting.entry)
            try validate(original.draft.reversal(on: original.date))
        }
        try ensureWritable()
        // Guardar sin haber cambiado nada no deja rastro.
        guard accountingChanged || Self.snapshot(of: invoice) != Self.snapshot(of: input, pricesIncludeTax: pricesIncludeTax) else { return nil }

        let previousTotal = invoice.total
        do {
            apply(input, to: invoice)
            store(posting, in: invoice)
            guard accountingChanged else {
                audit("Invoice", invoice.id, "editText", String(localized: "Factura \(invoice.number) editada (sin cambios contables)"))
                try commit()
                return nil
            }
            try reverse(original, on: original.date, memo: String(localized: "Reversión por edición: \(original.memo)"), save: false)
            let replacement = try post(posting.entry, sourceDocumentID: invoice.id, save: false)
            replacement.lines?.forEach { $0.customerID = invoice.customer?.id }
            replacement.replacesEntryID = original.id
            original.replacedByEntryID = replacement.id
            invoice.journalEntryID = replacement.id
            audit("Invoice", invoice.id, "edit", String(localized: "Factura \(invoice.number) editada: \(Money(minorUnits: previousTotal).formatted()) → \(Money(minorUnits: posting.total).formatted()) (asiento \(original.number) revertido, nuevo \(replacement.number))"))
            try commit()
            return replacement
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Ediciones de la factura (con o sin asientos), de la más antigua a la más reciente.
    public func edits(of invoice: Invoice) throws -> [AuditEvent] {
        let id: UUID? = invoice.id
        let entity = "Invoice"
        return try fetch(AuditEvent.self, #Predicate { $0.entityID == id && $0.subjectEntity == entity }, sortBy: [SortDescriptor(\.date)])
            .filter { $0.action == "edit" || $0.action == "editText" }
    }

    /// Historial de asientos de una factura (emisión, reversiones y vigente), del más antiguo al más nuevo.
    public func entries(ofInvoice invoice: Invoice) throws -> [JournalEntry] {
        let id: UUID? = invoice.id
        return try fetch(JournalEntry.self, #Predicate { $0.sourceDocumentID == id }, sortBy: [SortDescriptor(\.number)])
    }

    /// Lo que el editor puede cambiar de una factura, para saber si hubo cambios.
    private static func snapshot(of invoice: Invoice) -> String {
        let lines = invoice.sortedLines.map { "\($0.details)|\($0.quantity)|\($0.unitPrice)|\($0.isTaxable)|\($0.incomeAccountID?.uuidString ?? "")" }
        return snapshot(customer: invoice.customer?.id, issue: invoice.issueDate, due: invoice.dueDate, tax: invoice.taxGroupID,
                        discount: invoice.discount, message: invoice.customerMessage, included: invoice.pricesIncludeTax, lines: lines)
    }

    private static func snapshot(of input: InvoiceDraftInput, pricesIncludeTax: Bool) -> String {
        let lines = input.lines.map { "\($0.details)|\($0.quantity)|\($0.unitPrice)|\($0.isTaxable)|\($0.incomeAccountID?.uuidString ?? "")" }
        return snapshot(customer: input.customer?.id, issue: input.issueDate, due: input.dueDate, tax: input.taxGroupID,
                        discount: input.discount, message: input.customerMessage, included: pricesIncludeTax, lines: lines)
    }

    private static func snapshot(customer: UUID?, issue: Date, due: Date, tax: UUID?, discount: Int64, message: String,
                                 included: Bool, lines: [String]) -> String {
        let day = { (date: Date) in Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate }
        return "\(customer?.uuidString ?? "")#\(day(issue))#\(day(due))#\(tax?.uuidString ?? "")#\(discount)#\(message)#\(included)#"
            + lines.joined(separator: ";")
    }

    /// Debe − Haber por cuenta, sin las cuentas que quedan en cero: dos asientos con el mismo neto son el mismo efecto.
    private static func netByAccount(_ lines: [JournalLineDraft]) -> [UUID: Int64] {
        lines.reduce(into: [UUID: Int64]()) { $0[$1.accountID, default: 0] += $1.debit - $1.credit }.filter { $0.value != 0 }
    }
}

// MARK: - Estimados (canvas `Estimado`)

/// Totales de un estimado o de un borrador, calculados igual que al emitir la factura.
public struct DocumentTotals: Sendable, Equatable {
    public var subtotal: Int64
    public var discount: Int64
    public var tax: Int64
    public var total: Int64
    public var taxes: [TaxComponentAmount]

    public static let zero = DocumentTotals(subtotal: 0, discount: 0, tax: 0, total: 0, taxes: [])
}

extension Bookkeeper {

    public func estimates() throws -> [Estimate] {
        try fetch(Estimate.self, sortBy: [SortDescriptor(\.issueDate, order: .reverse)])
    }

    /// Facturas creadas a partir del estimado.
    public func invoices(for estimate: Estimate) throws -> [Invoice] {
        let estimateID: UUID? = estimate.id
        return try fetch(Invoice.self, #Predicate { $0.estimateID == estimateID }, sortBy: [SortDescriptor(\.createdAt)])
    }

    /// Crea o edita un estimado (no hace asiento). El número `E-` se asigna la primera vez. No se edita uno convertido
    /// ni uno que ya tiene facturas.
    @discardableResult
    public func saveEstimate(_ input: EstimateInput, into existing: Estimate? = nil) throws -> Estimate {
        if let existing, existing.status == .converted || existing.hasInvoices {
            throw BookkeepingError.invalidState(String(localized: "Un estimado que ya pasó a factura no se edita."))
        }
        let estimate = existing ?? Estimate(customer: input.customer, issueDate: input.issueDate, expirationDate: input.expirationDate)
        if existing == nil {
            insert(estimate)
            estimate.number = try nextDocumentNumber(.estimate)
            estimate.pricesIncludeTax = try company()?.pricesIncludeTax ?? false
        }
        if let pricesIncludeTax = input.pricesIncludeTax { estimate.pricesIncludeTax = pricesIncludeTax }
        estimate.customer = input.customer
        estimate.title = input.title
        estimate.issueDate = input.issueDate
        estimate.expirationDate = input.expirationDate
        estimate.taxGroupID = input.taxGroupID
        estimate.discount = input.discount
        estimate.customerMessage = input.customerMessage
        estimate.memo = input.memo
        for line in estimate.lines ?? [] { context.delete(line) }
        estimate.lines = []
        for (index, line) in input.lines.enumerated() {
            let model = EstimateLine(details: line.details, quantity: line.quantity, unitPrice: line.unitPrice,
                                     isTaxable: line.isTaxable, incomeAccountID: line.incomeAccountID, order: index)
            model.estimate = estimate
            insert(model)
        }
        let totals = try totals(for: estimate)
        estimate.subtotal = totals.subtotal
        estimate.taxTotal = totals.tax
        estimate.total = totals.total
        audit("Estimate", estimate.id, existing == nil ? "create" : "update", String(localized: "Estimado \(estimate.number)"))
        try saveOrRollback()
        return estimate
    }

    /// Totales del estimado con las mismas reglas que una factura (descuento antes de impuesto, cliente exento,
    /// precios con impuesto incluido). Las líneas sin importe no cuentan.
    public func totals(for estimate: Estimate) throws -> DocumentTotals {
        let lines = estimate.sortedLines.map {
            SalesLine(incomeAccountID: $0.incomeAccountID ?? UUID(), amount: $0.amount, isTaxable: $0.isTaxable)
        }
        return try documentTotals(lines: lines, discount: estimate.discount, taxGroupID: estimate.taxGroupID, on: estimate.issueDate,
                                  customer: estimate.customer, pricesIncludeTax: estimate.pricesIncludeTax)
    }

    /// Totales de un borrador de factura (para la vista previa antes de emitir).
    public func totals(for invoice: Invoice) throws -> DocumentTotals {
        let lines = invoice.sortedLines.map {
            SalesLine(incomeAccountID: $0.incomeAccountID ?? UUID(), amount: $0.amount, isTaxable: $0.isTaxable)
        }
        return try documentTotals(lines: lines, discount: invoice.discount, taxGroupID: invoice.taxGroupID, on: invoice.issueDate,
                                  customer: invoice.customer, pricesIncludeTax: invoice.pricesIncludeTax)
    }

    private func documentTotals(lines: [SalesLine], discount: Int64, taxGroupID: UUID?, on date: Date, customer: Customer?,
                                pricesIncludeTax: Bool) throws -> DocumentTotals {
        let lines = lines.filter { $0.amount > 0 }
        guard !lines.isEmpty else { return .zero }
        let subtotal = lines.reduce(0) { $0 + $1.amount }
        let posting: InvoicePosting
        do {
            posting = try PostingRules.invoice(
                date: date, memo: "", receivableAccountID: UUID(), lines: lines,
                taxComponents: try taxComponents(groupID: taxGroupID, on: date),
                customerIsTaxExempt: customer?.isTaxExempt ?? false,
                discount: min(max(discount, 0), subtotal), discountAccountID: UUID(), pricesIncludeTax: pricesIncludeTax)
        } catch {
            return DocumentTotals(subtotal: subtotal, discount: 0, tax: 0, total: subtotal, taxes: [])
        }
        return DocumentTotals(subtotal: posting.subtotal, discount: posting.discount, tax: posting.totalTax, total: posting.total, taxes: posting.taxes)
    }

    /// Cambia el estado de un estimado: enviado, aceptado (por quién), rechazado o vencido. «Convertido» solo lo pone
    /// `convertToInvoice`; uno convertido ya no cambia.
    public func setStatus(_ status: EstimateStatus, of estimate: Estimate, acceptedBy: String = "", date: Date = Date()) throws {
        guard estimate.status != .converted else {
            throw BookkeepingError.invalidState(String(localized: "El estimado ya se convirtió en factura."))
        }
        guard status != .converted else {
            throw BookkeepingError.invalidState(String(localized: "Para convertirlo en factura usa «Convertir en factura»."))
        }
        estimate.status = status
        switch status {
        case .sent: estimate.sentDate = estimate.sentDate ?? date
        case .accepted:
            estimate.acceptedDate = date
            estimate.acceptedBy = acceptedBy
        default: break
        }
        audit("Estimate", estimate.id, status.rawValue, String(localized: "Estimado \(estimate.number): \(status.auditTitle)"))
        try saveOrRollback()
    }

    /// Convierte (todo o parte de) un estimado en una **factura en borrador** con sus líneas, impuesto, mensaje y la
    /// parte proporcional del descuento. No hace asiento: el asiento llega al emitir la factura.
    ///
    /// Cada línea del estimado lleva la cantidad ya facturada; cuando no queda nada por facturar el estimado pasa a
    /// «convertido». Con un anticipo (`.percent(50)`) queda «aceptado» con el resto pendiente.
    @discardableResult
    public func convertToInvoice(_ estimate: Estimate, portion: EstimateConversion = .all, issueDate: Date = Date(),
                                 calendar: Calendar = .current) throws -> Invoice {
        guard estimate.status != .converted, estimate.status != .declined else {
            throw BookkeepingError.invalidState(String(localized: "Este estimado no se puede convertir."))
        }
        let lines = estimate.sortedLines
        let quantities: [Decimal] = lines.map { line in
            let remaining = max(line.remainingQuantity, 0)
            switch portion {
            case .all: return remaining
            case .percent(let percent):
                return min(remaining, line.quantity * max(percent, 0) / 100)
            case .lines(let ids): return ids.contains(line.id) ? remaining : 0
            }
        }
        let chosen = zip(lines, quantities).filter { $0.1 > 0 && EstimateLine.amount(quantity: $0.1, unitPrice: $0.0.unitPrice) > 0 }
        guard !chosen.isEmpty else { throw BookkeepingError.invalidState(String(localized: "No queda nada por facturar en lo elegido.")) }

        let invoice = Invoice(customer: estimate.customer, issueDate: issueDate)
        insert(invoice)
        let defaults = try newInvoiceDefaults(for: estimate.customer, issueDate: issueDate, calendar: calendar)
        invoice.dueDate = defaults.dueDate
        invoice.taxGroupID = estimate.taxGroupID
        invoice.pricesIncludeTax = estimate.pricesIncludeTax
        invoice.customerMessage = estimate.customerMessage.isEmpty ? defaults.customerMessage : estimate.customerMessage
        invoice.memo = String(localized: "Estimado \(estimate.number)")
        invoice.estimateID = estimate.id
        for (index, (line, quantity)) in chosen.enumerated() {
            let model = InvoiceLine(details: line.details, quantity: quantity, unitPrice: line.unitPrice, isTaxable: line.isTaxable,
                                    incomeAccountID: line.incomeAccountID, order: index)
            model.itemID = line.itemID
            model.invoice = invoice
            insert(model)
            line.invoicedQuantity += quantity
        }
        // Descuento: la parte proporcional a lo facturado; la última factura se lleva lo que quede.
        let invoicedNow = chosen.reduce(Int64(0)) { $0 + EstimateLine.amount(quantity: $1.1, unitPrice: $1.0.unitPrice) }
        let remainingDiscount = estimate.discount - estimate.discountInvoiced
        let share: Int64
        if estimate.isFullyInvoiced {
            share = remainingDiscount
        } else {
            let base = estimate.linesSubtotal
            share = base == 0 ? 0 : min(remainingDiscount, (estimate.discount * invoicedNow).dividedRoundingHalfAwayFromZero(by: base))
        }
        invoice.discount = min(max(share, 0), invoicedNow)
        estimate.discountInvoiced += invoice.discount

        if estimate.isFullyInvoiced {
            estimate.status = .converted
            estimate.convertedDate = issueDate
        } else if estimate.status == .draft || estimate.status == .sent || estimate.status == .expired {
            estimate.status = .accepted
            estimate.acceptedDate = estimate.acceptedDate ?? issueDate
        }
        try storeDraftTotals(of: invoice)
        audit("Estimate", estimate.id, "convert", String(localized: "Estimado \(estimate.number) convertido en factura borrador"))
        try saveOrRollback()
        return invoice
    }
}

extension EstimateStatus {
    /// Para la bitácora («Estimado E-0001: aceptado»); antes salía el valor interno («accepted», QA del 11-nov).
    var auditTitle: String {
        switch self {
        case .draft: String(localized: "estimate.audit.draft", defaultValue: "borrador")
        case .sent: String(localized: "estimate.audit.sent", defaultValue: "enviado")
        case .accepted: String(localized: "estimate.audit.accepted", defaultValue: "aceptado")
        case .declined: String(localized: "estimate.audit.declined", defaultValue: "rechazado")
        case .expired: String(localized: "estimate.audit.expired", defaultValue: "vencido")
        case .converted: String(localized: "estimate.audit.converted", defaultValue: "convertido")
        }
    }
}
