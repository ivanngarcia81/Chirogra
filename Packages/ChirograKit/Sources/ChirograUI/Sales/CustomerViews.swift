import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Clientes (canvas `Clientes`): segmentado Todos · Con saldo · Vencidos bajo la búsqueda y dos grupos, «Con saldo
/// pendiente» y «Sin saldo», con su total en el encabezado. Filas con monograma gris, saldo y nota de estado.
struct CustomerListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos", withBalance = "Con saldo", overdue = "Vencidos"
        var id: String { rawValue }
    }

    /// Texto de la búsqueda de Ventas (`SalesView`).
    var query = ""
    /// «Clientes ▾» del iPhone (`SalesView`).
    var sectionMenu: SalesSectionMenu? = nil
    /// «Nuevo cliente» del estado vacío sin clientes.
    var onCreate: () -> Void = {}
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var filter: Filter = .all
    /// Cliente nuevo con el nombre buscado («¿Quieres crear «…» como cliente nuevo?»).
    @State private var creatingFromQuery = false

    private func matches(_ customer: Customer, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .withBalance: customer.openBalance > 0
        case .overdue: customer.overdueBalance > 0
        }
    }

    private var active: [Customer] { customers.filter { !$0.isArchived } }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var filtered: [Customer] {
        let text = trimmedQuery
        return active.filter {
            matches($0, filter) && (text.isEmpty || $0.name.localizedStandardContains(text)
                || $0.email.localizedStandardContains(text) || $0.phone.contains(text))
        }
    }

    var body: some View {
        let owing = filtered.filter { $0.openBalance > 0 }
        let settled = filtered.filter { $0.openBalance <= 0 }
        List {
            // Menú de sección y segmentado en el mismo grupo, sin hueco entre ellos.
            Section {
                if let sectionMenu { sectionMenu.sectionMenuRow() }
                FilterPicker(title: String(localized: "Filtrar clientes"), options: Filter.allCases, selection: $filter, label: \.localizedTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .compactSectionSpacing(8)

            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                if !owing.isEmpty {
                    Section {
                        rows(owing)
                    } header: {
                        groupHeader(String(localized: "Con saldo pendiente"), owing.reduce(0) { $0 + $1.openBalance }.money)
                    }
                    .listRowBackground(Palette.surface)
                }
                if !settled.isEmpty {
                    Section {
                        rows(settled)
                    } header: {
                        groupHeader(String(localized: "Sin saldo"), String(localized: "\(settled.count) clientes"))
                    }
                    .listRowBackground(Palette.surface)
                }
            }
        }
        .screenBackground()
        // El menú de sección, justo debajo del buscador.
        .contentMargins(.top, 4, for: .scrollContent)
        .sheet(isPresented: $creatingFromQuery) {
            NavigationStack { CustomerEditorView(initialName: trimmedQuery) }.editorSheetSizing()
        }
    }

    private func rows(_ list: [Customer]) -> some View {
        ForEach(list) { customer in
            NavigationLink { CustomerDetailView(customer: customer) } label: { CustomerRow(customer: customer) }
        }
    }

    private func groupHeader(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fixedSize()
                Spacer(minLength: 8)
                Text(value).fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value)
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .monospacedDigit()
        .textCase(nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        if active.isEmpty {
            ContentUnavailableView {
                Label("Sin clientes todavía", systemImage: "person.2")
            } description: {
                Text("Añade tu primer cliente con el botón +.")
            } actions: {
                Button("Nuevo cliente", action: onCreate).buttonStyle(.primaryCompact)
            }
        } else if !trimmedQuery.isEmpty {
            // Canvas `Clientes`: «Ningún cliente coincide · ¿Quieres crear «…» como cliente nuevo?».
            ContentUnavailableView {
                Label("Ningún cliente coincide", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("¿Quieres crear «\(trimmedQuery)» como cliente nuevo?")
            } actions: {
                Button("Crear cliente") { creatingFromQuery = true }.buttonStyle(.primaryCompact)
            }
        } else {
            ContentUnavailableView {
                Label("Ningún cliente coincide", systemImage: "person.2")
            } description: {
                Text("Prueba con otro filtro.")
            } actions: {
                Button("Quitar filtros") { filter = .all }.buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            }
        }
    }
}

/// Fila de cliente (canvas `Clientes`): monograma gris, nombre y contacto; saldo y una nota de estado («$2,150
/// vencido» en rojo, «Vence 12 nov», «Al día»…). El chevron lo pone la lista.
struct CustomerRow: View {
    let customer: Customer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let late = customer.overdueBalance
        // Punto de corte invisible tras la «@»: si el correo no cabe, baja ahí y no se parte con guion.
        let contact = customer.email.isEmpty ? (customer.phone.isEmpty ? String(localized: "Sin correo") : customer.phone)
            : customer.email.replacingOccurrences(of: "@", with: "@\u{200B}")
        return LedgerRow(title: customer.name, subtitle: contact, subtitleLines: 2) {
            InitialsTile(text: customer.initials)
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                Text(customer.openBalance.money).font(.body).monospacedDigit()
                    .foregroundStyle(customer.openBalance > 0 ? Palette.ink : Palette.ink2)
                Text(status(customer, overdue: late)).font(.footnote)
                    .foregroundStyle(late > 0 ? Palette.negative : Palette.ink2)
                if customer.creditBalance > 0 {
                    Text("\(customer.creditBalance.money) a favor").font(.footnote).foregroundStyle(Palette.positive)
                }
            }
        }
    }

    /// «$2,150 vencido», «Pago parcial», «Vence 12 nov», «Con borrador», «Al día» o «Sin facturas».
    private func status(_ customer: Customer, overdue: Int64) -> String {
        let invoices = customer.invoices ?? []
        if overdue > 0 { return String(localized: "\(overdue.moneyWhole) vencido") }
        if let next = invoices.filter({ $0.isOpen && $0.balanceDue > 0 }).min(by: { $0.dueDate < $1.dueDate }) {
            return next.status == .partiallyPaid ? String(localized: "Pago parcial") : String(localized: "Vence \(next.dueDate.dayMonth)")
        }
        if invoices.isEmpty { return String(localized: "Sin facturas") }
        if invoices.contains(where: { $0.status == .draft }) { return String(localized: "Con borrador") }
        return String(localized: "Al día")
    }
}

