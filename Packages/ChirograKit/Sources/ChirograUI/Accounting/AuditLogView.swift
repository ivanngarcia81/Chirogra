import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Bitácora de cambios (1.2)
//
// Todo lo que cambió en los libros de la empresa, del más reciente al más antiguo: qué, cuándo, en qué aparato
// (decisión del usuario del 10-nov) y el antes y el después de cada campo. No se edita ni se borra. iPhone e iPad:
// lista por días con un detalle; Mac: tabla + inspector, como el diario. Sin canvas: se diseñó para la 1.2 con los
// componentes de siempre.

/// Filtro de la bitácora por área.
enum AuditLogFilter: String, CaseIterable, Hashable {
    case all = "Todo"
    case sales = "Ventas"
    case expenses = "Gastos"
    case banking = "Banca"
    case accounting = "Contabilidad"
    case company = "Empresa"
    case deletions = "Borrados"

    func matches(_ event: AuditEvent) -> Bool {
        switch self {
        case .all: true
        case .deletions: event.isDeletion || event.action == "void"
        default: event.subject?.area == self
        }
    }
}

extension AuditSubject {
    var title: String {
        switch self {
        case .company: String(localized: "Empresa")
        case .account: String(localized: "Cuenta")
        case .journalEntry: String(localized: "Asiento")
        case .customer: String(localized: "Cliente")
        case .vendor: String(localized: "Proveedor")
        case .item: String(localized: "Artículo")
        case .invoice: String(localized: "Factura")
        case .estimate: String(localized: "Estimado")
        case .bill: String(localized: "Factura de proveedor")
        case .billPayment: String(localized: "Pago a proveedor")
        case .expense: String(localized: "Gasto")
        case .attachment: String(localized: "Recibo")
        case .taxRate: String(localized: "Tasa de impuesto")
        case .taxGroup: String(localized: "Impuesto combinado")
        case .recurringTemplate: String(localized: "Recurrente")
        case .bankTransaction: String(localized: "Movimiento del banco")
        case .bankRule: String(localized: "Regla del banco")
        case .reconciliation: String(localized: "Conciliación")
        case .budget: String(localized: "Presupuesto")
        case .backup: String(localized: "Copia de seguridad")
        }
    }

    var systemImage: String {
        switch self {
        case .company: "building.2"
        case .account: "list.bullet.indent"
        case .journalEntry: "doc.plaintext"
        case .customer: "person"
        case .vendor: "shippingbox"
        case .item: "tag"
        case .invoice, .estimate: "doc.text"
        case .bill, .billPayment: "doc.text.below.ecg"
        case .expense: "creditcard"
        case .attachment: "paperclip"
        case .taxRate, .taxGroup: "percent"
        case .recurringTemplate: "arrow.triangle.2.circlepath"
        case .bankTransaction, .bankRule, .reconciliation: "building.columns"
        case .budget: "chart.bar"
        case .backup: "externaldrive"
        }
    }

    var color: Color {
        switch area {
        case .sales: Palette.blue
        case .expenses: Palette.orange
        case .banking: Palette.teal
        case .accounting: Palette.indigo
        default: Palette.gray
        }
    }

    var area: AuditLogFilter {
        switch self {
        case .customer, .item, .invoice, .estimate: .sales
        case .vendor, .bill, .billPayment, .expense, .attachment, .recurringTemplate: .expenses
        case .bankTransaction, .bankRule, .reconciliation: .banking
        case .account, .journalEntry, .budget: .accounting
        case .company, .taxRate, .taxGroup, .backup: .company
        }
    }
}

extension AuditEvent {
    /// Qué se hizo, en pocas palabras.
    var actionTitle: String {
        switch action {
        case "create": String(localized: "Alta")
        case "update", "edit", "editText": String(localized: "Edición")
        case "delete": String(localized: "Borrado")
        case "void": String(localized: "Anulación")
        case "post": String(localized: "Registro")
        case "ignore": String(localized: "Exclusión")
        case "returnToInbox": String(localized: "Devuelto a la bandeja")
        case "categorize": String(localized: "Registro")
        case "match": String(localized: "Emparejado")
        case "import": String(localized: "Importación")
        case "archive": String(localized: "Archivado")
        case "unarchive": String(localized: "Restaurado")
        case "restore": String(localized: "Restauración")
        default: String(localized: "Cambio")
        }
    }

