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

    @Test("Por cobrar y saldos sin datos: listas vacías y totales en cero")
    func empty() throws {
        let receivables = try run("por_cobrar")
        #expect(receivables["facturas"] as? Int == 0)
        let balances = try run("saldos_cuentas")
        #expect(balances["cuentas"] is [Any])
    }
}