extension Invoice {
    /// Color del punto de su estado, el mismo de `StatusChip`.
    var statusDotColor: Color {
        if daysOverdue() != nil { return Palette.red }
        return switch status {
        case .draft, .void: Palette.gray
        case .sent: Palette.blue
        case .partiallyPaid: Palette.orange
        case .paid: Palette.green
        }
    }
}

/// Ficha de cliente. iPhone (canvas `ClienteFicha`): cabecera centrada, Llamar · Mensaje · Correo · Factura, saldo con
/// vencido y por vencer, y Historial · Contacto · Notas. iPad y Mac (canvas `MacClienteFicha`): cabecera a la izquierda,
/// cajas de cifras, tabla «Historial de facturas» y los bloques «Contacto» y «Notas».
struct CustomerDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case history = "Historial", contact = "Contacto", notes = "Notas"
        var id: String { rawValue }
    }

    @Bindable var customer: Customer
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 100
    @State private var openOnly = false
    @State private var editing = false
    @State private var newInvoice = false
    @State private var newEstimate = false
    @State private var refunding = false
    @State private var addingNote = false
    @State private var deletingNote: CustomerNote?
    @State private var reminding: Invoice?
    @State private var tab: Tab = .history
    @Environment(\.modelContext) private var context

    private var openInvoices: [Invoice] { (customer.invoices ?? []).filter { $0.isOpen && $0.balanceDue > 0 } }
    private var overdue: Int64 { customer.overdueBalance }
    /// La factura del recordatorio: la abierta que vence (o venció) antes.
    private var reminderInvoice: Invoice? { openInvoices.min { $0.dueDate < $1.dueDate } }
    /// «Recordatorio enviado» si hoy ya se mandó uno de sus facturas abiertas (DATOS-V2 §9).
    private var remindedToday: Bool { openInvoices.contains { $0.lastReminderDate.map(Calendar.current.isDateInToday) ?? false } }
    private var estimates: [Estimate] { (customer.estimates ?? []).sorted { $0.issueDate > $1.issueDate } }

    /// `MacClienteFicha` en iPad y Mac hasta AX3; la ficha del iPhone en pantallas o columnas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        Group {
            if isWide { wideBody } else { compactBody }
        }
        .background(Palette.background)
        .recordTitle(customer.name, section: String(localized: "Clientes"))
        .toolbar {
            if isWide {
                // Canvas `MacClienteFicha`: «Editar | Enviar recordatorio» en un grupo y «Nueva factura» aparte.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Editar", systemImage: "pencil") { editing = true }.labelStyle(.titleAndIcon).headerButton()
                    if let reminderInvoice {
                        Button { reminding = reminderInvoice } label: {
                            Label(remindedToday ? "Recordatorio enviado" : "Enviar recordatorio",
                                  systemImage: remindedToday ? "checkmark" : "bell")
                                .labelStyle(.titleAndIcon)
                        }
                        .headerButton()
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { newEstimate = true } label: { Label("Nuevo estimado", systemImage: "list.clipboard").labelStyle(.titleAndIcon) }
                        .headerButton()
                    Button { newInvoice = true } label: { Label("Nueva factura", systemImage: "plus").labelStyle(.titleAndIcon) }
                        .headerButton()
                }
            } else {
                ToolbarItem(placement: .primaryAction) { Button("Editar") { editing = true }.headerButton() }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { CustomerEditorView(customer: customer) }.editorSheetSizing() }
        // En hoja también en iPad y Mac, como el resto de editores nuevos: en el detalle, junto a la lista, la factura
        // no cabía y ensanchaba la ventana del Mac.
        .sheet(isPresented: $newInvoice) {
            NavigationStack { InvoiceEditorView(preselectedCustomer: customer) }.editorSheetSizing()
        }
        .sheet(isPresented: $refunding) { NavigationStack { CustomerRefundView(customer: customer) }.editorSheetSizing() }
        .sheet(isPresented: $newEstimate) {
            NavigationStack { InvoiceEditorView(preselectedCustomer: customer, mode: .estimate(nil)) }.editorSheetSizing()
        }
        .sheet(isPresented: $addingNote) { NavigationStack { CustomerNoteEditor(customer: customer) }.editorSheetSizing() }
        .sheet(item: $reminding) { invoice in
            NavigationStack { SendDocumentView(source: .invoice(invoice), purpose: .reminder) }.editorSheetSizing()
        }
        .confirmationDialog("¿Borrar la nota?", isPresented: Binding(get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }),
                            titleVisibility: .visible, presenting: deletingNote) { note in
            Button("Borrar nota", role: .destructive) { deleteNote(note) }
        } message: { note in
            Text(note.text).lineLimit(2)
        }
        #if DEBUG
        // `-qa.nota 1` abre «Nueva nota» y `-qa.recordar 1` «Enviar recordatorio» en la ficha (pruebas sin tocar la pantalla).
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nota") { addingNote = true }
            if UserDefaults.standard.bool(forKey: "qa.recordar") { reminding = reminderInvoice }
        }
        #endif
    }

    private func deleteNote(_ note: CustomerNote) {
        try? Bookkeeper(context: context).deleteNote(note)
        deletingNote = nil
    }

    // MARK: iPad y Mac (`MacClienteFicha`)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                wideHeader
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Saldo pendiente"), value: customer.openBalance.money,
                            foot: String(localized: "\(openInvoices.count) facturas abiertas")),
                    KPIItem(title: String(localized: "Vencido"), value: overdue.money,
                            foot: overdue > 0 ? String(localized: "Requiere seguimiento") : String(localized: "Nada vencido"),
                            footColor: overdue > 0 ? Palette.negative : Palette.ink2),
                    KPIItem(title: String(localized: "Por vencer"), value: (customer.openBalance - overdue).money,
                            foot: nextDue.map { String(localized: "Próximo vencimiento \($0.dayMonth)") }),
                    KPIItem(title: String(localized: "Facturado en \(Date.now.formatted(.appDateTime.year()))"), value: billedThisYear.money,
                            foot: averageDaysToPay.map { String(localized: "Paga en \($0) días de promedio") }),
                ])
                if customer.creditBalance > 0 { creditCard }
                invoiceTable
                if !estimates.isEmpty { estimateTable }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        contactBox.frame(minWidth: 300, maxWidth: .infinity)
                        notesBox.frame(minWidth: 260, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 16) { contactBox; notesBox }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
        }
    }

    /// Cabecera del Mac: monograma de 64 a la izquierda, nombre y contacto (el `ProfileHeader` del sistema va centrado).
    private var wideHeader: some View {
        HStack(spacing: 14) {
            Text(customer.initials)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 64, height: 64)
                .foregroundStyle(.white)
                .background(Palette.monogram, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).font(Self.wideNameFont).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Text(headerDetail).font(.subheadline).foregroundStyle(Palette.ink2)
                if !customer.contactLine.isEmpty {
                    Text(customer.contactLine).font(.subheadline).foregroundStyle(Palette.ink2)
                }
                if !customer.email.isEmpty {
                    Button(customer.email) { if let url = URL(string: "mailto:\(customer.email)") { openURL(url) } }
                        .buttonStyle(.plain).font(.subheadline).foregroundStyle(Palette.brand)
                        .accessibilityLabel("Correo \(customer.email)")
                }
            }
        }
    }

    #if os(macOS)
    private static let wideNameFont = Font.title.weight(.bold)
    #else
    private static let wideNameFont = Font.title2.weight(.bold)
    #endif

    /// Historial de facturas: Número · Emitida · Vence · Estado · Importe · Saldo, con Todas / Abiertas.
    private var invoiceTable: some View {
        let invoices = (customer.invoices ?? []).filter { !openOnly || $0.isOpen }.sorted { $0.issueDate > $1.issueDate }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Historial de facturas").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                FilterPicker(title: String(localized: "Filtrar historial"), options: [false, true], selection: $openOnly) {
                    $0 ? String(localized: "Abiertas") : String(localized: "Todas")
                }
                .fixedSize()
            }
            // Con poco ancho (ficha junto a la lista en un Mac de 1000 pt), sin Emitida ni Importe.
            ViewThatFits(in: .horizontal) {
                historyTable(invoices, full: true)
                historyTable(invoices, full: false)
            }
        }
    }

    private func historyTable(_ invoices: [Invoice], full: Bool) -> some View {
        TableCard {
            Text("Número").frame(width: 70, alignment: .leading)
            if full { Text("Emitida").frame(width: 70, alignment: .leading) }
            Text("Vence").frame(width: 70, alignment: .leading)
            Text("Estado").frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            if full { Text("Importe").frame(width: amountWidth, alignment: .trailing) }
            Text("Saldo").frame(width: amountWidth, alignment: .trailing)
        } rows: {
            ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                    TableRow {
                        Text(invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number)
                            .frame(width: 70, alignment: .leading)
                        if full {
                            Text(invoice.issueDate.dayMonth).foregroundStyle(Palette.ink2).frame(width: 70, alignment: .leading)
                        }
                        Text(invoice.dueDate.dayMonth).foregroundStyle(Palette.ink2).frame(width: 70, alignment: .leading)
                        StatusChip(invoice: invoice).fixedSize().frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                        if full { Text(invoice.total.money).frame(width: amountWidth, alignment: .trailing) }
                        Text(invoice.balanceDue.money)
                            .foregroundStyle(invoice.isOpen ? Palette.ink : Palette.ink2).frame(width: amountWidth, alignment: .trailing)
                    }
                    .background(zebra(index))
                }
                .buttonStyle(.plain)
            }
            if invoices.isEmpty {
                Text("Sin facturas").foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    /// Estimados del cliente: Número · Emitido · Válido hasta · Estado · Importe.
    private var estimateTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimados").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TableCard {
                Text("Número").frame(width: 70, alignment: .leading)
                Text("Emitido").frame(width: 70, alignment: .leading)
                Text("Válido hasta").frame(width: 90, alignment: .leading)
                Text("Estado").frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                Text("Importe").frame(width: amountWidth, alignment: .trailing)
            } rows: {
                ForEach(Array(estimates.enumerated()), id: \.element.id) { index, estimate in
                    NavigationLink { EstimateDetailView(estimate: estimate) } label: {
                        TableRow {
                            Text(estimate.number).frame(width: 70, alignment: .leading)
                            Text(estimate.issueDate.dayMonth).foregroundStyle(Palette.ink2).frame(width: 70, alignment: .leading)
                            Text(estimate.expirationDate.dayMonth).foregroundStyle(Palette.ink2).frame(width: 90, alignment: .leading)
                            estimate.statusChip().fixedSize().frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                            Text(estimate.total.money).frame(width: amountWidth, alignment: .trailing)
                        }
                        .background(zebra(index))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Cebra del Mac (`--row2` en las filas impares); en iPhone e iPad, la celda lisa.
    private func zebra(_ index: Int) -> Color {
        #if os(macOS)
        index.isMultiple(of: 2) ? Color.clear : Palette.surface
        #else
        Color.clear
        #endif
    }

    private var contactBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contacto").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                contactRow(String(localized: "Persona"), customer.contactLine, first: true)
                contactRow(String(localized: "Correo"), customer.email, link: customer.email.isEmpty ? nil : URL(string: "mailto:\(customer.email)"))
                contactRow(String(localized: "Teléfono"), customer.phone, link: phoneURL)
                contactRow(String(localized: "Dirección"), customer.billingAddress)
                if !customer.taxID.isEmpty { contactRow(String(localized: "ID fiscal"), customer.taxID) }
                contactRow(String(localized: "Condiciones"), termsText)
                contactRow(String(localized: "Sales tax"), customer.isTaxExempt ? String(localized: "Exento") : String(localized: "Gravable"))
            }
            .card(padding: 0)
        }
    }

    private func contactRow(_ title: String, _ value: String, link: URL? = nil, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Divider().padding(.leading, Metrics.cardPadding) }
            AdaptiveRow(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Palette.ink2)
            } trailing: {
                if let link {
                    Button(value) { openURL(link) }.buttonStyle(.plain).foregroundStyle(Palette.brand)
                } else {
                    Text(value.isEmpty ? "—" : value).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 6)
            .frame(minHeight: Metrics.target)
        }
        .accessibilityElement(children: .combine)
    }

    private var notesBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notas").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            datedNotes
            fixedNote
        }
    }

    /// Notas fechadas, de la más reciente a la más antigua (canvas `ClienteFicha` · Notas: el texto y «22 oct · Ana R.»
    /// debajo), cada una con «Borrar», y «Nueva nota» al final.
    private var datedNotes: some View {
        VStack(spacing: 0) {
            ForEach(Array(customer.sortedNotes.enumerated()), id: \.element.id) { index, note in
                if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.text).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        Text(note.author.isEmpty ? note.date.dayMonth : "\(note.date.dayMonth) · \(note.author)")
                            .font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Button { deletingNote = note } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.ink2)
                            .frame(minWidth: Metrics.target, minHeight: Metrics.target)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar nota del \(note.date.dayMonth)")
                }
                .padding(.leading, Metrics.cardPadding)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
            }
            if customer.sortedNotes.isEmpty {
                Text("Sin notas todavía").foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .padding(.horizontal, Metrics.cardPadding)
            }
            Divider().padding(.leading, Metrics.cardPadding)
            Button { addingNote = true } label: {
                Label {
                    Text("Nueva nota").foregroundStyle(Palette.brand)
                } icon: {
                    Image(systemName: "plus.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Palette.green)
                }
                .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                .padding(.horizontal, Metrics.cardPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card(padding: 0)
    }

    /// Nota fija del cliente (`Customer.notes`), aparte de las fechadas.
    private var fixedNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: String(localized: "Nota fija")).padding(.horizontal, Metrics.cardPadding).padding(.top, 8)
            TextField("Añadir una nota…", text: $customer.notes, axis: .vertical)
                .lineLimit(2...)
                .textFieldStyle(.plain)
                .card(padding: 12)
        }
    }

    // MARK: iPhone (`ClienteFicha`)

    private var compactBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileHeader(initials: customer.initials, name: customer.name, detail: headerDetail)
                    .padding(.top, 4)
                actions.padding(.top, 18).padding(.horizontal, 8)
                balanceCard.padding(.top, 22)
                Text(balanceFootnote).font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, Metrics.cardPadding).padding(.top, 7)
                if customer.creditBalance > 0 { creditCard.padding(.top, 20) }
                FilterPicker(title: String(localized: "Información del cliente"), options: Tab.allCases, selection: $tab, label: \.localizedTitle)
                    .padding(.top, 20)
                Group {
                    switch tab {
                    case .history: history
                    case .contact: contact
                    case .notes: notes
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// «Cliente desde marzo de 2025 · Neto 15».
    private var headerDetail: String {
        let since = ([customer.createdAt] + (customer.invoices ?? []).map(\.issueDate)).min() ?? customer.createdAt
        // «Neto 15» con espacio de no separación: con texto grande no se parte entre líneas.
        let terms = termsText.replacingOccurrences(of: " ", with: "\u{00A0}")
        return String(localized: "Cliente desde \(since.formatted(.appDateTime.month(.wide).year())) · \(terms)")
    }

    private var termsText: String {
        customer.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(customer.paymentTermsDays)")
    }

    private var phoneDigits: String { customer.phone.filter { $0.isNumber || $0 == "+" } }
    private var phoneURL: URL? { customer.phone.isEmpty ? nil : URL(string: "tel:\(phoneDigits)") }

    /// Llamar · Mensaje · Correo · Factura; con tamaños de accesibilidad, en 2×2.
    private var actions: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 2 : 5)
        return LazyVGrid(columns: columns, spacing: 12) {
            ProfileAction(title: String(localized: "Llamar"), systemImage: "phone.fill") {
                if let phoneURL { openURL(phoneURL) }
            }
            .disabled(customer.phone.isEmpty)
            ProfileAction(title: String(localized: "Mensaje"), systemImage: "message.fill") {
                if let url = URL(string: "sms:\(phoneDigits)") { openURL(url) }
            }
            .disabled(customer.phone.isEmpty)
            ProfileAction(title: String(localized: "Correo"), systemImage: "envelope.fill") {
                if let url = URL(string: "mailto:\(customer.email)") { openURL(url) }
            }
            .disabled(customer.email.isEmpty)
            ProfileAction(title: String(localized: "Factura"), systemImage: "doc.badge.plus") { newInvoice = true }
            ProfileAction(title: String(localized: "Estimado"), systemImage: "list.clipboard") { newEstimate = true }
        }
    }

    /// Canvas `ClienteFicha`: «Saldo pendiente» (28 bold), barra vencido / por vencer y «Recordar pago».
    private var balanceCard: some View {
        let total = customer.openBalance
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Saldo pendiente").font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(total.money).font(.amount(28)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                if total > 0 {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            if overdue > 0 {
                                Capsule().fill(Palette.red)
                                    .frame(width: max(4, (proxy.size.width - 2) * CGFloat(overdue) / CGFloat(total)))
                            }
                            if total > overdue { Capsule().fill(Palette.brand) }
                        }
                    }
                    .frame(height: 6)
                    .background(Palette.surface2, in: Capsule())
                    .accessibilityHidden(true)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("Vencido \(overdue.money)").foregroundStyle(overdue > 0 ? Palette.negative : Palette.ink2).fixedSize()
                            Spacer()
                            Text("Por vencer \((total - overdue).money)").foregroundStyle(Palette.ink2).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vencido \(overdue.money)").foregroundStyle(overdue > 0 ? Palette.negative : Palette.ink2)
                            Text("Por vencer \((total - overdue).money)").foregroundStyle(Palette.ink2)
                        }
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 12)
            if total > 0, let reminderInvoice {
                Divider().padding(.leading, Metrics.cardPadding)
                Button { reminding = reminderInvoice } label: {
                    Label(remindedToday ? "Recordatorio enviado hoy" : "Recordar pago", systemImage: remindedToday ? "checkmark.circle" : "bell")
                        .foregroundStyle(remindedToday ? Palette.positive : Palette.brand)
                        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 0)
    }

    /// «Facturado en 2026: $18,940.00 · Paga en promedio en 21 días».
    private var balanceFootnote: String {
        let billed = String(localized: "Facturado en \(Date.now.formatted(.appDateTime.year())): \(billedThisYear.money)")
        guard let days = averageDaysToPay else { return billed }
        return billed + " · " + String(localized: "Paga en promedio en \(days) días")
    }

    private var nextDue: Date? { openInvoices.filter { $0.daysOverdue() == nil }.map(\.dueDate).min() }

    private var billedThisYear: Int64 {
        let year = Calendar.current.component(.year, from: .now)
        return (customer.invoices ?? [])
            .filter { $0.status != .draft && $0.status != .void && Calendar.current.component(.year, from: $0.issueDate) == year }
            .reduce(0) { $0 + $1.total }
    }

    /// Días entre la fecha de la factura y su último cobro, de media entre las facturas pagadas.
    private var averageDaysToPay: Int? {
        let days = (customer.invoices ?? []).filter { $0.status == .paid }.compactMap { invoice -> Int? in
            guard let paid = (invoice.paymentApplications ?? []).compactMap(\.payment?.date).max() else { return nil }
            return Calendar.current.dateComponents([.day], from: invoice.issueDate, to: paid).day
        }
        return days.isEmpty ? nil : days.reduce(0, +) / days.count
    }

    private var creditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Saldo a favor", value: customer.creditBalance.money)
                .foregroundStyle(Palette.positive).fontWeight(.semibold)
            Text("Viene de notas de crédito que superaron lo que debía. Para usarlo en una factura, abre la factura pendiente y elige «Aplicar saldo a favor».")
                .font(.footnote).foregroundStyle(Palette.ink2)
            Button("Reembolsar", systemImage: "arrow.uturn.backward") { refunding = true }.buttonStyle(.secondary)
        }
        .card()
    }

    // MARK: Pestañas

    /// Facturas y cobros, del más reciente al más antiguo, con un punto del color de su estado.
    private var history: some View {
        let invoices = (customer.invoices ?? []).map { HistoryItem.invoice($0) }
        let payments = (customer.payments ?? []).map { HistoryItem.payment($0) }
        let estimates = estimates.map { HistoryItem.estimate($0) }
        let items = (invoices + payments + estimates).sorted { $0.date > $1.date }
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text("Sin facturas").foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .padding(.horizontal, Metrics.cardPadding)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                switch item {
                case .invoice(let invoice):
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: { historyRow(item, chevron: true) }.buttonStyle(.plain)
                case .estimate(let estimate):
                    NavigationLink { EstimateDetailView(estimate: estimate) } label: { historyRow(item, chevron: true) }.buttonStyle(.plain)
                case .payment:
                    historyRow(item, chevron: false)
                }
            }
        }
        .card(padding: 0)
    }

    private func historyRow(_ item: HistoryItem, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    StatusDot(color: item.dot)
                    Text(item.title).font(.body).foregroundStyle(Palette.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Text(item.subtitle).font(.footnote).foregroundStyle(Palette.ink2).padding(.leading, 14)
            }
            Spacer(minLength: 8)
            Text(item.amount).font(.body).monospacedDigit().foregroundStyle(item.amountColor)
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Canvas `ClienteFicha` · Contacto: etiqueta pequeña encima y el valor (en Tinta si abre algo).
    private var contact: some View {
        let rows: [(String, String, URL?)] = [
            (String(localized: "Contacto"), customer.contactLine, nil),
            (String(localized: "Correo"), customer.email, customer.email.isEmpty ? nil : URL(string: "mailto:\(customer.email)")),
            (String(localized: "Teléfono"), customer.phone, phoneURL),
            (String(localized: "Dirección de facturación"), customer.billingAddress, nil),
        ] + (customer.shippingAddress.isEmpty ? [] : [(String(localized: "Dirección de envío"), customer.shippingAddress, nil)])
          + (customer.taxID.isEmpty ? [] : [(String(localized: "ID fiscal"), customer.taxID, nil)]) + [
            (String(localized: "Condiciones"), termsText, nil),
            (String(localized: "Sales tax"), customer.isTaxExempt ? String(localized: "Exento") : String(localized: "Gravable"), nil),
        ]
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let (title, value, link) = rows[index]
                if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.footnote).foregroundStyle(Palette.ink)
                    if let link {
                        Button(value) { openURL(link) }.buttonStyle(.plain).foregroundStyle(Palette.brand)
                    } else {
                        Text(value.isEmpty ? "—" : value).foregroundStyle(Palette.ink)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 0)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            datedNotes
            fixedNote
        }
    }
}

