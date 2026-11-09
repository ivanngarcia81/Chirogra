import ChirograCore
import ChirograData
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ChirograUI

/// Lógica de las pantallas de banca (1.2): sugerencias de la bandeja, aceptar, cuentas para categorizar, texto de la
/// regla, lectura del CSV con filas ilegibles, mensajes de error y el aviso de lo conciliado.
@MainActor
@Suite("Pantallas de banca")
struct BankingScreenTests {
    let container = SampleData.makeContainer()
    var context: ModelContext { container.mainContext }
    var books: Bookkeeper { Bookkeeper(context: context) }

    func inbox() throws -> BankInboxContext {
        BankInboxContext(books: books, accounts: try books.accounts(), invoices: try context.fetch(FetchDescriptor<Invoice>()),
                         bills: try context.fetch(FetchDescriptor<Bill>()))
    }

    func account(_ code: String) throws -> Account { try #require(try books.accounts().first { $0.code == code }) }

    @Test("Texto de la regla: sin números, referencias ni palabras de relleno")
    func ruleText() {
        #expect(BankRuleDraft.matchText(from: "POS 8812 FERRET LA LLAVE") == "FERRET LA LLAVE")
        #expect(BankRuleDraft.matchText(from: "UBER *TRIP HELP.UBER.COM") == "UBER")
        #expect(BankRuleDraft.matchText(from: "THE HOME DEPOT #4410") == "HOME DEPOT")
        #expect(BankRuleDraft.matchText(from: "SHELL OIL 57442") == "SHELL OIL")
        #expect(BankRuleDraft.matchText(from: "DEPOSITO CAFE AURORA LLC") == "CAFE AURORA LLC")
        #expect(BankRuleDraft.matchText(from: "12345") == "12345")
    }

    @Test("La bandeja de ejemplo: Shell con la categoría de su regla, Uber con su gasto ya registrado; aceptar registra")
    func suggestionsAndAccept() throws {
        let context = try inbox()
        let pending = try books.bankInbox()
        let shell = try #require(pending.first { $0.details.hasPrefix("SHELL") })
        let uber = try #require(pending.first { $0.details.hasPrefix("UBER") })
        guard case .category(let category, let fromRule) = context.suggestion(for: shell) else {
            Issue.record("Shell debería traer la categoría de la regla"); return
        }
        #expect(category.code == "6050" && fromRule)
        #expect(context.suggestion(for: shell).kind == .rule)
        guard case .match(let candidate) = context.suggestion(for: uber) else {
            Issue.record("Uber debería coincidir con el gasto registrado"); return
        }
        #expect(candidate.entry.source == .expense)

        let result = BankReview.acceptAll(pending, context: context)
        #expect(result.accepted == 2 && result.error == nil)
        #expect(shell.status == .categorized)
        #expect(uber.status == .matched)
    }

    @Test("Una entrada por el saldo exacto de una factura abierta propone su cobro")
    func invoiceSuggestion() throws {
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first { $0.isOpen && $0.balanceDue > 0 })
        let checking = try account("1010")
        let imported = try books.importStatementLines([
            BankStatementLine(date: .now, amount: invoice.balanceDue, details: "DEPOSIT \(invoice.customer?.name ?? "")", externalID: "fitid:QA-1"),
        ], source: .ofx, into: checking, applyRules: false).imported
        let transaction = try #require(imported.first)
        let suggestion = try inbox().suggestion(for: transaction)
        guard case .invoice(let proposed) = suggestion else { Issue.record("Esperaba el cobro de \(invoice.number)"); return }
        #expect(proposed.id == invoice.id)
        try BankReview.accept(suggestion, for: transaction, books: books)
        #expect(transaction.status == .categorized)
        #expect(invoice.balanceDue == 0)
    }

