#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Estimados (subsección de Ventas) con tabla + inspector, como Facturas (`MacVentas`). La selección vive aquí y
/// no en `AppShell`: Estimados no es una `MasterPage` en el Mac, para no tocar el `switch` de `MacTablePage.swift`
/// (anotado: al pasarla allí, `hasMacTable` y `macTable` solo necesitan un caso más).
struct EstimatesMacPage: View {
    @State private var selection: UUID?

    var body: some View { EstimateTablePage(selection: $selection) }
}

/// Tabla Número · Cliente · Concepto · Emitido · Válido hasta · Estado · Importe, con el segmentado de estados y las
/// cajas Por responder · Aceptados por facturar · Convertidos · Borradores. El inspector muestra el estimado elegido
/// (Detalles, Importes, Facturas) con la acción de su estado: «Enviar estimado…», «Marcar como aceptado…» o «Convertir
/// en factura…». Doble clic abre el estimado completo (`EstimateDetailView`).
struct EstimateTablePage: View {
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var context
    @Query(sort: \Estimate.issueDate, order: .reverse) private var estimates: [Estimate]
    @State private var filter: EstimateFilter = .all
    @State private var query = ""
    @State private var creating = false
    @State private var editing: Estimate?
    @State private var sending: Estimate?
    @State private var accepting: Estimate?
    @State private var converting: Estimate?
    @State private var opened: Estimate?
    @State private var openedInvoice: Invoice?
    @State private var openedCustomer: Customer?
    @State private var errorMessage: String?

    private var filtered: [Estimate] { estimates.filter { filter.matches($0) && EstimateFilter.search($0, query) } }

    private var footer: String {
        filtered.count == estimates.count ? String(localized: "\(estimates.count) estimados")
            : String(localized: "\(filtered.count) de \(estimates.count) estimados")
    }

    private var kpis: [KPIItem] {
        let sent = estimates.filter { $0.effectiveStatus() == .sent }
        let accepted = estimates.filter { $0.effectiveStatus() == .accepted }
        let books = Bookkeeper(context: context)
        let toInvoice = accepted.reduce(Int64(0)) { $0 + EstimateConversionChoice.amount($1, portion: .all, books: books) }
        let month = DateInterval.month(containing: .now)
        let converted = estimates.filter { $0.convertedDate.map(month.contains) ?? false }
        return [
            KPIItem(title: String(localized: "Por responder"), value: sent.reduce(0) { $0 + $1.total }.money,
                    foot: sent.isEmpty ? nil : String(localized: "\(sent.count) estimados")),
            KPIItem(title: String(localized: "Aceptados por facturar"), value: toInvoice.money,
                    foot: accepted.isEmpty ? nil : String(localized: "\(accepted.count) estimados")),
            KPIItem(title: String(localized: "Convertidos en \(Date.now.formatted(.appDateTime.month(.wide)))"), value: "\(converted.count)"),
            KPIItem(title: String(localized: "Borradores"), value: "\(estimates.filter { $0.status == .draft }.count)"),
        ]
    }

