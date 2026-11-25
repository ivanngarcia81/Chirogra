import ChirograCore
import ChirograData
import EventKit
import SwiftData
import SwiftUI

// MARK: - Las citas en Calendario (1.4, docs/PLAN-1.4.md §1; decisión del usuario del 25-nov: acceso completo)
//
// Opción por aparato «Añadir las citas a Calendario». Las citas van a un calendario propio, «Chirogra», que el usuario
// puede ocultar. Con acceso completo (con «solo añadir» la app no puede cambiar ni borrar después lo que puso) cada
// cambio en Chirogra cambia el evento. Cada evento lleva su enlace a la cita (`chirogra://cita/…`): no se guarda nada en
// el aparato, y con los calendarios de iCloud los aparatos ponen al día los mismos eventos en vez de duplicarlos.

@MainActor
enum AppointmentCalendar {
    static let enabledKey = "agenda.calendar"
    static let calendarIDKey = "agenda.calendarID"
    /// Ventana que se mantiene al día: desde ayer hasta dentro de 60 días. Lo anterior se queda como está (historial).
    static let pastDays = 1
    static let futureDays = 60

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private static let store = EKEventStore()

    /// Enlace interno de cada evento a su cita (`chirogra://cita/<empresa>/<cita>`): así se encuentran los eventos sin
    /// guardar nada en el aparato, y dos aparatos con los calendarios de iCloud (o una app reinstalada) no los duplican.
    private static func prefix(_ companyID: UUID?) -> String { "chirogra://cita/\(companyID?.uuidString ?? "sin-empresa")/" }

    private static func link(_ occurrenceID: String, _ companyID: UUID?) -> URL? {
        URL(string: prefix(companyID) + (occurrenceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? occurrenceID))
    }

    /// Los eventos de la empresa en el calendario «Chirogra» entre `start` y `end`.
    private static func events(in target: EKCalendar, from start: Date, to end: Date, companyID: UUID?) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [target])
        let mine = prefix(companyID)
        return store.events(matching: predicate).filter { $0.url?.absoluteString.hasPrefix(mine) ?? false }
    }

    /// Pide el acceso completo; `false` si no se dio.
    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined: return (try? await store.requestFullAccessToEvents()) ?? false
        default: return false
        }
    }

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// El calendario «Chirogra» (lo crea la primera vez, en la cuenta del calendario por omisión).
    private static func calendar() throws -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey), let found = store.calendar(withIdentifier: id) { return found }
        if let found = store.calendars(for: .event).first(where: { $0.title == "Chirogra" && $0.allowsContentModifications }) {
            UserDefaults.standard.set(found.calendarIdentifier, forKey: calendarIDKey)
            return found
        }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        let created = EKCalendar(for: .event, eventStore: store)
        created.title = "Chirogra"
        created.source = source
        created.cgColor = CGColor(red: 0.227, green: 0.247, blue: 0.82, alpha: 1)  // Tinta
        try store.saveCalendar(created, commit: true)
        UserDefaults.standard.set(created.calendarIdentifier, forKey: calendarIDKey)
        return created
    }

    /// Pone al día los eventos de la empresa activa: crea, cambia y quita los de la ventana.
    static func sync(context: ModelContext, now: Date = .now) {
        let books = Bookkeeper(context: context)
        let companyID = try? books.resolvedCompanyID()
        guard isEnabled, hasAccess, let target = try? calendar() else { return }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -pastDays, to: cal.startOfDay(for: now)),
              let end = cal.date(byAdding: .day, value: futureDays, to: now),
              let occurrences = try? books.appointments(in: DateInterval(start: start, end: end)) else { return }
        let names = Dictionary(((try? books.fetch(Customer.self)) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // Lo que ya hay, por enlace (con margen: un evento movido puede haber quedado fuera de la ventana).
        let searchStart = cal.date(byAdding: .day, value: -7, to: start) ?? start
        var existing: [String: EKEvent] = [:]
        for event in events(in: target, from: searchStart, to: end, companyID: companyID) {
            guard let key = event.url?.absoluteString else { continue }
            if existing[key] == nil { existing[key] = event } else { try? store.remove(event, span: .thisEvent, commit: false) }
        }
        var kept = Set<String>()
        for occurrence in occurrences where occurrence.status != .cancelled {
            guard let url = link(occurrence.id, companyID) else { continue }
            let event = existing[url.absoluteString] ?? EKEvent(eventStore: store)
            let appointment = occurrence.appointment
            let who = appointment.customerID.flatMap { names[$0] }
            event.calendar = target
            event.url = url
            event.title = [who, appointment.title.isEmpty ? nil : appointment.title].compactMap { $0 }.joined(separator: " · ")
            event.startDate = occurrence.start
            event.endDate = occurrence.end
            event.location = appointment.location.isEmpty ? nil : appointment.location
            event.notes = appointment.notes.isEmpty ? nil : appointment.notes
            // Los avisos los da Chirogra: sin alarmas en el evento para no avisar dos veces.
            event.alarms = nil
            if (try? store.save(event, span: .thisEvent, commit: false)) != nil { kept.insert(url.absoluteString) }
        }
        // Lo que ya no está (borrado, cancelado, movido fuera, la regla cambió) se quita, si no es de antes de la ventana.
        for (key, event) in existing where !kept.contains(key) && event.startDate >= start {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    /// Al apagar la opción: quita los eventos próximos que puso Chirogra (los pasados se quedan).
    static func removeUpcoming(context: ModelContext, now: Date = .now) {
        guard hasAccess, let target = try? calendar(),
              let end = Calendar.current.date(byAdding: .day, value: futureDays + 30, to: now) else { return }
        let companyID = try? Bookkeeper(context: context).resolvedCompanyID()
        for event in events(in: target, from: now, to: end, companyID: companyID) {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
