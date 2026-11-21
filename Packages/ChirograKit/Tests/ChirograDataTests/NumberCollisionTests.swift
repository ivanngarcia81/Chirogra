import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Números repetidos al emitir en dos aparatos a la vez (DISEÑO §6.5; revisión externa del 21-nov): se saltan los
/// números usados y, tras sincronizar, `resolveNumberCollisions()` renumera el documento emitido después.
@MainActor
@Suite("Números repetidos entre aparatos")
struct NumberCollisionTests {
    let container: ModelContainer
    let books: Bookkeeper

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Números LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func draft(_ name: String, number: String = "") throws -> Invoice {
        let customer = Customer(name: name)
        books.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: Date(), dueDate: Date(),
                                                            lines: [.init(details: "Servicio", unitPrice: 10_000, incomeAccountID: income.id)]))
        invoice.number = number
        return invoice
    }

    func sequence(_ kind: DocumentKind) throws -> NumberSequence { try books.sequence(kind) }

    @Test("Un contador atrasado por la sincronización no vuelve a dar un número usado")
    func skipsUsedNumbers() throws {
        let first = try draft("Ana")
        try books.issue(first)
        #expect(first.number == "F-1001")
        // Otro aparato escribió un contador viejo (CloudKit: gana el último).
        try sequence(.invoice).nextNumber = 1001
        #expect(try books.peekDocumentNumber(.invoice) == "F-1002")
        let second = try draft("Beto")
        try books.issue(second)
        #expect(second.number == "F-1002")
        #expect(try sequence(.invoice).nextNumber == 1003)
    }

    @Test("Dos facturas con el mismo número: la emitida después pasa al siguiente libre, con bitácora y aviso")
    func renumbersLaterInvoice() throws {
        let first = try draft("Ana")
        try books.issue(first)
        // Lo que llega de otro aparato sin conexión: su propia F-1001, emitida después.
        let other = try draft("Beto", number: "F-1001")
        try books.issue(other)
        #expect(first.number == "F-1001" && other.number == "F-1001")

        #expect(try books.resolveNumberCollisions() == 1)
        #expect(first.number == "F-1001")
        #expect(other.number == "F-1002")
        #expect(try books.peekDocumentNumber(.invoice) == "F-1003")

        let event = try #require(try books.auditLog(entityID: other.id).first { $0.action == Bookkeeper.renumberAction })
        #expect(event.renumbered?.old == "F-1001" && event.renumbered?.new == "F-1002")
        let notice = try #require(try books.notices().first { $0.kind == .documentRenumbered })
        #expect(notice.previousReference == "F-1001" && notice.reference == "F-1002")
        #expect(notice.documentID == other.id && notice.documentKind == .invoice && notice.party == "Beto")

        // Idempotente.
        #expect(try books.resolveNumberCollisions() == 0)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
    }

    @Test("Dos series del mismo tipo (dos aparatos nuevos): queda la que va más adelante")
    func mergesDuplicateSequences() throws {
        let first = try draft("Ana")
        try books.issue(first)
        let stale = NumberSequence(kind: .invoice, prefix: "F-", nextNumber: 1001, minimumDigits: 4)
        books.insert(stale)
        try context.save()
        #expect(try sequence(.invoice).nextNumber == 1002)

        _ = try books.resolveNumberCollisions()
        let raw = DocumentKind.invoice.rawValue
        #expect(try books.fetch(NumberSequence.self, #Predicate { $0.kindRaw == raw }).count == 1)
        #expect(try books.peekDocumentNumber(.invoice) == "F-1002")
    }

    @Test("Asientos con el mismo número: el creado después pasa al siguiente")
    func renumbersJournalEntries() throws {
        let first = try draft("Ana")
        try books.issue(first)
        let second = try draft("Beto")
        try books.issue(second)
        let entries = try books.fetch(JournalEntry.self).sorted { $0.number < $1.number }
        #expect(entries.count == 2)
        entries[1].number = entries[0].number
        try context.save()

        #expect(try books.resolveNumberCollisions() == 1)
        #expect(Set(try books.fetch(JournalEntry.self).map(\.number)).count == 2)
        // Los asientos no salen en la campana.
        #expect(try books.notices().contains { $0.kind == .documentRenumbered } == false)
    }
}
