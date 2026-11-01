import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

extension Customer {
    /// Saldo de las facturas abiertas ya vencidas.
    var overdueBalance: Int64 {
        (invoices ?? []).filter { $0.isOpen && $0.daysOverdue() != nil }.reduce(0) { $0 + $1.balanceDue }
    }
}

/// Campo de búsqueda de las pantallas anchas (canvas `MacVentas`, `iPadVentas`, `MacClientes`).
struct WideSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3).accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar búsqueda")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(minHeight: Self.height)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
    }

    #if os(macOS)
    static let height: CGFloat = 36
    #else
    static let height: CGFloat = 44
    #endif
}

/// Tabla en tarjeta: cabecera en mayúsculas y filas separadas por líneas.
struct TableCard<Header: View, Rows: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { header }
                .font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(Palette.ink3)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .accessibilityHidden(true)
            rows
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Fila de `TableCard`: línea arriba, 44 pt de alto como mínimo.
struct TableRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) { content }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Facturas en Mac (`MacVentas`)

/// Cifras clave, búsqueda con chips de estado y tabla Nº · CLIENTE · FECHA · VENCE · ESTADO · IMPORTE.
struct InvoiceTableView: View {
    @Binding var query: String
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @Query private var payments: [PaymentReceived]
    @State private var filter: InvoiceListView.Filter = .all
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    private var filtered: [Invoice] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return invoices.filter { invoice in
            filter.matches(invoice) && (text.isEmpty || invoice.number.localizedStandardContains(text)
                || (invoice.customer?.name.localizedStandardContains(text) ?? false) || invoice.total.money.contains(text))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacPageTitle(String(localized: "Ventas"))
                KPIGrid(items: kpis)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { search.frame(maxWidth: 320); chips }
                    VStack(alignment: .leading, spacing: 10) { search; chips }
                }
                TableCard {
                    Text("Nº").frame(width: 72, alignment: .leading)
                    Text("Cliente").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Fecha").frame(width: 90, alignment: .leading)
                    Text("Vence").frame(width: 90, alignment: .leading)
                    Text("Estado").frame(width: 150, alignment: .leading)
                    Text("Importe").frame(width: amountWidth, alignment: .trailing)
                } rows: {
                    ForEach(filtered) { invoice in
                        NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                            TableRow {
                                Text(invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number)
                                    .foregroundStyle(Palette.ink2).frame(width: 72, alignment: .leading)
                                Text(invoice.customer?.name ?? String(localized: "Sin cliente")).fontWeight(.semibold).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(invoice.issueDate.dayMonth).foregroundStyle(Palette.ink2).frame(width: 90, alignment: .leading)
                                Text(invoice.dueDate.dayMonth).foregroundStyle(invoice.daysOverdue() != nil ? Palette.negative : Palette.ink2)
                                    .frame(width: 90, alignment: .leading)
                                StatusChip(invoice: invoice).frame(width: 150, alignment: .leading)
                                Text((invoice.status == .draft ? invoice.draftAmount : invoice.total).money).fontWeight(.semibold)
                                    .frame(width: amountWidth, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Text("Ninguna factura coincide").font(.headline)
                            Button("Quitar filtros") { query = ""; filter = .all }.buttonStyle(.secondary).fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
    }

    private var search: some View { WideSearchField(prompt: "Cliente, número o monto", text: $query) }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InvoiceListView.Filter.allCases) { option in
                    FilterChip(title: option.localizedTitle, count: invoices.filter(option.matches).count, isSelected: filter == option) { filter = option }
                }
            }
        }
    }

    /// Por cobrar, vencido, cobrado este mes y borradores.
    private var kpis: [KPIItem] {
        let open = invoices.filter { $0.isOpen && $0.balanceDue > 0 }
        let late = open.filter { $0.daysOverdue() != nil }
        let month = DateInterval.month(containing: .now)
        let collected = payments.filter { month.contains($0.date) }.reduce(0) { $0 + $1.amount }
        return [
            KPIItem(title: String(localized: "Por cobrar"), value: open.reduce(0) { $0 + $1.balanceDue }.money),
            KPIItem(title: String(localized: "Vencido · \(late.count) facturas"), value: late.reduce(0) { $0 + $1.balanceDue }.money,
                    footColor: Palette.negative),
            KPIItem(title: String(localized: "Cobrado en \(Date.now.formatted(.appDateTime.month(.wide)))"), value: collected.money),
            KPIItem(title: String(localized: "Borradores"), value: invoices.filter { $0.status == .draft }.count.formatted()),
        ]
    }
}

// MARK: - Facturas en iPad (`iPadVentas`, `iPadVentasV`)

