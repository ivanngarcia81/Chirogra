import ChirograCore
import Foundation
import Testing
@testable import ChirograData

@MainActor
@Suite("Categorías de un gasto")
struct ExpenseCategoriesTests {
    private func accounts(_ template: ChartTemplate, spanish: Bool) -> [Account] {
        template.entries.map { Account(code: $0.code, name: spanish ? $0.spanish : $0.english, subtype: $0.subtype, isSystem: $0.isSystem) }
    }

    @Test("Construcción: primero gastos y costos; aparte, equipo, vehículos y prepagos; nunca retención ni depreciación",
          arguments: [true, false])
    func construction(spanish: Bool) {
        let groups = ExpenseCategories.groups(from: accounts(.usConstruction, spanish: spanish))
        #expect(groups.costs.allSatisfy { $0.type == .expense })
        #expect(groups.costs.map(\.code).first == "5000")
        #expect(groups.costs.map(\.code).contains("5300"))
        #expect(!groups.costs.map(\.code).contains("6900"), "el gasto de depreciación no se paga")
        #expect(groups.assetPurchases.map(\.code) == ["1300", "1500", "1510"])
        #expect(!groups.includesInventory)
        let all = (groups.costs + groups.assetPurchases).map(\.code)
        for excluded in ["1000", "1010", "1090", "1100", "1150", "1590", "2000", "2100", "3000", "4000"] {
            #expect(!all.contains(excluded), "\(excluded)")
        }
    }

    @Test("Comercio: el inventario va con las compras de activo", arguments: [true, false])
    func retail(spanish: Bool) {
        let groups = ExpenseCategories.groups(from: accounts(.usRetail, spanish: spanish))
        #expect(groups.assetPurchases.map(\.code) == ["1200", "1300", "1500", "1510"])
        #expect(groups.includesInventory)
        #expect(groups.costs.map(\.code).contains("6120"))
    }

    @Test("Servicios: todos los gastos operativos y de costo salvo la depreciación")
    func services() {
        let all = accounts(.usServices, spanish: true)
        let groups = ExpenseCategories.groups(from: all)
        let expected = all.filter { $0.type == .expense && $0.code != "6900" }.map(\.code)
        #expect(groups.costs.map(\.code) == expected)
    }

    @Test("Contra-cuentas creadas por el usuario, sin acentos ni mayúsculas, también fuera")
    func userContraAccounts() {
        let list = [
            Account(code: "1595", name: "AMORTIZACION ACUMULADA SOFTWARE", subtype: .fixedAsset),
            Account(code: "1110", name: "Allowance for Doubtful Accounts", subtype: .otherCurrentAsset),
            Account(code: "1520", name: "Computadoras", subtype: .fixedAsset),
            Account(code: "1800", name: "Depósitos en garantía", subtype: .otherAsset),
        ]
        let groups = ExpenseCategories.groups(from: list)
        #expect(groups.assetPurchases.map(\.code) == ["1520"])
        #expect(groups.costs.isEmpty)
    }

    @Test("Archivadas fuera, salvo la que ya estaba elegida, que se conserva al final de su grupo")
    func keepsSelection() {
        let archived = Account(code: "6010", name: "Ferias", subtype: .operatingExpense)
        archived.isArchived = true
        let retainage = Account(code: "1150", name: "Retenciones por cobrar (retainage)", subtype: .otherCurrentAsset)
        let supplies = Account(code: "6500", name: "Suministros", subtype: .operatingExpense)
        let list = [archived, retainage, supplies]
        #expect(ExpenseCategories.groups(from: list).costs.map(\.code) == ["6500"])
        #expect(ExpenseCategories.groups(from: list, keeping: archived.id).costs.map(\.code) == ["6500", "6010"])
        #expect(ExpenseCategories.groups(from: list, keeping: retainage.id).assetPurchases.map(\.code) == ["1150"])
        #expect(ExpenseCategories.groups(from: list, keeping: supplies.id).costs.map(\.code) == ["6500"])
    }
}
