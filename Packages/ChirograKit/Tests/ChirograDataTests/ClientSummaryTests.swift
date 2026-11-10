import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Panel de clientes (docs/PANEL-CLIENTES.md): estado y pendientes de cada empresa.
@MainActor
@Suite("Panel de clientes")
struct ClientSummaryTests {
    let container: ModelContainer
    let books: Bookkeeper
    let calendar: Calendar
    /// «Hoy» de las pruebas: 10 de noviembre de 2026. El último trimestre terminado (jul–sep) vence el 20 de octubre.
    let today: Date

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        self.calendar = calendar
        today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let base = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let id = try base.setUpCompany(legalName: "Rivera Landscaping LLC", entityType: .llc, state: "TX",
                                       locale: Locale(identifier: "es_US")).id
        books = base.forCompany(id)
        _ = try books.setUpSalesTax(totalMillionths: 82_500)
    }

    func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func account(_ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    func post(_ date: Date, debit: String, credit: String, _ amount: Int64) throws {
        try books.post(JournalEntryDraft(date: date, lines: [.debit(try account(debit).id, amount), .credit(try account(credit).id, amount)]))
    }

    func summary() throws -> ClientSummary {
        try #require(try books.clientSummaries(asOf: today, calendar: calendar).first)
    }

    @Test("Una empresa nueva está al día, sin sales tax ni conciliación pendientes")
    func freshCompany() throws {
        let s = try summary()
        #expect(s.status == .upToDate && !s.needsAttention)
        #expect(s.name == "Rivera Landscaping LLC" && s.entityType == .llc && s.state == "TX")
        #expect(s.salesTax == nil && s.reconciliation == nil && !s.reconciliationInProgress)
        #expect(s.bankToReview == 0 && s.overdueInvoices == 0 && s.receivables == 0 && s.payables == 0)
    }

    @Test("Sales tax: el periodo terminado sin pagar es urgente; pagado, cuenta el periodo en curso")
    func salesTax() throws {
        // Cobrado en septiembre (trimestre jul–sep, vence el 20 de octubre): vencido hace 21 días.
        try post(day(9, 15), debit: "3000", credit: "2200", 84_200)
        var s = try summary()
        #expect(s.salesTax == .init(amount: 84_200, deadline: calendar.startOfDay(for: day(10, 20)), days: -21,
                                    agencyName: s.salesTax?.agencyName ?? ""))
        #expect(s.salesTaxIsUrgent && s.status == .urgent)

        // Pagado el 25 de octubre: ya no queda nada de ese periodo ni hay nada acumulado en el actual.
        try post(day(10, 25), debit: "2200", credit: "3000", 84_200)
        s = try summary()
        #expect(s.salesTax == nil && s.status == .upToDate)

        // Lo cobrado en noviembre vence el 20 de enero: se muestra, pero no es urgente.
        try post(day(11, 5), debit: "3000", credit: "2200", 30_000)
        s = try summary()
        #expect(s.salesTax?.amount == 30_000 && s.salesTax?.days == 71)
        #expect(s.salesTax?.deadline == calendar.startOfDay(for: day(1, 20, year: 2027)))
        #expect(!s.salesTaxIsUrgent && s.status == .upToDate)
    }

    @Test("Conciliación: sin conciliar cuenta desde el primer movimiento; luego, desde el último extracto")
    func reconciliation() throws {
        let checking = try account("1010")
        try post(day(8, 1), debit: "1010", credit: "3000", 500_000)
        var s = try summary()
        #expect(s.reconciliation == .init(accountID: checking.id, accountName: checking.maskedName, reconciledThrough: nil, days: 101))
        #expect(s.reconciliationIsUrgent && s.status == .urgent)

        let september = Reconciliation(accountID: checking.id, statementDate: day(9, 30), statementEndingBalance: 500_000, beginningBalance: 0)
        september.status = .completed
        books.insert(september)
        try books.context.save()
        s = try summary()
        #expect(s.reconciliation?.reconciledThrough == day(9, 30) && s.reconciliation?.days == 41)
        #expect(s.reconciliationIsLate && !s.reconciliationIsUrgent && s.status == .pending)

        let october = Reconciliation(accountID: checking.id, statementDate: day(10, 31), statementEndingBalance: 500_000, beginningBalance: 500_000)
        october.status = .completed
        books.insert(october)
        let november = Reconciliation(accountID: checking.id, statementDate: day(11, 30), statementEndingBalance: 0, beginningBalance: 500_000)
        books.insert(november)
        try books.context.save()
        s = try summary()
        #expect(s.reconciliation?.days == 10 && s.reconciliationInProgress && s.status == .upToDate)
    }

    @Test("Facturas vencidas y banco por revisar dejan la empresa pendiente; archivada va al final")
    func pendingAndArchived() throws {
        let customer = Customer(name: "Ortiz")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: Date(), dueDate: Date(),
                                                            lines: [.init(details: "Servicio", unitPrice: 312_000,
                                                                          incomeAccountID: try account("4000").id)]))
        try books.issue(invoice)
        let later = Date().addingTimeInterval(10 * 86_400)
        var s = try #require(try books.clientSummaries(asOf: later).first)
        #expect(s.overdueInvoices == 1 && s.overdueAmount == invoice.balanceDue && s.receivables == invoice.balanceDue)
        #expect(s.status == .pending && s.needsAttention)
        #expect(s.lastActivity != nil)

        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        let second = try books.forNewCompany()
        let secondCompany = try second.setUpCompany(legalName: "Delgado Catering", entityType: .llc, state: "TX",
                                                    locale: Locale(identifier: "es_US"))
        try books.archiveCompany(try #require(try books.company()))
        let list = try books.clientSummaries(asOf: later)
        #expect(list.map(\.id) == [secondCompany.id, books.companyID!])
        s = try #require(list.last)
        #expect(s.isArchived && s.status == .archived && !s.needsAttention)
    }
}
