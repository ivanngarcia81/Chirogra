import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Base caja con notas de crédito, saldo a favor, reembolsos, anulaciones y centavos (auditoría del 23-nov).
///
/// Regla que se comprueba (la de `Bookkeeper.cashBasisLedgerLines`): cada liquidación de una factura —cobro en
/// efectivo o saldo a favor aplicado— reconoce, en su fecha, la parte de la factura que liquida; y cada vez que se
/// consume una nota de crédito fuera de su factura —aplicada a **otra** factura o reembolsada— se reconoce, en esa
/// fecha, la parte de la nota que se consume. Una nota aplicada a su **propia** factura la rebaja (el cobro que
/// falta reconoce la factura ya rebajada). Nada de lo que pasa después cambia un periodo anterior.
///
/// Los importes esperados están calculados a mano en cada prueba, no con el código que se prueba.
@MainActor
@Suite("Base caja: notas de crédito, saldo a favor, reembolsos, anulaciones y centavos")
struct CashBasisCreditTests {
    let container: ModelContainer
    let books: Bookkeeper
    let customer: Customer
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Caja LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        customer = Customer(name: "Cliente")
        books.insert(customer)
        try container.mainContext.save()
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    /// Lo reconocido en la cuenta en su lado normal (ingresos y sales tax en positivo), entre dos días incluidos.
    func amount(_ code: String, _ lines: [LedgerLine], from: Int? = nil, to: Int? = nil) throws -> Int64 {
        let lower = from.map(day) ?? .distantPast
        let upper = to.map(day) ?? .distantFuture
        return ReportBuilder.balance(of: try account(code).ledgerAccount, lines: lines.filter { $0.date >= lower && $0.date <= upper })
    }

    /// Lo reconocido en un solo día.
    func amount(_ code: String, _ lines: [LedgerLine], on offset: Int) throws -> Int64 {
        try amount(code, lines, from: offset, to: offset)
    }

    func taxGroup() throws -> TaxGroup {
        let agency = TaxAgency(name: "Texas Comptroller", liabilityAccountID: try account("2200").id)
        books.insert(agency)
        let rate = TaxRate(name: "Texas", rateMillionths: 82_500, agency: agency)
        books.insert(rate)
        let group = TaxGroup(name: "Austin", rates: [rate])
        books.insert(group)
        try context.save()
        return group
    }

    /// Emite una factura del cliente con una línea por (cuenta, importe).
    @discardableResult
    func issue(_ lines: [(String, Int64)], on offset: Int, tax: TaxGroup? = nil, discount: Int64 = 0,
               to who: Customer? = nil) throws -> Invoice {
        let invoice = try books.saveDraft(InvoiceDraftInput(
            customer: who ?? customer, issueDate: day(offset), dueDate: day(offset), taxGroupID: tax?.id, discount: discount,
            lines: try lines.map { .init(details: $0.0, unitPrice: $0.1, incomeAccountID: try account($0.0).id) }))
        try books.issue(invoice)
        return invoice
    }

    @discardableResult
    func pay(_ invoice: Invoice, _ amount: Int64, on offset: Int) throws -> PaymentReceived {
        try books.recordPayment(for: invoice, amount: amount, date: day(offset), depositAccount: try account("1010"))
    }

