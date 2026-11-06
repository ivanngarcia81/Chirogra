import ChirograCore
import ChirograData
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ChirograUI

/// Plantillas del editor de asientos (build 4): cada una genera un asiento que cuadra, con las cuentas correctas, y
/// que el libro acepta.
@MainActor
@Suite("Plantillas de asiento")
struct JournalTemplateTests {
    let container: ModelContainer
    let books: Bookkeeper

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Prueba LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var accounts: [Account] { (try? books.accounts()) ?? [] }

    func account(_ code: String) throws -> Account {
        try #require(accounts.first { $0.code == code })
    }

    /// Valida y registra el asiento como lo haría el editor.
    func post(_ draft: JournalEntryDraft) throws {
        let errors = try books.validator().errors(for: draft)
        #expect(errors.isEmpty, "Errores: \(errors)")
        try books.post(draft)
    }

    func line(_ draft: JournalEntryDraft, _ account: Account) -> JournalLineDraft? {
        draft.lines.first { $0.accountID == account.id }
    }

    @Test("«Puse dinero de mi bolsillo»: débito al banco, crédito a 3000 Capital del dueño")
    func ownerContribution() throws {
        let bank = try account("1010"), equity = try account("3000")
        #expect(equity.subtype == .ownersEquity)
        let draft = try #require(JournalTemplate.ownerContribution.draft(date: .now, memo: "", amount: 50_000, money: bank.id,
                                                                         destination: nil, accounts: accounts))
        #expect(draft.isBalanced && draft.totalDebits == 50_000)
        #expect(draft.lines.count == 2)
        #expect(line(draft, bank)?.debit == 50_000)
        #expect(line(draft, equity)?.credit == 50_000)
        #expect(draft.memo == JournalTemplate.ownerContribution.defaultMemo)
        #expect(draft.source == .manual)
        try post(draft)
    }

    @Test("«Saqué dinero para mí»: débito a 3100 Retiros del dueño, crédito al banco")
    func ownerDraw() throws {
        let bank = try account("1010"), draw = try account("3100")
        #expect(draw.subtype == .ownersDraw)
        let draft = try #require(JournalTemplate.ownerDraw.draft(date: .now, memo: "Para la renta de casa", amount: 12_345,
                                                                 money: bank.id, destination: nil, accounts: accounts))
        #expect(draft.isBalanced)
        #expect(line(draft, draw)?.debit == 12_345)
        #expect(line(draft, bank)?.credit == 12_345)
        #expect(draft.memo == "Para la renta de casa")
        try post(draft)
    }

    @Test("«Pasé dinero entre mis cuentas»: débito a la de destino, crédito a la de origen")
    func transfer() throws {
        let checking = try account("1010"), savings = try account("1020")
        let draft = try #require(JournalTemplate.transfer.draft(date: .now, memo: "", amount: 30_000, money: checking.id,
                                                                destination: savings.id, accounts: accounts))
        #expect(draft.isBalanced)
        #expect(line(draft, savings)?.debit == 30_000)
        #expect(line(draft, checking)?.credit == 30_000)
        try post(draft)
        // Pagar la tarjeta desde el banco también es un traspaso.
        let card = try account("2100")
        #expect(JournalTemplate.moneyAccounts(in: accounts).contains { $0.id == card.id })
        let payCard = try #require(JournalTemplate.transfer.draft(date: .now, memo: "", amount: 5_000, money: checking.id,
                                                                  destination: card.id, accounts: accounts))
        try post(payCard)
    }

    @Test("Sin importe, sin cuenta o con la misma cuenta, no hay asiento")
    func incomplete() throws {
        let bank = try account("1010")
        #expect(JournalTemplate.ownerContribution.draft(date: .now, memo: "", amount: 0, money: bank.id, destination: nil, accounts: accounts) == nil)
        #expect(JournalTemplate.ownerDraw.draft(date: .now, memo: "", amount: 100, money: nil, destination: nil, accounts: accounts) == nil)
        #expect(JournalTemplate.transfer.draft(date: .now, memo: "", amount: 100, money: bank.id, destination: bank.id, accounts: accounts) == nil)
        #expect(JournalTemplate.transfer.draft(date: .now, memo: "", amount: 100, money: bank.id, destination: nil, accounts: accounts) == nil)
    }

    @Test("Las cuentas de dinero: bancos primero, sin «Fondos no depositados»")
    func moneyAccounts() throws {
        let money = JournalTemplate.moneyAccounts(in: accounts)
        #expect(money.first?.code == "1010")
        #expect(!money.contains { $0.subtype == .undepositedFunds })
        #expect(money.allSatisfy { $0.subtype.isMoneyAccount })
    }

    @Test("Las tres plantillas tienen sus textos; las guías y la ayuda de palabras también")
    func texts() {
        for template in JournalTemplate.allCases {
            #expect(!template.title.isEmpty && !template.defaultMemo.isEmpty && !template.moneyAccountLabel.isEmpty)
        }
        let guides = EmptyGuide.allCases
        #expect(Set(guides.map(\.title)).count == guides.count)
        for guide in guides {
            #expect(!guide.what.isEmpty && !guide.why.isEmpty && !guide.actionTitle.isEmpty)
            #expect(guide.message.contains(guide.what) && guide.message.contains(guide.why))
        }
        for jargon in Jargon.allCases { #expect(!jargon.term.isEmpty && !jargon.explanation.isEmpty) }
    }

    func render(_ view: some View) -> Bool {
        ImageRenderer(content: view.environment(\.macReportInspectorEnabled, false).modelContainer(container)
            .frame(width: 390, height: 844)).nsImage != nil
    }

    // Con la empresa vacía, las pantallas con su guía y el editor con plantilla se construyen.
    @Test func emptySales() { #expect(render(NavigationStack { SalesView() })) }
    @Test func emptyExpenses() { #expect(render(ExpenseListView())) }
    @Test func emptyReports() { #expect(render(ReportsView())) }
    @Test func emptyJournal() { #expect(render(JournalListView())) }
    @Test func templateEditor() { #expect(render(JournalEntryEditorView(template: .ownerContribution))) }
    @Test func invoiceWithoutRates() { #expect(render(InvoiceEditorView())) }
    @Test func guides() { for guide in EmptyGuide.allCases { #expect(render(EmptyStateView(guide: guide) {})) } }
}
