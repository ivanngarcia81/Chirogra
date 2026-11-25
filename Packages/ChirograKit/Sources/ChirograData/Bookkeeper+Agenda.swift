import ChirograCore
import Foundation
import SwiftData

// MARK: - Agenda (1.4, docs/PLAN-1.4.md §1; canvas «Chirogra 1.4», https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt)
//
// Las citas con los clientes. Una cita suelta es un `Appointment`. Una serie guarda la regla en su primera cita (la
// «plantilla», que no se enseña tal cual) y sus repeticiones se calculan; solo se guarda aparte la que cambia (hecha,
// movida, facturada, borrada), con `seriesID` y `occurrenceStart` (`SchemaV6.swift`).

/// Lo que el editor de la cita rellena (canvas `CitaEditor`).
public struct AppointmentDraft: Equatable, Sendable {
    public var title: String
    public var customerID: UUID?
    public var start: Date
    public var durationMinutes: Int
    public var location: String
    public var notes: String
    public var reminderMinutes: Int
    public var recurrence: AppointmentRepeat
    /// Último día en que puede caer una repetición; `nil` = no termina.
    public var recurrenceEnd: Date?

    public init(title: String = "", customerID: UUID? = nil, start: Date, durationMinutes: Int = 60, location: String = "",
                notes: String = "", reminderMinutes: Int = 30, recurrence: AppointmentRepeat = .none, recurrenceEnd: Date? = nil) {
        self.title = title
        self.customerID = customerID
        self.start = start
        self.durationMinutes = durationMinutes
        self.location = location
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.recurrence = recurrence
        self.recurrenceEnd = recurrenceEnd
    }
}

/// Al cambiar o borrar una cita que se repite: «Solo esta» o «Esta y las siguientes».
public enum AppointmentChangeScope: Sendable {
    case onlyThis, thisAndFollowing
}

/// Una cita en la agenda: guardada, o una repetición calculada de una serie (`isCalculated`).
public struct AppointmentOccurrence: Identifiable {
    /// El registro del que salen los datos: la cita, su repetición guardada aparte o, si es calculada, la plantilla.
    public let appointment: Appointment
    public let start: Date
    /// En una serie: la plantilla y el inicio que la regla le da a esta repetición.
    public let seriesID: UUID?
    public let occurrenceStart: Date?
    public let isCalculated: Bool

    public var id: String {
        isCalculated ? "\(appointment.id.uuidString)@\(Int(start.timeIntervalSinceReferenceDate))" : appointment.id.uuidString
    }
    public var end: Date { start.addingTimeInterval(TimeInterval(appointment.durationMinutes * 60)) }
    /// Las calculadas siempre están programadas (la plantilla no tiene estado propio).
    public var status: AppointmentStatus { isCalculated ? .scheduled : appointment.status }
    public var isRepeating: Bool { seriesID != nil }
    /// Hecha y sin factura ni presupuesto: la agenda la pone en «Por facturar».
    public var isPendingInvoice: Bool { status == .done && appointment.invoiceID == nil && appointment.estimateID == nil }
}

/// Cómo volver a encontrar una cita en pantalla después de cambiarla: una calculada pasa a guardarse aparte al marcarla
/// hecha, pero sigue siendo la misma repetición (su serie y su inicio según la regla).
public enum AppointmentKey: Hashable, Sendable {
    case stored(UUID)
    case slot(series: UUID, start: Date)
}

extension AppointmentOccurrence {
    public var key: AppointmentKey {
        if let seriesID, let occurrenceStart { return .slot(series: seriesID, start: occurrenceStart) }
        return .stored(appointment.id)
    }
}

extension Bookkeeper {

    // MARK: Leer

