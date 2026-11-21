import Foundation
import SwiftData

// MARK: - Numeración y números repetidos tras sincronizar (DISEÑO §6.5)
//
// Cada serie (`NumberSequence`: facturas F-, notas de crédito NC-, estimados E- y asientos) guarda el siguiente número.
// Con iCloud, dos aparatos sin conexión (o con segundos de diferencia) pueden sacar el mismo: CloudKit se queda con el
// último `nextNumber` que se escribió, y dos aparatos nuevos pueden crear cada uno su serie. Dos defensas:
// 1. Al dar un número se salta el que ya use otro documento de la empresa (y en los asientos, se sigue al mayor), así
//    que un contador atrasado por la sincronización no vuelve a dar números usados.
// 2. Tras cada importación de iCloud (`AppAutomations.afterSync`), `resolveNumberCollisions()` deja una sola serie por
//    tipo y le da un número nuevo al documento repetido que se emitió después; lo anota en la bitácora («renumber») y
//    la campana lo avisa durante 30 días (`NoticeKind.documentRenumbered`), por si ya se le había mandado al cliente.
//    Los asientos guardan su texto («Factura F-1005 · …»): no se editan; el cambio queda en la bitácora.

extension Bookkeeper {
    /// Acción de la bitácora cuando se cambia el número de un documento repetido.
    nonisolated public static let renumberAction = "renumber"
    /// Días que la campana recuerda un número cambiado.
    static let renumberNoticeDays = 30

