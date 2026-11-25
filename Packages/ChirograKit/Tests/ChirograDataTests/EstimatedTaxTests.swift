import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Apartado para impuestos estimados (1.4, esquema 6): las fechas del 1040-ES, cuánto apartar, los pagos al IRS y su
/// asiento, el ajuste y la copia de seguridad.
@MainActor
@Suite("Impuestos estimados")
struct EstimatedTaxTests {
    let container: ModelContainer
    let books: Bookkeeper
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Apartado LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func account(_ code: String) throws -> Account { try #require(try books.accounts().first { $0.code == code }) }

    /// Un ingreso cobrado al banco en `day`.
    func earn(_ amount: Int64, on day: Date) throws {
        try books.post(JournalEntryDraft(date: day, memo: "Servicio", lines: [.debit(try account("1010").id, amount),
                                                                              .credit(try account("4000").id, amount)]))
    }

    // MARK: Fechas (ChirograCore)

    @Test("Los cuatro pagos de 2026: periodos del IRS y vencimientos, el 4.º en enero del año siguiente")
    func periods2026() {
        let periods = EstimatedTaxCalendar.periods(of: 2026, calendar: calendar)
        #expect(periods.map { calendar.component(.month, from: $0.start) } == [1, 4, 6, 9])
        #expect(periods.map(\.due) == [date(2026, 4, 15, 0), date(2026, 6, 15, 0), date(2026, 9, 15, 0), date(2027, 1, 15, 0)])
        #expect(EstimatedTaxCalendar.period(containing: date(2026, 5, 31), calendar: calendar)?.number == 2)
        #expect(EstimatedTaxCalendar.period(containing: date(2026, 6, 1), calendar: calendar)?.number == 3)
    }

    @Test("Si el 15 cae en fin de semana, vence el lunes")
    func weekendDue() {
        // 15 de abril de 2028 es sábado.
        #expect(EstimatedTaxCalendar.periods(of: 2028, calendar: calendar)[0].due == date(2028, 4, 17, 0))
    }

    @Test("Del 1 al 15 de enero toca el 4.º del año anterior mientras no esté pagado")
    func focusInJanuary() {
        let unpaid = EstimatedTaxCalendar.focus(today: date(2027, 1, 10), isPaid: { _ in false }, calendar: calendar)
        #expect(unpaid?.year == 2026 && unpaid?.number == 4)
        let paid = EstimatedTaxCalendar.focus(today: date(2027, 1, 10), isPaid: { _ in true }, calendar: calendar)
        #expect(paid?.year == 2027 && paid?.number == 1)
        let late = EstimatedTaxCalendar.focus(today: date(2027, 1, 16), isPaid: { _ in false }, calendar: calendar)
        #expect(late?.year == 2027 && late?.number == 1)
    }

    @Test("Apartar es el porcentaje de la ganancia, al centavo, y nada si no hubo ganancia")
    func setAside() {
        #expect(EstimatedTaxCalendar.setAside(profit: 845_000, percent: 25) == 211_250)
        #expect(EstimatedTaxCalendar.setAside(profit: 100_001, percent: 30) == 30_000)
        #expect(EstimatedTaxCalendar.setAside(profit: -50_000, percent: 25) == 0)
    }

    // MARK: Resumen

    @Test("El 25 de noviembre: 4.º pago, ganancia de sep a hoy, 25 % y faltan 51 días")
    func summaryOnNovember25() throws {
        try earn(500_000, on: date(2026, 8, 20))   // 3.er periodo: no cuenta en el 4.º
        try earn(845_000, on: date(2026, 10, 2))
        let summary = try #require(try books.estimatedTaxSummary(today: date(2026, 11, 25), calendar: calendar))
        #expect(summary.taxYear == 2026 && summary.focus.period.number == 4)
        #expect(summary.focus.profit == 845_000 && summary.focus.toSetAside == 211_250)
        #expect(summary.daysLeft == 51)
        #expect(summary.rows[2].profit == 500_000 && summary.rows[2].toSetAside == 125_000)
        #expect(summary.percent == 25 && summary.showsCard)
    }

    @Test("Sin movimientos no hay nada que apartar")
    func emptySummary() throws {
        let summary = try #require(try books.estimatedTaxSummary(today: date(2026, 11, 25), calendar: calendar))
        #expect(summary.focus.toSetAside == 0 && summary.paidThisYear == 0)
    }

    // MARK: Pagos

    @Test("Un pago al IRS sale del banco a retiros del dueño: no toca la ganancia y cuenta como pagado")
    func recordPayment() throws {
        try earn(845_000, on: date(2026, 10, 2))
        let checking = try account("1010")
        let payment = try books.recordEstimatedTaxPayment(taxYear: 2026, period: 3, date: date(2026, 9, 14), amount: 275_000,
                                                          fromAccountID: checking.id)
        let entry = try #require(try books.entry(id: payment.journalEntryID))
        #expect(entry.source == .estimatedTax && entry.sourceDocumentID == payment.id)
        #expect(entry.sortedLines.contains { $0.account?.subtype == .ownersDraw && $0.debit == 275_000 })
        #expect(entry.sortedLines.contains { $0.account?.id == checking.id && $0.credit == 275_000 })
        let summary = try #require(try books.estimatedTaxSummary(today: date(2026, 11, 25), calendar: calendar))
        #expect(summary.rows[2].paid == 275_000 && summary.rows[2].isPaid)
        #expect(summary.focus.profit == 845_000)
        #expect(summary.paidThisYear == 275_000 && summary.setAsideThisYear == 275_000 + 211_250)
        #expect(try books.auditLog(entityID: payment.id).first?.summary.contains("1040-ES") == true)
    }

    @Test("Quitar un pago revierte su asiento")
    func deletePayment() throws {
        let checking = try account("1010")
        let payment = try books.recordEstimatedTaxPayment(taxYear: 2026, period: 4, date: date(2026, 11, 25), amount: 100_000,
                                                          fromAccountID: checking.id)
        let entry = try #require(try books.entry(id: payment.journalEntryID))
        try books.deleteEstimatedTaxPayment(payment)
        #expect(entry.isReversed)
        #expect(try books.estimatedTaxPayments().isEmpty)
    }

    @Test("Sin monto o con un pago fuera del 1 al 4 no se anota")
    func paymentValidation() throws {
        let checking = try account("1010")
        #expect(throws: BookkeepingError.self) {
            try books.recordEstimatedTaxPayment(taxYear: 2026, period: 4, date: date(2026, 11, 25), amount: 0, fromAccountID: checking.id)
        }
        #expect(throws: BookkeepingError.self) {
            try books.recordEstimatedTaxPayment(taxYear: 2026, period: 5, date: date(2026, 11, 25), amount: 100, fromAccountID: checking.id)
        }
    }

    // MARK: Ajuste y copia

    @Test("El porcentaje se guarda (entre 1 y 60) y la tarjeta se puede apagar")
    func setting() throws {
        try books.setEstimatedTax(percent: 30)
        try books.setEstimatedTax(showsCard: false)
        try books.setEstimatedTax(percent: 90)
        let setting = try #require(try books.estimatedTaxSetting())
        #expect(setting.percent == 60 && !setting.showsCard)
        #expect(try context.fetch(FetchDescriptor<EstimatedTaxSetting>()).count == 1)
        #expect(try books.auditLog(entityID: setting.id).count == 3)
    }

    @Test("La copia de seguridad lleva el ajuste y los pagos")
    func backupRoundTrip() throws {
        try books.setEstimatedTax(percent: 28)
        try books.recordEstimatedTaxPayment(taxYear: 2026, period: 3, date: date(2026, 9, 14), amount: 275_000,
                                            fromAccountID: try account("1010").id)
        let data = try BackupArchive.make(from: context, appVersion: "1.4.0")
        let other = try ChirograStore.makeContainer(inMemory: true)
        _ = try BackupArchive.restore(data, into: other.mainContext)
        #expect(try other.mainContext.fetch(FetchDescriptor<EstimatedTaxSetting>()).first?.percent == 28)
        #expect(try other.mainContext.fetch(FetchDescriptor<EstimatedTaxPayment>()).first?.amount == 275_000)
    }
}
