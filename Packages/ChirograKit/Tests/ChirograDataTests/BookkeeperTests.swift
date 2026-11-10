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

    @Test("Factura con descuento: el ingreso neto del estado de resultados descuenta el descuento")
    func issueWithDiscount() throws {
        let invoice = try makeInvoice(amount: 200_000, taxGroup: try austinTaxGroup())
        invoice.discount = 20_000
        try books.issue(invoice)
        #expect(invoice.discount == 20_000)
        #expect(invoice.taxTotal == 14_850)     // 8.25 % de 1,800.00
        #expect(invoice.total == 194_850)
        let statement = ReportBuilder.incomeStatement(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(),
                                                      from: .distantPast, to: .distantFuture)
        #expect(statement.totalIncome == 180_000)
        #expect(try books.systemAccount(.salesDiscount).code == "4900")
    }

    @Test("Nota de crédito: revierte ingreso e impuesto, reduce el saldo y bloquea la anulación")
    func creditNote() throws {
        let invoice = try makeInvoice(amount: 200_000, taxGroup: try austinTaxGroup())
        try books.issue(invoice)                                   // total 216,500
        let note = try books.issueCreditNote(for: invoice, amount: 50_000, isTaxable: true, reason: "Devolución")
        #expect(note.number == "NC-0001")
        #expect(note.taxTotal == 4_125)
        #expect(note.total == 54_125)
        #expect(invoice.creditsApplied == 54_125)
        #expect(invoice.balanceDue == 162_375)
        #expect(invoice.status == .partiallyPaid)
        let lines = try books.ledgerLines()
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: lines) == 162_375)
        #expect(ReportBuilder.balance(of: try account("4000").ledgerAccount, lines: lines) == 150_000)
        #expect(ReportBuilder.balance(of: try account("2200").ledgerAccount, lines: lines) == 12_375)
        #expect(try books.entry(id: note.journalEntryID)?.source == .creditNote)
        #expect(try allEntriesBalanced())
        #expect(throws: BookkeepingError.self) { try books.void(invoice) }
        #expect(throws: BookkeepingError.exceedsCreditable(162_375)) {
            try books.issueCreditNote(for: invoice, amount: 160_000, isTaxable: true, reason: "Demasiado")
        }
        try books.issueCreditNote(for: invoice, amount: 150_000, isTaxable: true, reason: "Resto")
        #expect(invoice.balanceDue == 0)
        #expect(invoice.status == .paid)
    }

    @Test("Nota de crédito sobre una línea de producto rebaja la venta de productos, no los servicios")
    func creditNoteUsesLineAccount() throws {
        let invoice = try makeInvoice(amount: 100_000)                              // Servicio → 4000
        let product = InvoiceLine(details: "Lámpara", unitPrice: 40_000, isTaxable: false,
                                  incomeAccountID: try account("4100").id, order: 1)
        product.invoice = invoice
        context.insert(product)
        try books.issue(invoice)
        let note = try books.issueCreditNote(for: invoice, amount: 40_000, isTaxable: false, reason: "Devolución", lineID: product.id)
        #expect(try note.incomeAccountID == account("4100").id)
        let lines = try books.ledgerLines()
        #expect(ReportBuilder.balance(of: try account("4000").ledgerAccount, lines: lines) == 100_000)
        #expect(ReportBuilder.balance(of: try account("4100").ledgerAccount, lines: lines) == 0)
        #expect(try allEntriesBalanced())
    }

    @Test("Nota de crédito sin línea elegida: se reparte entre las cuentas de todas las líneas")
    func creditNoteProratesAcrossLines() throws {
        let invoice = try makeInvoice(amount: 30_000)                               // Servicio → 4000
        let product = InvoiceLine(details: "Lámpara", unitPrice: 10_000, isTaxable: false,
                                  incomeAccountID: try account("4100").id, order: 1)
        product.invoice = invoice
        context.insert(product)
        try books.issue(invoice)
        let note = try books.issueCreditNote(for: invoice, amount: 20_000, isTaxable: false, reason: "Ajuste")
        #expect(note.incomeAccountID == nil)
        let lines = try books.ledgerLines()
        #expect(ReportBuilder.balance(of: try account("4000").ledgerAccount, lines: lines) == 15_000)
        #expect(ReportBuilder.balance(of: try account("4100").ledgerAccount, lines: lines) == 5_000)
        #expect(try allEntriesBalanced())
    }

    @Test("Pago de sales tax a la agencia: salda el pasivo y no admite pagar de más")
    func salesTaxPayment() throws {
        let group = try austinTaxGroup()
        try books.issue(try makeInvoice(amount: 200_000, taxGroup: group))      // 16,500 de impuesto
        let agency = try #require(try context.fetch(FetchDescriptor<TaxAgency>()).first)
        let bank = try account("1010")
        #expect(throws: BookkeepingError.overpayment(balanceDue: 16_500)) {
            try books.paySalesTax(to: agency, amount: 16_501, from: bank)
        }
        let entry = try books.paySalesTax(to: agency, amount: 16_500, from: bank, reference: "Q4")
        #expect(entry.source == .salesTaxPayment)
        #expect(entry.memo == "Pago de sales tax · Texas Comptroller · Q4")
        #expect(ReportBuilder.balance(of: try account("2200").ledgerAccount, lines: try books.ledgerLines()) == 0)
        #expect(ReportBuilder.balance(of: bank.ledgerAccount, lines: try books.ledgerLines()) == -16_500)
    }

    @Test("Antigüedad de cuentas por pagar por proveedor y tramo; las pagadas no cuentan")
    func payablesAging() throws {
        let calendar = Calendar.current
        func bill(_ vendor: Vendor, _ number: String, dueInDays: Int, amount: Int64) throws -> Bill {
            let bill = Bill(vendor: vendor, vendorNumber: number, billDate: .now,
                            dueDate: calendar.date(byAdding: .day, value: dueInDays, to: .now))
            context.insert(bill)
            let line = BillLine(details: number, amount: amount, accountID: try account("6400").id)
            line.bill = bill
            context.insert(line)
            try books.record(bill)
            return bill
        }
        let lumber = Vendor(name: "Maderas del Norte"), landlord = Vendor(name: "Renta del taller")
        context.insert(lumber)
        context.insert(landlord)
        _ = try bill(lumber, "B-1", dueInDays: 10, amount: 84_230)
        _ = try bill(lumber, "B-2", dueInDays: -45, amount: 10_000)
        let paid = try bill(landlord, "R-1", dueInDays: -5, amount: 120_000)
        try books.pay(paid, amount: 120_000, from: try account("1010"))

        let report = try books.payablesAging()
        #expect(report.total == 94_230)
        #expect(report.total(for: .current) == 84_230)
        #expect(report.total(for: .days31to60) == 10_000)
        #expect(report.rows.map(\.party) == ["Maderas del Norte"])
        #expect(try books.receivablesAging().total == 0)
    }

    @Test("Resumen de sales tax con factura, cliente exento, descuento y nota de crédito")
    func salesTaxSummary() throws {
        let group = try austinTaxGroup()                                   // Texas 6.25 % + Austin 2 %
        let taxed = try makeInvoice(amount: 200_000, taxGroup: group)
        taxed.discount = 20_000
        try books.issue(taxed)                                             // base 180,000
        let exemptCustomer = Customer(name: "Escuela pública")
        exemptCustomer.isTaxExempt = true
        try books.issue(try makeInvoice(amount: 50_000, taxGroup: group, customer: exemptCustomer))
        try books.issueCreditNote(for: taxed, amount: 10_000, isTaxable: true, reason: "Ajuste")

        let report = try books.salesTaxSummary(from: .distantPast, to: .distantFuture)
        #expect(report.totalSales == 180_000 + 50_000 - 10_000)
        #expect(report.taxableSales == 170_000)
        #expect(report.exemptSales == 50_000)
        #expect(report.nonTaxableSales == 0)
        #expect(report.totalTax == taxed.taxTotal - 825)                    // 8.25 % de 100.00
        #expect(report.totalTax == ReportBuilder.balance(of: try account("2200").ledgerAccount, lines: try books.ledgerLines()))
    }

    @Test("Nota de crédito sobre una factura pagada: queda como saldo a favor del cliente")
    func creditNoteOnPaidInvoiceBecomesCustomerCredit() throws {
        let customer = Customer(name: "Café Aurora")
        let invoice = try makeInvoice(amount: 100_000, customer: customer)
        try books.issue(invoice)
        try books.recordPayment(for: invoice, amount: 100_000, depositAccount: try account("1010"))

        let note = try books.issueCreditNote(for: invoice, amount: 30_000, isTaxable: false, reason: "Devolución")
        #expect(invoice.status == .paid)
        #expect(invoice.balanceDue == 0)
        #expect(note.unappliedAmount == 30_000)
        #expect(customer.creditBalance == 30_000)
        // En libros, el saldo a favor es un saldo acreedor en cuentas por cobrar.
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: try books.ledgerLines()) == -30_000)
        #expect(throws: BookkeepingError.exceedsCreditable(70_000)) {
            try books.issueCreditNote(for: invoice, amount: 70_001, isTaxable: false, reason: "Demasiado")
        }
    }

    @Test("Una nota mayor que el saldo pendiente se aplica en parte y el resto queda a favor")
    func creditNotePartlyApplied() throws {
        let customer = Customer(name: "Hotel Mirador")
        let invoice = try makeInvoice(amount: 100_000, customer: customer)
        try books.issue(invoice)
        try books.recordPayment(for: invoice, amount: 50_000, depositAccount: try account("1010"))
        let note = try books.issueCreditNote(for: invoice, amount: 80_000, isTaxable: false, reason: "Ajuste")
        #expect(invoice.balanceDue == 0)
        #expect(invoice.status == .paid)
        #expect(note.unappliedAmount == 30_000)
        #expect(invoice.creditApplications?.first?.amount == 50_000)
    }

    @Test("El saldo a favor se aplica a una factura futura sin asiento, o se reembolsa desde el banco")
    func applyAndRefundCustomerCredit() throws {
        let customer = Customer(name: "Clínica Del Valle")
        let first = try makeInvoice(amount: 100_000, customer: customer)
        try books.issue(first)
        try books.recordPayment(for: first, amount: 100_000, depositAccount: try account("1010"))
        try books.issueCreditNote(for: first, amount: 40_000, isTaxable: false, reason: "Devolución")

        let second = try makeInvoice(amount: 25_000, customer: customer)
        try books.issue(second)
        let entriesBefore = try context.fetchCount(FetchDescriptor<JournalEntry>())
        #expect(throws: BookkeepingError.self) { try books.applyCustomerCredit(to: second, amount: 25_001) }
        try books.applyCustomerCredit(to: second, amount: 25_000)
        #expect(second.status == .paid)
        #expect(customer.creditBalance == 15_000)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entriesBefore)
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: try books.ledgerLines()) == -15_000)

        let bank = try account("1010")
        #expect(throws: BookkeepingError.overpayment(balanceDue: 15_000)) {
            try books.refundCustomerCredit(customer, amount: 15_001, from: bank)
        }
        let refund = try books.refundCustomerCredit(customer, amount: 15_000, from: bank)
        #expect(refund.source == .customerRefund)
        #expect(customer.creditBalance == 0)
        #expect(ReportBuilder.balance(of: try account("1100").ledgerAccount, lines: try books.ledgerLines()) == 0)
        #expect(ReportBuilder.balance(of: bank.ledgerAccount, lines: try books.ledgerLines()) == 100_000 - 15_000)
        #expect(try allEntriesBalanced())
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

    @Test("Los datos de ejemplo salen en el idioma de la app: plan de cuentas, empresa, clientes y descripciones")
    func sampleDataFollowsLanguage() throws {
        let cases = [("es_US", "Ingresos por servicios", "Ríos Diseño & Obra", "Café Aurora", "Renta del taller"),
                     ("en_US", "Service Revenue", "Rios Design & Build", "Aurora Café", "Workshop rent")]
        for (identifier, revenue, company, customer, expense) in cases {
            let sample = try ChirograStore.makeContainer(inMemory: true)
            let context = sample.mainContext
            try SampleData.populate(context, locale: Locale(identifier: identifier))
            let books = Bookkeeper(context: context)
            #expect(try books.accounts().first { $0.code == "4000" }?.name == revenue)
            #expect(try books.company()?.displayName == company)
            #expect(try context.fetch(FetchDescriptor<Customer>()).contains { $0.name == customer })
            #expect(try context.fetch(FetchDescriptor<Expense>()).contains { $0.payee == expense })
            // Lo mismo en los dos idiomas: sigue siendo de ejemplo y los movimientos del banco se emparejan igual.
            #expect(try SampleData.isSample(context))
            #expect(try books.bankInbox(account: books.accounts().first { $0.code == "1010" }!).isEmpty)
        }
        // Las cifras no cambian con el idioma.
        let totals = try ["es_US", "en_US"].map { identifier in
            let sample = try ChirograStore.makeContainer(inMemory: true)
            try SampleData.populate(sample.mainContext, today: Date(timeIntervalSince1970: 1_793_000_000),
                                    locale: Locale(identifier: identifier))
            return try sample.mainContext.fetch(FetchDescriptor<Invoice>()).map(\.balanceDue).sorted()
        }
        #expect(totals[0] == totals[1])
    }

    @Test("Construcción y servicios tienen ingresos distintos")
    func sectorsDiffer() {
        let names = { (sector: BusinessSector) in sector.template.entries.first { $0.code == "4000" }?.spanish }
        #expect(names(.services) == "Ingresos por servicios")
        #expect(names(.construction) == "Ingresos por obra")
        #expect(BusinessSector.construction.template.entries.contains { $0.code == "1150" })
    }
}