    var body: some View {
        MacTablePage(
            title: String(localized: "Estimados"),
            subtitle: String(localized: "Ventas · \(estimates.count) estimados"),
            rows: filtered, footer: footer,
            query: $query, searchPrompt: Text("Cliente, número o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\Estimate.tableNumber, order: .reverse)],
            kpis: kpis,
            addTitle: String(localized: "Nuevo estimado"), onAdd: { creating = true },
            onOpen: { opened = $0 },
            empty: estimates.isEmpty
                ? MacTableEmpty(systemImage: "list.clipboard", title: String(localized: "Todavía no hay estimados"),
                                message: String(localized: "Haz un estimado para tu cliente y, cuando lo acepte, conviértelo en factura."),
                                actionTitle: String(localized: "Nuevo estimado"), action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ningún estimado coincide con la búsqueda o el filtro."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { estimate in
                guard let estimate else { return String(localized: "Estimado") }
                return String(localized: "Estimado \(estimate.number)")
            },
            inspectorPlaceholder: String(localized: "Selecciona un estimado para ver sus detalles.")
        ) {
            TableColumn("Número", value: \.tableNumber) { estimate in
                MacCellText(text: estimate.number.isEmpty ? "—" : estimate.number)
            }
            .width(min: 52, ideal: 60, max: 110)
            TableColumn("Cliente", value: \.customerName) { estimate in
                Text(estimate.customer?.name ?? String(localized: "Sin cliente")).lineLimit(1)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Concepto", value: \.title) { estimate in
                MacCellText(text: estimate.title.isEmpty ? "—" : estimate.title).lineLimit(1)
            }
            .width(min: 70, ideal: 110)
            TableColumn("Emitido", value: \.issueDate) { estimate in
                MacCellText(text: estimate.issueDate.dayMonth)
            }
            .width(min: 52, ideal: 60, max: 100)
            TableColumn("Válido hasta", value: \.expirationDate) { estimate in
                MacCellText(text: estimate.expirationDate.dayMonth,
                            color: estimate.effectiveStatus() == .expired ? Palette.warning : Palette.ink2)
            }
            .width(min: 60, ideal: 70, max: 110)
            TableColumn("Estado", value: \.statusRank) { estimate in
                MacCellStatus(chip: estimate.statusChip())
            }
            .width(min: 80, ideal: 100, max: 200)
            TableColumn("Importe", value: \.total) { estimate in
                Text(estimate.total.money).monospacedDigit()
            }
            .width(min: 70, ideal: 80, max: 140)
            .alignment(.trailing)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar por estado"), options: EstimateFilter.allCases,
                           selection: $filter, label: \.title) { option in
                estimates.filter(option.matches).count
            }
        } inspector: { estimate in
            EstimateInspector(estimate: estimate, errorMessage: errorMessage, openCustomer: { openedCustomer = $0 },
                              openInvoice: { openedInvoice = $0 })
        } actions: { estimate in
            actions(for: estimate)
        }
        .onChange(of: selection) { errorMessage = nil }
        .sheet(isPresented: $creating) { NavigationStack { InvoiceEditorView(mode: .estimate(nil)) }.editorSheetSizing() }
        .sheet(item: $editing) { estimate in NavigationStack { InvoiceEditorView(mode: .estimate(estimate)) }.editorSheetSizing() }
        .sheet(item: $sending) { estimate in NavigationStack { SendDocumentView(source: .estimate(estimate)) }.editorSheetSizing() }
        .sheet(item: $accepting) { estimate in NavigationStack { EstimateAcceptView(estimate: estimate) }.editorSheetSizing() }
        .sheet(item: $converting) { estimate in
            NavigationStack { ConvertEstimateSheet(estimate: estimate) { openedInvoice = $0 } }.editorSheetSizing()
        }
        .navigationDestination(item: $opened) { EstimateDetailView(estimate: $0) }
        .navigationDestination(item: $openedInvoice) { InvoiceDetailView(invoice: $0) }
        .navigationDestination(item: $openedCustomer) { CustomerDetailView(customer: $0) }
        #if DEBUG
        // `-qa.nuevo 1` abre «Nuevo estimado»; con `-qa.fila N`, `-qa.abrir 1` abre el estimado, `-qa.convertir 1` la
        // hoja de convertir y `-qa.enviar 1` (además) la de enviar.
        .task {
            let defaults = UserDefaults.standard
            try? await Task.sleep(for: .seconds(1))
            if defaults.bool(forKey: "qa.nuevo") { creating = true; return }
            // `-qa.fila N`: aquí la tabla aparece antes de que lleguen los estimados y `QALaunch` no llega a elegirla.
            if selection == nil, defaults.object(forKey: "qa.fila") != nil {
                let rows = filtered.sorted { $0.tableNumber > $1.tableNumber }
                let index = defaults.integer(forKey: "qa.fila")
                if rows.indices.contains(index) { selection = rows[index].id }
                try? await Task.sleep(for: .seconds(0.5))
            }
            guard let id = selection, let estimate = estimates.first(where: { $0.id == id }) else { return }
            if defaults.bool(forKey: "qa.abrir") { opened = estimate }
            if defaults.bool(forKey: "qa.convertir") { converting = estimate }
            if defaults.bool(forKey: "qa.enviar") { sending = estimate }
        }
        #endif
    }

