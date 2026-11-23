import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Anular un cobro registrado por error (build 59; Eric, Beta Family: «un cobro de más no se puede borrar»).
@MainActor
@Suite("Anular un cobro")
struct VoidPaymentTests {
    let container: ModelContainer
    let books: Bookkeeper
    let today = Calendar.current.startOfDay(for: Date())

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Cobros LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    func balance(_ code: String, _ lines: [LedgerLine]) throws -> Int64 {
        ReportBuilder.balance(of: try account(code).ledgerAccount, lines: lines)
    }

    func issue(amount: Int64, on date: Date) throws -> Invoice {
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: date, dueDate: date,
                                                            lines: [.init(details: "Servicio", unitPrice: amount, incomeAccountID: try account("4000").id)]))
        try books.issue(invoice)
        return invoice
    }

    @Test("Revierte el asiento en su fecha, la factura vuelve a quedar pendiente y todo cuadra")
    func voidsAndReopensInvoice() throws {
        let checking = try account("1010")
        let invoice = try issue(amount: 100_000, on: day(-20))
        let first = try books.recordPayment(for: invoice, amount: 40_000, date: day(-10), depositAccount: checking)
        let second = try books.recordPayment(for: invoice, amount: 60_000, date: day(-5), depositAccount: checking)
        #expect(invoice.status == .paid && invoice.balanceDue == 0)

        try books.voidPayment(second)
        #expect(books.isVoided(second) && !books.isVoided(first))
        #expect(invoice.status == .partiallyPaid && invoice.amountPaid == 40_000 && invoice.balanceDue == 60_000)
        let original = try #require(try books.entry(id: second.journalEntryID))
        let reversal = try #require(try books.entry(id: original.reversedByEntryID))
        #expect(reversal.date == original.date && reversal.sourceDocumentID == second.id)
        #expect(try balance("1010", try books.ledgerLines()) == 40_000)
        #expect(try balance("1100", try books.ledgerLines()) == 60_000)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
        // Dos veces no.
        #expect(throws: BookkeepingError.self) { try books.voidPayment(second) }

        try books.voidPayment(first)
        #expect(invoice.status == .sent && invoice.amountPaid == 0 && invoice.balanceDue == 100_000)
        // Sin cobros vivos la factura vuelve a poder editarse y anularse.
        #expect(books.canEditIssued(invoice))
        try books.void(invoice)
        #expect(invoice.status == .void)
        // En la bitácora, con la factura.
        let events = try context.fetch(FetchDescriptor<AuditEvent>()).filter { $0.action == "voidPayment" }
        #expect(events.count == 2 && events.allSatisfy { $0.entityID == invoice.id })
    }

    @Test("Base caja: el ingreso del cobro anulado desaparece, también si se anula otro mes")
    func cashBasis() throws {
        let checking = try account("1010")
        let invoice = try issue(amount: 50_000, on: day(-90))
        let payment = try books.recordPayment(for: invoice, amount: 50_000, date: day(-60), depositAccount: checking)
        #expect(try balance("4000", try books.cashBasisLedgerLines()) == 50_000)
        // Con una fecha distinta (p. ej. el primer día abierto tras un cierre): la reversión también se reparte.
        try books.voidPayment(payment, on: day(-1))
        let cash = try books.cashBasisLedgerLines()
        #expect(try balance("4000", cash) == 0 && balance("1100", cash) == 0 && balance("1010", cash) == 0)
        #expect(try books.incomeStatement(from: day(-70), to: day(-50), basis: .cash).netIncome == 50_000)
        #expect(try books.incomeStatement(from: day(-3), to: today, basis: .cash).netIncome == -50_000)
        #expect(try books.trialBalance(asOf: .distantFuture, basis: .cash).isBalanced)
    }

    @Test("El movimiento del banco que lo registró (o se emparejó con él) vuelve a «Por revisar»")
    func returnsBankTransaction() throws {
        let checking = try account("1010")
        try books.importStatementLines([BankStatementLine(date: day(-3), amount: 30_000, details: "ZELLE CAFE AURORA", externalID: "1"),
                                        BankStatementLine(date: day(-2), amount: 20_000, details: "DEPOSITO", externalID: "2")],
                                       source: .ofx, into: checking)
        let inbox = Dictionary(uniqueKeysWithValues: try books.bankInbox().map { ($0.externalID, $0) })
        let zelle = try #require(inbox["1"])
        let deposit = try #require(inbox["2"])
        let fromBank = try books.recordPayment(from: zelle, for: try issue(amount: 30_000, on: day(-10)))
        try books.voidPayment(fromBank)
        #expect(zelle.status == .toReview && zelle.createdDocumentID == nil && zelle.matchedEntryID == nil)

        // Cobro registrado a mano y emparejado después con el movimiento.
        let manual = try books.recordPayment(for: try issue(amount: 20_000, on: day(-10)), amount: 20_000, date: day(-2), depositAccount: checking)
        let candidate = try #require(try books.matchCandidates(for: deposit).first)
        try books.match(deposit, to: candidate.line)
        try books.voidPayment(manual)
        #expect(deposit.status == .toReview && deposit.matchedEntryID == nil)
        // El cobro anulado ya no se ofrece para emparejar.
        #expect(try books.matchCandidates(for: deposit).isEmpty)
    }

    @Test("Antigüedad a una fecha pasada: el cobro anulado cuenta solo mientras estuvo vigente")
    func aging() throws {
        let checking = try account("1010")
        let kept = try issue(amount: 100_000, on: day(-40))
        let payment = try books.recordPayment(for: kept, amount: 100_000, date: day(-20), depositAccount: checking)
        // Anulado más tarde (primer día abierto, p. ej.): entre el cobro y la anulación la factura estaba pagada.
        try books.voidPayment(payment, on: day(-5))
        func owed(_ offset: Int) throws -> Int64 { try books.receivablesAging(asOf: day(offset)).total }
        #expect(try owed(-30) == 100_000)
        #expect(try owed(-10) == 0)
        #expect(try owed(0) == 100_000)
        // Anulado en su fecha: no llegó a estar vigente al final de ningún día.
        let other = try issue(amount: 50_000, on: day(-40))
        let same = try books.recordPayment(for: other, amount: 50_000, date: day(-20), depositAccount: checking)
        try books.voidPayment(same)
        #expect(try owed(-10) == 50_000)
    }

    @Test("En un periodo cerrado pide desbloquear o la fecha del primer día abierto")
    func closedPeriod() throws {
        let checking = try account("1010")
        let invoice = try issue(amount: 10_000, on: day(-40))
        let payment = try books.recordPayment(for: invoice, amount: 10_000, date: day(-35), depositAccount: checking)
        try books.closeBooks(through: day(-30))
        #expect(throws: BookkeepingError.invalidEntry(.periodLocked(lockDate: day(-30)))) { try books.voidPayment(payment) }
        #expect(invoice.status == .paid && !books.isVoided(payment))
        try books.voidPayment(payment, on: day(-29))
        #expect(invoice.status == .sent && books.isVoided(payment))
    }

    @Test("Una factura con nota de crédito no se anula, aunque su cobro se haya anulado (revisión)")
    func noVoidWithCreditNote() throws {
        let invoice = try issue(amount: 10_000, on: day(-20))
        let payment = try books.recordPayment(for: invoice, amount: 10_000, date: day(-19), depositAccount: try account("1010"))
        try books.issueCreditNote(for: invoice, amount: 2_000, isTaxable: false, reason: "Ajuste", date: day(-18))
        try books.voidPayment(payment)
        #expect(invoice.status == .sent && invoice.amountPaid == 0 && invoice.creditsApplied == 0)
        #expect(throws: BookkeepingError.self) { try books.void(invoice) }
        #expect(invoice.status == .sent)
    }
}
