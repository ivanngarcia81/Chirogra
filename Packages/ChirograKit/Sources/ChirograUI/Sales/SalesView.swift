import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ventas (canvas `Ventas`, `Clientes`): título grande con el menú de sección debajo (Facturas ·
/// Clientes; Estimados, Recibos, Pagos y Productos son de fase 2), búsqueda del sistema y, en Facturas, el botón de
/// filtro de la barra junto a «+». Es la pantalla del iPhone (y del iPad con la columna estrecha o AX4); en iPad y Mac,
/// Facturas y Clientes van con columna maestro (`MasterPage`).
struct SalesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case invoices = "Facturas"
        case customers = "Clientes"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .invoices: "doc.text"
            case .customers: "person.2"
            }
        }
    }

    /// Desde la barra lateral o un enlace, la subsección ya elegida y sin menú de sección.
    var fixedSegment: Segment? = nil

    @State private var selectedSegment: Segment = .invoices
    @State private var showingEditor = false
    @State private var query = ""
    @State private var filter: InvoiceListView.Filter = .all
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]

    private var segment: Segment { fixedSegment ?? selectedSegment }
    private var sectionMenu: SalesSectionMenu? { fixedSegment == nil ? SalesSectionMenu(selection: $selectedSegment) : nil }

    var body: some View {
        Group {
            switch segment {
            case .invoices: InvoiceListView(query: $query, filter: $filter, sectionMenu: sectionMenu) { showingEditor = true }
            case .customers: CustomerListView(query: query, sectionMenu: sectionMenu) { showingEditor = true }
            }
        }
        .background(Palette.background)
        .navigationTitle(fixedSegment == .customers ? "Clientes" : "Ventas")
        .headerTitle()
        // Una sola búsqueda en el contenedor y siempre visible: puesta en cada lista, desaparecía al volver de
        // una factura, porque la barra ya no encontraba la lista.
        .modifier(SalesSearch(query: $query,
                              prompt: segment == .invoices ? Text("Cliente, número o monto") : Text("Nombre, correo o teléfono")))
        .toolbar {
            // Canvas `Ventas`: filtro y «+» en un mismo grupo de vidrio.
            ToolbarItemGroup(placement: .primaryAction) {
                if segment == .invoices {
                    FilterMenu(options: InvoiceListView.Filter.allCases, selection: $filter, label: \.localizedTitle) { option in
                        invoices.filter(option.matches).count
                    }
                    .accessibilityLabel("Filtrar por estado")
                }
                AddButton(title: segment == .invoices ? "Nueva factura" : "Nuevo cliente") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                if segment == .invoices { InvoiceEditorView() } else { CustomerEditorView() }
            }
            .editorSheetSizing()
        }
    }
}

/// Menú de sección bajo el título (canvas `Ventas`: «Facturas ▾», gris, que abre Facturas · Clientes). Va al principio
/// de la lista: el título grande del sistema no admite un subtítulo con menú (con `toolbarTitleMenu` el título pasaba
/// a ir en línea, y con título grande el menú no se podía abrir).
struct SalesSectionMenu: View {
    @Binding var selection: SalesView.Segment

    var body: some View {
        Menu {
            Picker("Sección", selection: $selection) {
                ForEach(SalesView.Segment.allCases) { Label($0.localizedTitle, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(selection.localizedTitle)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink2)
            // Toda la fila abre el menú: en una lista, el toque fuera del texto no lo abría.
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sección")
        .accessibilityValue(selection.localizedTitle)
    }
}

extension View {
    /// `listSectionSpacing` del iPhone y el iPad (en el Mac no existe).
    @ViewBuilder
    func compactSectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(iOS)
        listSectionSpacing(spacing)
        #else
        self
        #endif
    }

    /// Fila del menú de sección: sin fondo y alineada con el título.
    func sectionMenuRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

struct InvoiceListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todas", draft = "Borrador", sent = "Enviada", partial = "Pago parcial", overdue = "Vencida", paid = "Pagada"
        var id: String { rawValue }

        func matches(_ invoice: Invoice) -> Bool {
            switch self {
            case .all: true
            case .draft: invoice.status == .draft
            case .sent: invoice.status == .sent && invoice.daysOverdue() == nil
            case .partial: invoice.status == .partiallyPaid && invoice.daysOverdue() == nil
            case .overdue: invoice.daysOverdue() != nil
            case .paid: invoice.status == .paid
            }
        }
    }

    /// Texto de la búsqueda de Ventas (`SalesView`).
    @Binding var query: String
    /// Filtro del botón de la barra (`SalesView`).
    @Binding var filter: Filter
    /// «Nueva factura» del estado vacío.
    var onCreate: () -> Void = {}
    /// «Facturas ▾» del iPhone (`SalesView`).
    var sectionMenu: SalesSectionMenu?
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]

