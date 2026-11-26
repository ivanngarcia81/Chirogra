import ChirograCore
import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Las herramientas que el asistente ejecuta en el aparato (1.4): lo que devuelven y cómo fallan.
@MainActor
@Suite("Herramientas del asistente")
struct AssistantToolsTests {
    let container: ModelContainer
    let books: Bookkeeper
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 23, minute: 30))!

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Asistente LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func run(_ name: String, _ input: [String: String] = [:]) throws -> [String: Any] {
        let json = AssistantTools.run(name, input: .object(input.mapValues { .string($0) }), context: container.mainContext,
                                      basis: .accrual, now: now)
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test("Resumen del periodo: cifras formateadas y el periodo que se usó")
    func summary() throws {
        let result = try run("resumen_periodo", ["desde": "2026-11-01", "hasta": "2026-11-30"])
        #expect(result["periodo"] as? String == "2026-11-01 a 2026-11-30")
        #expect(result["ganancia_neta"] is String)
        #expect(result["base"] as? String == "devengado")
    }

    @Test("Fechas al revés o mal escritas: un error que el modelo puede leer, no un fallo")
    func badDates() throws {
        #expect(try run("resumen_periodo", ["desde": "2026-12-01", "hasta": "2026-11-01"])["error"] != nil)
        #expect(try run("citas", ["desde": "noviembre", "hasta": "2026-11-30"])["error"] != nil)
    }

    @Test("Una herramienta que no existe")
    func unknown() throws {
        #expect(try run("borrar_todo")["error"] != nil)
    }

    @Test("Las fechas van en la zona del aparato, no en UTC (a las 23:30 sigue siendo el mismo día)")
    func localDay() {
        #expect(AssistantTools.day(now) == "2026-11-25")
    }

    @Test("Buscar movimientos: encuentra el gasto por el proveedor, con el total por tipo")
    func search() throws {
        let category = try #require(ExpenseCategories.groups(from: try books.accounts()).costs.first)
        let (draft, _) = try #require(AssistantDrafts.prepare("preparar_gasto", input: .object([
            "monto": .number(40), "proveedor": .string("Home Depot"), "categoria": .string(category.name),
            "fecha": .string("2026-11-20")]), context: container.mainContext, now: now))
        #expect(AssistantDrafts.save(draft, context: container.mainContext) == .saved(invoiceID: nil))
        let found = try run("buscar_movimientos", ["texto": "home depot", "desde": "2026-01-01"])
        #expect(found["encontrados"] as? Int == 1)
        #expect(try run("buscar_movimientos", ["texto": "home depot", "hasta": "2026-11-19"])["encontrados"] as? Int == 0)
        #expect(try run("buscar_movimientos", ["texto": "x"])["error"] != nil)
    }

    @Test("Sales tax: lo pendiente y los dos periodos con su fecha límite")
    func salesTax() throws {
        let result = try run("sales_tax")
        #expect(result["pendiente_hoy"] is String)
        #expect((result["periodo_anterior"] as? [String: Any])?["fecha_limite"] is String)
        #expect((result["periodo_en_curso"] as? [String: Any])?["impuesto_cobrado"] is String)
    }

    @Test("Abrir pantalla: el botón con el nombre de la barra; una que no existe da error")
    func screen() throws {
        #expect(try run("abrir_pantalla", ["pantalla": "facturas"])["boton"] as? String == "Ir a Facturas")
        #expect(try run("abrir_pantalla", ["pantalla": "nada"])["error"] != nil)
        #expect(Set(AssistantScreens.all.map(\.id)).count == AssistantScreens.all.count)
    }

    @Test("Por cobrar y saldos sin datos: listas vacías y totales en cero")
    func empty() throws {
        let receivables = try run("por_cobrar")
        #expect(receivables["facturas"] as? Int == 0)
        let balances = try run("saldos_cuentas")
        #expect(balances["cuentas"] is [Any])
    }
}
