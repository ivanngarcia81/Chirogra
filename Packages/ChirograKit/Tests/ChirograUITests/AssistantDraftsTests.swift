import ChirograCore
import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Registrar con una frase (1.4): lo que entiende la app de lo que pide Claude, lo que falta y que solo se guarda al
/// pulsar «Guardar».
@MainActor
@Suite("Borradores del asistente")
struct AssistantDraftsTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    var books: Bookkeeper { Bookkeeper(context: context) }
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 10))!

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        _ = try Bookkeeper(context: container.mainContext, actor: "Pruebas")
            .setUpCompany(legalName: "Asistente LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func prepare(_ name: String, _ input: [String: JSONValue]) throws -> (AssistantDraft, [String: Any]) {
        let (draft, json) = try #require(AssistantDrafts.prepare(name, input: .object(input), context: context, now: now))
        return (draft, try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]))
    }

    func value(_ draft: AssistantDraft, _ label: String) -> String? { draft.rows.first { $0.label == label }?.value }

    @Test("Gasto: monto en centavos, categoría por su nombre y nada guardado hasta «Guardar»")
    func expense() throws {
        let category = try #require(ExpenseCategories.groups(from: try books.accounts()).costs.first)
        let (draft, result) = try prepare("preparar_gasto", ["monto": .number(85.5), "proveedor": .string("Adobe"),
                                                             "categoria": .string(category.name.uppercased())])
        #expect(value(draft, "Monto") == Int64(8_550).money)
        #expect(value(draft, "Categoría") == category.name)
        #expect(draft.missing.isEmpty)
        #expect((result["estado"] as? String)?.contains("SIN GUARDAR") == true)
        #expect(try books.fetch(Expense.self).isEmpty)

        #expect(AssistantDrafts.save(draft, context: context) == .saved(invoiceID: nil))
        let saved = try #require(try books.fetch(Expense.self).first)
        #expect(saved.payee == "Adobe")
    }

    @Test("Gasto sin monto ni categoría: dice qué falta, da las opciones y no deja guardar")
    func expenseMissing() throws {
        let (draft, result) = try prepare("preparar_gasto", ["proveedor": .string("Tienda Rara"), "categoria": .string("zzz")])
        #expect(draft.missing.contains("el monto"))
        #expect(draft.missing.contains("la categoría"))
        #expect(!draft.canSave)
        #expect((result["categorias_posibles"] as? [String])?.isEmpty == false)
        #expect(result["proveedor_nuevo"] as? Bool == true)
    }

    @Test("Factura: cliente por su nombre y, al guardar, un borrador sin emitir")
    func invoice() throws {
        books.insert(Customer(name: "Ana López"))
        let (draft, _) = try prepare("preparar_factura", [
            "cliente": .string("ana"),
            "lineas": .array([.object(["descripcion": .string("Diseño"), "cantidad": .number(3), "precio": .number(60)])]),
        ])
        #expect(value(draft, "Cliente") == "Ana López")
        #expect(value(draft, "Subtotal") == Int64(18_000).money)
        guard case .saved(let id?) = AssistantDrafts.save(draft, context: context) else {
            Issue.record("No se guardó el borrador"); return
        }
        let invoice = try #require(try books.fetch(Invoice.self).first { $0.id == id })
        #expect(invoice.status == .draft)
    }

    @Test("Factura para un cliente que no está: falta el cliente y vienen los que hay")
    func invoiceUnknownCustomer() throws {
        books.insert(Customer(name: "Ana López"))
        let (draft, result) = try prepare("preparar_factura", [
            "cliente": .string("Pedro"), "lineas": .array([.object(["descripcion": .string("Visita"), "precio": .number(50)])]),
        ])
        #expect(draft.missing.contains("el cliente"))
        #expect((result["clientes_posibles"] as? [String]) == ["Ana López"])
    }

    @Test("Cobro: la factura del cliente, el saldo entero y la factura queda pagada al guardar")
    func payment() throws {
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: now, dueDate: now,
                                                            lines: [.init(details: "Servicio", unitPrice: 20_000, incomeAccountID: income.id)]))
        try books.issue(invoice)

        let (draft, _) = try prepare("preparar_cobro", ["cliente": .string("cafe aurora"), "metodo": .string("Zelle")])
        #expect(value(draft, "Cobrado") == invoice.balanceDue.money)
        #expect(draft.missing.isEmpty)
        #expect(AssistantDrafts.save(draft, context: context) == .saved(invoiceID: nil))
        #expect(invoice.balanceDue == 0)
    }

    @Test("Cobro sin factura que cuadre: no se puede guardar")
    func paymentWithoutInvoice() throws {
        let (draft, _) = try prepare("preparar_cobro", ["cliente": .string("Nadie")])
        #expect(draft.missing.contains("la factura"))
        #expect(!draft.canSave)
    }

    @Test("Cita: día y hora en la hora del aparato")
    func appointment() throws {
        let (draft, _) = try prepare("preparar_cita", ["inicio": .string("2026-11-27 15:30"), "titulo": .string("Medir la cocina"),
                                                       "minutos": .number(45)])
        #expect(draft.missing.isEmpty)
        #expect(AssistantDrafts.save(draft, context: context) == .saved(invoiceID: nil))
        let saved = try #require(try books.fetch(Appointment.self).first)
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: saved.start)
        #expect(parts.day == 27 && parts.hour == 15 && parts.minute == 30)
        #expect(saved.durationMinutes == 45)
    }

    @Test("Cita sin hora: falta el día y la hora")
    func appointmentWithoutTime() throws {
        let (draft, _) = try prepare("preparar_cita", ["inicio": .string("2026-11-27"), "titulo": .string("Visita")])
        #expect(draft.missing.contains("el día y la hora"))
    }

    @Test("Otra herramienta no es un borrador")
    func notADraft() {
        #expect(AssistantDrafts.prepare("resumen_periodo", input: .null, context: context) == nil)
    }
}
