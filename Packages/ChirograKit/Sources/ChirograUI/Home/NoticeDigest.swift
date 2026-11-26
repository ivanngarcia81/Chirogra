import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Resumen diario de avisos (1.4, docs/PLAN-1.4.md §2, «avisos automáticos»)
//
// Una notificación al día, a la hora elegida, con lo nuevo de la campana: lo que aparece ese día (una factura que vence,
// el sales tax o el pago al IRS que se acercan, un presupuesto excedido, una cita por facturar) y lo que vence ese mismo
// día, más las citas del día. Si no hay nada nuevo, ese día no avisa. Se programa por adelantado para los próximos 7
// días con los datos de ahora (la campana calcula los avisos de cualquier fecha) y se rehace al cambiar los datos o al
// volver a la app, como los avisos de las citas. Local: no gasta IA ni sale del aparato. Se enciende por aparato en
// Ajustes › Avisos (apagado de entrada). Desde la notificación, «Preguntar al asistente».

@MainActor
enum NoticeDigest {
    static let enabledKey = "avisos.resumen"
    /// Minutos desde medianoche (9:00 por omisión).
    static let timeKey = "avisos.resumenHora"
    static let identifierPrefix = "chirogra.resumen."
    static let category = "chirogra.resumen"
    static let askAction = "chirogra.resumen.preguntar"
    static let horizonDays = 7
    static let defaultMinutes = 9 * 60

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var minutes: Int { UserDefaults.standard.object(forKey: timeKey) as? Int ?? defaultMinutes }

    struct Planned: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        /// La pregunta para el asistente («Preguntar al asistente» de la notificación).
        let question: String
    }

    /// Lo que se avisaría cada día de los próximos `horizonDays`. Separado del centro de notificaciones para probarlo.
    static func plan(books: Bookkeeper, now: Date, minutes: Int, basis: AccountingBasis, calendar: Calendar = .current) -> [Planned] {
        let today = calendar.startOfDay(for: now)
        var planned: [Planned] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: day), fire > now,
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: fire) else { continue }
            let current = (try? books.notices(asOf: fire, calendar: calendar, basis: basis)) ?? []
            let before = Set(((try? books.notices(asOf: dayBefore, calendar: calendar, basis: basis)) ?? []).map(\.id))
            let dueToday: Set<NoticeKind> = [.billDueSoon, .salesTaxDue, .estimatedTaxDue]
            let items = current.filter { notice in
                notice.kind != .documentRenumbered && notice.kind != .recurringGenerated
                    && (!before.contains(notice.id) || (notice.days == 0 && dueToday.contains(notice.kind)))
            }
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let appointments = ((try? books.appointments(in: DateInterval(start: day, end: end), calendar: calendar)) ?? [])
                .filter { $0.status == .scheduled }.count
            guard !items.isEmpty || appointments > 0 else { continue }

            var lines = items.prefix(3).map { "\($0.title) · \($0.detail)" }
            if items.count > 3 { lines.append(String(localized: "Más avisos en la campana: \(items.count - 3).")) }
            if appointments > 0 { lines.append(String(localized: "Citas de hoy: \(appointments).")) }
            let question = items.isEmpty
                ? String(localized: "¿Qué citas tengo hoy?")
                : String(localized: "Tengo estos avisos hoy: \(items.prefix(5).map(\.title).joined(separator: "; ")). ¿Qué hago primero?")
            planned.append(Planned(identifier: identifierPrefix + Self.dayKey(day, calendar), fireDate: fire,
                                   title: String(localized: "Resumen de hoy"), body: lines.joined(separator: "\n"), question: question))
        }
        return planned
    }

    private static func dayKey(_ day: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// El botón «Preguntar al asistente» de la notificación.
    static func registerCategory() {
        let ask = UNNotificationAction(identifier: askAction, title: String(localized: "Preguntar al asistente"), options: [.foreground])
        let category = UNNotificationCategory(identifier: category, actions: [ask], intentIdentifiers: [])
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            center.setNotificationCategories(existing.filter { $0.identifier != NoticeDigest.category }.union([category]))
        }
    }

    /// Quita los resúmenes programados y pone los de ahora (de la empresa activa).
    static func reschedule(context: ModelContext, basis: AccountingBasis, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard isEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let books = Bookkeeper(context: context)
        let companyID = (try? books.company())?.id.uuidString ?? ""
        for item in plan(books: books, now: now, minutes: minutes, basis: basis) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["empresa": companyID, "pregunta": item.question]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let request = UNNotificationRequest(identifier: item.identifier, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Qué hacer al tocar una notificación de la app: el resumen abre la campana (o el asistente con «Preguntar al
/// asistente»); las demás (citas) solo abren la app. También las enseña con la app abierta.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    @MainActor static func install() {
        UNUserNotificationCenter.current().delegate = shared
        NoticeDigest.registerCategory()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(NoticeDigest.identifierPrefix) else { return }
        let info = request.content.userInfo
        let company = (info["empresa"] as? String).flatMap(UUID.init(uuidString:))
        let question = info["pregunta"] as? String
        let ask = response.actionIdentifier == NoticeDigest.askAction
        await MainActor.run {
            if ask, let question {
                AssistantState.shared.compose(question)
            } else if let company {
                ClientsRouter.shared.open(company, route: .notices)
            }
        }
    }
}

/// Rehace el resumen cuando cambian los datos de los que salen los avisos, al volver a la app o al cambiar el ajuste.
/// Va en `AppShell`, junto a `AppointmentReminderScheduler`.
struct NoticeDigestScheduler: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @CompanyQuery private var invoices: [Invoice]
    @CompanyQuery private var bills: [Bill]
    @CompanyQuery private var appointments: [Appointment]
    @CompanyQuery private var states: [NoticeState]
    @CompanyQuery private var lines: [JournalLine]
    @AppStorage(NoticeDigest.enabledKey) private var enabled = false
    @AppStorage(NoticeDigest.timeKey) private var minutes = NoticeDigest.defaultMinutes
    @ReportBasisSetting private var basis

    private var signature: String {
        "\(invoices.count)|\(bills.count)|\(appointments.count)|\(states.count)|\(lines.count)|\(enabled)|\(minutes)|\(basis.rawValue)|\(scenePhase == .active)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task { NotificationRouter.install() }
            .task(id: signature) {
                guard scenePhase == .active else { return }
                // Varios cambios seguidos (una importación) rehacen una sola vez.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await NoticeDigest.reschedule(context: context, basis: basis)
            }
    }
}

