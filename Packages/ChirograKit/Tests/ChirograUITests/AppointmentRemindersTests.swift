import ChirograCore
import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Avisos de las citas (1.4): cuáles se programan, cuándo y con qué texto.
@MainActor
@Suite("Avisos de las citas")
struct AppointmentRemindersTests {
    let container: ModelContainer
    let books: Bookkeeper
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 8))!

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        try books.setUpCompany(legalName: "Avisos LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func at(_ day: Int, _ hour: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }

    func planned() throws -> [AppointmentReminders.Planned] {
        let range = DateInterval(start: now, end: Calendar.current.date(byAdding: .day, value: 14, to: now)!)
        let names = Dictionary(try books.fetch(Customer.self).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return AppointmentReminders.plan(try books.appointments(in: range), customers: names, now: now)
    }

    @Test("Un aviso por cita programada, a su hora menos los minutos; el título es el cliente")
    func basic() throws {
        let customer = Customer(name: "Hotel Mirador")
        books.insert(customer)
        try books.createAppointment(AppointmentDraft(title: "Instalación", customerID: customer.id, start: at(25, 11), location: "Recepción",
                                                     reminderMinutes: 30))
        let items = try planned()
        #expect(items.count == 1)
        #expect(items.first?.fireDate == at(25, 11).addingTimeInterval(-1_800))
        #expect(items.first?.title == "Hotel Mirador")
        #expect(items.first?.body.contains("Instalación") == true && items.first?.body.contains("Recepción") == true)
    }

    @Test("Sin aviso, ya pasado, hecha o cancelada: no se programa")
    func skipped() throws {
        try books.createAppointment(AppointmentDraft(title: "Sin aviso", start: at(25, 15), reminderMinutes: AppointmentReminder.none))
        try books.createAppointment(AppointmentDraft(title: "Ya pasó el aviso", start: at(25, 8), reminderMinutes: 30))
        let done = try books.createAppointment(AppointmentDraft(title: "Hecha", start: at(26, 9)))
        try books.setStatus(.done, of: try #require(try books.appointment(for: Bookkeeper.key(of: done))))
        #expect(try planned().isEmpty)
    }

    @Test("Una serie semanal da un aviso por repetición dentro de los 14 días, con identificadores distintos")
    func series() throws {
        try books.createAppointment(AppointmentDraft(title: "Revisión", start: at(26, 10), recurrence: .weekly))
        let items = try planned()
        #expect(items.count == 2)
        #expect(Set(items.map(\.identifier)).count == 2)
        #expect(items.allSatisfy { $0.identifier.hasPrefix(AppointmentReminders.identifierPrefix) })
    }
}