    /// La acción principal según el estado y, debajo, las secundarias.
    @ViewBuilder
    private func actions(for estimate: Estimate) -> some View {
        switch estimate.effectiveStatus() {
        case .draft:
            Button("Enviar estimado…") { sending = estimate }.buttonStyle(.primary)
        case .sent, .expired:
            Button("Marcar como aceptado…") { accepting = estimate }.buttonStyle(.primary)
        case .accepted:
            if estimate.isConvertible {
                Button("Convertir en factura…") { converting = estimate }.buttonStyle(.primary)
            }
        case .declined, .converted:
            EmptyView()
        }
        HStack(spacing: 8) {
            Button("Abrir estimado") { opened = estimate }.buttonStyle(.secondary)
            if estimate.isEditable {
                Button("Editar") { editing = estimate }.buttonStyle(.secondary)
            }
        }
        if estimate.isConvertible && estimate.effectiveStatus() != .accepted {
            Button("Convertir en factura…") { converting = estimate }.buttonStyle(.secondary)
        }
    }
}

/// Inspector del estimado: cliente, total de 24 y estado; Detalles (Número, Cliente, Concepto, Emitido, Válido hasta,
/// Aceptado por), Importes (Subtotal, impuesto, Total, Por facturar) y las facturas que salieron de él.
private struct EstimateInspector: View {
    let estimate: Estimate
    let errorMessage: String?
    let openCustomer: (Customer) -> Void
    let openInvoice: (Invoice) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let books = Bookkeeper(context: context)
        if let errorMessage { ErrorBanner(message: errorMessage) }
        MacInspectorSummary(title: estimate.customer?.name ?? String(localized: "Sin cliente"), amount: estimate.total.money) {
            estimate.statusChip()
        }
        MacInspectorSection(title: String(localized: "Detalles")) {
            MacInspectorRow(String(localized: "Número"), value: estimate.number.isEmpty ? "—" : estimate.number)
            MacInspectorRow(label: String(localized: "Cliente")) {
                if let customer = estimate.customer {
                    Button(customer.name) { openCustomer(customer) }
                        .buttonStyle(.link).foregroundStyle(Palette.brand).lineLimit(1)
                } else {
                    Text("Sin cliente").foregroundStyle(Palette.ink2)
                }
            }
            if !estimate.title.isEmpty { MacInspectorRow(String(localized: "Concepto"), value: estimate.title) }
            MacInspectorRow(String(localized: "Emitido"), value: estimate.issueDate.shortDate)
            MacInspectorRow(String(localized: "Válido hasta"), value: estimate.expirationDate.shortDate,
                            color: estimate.effectiveStatus() == .expired ? Palette.warning : Palette.ink)
            if let sent = estimate.sentDate { MacInspectorRow(String(localized: "Enviado"), value: sent.shortDate) }
            if estimate.status == .accepted || estimate.status == .converted, let accepted = estimate.acceptedDate {
                MacInspectorRow(String(localized: "Aceptado"),
                                value: estimate.acceptedBy.isEmpty ? accepted.shortDate : "\(estimate.acceptedBy) · \(accepted.dayMonth)")
            }
        }
        MacInspectorSection(title: String(localized: "Importes")) {
            ForEach(SalesDocument(estimate: estimate).totals) { row in
                MacInspectorRow(row.title, value: row.value, color: row.style == .subtle ? Palette.ink2 : Palette.ink,
                                bold: row.style == .accent)
            }
            if estimate.hasInvoices && !estimate.isFullyInvoiced {
                MacInspectorRow(String(localized: "Por facturar"),
                                value: EstimateConversionChoice.amount(estimate, portion: .all, books: books).money)
            }
        }
        let invoices = (try? books.invoices(for: estimate)) ?? []
        if !invoices.isEmpty {
            MacInspectorSection(title: String(localized: "Facturas")) {
                ForEach(invoices) { invoice in
                    MacInspectorRow(label: invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number) {
                        Button(invoice.tableAmount.money) { openInvoice(invoice) }
                            .buttonStyle(.link).foregroundStyle(Palette.brand)
                    }
                }
            }
        }
    }
}
#endif
