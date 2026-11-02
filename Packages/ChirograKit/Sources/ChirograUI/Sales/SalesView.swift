import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ventas (canvas: `Ventas`, `Clientes`): facturas con búsqueda y filtros por estado, y clientes. Es la pantalla del
/// iPhone (y del iPad con AX4 o más); en iPad y Mac, Facturas y Clientes van con columna maestro (`MasterPage`).
struct SalesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case invoices = "Facturas"
        case customers = "Clientes"
        var id: String { rawValue }
    }

    /// Desde la barra lateral o un enlace, la subsección ya elegida y sin pestañas.
    var fixedSegment: Segment? = nil

    @State private var selectedSegment: Segment = .invoices
    @State private var showingEditor = false
    @State private var query = ""

    private var segment: Segment { fixedSegment ?? selectedSegment }

    var body: some View {
        VStack(spacing: 0) {
            if fixedSegment == nil {
                UnderlineTabs(options: Segment.allCases, selection: $selectedSegment) { $0.localizedTitle }
            }

            switch segment {
            case .invoices: InvoiceListView(query: $query)
            case .customers: CustomerListView(query: query)
            }
        }
        .background(Palette.background)
        .navigationTitle(fixedSegment != nil && segment == .customers ? "Clientes" : "Ventas")
        .headerTitle()
        // Una sola búsqueda en el contenedor y siempre visible: puesta en cada lista, desaparecía al volver de
        // una factura, porque la barra ya no encontraba la lista debajo de las pestañas.
        .modifier(SalesSearch(query: $query,
                              prompt: segment == .invoices ? Text("Cliente, número o monto") : Text("Nombre, correo o teléfono")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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

struct InvoiceListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todas", draft = "Borrador", sent = "Enviada", partial = "Pago parcial", overdue = "Vencida", paid = "Pagada"
        var id: String { rawValue }

        func matches(_ invoice: Invoice) -> Bool {
            switch self {
            case .all: true
            case .draft: invoice.status == .draft
            case .sent: invoice.status == .sent && invoice.daysOverdue() == nil
            case .partial: invoice.status == .partiallyPaid
            case .overdue: invoice.daysOverdue() != nil
            case .paid: invoice.status == .paid
            }
        }
    }

    /// Texto de la búsqueda de Ventas (`SalesView`).
    @Binding var query: String
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @State private var filter: Filter = .all

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

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in
                            let count = invoices.filter(option.matches).count
                            FilterChip(title: option.localizedTitle, count: count, isSelected: filter == option) { filter = option }
                                .accessibilityHint("Filtra la lista de facturas")
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                let count = Text("\(filtered.count) facturas")   // singular y plural en el catálogo
                let receivable = Text("Por cobrar \(Text(invoices.filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }.money).bold())")
                ViewThatFits(in: .horizontal) {
                    HStack {
                        count.fixedSize()
                        Spacer()
                        receivable.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        count
                        receivable
                    }
                }
            }

            if filtered.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: invoices.isEmpty ? String(localized: "Todavía no hay facturas") : String(localized: "Sin resultados"),
                               message: invoices.isEmpty ? String(localized: "Crea tu primera factura con el botón +.") : String(localized: "Prueba con otro cliente, número o estado."),
                               actionTitle: invoices.isEmpty ? nil : String(localized: "Quitar filtros")) {
                    query = ""
                    filter = .all
                }
                .listRowBackground(Palette.surface)
            } else {
                Section {
                    ForEach(filtered) { invoice in
                        NavigationLink { InvoiceDetailView(invoice: invoice) } label: { InvoiceRow(invoice: invoice) }
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        // Sin el margen superior de la lista: los chips van justo debajo de las pestañas, como en el canvas.
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

struct InvoiceRow: View {
    let invoice: Invoice
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: invoice.customer?.name ?? String(localized: "Sin cliente"), subtitle: subtitle) {
            InitialsTile(text: invoice.customer?.initials ?? "?", foreground: Palette.ink2, background: Palette.surface2)
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text(amount).font(.body.weight(.semibold)).monospacedDigit()
                if invoice.status == .partiallyPaid {
                    Text("de \(invoice.total.money)").font(.caption).foregroundStyle(Palette.ink3).monospacedDigit()
                }
                StatusChip(invoice: invoice)
            }
        }
    }

    private var amount: String {
        switch invoice.status {
        case .draft: invoice.draftAmount.money
        case .partiallyPaid: invoice.balanceDue.money
        default: invoice.total.money
        }
    }

    private var subtitle: String {
        let number = invoice.number.isEmpty ? String(localized: "Sin número") : invoice.number
        switch invoice.status {
        case .draft: return String(localized: "\(number) · borrador")
        case .paid: return String(localized: "\(number) · pagada")
        case .void: return String(localized: "\(number) · anulada")
        case .partiallyPaid, .sent: return "\(number) · \(invoice.dueDate.dueLabel)"
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
