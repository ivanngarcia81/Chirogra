import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Funciones del esquema 2")
struct DataV2Tests {
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

    func balance(_ code: String) throws -> Int64 {
        ReportBuilder.balance(of: try account(code).ledgerAccount, lines: try books.ledgerLines())
    }

    func makeBill(_ number: String, amount: Int64, vendor: Vendor? = nil, due: Int = 10) throws -> Bill {
        let vendor = vendor ?? Vendor(name: "Proveedor \(number)")
        if vendor.modelContext == nil { context.insert(vendor) }
        let bill = Bill(vendor: vendor, vendorNumber: number, billDate: day(-5), dueDate: day(due))
        context.insert(bill)
        let line = BillLine(details: "Material", amount: amount, accountID: try account("5000").id)
        line.bill = bill
        context.insert(line)
        try books.record(bill)
        return bill
    }

    func austin() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", filingFrequency: .quarterly, liabilityAccountID: try account("2200").id)
        context.insert(agency)
        let rates = [("Texas", 62_500), ("Austin", 10_000), ("Austin MTA", 10_000)].map {
            let rate = TaxRate(name: $0.0, rateMillionths: Int64($0.1), agency: agency)
            context.insert(rate)
            return rate
        }
        let group = TaxGroup(name: "Austin, TX", rates: rates)
        context.insert(group)
        try context.save()
        return group
    }

    // MARK: Por pagar

    @Test("Pago en lote: un pago y un asiento por factura, misma fecha y cuenta; todo o nada")
    func batchPayment() throws {
        let checking = try account("1010")
        let a = try makeBill("A-1", amount: 10_000), b = try makeBill("B-2", amount: 25_050), c = try makeBill("C-3", amount: 7_000)
        try books.pay(c, amount: 2_000, date: day(-1), from: checking)
        let entriesBefore = try context.fetchCount(FetchDescriptor<JournalEntry>())

        let payments = try books.payBills([a, b, c], on: today, from: checking, method: .check, reference: "Lote 1")
        #expect(payments.count == 3)
        #expect(payments.map(\.amount) == [10_000, 25_050, 5_000])
        #expect(payments.allSatisfy { $0.date == today && $0.paymentAccountID == checking.id && $0.methodRaw == PaymentMethod.check.rawValue && $0.reference == "Lote 1" })
        #expect([a, b, c].allSatisfy { $0.status == .paid && $0.balanceDue == 0 })
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entriesBefore + 3)
        #expect(try balance("2000") == 0)
        #expect(try trialBalanced())

        // Si una falla (ya pagada), no se paga ninguna.
        let d = try makeBill("D-4", amount: 1_000)
        let count = try context.fetchCount(FetchDescriptor<BillPayment>())
        #expect(throws: BookkeepingError.self) { try books.payBills([d, a], on: today, from: checking) }
        #expect(d.isOpen && d.amountPaid == 0)
        #expect(try context.fetchCount(FetchDescriptor<BillPayment>()) == count)
        #expect(throws: BookkeepingError.self) { try books.payBills([d, d], on: today, from: checking) }
    }

    @Test("Pagos programados: programar, desprogramar y registrar los de hoy o antes con su fecha")
    func scheduledPayments() throws {
        let checking = try account("1010"), card = try account("2100")
        let early = try makeBill("P-1", amount: 12_000), todayBill = try makeBill("P-2", amount: 8_000), later = try makeBill("P-3", amount: 3_000)
        try books.schedulePayment(for: early, on: day(-2), from: checking, method: .bankTransfer)
        try books.schedulePayment(for: todayBill, on: today, from: card, method: .card)
        try books.schedulePayment(for: later, on: day(3), from: checking)
        #expect(early.isScheduled && early.scheduledPaymentMethod == .bankTransfer)
        #expect(throws: BookkeepingError.self) { try books.schedulePayment(for: early, on: today, from: try account("5000")) }

        #expect(try books.scheduledBills(dueOnOrBefore: today, calendar: calendar).map(\.vendorNumber) == ["P-1", "P-2"])
        let run = try books.payScheduledBills(dueOnOrBefore: today, calendar: calendar)
        #expect(run.paid.count == 2 && run.failures.isEmpty)
        #expect(run.paid.first { $0.bill?.id == early.id }?.date == day(-2))
        #expect(run.paid.first { $0.bill?.id == todayBill.id }?.paymentAccountID == card.id)
        #expect(early.status == .paid && early.scheduledPaymentDate == nil)
        #expect(later.isScheduled && later.isOpen)

        try books.unschedulePayment(for: later)
        #expect(!later.isScheduled && later.scheduledPaymentAccountID == nil)
        #expect(try books.payScheduledBills(dueOnOrBefore: day(30), calendar: calendar).paid.isEmpty)
        #expect(try trialBalanced())
    }

    // MARK: Recurrentes

    @Test("Recurrentes: genera hasta la fecha, no duplica y respeta fin y pausa")
    func recurringIsIdempotent() throws {
        let card = try account("2100"), software = try account("6750")
        let template = try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Adobe", kind: .expense, payee: "Adobe Creative Cloud",
            lines: [.init(details: "Suscripción", amount: 5_999, accountID: software.id)],
            paymentAccountID: card.id, method: .card, frequency: .monthly,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!, autoCharge: true), calendar: calendar)

        let first = try books.generateRecurring(through: today, calendar: calendar)
        // 31 ago, 30 sep, 31 oct (anclado al día 31).
        #expect(first.created.count == 3 && first.failures.isEmpty)
        let expenses = try context.fetch(FetchDescriptor<Expense>()).sorted { $0.date < $1.date }
        #expect(expenses.map { calendar.component(.day, from: $0.date) } == [31, 30, 31])
        #expect(expenses.allSatisfy { $0.isPosted && $0.recurringTemplateID == template.id && $0.total == 5_999 })
        #expect(template.lastGeneratedDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)))
        #expect(template.nextDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 30)))
        #expect(try balance("6750") == 3 * 5_999)

        // Otra vez: nada nuevo.
        #expect(try books.generateRecurring(through: today, calendar: calendar).created.isEmpty)
        // Otro aparato ya generó la de noviembre y sincronizó, pero aquí la plantilla aún no avanzó: no la repite.
        template.nextDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        #expect(try books.generateRecurring(through: today, calendar: calendar).created.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 3)

        // Fin y pausa.
        var input = RecurringTemplateInput(name: "Adobe", kind: .expense, payee: "Adobe Creative Cloud",
                                           lines: [.init(details: "Suscripción", amount: 5_999, accountID: software.id)],
                                           paymentAccountID: card.id, method: .card, frequency: .monthly,
                                           startDate: template.startDate, endDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)), autoCharge: true)
        try books.saveRecurringTemplate(input, into: template, calendar: calendar)
        #expect(try books.generateRecurring(through: day(90), calendar: calendar).created.count == 1)   // solo 30 nov
        #expect(template.isFinished)
        input.endDate = nil
        try books.saveRecurringTemplate(input, into: template, calendar: calendar)
        try books.setRecurringTemplate(template, active: false)
        #expect(try books.generateRecurring(through: day(90), calendar: calendar).created.isEmpty)
        try books.setRecurringTemplate(template, active: true, asOf: day(90), calendar: calendar)
        #expect(calendar.startOfDay(for: template.nextDate) >= day(90))   // lo que pasó en pausa no se genera
        #expect(try trialBalanced())
    }

    @Test("Recurrentes: sin cargo automático el gasto queda por confirmar; una factura con cargo automático se paga sola")
    func recurringKinds() throws {
        let checking = try account("1010"), rent = try account("6400")
        let landlord = Vendor(name: "Inmobiliaria Sur")
        context.insert(landlord)
        try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Luz", kind: .expense, payee: "Austin Energy", lines: [.init(amount: 14_680, accountID: try account("6700").id)],
            paymentAccountID: checking.id, frequency: .monthly, startDate: day(-1)), calendar: calendar)
        try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Renta del taller", kind: .bill, vendor: landlord, lines: [.init(amount: 120_000, accountID: rent.id)],
            paymentAccountID: checking.id, method: .bankTransfer, frequency: .monthly, startDate: day(-3), autoCharge: true,
            billTermsDays: 3), calendar: calendar)

        let run = try books.runAutomations(asOf: today, calendar: calendar)
        #expect(run.recurring.created.count == 2)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(!expense.isPosted && expense.total == 14_680)   // por confirmar
        let bill = try #require(try context.fetch(FetchDescriptor<Bill>()).first)
        #expect(bill.journalEntryID != nil && bill.dueDate == today)
        #expect(run.autoPayments.paid.count == 1 && bill.status == .paid)   // vence hoy y tiene cargo automático
        #expect(try books.notices(asOf: today, calendar: calendar).contains { $0.kind == .recurringGenerated && $0.needsConfirmation })

        // Confirmar el gasto lo contabiliza.
        try books.record(expense)
        #expect(expense.isPosted)
        #expect(try trialBalanced())
    }

    @Test("Recurrentes duplicadas por dos aparatos sin conexión: se anula la copia y los reportes cuadran")
    func recurringDuplicates() throws {
        let card = try account("2100"), software = try account("6750")
        let template = try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Adobe", kind: .expense, lines: [.init(amount: 5_999, accountID: software.id)],
            paymentAccountID: card.id, frequency: .monthly, startDate: day(-1), autoCharge: true), calendar: calendar)
        try books.generateRecurring(through: today, calendar: calendar)
        // Simula la copia que llegó de otro aparato.
        let copy = try books.createExpense(ExpenseInput(date: day(-1), payee: "Adobe", paymentAccountID: card.id,
                                                        lines: [.init(amount: 5_999, accountID: software.id)]))
        copy.recurringTemplateID = template.id
        copy.recurrenceDate = day(-1)
        try context.save()
        #expect(try balance("6750") == 2 * 5_999)

        #expect(try books.resolveRecurringDuplicates(calendar: calendar) == 1)
        #expect(copy.isVoid)
        #expect(try balance("6750") == 5_999)
        #expect(try books.resolveRecurringDuplicates(calendar: calendar) == 0)
        #expect(try trialBalanced())
    }

    // MARK: Editar lo contabilizado

    @Test("Editar un gasto contabilizado: reversión del original + asiento nuevo, enlazados, y la balanza cuadra")
    func editPostedExpense() throws {
        let checking = try account("1010"), card = try account("2100"), supplies = try account("6500"), travel = try account("6600")
        let expense = try books.createExpense(ExpenseInput(date: day(-3), payee: "Home Depot", paymentAccountID: checking.id,
                                                          lines: [.init(details: "Tornillos", amount: 21_475, accountID: supplies.id)]))
        let original = try #require(try books.entry(id: expense.journalEntryID))
        let expenseCount = try context.fetchCount(FetchDescriptor<Expense>())

        // Solo texto: sin asientos nuevos.
        var input = ExpenseInput(expense)
        input.memo = "Para la terraza"
        input.salesTaxIncluded = 1_637
        #expect(try books.updateExpense(expense, with: input) == nil)
        #expect(expense.journalEntryID == original.id && expense.revision == 0 && expense.salesTaxIncluded == 1_637)

        // Cambio contable: otro importe, otra cuenta, otra fecha y otra cuenta de pago.
        input.date = day(-1)
        input.paymentAccountID = card.id
        input.lines = [.init(details: "Tornillos", amount: 15_000, accountID: supplies.id), .init(details: "Uber", amount: 2_000, accountID: travel.id)]
        let replacement = try #require(try books.updateExpense(expense, with: input))

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == expenseCount)   // sigue siendo un gasto
        #expect(expense.journalEntryID == replacement.id && expense.total == 17_000 && expense.revision == 1)
        #expect(original.isReversed && original.replacedByEntryID == replacement.id && replacement.replacesEntryID == original.id)
        let reversal = try #require(try books.entry(id: original.reversedByEntryID))
        #expect(reversal.date == original.date && reversal.source == .reversal && reversal.sourceDocumentID == expense.id)
        #expect(try books.entries(ofExpense: expense).count == 3)
        #expect(try balance("6500") == 15_000 && balance("6600") == 2_000)
        #expect(try balance("1010") == -0 && balance("2100") == 17_000)
        #expect(try trialBalanced())
        #expect(try context.fetch(FetchDescriptor<AuditEvent>()).contains { $0.entityID == expense.id && $0.action == "edit" })

        // Un fallo (línea sin importe) no deja nada a medias.
        let entries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        input.lines = [.init(amount: 0, accountID: supplies.id)]
        #expect(throws: BookkeepingError.self) { try books.updateExpense(expense, with: input) }
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries && expense.total == 17_000 && expense.journalEntryID == replacement.id)

        // Anular: revierte el vigente.
        try books.void(expense)
        #expect(try expense.isVoid && balance("6500") == 0 && balance("2100") == 0)
        #expect(try trialBalanced())
    }

    @Test("Editar un gasto en periodo cerrado pide desbloquear (con la contraseña si la hay)")
    func editExpenseInClosedPeriod() throws {
        let checking = try account("1010"), supplies = try account("6500")
        let expense = try books.createExpense(ExpenseInput(date: day(-40), payee: "Home Depot", paymentAccountID: checking.id,
                                                          lines: [.init(amount: 1_000, accountID: supplies.id)]))
        try books.closeBooks(through: day(-30), calendar: calendar)
        try books.setClosingPassword("cierre-2026")
        var input = ExpenseInput(expense)
        input.lines[0].amount = 1_500
        #expect(throws: BookkeepingError.invalidEntry(.periodLocked(lockDate: day(-30)))) { try books.updateExpense(expense, with: input) }
        #expect(throws: BookkeepingError.wrongClosingPassword) { try books.unlockedForClosedPeriod(password: "otra") }
        let unlocked = try books.unlockedForClosedPeriod(password: "cierre-2026")
        #expect(try unlocked.updateExpense(expense, with: input) != nil)
        #expect(try balance("6500") == 1_500)
        #expect(try trialBalanced())
    }

    @Test("Editar una cuenta: nombre, número único, tipo de detalle, cuenta principal y últimos 4")
    func editAccount() throws {
        let checking = try account("1010"), savings = try account("1020"), supplies = try account("6500")
        try books.updateAccount(checking, with: AccountInput(code: "1011", name: "Corriente", subtype: .bank, last4: "4821"))
        #expect(checking.code == "1011" && checking.maskedName == "Corriente ••4821")
        #expect(throws: BookkeepingError.duplicateAccountCode("1020")) {
            try books.updateAccount(checking, with: AccountInput(code: "1020", name: "Corriente", subtype: .bank))
        }
        #expect(throws: BookkeepingError.self) { try books.updateAccount(checking, with: AccountInput(code: "1011", name: "Corriente", subtype: .bank, last4: "48")) }

        // Tipo de detalle dentro del mismo tipo: sí; a otro tipo: solo sin movimientos.
        try books.updateAccount(savings, with: AccountInput(code: "1020", name: "Ahorro", subtype: .cash))
        #expect(savings.subtype == .cash)
        try books.updateAccount(savings, with: AccountInput(code: "1020", name: "Ahorro", subtype: .bank))
        try books.createExpense(ExpenseInput(date: today, payee: "X", paymentAccountID: checking.id, lines: [.init(amount: 500, accountID: supplies.id)]))
        #expect(throws: BookkeepingError.self) {
            try books.updateAccount(supplies, with: AccountInput(code: "6500", name: "Suministros", subtype: .otherCurrentAsset))
        }
        try books.updateAccount(supplies, with: AccountInput(code: "6500", name: "Suministros de obra", subtype: .costOfGoodsSold))
        #expect(supplies.type == .expense && supplies.name == "Suministros de obra")
        let unused = try account("1300")
        try books.updateAccount(unused, with: AccountInput(code: "1300", name: "Anticipos", subtype: .otherCurrentLiability))
        #expect(unused.type == .liability)

        // Las de sistema no cambian de tipo de detalle.
        let receivable = try books.systemAccount(.accountsReceivable)
        #expect(throws: BookkeepingError.self) {
            try books.updateAccount(receivable, with: AccountInput(code: receivable.code, name: receivable.name, subtype: .otherCurrentAsset))
        }

        // Cuenta principal: mismo tipo, sin movimientos propios y sin ciclos.
        let vehicles = try account("1510"), equipment = try account("1500")
        try books.updateAccount(vehicles, with: AccountInput(code: "1510", name: "Vehículos", subtype: .fixedAsset, parentID: equipment.id))
        #expect(vehicles.parent?.id == equipment.id && !equipment.isLeaf)
        #expect(throws: BookkeepingError.self) {
            try books.updateAccount(equipment, with: AccountInput(code: "1500", name: "Equipo", subtype: .fixedAsset, parentID: vehicles.id))
        }
        #expect(throws: BookkeepingError.self) {
            try books.updateAccount(vehicles, with: AccountInput(code: "1510", name: "Vehículos", subtype: .fixedAsset, parentID: checking.id))
        }
        #expect(throws: BookkeepingError.self) {
            try books.updateAccount(try account("6000"), with: AccountInput(code: "6000", name: "Publicidad", subtype: .operatingExpense, parentID: supplies.id))
        }
    }

    @Test("Editar una tasa no cambia las facturas emitidas ni sus notas de crédito; los borradores toman la nueva")
    func editTaxRate() throws {
        let group = try austin()
        let customer = Customer(name: "Café Aurora")
        context.insert(customer)
        let line = InvoiceDraftInput.Line(details: "Materiales", unitPrice: 10_000, isTaxable: true, incomeAccountID: try account("4100").id)
        let issued = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(-5), dueDate: today, taxGroupID: group.id, lines: [line]))
        try books.issue(issued)
        #expect(issued.taxTotal == 825)
        let draft = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: today, dueDate: day(15), taxGroupID: group.id, lines: [line]))
        // El borrador guarda su total con impuesto, que es lo que muestran las listas.
        #expect(draft.taxTotal == 825 && draft.draftAmount == 10_825)

        let texas = try #require(group.rates?.first { $0.name == "Texas" })
        try books.updateTaxRate(texas, name: "Texas (estatal)", agency: texas.agency, rateMillionths: 70_000)
        #expect(texas.name == "Texas (estatal)" && texas.percent == 7)
        #expect(throws: BookkeepingError.self) { try books.updateTaxRate(texas, name: "", agency: nil, rateMillionths: 10) }
        #expect(throws: BookkeepingError.self) { try books.updateTaxRate(texas, name: "X", agency: nil, rateMillionths: 2_000_000) }

        #expect(issued.taxTotal == 825 && issued.total == 10_825)
        #expect(issued.taxLines?.first { $0.name == "Texas" }?.rateMillionths == 62_500)
        let note = try books.issueCreditNote(for: issued, amount: 10_000, isTaxable: true, reason: "Devolución", date: today)
        #expect(note.taxTotal == 825)   // con las tasas con que se emitió
        #expect(try books.totals(for: draft).tax == 900)
        #expect(draft.draftAmount == 10_825)   // hasta que se recalcula al abrir la app
        #expect(try books.refreshDraftTotals() == 1 && draft.draftAmount == 10_900)
        #expect(try books.refreshDraftTotals() == 0)
        try books.issue(draft)
        #expect(draft.taxTotal == 900)
        let summary = try books.salesTaxSummary(from: day(-30), to: day(30))
        #expect(summary.totalTax == 900)
        #expect(try trialBalanced())
    }

    @Test("Impuesto predeterminado de la empresa (grupo o tasa sola) en facturas nuevas")
    func defaultTax() throws {
        let group = try austin()
        let texas = try #require(group.rates?.first { $0.name == "Texas" })
        let customer = Customer(name: "Clínica")
        context.insert(customer)
        #expect(try books.newInvoiceDefaults(for: customer).taxGroupID == nil)
        try books.setDefaultTax(texas.id)
        #expect(try books.company()?.defaultTaxGroupID == texas.id)
        #expect(try books.newInvoiceDefaults(for: customer).taxGroupID == texas.id)
        #expect(try books.taxCodeName(texas.id) == "Texas")
        // Una tasa sola funciona como grupo de un componente al emitir.
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: today, dueDate: today, taxGroupID: texas.id,
                                                            lines: [.init(details: "Material", unitPrice: 10_000, incomeAccountID: try account("4100").id)]))
        try books.issue(invoice)
        #expect(invoice.taxTotal == 625)
        try books.setDefaultTax(group.id)
        customer.isTaxExempt = true
        #expect(try books.newInvoiceDefaults(for: customer).taxGroupID == nil)
        #expect(throws: BookkeepingError.self) { try books.setDefaultTax(UUID()) }
    }

    @Test("Precios con impuesto incluido: la factura separa el impuesto, cuadra y el resumen de sales tax lo reconoce")
    func pricesIncludeTax() throws {
        let group = try austin()
        try books.company()?.pricesIncludeTax = true
        let customer = Customer(name: "Café Aurora")
        context.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: today, dueDate: day(15), taxGroupID: group.id, lines: [
            .init(details: "Diseño", unitPrice: 50_000, isTaxable: false, incomeAccountID: try account("4000").id),
            .init(details: "Madera", quantity: 3, unitPrice: 3_333, isTaxable: true, incomeAccountID: try account("4100").id),
        ]))
        #expect(invoice.pricesIncludeTax)
        #expect(try books.totals(for: invoice).total == 59_999)
        try books.issue(invoice)
        // 9_999 brutos al 8.25 %: base 9_237, impuesto 762 (578 + 92 + 92).
        #expect(invoice.total == 59_999 && invoice.taxTotal == 762 && invoice.netSales == 59_237)
        #expect(invoice.taxLines?.map(\.amount).sorted() == [92, 92, 578])
        #expect(try balance("4100") == 9_237 && balance("4000") == 50_000 && balance("2200") == 762)
        let summary = try books.salesTaxSummary(from: day(-1), to: day(1))
        #expect(summary.totalTax == 762 && summary.taxableSales == 9_237 && summary.totalSales == 59_237)
        #expect(try trialBalanced())

        // Cambiar el ajuste de la empresa no toca la emitida; una factura puede elegir lo contrario.
        try books.company()?.pricesIncludeTax = false
        #expect(invoice.pricesIncludeTax)
        let exclusive = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: today, dueDate: day(15), taxGroupID: group.id,
                                                              lines: [.init(details: "Madera", unitPrice: 10_000, incomeAccountID: try account("4100").id)],
                                                              pricesIncludeTax: true))
        try books.issue(exclusive)
        #expect(exclusive.total == 10_000 && exclusive.taxTotal == 762)
    }

    // MARK: Ventas

    @Test("Estimado → factura: borrador con sus líneas, sin asiento; anticipo del 50 % y luego el resto")
    func convertEstimate() throws {
        let group = try austin()
        let customer = Customer(name: "Hotel Mirador", paymentTermsDays: 15)
        context.insert(customer)
        let services = try account("4000"), materials = try account("4100")
        let entries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        let estimate = try books.saveEstimate(EstimateInput(
            customer: customer, title: "Remodelación del lobby", issueDate: day(-3), expirationDate: day(27), taxGroupID: group.id,
            customerMessage: "Válido 30 días", lines: [
                .init(details: "Diseño de lobby", unitPrice: 240_000, isTaxable: false, incomeAccountID: services.id),
                .init(details: "Mano de obra", quantity: 40, unitPrice: 5_800, isTaxable: false, incomeAccountID: services.id),
                .init(details: "Madera de roble", quantity: 12, unitPrice: 8_500, isTaxable: true, incomeAccountID: materials.id),
            ]))
        #expect(estimate.number == "E-0001" && estimate.status == .draft)
        #expect(estimate.subtotal == 574_000 && estimate.taxTotal == 8_415 && estimate.total == 582_415)   // $5,824.15 como el canvas
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries)   // sin asiento
        try books.setStatus(.sent, of: estimate, date: day(-3))
        #expect(estimate.effectiveStatus(asOf: day(40), calendar: calendar) == .expired)
        try books.setStatus(.accepted, of: estimate, acceptedBy: "Laura Méndez", date: day(-1))
        #expect(estimate.acceptedBy == "Laura Méndez")

        let deposit = try books.convertToInvoice(estimate, portion: .percent(50), issueDate: today, calendar: calendar)
        #expect(deposit.status == .draft && deposit.estimateID == estimate.id && deposit.taxGroupID == group.id)
        #expect(deposit.sortedLines.map(\.amount) == [120_000, 116_000, 51_000])
        #expect(deposit.customerMessage == "Válido 30 días" && deposit.dueDate == day(15))
        #expect(estimate.status == .accepted && !estimate.isFullyInvoiced)
        #expect(try books.totals(for: deposit).total == 291_208)   // $2,912.08
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries)
        #expect(throws: BookkeepingError.self) { try books.saveEstimate(EstimateInput(customer: customer, issueDate: today, expirationDate: today, lines: []), into: estimate) }

        let rest = try books.convertToInvoice(estimate, issueDate: today, calendar: calendar)
        #expect(rest.sortedLines.map(\.amount) == [120_000, 116_000, 51_000])
        #expect(estimate.status == .converted && estimate.isFullyInvoiced)
        #expect(try books.invoices(for: estimate).count == 2)
        #expect(throws: BookkeepingError.self) { try books.convertToInvoice(estimate) }
        try books.issue(deposit)
        try books.issue(rest)
        #expect(deposit.total + rest.total == 582_416)   // el impuesto se redondea por factura
        #expect(try trialBalanced())
    }

    @Test("Estimado: convertir líneas elegidas y repartir el descuento")
    func convertEstimateLines() throws {
        let customer = Customer(name: "Café Aurora")
        context.insert(customer)
        let services = try account("4000")
        let estimate = try books.saveEstimate(EstimateInput(customer: customer, issueDate: today, expirationDate: day(30), discount: 1_000, lines: [
            .init(details: "Etapa 1", unitPrice: 30_000, isTaxable: false, incomeAccountID: services.id),
            .init(details: "Etapa 2", unitPrice: 70_000, isTaxable: false, incomeAccountID: services.id),
        ]))
        #expect(estimate.total == 99_000)
        let firstLine = try #require(estimate.sortedLines.first)
        let stage1 = try books.convertToInvoice(estimate, portion: .lines([firstLine.id]), issueDate: today)
        #expect(stage1.sortedLines.count == 1 && stage1.discount == 300)
        let stage2 = try books.convertToInvoice(estimate, issueDate: today)
        #expect(stage2.discount == 700 && estimate.status == .converted)
        #expect(throws: BookkeepingError.self) { try books.setStatus(.declined, of: estimate) }
    }

    @Test("Notas fechadas del cliente y persona de contacto")
    func customerNotes() throws {
        let customer = Customer(name: "Hotel Mirador")
        customer.contactName = "Laura Méndez"
        customer.contactTitle = "Gerente"
        context.insert(customer)
        try books.addNote(to: customer, text: "Pagan los viernes.", date: day(-10))
        let recent = try books.addNote(to: customer, text: "  Quieren remodelar el lobby.  ", date: day(-1))
        #expect(customer.contactLine == "Laura Méndez · Gerente")
        #expect(customer.sortedNotes.map(\.text) == ["Quieren remodelar el lobby.", "Pagan los viernes."])
        #expect(recent.author == "Pruebas")
        #expect(throws: BookkeepingError.self) { try books.addNote(to: customer, text: "   ") }
        try books.updateNote(recent, text: "Lobby en enero")
        try books.deleteNote(customer.sortedNotes[1])
        #expect(customer.sortedNotes.map(\.text) == ["Lobby en enero"])
    }

    @Test("Historial de envíos y recordatorios de una factura")
    func invoiceEvents() throws {
        let customer = Customer(name: "Café Aurora", email: "pagos@cafeaurora.com")
        context.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(-20), dueDate: day(-5),
                                                            lines: [.init(details: "Diseño", unitPrice: 10_000, incomeAccountID: try account("4000").id)]))
        #expect(throws: BookkeepingError.self) { try books.recordInvoiceSent(invoice, to: customer.email, subject: "Factura") }
        try books.issue(invoice)
        try books.recordInvoiceSent(invoice, to: customer.email, subject: "Factura \(invoice.number)", date: day(-20))
        try books.recordReminder(invoice, to: customer.email, subject: "Recordatorio", date: today)
        #expect(invoice.sortedEvents.map(\.kind) == [.reminder, .sent])
        #expect(invoice.lastReminderDate == today && invoice.lastSentDate == day(-20))
        try books.recordPayment(for: invoice, amount: invoice.balanceDue, depositAccount: try account("1010"))
        #expect(throws: BookkeepingError.self) { try books.recordReminder(invoice, to: customer.email, subject: "Otra vez") }
    }

    @Test("Proveedor: W-9 y pago preferido; plantilla de factura y logo de la empresa")
    func vendorAndTemplate() throws {
        let vendor = Vendor(name: "Luis Mora")
        context.insert(vendor)
        try books.setW9(for: vendor, received: true, on: day(-3))
        #expect(vendor.w9Received && vendor.w9ReceivedDate == day(-3))
        try books.attachW9(Data("%PDF-1.4".utf8), filename: "w9.pdf", contentType: .pdf, to: vendor)
        #expect(vendor.w9Attachment?.contentType == "com.adobe.pdf" && vendor.w9ReceivedDate == day(-3))
        try books.setPreferredPayment(for: vendor, method: .bankTransfer, account: try account("1010"))
        #expect(vendor.preferredPaymentMethod == .bankTransfer)
        try books.setW9(for: vendor, received: false)
        #expect(vendor.w9ReceivedDate == nil)

        let company = try #require(try books.company())
        #expect(company.invoiceAccent == .ink && company.invoiceStyle == .classic)
        company.invoiceAccentHex = InvoiceAccent.copper.hex
        company.invoiceStyle = .compact
        #expect(company.invoiceAccent == .copper)
        #expect(throws: AttachmentProcessing.Failure.unsupportedType) {
            try books.setCompanyLogo(Data("x".utf8), filename: "logo.pdf", contentType: .pdf)
        }
        try books.removeCompanyLogo()
        #expect(company.logo == nil)
    }

    // MARK: Cierre

    @Test("Contraseña de cierre: solo se guarda un hash con sal; fijar, cambiar, comprobar y quitar")
    func closingPassword() throws {
        let company = try #require(try books.company())
        #expect(try books.verifyClosingPassword("lo-que-sea"))   // sin contraseña
        try books.setClosingPassword("cierre-2026")
        #expect(company.hasClosingPassword && !company.closingPasswordHash.contains("cierre-2026"))
        #expect(company.closingPasswordHash.hasPrefix("pbkdf2-sha256$"))
        #expect(try books.verifyClosingPassword("cierre-2026") && !books.verifyClosingPassword("Cierre-2026"))
        let first = company.closingPasswordHash
        #expect(throws: BookkeepingError.wrongClosingPassword) { try books.setClosingPassword("nueva", current: "mala") }
        try books.setClosingPassword("cierre-2026", current: "cierre-2026")
        #expect(company.closingPasswordHash != first)   // sal nueva cada vez
        #expect(throws: BookkeepingError.self) { try books.setClosingPassword("123", current: "cierre-2026") }
        #expect(throws: BookkeepingError.wrongClosingPassword) { try books.removeClosingPassword(current: "mala") }
        try books.removeClosingPassword(current: "cierre-2026")
        #expect(!company.hasClosingPassword)
        #expect(!ClosingPassword.verify("x", against: "basura"))
    }

    @Test("Cierre de periodo: historial de cierres y reaperturas, y la contraseña protege reabrir y registrar")
    func closingHistory() throws {
        let checking = try account("1010"), capital = try account("3000")
        let sep30 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let oct31 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        try books.closeBooks(through: sep30, note: "Septiembre revisado", device: "Mac de Ana", calendar: calendar)
        try books.setClosingPassword("cierre-2026")
        try books.closeBooks(through: oct31, note: "Octubre", calendar: calendar)
        #expect(throws: BookkeepingError.self) { try books.closeBooks(through: sep30, calendar: calendar) }
        #expect(try books.company()?.lockDate == oct31)

        let draft = JournalEntryDraft(date: day(-10), memo: "Ajuste", lines: [.debit(checking.id, 100), .credit(capital.id, 100)])
        #expect(throws: BookkeepingError.invalidEntry(.periodLocked(lockDate: oct31))) { try books.post(draft) }
        try books.unlockedForClosedPeriod(password: "cierre-2026").post(draft)

        #expect(throws: BookkeepingError.wrongClosingPassword) { try books.reopenBooks(to: sep30, password: "no", calendar: calendar) }
        try books.reopenBooks(to: sep30, password: "cierre-2026", note: "Falta un recibo", calendar: calendar)
        #expect(try books.company()?.lockDate == sep30)
        let history = try books.closingHistory()
        #expect(history.count == 3)
        #expect(history.filter(\.isReopen).count == 1)
        let first = try #require(history.first { $0.note == "Septiembre revisado" })
        #expect(first.device == "Mac de Ana" && first.actor == "Pruebas" && first.previousLockDate == nil)
        #expect(try context.fetch(FetchDescriptor<AuditEvent>()).contains { $0.action == "unlockClosedPeriod" })
    }

    // MARK: Avisos

    @Test("Avisos: vencidas, por pagar en 7 días, programados de hoy, recurrentes recientes y sales tax en 15 días")
    func notices() throws {
        let checking = try account("1010")
        let group = try austin()
        let customer = Customer(name: "Hotel Mirador")
        context.insert(customer)
        // Sales tax cobrado en el trimestre jul–sep; la declaración vence el 20 oct.
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                                                            dueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!, taxGroupID: group.id,
                                                            lines: [.init(details: "Materiales", unitPrice: 100_000, incomeAccountID: try account("4100").id)]))
        try books.issue(invoice)
        let dueSoon = try makeBill("S-1", amount: 5_000, due: 4)
        _ = try makeBill("L-1", amount: 5_000, due: 20)
        let scheduled = try makeBill("P-1", amount: 9_000, due: 10)
        try books.schedulePayment(for: scheduled, on: today, from: checking)
        try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Luz", kind: .expense, payee: "Austin Energy", lines: [.init(amount: 14_680, accountID: try account("6700").id)],
            paymentAccountID: checking.id, frequency: .monthly, startDate: day(-2)), calendar: calendar)
        try books.generateRecurring(through: today, calendar: calendar)

        let notices = try books.notices(asOf: today, calendar: calendar)
        #expect(notices.map(\.kind) == [.scheduledPaymentDue, .overdueInvoice, .billDueSoon, .recurringGenerated])
        #expect(notices.first { $0.kind == .overdueInvoice }?.documentID == invoice.id)
        #expect(notices.first { $0.kind == .billDueSoon }?.documentID == dueSoon.id && notices.first { $0.kind == .billDueSoon }?.days == 4)
        #expect(notices.first { $0.kind == .recurringGenerated }?.needsConfirmation == true)

        // El 10 oct faltaban 10 días para declarar el T3 y había impuesto por pagar.
        let oct10 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let taxNotice = try #require(try books.notices(asOf: oct10, calendar: calendar).first { $0.kind == .salesTaxDue })
        #expect(taxNotice.amount == 8_250 && taxNotice.days == 10)
        #expect(taxNotice.date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let agency = try #require(try context.fetch(FetchDescriptor<TaxAgency>()).first)
        let q4 = books.salesTaxFilingPeriod(for: agency, containing: today, calendar: calendar)
        #expect(q4.deadline == calendar.date(from: DateComponents(year: 2027, month: 1, day: 20)))

        // Leído y descartado.
        let first = try #require(notices.first)
        try books.markNoticeRead(first.id)
        #expect(try books.notices(asOf: today, calendar: calendar).first { $0.id == first.id }?.isRead == true)
        #expect(try books.unreadNoticeCount(asOf: today, calendar: calendar) == 3)
        try books.dismissNotice(first.id)
        #expect(try !books.notices(asOf: today, calendar: calendar).contains { $0.id == first.id })
        try books.markAllNoticesRead(asOf: today, calendar: calendar)
        #expect(try books.unreadNoticeCount(asOf: today, calendar: calendar) == 0)
    }

    // MARK: Datos de ejemplo

    @Test("Los datos de ejemplo traen algo de cada función nueva y siguen cuadrando")
    func sampleData() throws {
        let sample = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(sample.mainContext)
        let context = sample.mainContext
        let sampleBooks = Bookkeeper(context: context)
        #expect(try context.fetch(FetchDescriptor<Bill>()).contains { $0.isScheduled })
        #expect(try context.fetch(FetchDescriptor<RecurringTemplate>()).contains { $0.autoCharge })
        #expect(try context.fetch(FetchDescriptor<Expense>()).contains { $0.recurringTemplateID != nil && $0.isPosted })
        #expect(try context.fetch(FetchDescriptor<Estimate>()).first?.status == .accepted)
        #expect(try context.fetchCount(FetchDescriptor<CustomerNote>()) >= 2)
        #expect(try context.fetch(FetchDescriptor<Vendor>()).contains { $0.w9Received })
        #expect(try sampleBooks.accounts().filter { !$0.last4.isEmpty }.count == 3)
        #expect(try context.fetch(FetchDescriptor<InvoiceEvent>()).contains { $0.kind == .reminder })
        #expect(try context.fetch(FetchDescriptor<Expense>()).contains { $0.isBillable && $0.salesTaxIncluded > 0 })
        #expect(ReportBuilder.trialBalance(accounts: try sampleBooks.ledgerAccounts(), lines: try sampleBooks.ledgerLines(), asOf: .distantFuture).isBalanced)
        #expect(try !sampleBooks.notices().isEmpty)
    }
}