/// Lista de facturas a la izquierda (búsqueda, Abiertas / Vencidas / Todas) y el detalle de la elegida a la derecha.
struct InvoiceSplitView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case open = "Abiertas", overdue = "Vencidas", all = "Todas"
        var id: String { rawValue }
    }

    @Binding var query: String
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @State private var scope: Scope = .open
    @State private var selectedID: Invoice.ID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var listWidth: CGFloat = 300

    private var filtered: [Invoice] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return invoices.filter { invoice in
            let inScope = switch scope {
            case .open: invoice.isOpen && invoice.balanceDue > 0 || invoice.status == .draft
            case .overdue: invoice.daysOverdue() != nil
            case .all: true
            }
            return inScope && (text.isEmpty || invoice.number.localizedStandardContains(text)
                || (invoice.customer?.name.localizedStandardContains(text) ?? false) || invoice.total.money.contains(text))
        }
    }

    private var selected: Invoice? { filtered.first { $0.id == selectedID } ?? filtered.first }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                WideSearchField(prompt: "Buscar", text: $query)
                // Con tamaños de accesibilidad, chips: el segmentado no crece con el texto.
                if dynamicTypeSize.isAccessibilitySize {
                    FlowLayout(spacing: 6) {
                        ForEach(Scope.allCases) { option in
                            FilterChip(title: option.localizedTitle, isSelected: scope == option) { scope = option }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Filtrar", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { invoice in row(invoice) }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if filtered.isEmpty {
                        Text("Ninguna factura coincide").font(.subheadline).foregroundStyle(Palette.ink3).padding(.top, 20)
                    }
                }
            }
            .frame(width: listWidth)

            Group {
                if let selected {
                    InvoiceDetailView(invoice: selected, embedded: true).id(selected.id)
                } else {
                    EmptyStateView(systemImage: "doc.text", title: String(localized: "Sin facturas"),
                                   message: String(localized: "Crea tu primera factura con «+ Factura»."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(Palette.background)
    }

    private func row(_ invoice: Invoice) -> some View {
        let isSelected = invoice.id == selected?.id
        return Button { selectedID = invoice.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(invoice.customer?.name ?? String(localized: "Sin cliente")).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text((invoice.isOpen ? invoice.balanceDue : invoice.status == .draft ? invoice.draftAmount : invoice.total).money)
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                HStack {
                    Text("\(invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number) · \(invoice.dueDate.dueLabel)")
                        .font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                    Spacer(minLength: 8)
                    StatusChip(invoice: invoice)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(isSelected ? Palette.brandWash : Palette.surface)
            .overlay(alignment: .leading) { Rectangle().fill(isSelected ? Palette.brand : .clear).frame(width: 3) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Clientes (`MacClientes`)

/// Búsqueda, chips Todos / Con saldo / Vencidos, total y tabla CLIENTE · CONTACTO · ABIERTAS · VENCIDO · SALDO · ESTADO.
struct CustomerTableView: View {
    @Binding var query: String
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var filter: CustomerListView.Filter = .all
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    private var active: [Customer] { customers.filter { !$0.isArchived } }

    private var filtered: [Customer] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return active.filter { customer in
            let inFilter = switch filter {
            case .all: true
            case .withBalance: customer.openBalance > 0
            case .overdue: customer.overdueBalance > 0
            }
            return inFilter && (text.isEmpty || customer.name.localizedStandardContains(text)
                || customer.email.localizedStandardContains(text) || customer.phone.contains(text))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacPageTitle(String(localized: "Clientes"))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { search.frame(maxWidth: 320); chips; Spacer(minLength: 8); summary }
                    VStack(alignment: .leading, spacing: 10) { search; HStack { chips; Spacer(minLength: 8) }; summary }
                }
                TableCard {
                    Text("Cliente").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Contacto").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Abiertas").frame(width: 80, alignment: .trailing)
                    Text("Vencido").frame(width: amountWidth, alignment: .trailing)
                    Text("Saldo").frame(width: amountWidth, alignment: .trailing)
                    Text("Estado").frame(width: 100, alignment: .leading)
                } rows: {
                    ForEach(filtered) { customer in
                        NavigationLink { CustomerDetailView(customer: customer) } label: { row(customer) }
                            .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text(query.isEmpty ? String(localized: "Sin clientes todavía") : String(localized: "Ningún cliente coincide con «\(query)»."))
                            .font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
    }

    private var search: some View { WideSearchField(prompt: "Nombre, correo o teléfono", text: $query) }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(CustomerListView.Filter.allCases) { option in
                FilterChip(title: option.localizedTitle, isSelected: filter == option) { filter = option }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Text("\(filtered.count) clientes")
            Text(" · ")
            Text("saldo total \(Text(active.reduce(0) { $0 + $1.openBalance }.money).bold())")
        }
        .font(.footnote).foregroundStyle(Palette.ink3).fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func row(_ customer: Customer) -> some View {
        let late = customer.overdueBalance
        let open = (customer.invoices ?? []).filter { $0.isOpen && $0.balanceDue > 0 }.count
        return TableRow {
            HStack(spacing: 10) {
                InitialsTile(text: customer.initials, foreground: late > 0 ? Palette.negative : Palette.brand,
                             background: late > 0 ? Palette.negativeWash : Palette.brandWash, round: true)
                Text(customer.name).fontWeight(.semibold).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(customer.email.isEmpty ? customer.phone : customer.email).foregroundStyle(Palette.ink2).lineLimit(1)
                .truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(open == 0 ? "—" : open.formatted()).foregroundStyle(Palette.ink2).frame(width: 80, alignment: .trailing)
            Text(late == 0 ? "—" : late.money).fontWeight(.semibold).foregroundStyle(late == 0 ? Palette.ink3 : Palette.negative)
                .frame(width: amountWidth, alignment: .trailing)
            Text(customer.openBalance.money).fontWeight(.semibold).frame(width: amountWidth, alignment: .trailing)
            Group {
                if late > 0 {
                    StatusChip(text: String(localized: "Vencido"), foreground: Palette.negative, background: Palette.negativeWash)
                } else if customer.openBalance > 0 {
                    StatusChip(text: String(localized: "Al día"), foreground: Palette.positive, background: Palette.positiveWash)
                } else {
                    StatusChip(text: String(localized: "Sin saldo"), foreground: Palette.ink2, background: Palette.surface2)
                }
            }
            .frame(width: 100, alignment: .leading)
        }
    }
}
