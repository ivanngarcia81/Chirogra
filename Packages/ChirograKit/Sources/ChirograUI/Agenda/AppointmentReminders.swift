import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Avisos de las citas (1.4, docs/PLAN-1.4.md §1)
//
// Notificaciones locales: cada aparato programa las suyas a partir de las citas que tiene (también las que llegan por
// iCloud) y las rehace cuando cambia alguna. Solo las de los próximos 14 días y como mucho 50 (iOS guarda 64 por app).
// Se apagan por aparato (`enabledKey`). El permiso se pide la primera vez que se guarda una cita con aviso.

@MainActor
enum AppointmentReminders {
    /// Avisos encendidos en este aparato (por defecto, sí).
    static let enabledKey = "agenda.reminders"
    static let identifierPrefix = "chirogra.cita."
    static let horizonDays = 14
    static let maximum = 50

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// La primera vez, el permiso del sistema para avisar.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Lo que hay que avisar: inicio del aviso, título y texto. Separado para probarlo sin el centro de notificaciones.
    struct Planned: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    static func plan(_ occurrences: [AppointmentOccurrence], customers: [UUID: String], now: Date) -> [Planned] {
        occurrences
            .filter { $0.status == .scheduled && $0.appointment.reminderMinutes >= 0 }
            .compactMap { occurrence -> Planned? in
                let fire = occurrence.start.addingTimeInterval(-TimeInterval(occurrence.appointment.reminderMinutes * 60))
                guard fire > now else { return nil }
                let appointment = occurrence.appointment
                let who = appointment.customerID.flatMap { customers[$0] }
                let time = occurrence.start.formatted(.appDateTime.hour().minute())
                let when = Calendar.current.isDate(occurrence.start, inSameDayAs: fire)
                    ? time : "\(occurrence.start.formatted(.appDateTime.weekday(.wide))) \(time)"
                let body = [appointment.title.isEmpty || who == nil ? nil : appointment.title, when,
                            appointment.location.isEmpty ? nil : appointment.location].compactMap { $0 }.joined(separator: " · ")
                return Planned(identifier: identifierPrefix + occurrence.id, fireDate: fire,
                               title: who ?? (appointment.title.isEmpty ? String(localized: "Cita") : appointment.title), body: body)
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximum)
            .map { $0 }
    }

    /// Quita los avisos de citas programados y vuelve a poner los de ahora.
    static func reschedule(context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard isEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let books = Bookkeeper(context: context)
        guard let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: now),
              let occurrences = try? books.appointments(in: DateInterval(start: now, end: end)) else { return }
        let names = Dictionary(((try? books.fetch(Customer.self)) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for item in plan(occurrences, customers: names, now: now) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let request = UNNotificationRequest(identifier: item.identifier, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Rehace los avisos cuando cambia alguna cita de la empresa activa (también las que llegan por iCloud) o al encender
/// o apagar los avisos. Va en `AppShell`, siempre a la vista.
struct AppointmentReminderScheduler: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @CompanyQuery(sort: \Appointment.start) private var appointments: [Appointment]
    @AppStorage(AppointmentReminders.enabledKey) private var enabled = true

    /// Lo que cambia los avisos de una cita.
    private var signature: String {
        appointments.map {
            "\($0.id)|\($0.start.timeIntervalSinceReferenceDate)|\($0.durationMinutes)|\($0.statusRaw)|\($0.reminderMinutes)|\($0.recurrenceRaw)|\($0.recurrenceEnd?.timeIntervalSinceReferenceDate ?? 0)|\($0.title)|\($0.location)|\($0.customerID?.uuidString ?? "")"
        }.joined(separator: ";") + "|\(enabled)|\(scenePhase == .active)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // El permiso no se pide aquí (los datos de ejemplo traen avisos y saldría al abrir la app): lo pide el editor
            // al guardar una cita con aviso.
            .task(id: signature) {
                guard scenePhase == .active else { return }
                await AppointmentReminders.reschedule(context: context)
            }
    }
}
