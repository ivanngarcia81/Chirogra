import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Saldos de los documentos tras sincronizar (auditoría del 23-nov, `Bookkeeper+Consistency.swift`). CloudKit no se puede
/// correr en una prueba: se deja el documento como lo dejaría «gana el último» (la suma de un solo aparato) y se comprueba
/// que se vuelve a sacar de sus registros.
@MainActor
@Suite("Saldos de facturas, facturas de proveedor y notas tras cambios a la vez en dos aparatos")
struct DocumentBalanceTests {
    let container: ModelContainer
    let books: Bookkeeper
    let customer: Customer
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Saldos LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        customer = Customer(name: "Cliente")
        books.insert(customer)
        try container.mainContext.save()
    }

    func account(_ code: String) throws -> Account { try #require(try books.accounts().first { $0.code == code }) }
    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    func issue(_ amount: Int64, on offset: Int) throws -> Invoice {
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(offset), dueDate: day(offset),
                                                            lines: [.init(details: "Servicio", unitPrice: amount, incomeAccountID: try account("4000").id)]))
        try books.issue(invoice)
        return invoice
    }

    func repairs() throws -> [AuditEvent] {
        try container.mainContext.fetch(FetchDescriptor<AuditEvent>()).filter { $0.action == "syncRepair" }
    }

    @Test("Dos cobros a la vez: la factura se queda con lo de un aparato y se corrige con sus cobros")
    func concurrentPayments() throws {
        let invoice = try issue(10_000, on: -10)
        try books.recordPayment(for: invoice, amount: 5_000, date: day(-5), depositAccount: try account("1010"))
        try books.recordPayment(for: invoice, amount: 3_000, date: day(-5), depositAccount: try account("1010"))
        // Lo que deja iCloud: el otro aparato subió «cobrado 30» y ganó.
        invoice.amountPaid = 3_000
        try container.mainContext.save()

        let check = try books.reconcileDocumentBalances()
        #expect(check.repaired == 1)
        #expect(invoice.amountPaid == 8_000 && invoice.balanceDue == 2_000 && invoice.status == .partiallyPaid)
        let event = try #require(try repairs().first)
        #expect(event.subjectEntity == "Invoice" && event.entityID == invoice.id)
        #expect(try books.reconcileDocumentBalances().repaired == 0)          // idempotente
    }

    @Test("Un cobro anulado en un aparato y otro registrado en el otro")
    func voidAndPaymentAtOnce() throws {
        let invoice = try issue(10_000, on: -10)
        let first = try books.recordPayment(for: invoice, amount: 5_000, date: day(-6), depositAccount: try account("1010"))
        try books.voidPayment(first)
        try books.recordPayment(for: invoice, amount: 3_000, date: day(-5), depositAccount: try account("1010"))
        invoice.amountPaid = 8_000                // el otro aparato no vio la anulación
        try books.reconcileDocumentBalances()
        #expect(invoice.amountPaid == 3_000 && invoice.status == .partiallyPaid)
    }

    @Test("Solo se corrige una diferencia que ya estaba en la pasada anterior")
    func confirmsBeforeRepairing() throws {
        let invoice = try issue(10_000, on: -10)
        try books.recordPayment(for: invoice, amount: 10_000, date: day(-5), depositAccount: try account("1010"))
        invoice.amountPaid = 0
        invoice.status = .sent
        let first = try books.reconcileDocumentBalances(confirming: [])
        #expect(first.repaired == 0 && first.discrepancies.count == 1 && invoice.amountPaid == 0)
        let second = try books.reconcileDocumentBalances(confirming: first.discrepancies)
        #expect(second.repaired == 1 && invoice.amountPaid == 10_000 && invoice.status == .paid)
    }

    @Test("Dos notas con el mismo id (copia restaurada en un aparato y editada en otro) no cierran la app (revisión)")
    func duplicateNoteIDs() throws {
        let invoice = try issue(10_000, on: -10)
        try books.recordPayment(for: invoice, amount: 10_000, date: day(-9), depositAccount: try account("1010"))
        let note = try books.issueCreditNote(for: invoice, amount: 1_000, isTaxable: false, reason: "A", date: day(-8))
        let twin = CreditNote(invoice: invoice, date: day(-8), amount: 1_000, isTaxable: false, reason: "A")
        twin.id = note.id
        twin.journalEntryID = note.journalEntryID
        twin.total = note.total
        twin.unappliedAmount = note.unappliedAmount
        books.insert(twin)
        _ = try books.reconcileDocumentBalances()
    }

    @Test("Con un cobro cuyo asiento aún no llegó, la factura no se toca")
    func skipsWhileRecordsArrive() throws {
        let invoice = try issue(10_000, on: -10)
        let payment = try books.recordPayment(for: invoice, amount: 4_000, date: day(-5), depositAccount: try account("1010"))
        let entry = try #require(try books.entry(id: payment.journalEntryID))
        container.mainContext.delete(entry)
        try container.mainContext.save()
        invoice.amountPaid = 0
        #expect(try books.reconcileDocumentBalances().repaired == 0)
        #expect(invoice.amountPaid == 0)
    }

    @Test("Saldo a favor aplicado y reembolsado a la vez en dos aparatos")
    func concurrentCreditUse() throws {
        let checking = try account("1010")
        let paid = try issue(10_000, on: -30)
        try books.recordPayment(for: paid, amount: 10_000, date: day(-29), depositAccount: checking)
        let note = try books.issueCreditNote(for: paid, amount: 5_000, isTaxable: false, reason: "Devolución", date: day(-20))
        let other = try issue(3_000, on: -15)
        try books.applyCustomerCredit(to: other, amount: 2_000, date: day(-10))
        try books.refundCustomerCredit(customer, amount: 1_000, date: day(-9), from: checking)
        try books.refundCustomerCredit(customer, amount: 1_500, date: day(-8), from: checking)
        // Lo que deja iCloud: la nota y la otra factura con la suma de un solo aparato.
        note.refundedAmount = 1_500
        note.unappliedAmount = 3_500
        other.creditsApplied = 0
        other.status = .sent

        #expect(try books.reconcileDocumentBalances().repaired == 2)
        #expect(note.refundedAmount == 2_500 && note.unappliedAmount == 500 && customer.creditBalance == 500)
        #expect(other.creditsApplied == 2_000 && other.balanceDue == 1_000 && other.status == .partiallyPaid)
    }

    @Test("Factura de proveedor pagada en dos aparatos a la vez")
    func concurrentBillPayments() throws {
        let vendor = Vendor(name: "Proveedor")
        books.insert(vendor)
        let bill = Bill(vendor: vendor, vendorNumber: "P-9", billDate: day(-20))
        books.insert(bill)
        let line = BillLine(details: "Material", amount: 6_000, accountID: try account("5000").id)
        line.bill = bill
        books.insert(line)
        try books.record(bill)
        try books.pay(bill, amount: 2_000, date: day(-10), from: try account("1010"))
        try books.pay(bill, amount: 4_000, date: day(-10), from: try account("1010"))
        bill.amountPaid = 4_000
        bill.status = .partiallyPaid
        #expect(try books.reconcileDocumentBalances().repaired == 1)
        #expect(bill.amountPaid == 6_000 && bill.status == .paid)
    }

    @Test("En libros sanos (los de ejemplo, con cobros, notas, reembolsos y anulaciones) no corrige nada")
    func noFalsePositives() throws {
        let sample = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(sample.mainContext)
        let sampleBooks = Bookkeeper(context: sample.mainContext)
        #expect(try sampleBooks.reconcileDocumentBalances().repaired == 0)

        let checking = try account("1010")
        let a = try issue(10_000, on: -30)
        try books.recordPayment(for: a, amount: 4_000, date: day(-25), depositAccount: checking)
        let voided = try books.recordPayment(for: a, amount: 1_000, date: day(-24), depositAccount: checking)
        try books.voidPayment(voided)
        try books.issueCreditNote(for: a, amount: 8_000, isTaxable: false, reason: "Ajuste", date: day(-20))
        let b = try issue(5_000, on: -15)
        try books.applyCustomerCredit(to: b, amount: 1_000, date: day(-10))
        try books.refundCustomerCredit(customer, amount: 500, date: day(-9), from: checking)
        let check = try books.reconcileDocumentBalances()
        #expect(check.repaired == 0 && check.discrepancies.isEmpty)
    }
}