    /// Base caja cuadrada: balanza y balance, y sin cuentas por cobrar ni por pagar.
    func expectBalanced(_ lines: [LedgerLine]) throws {
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: lines, asOf: .distantFuture).isBalanced)
        #expect(try amount("1100", lines) == 0)
        #expect(try amount("2000", lines) == 0)
        #expect(try books.balanceSheet(asOf: .distantFuture, basis: .cash).isBalanced)
    }

    /// Con todo liquidado (facturas cobradas o acreditadas y sin saldo a favor), lo reconocido en caja por cuenta es
    /// lo mismo que en devengo.
    func expectSameAsAccrual(_ codes: [String]) throws {
        let cash = try books.cashBasisLedgerLines()
        let accrual = try books.ledgerLines()
        for code in codes {
            #expect(try amount(code, cash) == amount(code, accrual), "cuenta \(code)")
        }
    }

    // MARK: - Prueba obligatoria de la auditoría

    @Test("Factura de $100 cobrada, nota de $20 y ese saldo a favor aplicado a otra de $50 con $30 en efectivo")
    func requiredScenario() throws {
        let a = try issue([("4000", 10_000)], on: -90)
        try pay(a, 10_000, on: -80)
        let note = try books.issueCreditNote(for: a, amount: 2_000, isTaxable: false, reason: "Ajuste", date: day(-60))
        #expect(note.unappliedAmount == 2_000 && customer.creditBalance == 2_000)          // A ya estaba pagada
        let b = try issue([("4000", 5_000)], on: -40)
        try books.applyCustomerCredit(to: b, amount: 2_000, date: day(-30))
        try pay(b, 3_000, on: -20)
        #expect(b.status == .paid && b.balanceDue == 0 && customer.creditBalance == 0)

        let cash = try books.cashBasisLedgerLines()
        // Efectivo recibido: $100 + $30 = $130, y eso es el ingreso en caja: $100 el día del cobro de A, $30 el del de B.
        #expect(try amount("4000", cash, on: -80) == 10_000)
        #expect(try amount("4000", cash, on: -60) == 0)        // la nota no mueve dinero
        #expect(try amount("4000", cash, on: -30) == 0)        // saldo a favor aplicado: −$20 de A y +$20 de B, misma cuenta
        #expect(try amount("4000", cash, on: -20) == 3_000)
        #expect(try amount("4000", cash) == 13_000)
        #expect(try amount("1010", cash) == 13_000)
        // Lo de enero no se reescribe por la nota de febrero: ese día solo hay un haber de $100 en ingresos.
        let income = try account("4000").id
        let firstDay = cash.filter { $0.accountID == income && $0.date == day(-80) }
        #expect(firstDay.reduce(0) { $0 + $1.debit } == 0 && firstDay.reduce(0) { $0 + $1.credit } == 10_000)
        try expectBalanced(cash)

        // Devengo, con sus reglas de siempre: el ingreso al facturar y la nota en su fecha.
        let accrual = try books.ledgerLines()
        #expect(try amount("4000", accrual, on: -90) == 10_000)
        #expect(try amount("4000", accrual, on: -60) == -2_000)
        #expect(try amount("4000", accrual, on: -40) == 5_000)
        #expect(try amount("4000", accrual, on: -30) == 0 && amount("4000", accrual, on: -20) == 0)
        #expect(try amount("4000", accrual) == 13_000)
        #expect(try books.incomeStatement(from: day(-100), to: today, basis: .cash).netIncome == 13_000)
        #expect(try books.incomeStatement(from: day(-100), to: today, basis: .accrual).netIncome == 13_000)
    }

    @Test("La misma prueba con otra cuenta de ingresos en B y sales tax en A: cada cuenta y el impuesto, exactos")
    func requiredScenarioWithTaxAndAccounts() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 10_000)], on: -90, tax: tax)                                // 100 + 8.25 = 108.25
        #expect(a.total == 10_825)
        try pay(a, 10_825, on: -80)
        let note = try books.issueCreditNote(for: a, amount: 2_000, isTaxable: true, reason: "Ajuste", date: day(-60))
        #expect(note.total == 2_165)                                                            // 20 + 1.65
        let b = try issue([("4100", 5_000)], on: -40)                                          // sin impuesto
        try books.applyCustomerCredit(to: b, amount: 2_165, date: day(-30))
        try pay(b, 2_835, on: -20)

        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4000", cash, on: -80) == 10_000 && amount("2200", cash, on: -80) == 825)
        // El día que se aplica el saldo: A baja lo de la nota (20 + 1.65 de impuesto) y B reconoce 21.65.
        #expect(try amount("4000", cash, on: -30) == -2_000)
        #expect(try amount("2200", cash, on: -30) == -165)
        #expect(try amount("4100", cash, on: -30) == 2_165)
        #expect(try amount("4100", cash, on: -20) == 2_835)
        // Totales = devengo: 4000 = 100 − 20, 4100 = 50, sales tax = 8.25 − 1.65.
        #expect(try amount("4000", cash) == 8_000 && amount("4100", cash) == 5_000 && amount("2200", cash) == 660)
        try expectSameAsAccrual(["4000", "4100", "2200", "1010"])
        try expectBalanced(cash)
    }

    // MARK: - Notas sobre la propia factura

    @Test("Cobro parcial, nota sobre una línea de la propia factura y el resto: lo ya reconocido no cambia")
    func partialPaymentThenOwnNote() throws {
        let a = try issue([("4000", 6_000), ("4100", 4_000)], on: -90)
        try pay(a, 5_000, on: -80)
        let before = try books.cashBasisLedgerLines()
        #expect(try amount("4000", before, on: -80) == 3_000 && amount("4100", before, on: -80) == 2_000)

        let productLine = try #require(a.sortedLines.last?.id)
        try books.issueCreditNote(for: a, amount: 2_000, isTaxable: false, reason: "Material devuelto", date: day(-60), lineID: productLine)
        #expect(a.balanceDue == 3_000)
        let afterNote = try books.cashBasisLedgerLines()
        #expect(try amount("4000", afterNote, on: -80) == 3_000 && amount("4100", afterNote, on: -80) == 2_000)
        #expect(try amount("4000", afterNote, on: -60) == 0 && amount("4100", afterNote, on: -60) == 0)

        try pay(a, 3_000, on: -20)
        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4000", cash, on: -80) == 3_000 && amount("4100", cash, on: -80) == 2_000)
        #expect(try amount("4000", cash, on: -20) == 3_000 && amount("4100", cash, on: -20) == 0)
        try expectSameAsAccrual(["4000", "4100"])
        try expectBalanced(cash)
    }

    @Test("Nota antes de cobrar (lo habitual): el cobro reconoce la factura ya rebajada")
    func noteBeforePayment() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 6_000), ("4100", 4_000)], on: -90, tax: tax, discount: 1_000)
        // 10 000 − 1 000 de descuento = 9 000; impuesto 8.25 % = 742.50 → total 9 742.50
        #expect(a.total == 9_743 || a.total == 9_742)
        let total = a.total
        let note = try books.issueCreditNote(for: a, amount: 1_000, isTaxable: true, reason: "Rebaja", date: day(-80))
        try pay(a, total - note.total, on: -70)
        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4000", cash, on: -80) == 0 && amount("2200", cash, on: -80) == 0)
        #expect(try amount("1010", cash) == total - note.total)
        try expectSameAsAccrual(["4000", "4100", "4900", "2200", "1010"])
        try expectBalanced(cash)
    }

    @Test("Nota mayor que el saldo: una parte rebaja la propia factura y el resto se aplica a otra")
    func noteSplitBetweenOwnAndOther() throws {
        let a = try issue([("4000", 10_000)], on: -90)
        try pay(a, 9_000, on: -80)
        let note = try books.issueCreditNote(for: a, amount: 3_000, isTaxable: false, reason: "Ajuste", date: day(-60))
        #expect(a.status == .paid && note.unappliedAmount == 2_000)
        let b = try issue([("4100", 5_000)], on: -40)
        try books.applyCustomerCredit(to: b, amount: 2_000, date: day(-30))
        try pay(b, 3_000, on: -20)

        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4000", cash, on: -80) == 9_000)
        #expect(try amount("4000", cash, on: -60) == 0)
        #expect(try amount("4000", cash, on: -30) == -2_000 && amount("4100", cash, on: -30) == 2_000)
        #expect(try amount("4100", cash, on: -20) == 3_000)
        #expect(try amount("4000", cash) == 7_000 && amount("4100", cash) == 5_000)
        try expectSameAsAccrual(["4000", "4100"])
        try expectBalanced(cash)
    }

    // MARK: - Un saldo a favor en varias facturas

    @Test("Un saldo a favor repartido en dos facturas, con impuesto y descuento")
    func creditAcrossTwoInvoices() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 10_000)], on: -100, tax: tax)
        try pay(a, a.total, on: -90)                                                        // 108.25
        let note = try books.issueCreditNote(for: a, amount: 4_000, isTaxable: true, reason: "Devolución", date: day(-70))
        #expect(note.total == 4_330)                                                        // 40 + 3.30
        let b = try issue([("4100", 2_000)], on: -60, tax: tax)
        #expect(b.total == 2_165)
        let c = try issue([("4000", 3_000)], on: -50, discount: 500)                        // 25, sin impuesto
        try books.applyCustomerCredit(to: b, amount: 2_165, date: day(-40))
        try books.applyCustomerCredit(to: c, amount: 2_165, date: day(-30))
        try pay(c, 335, on: -20)
        #expect(b.status == .paid && c.status == .paid && customer.creditBalance == 0)

        let cash = try books.cashBasisLedgerLines()
        // Día -40: la mitad de la nota (−40 de 4000 en dos mitades, −1.65 de impuesto) y B entera (+20 en 4100, +1.65).
        #expect(try amount("4000", cash, on: -40) == -2_000)
        #expect(try amount("4100", cash, on: -40) == 2_000)
        #expect(try amount("2200", cash, on: -40) == 0)
        // Día -30: la otra mitad de la nota y 21.65 de los 25 de C (30 de ingreso y −5 de descuento, en proporción).
        #expect(try amount("4000", cash, on: -30) == -2_000 + 2_598)
        #expect(try amount("4900", cash, on: -30) == -433)
        #expect(try amount("2200", cash, on: -30) == -165)
        // Día -20: lo que faltaba de C.
        #expect(try amount("4000", cash, on: -20) == 402 && amount("4900", cash, on: -20) == -67)
        // Totales = devengo: 4000 = 100 − 40 + 30, 4100 = 20, descuento −5, sales tax = 8.25 − 3.30 + 1.65.
        #expect(try amount("4000", cash) == 9_000 && amount("4100", cash) == 2_000)
        #expect(try amount("4900", cash) == -500 && amount("2200", cash) == 660)
        try expectSameAsAccrual(["4000", "4100", "4900", "2200", "1010"])
        try expectBalanced(cash)
    }

    // MARK: - Reembolsos

    @Test("Dos reembolsos de dos notas en cuentas distintas: cada uno baja la cuenta de su nota, en su fecha")
    func refundsOfDifferentNotes() throws {
        let checking = try account("1010")
        let a = try issue([("4000", 10_000)], on: -90)
        try pay(a, 10_000, on: -85)
        let b = try issue([("4100", 8_000)], on: -80)
        try pay(b, 8_000, on: -75)
        try books.issueCreditNote(for: a, amount: 1_000, isTaxable: false, reason: "X", date: day(-60))
        try books.refundCustomerCredit(customer, amount: 1_000, date: day(-50), from: checking)
        let afterFirst = try books.cashBasisLedgerLines()
        #expect(try amount("4000", afterFirst, on: -50) == -1_000 && amount("4100", afterFirst, on: -50) == 0)

        try books.issueCreditNote(for: b, amount: 2_000, isTaxable: false, reason: "Y", date: day(-40))
        try books.refundCustomerCredit(customer, amount: 2_000, date: day(-30), from: checking)
        let cash = try books.cashBasisLedgerLines()
        // El primer reembolso no cambia por el segundo.
        #expect(try amount("4000", cash, on: -50) == -1_000 && amount("4100", cash, on: -50) == 0)
        #expect(try amount("4100", cash, on: -30) == -2_000 && amount("4000", cash, on: -30) == 0)
        #expect(try amount("4000", cash) == 9_000 && amount("4100", cash) == 6_000)
        try expectSameAsAccrual(["4000", "4100", "1010"])
        try expectBalanced(cash)
    }

    @Test("Saldo a favor en parte aplicado y en parte reembolsado")
    func creditPartlyAppliedPartlyRefunded() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 20_000)], on: -90, tax: tax)
        try pay(a, a.total, on: -85)
        let note = try books.issueCreditNote(for: a, amount: 6_000, isTaxable: true, reason: "Devolución", date: day(-60))
        #expect(note.total == 6_495)
        let b = try issue([("4100", 3_000)], on: -50)
        try books.applyCustomerCredit(to: b, amount: 3_000, date: day(-40))
        try books.refundCustomerCredit(customer, amount: 3_495, date: day(-30), from: try account("1010"))
        #expect(customer.creditBalance == 0)

        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4100", cash, on: -40) == 3_000)
        #expect(try amount("4000", cash, on: -40) + amount("2200", cash, on: -40) == -3_000)
        #expect(try amount("4000", cash, on: -30) + amount("2200", cash, on: -30) == -3_495)
        try expectSameAsAccrual(["4000", "4100", "2200", "1010"])
        try expectBalanced(cash)
    }

    @Test("Una nota con fecha anterior emitida después no cambia lo que consumió un reembolso ya hecho (revisión)")
    func backdatedNoteAfterRefund() throws {
        let checking = try account("1010")
        let tax = try taxGroup()
        let i1 = try issue([("4000", 100_000)], on: -90)
        try pay(i1, 100_000, on: -89)
        let i2 = try issue([("4100", 100_000)], on: -80, tax: tax)
        try pay(i2, i2.total, on: -79)
        try books.issueCreditNote(for: i2, amount: 10_000, isTaxable: true, reason: "B", date: day(-60))    // 108.25
        try books.refundCustomerCredit(customer, amount: 5_000, date: day(-59), from: checking)
        let before = try books.cashBasisLedgerLines()
        let refundDay = (try amount("4100", before, on: -59), try amount("2200", before, on: -59))
        #expect(refundDay.0 + refundDay.1 == -5_000 && refundDay.1 != 0)
        // Nota A sobre I1, emitida ahora pero con fecha anterior a la B; y un reembolso de lo que queda.
        try books.issueCreditNote(for: i1, amount: 10_000, isTaxable: false, reason: "A", date: day(-65))
        try books.refundCustomerCredit(customer, amount: customer.creditBalance, date: day(-30), from: checking)
        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4100", cash, on: -59) == refundDay.0 && amount("2200", cash, on: -59) == refundDay.1)
        #expect(try amount("4000", cash, on: -59) == 0)
        try expectSameAsAccrual(["4000", "4100", "2200", "1010"])
        try expectBalanced(cash)
    }

    @Test("Con un reembolso que no cuadra (dos aparatos a la vez), lo pendiente de la nota no se pierde (revisión)")
    func failedRefundKeepsPending() throws {
        let checking = try account("1010")
        let a = try issue([("4000", 10_000)], on: -90)
        try pay(a, 10_000, on: -89)
        let note = try books.issueCreditNote(for: a, amount: 10_000, isTaxable: false, reason: "A", date: day(-80))
        try books.refundCustomerCredit(customer, amount: 4_000, date: day(-70), from: checking)
        try books.refundCustomerCredit(customer, amount: 6_000, date: day(-69), from: checking)
        // Lo que deja iCloud si los dos reembolsos se hicieron a la vez: la nota con lo de un solo aparato.
        note.refundedAmount = 6_000
        note.unappliedAmount = 4_000
        let b = try issue([("4100", 4_000)], on: -60)
        try books.applyCustomerCredit(to: b, amount: 4_000, date: day(-50))
        let cash = try books.cashBasisLedgerLines()
        // El primer reembolso se reconoce; el segundo no cuadra y se queda con su cuenta por cobrar a la vista, pero el
        // saldo aplicado a B sí se reconoce (antes se perdía por un signo al revés al deshacer).
        #expect(try amount("4000", cash, on: -70) == -4_000)
        #expect(try amount("4000", cash, on: -50) == -4_000 && amount("4100", cash, on: -50) == 4_000)
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: cash, asOf: .distantFuture).isBalanced)
    }

    // MARK: - Anulaciones

    @Test("Anular el cobro de una factura pagada en parte con saldo a favor revierte solo lo del cobro")
    func voidPaymentAfterCredit() throws {
        let a = try issue([("4000", 10_000)], on: -90)
        try pay(a, 10_000, on: -85)
        try books.issueCreditNote(for: a, amount: 2_000, isTaxable: false, reason: "Ajuste", date: day(-80))
        let b = try issue([("4100", 5_000)], on: -70)
        try books.applyCustomerCredit(to: b, amount: 2_000, date: day(-60))
        let cashPayment = try pay(b, 3_000, on: -50)
        try books.voidPayment(cashPayment, on: day(-40))
        #expect(b.balanceDue == 3_000 && b.status == .partiallyPaid)

        let voided = try books.cashBasisLedgerLines()
        #expect(try amount("4100", voided, on: -60) == 2_000)
        #expect(try amount("4100", voided, on: -50) == 3_000)          // el periodo del cobro no se reescribe
        #expect(try amount("4100", voided, on: -40) == -3_000)
        #expect(try amount("4100", voided) == 2_000 && amount("4000", voided) == 8_000)
        try expectBalanced(voided)

        try pay(b, 3_000, on: -20)
        let cash = try books.cashBasisLedgerLines()
        #expect(try amount("4100", cash, on: -20) == 3_000)
        try expectSameAsAccrual(["4000", "4100", "1010"])
        try expectBalanced(cash)
    }

    // MARK: - Centavos e importes extremos

    @Test("Cobros de un centavo y líneas de tercios: al liquidar, cada cuenta queda exacta al centavo")
    func pennies() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 3_333), ("4100", 3_333), ("4000", 3_334)], on: -60, tax: tax)
        let total = a.total
        for (amount, offset) in [(Int64(1), -50), (3_333, -40), (1, -35)] {
            let payment = try pay(a, amount, on: offset)
            let bank = try account("1010").id
            let lines = try books.cashBasisLedgerLines().filter { $0.entryID == payment.journalEntryID && $0.accountID != bank }
            // Lo reconocido por cada cobro (ingresos e impuesto) suma exactamente el cobro.
            #expect(lines.reduce(0) { $0 + $1.credit - $1.debit } == amount)
        }
        try pay(a, total - 3_335, on: -30)
        try expectSameAsAccrual(["4000", "4100", "2200", "1010"])
        try expectBalanced(try books.cashBasisLedgerLines())
    }

    @Test("Factura de proveedor pagada en partes: cada cuenta de gasto queda exacta al centavo")
    func billPennies() throws {
        let vendor = Vendor(name: "Proveedor")
        books.insert(vendor)
        let bill = Bill(vendor: vendor, vendorNumber: "P-1", billDate: day(-60))
        books.insert(bill)
        for (code, amount) in [("5000", 3_333), ("6500", 3_333), ("6050", 3_334)] {
            let line = BillLine(details: code, amount: Int64(amount), accountID: try account(code).id)
            line.bill = bill
            books.insert(line)
        }
        try books.record(bill)
        let checking = try account("1010")
        try books.pay(bill, amount: 1, date: day(-50), from: checking)
        try books.pay(bill, amount: 5_000, date: day(-40), from: checking)
        try books.pay(bill, amount: 4_999, date: day(-30), from: checking)
        #expect(bill.balanceDue == 0)
        try expectSameAsAccrual(["5000", "6500", "6050", "1010"])
        try expectBalanced(try books.cashBasisLedgerLines())
    }

    @Test("Importes extremos: una factura de casi diez mil millones con impuesto, en dos cobros")
    func extremeAmounts() throws {
        let tax = try taxGroup()
        let a = try issue([("4000", 999_999_999_999), ("4100", 1)], on: -60, tax: tax)
        try pay(a, 1, on: -50)
        try pay(a, a.balanceDue, on: -40)
        try expectSameAsAccrual(["4000", "4100", "2200", "1010"])
        try expectBalanced(try books.cashBasisLedgerLines())
    }

    // MARK: - Propiedad con operaciones al azar

    /// Generador determinista (SplitMix64): la misma semilla da siempre la misma historia.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("Propiedad: con historias al azar nada reescribe un día ya pasado y, liquidado todo, caja = devengo por cuenta",
          arguments: [UInt64(1), 7, 42, 2026])
    func randomHistories(seed: UInt64) throws {
        var random = SeededGenerator(state: seed)
        let tax = try taxGroup()
        let checking = try account("1010")
        let codes = ["4000", "4100", "4900", "2200", "1010"]
        var invoices: [Invoice] = []
        var payments: [PaymentReceived] = []
        var snapshots: [(day: Int, lines: [LedgerLine])] = []
        var offset = -700

        for _ in 0..<120 {
            offset += Int.random(in: 1...5, using: &random)
            let open = invoices.filter { $0.isOpen && $0.balanceDue > 0 }
            switch Int.random(in: 0..<7, using: &random) {
            case 0, 1:
                let lines: [(String, Int64)] = (0..<Int.random(in: 1...3, using: &random)).map { _ in
                    ([("4000"), ("4100")].randomElement(using: &random)!, Int64.random(in: 1...50_000, using: &random))
                }
                let subtotal = lines.reduce(0) { $0 + $1.1 }
                let discount = Bool.random(using: &random) ? Int64.random(in: 0...(subtotal / 4), using: &random) : 0
                invoices.append(try issue(lines, on: offset, tax: Bool.random(using: &random) ? tax : nil, discount: discount))
            case 2:
                if let invoice = open.randomElement(using: &random) {
                    // La mitad de las veces se cobra todo: así hay facturas pagadas a las que hacerles notas (saldo a favor).
                    let amount = Bool.random(using: &random) ? invoice.balanceDue : Int64.random(in: 1...invoice.balanceDue, using: &random)
                    payments.append(try pay(invoice, amount, on: offset))
                }
            case 3:
                let creditable = invoices.filter { [.sent, .partiallyPaid, .paid].contains($0.status) }
                let paid = creditable.filter { $0.status == .paid }
                if let invoice = (Bool.random(using: &random) && !paid.isEmpty ? paid : creditable).randomElement(using: &random) {
                    let room = invoice.total - (invoice.creditNotes ?? []).reduce(0) { $0 + $1.total }
                    let net = invoice.netSales - (invoice.creditNotes ?? []).reduce(0) { $0 + $1.amount }
                    let cap = min(room * 9 / 10, net)
                    if cap > 1 {
                        try books.issueCreditNote(for: invoice, amount: Int64.random(in: 1...cap, using: &random),
                                                  isTaxable: Bool.random(using: &random), reason: "Azar", date: day(offset))
                    }
                }
            case 4:
                if customer.creditBalance > 0, let invoice = open.randomElement(using: &random) {
                    let amount = Int64.random(in: 1...min(customer.creditBalance, invoice.balanceDue), using: &random)
                    try books.applyCustomerCredit(to: invoice, amount: amount, date: day(offset))
                }
            case 5:
                if customer.creditBalance > 0 {
                    try books.refundCustomerCredit(customer, amount: Int64.random(in: 1...customer.creditBalance, using: &random),
                                                   date: day(offset), from: checking)
                }
            default:
                let live = payments.filter { !books.isVoided($0) && $0.applications?.first?.invoice?.status != .void }
                if let payment = live.randomElement(using: &random) {
                    try books.voidPayment(payment, on: day(offset))
                }
            }
            if Int.random(in: 0..<4, using: &random) == 0 {
                snapshots.append((offset, try books.cashBasisLedgerLines()))
            }
        }

        // Liquidar todo: el saldo a favor a lo que haya pendiente, cobrar el resto y reembolsar lo que sobre.
        offset += 1
        for invoice in invoices where invoice.isOpen && invoice.balanceDue > 0 && customer.creditBalance > 0 {
            try books.applyCustomerCredit(to: invoice, amount: min(customer.creditBalance, invoice.balanceDue), date: day(offset))
        }
        for invoice in invoices where invoice.isOpen && invoice.balanceDue > 0 {
            try pay(invoice, invoice.balanceDue, on: offset)
        }
        if customer.creditBalance > 0 {
            try books.refundCustomerCredit(customer, amount: customer.creditBalance, date: day(offset), from: checking)
        }

        let cash = try books.cashBasisLedgerLines()
        // La historia tocó todos los casos: saldo a favor en otra factura, reembolsos, notas y cobros anulados.
        let applications = try books.fetch(CreditApplication.self)
        #expect(applications.contains { $0.note?.invoice?.id != $0.invoice?.id })
        #expect(applications.contains { $0.note?.invoice?.id == $0.invoice?.id })
        #expect(try books.postedEntries().contains { $0.source == .customerRefund })
        #expect(payments.contains { books.isVoided($0) })
        try expectBalanced(cash)
        try expectSameAsAccrual(codes)
        // Lo de cada día que ya había pasado al tomar la foto sigue igual al final.
        for snapshot in snapshots {
            for code in codes {
                #expect(try amount(code, snapshot.lines, to: snapshot.day) == amount(code, cash, to: snapshot.day),
                        "semilla \(seed), cuenta \(code), hasta el día \(snapshot.day)")
            }
        }
    }
}