    var subjectTitle: String { subject?.title ?? subjectEntity }
    var deviceTitle: String { device.isEmpty ? "—" : device }
    var timeTitle: String { date.formatted(.appDateTime.hour().minute()) }
    /// Para la tabla del Mac: «10 nov, 7:49 p.m.» (el año, en el inspector).
    var shortDateTimeTitle: String { date.formatted(.appDateTime.day().month(.abbreviated).hour().minute()) }
    var dateTimeTitle: String { date.formatted(.appDateTime.day().month(.abbreviated).year().hour().minute()) }

    func matches(_ text: String) -> Bool {
        text.isEmpty || summary.localizedStandardContains(text) || changeDetails.localizedStandardContains(text)
            || subjectTitle.localizedStandardContains(text) || device.localizedStandardContains(text)
    }
}

/// La bitácora: iPhone e iPad, lista por días; Mac, tabla con inspector.
struct AuditLogView: View {
    @CompanyQuery(sort: [SortDescriptor(\AuditEvent.date, order: .reverse)]) private var events: [AuditEvent]
    @State private var filter: AuditLogFilter = .all
    @State private var query = ""
    #if os(macOS)
    @State private var selection: UUID?
    #endif

    private var shown: [AuditEvent] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return events.filter { filter.matches($0) && $0.matches(text) }
    }

    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            #if os(macOS)
            macTable
            #else
            list
            #endif
        }
        #if DEBUG
        .task {
            QAAuditLog.makeSampleChanges(in: context)
            #if os(macOS)
            // `-qa.fila N` elige la fila N (la tabla aplica la suya antes de que haya filas).
            try? await Task.sleep(for: .milliseconds(300))
            if UserDefaults.standard.object(forKey: "qa.fila") != nil {
                let index = UserDefaults.standard.integer(forKey: "qa.fila")
                if shown.indices.contains(index) { selection = shown[index].id }
            }
            #endif
        }
        #endif
    }

    // MARK: iPhone e iPad

    #if os(iOS)
    private var list: some View {
        let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.date) }
        return List {
            Section {
                FilterPicker(title: String(localized: "Filtrar"), options: AuditLogFilter.allCases, selection: $filter, label: \.localizedTitle)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Cada cambio de tus libros, con la fecha y el aparato en que se hizo. La bitácora no se puede editar ni borrar.")
            }
            if shown.isEmpty {
                Text(events.isEmpty ? String(localized: "Aún no hay cambios.") : String(localized: "Ningún cambio coincide con la búsqueda o el filtro."))
                    .foregroundStyle(Palette.ink2)
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(days[day] ?? []) { event in
                        NavigationLink { AuditEventDetailView(event: event) } label: { AuditEventRow(event: event) }
                    }
                } header: {
                    SectionLabel(text: Self.dayTitle(day))
                }
            }
        }
        .groupedList()
        .screenBackground()
        .searchable(text: $query, prompt: Text("Buscar en la bitácora"))
        .navigationTitle("Bitácora de cambios")
        .inlineTitle()
    }
    #endif

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Hoy") }
        if calendar.isDateInYesterday(day) { return String(localized: "Ayer") }
        return day.formatted(.appDateTime.weekday(.wide).day().month(.wide).year())
    }

    // MARK: Mac

    #if os(macOS)
    private var macTable: some View {
        MacTablePage(
            title: String(localized: "Bitácora de cambios"),
            subtitle: String(localized: "Contabilidad · \(events.count) cambios"),
            rows: shown,
            footer: shown.count == events.count ? String(localized: "\(events.count) cambios") : String(localized: "\(shown.count) de \(events.count) cambios"),
            query: $query, searchPrompt: Text("Cambio, cuenta, cliente o aparato"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\AuditEvent.date, order: .reverse)],
            addTitle: "", onAdd: {},
            empty: events.isEmpty
                ? MacTableEmpty(systemImage: "clock.arrow.circlepath", title: String(localized: "Aún no hay cambios"),
                                message: String(localized: "Aquí verás cada cambio de tus libros, con la fecha y el aparato en que se hizo."))
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ningún cambio coincide con la búsqueda o el filtro."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { _ in String(localized: "Cambio") },
            inspectorPlaceholder: String(localized: "Selecciona un cambio para ver el detalle.")
        ) {
            TableColumn("Fecha", value: \.date) { event in
                MacCellText(text: event.shortDateTimeTitle)
            }
            .width(min: 100, ideal: 118, max: 160)
            TableColumn("Qué", value: \.subjectEntity) { event in
                MacCellText(text: event.subjectTitle)
            }
            // «Movimiento del banco» y «Factura de proveedor» enteros (QA del 11-nov).
            .width(min: 110, ideal: 150, max: 200)
            TableColumn("Cambio", value: \.summary) { event in
                Text(event.summary).lineLimit(1)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Aparato", value: \.device) { event in
                MacCellText(text: event.deviceTitle)
            }
            .width(min: 80, ideal: 120, max: 200)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar por área"), options: AuditLogFilter.allCases,
                           selection: $filter, label: \.localizedTitle) { option in
                events.filter(option.matches).count
            }
        } inspector: { event in
            AuditEventInspector(event: event)
        } actions: { _ in
            EmptyView()
        }
    }
    #endif
}

