import ChirograCore
import Foundation

// MARK: - Saldos de los documentos tras sincronizar (auditoría del 23-nov)
//
// `amountPaid` y `creditsApplied` de las facturas, `amountPaid` de las facturas de proveedor y `unappliedAmount` /
// `refundedAmount` de las notas de crédito son sumas guardadas de registros propios: cada cobro (`PaymentApplication`),
// pago (`BillPayment`), saldo a favor aplicado (`CreditApplication`) y reembolso (su asiento) es un registro aparte, y
// esos nunca chocan entre aparatos. La suma guardada sí: con iCloud, si dos aparatos cobran la misma factura a la vez,
// cada uno sube su suma y se queda la del último. El diario está bien (cada cobro tiene su asiento), pero la factura
// diría que se debe más (o menos) de lo que se debe, y el estado, la antigüedad y el tope de cobro saldrían mal.
//
// `reconcileDocumentBalances` vuelve a sacar cada suma de sus registros y corrige el documento y su estado, con una
// línea en la bitácora. No toca borradores ni anulados, ni un documento con registros a medio llegar (un cobro sin su
// asiento). Para no corregir mientras aún llegan registros de otro aparato, la app solo corrige lo que ya vio igual en
// la pasada anterior (`confirming`, `AppAutomations`).

/// Resultado de `reconcileDocumentBalances`.
public struct DocumentBalanceCheck: Sendable, Equatable {
    /// Diferencias encontradas en esta pasada («id|valores buenos»), para confirmarlas en la siguiente.
    public var discrepancies: Set<String>
    /// Documentos corregidos.
    public var repaired: Int
}

extension Bookkeeper {

