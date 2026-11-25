import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Agenda de la 1.4 (esquema 6): citas sueltas y que se repiten, «solo esta» o «esta y las siguientes», facturar y
/// borrar, la copia de seguridad y el borrado de la empresa.
@MainActor
@Suite("Agenda")
struct AgendaTests {
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
        try books.setUpCompany(legalName: "Agenda LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    var context: ModelContext { container.mainContext }

    /// 2026-11-<day> a las `hour`:`minute`, hora de Austin.
    func date(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func range(_ from: Date, days: Int) -> DateInterval {
        DateInterval(start: from, end: calendar.date(byAdding: .day, value: days, to: from)!)
    }

    func november() -> DateInterval { range(date(1, 0), days: 30) }

    // MARK: Repeticiones (ChirograCore)

    @Test("Una serie semanal da una cita cada 7 días dentro del rango, hasta su último día")
    func weeklyStarts() {
        let starts = AppointmentRecurrence.starts(from: date(2), rule: .weekly, lastDay: date(23, 0), in: november(), calendar: calendar)
        #expect(starts == [date(2), date(9), date(16), date(23)])
    }

    @Test("Mensual desde el día 31: cae en el último día del mes corto y vuelve al 31")
    func monthlyFromThirtyFirst() {
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 10))!
        let year = DateInterval(start: first, end: calendar.date(byAdding: .month, value: 3, to: first)!)
        let starts = AppointmentRecurrence.starts(from: first, rule: .monthly, lastDay: nil, in: year, calendar: calendar)
        let days = starts.map { calendar.component(.day, from: $0) }
        #expect(days == [31, 30, 31])
    }

    @Test("Una serie diaria de hace años no recorre cada día para llegar al rango")
    func dailyFarInThePast() {
        let first = calendar.date(from: DateComponents(year: 2016, month: 1, day: 1, hour: 8))!
        let starts = AppointmentRecurrence.starts(from: first, rule: .daily, lastDay: nil, in: range(date(10, 0), days: 3), calendar: calendar)
        #expect(starts.map { calendar.component(.day, from: $0) } == [10, 11, 12])
    }

    // MARK: Crear y leer

    @Test("Una cita suelta sale en su día, con la empresa puesta y en la bitácora")
    func createSingle() throws {
        let customer = Customer(name: "Hotel Mirador")
        books.insert(customer)
        let appointment = try books.createAppointment(AppointmentDraft(title: "Instalación de repisas", customerID: customer.id,
                                                                       start: date(25, 11, 30), durationMinutes: 90))
        #expect(appointment.companyID != nil)
        let found = try books.appointments(in: range(date(25, 0), days: 1), calendar: calendar)
        #expect(found.count == 1)
        #expect(found.first?.status == .scheduled && found.first?.end == date(25, 13, 0))
        #expect(try books.appointments(forCustomer: customer.id, in: november(), calendar: calendar).count == 1)
        #expect(try books.auditLog(entityID: appointment.id).first?.summary.contains("Hotel Mirador") == true)
    }

    @Test("Sin cliente ni título no se guarda; tampoco con duración cero")
    func validation() throws {
        #expect(throws: BookkeepingError.self) { try books.createAppointment(AppointmentDraft(title: "  ", start: date(25))) }
        #expect(throws: BookkeepingError.self) { try books.createAppointment(AppointmentDraft(title: "Visita", start: date(25), durationMinutes: 0)) }
    }

    @Test("En solo lectura no se crean citas")
    func readOnly() throws {
        Bookkeeper.isReadOnly = true
        defer { Bookkeeper.isReadOnly = false }
        #expect(throws: BookkeepingError.readOnly) { try books.createAppointment(AppointmentDraft(title: "Visita", start: date(25))) }
    }

    // MARK: Series

    func weeklySeries() throws -> Appointment {
        try books.createAppointment(AppointmentDraft(title: "Revisión de mostrador", start: date(2, 10), recurrence: .weekly))
    }

    @Test("Una serie semanal sin fin sale cada semana y solo guarda la plantilla")
    func seriesIsCalculated() throws {
        _ = try weeklySeries()
        let found = try books.appointments(in: november(), calendar: calendar)
        #expect(found.map(\.start) == [date(2, 10), date(9, 10), date(16, 10), date(23, 10), date(30, 10)])
        #expect(found.allSatisfy { $0.isCalculated && $0.isRepeating })
        #expect(try context.fetch(FetchDescriptor<Appointment>()).count == 1)
    }

    @Test("Marcar hecha una repetición guarda solo esa; las demás siguen programadas")
    func doneOnlyThis() throws {
        _ = try weeklySeries()
        let second = try #require(try books.appointments(in: november(), calendar: calendar)[1])
        try books.setStatus(.done, of: second)
        let found = try books.appointments(in: november(), calendar: calendar)
        #expect(found.count == 5)
        #expect(found.map(\.status) == [.scheduled, .done, .scheduled, .scheduled, .scheduled])
        #expect(found[1].isPendingInvoice && !found[1].isCalculated)
        #expect(try context.fetch(FetchDescriptor<Appointment>()).count == 2)
    }

    @Test("«Solo esta»: mover una repetición no cambia las demás ni la duplica")
    func moveOnlyThis() throws {
        _ = try weeklySeries()
        let third = try #require(try books.appointments(in: november(), calendar: calendar)[2])
        var draft = AppointmentDraft(title: "Revisión de mostrador", start: date(17, 15), durationMinutes: 45)
        draft.recurrence = .daily  // en «solo esta» la regla no cuenta
        try books.updateAppointment(third, with: draft, scope: .onlyThis, calendar: calendar)
        let found = try books.appointments(in: november(), calendar: calendar)
        #expect(found.map(\.start) == [date(2, 10), date(9, 10), date(17, 15), date(23, 10), date(30, 10)])
        #expect(found[2].appointment.recurrence == .none && found[2].appointment.durationMinutes == 45)
    }