    @Test("Ya registrado: el emparejamiento va antes que la regla")
    func matchFirst() throws {
        let card = try account("2100")
        let gas = try account("6050")
        try books.post(JournalEntryDraft(date: .now, memo: "Gasolina a mano", source: .manual,
                                         lines: [.debit(gas.id, 2_500), .credit(card.id, 2_500)]))
        let transaction = try #require(try books.importStatementLines([
            BankStatementLine(date: .now, amount: -2_500, details: "SHELL OIL 9", externalID: "fitid:QA-2"),
        ], source: .ofx, into: card).imported.first)
        guard case .match(let candidate) = try inbox().suggestion(for: transaction) else { Issue.record("Esperaba coincidencia"); return }
        #expect(candidate.entry.memo == "Gasolina a mano")
    }

    @Test("Cuentas para categorizar: sin la propia ni las por cobrar; las entradas ofrecen ingresos")
    func categoryGroups() throws {
        let accounts = try books.accounts()
        let checking = try account("1010")
        let outflow = BankCategoryOptions.groups(for: -100, bankAccountID: checking.id, accounts: accounts)
        let all = outflow.flatMap(\.accounts)
        #expect(!all.contains { $0.id == checking.id })
        #expect(!all.contains { $0.subtype == .accountsReceivable || $0.subtype == .accountsPayable || $0.subtype == .salesTaxPayable })
        #expect(all.contains { $0.code == "6050" })
        #expect(all.contains { $0.code == "1020" })   // transferencia al ahorro
        let inflow = BankCategoryOptions.groups(for: 100, bankAccountID: checking.id, accounts: accounts)
        #expect(inflow.first?.accounts.allSatisfy { $0.type == .income } == true)
    }

    @Test("Siguiente por revisar: el de después o, al final, el primero que quede")
    func nextPending() throws {
        let pending = try books.bankInbox()
        #expect(pending.count == 2)
        #expect(BankReview.next(after: pending[0], in: pending)?.id == pending[1].id)
        #expect(BankReview.next(after: pending[1], in: pending)?.id == pending[0].id)
        #expect(BankReview.next(after: nil, in: pending)?.id == pending[0].id)
    }

    @Test("CSV: se saltan las filas ilegibles y se dicen sus números; las comillas sobreviven")
    func lenientCSV() throws {
        let text = "Date,Description,Amount\n10/01/2026,\"UBER, TRIP\",-18.40\n2026-10-02,MAL,-1.00\n10/03/2026,DEPOSIT,1800.00\n10/04/2026,OTRA,abc\n"
        let settings = try #require(CSVImportSettings.suggested(for: text))
        #expect(throws: BankStatementError.unreadableRow(3)) {
            _ = try BankCSVImport.parse(text, settings: settings, skippingUnreadable: false)
        }
        let result = try BankCSVImport.parse(text, settings: settings, skippingUnreadable: true)
        #expect(result.skipped == [3, 5])
        #expect(result.lines.map(\.amount) == [-1_840, 180_000])
        #expect(result.lines.first?.details == "UBER, TRIP")
        #expect(BankCSVImport.serialize([["a,b", "c\"d", "e"]], delimiter: ",") == "\"a,b\",\"c\"\"d\",e")
    }

    @Test("CSV: el perfil guardado se usa si encaja con el archivo; si no, la propuesta por la cabecera")
    func initialSettings() throws {
        let text = "Posted Date,Description,Debit,Credit\n10/01/2026,UBER,18.40,\n"
        let profile = CSVImportSettings(mapping: CSVColumnMapping(date: 0, details: 1, amount: 7))
        let fromHeader = BankCSVImport.initialSettings(for: text, profile: profile)
        #expect(fromHeader.mapping.amount == nil && fromHeader.mapping.debit == 2 && fromHeader.mapping.credit == 3)
        let fitting = CSVImportSettings(mapping: CSVColumnMapping(date: 0, details: 1, debit: 2, credit: 3), dateFormat: "M/d/yyyy")
        #expect(BankCSVImport.initialSettings(for: text, profile: fitting) == fitting)
        #expect(BankCSVImport.columnNames(CSVBankSource.rows(text), hasHeaderRow: false).first == String(localized: "Columna 1"))
    }

    @Test("Los errores del extracto tienen texto propio")
    func errorMessages() {
        for error in [BankStatementError.empty, .unreadableRow(4), .missingColumn("amount"), .notOFX] {
            let message = BankImportText.message(for: error)
            #expect(!message.isEmpty && !message.contains("BankStatementError"))
        }
        #expect(BankImportText.message(for: BankStatementError.unreadableRow(4)).contains("4"))
    }

    @Test("Revertir algo conciliado pide confirmación y, confirmado, se puede")
    func reconciledChange() throws {
        let checking = try account("1010")
        let reconciliation = try books.startReconciliation(for: checking, statementDate: .now, endingBalance: 0)
        let lines = try books.reconciliationLines(reconciliation)
        try books.setCleared(lines, true, in: reconciliation)
        try books.updateReconciliation(reconciliation, endingBalance: try books.summary(of: reconciliation).clearedBalance)
        try books.completeReconciliation(reconciliation)
        let entry = try #require(lines.compactMap(\.entry).first { $0.source == .opening })
        var caught: Error?
        do { try books.reverse(entry) } catch { caught = error }
        let error = try #require(caught)
        #expect(ReconciledChange.matches(error))
        let retry = try #require(ReconciledChange.retry(for: error) { try $0.reverse(entry) })
        try retry.perform(books.allowingReconciledChanges())
        #expect(entry.isReversed)
        #expect(ReconciledChange.retry(for: BookkeepingError.unknownAccount) { _ in } == nil)
    }

    func render<V: View>(_ view: V) -> Bool {
        ImageRenderer(content: view.environment(\.macReportInspectorEnabled, false).modelContainer(container)
            .frame(width: 390, height: 844)).nsImage != nil
    }

    // `BankingView` no: ya antes de la 1.2 `ImageRenderer` se detenía con ella («no current update to enqueue action»).
    @Test func rulesScreen() { #expect(render(NavigationStack { BankRulesView() })) }
    @Test func ruleEditor() { #expect(render(NavigationStack { BankRuleEditorView() })) }
    @Test func importScreen() { #expect(render(NavigationStack { BankImportView() })) }
    @Test func inboxScreen() { #expect(render(NavigationStack { BankInboxScreen() })) }
    /// La conciliación no se dibuja aquí: `ImageRenderer` del Mac se detiene con su `DatePicker`. Se prueba lo que pinta.
    @Test("Sesión de conciliación: las emparejadas con el banco se proponen y la diferencia baja a 0 al marcar todo")
    func reconcileSnapshot() throws {
        let checking = try account("1010")
        let reconciliation = try books.startReconciliation(for: checking, statementDate: .now, endingBalance: 0)
        let empty = try #require(ReconciliationSnapshot(reconciliation, books: books))
        #expect(empty.summary.clearedCount == 0)
        #expect(empty.suggested.count == 2)   // el depósito de Café Aurora y la renta, emparejados en los datos de ejemplo
        #expect(empty.items.allSatisfy { !$0.isCleared })
        try books.setCleared(Array(empty.lines.values), true, in: reconciliation)
        let total = try books.summary(of: reconciliation).clearedBalance
        try books.updateReconciliation(reconciliation, endingBalance: total)
        let full = try #require(ReconciliationSnapshot(reconciliation, books: books))
        #expect(full.summary.isBalanced)
        #expect(full.items.allSatisfy { $0.isCleared })
        #expect(full.clearedText == String(localized: "\(full.items.count) de \(full.items.count)"))
        #expect(ReconciliationText.status(of: checking, reconciliations: [reconciliation]).color == Palette.warning)
    }

    @Test func reviewForm() throws {
        let transaction = try #require(try books.bankInbox().first)
        #expect(render(NavigationStack { BankReviewForm(transaction: transaction, position: "1 de 2") { _ in } }))
    }
}