/// Fila de la bitácora: icono del área, el resumen y «10:42 · iPhone».
struct AuditEventRow: View {
    let event: AuditEvent

    var body: some View {
        LedgerRow(title: event.summary.isEmpty ? event.actionTitle : event.summary,
                  // El icono dice el área; «Movimiento del banco» no cabía junto al aparato.
                  subtitle: [event.timeTitle, event.device].filter { !$0.isEmpty }.joined(separator: " · "),
                  titleLines: 2) {
            IconTile(systemImage: event.isDeletion ? "trash" : (event.subject?.systemImage ?? "clock"),
                     foreground: event.isDeletion ? Palette.red : (event.subject?.color ?? Palette.gray))
        } trailing: {
            EmptyView()
        }
    }
}

/// Un cambio de la bitácora: qué, cuándo, en qué aparato y el antes y el después de cada campo.
struct AuditEventDetailView: View {
    let event: AuditEvent

    var body: some View {
        Form {
            Section {
                Text(event.summary.isEmpty ? event.actionTitle : event.summary)
                    .font(.headline).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Qué", value: event.subjectTitle)
                LabeledContent("Acción", value: event.actionTitle)
                LabeledContent("Fecha", value: event.dateTimeTitle)
                LabeledContent("Aparato", value: event.deviceTitle)
            }
            if !event.detailLines.isEmpty {
                Section {
                    ForEach(Array(event.detailLines.enumerated()), id: \.offset) { _, line in
                        Text(line).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    SectionLabel(text: event.isDeletion ? String(localized: "Lo que tenía") : String(localized: "Cambios"))
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(event.actionTitle)
        .inlineTitle()
    }
}

#if os(macOS)
/// Inspector de la bitácora en el Mac.
private struct AuditEventInspector: View {
    let event: AuditEvent

    var body: some View {
        MacInspectorSection(title: event.actionTitle) {
            Text(event.summary).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            MacInspectorRow(String(localized: "Qué"), value: event.subjectTitle)
            MacInspectorRow(String(localized: "Fecha"), value: event.dateTimeTitle)
            MacInspectorRow(String(localized: "Aparato"), value: event.deviceTitle)
        }
        if !event.detailLines.isEmpty {
            MacInspectorSection(title: event.isDeletion ? String(localized: "Lo que tenía") : String(localized: "Cambios")) {
                ForEach(Array(event.detailLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.subheadline).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
#endif

#if DEBUG
/// `-qa.bitacoraMuestra 1`: sobre los datos de ejemplo, edita un cliente y excluye un movimiento con motivo, para ver la
/// bitácora con detalle. Solo una vez por arranque.
enum QAAuditLog {
    private static var done = false

    static func makeSampleChanges(in context: ModelContext) {
        guard !done, UserDefaults.standard.bool(forKey: "qa.bitacoraMuestra") else { return }
        done = true
        let books = Bookkeeper(context: context)
        if let customer = try? context.fetch(FetchDescriptor<Customer>()).first {
            let before = AuditSnapshot(customer)
            customer.email = "pagos@" + (customer.email.split(separator: "@").last.map(String.init) ?? "ejemplo.com")
            customer.paymentTermsDays = 15
            books.logSave(.customer, id: customer.id, name: customer.name, before: before, after: AuditSnapshot(customer))
            try? context.save()
        }
        if let pending = try? books.bankInbox().first {
            try? books.ignore(pending, reason: BankExclusionReason.duplicate.localizedTitle)
        }
    }
}
#endif
