import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// QA Hudson (12-nov), H05: cambiar solo la categoría de un gasto conciliado no debe romper la conciliación ni dejar
/// partidas que se anulan para el siguiente extracto. Si cambia el dinero (importe, fecha, cuenta), sí se avisa.
@MainActor
@Suite("Reclasificar un gasto conciliado sin tocar el banco")
struct ReclassifyReconciledTests {
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

    func balance(_ code: String) throws -> Int64 {
        try books.trialBalance(asOf: day(1)).rows.first { $0.account.code == code }.map { $0.debit - $0.credit } ?? 0
    }

    /// Gasto de $240 en 6500 pagado desde 1010, emparejado con su línea del extracto y conciliado.
    func reconciledExpense() throws -> (Expense, BankTransaction, Reconciliation) {
        let checking = try account("1010")
        try books.recordOpeningBalances(bank: 500_000, on: day(-40))
        let expense = try books.createExpense(ExpenseInput(date: day(-10), payee: "Papel Norte", paymentAccountID: checking.id,
                                                           lines: [.init(amount: 24_000, accountID: try account("6500").id)]))
        try books.importStatementLines([BankStatementLine(date: day(-10), amount: -24_000, details: "PAPEL NORTE", externalID: "p1")],
                                       source: .ofx, into: checking)
        let transaction = try #require(try books.bankInbox().first)
        try books.match(transaction, to: try #require(try books.matchCandidates(for: transaction).first?.line))
        let session = try books.startReconciliation(for: checking, statementDate: day(-5), endingBalance: 476_000)
        try books.setCleared(try books.reconciliationLines(session), true, in: session)
        #expect(try books.summary(of: session).isBalanced)
        try books.completeReconciliation(session)
        return (expense, transaction, session)
    }

    @Test("Solo la categoría: sin aviso, la conciliación sigue cuadrando y el extracto sigue emparejado")
    func categoryOnly() throws {
        let (expense, transaction, session) = try reconciledExpense()
        let originalID = try #require(expense.journalEntryID)
        var input = ExpenseInput(expense)
        input.lines[0].accountID = try account("6350").id

        let replacement = try #require(try books.updateExpense(expense, with: input))

        #expect(try balance("6500") == 0)
        #expect(try balance("6350") == 24_000)
        #expect(try balance("1010") == 476_000)
        #expect(try books.summary(of: session).isBalanced)
        #expect(try books.hasReconciledLines(replacement))
        #expect(transaction.matchedEntryID == replacement.id)
        #expect(replacement.sortedLines.contains { $0.id == transaction.matchedLineID })
        // El siguiente extracto no trae la pareja original + reversión por marcar.
        let next = try books.startReconciliation(for: try account("1010"), statementDate: day(0), endingBalance: 476_000)
        #expect(try books.reconciliationLines(next).isEmpty)
        #expect(try books.summary(of: next).isBalanced)
        // Sin «Asiento conciliado cambiado» en la bitácora: no se cambió nada conciliado.
        #expect(!(try container.mainContext.fetch(FetchDescriptor<AuditEvent>()).contains { $0.action == "changeReconciled" }))
        #expect(try books.entry(id: originalID)?.isReversed == true)
    }

    @Test("Varias líneas y otro proveedor, mismo total: tampoco toca el banco")
    func splitSameTotal() throws {
        let (expense, _, session) = try reconciledExpense()
        var input = ExpenseInput(expense)
        input.lines = [.init(details: "Papel", amount: 14_000, accountID: try account("6500").id),
                       .init(details: "Licencia", amount: 10_000, accountID: try account("6350").id)]
        #expect(try books.updateExpense(expense, with: input) != nil)
        #expect(try balance("6500") == 14_000 && balance("6350") == 10_000)
        #expect(try books.summary(of: session).isBalanced)
    }

    @Test("Si cambia el dinero, se sigue pidiendo confirmación")
    func moneyChangedStillAsks() throws {
        let (expense, _, _) = try reconciledExpense()
        var amount = ExpenseInput(expense)
        amount.lines[0].amount = 25_000
        #expect(throws: BookkeepingError.reconciledLines) { try books.updateExpense(expense, with: amount) }
        var date = ExpenseInput(expense)
        date.date = day(-9)
        #expect(throws: BookkeepingError.reconciledLines) { try books.updateExpense(expense, with: date) }
        var account = ExpenseInput(expense)
        account.paymentAccountID = try self.account("1020").id
        #expect(throws: BookkeepingError.reconciledLines) { try books.updateExpense(expense, with: account) }
        #expect(expense.total == 24_000)
    }

    @Test("La herramienta «Reclasificar gastos» ya no se salta los conciliados")
    func bulkReclassify() throws {
        let (expense, _, session) = try reconciledExpense()
        let result = try books.reclassifyExpenses([expense], from: try account("6500").id, to: try account("6350").id)
        #expect(result.failures.isEmpty)
        #expect(try balance("6350") == 24_000)
        #expect(try books.summary(of: session).isBalanced)
    }
}
