import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ventas (canvas: `Ventas`, `Clientes`): facturas con búsqueda y filtros por estado, y clientes.
struct SalesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case invoices = "Facturas"
        case customers = "Clientes"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .invoices
    @State private var showingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)

            switch segment {
            case .invoices: InvoiceListView()
            case .customers: CustomerListView()
            }
        }
        .background(Palette.background)
        .navigationTitle("Ventas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: {
                    Label(segment == .invoices ? "Nueva factura" : "Nuevo cliente", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                if segment == .invoices { InvoiceEditorView() } else { CustomerEditorView() }
            }
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

    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @State private var query = ""
    @State private var filter: Filter = .all

    private var filtered: [Invoice] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return invoices.filter { invoice in
            filter.matches(invoice) && (text.isEmpty
                || invoice.number.lowercased().contains(text)
                || (invoice.customer?.name.lowercased().contains(text) ?? false)
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
                            FilterChip(title: option.rawValue, count: count, isSelected: filter == option) { filter = option }
                                .accessibilityHint("Filtra la lista de facturas")
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                HStack {
                    Text("\(filtered.count) \(filtered.count == 1 ? "factura" : "facturas")")
                    Spacer()
                    Text("Por cobrar \(Text(invoices.filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }.money).bold())")
                }
            }

            if filtered.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: invoices.isEmpty ? "Todavía no hay facturas" : "Sin resultados",
                               message: invoices.isEmpty ? "Crea tu primera factura con el botón +." : "Prueba con otro cliente, número o estado.",
                               actionTitle: invoices.isEmpty ? nil : "Quitar filtros") {
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
        .searchable(text: $query, prompt: "Cliente, número o monto")
    }
}

struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        LedgerRow(title: invoice.customer?.name ?? "Sin cliente", subtitle: subtitle) {
            InitialsTile(text: invoice.customer?.initials ?? "?", foreground: Palette.ink2, background: Palette.surface2)
        } trailing: {
            VStack(alignment: .trailing, spacing: 3) {
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
        let number = invoice.number.isEmpty ? "Sin número" : invoice.number
        switch invoice.status {
        case .draft: return "\(number) · borrador"
        case .paid: return "\(number) · pagada"
        case .void: return "\(number) · anulada"
        case .partiallyPaid, .sent: return "\(number) · \(invoice.dueDate.dueLabel)"
        }
    }
}

#Preview {
    NavigationStack { SalesView() }.modelContainer(SampleData.makeContainer())
}
