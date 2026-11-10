import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// «Reclasificar gastos»: varias líneas de una categoría pasan a otra de una vez.
@MainActor
@Suite("Reclasificar gastos")
struct ReclassifyTests {
    let container: ModelContainer
    let books: Bookkeeper

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Taller", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func expenseAccounts() throws -> [Account] {
        try books.accounts().filter { $0.type == .expense }.sorted { $0.code < $1.code }
    }

    func checking() throws -> Account { try #require(try books.accounts().first { $0.code == "1010" }) }

    @discardableResult
    func expense(_ payee: String, _ lines: [(Account, Int64)], date: Date = Date(), post: Bool = true) throws -> Expense {
        try books.createExpense(ExpenseInput(date: date, payee: payee, paymentAccountID: try checking().id,
                                             lines: lines.map { .init(amount: $0.1, accountID: $0.0.id) }), post: post)
    }

    @Test("Solo cambian las líneas de la categoría actual; contabilizados con reversión, anulados y ajenos se saltan")
    func reclassifies() throws {
        let accounts = try expenseAccounts()
        let (a, b, c) = (accounts[0], accounts[1], accounts[2])
        let one = try expense("Uno", [(a, 10_000)])
        let split = try expense("Dividido", [(a, 5_000), (b, 3_000)])
        let other = try expense("Otro", [(b, 2_000)])
        let draft = try expense("Sin asiento", [(a, 1_000)], post: false)
        let voided = try expense("Anulado", [(a, 500)])
        try books.void(voided)

        let result = try books.reclassifyExpenses([one, split, other, draft, voided], from: a.id, to: c.id)
        #expect(result.changed == 3 && result.failures.isEmpty)
        #expect(one.sortedLines.map(\.accountID) == [c.id])
        #expect(split.sortedLines.map(\.accountID) == [c.id, b.id])
        #expect(other.sortedLines.map(\.accountID) == [b.id])
        #expect(draft.sortedLines.map(\.accountID) == [c.id] && !draft.isPosted)
        #expect(voided.sortedLines.map(\.accountID) == [a.id])

        // Los saldos se movieron (el gasto sin asiento no cuenta) y el original quedó revertido.
        #expect(books.postedBalance(of: a) == 0)
        #expect(books.postedBalance(of: c) == 15_000)
        #expect(books.postedBalance(of: b) == 5_000)
        #expect(try books.entries(ofExpense: one).count == 3)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
    }

    @Test("Un gasto de un periodo cerrado no se cambia y no frena a los demás")
    func closedPeriod() throws {
        let accounts = try expenseAccounts()
        let (a, c) = (accounts[0], accounts[2])
        let old = try expense("Viejo", [(a, 4_000)], date: Date().addingTimeInterval(-40 * 86_400))
        let recent = try expense("Nuevo", [(a, 6_000)])
        try books.closeBooks(through: Date().addingTimeInterval(-30 * 86_400))

        let result = try books.reclassifyExpenses([old, recent], from: a.id, to: c.id)
        #expect(result.changed == 1)
        #expect(result.failures.map(\.expenseID) == [old.id])
        #expect(old.sortedLines.map(\.accountID) == [a.id] && recent.sortedLines.map(\.accountID) == [c.id])
    }

    @Test("La categoría nueva tiene que ser otra")
    func sameAccount() throws {
        let a = try #require(try expenseAccounts().first)
        #expect(throws: BookkeepingError.self) { try books.reclassifyExpenses([], from: a.id, to: a.id) }
    }
}