/// «Nueva nota» de la ficha del cliente: el texto y la fecha (hoy).
struct CustomerNoteEditor: View {
    let customer: Customer
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @State private var text = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                TextField("Nota", text: $text, prompt: Text("Qué quieres recordar de \(customer.name)"), axis: .vertical)
                    .lineLimit(4...)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            } footer: {
                Text("Las notas solo las ves tú; no salen en las facturas.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Nueva nota")
        .inlineTitle()
        .discardableEditor(tracking: "\(text)|\(date)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .headerButton()
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 280)
        #endif
        #if DEBUG
        // `-qa.nota.texto <texto>`: escribe y guarda la nota sola (pruebas del Mac sin teclado).
        .task {
            guard let qaText = UserDefaults.standard.string(forKey: "qa.nota.texto") else { return }
            try? await Task.sleep(for: .seconds(1))
            text = qaText
            try? await Task.sleep(for: .seconds(0.5))
            save()
        }
        #endif
    }

    private func save() {
        do {
            try Bookkeeper(context: context).addNote(to: customer, text: text, date: date)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Una entrada del historial de un cliente.
private enum HistoryItem: Identifiable {
    case invoice(Invoice)
    case payment(PaymentReceived)
    case estimate(Estimate)

    var id: UUID {
        switch self {
        case .invoice(let invoice): invoice.id
        case .payment(let payment): payment.id
        case .estimate(let estimate): estimate.id
        }
    }

    var date: Date {
        switch self {
        case .invoice(let invoice): invoice.issueDate
        case .payment(let payment): payment.date
        case .estimate(let estimate): estimate.issueDate
        }
    }

    var title: String {
        switch self {
        case .invoice(let invoice):
            if invoice.number.isEmpty { return String(localized: "Factura en borrador") }
            return String(localized: "Factura \(invoice.number) · \(invoice.statusTitle.lowercased())")
        case .payment(let payment):
            let numbers = (payment.applications ?? []).compactMap(\.invoice?.number).joined(separator: ", ")
            return numbers.isEmpty ? String(localized: "Pago recibido") : String(localized: "Pago recibido · \(numbers)")
        case .estimate(let estimate):
            // Canvas `ClienteFicha`: «Estimado E-0009 · aceptado».
            return String(localized: "Estimado \(estimate.number) · \(estimate.statusTitle.lowercased())")
        }
    }

    /// «21 oct · vence 20 nov», «8 oct · venció 23 oct» o «29 sep · transferencia».
    var subtitle: String {
        switch self {
        case .invoice(let invoice):
            if invoice.isOpen, invoice.daysOverdue() != nil {
                return String(localized: "\(invoice.issueDate.dayMonth) · venció \(invoice.dueDate.dayMonth)")
            }
            return invoice.isOpen ? "\(invoice.issueDate.dayMonth) · \(invoice.dueDate.dueLabel)" : invoice.issueDate.dayMonth
        case .payment(let payment):
            return "\(payment.date.dayMonth) · \((PaymentMethod(rawValue: payment.methodRaw) ?? .other).title.lowercased())"
        case .estimate(let estimate):
            return estimate.title.isEmpty ? estimate.issueDate.dayMonth : "\(estimate.issueDate.dayMonth) · \(estimate.title)"
        }
    }

    var amount: String {
        switch self {
        // Un borrador aún no tiene total guardado: lo que suman sus líneas.
        case .invoice(let invoice): (invoice.status == .draft ? invoice.draftAmount : invoice.total).money
        case .payment(let payment): "+\(payment.amount.money)"
        case .estimate(let estimate): estimate.total.money
        }
    }

    var dot: Color {
        switch self {
        case .invoice(let invoice): invoice.statusDotColor
        case .payment: Palette.green
        case .estimate: Palette.gray
        }
    }

    var amountColor: Color {
        switch self {
        case .invoice(let invoice):
            invoice.daysOverdue() != nil ? Palette.negative : (invoice.status == .void || invoice.status == .draft) ? Palette.ink2 : Palette.ink
        case .payment: Palette.positive
        case .estimate: Palette.ink2
        }
    }
}

/// Cliente nuevo o edición: formulario agrupado del sistema.
struct CustomerEditorView: View {
    var customer: Customer?
    var onCreate: ((Customer) -> Void)?
    /// Nombre con el que empieza un cliente nuevo (el texto buscado en Clientes).
    var initialName = ""

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \TaxGroup.name) private var taxGroups: [TaxGroup]

    @State private var name = ""
    @State private var contactName = ""
    @State private var contactTitle = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var billingAddress = ""
    @State private var taxID = ""
    @State private var terms = 30
    @State private var taxGroupID: UUID?
    @State private var isTaxExempt = false
    @State private var exemptionReason = ""

    init(customer: Customer? = nil, initialName: String = "", onCreate: ((Customer) -> Void)? = nil) {
        self.customer = customer
        self.initialName = initialName
        self.onCreate = onCreate
    }

    var body: some View {
        Form {
            Section {
                TextField("Nombre o empresa", text: $name)
                TextField("Correo", text: $email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Teléfono", text: $phone)
                    #if os(iOS)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    #endif
                TextField("Dirección de facturación", text: $billingAddress, axis: .vertical)
            }
            // Canvas `ClienteFicha` · Contacto: «Laura Méndez · Gerente».
            Section {
                TextField("Nombre", text: $contactName, prompt: Text("Nombre de la persona"))
                    .textContentType(.name)
                TextField("Cargo", text: $contactTitle, prompt: Text("Cargo (opcional)"))
                    .textContentType(.jobTitle)
            } header: {
                SectionLabel(text: String(localized: "Persona de contacto"))
            } footer: {
                Text("A quién te diriges en los correos y quién suele aceptar los estimados.")
            }
            Section(title: "Cobro") {
                TextField("ID fiscal", text: $taxID, prompt: Text("ID fiscal (opcional)"))
                Picker("Condiciones de pago", selection: $terms) {
                    Text("Al recibir").tag(0)
                    Text("Neto 15").tag(15)
                    Text("Neto 30").tag(30)
                    Text("Neto 60").tag(60)
                }
                Picker("Impuesto por defecto", selection: $taxGroupID) {
                    Text("Sin impuesto").tag(UUID?.none)
                    ForEach(taxGroups) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Exento de sales tax", isOn: $isTaxExempt)
                if isTaxExempt { TextField("Motivo (reventa, sin fines de lucro…)", text: $exemptionReason) }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(customer == nil ? "Nuevo cliente" : "Editar cliente")
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|\(contactName)|\(contactTitle)|\(email)|\(phone)|\(billingAddress)|\(taxID)|\(terms)|\(taxGroupID?.uuidString ?? "")|\(isTaxExempt)|\(exemptionReason)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).headerButton()
            }
        }
        .onAppear {
            guard let customer else {
                if name.isEmpty { name = initialName }
                return
            }
            name = customer.name; email = customer.email; phone = customer.phone
            contactName = customer.contactName; contactTitle = customer.contactTitle; taxID = customer.taxID
            billingAddress = customer.billingAddress; terms = customer.paymentTermsDays
            taxGroupID = customer.defaultTaxGroupID; isTaxExempt = customer.isTaxExempt
            exemptionReason = customer.exemptionReason
        }
    }

    private func save() {
        let target = customer ?? Customer(name: name)
        if customer == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.email = email; target.phone = phone; target.billingAddress = billingAddress
        target.contactName = contactName.trimmingCharacters(in: .whitespaces)
        target.contactTitle = contactTitle.trimmingCharacters(in: .whitespaces)
        target.taxID = taxID.trimmingCharacters(in: .whitespaces)
        target.paymentTermsDays = terms; target.defaultTaxGroupID = taxGroupID
        target.isTaxExempt = isTaxExempt; target.exemptionReason = exemptionReason
        try? context.save()
        if customer == nil { onCreate?(target) }
        unsavedChanges?.remove(editorToken); dismiss()
    }
}

/// Reembolso del saldo a favor del cliente: Debe Cuentas por cobrar / Haber Banco.
struct CustomerRefundView: View {
    let customer: Customer
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var errorMessage: String?

    private var paymentAccounts: [Account] { accounts.filtered { $0 == .bank || $0 == .cash } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Cliente", value: customer.name)
                LabeledContent("Saldo a favor", value: customer.creditBalance.money)
            }
            Section {
                MoneyField(title: String(localized: "Importe a reembolsar"), minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $accountID)
            } footer: {
                Text("Se registra la salida de dinero del banco y se cancela ese saldo a favor en cuentas por cobrar.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Reembolso")
        .inlineTitle()
        .discardableEditor(tracking: "\(amount)|\(date)|\(accountID?.uuidString ?? "")", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Reembolsar", action: save).disabled(amount <= 0 || accountID == nil).headerButton()
            }
        }
        .onAppear {
            amount = customer.creditBalance
            accountID = accountID ?? paymentAccounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).refundCustomerCredit(customer, amount: amount, date: date, from: account)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