    /// La cita de `key` tal como está ahora; `nil` si se borró.
    public func appointment(for key: AppointmentKey) throws -> AppointmentOccurrence? {
        let all = try fetch(Appointment.self)
        switch key {
        case .stored(let id):
            guard let found = all.first(where: { $0.id == id }), found.status != .removed, !found.isSeries else { return nil }
            return AppointmentOccurrence(appointment: found, start: found.start, seriesID: found.seriesID,
                                         occurrenceStart: found.occurrenceStart, isCalculated: false)
        case .slot(let series, let start):
            let slot = Self.slotKey(start)
            if let saved = all.first(where: { $0.seriesID == series && $0.occurrenceStart.map(Self.slotKey) == slot }) {
                guard saved.status != .removed else { return nil }
                return AppointmentOccurrence(appointment: saved, start: saved.start, seriesID: series, occurrenceStart: start, isCalculated: false)
            }
            guard let template = all.first(where: { $0.id == series && $0.isSeries }) else { return nil }
            let lastDay = template.recurrenceEnd.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) }
            guard start >= template.start, lastDay.map({ start < $0 }) ?? true else { return nil }
            return AppointmentOccurrence(appointment: template, start: start, seriesID: series, occurrenceStart: start, isCalculated: true)
        }
    }

    /// Las citas que empiezan dentro de `range`, por hora, sin las borradas de una serie.
    public func appointments(in range: DateInterval, calendar: Calendar = .current) throws -> [AppointmentOccurrence] {
        let all = try fetch(Appointment.self)
        var overrides: [UUID: Set<Int>] = [:]
        for appointment in all {
            if let series = appointment.seriesID, let slot = appointment.occurrenceStart {
                overrides[series, default: []].insert(Self.slotKey(slot))
            }
        }
        var result: [AppointmentOccurrence] = []
        for appointment in all {
            if appointment.isSeries {
                let taken = overrides[appointment.id] ?? []
                for start in AppointmentRecurrence.starts(from: appointment.start, rule: appointment.recurrence,
                                                          lastDay: appointment.recurrenceEnd, in: range, calendar: calendar)
                where !taken.contains(Self.slotKey(start)) {
                    result.append(AppointmentOccurrence(appointment: appointment, start: start, seriesID: appointment.id,
                                                        occurrenceStart: start, isCalculated: true))
                }
            } else if appointment.status != .removed, range.start <= appointment.start, appointment.start < range.end {
                result.append(AppointmentOccurrence(appointment: appointment, start: appointment.start, seriesID: appointment.seriesID,
                                                    occurrenceStart: appointment.occurrenceStart, isCalculated: false))
            }
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Las de un cliente dentro de `range`.
    public func appointments(forCustomer customerID: UUID, in range: DateInterval, calendar: Calendar = .current) throws -> [AppointmentOccurrence] {
        try appointments(in: range, calendar: calendar).filter { $0.appointment.customerID == customerID }
    }

    // MARK: Crear y cambiar

    /// Cita nueva (suelta o la primera de una serie).
    @discardableResult
    public func createAppointment(_ draft: AppointmentDraft) throws -> Appointment {
        try validate(draft)
        let appointment = Appointment(title: "", start: draft.start)
        apply(draft, to: appointment, includingRecurrence: true)
        insert(appointment)
        audit(AuditSubject.appointment.rawValue, appointment.id, "create",
              String(localized: "Cita creada: \(summary(of: appointment, at: draft.start))"))
        try saveOrRollback()
        return appointment
    }

    /// Cambia una cita. En una serie, `scope` dice si solo esta repetición o esta y las siguientes (la regla nueva es la
    /// del borrador). En una suelta, el borrador puede convertirla en serie.
    @discardableResult
    public func updateAppointment(_ occurrence: AppointmentOccurrence, with draft: AppointmentDraft,
                                  scope: AppointmentChangeScope = .onlyThis, calendar: Calendar = .current) throws -> AppointmentKey {
        try validate(draft)
        let target: Appointment
        switch (occurrence.isRepeating, scope) {
        case (false, _):
            target = occurrence.appointment
            apply(draft, to: target, includingRecurrence: true)
        case (true, .onlyThis):
            target = materialize(occurrence)
            apply(draft, to: target, includingRecurrence: false)
        case (true, .thisAndFollowing):
            target = try splitSeries(at: occurrence, calendar: calendar)
            apply(draft, to: target, includingRecurrence: true)
        }
        audit(AuditSubject.appointment.rawValue, target.id, "update",
              String(localized: "Cita cambiada: \(summary(of: target, at: target.start))"))
        try saveOrRollback()
        return Self.key(of: target)
    }

    /// La clave de una cita guardada: la de su primera repetición si es una serie.
    public static func key(of appointment: Appointment) -> AppointmentKey {
        if appointment.isSeries { return .slot(series: appointment.id, start: appointment.start) }
        if let series = appointment.seriesID, let slot = appointment.occurrenceStart { return .slot(series: series, start: slot) }
        return .stored(appointment.id)
    }

    /// Hecha, cancelada, no vino o de vuelta a programada.
    public func setStatus(_ status: AppointmentStatus, of occurrence: AppointmentOccurrence) throws {
        guard status != .removed else { return try deleteAppointment(occurrence, scope: .onlyThis) }
        let target = materialize(occurrence)
        target.status = status
        audit(AuditSubject.appointment.rawValue, target.id, "update",
              String(localized: "Cita \(Self.statusTitle(status)): \(summary(of: target, at: target.start))"))
        try saveOrRollback()
    }

    /// Enlaza la factura o el presupuesto creado desde la cita («Crear factura» del canvas `CitaFichaHecha`). Una cita
    /// programada pasa a hecha: si se factura, se hizo.
    public func link(_ occurrence: AppointmentOccurrence, invoiceID: UUID? = nil, estimateID: UUID? = nil) throws {
        let target = materialize(occurrence)
        if let invoiceID { target.invoiceID = invoiceID }
        if let estimateID { target.estimateID = estimateID }
        if invoiceID != nil, target.status == .scheduled { target.status = .done }
        audit(AuditSubject.appointment.rawValue, target.id, "update",
              invoiceID != nil ? String(localized: "Cita facturada: \(summary(of: target, at: target.start))")
                               : String(localized: "Estimado desde la cita: \(summary(of: target, at: target.start))"))
        try saveOrRollback()
    }

    /// Borra una cita; en una serie, solo esta repetición o esta y las siguientes.
    public func deleteAppointment(_ occurrence: AppointmentOccurrence, scope: AppointmentChangeScope = .onlyThis,
                                  calendar: Calendar = .current) throws {
        let text = summary(of: occurrence.appointment, at: occurrence.start)
        switch (occurrence.isRepeating, scope) {
        case (false, _):
            context.delete(occurrence.appointment)
        case (true, .onlyThis):
            materialize(occurrence).status = .removed
        case (true, .thisAndFollowing):
            let next = try splitSeries(at: occurrence, calendar: calendar)
            context.delete(next)
        }
        audit(AuditSubject.appointment.rawValue, occurrence.appointment.id, "delete", String(localized: "Cita eliminada: \(text)"))
        try saveOrRollback()
    }

    // MARK: Por dentro

    private func validate(_ draft: AppointmentDraft) throws {
        try ensureWritable()
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.customerID == nil {
            throw BookkeepingError.invalidState(String(localized: "La cita necesita un cliente o un título."))
        }
        guard draft.durationMinutes > 0 else {
            throw BookkeepingError.invalidState(String(localized: "La cita tiene que durar algo."))
        }
    }

    private func apply(_ draft: AppointmentDraft, to appointment: Appointment, includingRecurrence: Bool) {
        appointment.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.customerID = draft.customerID
        appointment.start = draft.start
        appointment.durationMinutes = draft.durationMinutes
        appointment.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.notes = draft.notes
        appointment.reminderMinutes = draft.reminderMinutes
        if includingRecurrence {
            appointment.recurrence = draft.recurrence
            appointment.recurrenceEnd = draft.recurrence == .none ? nil : draft.recurrenceEnd
        }
    }

    /// La repetición guardada aparte (la crea si era calculada, con los datos de la plantilla).
    private func materialize(_ occurrence: AppointmentOccurrence) -> Appointment {
        guard occurrence.isCalculated else { return occurrence.appointment }
        let series = occurrence.appointment
        let copy = Appointment(title: series.title, start: occurrence.start, durationMinutes: series.durationMinutes,
                               customerID: series.customerID)
        copy.companyID = series.companyID
        copy.location = series.location
        copy.notes = series.notes
        copy.reminderMinutes = series.reminderMinutes
        copy.seriesID = series.id
        copy.occurrenceStart = occurrence.occurrenceStart ?? occurrence.start
        insert(copy)
        return copy
    }

    /// «Esta y las siguientes»: la serie de antes termina el día anterior a esta repetición y empieza otra aquí, que se
    /// devuelve (si es la primera repetición, la misma plantilla). Las repeticiones guardadas desde aquí: las que solo se
    /// movieron o se borraron se quitan (la serie nueva las vuelve a dar); las hechas, canceladas o facturadas quedan
    /// como citas sueltas, con su historia.
    private func splitSeries(at occurrence: AppointmentOccurrence, calendar: Calendar) throws -> Appointment {
        guard let seriesID = occurrence.seriesID, let slot = occurrence.occurrenceStart,
              let series = try fetch(Appointment.self).first(where: { $0.id == seriesID }) else {
            return occurrence.appointment
        }
        let key = Self.slotKey(slot)
        for saved in try fetch(Appointment.self) where saved.seriesID == seriesID {
            guard let savedSlot = saved.occurrenceStart, Self.slotKey(savedSlot) >= key else { continue }
            if saved.status == .scheduled && saved.invoiceID == nil && saved.estimateID == nil || saved.status == .removed {
                context.delete(saved)
            } else {
                saved.seriesID = nil
                saved.occurrenceStart = nil
            }
        }
        if Self.slotKey(series.start) >= key { return series }
        let next = Appointment(title: series.title, start: slot, durationMinutes: series.durationMinutes, customerID: series.customerID)
        next.companyID = series.companyID
        next.location = series.location
        next.notes = series.notes
        next.reminderMinutes = series.reminderMinutes
        next.recurrence = series.recurrence
        next.recurrenceEnd = series.recurrenceEnd
        insert(next)
        series.recurrenceEnd = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: slot))
        return next
    }

    /// Clave de una repetición: su inicio al segundo (las fechas que vuelven de iCloud pueden traer milésimas de más).
    static func slotKey(_ date: Date) -> Int { Int(date.timeIntervalSinceReferenceDate.rounded()) }

    private func summary(of appointment: Appointment, at date: Date) -> String {
        let who = appointment.customerID.flatMap { id in (try? fetch(Customer.self))?.first { $0.id == id }?.name }
        let what = [who, appointment.title.isEmpty ? nil : appointment.title].compactMap { $0 }.joined(separator: " · ")
        return "\(what) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func statusTitle(_ status: AppointmentStatus) -> String {
        switch status {
        case .scheduled: String(localized: "programada")
        case .done: String(localized: "hecha")
        case .cancelled: String(localized: "cancelada")
        case .noShow: String(localized: "sin asistencia")
        case .removed: String(localized: "eliminada")
        }
    }
}
