import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Contabilización de punta a punta con SwiftData")
struct BookkeeperTests {
    let container: ModelContainer
    let books: Bookkeeper

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Prueba LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func allEntriesBalanced() throws -> Bool {
        try context.fetch(FetchDescriptor<JournalEntry>()).allSatisfy { $0.totalDebits == $0.totalCredits }
    }

    func trialBalance() throws -> TrialBalance {
        ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture)
    }

    func makeInvoice(amount: Int64, taxGroup: TaxGroup? = nil, customer: Customer? = nil) throws -> Invoice {
        let customer = customer ?? Customer(name: "Café Aurora")
        if customer.modelContext == nil { context.insert(customer) }
        let invoice = Invoice(customer: customer)
        invoice.taxGroupID = taxGroup?.id
        context.insert(invoice)
        let line = InvoiceLine(details: "Servicio", unitPrice: amount, incomeAccountID: try account("4000").id)
        line.invoice = invoice
        context.insert(line)
        return invoice
    }

    func austinTaxGroup() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", liabilityAccountID: try account("2200").id)
        context.insert(agency)
        let state = TaxRate(name: "Texas", rateMillionths: 62_500, agency: agency)
        let city = TaxRate(name: "Austin", rateMillionths: 20_000, agency: agency)
        context.insert(state)
        context.insert(city)
        let group = TaxGroup(name: "Austin, TX", rates: [state, city])
        context.insert(group)
        return group
    }

    @Test("El alta crea el plan de cuentas con las cuentas de sistema")
    func companySetup() throws {
        #expect(try books.company()?.legalName == "Prueba LLC")
        for subtype in [AccountSubtype.accountsReceivable, .accountsPayable, .salesTaxPayable, .retainedEarnings, .undepositedFunds] {
            #expect(try books.systemAccount(subtype).isSystem)
        }
        #expect(throws: BookkeepingError.companyAlreadyExists) { try books.setUpCompany(legalName: "Otra") }
    }

    @Test("Asiento manual cuadrado se guarda; descuadrado se rechaza y no deja nada")
    func manualEntries() throws {
        let cash = try account("1000"), capital = try account("3000")
        let entry = try books.post(JournalEntryDraft(date: Date(), memo: "Aporte", lines: [.debit(cash.id, 50_000), .credit(capital.id, 50_000)]))
        #expect(entry.totalDebits == entry.totalCredits)
        #expect(entry.number == 1)

        let before = try context.fetchCount(FetchDescriptor<JournalEntry>())
        #expect(throws: BookkeepingError.invalidEntry(.unbalanced(debits: 100, credits: 90))) {
            try books.post(JournalEntryDraft(date: Date(), lines: [.debit(cash.id, 100), .credit(capital.id, 90)]))
        }
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == before)
        #expect(try context.fetchCount(FetchDescriptor<JournalLine>()) == 2)
    }

    @Test("Emitir factura con sales tax: asiento cuadrado, totales y número asignados")
    func issueInvoice() throws {
        let invoice = try makeInvoice(amount: 200_000, taxGroup: try austinTaxGroup())
        let entry = try books.issue(invoice)

        #expect(invoice.number == "F-1001")
        #expect(invoice.status == .sent)
        #expect(invoice.subtotal == 200_000)
        #expect(invoice.taxTotal == 16_500)   // 8.25 %
        #expect(invoice.total == 216_500)
        #expect(invoice.taxLines?.count == 2)
        #expect(entry.totalDebits == entry.totalCredits)
        #expect(entry.source == .invoice)
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: try books.ledgerLines()) == 216_500)
        #expect(ReportBuilder.balance(of: try account("2200").ledgerAccount, lines: try books.ledgerLines()) == 16_500)
    }

    @Test("Cobros parciales y totales actualizan el estado; no se puede cobrar de más")
    func payments() throws {
        let invoice = try makeInvoice(amount: 100_000)
        try books.issue(invoice)
        let bank = try account("1010")

        try books.recordPayment(for: invoice, amount: 40_000, depositAccount: bank)
        #expect(invoice.status == .partiallyPaid)
        #expect(invoice.balanceDue == 60_000)
        #expect(throws: BookkeepingError.overpayment(balanceDue: 60_000)) {
            try books.recordPayment(for: invoice, amount: 60_001, depositAccount: bank)
        }
        try books.recordPayment(for: invoice, amount: 60_000, depositAccount: bank)
        #expect(invoice.status == .paid)
        #expect(invoice.customer?.openBalance == 0)
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: try books.ledgerLines()) == 0)
        #expect(ReportBuilder.balance(of: bank.ledgerAccount, lines: try books.ledgerLines()) == 100_000)
    }

    @Test("Anular una factura la revierte y deja CxC e ingresos en cero")
    func voidInvoice() throws {
        let invoice = try makeInvoice(amount: 75_000, taxGroup: try austinTaxGroup())
        let original = try books.issue(invoice)
        try books.void(invoice)

        #expect(invoice.status == .void)
        #expect(original.isReversed)
        for code in ["1100", "4000", "2200"] {
            #expect(ReportBuilder.balance(of: try account(code).ledgerAccount, lines: try books.ledgerLines()) == 0)
        }
        #expect(throws: BookkeepingError.self) { try books.reverse(original) }
    }

    @Test("Factura de proveedor, pago y gasto")
    func purchases() throws {
        let vendor = Vendor(name: "Maderas del Norte")
        context.insert(vendor)
        let bill = Bill(vendor: vendor, vendorNumber: "B-221")
        context.insert(bill)
        let line = BillLine(details: "Triplay", amount: 84_230, accountID: try account("5000").id)
        line.bill = bill
        context.insert(line)

        try books.record(bill)
        #expect(bill.total == 84_230)
        #expect(vendor.openBalance == 84_230)
        try books.pay(bill, amount: 84_230, from: try account("1010"))
        #expect(bill.status == .paid)

        let expense = Expense(payee: "UBER *TRIP", paymentAccountID: try account("2100").id)
        context.insert(expense)
        let expenseLine = ExpenseLine(details: "Viaje", amount: 1_840, accountID: try account("6050").id)
        expenseLine.expense = expense
        context.insert(expenseLine)
        try books.record(expense)
        #expect(expense.total == 1_840)
        #expect(ReportBuilder.balance(of: try account("2100").ledgerAccount, lines: try books.ledgerLines()) == 1_840)
    }

    @Test("Fecha de cierre: no se contabiliza en un periodo cerrado")
    func lockDate() throws {
        let company = try #require(try books.company())
        company.lockDate = Date()
        let invoice = try makeInvoice(amount: 10_000)
        #expect(throws: BookkeepingError.invalidEntry(.periodLocked(lockDate: company.lockDate!))) {
            try books.issue(invoice)
        }
        #expect(invoice.status == .draft)
        #expect(invoice.number.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    @Test("Con los datos de ejemplo todo cuadra: asientos, balanza y balance general")
    func sampleDataBalances() throws {
        let sample = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(sample.mainContext)
        let sampleBooks = Bookkeeper(context: sample.mainContext)
        let accounts = try sampleBooks.ledgerAccounts()
        let lines = try sampleBooks.ledgerLines()

        #expect(try sample.mainContext.fetch(FetchDescriptor<JournalEntry>()).allSatisfy { $0.totalDebits == $0.totalCredits })
        #expect(ReportBuilder.trialBalance(accounts: accounts, lines: lines, asOf: .distantFuture).isBalanced)
        #expect(ReportBuilder.balanceSheet(accounts: accounts, lines: lines, asOf: .distantFuture).isBalanced)
        #expect(try sample.mainContext.fetchCount(FetchDescriptor<Invoice>()) == 5)
    }

    @Test("Tras todas las operaciones la balanza de comprobación cuadra")
    func everythingBalances() throws {
        let invoice = try makeInvoice(amount: 123_456, taxGroup: try austinTaxGroup())
        try books.issue(invoice)
        try books.recordPayment(for: invoice, amount: 50_000, depositAccount: try account("1090"))
        #expect(try allEntriesBalanced())
        let report = try trialBalance()
        #expect(report.isBalanced)
        #expect(report.totalDebit > 0)
    }
}

