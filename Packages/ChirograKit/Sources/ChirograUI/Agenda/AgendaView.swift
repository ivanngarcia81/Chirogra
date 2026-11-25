import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Agenda (1.4; canvas «Chirogra 1.4», https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt, tableros `Agenda`,
// `AgendaSemana`, `AgendaLista`, `AgendaVacia`)
//
// Las citas con los clientes en tres vistas: Día (franjas por hora), Semana (tira de días y la lista del día elegido) y
// Lista (próximas, con «Por facturar» aparte). Los datos están en `Bookkeeper+Agenda.swift` (docs/DATOS-V6.md).

/// Cómo se ve el estado de una cita (punto de color + texto, como en el canvas).
extension AppointmentOccurrence {
    var statusTitle: String {
        switch status {
        case .scheduled: String(localized: "Programada")
        case .done: isPendingInvoice ? String(localized: "Hecha · sin factura") : String(localized: "Hecha")
        case .cancelled: String(localized: "Cancelada")
        case .noShow: String(localized: "No vino")
        case .removed: String(localized: "Eliminada")
        }
    }

    var statusColor: Color {
        switch status {
        case .scheduled: Palette.info
        case .done: Palette.positive
        case .cancelled, .removed: Palette.ink2
        case .noShow: Palette.warning
        }
    }

    var statusDot: Color {
        switch status {
        case .scheduled: Palette.blue
        case .done: Palette.green
        case .cancelled, .removed: Palette.gray
        case .noShow: Palette.orange
        }
    }

    /// «11:30 a. m. – 1:00 p. m.»
    var timeRange: String {
        "\(start.formatted(.appDateTime.hour().minute())) – \(end.formatted(.appDateTime.hour().minute()))"
    }

    /// «1 h 30 min»
    var durationText: String { AppointmentText.duration(appointment.durationMinutes) }
}

enum AppointmentText {
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    static func reminder(_ minutes: Int) -> String {
        switch minutes {
        case AppointmentReminder.none: String(localized: "Sin aviso")
        case 0: String(localized: "A la hora")
        case 1_440: String(localized: "1 día antes")
        case let value where value % 60 == 0: String(localized: "\(value / 60) h antes")
        default: String(localized: "\(minutes) min antes")
        }
    }

    static func recurrence(_ rule: AppointmentRepeat) -> String {
        switch rule {
        case .none: String(localized: "No se repite")
        case .daily: String(localized: "Cada día")
        case .weekly: String(localized: "Cada semana")
        case .biweekly: String(localized: "Cada 2 semanas")
        case .monthly: String(localized: "Cada mes")
        }
    }
}

/// Fila de una cita (canvas `AgendaLista`): cliente y hora arriba; servicio y estado debajo.
struct AppointmentRow: View {
    let occurrence: AppointmentOccurrence
    let customerName: String?
    /// Lo de la derecha arriba: la hora, o el día en «Por facturar».
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(customerName ?? occurrence.appointment.title).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(trailing ?? occurrence.start.formatted(.appDateTime.hour().minute()))
                    .font(.subheadline).foregroundStyle(Palette.ink2).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                if customerName != nil, !occurrence.appointment.title.isEmpty {
                    Text(occurrence.appointment.title).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                StatusChip(text: occurrence.statusTitle, foreground: occurrence.statusColor, compact: true, dot: occurrence.statusDot)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AgendaView: View {
    enum Mode: String, CaseIterable, Hashable {
        case day, week, list

        var title: String {
            switch self {
            case .day: String(localized: "Día")
            case .week: String(localized: "Semana")
            case .list: String(localized: "Lista")
            }
        }
    }

    @Environment(\.modelContext) private var context
    /// Solo para redibujar al cambiar algo: las citas se calculan con `Bookkeeper.appointments(in:)`.
    @CompanyQuery(sort: \Appointment.start) private var stored: [Appointment]
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]
    @AppStorage("agenda.mode") private var mode: Mode = .day
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var creating = false
    @AppStorage(AppointmentReminders.enabledKey) private var remindersOn = true
    @AppStorage(AppointmentCalendar.enabledKey) private var calendarOn = false
    @State private var calendarDenied = false
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 60

    private var calendar: Calendar { .current }
    private var books: Bookkeeper { Bookkeeper(context: context) }

    var body: some View {
        Group {
            if stored.isEmpty {
                emptyState
            } else {
                switch mode {
                case .day: dayView
                case .week: weekView
                case .list: listView
                }
            }
        }
        .screenBackground()
        .navigationTitle("Agenda")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Hoy") { withAnimation { day = calendar.startOfDay(for: .now) } }
                    .disabled(calendar.isDateInToday(day) && mode != .list)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Nueva cita", systemImage: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Avisos de citas en este aparato", isOn: $remindersOn)
                    Toggle("Añadir las citas a Calendario", isOn: calendarBinding)
                } label: {
                    Label("Más opciones", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { AppointmentEditorView(day: day) }.editorSheetSizing()
        }
        .alert("Sin acceso a Calendario", isPresented: $calendarDenied) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            #if os(iOS)
            Text("Para poner tus citas en Calendario, permite el acceso completo en Ajustes › Apps › Chirogra › Calendarios.")
            #else
            Text("Para poner tus citas en Calendario, permite el acceso en Ajustes del Sistema › Privacidad y seguridad › Calendarios.")
            #endif
        }
    }

    /// «Añadir las citas a Calendario»: al encenderla pide el acceso completo; si no se da, se queda apagada y explica
    /// dónde darlo. Al apagarla quita los eventos próximos que puso Chirogra.
    private var calendarBinding: Binding<Bool> {
        Binding(get: { calendarOn }, set: { turnOn in
            if turnOn {
                Task { @MainActor in
                    if await AppointmentCalendar.requestAccess() {
                        calendarOn = true
                        AppointmentCalendar.sync(context: context)
                    } else {
                        calendarDenied = true
                    }
                }
            } else {
                calendarOn = false
                AppointmentCalendar.removeUpcoming(context: context)
            }
        })
    }

    private func customerName(_ occurrence: AppointmentOccurrence) -> String? {
        occurrence.appointment.customerID.flatMap { id in customers.first { $0.id == id }?.name }
    }

    private func occurrences(from start: Date, days: Int) -> [AppointmentOccurrence] {
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        _ = stored.count  // depende de la consulta para redibujarse
        return (try? books.appointments(in: DateInterval(start: start, end: end), calendar: calendar)) ?? []
    }

    private var modePicker: some View {
        FilterPicker(title: String(localized: "Vista de la agenda"), options: Mode.allCases, selection: $mode, label: \.title)
    }

    private func link(_ occurrence: AppointmentOccurrence, trailing: String? = nil) -> some View {
        NavigationLink {
            AppointmentDetailView(key: occurrence.key)
        } label: {
            AppointmentRow(occurrence: occurrence, customerName: customerName(occurrence), trailing: trailing)
        }
    }

    // MARK: Día

    private var dayView: some View {
        let items = occurrences(from: day, days: 1).filter { $0.status != .cancelled }
        let firstHour = min(8, items.map { calendar.component(.hour, from: $0.start) }.min() ?? 8)
        let lastHour = max(19, items.map { calendar.component(.hour, from: $0.end) + (calendar.component(.minute, from: $0.end) > 0 ? 1 : 0) }.max() ?? 19)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                dayStepper(title: day.formatted(.appDateTime.weekday(.wide).day().month(.wide)).sentenceCased, unit: .day)
                if items.isEmpty {
                    Text("Sin citas este día").font(.subheadline).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                DayGrid(items: items, firstHour: firstHour, lastHour: min(24, lastHour), hourHeight: hourHeight,
                        isToday: calendar.isDateInToday(day), name: customerName)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
            .padReadingColumn()
        }
    }

    private func dayStepper(title: String, unit: Calendar.Component) -> some View {
        HStack {
            Button { step(unit, -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(unit == .day ? Text("Día anterior") : Text("Semana anterior"))
            Spacer()
            HStack(spacing: 8) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                if calendar.isDateInToday(day) && unit == .day {
                    Text("Hoy").font(.footnote.weight(.semibold)).foregroundStyle(Palette.brand)
                }
            }
            Spacer()
            Button { step(unit, 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(unit == .day ? Text("Día siguiente") : Text("Semana siguiente"))
        }
        .buttonStyle(.borderless)
        .frame(minHeight: Metrics.target)
    }

    private func step(_ unit: Calendar.Component, _ value: Int) {
        let amount = unit == .weekOfYear ? 7 * value : value
        withAnimation { day = calendar.date(byAdding: .day, value: amount, to: day) ?? day }
    }

    // MARK: Semana

    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day }

    private var weekView: some View {
        let week = occurrences(from: weekStart, days: 7)
        let selected = week.filter { calendar.isDate($0.start, inSameDayAs: day) }
        return List {
            Section {
                VStack(spacing: 10) {
                    modePicker
                    dayStepper(title: String(localized: "Semana del \(weekStart.dayMonth)"), unit: .weekOfYear)
                    WeekStrip(start: weekStart, selected: $day, counts: Dictionary(grouping: week) { calendar.startOfDay(for: $0.start) }.mapValues(\.count))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section(heading: day.formatted(.appDateTime.weekday(.wide).day().month(.wide)).sentenceCased) {
                if selected.isEmpty {
                    Text("Sin citas este día").foregroundStyle(Palette.ink2)
                    Button("Nueva cita") { creating = true }
                } else {
                    ForEach(selected) { link($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .padReadingList()
    }

    // MARK: Lista

    private var listView: some View {
        let today = calendar.startOfDay(for: .now)
        let past = (calendar.date(byAdding: .day, value: -90, to: today)).map { occurrences(from: $0, days: 90) } ?? []
        let pending = past.filter(\.isPendingInvoice) + occurrences(from: today, days: 1).filter { $0.isPendingInvoice }
        let upcoming = occurrences(from: today, days: 60).filter { $0.status == .scheduled }
        let days = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.start) }
        return List {
            Section { modePicker.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            if !pending.isEmpty {
                Section(heading: String(localized: "Por facturar · \(pending.count)")) {
                    ForEach(pending) { link($0, trailing: calendar.isDateInToday($0.start) ? String(localized: "Hoy") : $0.start.dayMonth) }
                }
            }
            ForEach(days.keys.sorted(), id: \.self) { date in
                Section(heading: (calendar.isDateInToday(date) ? String(localized: "Hoy · ") : "")
                        + date.formatted(.appDateTime.weekday(.wide).day().month(.wide)).sentenceCased) {
                    ForEach(days[date] ?? []) { link($0) }
                }
            }
            if upcoming.isEmpty && pending.isEmpty {
                Text("No hay citas próximas.").foregroundStyle(Palette.ink2)
            }
        }
        .scrollContentBackground(.hidden)
        .padReadingList()
    }

    // MARK: Vacía

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar").font(.system(size: 52)).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            Text("Tu agenda está vacía").font(.title3.bold()).foregroundStyle(Palette.ink)
            Text("Anota tus citas con los clientes. Cuando termines una, la conviertes en factura con un toque.")
                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center).frame(maxWidth: 320)
            Button { creating = true } label: { Label("Nueva cita", systemImage: "plus") }
                .buttonStyle(CompactPrimaryButtonStyle())
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Las franjas de un día (canvas `Agenda`, vista Día): una línea por hora y las citas como bloques; las que se pisan,
/// una al lado de la otra. Hoy, la línea roja de la hora actual.
private struct DayGrid: View {
    let items: [AppointmentOccurrence]
    let firstHour: Int
    let lastHour: Int
    let hourHeight: CGFloat
    let isToday: Bool
    let name: (AppointmentOccurrence) -> String?
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 58

    private var calendar: Calendar { .current }

    private func offset(_ date: Date) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return CGFloat((parts.hour ?? 0) - firstHour) * hourHeight + CGFloat(parts.minute ?? 0) / 60 * hourHeight
    }

    /// Carril de cada cita (0, 1…) y cuántos carriles tiene su grupo de citas que se pisan.
    private var lanes: [String: (lane: Int, of: Int)] {
        var result: [String: (Int, Int)] = [:]
        var group: [AppointmentOccurrence] = []
        var groupEnd = Date.distantPast
        var laneEnds: [Date] = []
        func close() {
            let count = max(1, laneEnds.count)
            for item in group { result[item.id] = (result[item.id]?.0 ?? 0, count) }
            group = []; laneEnds = []
        }
        for item in items.sorted(by: { $0.start < $1.start }) {
            if item.start >= groupEnd { close() }
            let lane = laneEnds.firstIndex { $0 <= item.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.end) } else { laneEnds[lane] = item.end }
            result[item.id] = (lane, 0)
            group.append(item)
            groupEnd = max(groupEnd, item.end)
        }
        close()
        return result
    }

    var body: some View {
        let hours = Array(firstHour..<lastHour)
        let lanes = self.lanes
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)?.formatted(.appDateTime.hour()) ?? "")
                            .font(.caption).foregroundStyle(Palette.ink2).monospacedDigit()
                            .frame(width: labelWidth, alignment: .trailing)
                            .offset(y: -7)
                        Rectangle().fill(Palette.separator).frame(height: 0.5)
                    }
                    .frame(height: hourHeight, alignment: .top)
                }
            }
            .accessibilityHidden(true)
            GeometryReader { proxy in
                let left = labelWidth + 8
                let width = proxy.size.width - left
                ForEach(items) { item in
                    let place = lanes[item.id] ?? (0, 1)
                    let laneWidth = width / CGFloat(max(1, place.of))
                    let height = max(CGFloat(item.appointment.durationMinutes) / 60 * hourHeight, 44)
                    NavigationLink {
                        AppointmentDetailView(key: item.key)
                    } label: {
                        block(item, tall: height >= hourHeight * 0.9)
                            .frame(width: laneWidth - 4, height: height - 3, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .offset(x: left + CGFloat(place.lane) * laneWidth, y: offset(item.start) + 1)
                }
                if isToday, (firstHour..<lastHour).contains(calendar.component(.hour, from: .now)) {
                    HStack(spacing: 0) {
                        Circle().fill(Palette.red).frame(width: 8, height: 8)
                        Rectangle().fill(Palette.red).frame(height: 1.5)
                    }
                    .frame(width: width + 4)
                    .offset(x: left - 4, y: offset(.now) - 4)
                    .accessibilityLabel(Text("Ahora: \(Date.now.formatted(.appDateTime.hour().minute()))"))
                }
            }
        }
        .frame(height: CGFloat(hours.count) * hourHeight)
    }

    private func block(_ item: AppointmentOccurrence, tall: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name(item) ?? item.appointment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                StatusChip(text: item.statusTitle, foreground: item.statusColor, compact: true, dot: item.statusDot)
            }
            if tall {
                Text(name(item) == nil ? item.timeRange : "\(item.appointment.title) · \(item.timeRange)")
                    .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(item.statusDot).frame(width: 3).padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Abre la cita"))
    }
}

/// Tira de los 7 días de una semana (canvas `AgendaSemana`, iPhone): día de la semana, número y un punto por cita.
private struct WeekStrip: View {
    let start: Date
    @Binding var selected: Date
    let counts: [Date: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let date = Calendar.current.date(byAdding: .day, value: index, to: start) ?? start
                let isOn = Calendar.current.isDate(date, inSameDayAs: selected)
                let count = counts[Calendar.current.startOfDay(for: date)] ?? 0
                Button { withAnimation { selected = Calendar.current.startOfDay(for: date) } } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.appDateTime.weekday(.narrow))).font(.caption2.weight(.semibold))
                        Text(date.formatted(.appDateTime.day())).font(.headline).monospacedDigit()
                        HStack(spacing: 2) {
                            ForEach(0..<min(count, 3), id: \.self) { _ in Circle().frame(width: 4, height: 4) }
                        }
                        .frame(height: 4)
                    }
                    .foregroundStyle(isOn ? Palette.onBrandFill : (Calendar.current.isDateInToday(date) ? Palette.brand : Palette.ink))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(isOn ? Palette.brandFill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(date.formatted(.appDateTime.weekday(.wide).day().month(.wide))), \(count) citas"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
