import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Editor de una cita, en hoja (canvas `CitaEditor`, `CitaEditorRepite`): cliente (opcional) y servicio; fecha, hora,
/// duración y lugar; aviso y repetición; notas. Al guardar una cita que se repite pregunta «Solo esta» o «Esta y las
/// siguientes».
struct AppointmentEditorView: View {
    /// La cita que se cambia; `nil` = nueva.
    var occurrence: AppointmentOccurrence?
    /// Nueva: el día que se veía en la agenda (a la próxima hora en punto si es hoy, si no a las 9).
    var day: Date?
    /// Nueva desde la ficha de un cliente.
    var customerID: UUID?
    /// Al guardar, la clave de la cita resultante (con «esta y las siguientes» es otra serie).
    var onSaved: ((AppointmentKey) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]
    @CompanyQuery(sort: \Appointment.start) private var stored: [Appointment]

    @State private var selectedCustomer: UUID?
    @State private var title = ""
    @State private var start = Date()
    @State private var duration = 60
    @State private var location = ""
    @State private var reminder = 30
    @State private var recurrence: AppointmentRepeat = .none
    @State private var ends = false
    @State private var lastDay = Date()
    @State private var notes = ""
    @State private var loaded = false
    @State private var askingScope = false
    @State private var errorMessage: String?

    init(occurrence: AppointmentOccurrence? = nil, day: Date? = nil, customerID: UUID? = nil,
         onSaved: ((AppointmentKey) -> Void)? = nil) {
        self.occurrence = occurrence
        self.day = day
        self.customerID = customerID
        self.onSaved = onSaved
    }

    private static let durations = [15, 30, 45, 60, 90, 120, 180, 240, 480]

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var isRepeating: Bool { occurrence?.isRepeating ?? false }

    var body: some View {
        Form {
            Section {
                Picker(selection: $selectedCustomer) {
                    Text("Sin cliente").tag(UUID?.none)
                    ForEach(customers) { Text($0.name).tag(Optional($0.id)) }
                } label: {
                    HStack(spacing: 6) {
                        Text("Cliente")
                        Text("opcional").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                LabeledContent("Servicio o título") {
                    TextField("Servicio o título", text: $title, prompt: Text("Visita, instalación…"))
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Servicio o título")
                }
            }
            Section {
                DatePicker("Fecha y hora", selection: $start, displayedComponents: [.date, .hourAndMinute])
                Picker("Duración", selection: $duration) {
                    ForEach(Self.durations.contains(duration) ? Self.durations : Self.durations + [duration], id: \.self) {
                        Text(AppointmentText.duration($0)).tag($0)
                    }
                }
                LabeledContent("Lugar") {
                    TextField("Lugar", text: $location, prompt: Text("Opcional"))
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Lugar")
                }
            }
            Section {
                Picker("Recordatorio", selection: $reminder) {
                    ForEach(AppointmentReminder.choices, id: \.self) { Text(AppointmentText.reminder($0)).tag($0) }
                }
                Picker("Repetición", selection: $recurrence) {
                    ForEach(AppointmentRepeat.allCases, id: \.self) { Text(AppointmentText.recurrence($0)).tag($0) }
                }
                if recurrence != .none {
                    Toggle("Termina", isOn: $ends)
                    if ends {
                        DatePicker("Último día", selection: $lastDay, in: start..., displayedComponents: .date)
                    }
                }
            } footer: {
                if isRepeating {
                    Text("La repetición cambia solo si eliges «Esta y las siguientes» al guardar.")
                }
            }
            Section {
                TextField("Notas", text: $notes, prompt: Text("Qué llevar, a quién preguntar…"), axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel("Notas")
            }
            if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(occurrence == nil ? "Nueva cita" : "Editar cita")
        .inlineTitle()
        .discardableEditor(tracking: signature, token: editorToken)
        .bottomActionBar {
            Button("Guardar cita", action: attemptSave).buttonStyle(PrimaryButtonStyle())
        }
        // Aviso centrado, como el canvas `CitaEditorRepite` (un globo con flecha tapaba el formulario).
        .alert("Esta cita se repite", isPresented: $askingScope) {
            Button("Solo esta") { save(.onlyThis) }
            Button("Esta y las siguientes") { save(.thisAndFollowing) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("¿Qué citas quieres cambiar?")
        }
        .onAppear(perform: load)
    }

    private var signature: String {
        "\(selectedCustomer?.uuidString ?? "")|\(title)|\(start.timeIntervalSinceReferenceDate)|\(duration)|\(location)|\(reminder)|\(recurrence.rawValue)|\(ends)|\(lastDay.timeIntervalSinceReferenceDate)|\(notes)"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let occurrence {
            let appointment = occurrence.appointment
            selectedCustomer = appointment.customerID
            title = appointment.title
            start = occurrence.start
            duration = appointment.durationMinutes
            location = appointment.location
            reminder = appointment.reminderMinutes
            notes = appointment.notes
            if let series = occurrence.seriesID, let template = stored.first(where: { $0.id == series }) {
                recurrence = template.recurrence
                if let end = template.recurrenceEnd { ends = true; lastDay = end }
            } else {
                recurrence = appointment.recurrence
                if let end = appointment.recurrenceEnd { ends = true; lastDay = end }
            }
        } else {
            selectedCustomer = customerID
            start = Self.defaultStart(on: day ?? .now)
            lastDay = Calendar.current.date(byAdding: .month, value: 3, to: start) ?? start
        }
    }

    /// Hoy, la próxima hora en punto; otro día, a las 9.
    private static func defaultStart(on day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            let next = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
            return next
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private var draft: AppointmentDraft {
        AppointmentDraft(title: title, customerID: selectedCustomer, start: start, durationMinutes: duration, location: location,
                         notes: notes, reminderMinutes: reminder, recurrence: recurrence,
                         recurrenceEnd: recurrence != .none && ends ? lastDay : nil)
    }

    private func attemptSave() {
        if isRepeating { askingScope = true } else { save(.onlyThis) }
    }

    private func save(_ scope: AppointmentChangeScope) {
        do {
            let key: AppointmentKey
            if let occurrence {
                key = try books.updateAppointment(occurrence, with: draft, scope: scope)
            } else {
                key = Bookkeeper.key(of: try books.createAppointment(draft))
            }
            unsavedChanges?.remove(editorToken)
            onSaved?(key)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