    init(query: Binding<String>, filter: Binding<Filter> = .constant(.all), sectionMenu: SalesSectionMenu? = nil,
         onCreate: @escaping () -> Void = {}) {
        _query = query
        _filter = filter
        self.sectionMenu = sectionMenu
        self.onCreate = onCreate
    }

    private var filtered: [Invoice] {
        // Sin distinguir mayúsculas ni tildes: «clinica» encuentra «Clínica Del Valle».
        let text = query.trimmingCharacters(in: .whitespaces)
        return invoices.filter { invoice in
            filter.matches(invoice) && (text.isEmpty
                || invoice.number.localizedStandardContains(text)
                || (invoice.customer?.name.localizedStandardContains(text) ?? false)
                || invoice.total.money.contains(text))
        }
    }

    private var receivable: Int64 { invoices.filter(\.isOpen).reduce(0) { $0 + $1.balanceDue } }

    var body: some View {
        List {
            if let sectionMenu {
                // Pegado al título: sin el espacio entre grupos.
                Section { sectionMenu.sectionMenuRow() }.compactSectionSpacing(0)
            }
            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filtered) { invoice in
                        NavigationLink { InvoiceDetailView(invoice: invoice) } label: { InvoiceRow(invoice: invoice) }
                    }
                } header: {
                    summary
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        // El menú de sección, justo debajo del buscador.
        .contentMargins(.top, 4, for: .scrollContent)
    }

    /// «5 facturas · Vencida» y «Por cobrar $10,050.00» sobre el grupo (canvas `Ventas`).
    private var summary: some View {
        let count = filter == .all ? Text("\(filtered.count) facturas")   // singular y plural en el catálogo
            : Text("\(filtered.count) facturas") + Text(verbatim: " · ") + Text(filter.localizedTitle)
        let total = Text("Por cobrar \(receivable.money)")
        return ViewThatFits(in: .horizontal) {
            HStack {
                count.fixedSize()
                Spacer(minLength: 8)
                total.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                count
                total
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .monospacedDigit()
        .textCase(nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        if invoices.isEmpty {
            ContentUnavailableView {
                Label("Todavía no hay facturas", systemImage: "doc.text")
            } description: {
                Text("Crea tu primera factura con el botón +.")
            } actions: {
                Button("Nueva factura", action: onCreate).buttonStyle(.primaryCompact)
            }
        } else {
            // Canvas `Ventas`: «Sin resultados» con «Quitar filtros» en la cápsula gris.
            ContentUnavailableView {
                Label("Sin resultados", systemImage: "magnifyingglass")
            } description: {
                Text("Prueba con otro cliente, número o estado.")
            } actions: {
                Button("Quitar filtros") {
                    query = ""
                    filter = .all
                }
                .buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            }
        }
    }
}

/// Fila de factura del canvas `Ventas`: cliente y «F-1047 · vence 12 nov» a la izquierda; importe y estado a la
/// derecha. Sin monograma (el canvas no lo pone); el chevron lo pone la lista.
struct InvoiceRow: View {
    let invoice: Invoice
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: invoice.customer?.name ?? String(localized: "Sin cliente"), subtitle: subtitle) {
            EmptyView()
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                Text(amount).font(.body).monospacedDigit().foregroundStyle(Palette.ink)
                StatusChip(invoice: invoice)
            }
        }
    }

    private var amount: String {
        switch invoice.status {
        case .draft: invoice.draftAmount.money
        // «$850.00 de $1,450», como en el canvas.
        case .partiallyPaid: String(localized: "\(invoice.balanceDue.money) de \(invoice.total.moneyWhole)")
        default: invoice.total.money
        }
    }

    private var subtitle: String {
        let number = invoice.number.isEmpty ? String(localized: "Sin número") : invoice.number
        switch invoice.status {
        case .draft:
            return Calendar.current.isDateInToday(invoice.createdAt) ? String(localized: "\(number) · creada hoy")
                : String(localized: "\(number) · creada \(invoice.createdAt.dayMonth)")
        case .paid:
            let paid = (invoice.paymentApplications ?? []).compactMap(\.payment?.date).max()
            return paid.map { String(localized: "\(number) · pagada \($0.dayMonth)") } ?? String(localized: "\(number) · pagada")
        case .void:
            return String(localized: "\(number) · anulada")
        case .partiallyPaid, .sent:
            if invoice.daysOverdue() != nil { return String(localized: "\(number) · venció \(invoice.dueDate.dayMonth)") }
            return "\(number) · \(invoice.dueDate.dueLabel)"
        }
    }
}

#Preview {
    NavigationStack { SalesView() }.modelContainer(SampleData.makeContainer())
}

/// Búsqueda de la barra de navegación, siempre a la vista.
private struct SalesSearch: ViewModifier {
    @Binding var query: String
    let prompt: Text

    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        content.searchable(text: $query, prompt: prompt)
        #endif
    }
}
