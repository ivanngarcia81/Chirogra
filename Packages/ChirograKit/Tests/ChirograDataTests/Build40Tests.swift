import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Build 40 (QA Hudson, hallazgos menores): estado del código postal (H13), extracto ya importado (H12) y bitácora de un
/// gasto reclasificado (H20).
@MainActor
@Suite("Build 40: código postal, extracto repetido y bitácora")
struct Build40Tests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        _ = try books.setUpCompany(legalName: "Hudson LLC", entityType: .llc, state: "NJ", locale: Locale(identifier: "es_US"))
    }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    @Test("El ZIP dice el estado, también sin tabla y en estados que la tabla no tiene")
    func postalState() throws {
        #expect(PostalState.state(for: "07102") == "NJ")
        #expect(PostalState.state(for: "07102-1234") == "NJ")
        #expect(PostalState.state(for: "78702") == "TX")
        #expect(PostalState.state(for: "88510") == "TX")
        #expect(PostalState.state(for: "19104") == "PA")
        #expect(PostalState.state(for: "20500") == "DC")
        #expect(PostalState.state(for: "20120") == "VA")
        #expect(PostalState.state(for: "99501") == "AK")
        #expect(PostalState.state(for: "00901") == nil)
        #expect(PostalState.state(for: "123") == nil)
        // Con la tabla, manda la tabla (03579 es de Maine aunque el prefijo 035 sea de New Hampshire).
        let table = PostalTaxTable(rates: [PostalTaxRate(postalCode: "03579", state: "ME", region: "Oxford",
                                                         stateRateMillionths: 55_000, localRateMillionths: 0)])
        #expect(PostalState.state(for: "03579") == "NH")
        #expect(PostalState.state(for: "03579", table: table) == "ME")
    }

    @Test("La vista previa cuenta los ya importados igual que la importación")
    func alreadyImported() throws {
        let checking = try account("1010")
        let lines = (1...3).map { BankStatementLine(date: day(-$0), amount: -1_000 * Int64($0), details: "PAGO \($0)", externalID: "x\($0)") }
        #expect(try books.alreadyImportedCount(lines, in: checking) == 0)
        try books.importStatementLines(lines, source: .ofx, into: checking)
        #expect(try books.alreadyImportedCount(lines, in: checking) == 3)
        let more = lines + [BankStatementLine(date: day(0), amount: -500, details: "NUEVO", externalID: "x9")]
        #expect(try books.alreadyImportedCount(more, in: checking) == 3)
        let result = try books.importStatementLines(more, source: .ofx, into: checking)
        #expect(result.duplicates == 3)
        #expect(result.imported.count == 1)
        // En otra cuenta no cuentan.
        #expect(try books.alreadyImportedCount(lines, in: try account("1000")) == 0)
    }

    @Test("Cambiar solo la categoría: la bitácora dice de cuál a cuál")
    func reclassifySummary() throws {
        let checking = try account("1010")
        try books.recordOpeningBalances(bank: 500_000, on: day(-40))
        let expense = try books.createExpense(ExpenseInput(date: day(-10), payee: "Papel Norte", paymentAccountID: checking.id,
                                                           lines: [.init(amount: 24_000, accountID: try account("6500").id)]))
        var input = ExpenseInput(expense)
        input.lines[0].accountID = try account("6350").id
        try books.updateExpense(expense, with: input)
        let summary = try #require(try books.auditLog(entityID: expense.id).first { $0.action == "edit" }?.summary)
        #expect(summary.contains("Categoría"))
        #expect(summary.contains("6500"))
        #expect(summary.contains("6350"))
        #expect(!summary.contains("$240.00 → $240.00"))

        // Si cambia el importe, el resumen de siempre.
        var bigger = ExpenseInput(expense)
        bigger.lines[0].amount = 30_000
        try books.updateExpense(expense, with: bigger)
        let edits = try books.auditLog(entityID: expense.id).filter { $0.action == "edit" }.map(\.summary)
        #expect(edits.contains { $0.contains("→") && $0.contains("300") })
    }
}
