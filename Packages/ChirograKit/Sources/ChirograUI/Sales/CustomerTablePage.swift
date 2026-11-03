#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Clientes como tabla + inspector (canvas `MacClientes`). Arriba el segmentado Todos · Con saldo · Vencidos y la
/// tabla Cliente (monograma y nombre) · Contacto · Abiertas · Vencido · Saldo · Estado. El inspector muestra el cliente
/// elegido (monograma, nombre y contacto; Saldo; Contacto) con «Abrir ficha», «Nueva factura» y «Editar». Doble clic o
/// «Abrir ficha» abre la ficha completa (`CustomerDetailView`, canvas `MacClienteFicha`).
struct CustomerTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var filter: CustomerListView.Filter = .all
    @State private var query = ""
    @State private var creating = false
    @State private var editing: Customer?
    @State private var invoicing: Customer?
    @State private var openedCustomer: Customer?

    /// Los archivados no salen, como en la lista del iPhone y la columna maestro.
    private var active: [Customer] { customers.filter { !$0.isArchived } }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ customer: Customer, _ filter: CustomerListView.Filter) -> Bool {
        switch filter {
        case .all: true
        case .withBalance: customer.openBalance > 0
        case .overdue: customer.tableOverdue > 0
        }
    }

    private var filtered: [Customer] {
        let text = trimmedQuery
        return active.filter { customer in
            matches(customer, filter) && (text.isEmpty
                || customer.name.localizedStandardContains(text)
                || customer.email.localizedStandardContains(text)
                || customer.phone.contains(text))
        }
    }

    private var footer: String {
        filtered.count == active.count ? String(localized: "\(active.count) clientes")
            : String(localized: "\(filtered.count) de \(active.count) clientes")
    }

    /// Canvas: «9 clientes · saldo total $10,050.00» (en dos textos: «%lld clientes» ya tiene sus plurales).
    private var subtitle: String {
        let total = active.reduce(0) { $0 + $1.openBalance }
        return String(localized: "\(active.count) clientes") + " · " + String(localized: "saldo total \(total.money)")
    }

    private var empty: MacTableEmpty {
        if active.isEmpty {
            return MacTableEmpty(systemImage: "person.2", title: String(localized: "Sin clientes todavía"),
                                 message: String(localized: "Añade tu primer cliente para empezar a facturar."),
                                 actionTitle: String(localized: "Nuevo cliente"), action: { creating = true })
        }
        let text = trimmedQuery
        return MacTableEmpty(title: String(localized: "Sin resultados"),
                             message: text.isEmpty ? String(localized: "Ningún cliente coincide con el filtro.")
                                 : String(localized: "Ningún cliente coincide con «\(text)»."),
                             actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all })
    }

    var body: some View {
        MacTablePage(
            title: String(localized: "Clientes"),
            subtitle: subtitle,
            rows: filtered, footer: footer,
            query: $query, searchPrompt: Text("Nombre, correo o teléfono"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\Customer.tableName)],
            addTitle: String(localized: "Nuevo cliente"), onAdd: { creating = true },
            onOpen: { openedCustomer = $0 },
            empty: empty,
            inspectorTitle: { _ in String(localized: "Cliente") },
            inspectorPlaceholder: String(localized: "Selecciona un cliente para ver su saldo.")
        ) {
            TableColumn("Cliente", value: \.tableName) { customer in
                HStack(spacing: 8) {
                    CustomerMonogram(initials: customer.initials, side: 20)
                    Text(customer.name).lineLimit(1)
                }
            }
            .width(min: 120, ideal: 150)
            TableColumn("Contacto", value: \.tableContact) { customer in
                MacCellText(text: customer.tableContact.isEmpty ? "—" : customer.tableContact).lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Abiertas", value: \.tableOpenCount) { customer in
                MacCellText(text: customer.tableOpenCount == 0 ? "—" : "\(customer.tableOpenCount)").monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 80)
            .alignment(.trailing)
            TableColumn("Vencido", value: \.tableOverdue) { customer in
                let late = customer.tableOverdue
                MacCellText(text: late == 0 ? "—" : late.money, color: late > 0 ? Palette.negative : Palette.ink2)
                    .monospacedDigit()
            }
            .width(min: 64, ideal: 80, max: 130)
            .alignment(.trailing)
            TableColumn("Saldo", value: \.openBalance) { customer in
                Text(customer.openBalance.money).monospacedDigit()
            }
            .width(min: 72, ideal: 86, max: 140)
            .alignment(.trailing)
            TableColumn("Estado", value: \.tableStatusRank) { customer in
                MacCellStatus(chip: customer.tableStatus)
            }
            .width(min: 76, ideal: 84, max: 160)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar clientes"), options: CustomerListView.Filter.allCases,
                           selection: $filter, label: \.localizedTitle)
        } inspector: { customer in
            CustomerInspector(customer: customer)
        } actions: { customer in
            Button("Abrir ficha") { openedCustomer = customer }.buttonStyle(.primary)
            HStack(spacing: 8) {
                Button("Nueva factura") { invoicing = customer }.buttonStyle(.secondary)
                Button("Editar") { editing = customer }.buttonStyle(.secondary)
            }
        }
        .sheet(isPresented: $creating) {
            // El cliente nuevo queda elegido en la tabla y en el inspector.
            NavigationStack { CustomerEditorView { selection = $0.id } }.editorSheetSizing()
        }
        .sheet(item: $editing) { customer in NavigationStack { CustomerEditorView(customer: customer) }.editorSheetSizing() }
        .sheet(item: $invoicing) { customer in
            NavigationStack { InvoiceEditorView(preselectedCustomer: customer) }.editorSheetSizing()
        }
        .navigationDestination(item: $openedCustomer) { CustomerDetailView(customer: $0) }
        #if DEBUG
        // `-qa.buscar <texto>` y `-qa.filtro todos|saldo|vencidos` para ver la búsqueda y el estado vacío;
        // `-qa.abrir 1` abre la ficha de la fila elegida con `-qa.fila`.
        .task {
            let defaults = UserDefaults.standard
            if let text = defaults.string(forKey: "qa.buscar") { query = text }
            switch defaults.string(forKey: "qa.filtro") {
            case "saldo": filter = .withBalance
            case "vencidos": filter = .overdue
            default: break
            }
            try? await Task.sleep(for: .seconds(1))
            if defaults.bool(forKey: "qa.nuevo") { creating = true; return }
            guard let id = selection, let customer = customers.first(where: { $0.id == id }) else { return }
            if defaults.bool(forKey: "qa.abrir") { openedCustomer = customer }
        }
        #endif
    }
}

