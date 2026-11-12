import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// QA Hudson (12-nov), H02: lo registrado en un mes ya cerrado sale en «Cambios después del cierre» con su motivo, y
/// en el paquete del contador.
@MainActor
@Suite("Cambios después del cierre")
struct ChangesAfterCloseTests {
    let container: ModelContainer
    let books: Bookkeeper
    let calendar = Calendar.current

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        _ = try books.setUpCompany(legalName: "Hudson LLC", entityType: .llc, state: "NJ", locale: Locale(identifier: "es_US"))
    }

    func day(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day))! }
    func account(_ code: String) throws -> Account { try #require(try books.accounts().first { $0.code == code }) }
    func draft(_ date: Date, _ memo: String, _ amount: Int64) throws -> JournalEntryDraft {
        JournalEntryDraft(date: date, memo: memo, lines: [.debit(try account("6500").id, amount), .credit(try account("1010").id, amount)])
    }

    @Test("Solo lo que entró en un periodo ya cerrado, con el motivo, quién y el aparato")
    func listsOnlyPostCloseEntries() throws {
        try books.post(try draft(day(10, 10), "Antes del cierre", 1_000))
        try books.closeBooks(through: day(10, 31), calendar: calendar)
        try books.post(try draft(day(11, 5), "Noviembre, abierto", 2_000))
        try books.unlockedForClosedPeriod(password: nil, reason: "Recibo que llegó tarde").post(try draft(day(10, 15), "Papel", 3_000))

        let changes = try books.changesAfterClose(calendar: calendar)
        #expect(changes.map(\.memo) == ["Papel"])
        let change = try #require(changes.first)
        #expect(change.reason == "Recibo que llegó tarde" && change.actor == "Pruebas" && change.amount == 3_000)
        #expect(calendar.isDate(change.lockDate, inSameDayAs: day(10, 31)))
        #expect(try books.changesAfterClose(from: day(11, 1), to: day(11, 30), calendar: calendar).isEmpty)
    }

    @Test("Con la contraseña no hace falta motivo; tras reabrir, ya no cuenta como cambio después del cierre")
    func passwordAndReopen() throws {
        try books.setClosingPassword("cierre-2026")
        try books.closeBooks(through: day(10, 31), calendar: calendar)
        try books.unlockedForClosedPeriod(password: "cierre-2026").post(try draft(day(10, 20), "Con contraseña", 500))
        try books.reopenBooks(to: nil, password: "cierre-2026", calendar: calendar)
        try books.post(try draft(day(10, 21), "Con el mes reabierto", 700))

        let changes = try books.changesAfterClose(calendar: calendar)
        #expect(changes.map(\.memo) == ["Con contraseña"])
        #expect(changes.first?.reason == "")
    }

    @Test("El paquete del contador trae «Cambios después del cierre» solo si los hubo")
    func accountantPackage() throws {
        try books.closeBooks(through: day(10, 31), calendar: calendar)
        let empty = try books.accountantPackage(from: day(10, 1), to: day(10, 31), calendar: calendar)
        #expect(!empty.files.contains { $0.name.hasPrefix("Cambios después del cierre") })
        try books.unlockedForClosedPeriod(password: nil, reason: "Ajuste, el contador").post(try draft(day(10, 30), "Ajuste", 900))
        let package = try books.accountantPackage(from: day(10, 1), to: day(10, 31), calendar: calendar)
        let file = try #require(package.files.first { $0.name.hasPrefix("Cambios después del cierre") })
        #expect(file.contents.contains("\"Ajuste, el contador\"") && file.contents.contains("9.00"))
    }
}