@MainActor
@Suite("Borradores de factura")
struct InvoiceDraftTests {
    let container: ModelContainer
    let books: Bookkeeper

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext)
        try books.setUpCompany(legalName: "Prueba LLC", locale: Locale(identifier: "es_US"))
    }

    @Test("Reintentar la emisión tras un fallo usa los datos corregidos, no los del primer intento")
    func retryAfterFailureUsesCorrectedData() throws {
        let context = container.mainContext
        let customer = Customer(name: "Café Aurora")
        context.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let company = try #require(try books.company())
        let calendar = Calendar.current
        let lockedDay = calendar.date(byAdding: .day, value: -10, to: .now)!
        company.lockDate = calendar.date(byAdding: .day, value: -5, to: .now)

        // Primer intento: fecha dentro del periodo cerrado y una línea de $100.
        var input = InvoiceDraftInput(customer: customer, issueDate: lockedDay, dueDate: lockedDay,
                                      lines: [.init(details: "Diseño", unitPrice: 10_000, incomeAccountID: income.id)])
        let draft = try books.saveDraft(input)
        #expect(throws: BookkeepingError.self) { try books.issue(draft) }
        #expect(draft.status == .draft)

        // El usuario corrige la fecha y las líneas, y vuelve a emitir.
        input.issueDate = .now
        input.dueDate = .now
        input.lines = [.init(details: "Diseño", unitPrice: 25_000, incomeAccountID: income.id),
                       .init(details: "Instalación", quantity: 2, unitPrice: 5_000, incomeAccountID: income.id)]
        let corrected = try books.saveDraft(input, into: draft)
        #expect(corrected === draft)
        #expect(corrected.lines?.count == 2)
        try books.issue(corrected)

        #expect(corrected.status == .sent)
        #expect(corrected.total == 35_000)
        #expect(calendar.isDate(corrected.issueDate, inSameDayAs: .now))
        #expect(try context.fetchCount(FetchDescriptor<InvoiceLine>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Invoice>()) == 1)
    }

    @Test("Editar un borrador reemplaza líneas y campos sin crear otra factura ni asientos")
    func editDraft() throws {
        let context = container.mainContext
        let first = Customer(name: "Café Aurora"), second = Customer(name: "Hotel Mirador")
        context.insert(first)
        context.insert(second)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let draft = try books.saveDraft(InvoiceDraftInput(customer: first, issueDate: .now, dueDate: .now, lines: [
            .init(details: "A", unitPrice: 1_000, incomeAccountID: income.id),
            .init(details: "B", unitPrice: 2_000, incomeAccountID: income.id),
        ]))
        try books.saveDraft(InvoiceDraftInput(customer: second, issueDate: .now, dueDate: .now, customerMessage: "Gracias",
                                              lines: [.init(details: "C", quantity: 3, unitPrice: 500, incomeAccountID: income.id)]),
                            into: draft)
        #expect(draft.customer === second)
        #expect(draft.customerMessage == "Gracias")
        #expect(draft.sortedLines.map(\.details) == ["C"])
        #expect(draft.linesSubtotal == 1_500)
        #expect(try context.fetchCount(FetchDescriptor<InvoiceLine>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Invoice>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    @Test("Una factura emitida ya no se puede reescribir como borrador")
    func issuedInvoiceIsNotEditable() throws {
        let customer = Customer(name: "Hotel Mirador")
        container.mainContext.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let input = InvoiceDraftInput(customer: customer, issueDate: .now, dueDate: .now,
                                      lines: [.init(details: "X", unitPrice: 1_000, incomeAccountID: income.id)])
        let invoice = try books.saveDraft(input)
        try books.issue(invoice)
        #expect(throws: BookkeepingError.self) { try books.saveDraft(input, into: invoice) }
    }
}

