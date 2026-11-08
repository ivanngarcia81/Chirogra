import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Banca: importar, bandeja, reglas, coincidencias y conciliación")
struct BankingTests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let id = try books.setUpCompany(legalName: "Banco LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
        _ = id
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    func line(_ offset: Int, _ amount: Int64, _ details: String, id: String = "") -> BankStatementLine {
        BankStatementLine(date: day(offset), amount: amount, details: details, externalID: id)
    }

    @Test("Importar no duplica: el mismo archivo dos veces, o solapado, solo trae lo nuevo")
    func importDeduplicates() throws {
        let checking = try account("1010")
        let first = try books.importStatementLines([line(-3, -1_840, "UBER", id: "fitid:1"), line(-2, 180_000, "DEPOSITO", id: "fitid:2")],
                                                   source: .ofx, into: checking)
        #expect(first.imported.count == 2 && first.duplicates == 0)
        let second = try books.importStatementLines([line(-2, 180_000, "DEPOSITO", id: "fitid:2"), line(-1, -525, "CAFE", id: "fitid:3")],
                                                    source: .ofx, into: checking)
        #expect(second.imported.count == 1 && second.duplicates == 1)
        #expect(try books.bankInbox(account: checking).count == 3)
        #expect(try books.bankInbox(account: checking).allSatisfy { $0.importBatchID != nil && $0.status == .toReview })
        // Sin id del banco: hash estable; el mismo CSV otra vez no entra.
        let csv = [line(-1, -999, "SIN ID"), line(-1, -999, "SIN ID")]
        #expect(try books.importStatementLines(csv, source: .csv, into: checking).imported.count == 2)
        #expect(try books.importStatementLines(csv, source: .csv, into: checking).duplicates == 2)
        // Una cuenta que no es de dinero no admite extractos.
        #expect(throws: BookkeepingError.self) { try books.importStatementLines(csv, source: .csv, into: try account("6500")) }
    }

    @Test("Importar desde una fuente (CSV) guarda el perfil de columnas para la próxima")
    func importFromSource() async throws {
        let checking = try account("1010")
        let text = "Date,Description,Amount\n10/01/2026,UBER,-18.40\n10/02/2026,DEPOSIT,1800.00\n"
        let settings = try #require(CSVImportSettings.suggested(for: text))
        let result = try await books.importTransactions(from: CSVBankSource(text: text, settings: settings), into: checking)
        #expect(result.imported.map(\.amount) == [-1_840, 180_000])
        #expect(result.imported.allSatisfy { $0.source == .csv })
        let profile = try books.saveImportProfile(settings, for: checking)
        #expect(try books.importProfiles(for: checking).map(\.id) == [profile.id])
        #expect(profile.settings == settings)
    }

    @Test("Reglas: la de mayor prioridad propone la cuenta y la automática registra el gasto")
    func rules() throws {
        let card = try account("2100")
        let travel = try account("6050")
        let software = try account("6750")
        let adobe = Vendor(name: "Adobe")
        books.insert(adobe)
        try books.saveBankRule(BankRuleInput(name: "Uber", matchText: "uber", amountSign: .outflow, targetAccountID: travel.id))
        try books.saveBankRule(BankRuleInput(matchText: "Adobe", targetAccountID: software.id, vendorID: adobe.id, payee: "Adobe",
                                             autoApply: true, priority: 10))
        // Una regla general de menor prioridad no gana.
        try books.saveBankRule(BankRuleInput(matchText: "e", targetAccountID: try account("8000").id, priority: -1))
        #expect(throws: BookkeepingError.self) { try books.saveBankRule(BankRuleInput(matchText: "  ", targetAccountID: travel.id)) }

        let result = try books.importStatementLines([line(-5, -1_840, "UBER *TRIP", id: "1"), line(-4, -5_999, "ADOBE CREATIVE CLD", id: "2"),
                                                     line(-3, 5_000, "UBER REFUND", id: "3")], source: .ofx, into: card)
        #expect(result.autoApplied.count == 1 && result.failures.isEmpty)
        let inbox = try books.bankInbox(account: card)
        let uber = try #require(inbox.first { $0.details == "UBER *TRIP" })
        #expect(uber.categoryAccountID == travel.id && uber.ruleID != nil)
        // El reembolso de Uber es una entrada: la regla de salidas no aplica; cae en la general.
        #expect(inbox.first { $0.details == "UBER REFUND" }?.categoryAccountID == (try account("8000").id))
        let adobeTx = try #require(try books.bankTransactions(account: card, status: .categorized).first)
        #expect(adobeTx.vendorID == adobe.id && adobeTx.payee == "Adobe")
        let expense = try #require(try books.fetch(Expense.self).first)
        #expect(expense.total == 5_999 && expense.vendor?.id == adobe.id && expense.paymentAccountID == card.id && expense.isPosted)
        #expect(adobeTx.createdDocumentID == expense.id && adobeTx.matchedEntryID == expense.journalEntryID)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
    }

    @Test("Coincidencias: misma cuenta, mismo importe, ±5 días, sin conciliar ni emparejar")
    func matching() throws {
        let checking = try account("1010")
        let supplies = try account("6500")
        let expense = try books.createExpense(ExpenseInput(date: day(-10), payee: "Home Depot", paymentAccountID: checking.id, method: .card,
                                                           lines: [.init(details: "Tornillos", amount: 4_500, accountID: supplies.id)]))
        _ = try books.createExpense(ExpenseInput(date: day(-30), payee: "Viejo", paymentAccountID: checking.id,
                                                 lines: [.init(amount: 4_500, accountID: supplies.id)]))
        try books.importStatementLines([line(-7, -4_500, "HOME DEPOT 123", id: "a"), line(-7, -4_500, "HOME DEPOT 124", id: "b"),
                                        line(-1, -4_501, "OTRA", id: "c")], source: .ofx, into: checking)
        let inbox = try books.bankInbox(account: checking).sorted { $0.details < $1.details }
        let candidates = try books.matchCandidates(for: inbox[0])
        #expect(candidates.map(\.entry.id) == [expense.journalEntryID])
        #expect(candidates.first?.daysApart == 3)
        #expect(try books.matchCandidates(for: inbox[2]).isEmpty)

        try books.match(inbox[0], to: try #require(candidates.first?.line))
        #expect(inbox[0].status == .matched && inbox[0].matchedEntryID == expense.journalEntryID)
        // La línea ya emparejada no se ofrece al otro movimiento.
        #expect(try books.matchCandidates(for: inbox[1]).isEmpty)
        #expect(throws: BookkeepingError.self) { try books.match(inbox[1], to: try #require(candidates.first?.line)) }
        try books.ignore(inbox[1])
        #expect(inbox[1].status == .ignored)
        #expect(throws: BookkeepingError.self) { try books.ignore(inbox[1]) }
        try books.returnToInbox(inbox[0])
        #expect(inbox[0].status == .toReview && inbox[0].matchedLineID == nil)
        #expect(try books.matchCandidates(for: inbox[0]).count == 1)
    }

    @Test("Registrar desde el movimiento: gasto, depósito, transferencia, cobro y pago a proveedor")
    func categorize() throws {
        let checking = try account("1010")
        let savings = try account("1020")
        let sales = try account("4000")
        try books.importStatementLines([line(-6, -2_000, "GAS STATION", id: "1"), line(-5, 30_000, "VENTA MOSTRADOR", id: "2"),
                                        line(-4, -50_000, "TRANSFER TO SAVINGS", id: "3"), line(-3, 120_000, "ZELLE CAFE AURORA", id: "4"),
                                        line(-2, -84_230, "MADERAS DEL NORTE", id: "5")], source: .ofx, into: checking)
        let inbox = Dictionary(uniqueKeysWithValues: try books.bankInbox().map { ($0.externalID, $0) })

        guard case .expense(let expense) = try books.categorize(try #require(inbox["1"]), as: try account("6050"), payee: "Shell") else {
            Issue.record("no es un gasto"); return
        }
        #expect(expense.total == 2_000 && expense.payee == "Shell" && expense.method == .bankTransfer)

        guard case .deposit(let deposit) = try books.categorize(try #require(inbox["2"]), as: sales) else { Issue.record("no es un depósito"); return }
        #expect(deposit.source == .bankDeposit && deposit.totalDebits == 30_000)

        guard case .transfer(let transfer) = try books.categorize(try #require(inbox["3"]), as: savings) else { Issue.record("no es una transferencia"); return }
        #expect(transfer.source == .transfer)
        #expect(ReportBuilder.balance(of: savings.ledgerAccount, lines: try books.ledgerLines()) == 50_000)

        // Cobro de una factura emitida.
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: day(-20), dueDate: day(-5),
                                                            lines: [.init(details: "Diseño", unitPrice: 200_000, incomeAccountID: sales.id)]))
        try books.issue(invoice)
        let payment = try books.recordPayment(from: try #require(inbox["4"]), for: invoice)
        #expect(payment.amount == 120_000 && invoice.status == .partiallyPaid && invoice.balanceDue == 80_000)
        #expect(inbox["4"]?.status == .categorized && inbox["4"]?.createdDocumentID == payment.id && inbox["4"]?.customerID == customer.id)

        // Pago de una factura de proveedor.
        let vendor = Vendor(name: "Maderas del Norte")
        books.insert(vendor)
        let bill = Bill(vendor: vendor, vendorNumber: "B-221", billDate: day(-12))
        books.insert(bill)
        let billLine = BillLine(details: "Triplay", amount: 84_230, accountID: try account("5000").id)
        billLine.bill = bill
        books.insert(billLine)
        try books.record(bill)
        let billPayment = try books.payBill(from: try #require(inbox["5"]), bill: bill)
        #expect(billPayment.amount == 84_230 && bill.status == .paid)

        // Ya revisados: no se registran dos veces; una entrada no es un pago y viceversa.
        #expect(throws: BookkeepingError.self) { try books.categorize(try #require(inbox["1"]), as: try account("6050")) }
        #expect(try books.bankInbox().isEmpty)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
        #expect(try books.bankTransactions(status: .categorized).allSatisfy { $0.matchedLineID != nil && $0.matchedEntryID != nil })
    }

    @Test("Una regla automática que no puede registrar (periodo cerrado) deja el movimiento por revisar")
    func automaticRuleFailure() throws {
        let checking = try account("1010")
        try books.saveBankRule(BankRuleInput(matchText: "renta", targetAccountID: try account("6400").id, autoApply: true))
        try books.closeBooks(through: day(-10))
        let result = try books.importStatementLines([line(-15, -120_000, "RENTA OCTUBRE", id: "r")], source: .ofx, into: checking)
        #expect(result.autoApplied.isEmpty && result.failures.count == 1)
        let pending = try #require(try books.bankInbox().first)
        #expect(pending.categoryAccountID == (try account("6400").id) && pending.status == .toReview)
        #expect(try books.fetch(Expense.self).isEmpty)
    }

    @Test("Conciliación: marcar hasta diferencia 0, terminar, y avisar al cambiar lo conciliado")
    func reconciliation() throws {
        let checking = try account("1010")
        let supplies = try account("6500")
        try books.recordOpeningBalances(bank: 500_000, on: day(-40))
        let rent = try books.createExpense(ExpenseInput(date: day(-20), payee: "Renta", paymentAccountID: checking.id,
                                                        lines: [.init(amount: 120_000, accountID: try account("6400").id)]))
        let tools = try books.createExpense(ExpenseInput(date: day(-10), payee: "Herramientas", paymentAccountID: checking.id,
                                                         lines: [.init(amount: 4_500, accountID: supplies.id)]))
        _ = try books.createExpense(ExpenseInput(date: day(-1), payee: "Después del extracto", paymentAccountID: checking.id,
                                                 lines: [.init(amount: 999, accountID: supplies.id)]))

        let session = try books.startReconciliation(for: checking, statementDate: day(-5), endingBalance: 375_500)
        #expect(session.beginningBalance == 0)
        #expect(throws: BookkeepingError.self) { try books.startReconciliation(for: checking, statementDate: day(-4), endingBalance: 0) }
        let lines = try books.reconciliationLines(session)
        #expect(lines.count == 3)   // apertura, renta y herramientas (la de después del extracto no)
        try books.setCleared(Array(lines.prefix(2)), true, in: session)
        var summary = try books.summary(of: session)
        #expect(summary.clearedIncreases == 500_000 && summary.clearedDecreases == 120_000 && summary.difference == -4_500)
        #expect(throws: BookkeepingError.self) { try books.completeReconciliation(session) }
        try books.setCleared([lines[2]], true, in: session)
        summary = try books.summary(of: session)
        #expect(summary.isBalanced && summary.clearedCount == 3)
        try books.completeReconciliation(session)
        #expect(session.isCompleted)

        // Lo conciliado no se cambia sin confirmar.
        let toolsEntry = try #require(try books.entry(id: tools.journalEntryID))
        #expect(try books.hasReconciledLines(toolsEntry))
        #expect(throws: BookkeepingError.reconciledLines) { try books.void(tools) }
        var input = ExpenseInput(rent)
        input.lines[0].amount = 130_000
        #expect(throws: BookkeepingError.reconciledLines) { try books.updateExpense(rent, with: input) }
        #expect(rent.total == 120_000)
        try books.allowingReconciledChanges().void(tools)
        #expect(tools.isVoid)
        #expect(try books.summary(of: session).isBalanced)   // la conciliación terminada sigue cuadrando

        // La siguiente empieza donde terminó esta; solo se reabre la última.
        let next = try books.startReconciliation(for: checking, statementDate: day(0), endingBalance: 0)
        #expect(next.beginningBalance == 375_500)
        #expect(try books.reconciliationLines(next).allSatisfy { $0.reconciliationID == nil })
        #expect(throws: BookkeepingError.self) { try books.reopenReconciliation(session) }
        try books.cancelReconciliation(next)
        try books.reopenReconciliation(session)
        #expect(!session.isCompleted)
        #expect(try !books.hasReconciledLines(try #require(try books.entry(id: rent.journalEntryID))))
    }

    @Test("Las líneas emparejadas con el banco se proponen como marcadas")
    func suggestedCleared() throws {
        let checking = try account("1010")
        let expense = try books.createExpense(ExpenseInput(date: day(-10), payee: "Home Depot", paymentAccountID: checking.id,
                                                           lines: [.init(amount: 4_500, accountID: try account("6500").id)]))
        try books.importStatementLines([line(-9, -4_500, "HOME DEPOT", id: "x")], source: .ofx, into: checking)
        let transaction = try #require(try books.bankInbox().first)
        try books.match(transaction, to: try #require(try books.matchCandidates(for: transaction).first?.line))
        let session = try books.startReconciliation(for: checking, statementDate: day(0), endingBalance: -4_500)
        let suggested = try books.suggestedClearedLines(session)
        #expect(suggested.map { $0.entry?.id } == [expense.journalEntryID])
    }

    @Test("Los datos de ejemplo traen banco por revisar, emparejados, una regla y un presupuesto")
    func sampleBanking() throws {
        let sample = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(sample.mainContext)
        let books = Bookkeeper(context: sample.mainContext)
        #expect(try books.bankTransactions(status: .matched).count == 2)
        let inbox = try books.bankInbox()
        #expect(inbox.count == 2)
        let shell = try #require(inbox.first { $0.details.hasPrefix("SHELL") })
        #expect(try books.account(id: shell.categoryAccountID)?.code == "6050")
        #expect(try books.matchCandidates(for: try #require(inbox.first { $0.details.hasPrefix("UBER") })).count == 1)
        #expect(try books.budgets().first?.total == 9_000_000 + 1_440_000 + 240_000)
    }
}