    /// Recalcula lo cobrado, lo acreditado y lo reembolsado de facturas, facturas de proveedor y notas de crédito a
    /// partir de sus registros y corrige lo que no cuadre (ver arriba). Con `confirming`, solo corrige las diferencias
    /// que ya estaban en esa pasada anterior; sin él (`nil`), todas. Es idempotente.
    @discardableResult
    public func reconcileDocumentBalances(confirming previous: Set<String>? = nil) throws -> DocumentBalanceCheck {
        let entries = Dictionary(try fetch(JournalEntry.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var found: Set<String> = []
        var repaired = 0
        func shouldFix(_ key: String) -> Bool {
            found.insert(key)
            return previous?.contains(key) ?? true
        }
        /// Asiento contabilizado y sin revertir; `nil` si aún no llegó.
        func live(_ entryID: UUID?) -> Bool? {
            guard let entryID, let entry = entries[entryID] else { return nil }
            return entry.status == .posted && !entry.isReversed
        }

        // Facturas emitidas: lo cobrado es lo de sus cobros no anulados; lo acreditado, sus aplicaciones de saldo a favor.
        for invoice in try fetch(Invoice.self) where [.sent, .partiallyPaid, .paid].contains(invoice.status) {
            var paid: Int64 = 0
            var complete = true
            for application in invoice.paymentApplications ?? [] {
                guard let payment = application.payment, let counts = live(payment.journalEntryID) else { complete = false; break }
                if counts { paid += application.amount }
            }
            guard complete else { continue }
            let credited = (invoice.creditApplications ?? []).reduce(Int64(0)) { $0 + $1.amount }
            let status: InvoiceStatus = paid == 0 && credited == 0 ? .sent : (invoice.total - paid - credited <= 0 ? .paid : .partiallyPaid)
            guard invoice.amountPaid != paid || invoice.creditsApplied != credited || invoice.status != status,
                  shouldFix("\(invoice.id)|\(paid)|\(credited)") else { continue }
            var changes = AuditChanges()
            if invoice.amountPaid != paid { changes.money(String(localized: "Cobrado"), invoice.amountPaid, paid) }
            if invoice.creditsApplied != credited { changes.money(String(localized: "Saldo a favor aplicado"), invoice.creditsApplied, credited) }
            invoice.amountPaid = paid
            invoice.creditsApplied = credited
            invoice.status = status
            audit("Invoice", invoice.id, "syncRepair",
                  String(localized: "Saldo de la factura \(invoice.number) corregido tras sincronizar"), changes: changes)
            repaired += 1
        }

        // Facturas de proveedor registradas: lo pagado es lo de sus pagos con asiento vigente.
        for bill in try fetch(Bill.self) where [.open, .partiallyPaid, .paid].contains(bill.status) && bill.journalEntryID != nil {
            var paid: Int64 = 0
            var complete = true
            for payment in bill.payments ?? [] {
                guard let counts = live(payment.journalEntryID) else { complete = false; break }
                if counts { paid += payment.amount }
            }
            guard complete else { continue }
            let status: BillStatus = paid == 0 ? .open : (bill.total - paid <= 0 ? .paid : .partiallyPaid)
            guard bill.amountPaid != paid || bill.status != status, shouldFix("\(bill.id)|\(paid)") else { continue }
            var changes = AuditChanges()
            changes.money(String(localized: "Pagado"), bill.amountPaid, paid)
            bill.amountPaid = paid
            bill.status = status
            if status == .paid { clearSchedule(of: bill) }
            audit("Bill", bill.id, "syncRepair",
                  String(localized: "Saldo de la factura de proveedor \(bill.vendorNumber) corregido tras sincronizar"), changes: changes)
            repaired += 1
        }

        // Notas de crédito: lo reembolsado de cada cliente es lo de sus reembolsos vigentes, repartido entre sus notas de
        // la más antigua a la más reciente (como `refundCustomerCredit`) si la suma guardada no coincide; lo que queda
        // a favor, el total menos lo aplicado y lo reembolsado.
        let receivable = Set(try accounts(includeArchived: true).filter { $0.subtype == .accountsReceivable }.map(\.id))
        let refundEntries = entries.values.filter { $0.source == .customerRefund && $0.status == .posted && !$0.isReversed
            && $0.reversesEntryID == nil }
        var refunds: [UUID: Int64] = [:]
        for entry in refundEntries {
            guard let customerID = entry.sourceDocumentID else { continue }
            refunds[customerID, default: 0] += (entry.lines ?? []).reduce(Int64(0)) { $0 + $1.debit }
        }
        let notes = try fetch(CreditNote.self).filter { $0.journalEntryID != nil }
        func appliedTotal(_ note: CreditNote) -> Int64 { (note.applications ?? []).reduce(Int64(0)) { $0 + $1.amount } }
        // Si la suma guardada no coincide, lo reembolsado se vuelve a repartir como lo hace `refundCustomerCredit`
        // (`refundAllocations`: cada reembolso con las notas que ya existían, hasta lo que cada una tenía libre).
        let reassigned = Self.refundAllocations(refunds: Array(refundEntries), notes: notes, receivable: receivable) {
            $0.total - appliedTotal($0)
        }
        for (customerID, group) in Dictionary(grouping: notes, by: { $0.customer?.id }) {
            let ordered = group.sorted { ($0.date, $0.createdAt, $0.id.uuidString) < ($1.date, $1.createdAt, $1.id.uuidString) }
            let applied = Dictionary(ordered.map { ($0.id, appliedTotal($0)) }, uniquingKeysWith: { first, _ in first })
            var refunded = Dictionary(ordered.map { ($0.id, $0.refundedAmount) }, uniquingKeysWith: { first, _ in first })
            let total = customerID.flatMap { refunds[$0] } ?? 0
            if refunded.values.reduce(0, +) != total {
                let mine = refundEntries.filter { $0.sourceDocumentID == customerID }
                let shares = mine.flatMap { reassigned[$0.id] ?? [] }
                guard shares.reduce(0, { $0 + $1.amount }) == total else { continue }      // no se adivina
                refunded = Dictionary(ordered.map { ($0.id, Int64(0)) }, uniquingKeysWith: { first, _ in first })
                for share in shares { refunded[share.note.id, default: 0] += share.amount }
            }
            for note in ordered {
                let refund = refunded[note.id, default: 0]
                let unapplied = note.total - applied[note.id, default: 0] - refund
                guard unapplied >= 0, note.refundedAmount != refund || note.unappliedAmount != unapplied,
                      shouldFix("\(note.id)|\(refund)|\(unapplied)") else { continue }
                var changes = AuditChanges()
                changes.money(String(localized: "Saldo a favor"), note.unappliedAmount, unapplied)
                if note.refundedAmount != refund { changes.money(String(localized: "Reembolsado"), note.refundedAmount, refund) }
                note.refundedAmount = refund
                note.unappliedAmount = unapplied
                // En la bitácora va con su factura (no hay «Nota de crédito» entre sus tipos).
                audit("Invoice", note.invoice?.id, "syncRepair",
                      String(localized: "Saldo de la nota de crédito \(note.number) corregido tras sincronizar"), changes: changes)
                repaired += 1
            }
        }

        if repaired > 0 { try saveOrRollback() }
        return DocumentBalanceCheck(discrepancies: found, repaired: repaired)
    }
}
