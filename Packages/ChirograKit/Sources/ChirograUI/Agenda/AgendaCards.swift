import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Piezas de la agenda que se ven fuera de ella (canvas «Chirogra 1.4»): «Hoy» en Inicio (`Main`, `InicioSinCitas`,
// `iPadInicio`) y las citas en la ficha del cliente (`ClienteCitas`).

/// Las citas de hoy, para Inicio.
struct TodayAppointments {
    let items: [AppointmentOccurrence]
    /// La agenda se ha usado (hay alguna cita): si no, Inicio no enseña «Hoy».
    let isUsed: Bool

    @MainActor
    init(context: ModelContext, stored: [Appointment]) {
        isUsed = !stored.isEmpty
        let today = Calendar.current.startOfDay(for: .now)
        let range = DateInterval(start: today, end: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
        items = isUsed ? ((try? Bookkeeper(context: context).appointments(in: range)) ?? []).filter { $0.status != .cancelled } : []
    }

    /// «mié 25 nov · 3 citas» o «Sin citas hoy».
    var subtitle: String {
        guard !items.isEmpty else { return String(localized: "Sin citas hoy") }
        let day = Date.now.formatted(.appDateTime.weekday(.abbreviated).day().month(.abbreviated))
        return items.count == 1 ? String(localized: "\(day) · 1 cita") : String(localized: "\(day) · \(items.count) citas")
    }

    /// «3 citas · próxima 11:30 a. m.» (columna del iPad).
    var padSubtitle: String {
        guard !items.isEmpty else { return String(localized: "Sin citas hoy") }
        let count = items.count == 1 ? String(localized: "1 cita") : String(localized: "\(items.count) citas")
        guard let next = items.first(where: { $0.status == .scheduled && $0.end > .now }) else { return count }
        return String(localized: "\(count) · próxima \(next.start.formatted(.appDateTime.hour().minute()))")
    }
}

/// Tarjeta «Hoy» de Inicio en el iPhone (canvas `Main`): título, el día y cuántas citas, «Agenda» a la derecha y una fila
/// por cita.
struct TodayAppointmentsCard: View {
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Appointment.start) private var stored: [Appointment]
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]

    var body: some View {
        let today = TodayAppointments(context: context, stored: stored)
        if today.isUsed {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Hoy").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    Text(today.subtitle).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                    Spacer(minLength: 8)
                    SectionLink(item: .section(.agenda)) { AgendaView() } label: { Text("Agenda") }
                        .buttonStyle(.plain).foregroundStyle(Palette.brand)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                ForEach(today.items) { item in
                    Divider().padding(.leading, 16)
                    AppointmentLinkRow(occurrence: item, customers: customers)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Citas de hoy")
        }
    }
}

/// Fila que abre la ficha de la cita, con su chevron.
struct AppointmentLinkRow: View {
    let occurrence: AppointmentOccurrence
    let customers: [Customer]
    var trailing: String?

    var body: some View {
        NavigationLink {
            AppointmentDetailView(key: occurrence.key)
        } label: {
            HStack(spacing: 10) {
                AppointmentRow(occurrence: occurrence,
                               customerName: occurrence.appointment.customerID.flatMap { id in customers.first { $0.id == id }?.name },
                               trailing: trailing)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Citas de un cliente en su ficha (canvas `ClienteCitas`): la próxima y las últimas, «Nueva cita» y «Ver en la agenda».
struct CustomerAppointmentsSection: View {
    let customer: Customer
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Appointment.start) private var stored: [Appointment]
    @State private var creating = false

    private var occurrences: (upcoming: [AppointmentOccurrence], past: [AppointmentOccurrence]) {
        _ = stored.count
        let calendar = Calendar.current
        let now = Date.now
        guard let from = calendar.date(byAdding: .day, value: -180, to: now),
              let to = calendar.date(byAdding: .day, value: 90, to: now),
              let all = try? Bookkeeper(context: context).appointments(forCustomer: customer.id, in: DateInterval(start: from, end: to))
        else { return ([], []) }
        let upcoming = all.filter { $0.end >= now && $0.status == .scheduled }
        let past = all.filter { !($0.end >= now && $0.status == .scheduled) }.reversed()
        return (Array(upcoming.prefix(3)), Array(past.prefix(5)))
    }

    var body: some View {
        let lists = occurrences
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "Citas")) {
                Button("Nueva cita") { creating = true }.buttonStyle(.plain).foregroundStyle(Palette.brand)
            }
            RowGroup {
                if lists.upcoming.isEmpty && lists.past.isEmpty {
                    Text("Sin citas con este cliente.").font(.subheadline).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                // Sin el nombre del cliente (ya es su ficha): el servicio arriba y el día con la hora a la derecha.
                ForEach(lists.upcoming + lists.past) {
                    AppointmentLinkRow(occurrence: $0, customers: [], trailing: "\($0.start.dayMonth) · \($0.start.formatted(.appDateTime.hour().minute()))")
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { AppointmentEditorView(customerID: customer.id) }.editorSheetSizing()
        }
    }
}
