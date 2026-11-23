import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// El reporte de sales tax con notas de crédito (auditoría del 23-nov): cada nota resta la base gravable y el impuesto
/// con que **se contabilizó**, no el importe entero como si fuera gravable.
@MainActor
@Suite("Sales tax: notas de crédito con lo que se contabilizó")
struct SalesTaxCreditNoteTests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Impuesto LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func account(_ code: String) throws -> Account { try #require(try books.accounts().first { $0.code == code }) }

    func taxGroup() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", liabilityAccountID: try account("2200").id)
        books.insert(agency)
        let state = TaxRate(name: "Texas", rateMillionths: 62_500, agency: agency)
        let city = TaxRate(name: "Austin", rateMillionths: 20_000, agency: agency)
        books.insert(state)
        books.insert(city)
        let group = TaxGroup(name: "Austin", rates: [state, city])
        books.insert(group)
        try container.mainContext.save()
        return group
    }

    /// Factura con una línea gravable de $100 y otra no gravable de $100, a 8.25 %.
    func mixedInvoice(_ tax: TaxGroup) throws -> Invoice {
        let customer = Customer(name: "Cliente")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: today, dueDate: today, taxGroupID: tax.id, lines: [
            .init(details: "Servicio", unitPrice: 10_000, isTaxable: true, incomeAccountID: try account("4000").id),
            .init(details: "Mano de obra", unitPrice: 10_000, isTaxable: false, incomeAccountID: try account("4100").id),
        ]))
        try books.issue(invoice)
        #expect(invoice.taxTotal == 825)
        return invoice
    }

    func summary() throws -> SalesTaxSummary {
        try books.salesTaxSummary(from: today.addingTimeInterval(-86_400), to: today.addingTimeInterval(86_400))
    }

    /// Lo que quedó en la cuenta de sales tax por pagar (el diario).
    func ledgerTax() throws -> Int64 {
        ReportBuilder.balance(of: try account("2200").ledgerAccount, lines: try books.ledgerLines())
    }

    @Test("Nota sin elegir línea sobre una factura mixta: resta la mitad gravable y su impuesto, como el diario")
    func proratedNote() throws {
        let invoice = try mixedInvoice(try taxGroup())
        let note = try books.issueCreditNote(for: invoice, amount: 10_000, isTaxable: true, reason: "Rebaja")
        #expect(note.taxTotal == 413)                                    // 8.25 % de los $50 gravables
        let report = try summary()
        #expect(report.taxableSales == 10_000 - 5_000)
        #expect(report.totalTax == 825 - 413)
        #expect(report.totalTax == (try ledgerTax()))
    }

    @Test("Nota sobre la línea no gravable: no resta impuesto ni base gravable")
    func nonTaxableLineNote() throws {
        let invoice = try mixedInvoice(try taxGroup())
        let line = try #require(invoice.sortedLines.last?.id)
        let note = try books.issueCreditNote(for: invoice, amount: 4_000, isTaxable: true, reason: "Horas de más", lineID: line)
        #expect(note.taxTotal == 0)
        let report = try summary()
        #expect(report.taxableSales == 10_000 && report.totalTax == 825)
        #expect(report.totalTax == (try ledgerTax()))
    }

    @Test("Nota sobre la línea gravable: resta todo su importe y su impuesto, repartido por tasa")
    func taxableLineNote() throws {
        let invoice = try mixedInvoice(try taxGroup())
        let line = try #require(invoice.sortedLines.first?.id)
        let note = try books.issueCreditNote(for: invoice, amount: 4_000, isTaxable: true, reason: "Devolución", lineID: line)
        #expect(note.taxTotal == 330)
        let report = try summary()
        #expect(report.taxableSales == 6_000 && report.totalTax == 825 - 330)
        #expect(report.totalTax == (try ledgerTax()))
        #expect(report.rows.map(\.tax).reduce(0, +) == report.totalTax)
    }
}