/// Inspector del cliente (canvas `MacClientes`): monograma de 48, nombre y contacto en Tinta; Saldo (Facturas
/// abiertas, Vencido, Saldo pendiente, Estado y, si lo hay, Saldo a favor) y Contacto (Correo y Teléfono).
private struct CustomerInspector: View {
    let customer: Customer
    @Environment(\.openURL) private var openURL

    private var emailURL: URL? { customer.email.isEmpty ? nil : URL(string: "mailto:\(customer.email)") }

    var body: some View {
        header
        MacInspectorSection(title: String(localized: "Saldo")) {
            MacInspectorRow(String(localized: "Facturas abiertas"), value: "\(customer.tableOpenCount)")
            MacInspectorRow(String(localized: "Vencido"), value: customer.tableOverdue.money,
                            color: customer.tableOverdue > 0 ? Palette.negative : Palette.ink)
            MacInspectorRow(String(localized: "Saldo pendiente"), value: customer.openBalance.money, bold: true)
            if customer.creditBalance > 0 {
                MacInspectorRow(String(localized: "Saldo a favor"), value: customer.creditBalance.money, color: Palette.positive)
            }
            MacInspectorRow(label: String(localized: "Estado")) { customer.tableStatus }
        }
        MacInspectorSection(title: String(localized: "Contacto")) {
            MacInspectorRow(label: String(localized: "Correo")) {
                if let emailURL {
                    Button(customer.email) { openURL(emailURL) }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(verbatim: "—").foregroundStyle(Palette.ink2)
                }
            }
            if !customer.phone.isEmpty {
                MacInspectorRow(String(localized: "Teléfono"), value: customer.phone)
            }
        }
    }

    /// Monograma de 48, nombre (17 bold) y contacto (11, en Tinta).
    private var header: some View {
        HStack(spacing: 12) {
            CustomerMonogram(initials: customer.initials, side: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(customer.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if !customer.tableContact.isEmpty {
                    Text(customer.tableContact)
                        .font(.subheadline)
                        .foregroundStyle(customer.email.isEmpty ? Palette.ink2 : Palette.brand)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monograma gris redondo (canvas: 20 pt en la fila, 48 en el inspector), con el tamaño de letra de Accesibilidad.
/// Pieza propia de esta página: `InitialsTile` tiene un solo tamaño (`Metrics.avatar`).
private struct CustomerMonogram: View {
    let initials: String
    @ScaledMetric private var side: CGFloat

    init(initials: String, side: CGFloat) {
        self.initials = initials
        _side = ScaledMetric(wrappedValue: side, relativeTo: .body)
    }

    var body: some View {
        Text(initials)
            .font(.system(size: side * 0.42, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            .background(Palette.monogram, in: Circle())
            .accessibilityHidden(true)
    }
}

extension Customer {
    /// Claves de orden y valores de la tabla del Mac (`nonisolated` para `KeyPathComparator`).
    nonisolated var tableName: String { name }
    /// Contacto de la fila: el correo o, si no hay, el teléfono.
    nonisolated var tableContact: String { email.isEmpty ? phone : email }
    /// Facturas emitidas con saldo pendiente (columna «Abiertas»).
    nonisolated var tableOpenCount: Int { (invoices ?? []).filter { $0.isOpen && $0.balanceDue > 0 }.count }
    /// Saldo de las facturas abiertas ya vencidas (`overdueBalance`, sin aislar).
    nonisolated var tableOverdue: Int64 {
        (invoices ?? []).filter { $0.isOpen && $0.daysOverdue() != nil }.reduce(0) { $0 + $1.balanceDue }
    }
    /// Orden de los estados al ordenar por «Estado»: Vencido, Al día, Sin saldo.
    nonisolated var tableStatusRank: Int { tableOverdue > 0 ? 0 : openBalance > 0 ? 1 : 2 }

    /// Estado de la fila (canvas `MacClientes`): «● Vencido» en rojo, «● Al día» en verde o «● Sin saldo» en gris.
    var tableStatus: StatusChip {
        if tableOverdue > 0 {
            return StatusChip(text: String(localized: "Vencido"), foreground: Palette.negative, background: .clear,
                              compact: true, dot: Palette.red)
        }
        if openBalance > 0 {
            return StatusChip(text: String(localized: "Al día"), foreground: Palette.positive, background: .clear,
                              compact: true, dot: Palette.green)
        }
        return StatusChip(text: String(localized: "Sin saldo"), foreground: Palette.ink2, background: .clear,
                          compact: true, dot: Palette.gray)
    }
}
#endif