    @Test("«Esta y las siguientes»: la serie de antes termina la víspera y la nueva sigue con la hora nueva")
    func changeThisAndFollowing() throws {
        let series = try weeklySeries()
        let all = try books.appointments(in: november(), calendar: calendar)
        try books.setStatus(.done, of: all[0])
        try books.setStatus(.done, of: try books.appointments(in: november(), calendar: calendar)[3])  // 23 nov, hecha
        let third = try #require(try books.appointments(in: november(), calendar: calendar)[2])  // 16 nov
        try books.updateAppointment(third, with: AppointmentDraft(title: "Revisión de mostrador", start: date(16, 14), recurrence: .weekly),
                                    scope: .thisAndFollowing, calendar: calendar)
        let found = try books.appointments(in: november(), calendar: calendar)
        // El 23 ya estaba hecho: se queda como cita suelta y la serie nueva no lo repite.
        #expect(found.map(\.start) == [date(2, 10), date(9, 10), date(16, 14), date(23, 10), date(23, 14), date(30, 14)])
        #expect(series.recurrenceEnd == date(15, 0))
        let kept = try #require(found.first { $0.start == date(23, 10) })
        #expect(kept.status == .done && !kept.isRepeating)
    }

    @Test("Cambiar la serie desde la primera cita la cambia entera, sin cortar nada")
    func changeFromFirst() throws {
        let series = try weeklySeries()
        let first = try #require(try books.appointments(in: november(), calendar: calendar).first)
        try books.updateAppointment(first, with: AppointmentDraft(title: "Revisión", start: date(3, 8), recurrence: .biweekly),
                                    scope: .thisAndFollowing, calendar: calendar)
        let found = try books.appointments(in: november(), calendar: calendar)
        #expect(found.map(\.start) == [date(3, 8), date(17, 8)])
        #expect(series.recurrenceEnd == nil)
        #expect(try context.fetch(FetchDescriptor<Appointment>()).count == 1)
    }

    @Test("Borrar solo una repetición la quita; borrar esta y las siguientes corta la serie")
    func deleteScopes() throws {
        _ = try weeklySeries()
        try books.deleteAppointment(try books.appointments(in: november(), calendar: calendar)[1], scope: .onlyThis, calendar: calendar)
        #expect(try books.appointments(in: november(), calendar: calendar).map(\.start) == [date(2, 10), date(16, 10), date(23, 10), date(30, 10)])
        try books.deleteAppointment(try books.appointments(in: november(), calendar: calendar)[2], scope: .thisAndFollowing, calendar: calendar)
        #expect(try books.appointments(in: november(), calendar: calendar).map(\.start) == [date(2, 10), date(16, 10)])
    }

    @Test("Borrar una serie desde la primera cita la quita entera, pero no las repeticiones ya hechas")
    func deleteWholeSeries() throws {
        _ = try weeklySeries()
        try books.setStatus(.done, of: try books.appointments(in: november(), calendar: calendar)[0])
        let second = try #require(try books.appointments(in: november(), calendar: calendar)[1])
        try books.setStatus(.cancelled, of: second)
        let first = try #require(try books.appointments(in: november(), calendar: calendar).first)
        // La primera ya está guardada aparte: para borrar toda la serie se usa su repetición calculada siguiente…
        // …o la propia guardada, que sigue siendo de la serie.
        try books.deleteAppointment(first, scope: .thisAndFollowing, calendar: calendar)
        let found = try books.appointments(in: november(), calendar: calendar)
        #expect(found.map(\.status) == [.done, .cancelled])
        #expect(found.allSatisfy { !$0.isRepeating })
    }

    // MARK: Facturar

    @Test("Crear factura desde una cita la enlaza y la marca hecha")
    func linkInvoice() throws {
        _ = try weeklySeries()
        let first = try #require(try books.appointments(in: november(), calendar: calendar).first)
        let invoiceID = UUID()
        try books.link(first, invoiceID: invoiceID)
        let linked = try #require(try books.appointments(in: november(), calendar: calendar).first)
        #expect(linked.status == .done && linked.appointment.invoiceID == invoiceID && !linked.isPendingInvoice)
    }

    // MARK: Copia y borrado

    @Test("La copia de seguridad lleva las citas y las devuelve")
    func backupRoundTrip() throws {
        _ = try weeklySeries()
        try books.setStatus(.done, of: try books.appointments(in: november(), calendar: calendar)[1])
        let data = try BackupArchive.make(from: context, appVersion: "1.4.0")
        let other = try ChirograStore.makeContainer(inMemory: true)
        _ = try BackupArchive.restore(data, into: other.mainContext)
        let restored = try other.mainContext.fetch(FetchDescriptor<Appointment>())
        #expect(restored.count == 2)
        #expect(Set(restored.map(\.statusRaw)) == [AppointmentStatus.scheduled.rawValue, AppointmentStatus.done.rawValue])
    }

    @Test("Borrar todo se lleva también las citas")
    func eraseAll() throws {
        _ = try weeklySeries()
        try BackupArchive.eraseAll(in: context)
        #expect(try context.fetch(FetchDescriptor<Appointment>()).isEmpty)
    }
}