@MainActor
@Suite("Plantillas por sector")
struct SectorTemplateTests {
    @Test("Cada plantilla tiene todas las cuentas de sistema y códigos únicos", arguments: BusinessSector.allCases)
    func templatesAreComplete(sector: BusinessSector) {
        let entries = sector.template.entries
        #expect(Set(entries.map(\.code)).count == entries.count)
        let system = Set(entries.filter(\.isSystem).map(\.subtype))
        for subtype in [AccountSubtype.accountsReceivable, .accountsPayable, .salesTaxPayable, .retainedEarnings, .undepositedFunds, .openingBalanceEquity] {
            #expect(system.contains(subtype), "\(sector) no tiene \(subtype)")
        }
    }

    @Test("El alta de un comercio crea inventario y guarda el sector")
    func retailSetUp() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext)
        let company = try books.setUpCompany(legalName: "Tienda Sol", state: "TX", sector: .retail, locale: Locale(identifier: "es_US"))
        #expect(company.sectorRaw == BusinessSector.retail.rawValue)
        #expect(try books.accounts().contains { $0.subtype == .inventory })
        #expect(try books.accounts().first { $0.code == "4000" }?.name == "Ventas de mercancía")
    }

    @Test("Construcción y servicios tienen ingresos distintos")
    func sectorsDiffer() {
        let names = { (sector: BusinessSector) in sector.template.entries.first { $0.code == "4000" }?.spanish }
        #expect(names(.services) == "Ingresos por servicios")
        #expect(names(.construction) == "Ingresos por obra")
        #expect(BusinessSector.construction.template.entries.contains { $0.code == "1150" })
    }
}
