import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ficha de una cita (canvas `CitaFicha`, `CitaFichaHecha`, `CitaFichaFacturada`): quién, qué y cuándo arriba, con el
/// estado; la acción principal según el estado (programada → «Marcar como hecha», hecha sin factura → «Crear
/// factura», cancelada o no vino → «Volver a programar»); las demás acciones; y lugar, aviso, repetición y notas.
struct AppointmentDetailView: View {
    @State var key: AppointmentKey
    /// iPad y Mac: al lado de la agenda (sin título propio, que es el de la Agenda).
    var embedded = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Solo para redibujar al cambiar algo.
    @CompanyQuery(sort: \Appointment.start) private var stored: [Appointment]
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]
    @CompanyQuery(sort: \Invoice.issueDate) private var invoices: [Invoice]
    @State private var editing = false
    @State private var creatingInvoice = false
    @State private var creatingEstimate = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    private var occurrence: AppointmentOccurrence? {
        _ = stored.count
        return try? books.appointment(for: key)
    }

    var body: some View {
        Group {
            if let occurrence { content(occurrence) } else {
                ContentUnavailableView("Cita eliminada", systemImage: "calendar.badge.minus",
                                       description: Text("Esta cita ya no está en la agenda."))
            }
        }
        .screenBackground()
        .modifier(DetailTitle(embedded: embedded))
    }

    private func customer(_ occurrence: AppointmentOccurrence) -> Customer? {
        occurrence.appointment.customerID.flatMap { id in customers.first { $0.id == id } }
    }

    @ViewBuilder
    private func content(_ occurrence: AppointmentOccurrence) -> some View {
        let appointment = occurrence.appointment
        Form {
            Section {
                VStack(spacing: 4) {
                    if let name = customer(occurrence)?.name {
                        Text(name).font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                    Text(appointment.title.isEmpty ? String(localized: "Cita") : appointment.title)
                        .font(.title.bold()).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    StatusChip(text: occurrence.statusTitle, foreground: occurrence.statusColor, dot: occurrence.statusDot)
                    Text(occurrence.start.formatted(.appDateTime.weekday(.wide).day().month(.wide)).sentenceCased)
                        .font(.body).foregroundStyle(Palette.ink).padding(.top, 4)
                    Text("\(occurrence.timeRange) · \(occurrence.durationText)").font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }

            if let invoiceID = appointment.invoiceID, let invoice = invoices.first(where: { $0.id == invoiceID }) {
                Section {
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                        LabeledContent {
                            Text(invoice.total.money)
                        } label: {
                            Label(String(localized: "Facturada · \(invoice.number)"), systemImage: "doc.text")
                                .foregroundStyle(Palette.brand)
                        }
                    }
                }
            }

            if let main = mainAction(occurrence) {
                Section {
                    Button(action: main.action) { Label(main.title, systemImage: main.symbol) }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if occurrence.isPendingInvoice {
                        Text("Esta cita ya se hizo y todavía no tiene factura.").frame(maxWidth: .infinity)
                    }
                }
            }

            Section {
                if occurrence.status == .scheduled {
                    Button { creatingInvoice = true } label: { Label("Crear factura", systemImage: "doc.badge.plus") }
                }
                if appointment.estimateID == nil, occurrence.status != .cancelled {
                    Button { creatingEstimate = true } label: { Label("Crear estimado", systemImage: "doc.badge.clock") }
                }
                if occurrence.status == .scheduled {
                    Button { set(.noShow, occurrence) } label: { Label("No vino", systemImage: "person.fill.xmark") }
                    Button(role: .destructive) { set(.cancelled, occurrence) } label: { Label("Cancelar cita", systemImage: "xmark.circle") }
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Eliminar cita", systemImage: "trash") }
            }

            Section {
                if let customer = customer(occurrence) {
                    NavigationLink { CustomerDetailView(customer: customer) } label: {
                        LabeledContent("Cliente", value: customer.name)
                    }
                }
                if !appointment.location.isEmpty { LabeledContent("Lugar", value: appointment.location) }
                LabeledContent("Recordatorio", value: AppointmentText.reminder(appointment.reminderMinutes))
                LabeledContent("Repetición", value: repetition(occurrence))
                if !appointment.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notas").font(.footnote).foregroundStyle(Palette.ink2)
                        Text(appointment.notes).foregroundStyle(Palette.ink)
                    }
                }
            }

            if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padReadingList(PadReading.detail)
        .modifier(DetailTitle(embedded: embedded, title: appointment.title.isEmpty ? String(localized: "Cita") : appointment.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Editar") { editing = true } }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                AppointmentEditorView(occurrence: occurrence) { key = $0 }
            }
            .editorSheetSizing()
        }
        .sheet(isPresented: $creatingInvoice) {
            NavigationStack { InvoiceEditorView(appointment: occurrence) }.editorSheetSizing()
        }
        .sheet(isPresented: $creatingEstimate) {
            NavigationStack { InvoiceEditorView(mode: .estimate(nil), appointment: occurrence) }.editorSheetSizing()
        }
        .alert(occurrence.isRepeating ? "Esta cita se repite" : "¿Eliminar esta cita?", isPresented: $confirmingDelete) {
            if occurrence.isRepeating {
                Button("Eliminar solo esta", role: .destructive) { delete(occurrence, .onlyThis) }
                Button("Eliminar esta y las siguientes", role: .destructive) { delete(occurrence, .thisAndFollowing) }
            } else {
                Button("Eliminar", role: .destructive) { delete(occurrence, .onlyThis) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func repetition(_ occurrence: AppointmentOccurrence) -> String {
        guard let series = occurrence.seriesID,
              let template = stored.first(where: { $0.id == series }) else { return AppointmentText.recurrence(.none) }
        return AppointmentText.recurrence(template.recurrence)
    }

    private func mainAction(_ occurrence: AppointmentOccurrence) -> (title: String, symbol: String, action: () -> Void)? {
        switch occurrence.status {
        case .scheduled: (String(localized: "Marcar como hecha"), "checkmark", { set(.done, occurrence) })
        case .done where occurrence.isPendingInvoice: (String(localized: "Crear factura"), "doc.badge.plus", { creatingInvoice = true })
        case .cancelled, .noShow: (String(localized: "Volver a programar"), "calendar", { set(.scheduled, occurrence) })
        default: nil
        }
    }

    private func set(_ status: AppointmentStatus, _ occurrence: AppointmentOccurrence) {
        do {
            try books.setStatus(status, of: occurrence)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ occurrence: AppointmentOccurrence, _ scope: AppointmentChangeScope) {
        do {
            try books.deleteAppointment(occurrence, scope: scope)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Título de la ficha: el de la cita y en línea; nada si va al lado de la agenda.
private struct DetailTitle: ViewModifier {
    let embedded: Bool
    var title: String?

    func body(content: Content) -> some View {
        if embedded {
            content
        } else if let title {
            content.navigationTitle(title)
        } else {
            content.inlineTitle()
        }
    }
}
