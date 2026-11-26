import ChirograCore
import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Avisos nuevos de la 1.4 (presupuesto excedido, pago al IRS, cita por facturar) y el resumen diario que los avisa.
@MainActor
@Suite("Avisos de la 1.4 y resumen diario")
struct NoticeDigestTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    var books: Bookkeeper { Bookkeeper(context: context) }
    let calendar = Calendar.current

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        _ = try Bookkeeper(context: container.mainContext, actor: "Pruebas")
            .setUpCompany(legalName: "Avisos LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func expense(_ cents: Int64, on day: Date) throws -> Account {
        let category = try #require(ExpenseCategories.groups(from: try books.accounts()).costs.first)
        let bank = try #require(try books.accounts().first { $0.subtype == .bank })
        _ = try books.createExpense(ExpenseInput(date: day, payee: "Tienda", paymentAccountID: bank.id,
                                                lines: [.init(amount: cents, accountID: category.id)]))
        return category
    }

    func issuedInvoice(_ cents: Int64, issued: Date, due: Date) throws -> Invoice {
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: issued, dueDate: due,
                                                            lines: [.init(details: "Servicio", unitPrice: cents, isTaxable: false,
                                                                          incomeAccountID: income.id)]))
        try books.issue(invoice)
        return invoice
    }

    @Test("Presupuesto excedido: la categoría del mes que pasa de lo presupuestado")
    func budget() throws {
        let now = date(2026, 11, 20)
        let category = try expense(30_000, on: date(2026, 11, 10))
        let budget = try books.createBudget(name: "Base", fiscalYear: 2026)
        try books.setBudgetAmount(10_000, account: category, month: 11, in: budget)
        let notice = try #require(try books.notices(asOf: now).first { $0.kind == .budgetExceeded })
        #expect(notice.amount == 20_000)
        #expect(notice.party == category.name)
        // En el mes siguiente ya no.
        #expect(try books.notices(asOf: date(2026, 12, 2)).allSatisfy { $0.kind != .budgetExceeded })
    }

    @Test("Pago estimado al IRS: sale en los 15 días antes de que venza, con lo que falta por apartar")
    func estimatedTax() throws {
        _ = try issuedInvoice(1_000_000, issued: date(2026, 10, 5), due: date(2026, 10, 20))
        let notice = try #require(try books.notices(asOf: date(2027, 1, 5)).first { $0.kind == .estimatedTaxDue })
        #expect(notice.amount > 0)
        #expect(notice.days == 10)
        #expect(try books.notices(asOf: date(2026, 12, 20)).allSatisfy { $0.kind != .estimatedTaxDue })
    }

    @Test("Cita hecha sin facturar: aviso hasta que se factura")
    func appointmentToInvoice() throws {
        let start = date(2026, 11, 18, 15)
        let saved = try books.createAppointment(AppointmentDraft(title: "Medir la cocina", start: start))
        let occurrence = try #require(try books.appointment(for: Bookkeeper.key(of: saved)))
        try books.setStatus(.done, of: occurrence)
        let notice = try #require(try books.notices(asOf: date(2026, 11, 20)).first { $0.kind == .appointmentToInvoice })
        #expect(notice.party == "Medir la cocina")
        #expect(notice.amount == 0)
    }

    @Test("Resumen diario: avisa el día en que aparece algo nuevo y no los días siguientes")
    func digest() throws {
        let now = date(2026, 11, 20, 7)
        // Vence el 21: el 22 a las 9 sale como vencida (nueva); el 23 ya no es nueva.
        _ = try issuedInvoice(50_000, issued: date(2026, 11, 1), due: date(2026, 11, 21))
        let plan = NoticeDigest.plan(books: books, now: now, minutes: 9 * 60, basis: .accrual)
        let days = plan.map { calendar.component(.day, from: $0.fireDate) }
        #expect(days.contains(22))
        #expect(!days.contains(23))
        let item = try #require(plan.first { calendar.component(.day, from: $0.fireDate) == 22 })
        #expect(item.body.contains("vencida"))
        #expect(item.question.contains("¿Qué hago primero?"))
        #expect(calendar.component(.hour, from: item.fireDate) == 9)
    }

    @Test("Resumen diario: nada nuevo, ningún aviso; hoy ya pasada la hora, se salta")
    func digestQuiet() {
        #expect(NoticeDigest.plan(books: books, now: date(2026, 11, 20, 7), minutes: 9 * 60, basis: .accrual).isEmpty)
        let late = NoticeDigest.plan(books: books, now: date(2026, 11, 20, 23), minutes: 9 * 60, basis: .accrual)
        #expect(late.allSatisfy { $0.fireDate > date(2026, 11, 20, 23) })
    }
}