/// Ajustes › Avisos: el resumen diario en este aparato y su hora, y los avisos de las citas (también en el «⋯» de la
/// Agenda). Al encender el resumen se pide el permiso del sistema.
struct NoticeDigestSettings: View {
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @AppStorage(NoticeDigest.enabledKey) private var enabled = false
    @AppStorage(NoticeDigest.timeKey) private var minutes = NoticeDigest.defaultMinutes
    @AppStorage(AppointmentReminders.enabledKey) private var appointmentReminders = true
    @State private var denied = false

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        })
    }

    var body: some View {
        SettingsForm {
            SettingsSection {
                HStack(spacing: 12) {
                    IconTile(systemImage: "bell.badge.fill", foreground: Palette.red)
                    Toggle("Resumen diario", isOn: $enabled)
                }
                if enabled {
                    DatePicker("Hora", selection: time, displayedComponents: .hourAndMinute)
                }
            } header: {
                SectionLabel(text: String(localized: "Notificaciones de la campana"))
            } footer: {
                if denied {
                    Text("Las notificaciones de Chirogra están apagadas. Enciéndelas en los ajustes del sistema, en Notificaciones.")
                        .foregroundStyle(Palette.negative)
                } else {
                    Text("Una notificación al día con lo nuevo de la campana: facturas que vencen, sales tax y pagos al IRS que se acercan, presupuestos excedidos, citas por facturar y las citas del día. Si no hay nada nuevo, no avisa. Solo en este aparato.")
                }
            }
            SettingsSection {
                HStack(spacing: 12) {
                    IconTile(systemImage: "calendar", foreground: Palette.teal)
                    Toggle("Avisos de las citas", isOn: $appointmentReminders)
                }
            } footer: {
                Text("Antes de cada cita, con el tiempo que elijas en la cita. Solo en este aparato.")
            }
        }
        .toggleStyle(.switch)
        .screenBackground()
        .modifier(SettingsTitle(title: "Avisos", embedded: embedded))
        .onChange(of: enabled) { _, on in
            guard on else { denied = false; return }
            Task { @MainActor in
                let center = UNUserNotificationCenter.current()
                if await center.notificationSettings().authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound])
                }
                denied = await center.notificationSettings().authorizationStatus == .denied
            }
        }
        .task {
            guard enabled else { return }
            denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
    }
}

/// Título de la página abierta encima; dentro de `SettingsWideView`, ninguno (como `TitleUnlessEmbedded`).
private struct SettingsTitle: ViewModifier {
    let title: LocalizedStringKey
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle(title).inlineTitle() }
    }
}