    /// La serie de ese tipo. Si la sincronización dejó varias, la que va más adelante (la misma en todos los aparatos).
    func sequence(_ kind: DocumentKind) throws -> NumberSequence {
        let raw = kind.rawValue
        let all = try fetch(NumberSequence.self, #Predicate { $0.kindRaw == raw })
        if let best = all.max(by: { ($0.nextNumber, $0.id.uuidString) < ($1.nextNumber, $1.id.uuidString) }) {
            return best
        }
        let format = kind.defaultFormat
        let created = NumberSequence(kind: kind, prefix: format.prefix, nextNumber: format.firstNumber, minimumDigits: format.minimumDigits)
        insert(created)
        return created
    }

    /// Reserva el siguiente número libre de la serie.
    func nextNumber(_ kind: DocumentKind) throws -> Int {
        try reserveNumber(in: try sequence(kind), kind)
    }

    private func reserveNumber(in sequence: NumberSequence, _ kind: DocumentKind) throws -> Int {
        let number = try firstFreeNumber(kind, from: sequence.nextNumber, in: sequence)
        sequence.nextNumber = number + 1
        return number
    }

    /// El primer número desde `start` que no use nadie: en los documentos, que ninguno tenga ese número con formato; en
    /// los asientos (correlativo interno), uno más que el mayor.
    private func firstFreeNumber(_ kind: DocumentKind, from start: Int, in sequence: NumberSequence) throws -> Int {
        if kind == .journalEntry {
            let highest = try fetch(JournalEntry.self, sortBy: [SortDescriptor(\.number, order: .reverse)], limit: 1).first?.number ?? 0
            return max(start, highest + 1)
        }
        var number = start
        while try isDocumentNumberUsed(sequence.format(number), kind) { number += 1 }
        return number
    }

    private func isDocumentNumberUsed(_ text: String, _ kind: DocumentKind) throws -> Bool {
        switch kind {
        case .invoice: try count(Invoice.self, #Predicate { $0.number == text }) > 0
        case .creditNote: try count(CreditNote.self, #Predicate { $0.number == text }) > 0
        case .estimate: try count(Estimate.self, #Predicate { $0.number == text }) > 0
        case .journalEntry: false
        }
    }

    /// Siguiente número con formato, sin reservarlo.
    public func peekDocumentNumber(_ kind: DocumentKind) throws -> String {
        let sequence = try sequence(kind)
        return sequence.format(try firstFreeNumber(kind, from: sequence.nextNumber, in: sequence))
    }

    /// Número de documento con formato. Se asigna al emitir; si tras sincronizar resulta repetido, lo arregla
    /// `resolveNumberCollisions()`.
    public func nextDocumentNumber(_ kind: DocumentKind) throws -> String {
        let sequence = try sequence(kind)
        return sequence.format(try reserveNumber(in: sequence, kind))
    }

    /// Arregla lo que dos aparatos numeraron a la vez: una sola serie por tipo, y a cada factura, nota de crédito,
    /// estimado o asiento con el número de otro (de la misma empresa) le da el siguiente libre; se queda con el suyo el
    /// que se emitió primero. Cada cambio va a la bitácora. Devuelve cuántos documentos cambió. Idempotente.
    @discardableResult
    public func resolveNumberCollisions() throws -> Int {
        var removedSequences = false
        for kind in DocumentKind.allCases {
            let raw = kind.rawValue
            let all = try fetch(NumberSequence.self, #Predicate { $0.kindRaw == raw })
            guard all.count > 1 else { continue }
            let kept = try sequence(kind)
            for extra in all where extra.id != kept.id {
                context.delete(extra)
                removedSequences = true
            }
        }

        var changed = 0
        let invoices = try fetch(Invoice.self).filter { !$0.number.isEmpty }
        for group in Dictionary(grouping: invoices, by: \.number).values where group.count > 1 {
            let ordered = try group.map { (try issuedAt($0), $0) }
                .sorted { ($0.0, $0.1.id.uuidString) < ($1.0, $1.1.id.uuidString) }.map(\.1)
            for invoice in ordered.dropFirst() {
                let old = invoice.number
                invoice.number = try nextDocumentNumber(.invoice)
                auditRenumber(AuditSubject.invoice.rawValue, invoice.id, old, invoice.number,
                              String(localized: "Factura \(old) renumerada a \(invoice.number): otro aparato emitió el mismo número"))
                changed += 1
            }
        }

        let notes = try fetch(CreditNote.self).filter { !$0.number.isEmpty }
        for group in Dictionary(grouping: notes, by: \.number).values where group.count > 1 {
            for note in group.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }).dropFirst() {
                let old = note.number
                note.number = try nextDocumentNumber(.creditNote)
                auditRenumber(Self.creditNoteSubject, note.id, old, note.number,
                              String(localized: "Nota de crédito \(old) renumerada a \(note.number): otro aparato emitió el mismo número"))
                changed += 1
            }
        }

        let estimates = try fetch(Estimate.self).filter { !$0.number.isEmpty }
        for group in Dictionary(grouping: estimates, by: \.number).values where group.count > 1 {
            for estimate in group.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }).dropFirst() {
                let old = estimate.number
                estimate.number = try nextDocumentNumber(.estimate)
                auditRenumber(AuditSubject.estimate.rawValue, estimate.id, old, estimate.number,
                              String(localized: "Estimado \(old) renumerado a \(estimate.number): otro aparato usó el mismo número"))
                changed += 1
            }
        }

        // Asientos: solo el número (propiedad suelta), para no cargar el diario entero en cada sincronización.
        var descriptor = FetchDescriptor<JournalEntry>(predicate: try scoped(nil))
        descriptor.propertiesToFetch = [\.number, \.createdAt]
        let entries = try context.fetch(descriptor)
        for group in Dictionary(grouping: entries, by: \.number).values where group.count > 1 {
            for entry in group.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }).dropFirst() {
                let old = entry.number
                entry.number = try nextNumber(.journalEntry)
                auditRenumber(AuditSubject.journalEntry.rawValue, entry.id, String(old), String(entry.number),
                              String(localized: "Asiento \(old) renumerado a \(entry.number): otro aparato usó el mismo número"))
                changed += 1
            }
        }

        if changed > 0 || removedSequences { try saveOrRollback() }
        return changed
    }

    /// Las notas de crédito no tienen `AuditSubject` propio (su historial va con la factura).
    nonisolated public static let creditNoteSubject = "CreditNote"

    /// Cuándo se emitió la factura: su asiento de emisión (el número se da al emitir), o al crearla si no lo tiene.
    private func issuedAt(_ invoice: Invoice) throws -> Date {
        try entry(id: invoice.journalEntryID)?.createdAt ?? invoice.createdAt
    }

    private func auditRenumber(_ entity: String, _ id: UUID, _ old: String, _ new: String, _ summary: String) {
        var changes = AuditChanges()
        changes.field(String(localized: "Número"), old, new)
        audit(entity, id, Self.renumberAction, summary, changes: changes)
    }
}

extension AuditEvent {
    /// En un cambio de número («renumber»), el número de antes y el nuevo, leídos del detalle («Número: F-1005 → F-1012»).
    public var renumbered: (old: String, new: String)? {
        guard action == Bookkeeper.renumberAction, let line = changeDetails.split(separator: "\n").first,
              let colon = line.range(of: ": ") else { return nil }
        let parts = line[colon.upperBound...].components(separatedBy: " → ")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}
