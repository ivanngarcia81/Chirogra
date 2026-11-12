import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Corregir una factura emitida (build 5): reversión del asiento de emisión + asiento nuevo, mismo número.
@MainActor
@Suite("Editar una factura emitida")
struct InvoiceEditingTests {
    let container: ModelContainer
    let books: Bookkeeper
    let calendar = Calendar(identifier: .gregorian)
    let today: Date

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Prueba LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    func trialBalanced() throws -> Bool {
        ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture).isBalanced
    }

    func balance(_ account: Account) throws -> Int64 {
        ReportBuilder.balance(of: account.ledgerAccount, lines: try books.ledgerLines())
    }

    /// Texas 6.25 % + Austin 2 % = 8.25 %.
    func austin() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", filingFrequency: .quarterly, liabilityAccountID: try account("2200").id)
        context.insert(agency)
        let rates = [("Texas", 62_500), ("Austin", 20_000)].map {
            let rate = TaxRate(name: $0.0, rateMillionths: Int64($0.1), agency: agency)
            context.insert(rate)
            return rate
        }
        let group = TaxGroup(name: "Austin, TX", rates: rates)
        context.insert(group)
        try context.save()
        return group
    }

    func issuedInvoice(_ customer: Customer, group: TaxGroup?, amount: Int64 = 10_000) throws -> (Invoice, InvoiceDraftInput) {
        let input = InvoiceDraftInput(customer: customer, issueDate: day(-5), dueDate: day(25), taxGroupID: group?.id,
                                      lines: [.init(details: "Diseño", unitPrice: amount, isTaxable: true, incomeAccountID: try account("4100").id)])
        let invoice = try books.saveDraft(input)
        try books.issue(invoice)
        return (invoice, input)
    }

    @Test("Con cambios contables: revierte la emisión en su fecha, registra otra, conserva el número y cuadra")
    func editWithAccountingChanges() throws {
        let group = try austin()
        let customer = Customer(name: "Casa Gómez")
        context.insert(customer)
        let (invoice, input) = try issuedInvoice(customer, group: group)
        let number = invoice.number
        let original = try #require(try books.entry(id: invoice.journalEntryID))
        let receivable = try books.systemAccount(.accountsReceivable), income = try account("4100"), salesTax = try account("2200")
        #expect(invoice.total == 10_825 && invoice.status == .sent && books.canEditIssued(invoice))
        let nextInvoiceNumber = try books.peekDocumentNumber(.invoice)

        // Otro precio, una línea más (sin impuesto) y otra fecha.
        var corrected = input
        corrected.issueDate = day(-3)
        corrected.lines = [.init(details: "Diseño", quantity: 2, unitPrice: 10_000, isTaxable: true, incomeAccountID: income.id),
                           .init(details: "Visita", unitPrice: 5_000, isTaxable: false, incomeAccountID: income.id)]
        let replacement = try #require(try books.updateIssuedInvoice(invoice, with: corrected))

        #expect(invoice.number == number && invoice.status == .sent)
        #expect(try books.peekDocumentNumber(.invoice) == nextInvoiceNumber)   // no gasta otro número
        #expect(invoice.journalEntryID == replacement.id && invoice.subtotal == 25_000 && invoice.taxTotal == 1_650 && invoice.total == 26_650)
        #expect(invoice.issueDate == day(-3) && replacement.date == day(-3) && replacement.sourceDocumentID == invoice.id)
        #expect(original.isReversed && original.replacedByEntryID == replacement.id && replacement.replacesEntryID == original.id)
        let reversal = try #require(try books.entry(id: original.reversedByEntryID))
        #expect(reversal.date == original.date && reversal.source == .reversal && reversal.sourceDocumentID == invoice.id)
        #expect(reversal.totalDebits == original.totalDebits)
        #expect(try books.entries(ofInvoice: invoice).count == 3)

        // Reportes: el original y su reversión se anulan; cuenta el nuevo.
        #expect(try balance(receivable) == 26_650 && balance(income) == 25_000 && balance(salesTax) == 1_650)
        #expect(try trialBalanced())
        #expect(invoice.balanceDue == 26_650)
        let summary = try books.salesTaxSummary(from: day(-30), to: day(30))
        #expect(summary.totalTax == 1_650 && summary.taxableSales == 20_000 && summary.totalSales == 25_000)
        #expect(summary.totalTax == (try balance(salesTax)))

        // Queda en el historial de la factura.
        let edits = try books.edits(of: invoice)
        #expect(edits.count == 1 && edits.first?.action == "edit")
    }

    @Test("Solo cambios de texto: sin asientos nuevos, pero anotado como edición")
    func editTextOnly() throws {
        let customer = Customer(name: "Casa Gómez")
        context.insert(customer)
        let (invoice, input) = try issuedInvoice(customer, group: nil)
        let entries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        // Guardar sin cambios no deja rastro.
        #expect(try books.updateIssuedInvoice(invoice, with: input) == nil)
        #expect(try books.edits(of: invoice).isEmpty)
        var corrected = input
        corrected.dueDate = day(40)
        corrected.customerMessage = "Gracias por su compra"
        corrected.lines[0].details = "Diseño de cocina"
        #expect(try books.updateIssuedInvoice(invoice, with: corrected) == nil)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries)
        #expect(invoice.dueDate == day(40) && invoice.sortedLines.first?.details == "Diseño de cocina" && invoice.total == 10_000)
        #expect(try books.edits(of: invoice).map(\.action) == ["editText"])
        #expect(try trialBalanced())
    }

    @Test("Mismo impuesto: usa las tasas con que se emitió, aunque se haya editado la tasa")
    func keepsIssuedRates() throws {
        let group = try austin()
        let customer = Customer(name: "Casa Gómez")
        context.insert(customer)
        let (invoice, input) = try issuedInvoice(customer, group: group)
        let texas = try #require(group.rates?.first { $0.name == "Texas" })
        try books.updateTaxRate(texas, name: "Texas", agency: texas.agency, rateMillionths: 70_000)
        var corrected = input
        corrected.lines[0].unitPrice = 20_000
        try books.updateIssuedInvoice(invoice, with: corrected)
        #expect(invoice.taxTotal == 1_650 && invoice.taxLines?.first { $0.name == "Texas" }?.rateMillionths == 62_500)
        #expect(invoice.taxLines?.count == 2)
        #expect(try trialBalanced())
    }

    @Test("Con cobros, créditos o anulada no se edita; un fallo no deja nada a medias")
    func cannotEditWithPaymentsOrCredits() throws {
        let customer = Customer(name: "Casa Gómez")
        context.insert(customer)
        let checking = try account("1010")

        let (paid, paidInput) = try issuedInvoice(customer, group: nil)
        try books.recordPayment(for: paid, amount: 1_000, date: today, depositAccount: checking)
        #expect(!books.canEditIssued(paid))
        #expect(throws: BookkeepingError.self) { try books.updateIssuedInvoice(paid, with: paidInput) }

        let (credited, creditedInput) = try issuedInvoice(customer, group: nil)
        try books.issueCreditNote(for: credited, amount: 2_000, isTaxable: false, reason: "Ajuste", date: today)
        #expect(!books.canEditIssued(credited))
        #expect(throws: BookkeepingError.self) { try books.updateIssuedInvoice(credited, with: creditedInput) }

        let (voided, voidedInput) = try issuedInvoice(customer, group: nil)
        try books.void(voided)
        #expect(throws: BookkeepingError.self) { try books.updateIssuedInvoice(voided, with: voidedInput) }

        let draft = try books.saveDraft(paidInput)
        #expect(!books.canEditIssued(draft))
        #expect(throws: BookkeepingError.self) { try books.updateIssuedInvoice(draft, with: paidInput) }

        // Sin líneas válidas: error y la factura sigue igual.
        let (invoice, input) = try issuedInvoice(customer, group: nil)
        let entries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        var broken = input
        broken.lines = []
        #expect(throws: BookkeepingError.self) { try books.updateIssuedInvoice(invoice, with: broken) }
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries)
        #expect(invoice.total == 10_000 && invoice.sortedLines.count == 1 && invoice.status == .sent)
        #expect(try books.edits(of: invoice).isEmpty)
        #expect(try trialBalanced())
    }

    @Test("En un periodo cerrado pide desbloquear")
    func editInClosedPeriod() throws {
        let customer = Customer(name: "Casa Gómez")
        context.insert(customer)
        let input = InvoiceDraftInput(customer: customer, issueDate: day(-40), dueDate: day(-10),
                                      lines: [.init(details: "Diseño", unitPrice: 10_000, incomeAccountID: try account("4100").id)])
        let invoice = try books.saveDraft(input)
        try books.issue(invoice)
        try books.closeBooks(through: day(-30), calendar: calendar)
        var corrected = input
        corrected.lines[0].unitPrice = 12_000
        #expect(throws: BookkeepingError.invalidEntry(.periodLocked(lockDate: day(-30)))) { try books.updateIssuedInvoice(invoice, with: corrected) }
        #expect(invoice.total == 10_000)
        // Sin contraseña de cierre hay que escribir el motivo (QA Hudson, H02); queda en la auditoría.
        #expect(throws: BookkeepingError.closedPeriodReasonRequired) { try books.unlockedForClosedPeriod(password: nil) }
        #expect(throws: BookkeepingError.closedPeriodReasonRequired) { try books.unlockedForClosedPeriod(password: nil, reason: "  ") }
        #expect(try books.unlockedForClosedPeriod(password: nil, reason: "Precio mal escrito")
            .updateIssuedInvoice(invoice, with: corrected) != nil)
        #expect(invoice.total == 12_000)
        #expect(try context.fetch(FetchDescriptor<AuditEvent>()).contains {
            $0.action == "unlockClosedPeriod" && $0.summary.contains("Precio mal escrito")
        })
        #expect(try trialBalanced())
    }
}
