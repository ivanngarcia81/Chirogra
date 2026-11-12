import Foundation
import Testing
@testable import ChirograUI

/// Pestañas y favoritos del iPhone a elección (`PhoneShortcuts`): lo guardado en el aparato se lee siempre bien.
@Suite("Pestañas y favoritos")
@MainActor
struct PhoneShortcutsTests {
    @Test("La barra de fábrica es Ventas · Gastos · Banca")
    func defaults() {
        #expect(PhoneShortcuts.tabs(from: PhoneShortcuts.defaultTabsRaw) == [.sales, .expenses, .banking])
    }

    @Test("Cada herramienta vuelve de su id, y los ids no se repiten")
    func roundTrip() {
        let all = PhoneTool.all
        #expect(PhoneShortcuts.decode(PhoneShortcuts.encode(all)) == all)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.contains(.report(.income)) && all.contains(.journal))
    }

    @Test("Ids desconocidos o repetidos se ignoran, y la barra no pasa de tres")
    func tolerant() {
        #expect(PhoneShortcuts.decode("journal,nada,journal,,banking") == [.journal, .banking])
        #expect(PhoneShortcuts.tabs(from: "journal,taxes,ledger,banking,sales") == [.journal, .taxes, .ledger])
        #expect(PhoneShortcuts.decode("").isEmpty)
    }

    @Test("Solo Ventas, Gastos y Banca son secciones (las rutas del panel las buscan en la barra)")
    func sections() {
        #expect(PhoneTool.all.compactMap(\.section) == [.sales, .expenses, .banking])
    }

    @Test("Los títulos de las pestañas son cortos")
    func shortTabTitles() {
        for tool in PhoneTool.all {
            #expect(tool.tabTitle.count <= 12, "«\(tool.tabTitle)» es largo para la barra")
        }
    }
}
