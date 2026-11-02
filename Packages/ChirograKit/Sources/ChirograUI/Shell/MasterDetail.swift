import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Páginas de lista y detalle que en iPad y Mac van en una vista dividida de tres columnas: barra lateral, lista
/// (columna maestro, de altura completa, con su título, búsqueda, filtro y botones en la barra) y detalle (§7.4,
/// decisión del usuario; se aparta de los tableros, que ponían la lista o una tabla dentro del contenido).
/// Las de tabla o reporte a todo el ancho (Inicio, Reportes, Libro mayor, Cierre, Impuestos, Ajustes) no cambian.
enum MasterPage: Hashable {
    case invoices, customers, expenses, vendors, bills, banking, journal, chart

    init?(_ item: SidebarItem) {
        switch item {
        case .section(.sales), .sales(.invoices): self = .invoices
        case .sales(.customers): self = .customers
        case .section(.expenses), .expenses(.expenses): self = .expenses
        case .expenses(.vendors): self = .vendors
        case .expenses(.bills): self = .bills
        case .section(.banking): self = .banking
        case .accounting(.journal): self = .journal
        case .accounting(.chart): self = .chart
        default: return nil
        }
    }

    /// Detalle sin nada elegido.
    fileprivate var placeholder: (image: String, title: String) {
        switch self {
        case .invoices: ("doc.text", String(localized: "Elige una factura"))
        case .customers: ("person.2", String(localized: "Elige un cliente"))
        case .expenses: ("wallet.bifold", String(localized: "Elige un gasto"))
        case .vendors: ("shippingbox", String(localized: "Elige un proveedor"))
        case .bills: ("doc.text", String(localized: "Elige una factura por pagar"))
        case .banking: ("building.columns", String(localized: "Elige una cuenta"))
        case .journal: ("doc.plaintext", String(localized: "Elige un asiento"))
        case .chart: ("list.bullet.indent", String(localized: "Elige una cuenta"))
        }
    }
}

/// Filtros de las columnas maestro (los `rawValue` son las etiquetas en español del catálogo).
enum InvoiceScope: String, CaseIterable, Identifiable {
    case open = "Abiertas", overdue = "Vencidas", all = "Todas"
    var id: String { rawValue }
}

enum VendorFilter: String, CaseIterable, Identifiable {
    case all = "Todos", withBalance = "Con saldo", form1099 = "1099"
    var id: String { rawValue }
}

enum BillFilter: String, CaseIterable, Identifiable {
    case open = "Por pagar", overdue = "Vencidas", thisWeek = "Esta semana", paid = "Pagadas"
    var id: String { rawValue }
}

/// Lo que crea «+ Movimiento» en Banca.
enum NewMovement: String, Identifiable {
    case expense, entry
    var id: String { rawValue }
}

// MARK: - Columnas

/// Columna maestro de la página: la selección manda en el detalle.
struct MasterColumn: View {
    let page: MasterPage
    @Binding var selection: UUID?

    var body: some View {
        switch page {
        case .invoices: InvoiceMasterList(selection: $selection)
        case .customers: CustomerMasterList(selection: $selection)
        case .expenses: ExpenseMasterList(selection: $selection)
        case .vendors: VendorMasterList(selection: $selection)
        case .bills: BillMasterList(selection: $selection)
        case .banking: BankingMasterList(selection: $selection)
        case .journal: JournalMasterList(selection: $selection)
        case .chart: ChartMasterList(selection: $selection)
        }
    }
}

/// Columna de detalle: la ficha de lo elegido o, sin nada elegido, un estado vacío.
struct MasterDetailColumn: View {
    let page: MasterPage
    let selection: UUID?

    var body: some View {
        if let id = selection {
            switch page {
            case .invoices: ModelLookup(id: id, key: \Invoice.id, page: page) { InvoiceDetailView(invoice: $0) }
            case .customers: ModelLookup(id: id, key: \Customer.id, page: page) { CustomerDetailView(customer: $0) }
            case .expenses: ModelLookup(id: id, key: \Expense.id, page: page) { ExpenseDetailView(expense: $0) }
            case .vendors: ModelLookup(id: id, key: \Vendor.id, page: page) { VendorDetailView(vendor: $0) }
            case .bills: ModelLookup(id: id, key: \Bill.id, page: page) { BillDetailView(bill: $0) }
            case .banking: ModelLookup(id: id, key: \Account.id, page: page) { BankAccountDetail(account: $0) }
            case .journal: ModelLookup(id: id, key: \JournalEntry.id, page: page) { JournalEntryDetailView(entry: $0) }
            case .chart: ModelLookup(id: id, key: \Account.id, page: page) { LedgerView(account: $0, inDetailColumn: true) }
            }
        } else {
            MasterPlaceholder(page: page)
        }
    }
}

/// Movimientos de la cuenta elegida en Banca: la tabla del mes si el detalle es ancho; si es estrecho (iPad vertical
/// con la lista a la vista, o un Mac de 1000 pt), el libro mayor en lista, porque la tabla no cabe. Se decide con el
/// ancho que ofrece la columna: los anchos mínimos de la tabla ensanchaban la ventana del Mac de 1000 a 1099 pt.
private struct BankAccountDetail: View {
    let account: Account

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 720 { LedgerView(account: account, inDetailColumn: true) } else { table }
        }
    }

    private var table: some View {
        ScrollView { AccountMovementsView(account: account).padding(20) }
            .background(Palette.background)
            .navigationTitle(account.name)
            .inlineTitle()
    }
}

private struct MasterPlaceholder: View {
    let page: MasterPage

    var body: some View {
        EmptyStateView(systemImage: page.placeholder.image, title: page.placeholder.title,
                       message: String(localized: "Lo que elijas en la lista se abre aquí."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
    }
}

/// Busca el registro elegido entre los del modelo; si ya no existe (un borrador descartado), el estado vacío.
private struct ModelLookup<Model: PersistentModel, Content: View>: View {
    let id: UUID
    let key: KeyPath<Model, UUID>
    let page: MasterPage
    @ViewBuilder let content: (Model) -> Content
    @Query private var models: [Model]

    var body: some View {
        if let model = models.first(where: { $0[keyPath: key] == id }) {
            content(model)
        } else {
            MasterPlaceholder(page: page)
        }
    }
}

// MARK: - Piezas comunes

/// Filtro de la columna maestro, encima de la lista. Con tamaños de accesibilidad o más de tres opciones, chips que
/// pasan de línea: el segmentado no crece con el texto.
private struct MasterFilterBar<Option: Hashable & Identifiable & RawRepresentable>: View where Option.RawValue == String {
    let options: [Option]
    @Binding var selection: Option
    var count: ((Option) -> Int)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // Más de tres opciones no caben en un segmentado de 300 pt: chips.
            if dynamicTypeSize.isAccessibilitySize || options.count > 3 {
                FlowLayout(spacing: 6) {
                    ForEach(options) { option in
                        FilterChip(title: option.localizedTitle, count: count?(option), isSelected: selection == option) { selection = option }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Filtrar", selection: $selection) {
                    ForEach(options) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Título, búsqueda y aspecto comunes de las columnas maestro.
private struct MasterListStyle: ViewModifier {
    let title: String
    @Binding var query: String
    let prompt: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            #if os(iOS)
            // Si el sistema pinta la selección, en el mismo lavado que `masterRow` y no en el color de marca.
            .tint(Palette.brandWash)
            #endif
            .navigationTitle(title)
            .masterTitle()
            .searchable(text: $query, prompt: Text(prompt))
    }
}

/// Fila compacta de la columna maestro (como la lista de `iPadVentas`): nombre e importe arriba; detalle y estado
/// abajo. Cabe en los 300 pt de la columna sin recortar el nombre a las pocas letras; con tamaños de accesibilidad,
/// todo en columna.
private struct MasterRow<Badge: View>: View {
    let title: String
    let amount: String
    let subtitle: String
    var amountColor = Palette.ink
    @ViewBuilder var badge: Badge
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(amountColor)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.ink3)
                    badge
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(amountColor).fixedSize()
                    }
                    HStack {
                        Text(subtitle).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                        Spacer(minLength: 8)
                        badge
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Título de la columna maestro: en el iPad, en la fila de la barra junto a «+», como en Mail con la lista
    /// estrecha. Grande (`.inlineLarge`) quedaba debajo de la barra: el filtro fijo lo tapaba (hueco vacío) o, con el
    /// filtro en la barra, el efecto de borde lo desenfocaba. En el Mac, el de la ventana.
    func masterTitle() -> some View {
        #if os(iOS)
        toolbarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Fila de la columna maestro con su selección: fondo lavado de marca y texto en sus colores (AA en claro y en
    /// oscuro). Con el relleno de marca del sistema, el texto quedaba en ~2,5:1 y la línea de abajo en ~1,2:1.
    func masterRow(_ id: UUID, selection: UUID?) -> some View {
        tag(id).listRowBackground(id == selection ? Palette.brandWash : Palette.surface)
    }

    /// Filtro de la columna, fijo encima de la lista con fondo opaco. Con `safeAreaBar` formaba parte de la barra y
    /// el efecto de borde dejaba borroso el título grande.
    func masterFilter<Filter: View>(@ViewBuilder _ filter: () -> Filter) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { filter().background(Palette.surface) }
    }

    func masterList(_ title: String, query: Binding<String>, prompt: LocalizedStringKey) -> some View {
        modifier(MasterListStyle(title: title, query: query, prompt: prompt))
    }

    /// Botón «+» de la columna: icono y texto, en el vidrio de la barra (§7.4). Sin `title`, solo «+» con su etiqueta
    /// de accesibilidad: en el iPad el título de la columna comparte la fila con el botón, y un texto largo («+ Factura
    /// de proveedor») ocupaba la fila y el sistema ocultaba el título.
    func masterAddButton(_ title: String?, label: String, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        if let title { Text(title) }
                    }
                }
                .accessibilityLabel(label)
                .help(label)
                .headerButton()
            }
        }
    }
}

private func matches(_ text: String, _ fields: String...) -> Bool {
    let text = text.trimmingCharacters(in: .whitespaces)
    return text.isEmpty || fields.contains { $0.localizedStandardContains(text) }
}

// MARK: - Ventas

private struct InvoiceMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @State private var scope: InvoiceScope = .open
    @State private var query = ""
    @State private var creating = false

    private func inScope(_ invoice: Invoice, _ scope: InvoiceScope) -> Bool {
        switch scope {
        case .open: invoice.isOpen && invoice.balanceDue > 0 || invoice.status == .draft
        case .overdue: invoice.daysOverdue() != nil
        case .all: true
        }
    }

    private var filtered: [Invoice] {
        invoices.filter {
            inScope($0, scope) && matches(query, $0.number, $0.customer?.name ?? "", $0.total.money)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { invoice in
                MasterRow(title: invoice.customer?.name ?? String(localized: "Sin cliente"),
                          amount: (invoice.isOpen ? invoice.balanceDue : invoice.status == .draft ? invoice.draftAmount : invoice.total).money,
                          subtitle: "\(invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number) · \(invoice.dueDate.dueLabel)") {
                    StatusChip(invoice: invoice)
                }
                .masterRow(invoice.id, selection: selection)
            }
            if filtered.isEmpty {
                Text("Ninguna factura coincide").font(.subheadline).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Ventas"), query: $query, prompt: "Cliente, número o monto")
        .masterFilter {
            MasterFilterBar(options: InvoiceScope.allCases, selection: $scope) { option in
                invoices.filter { inScope($0, option) }.count
            }
        }
        .masterAddButton(String(localized: "Factura"), label: String(localized: "Nueva factura")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { InvoiceEditorView() }.editorSheetSizing() }
    }
}

private struct CustomerMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var filter: CustomerListView.Filter = .all
    @State private var query = ""
    @State private var creating = false

    private func inFilter(_ customer: Customer, _ filter: CustomerListView.Filter) -> Bool {
        switch filter {
        case .all: true
        case .withBalance: customer.openBalance > 0
        case .overdue: customer.overdueBalance > 0
        }
    }

    private var filtered: [Customer] {
        customers.filter { !$0.isArchived && inFilter($0, filter) && matches(query, $0.name, $0.email, $0.phone) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { customer in
                let late = customer.overdueBalance
                MasterRow(title: customer.name, amount: customer.openBalance.money,
                          subtitle: customer.email.isEmpty ? customer.phone : customer.email) {
                    if late > 0 {
                        StatusChip(text: String(localized: "Vencido"), foreground: Palette.negative, background: Palette.negativeWash)
                    } else if customer.openBalance > 0 {
                        StatusChip(text: String(localized: "Al día"), foreground: Palette.positive, background: Palette.positiveWash)
                    }
                }
                .masterRow(customer.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(customers.isEmpty ? String(localized: "Sin clientes todavía") : String(localized: "Ningún cliente coincide con «\(query)»."))
                    .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Clientes"), query: $query, prompt: "Nombre, correo o teléfono")
        .masterFilter { MasterFilterBar(options: CustomerListView.Filter.allCases, selection: $filter) }
        .masterAddButton(String(localized: "Cliente"), label: String(localized: "Nuevo cliente")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { CustomerEditorView() }.editorSheetSizing() }
    }
}

// MARK: - Gastos

private struct ExpenseMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var withoutReceipt = false
    @State private var query = ""
    @State private var creating = false

    private func category(_ expense: Expense) -> Account? {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }
    }

    private var filtered: [Expense] {
        expenses.filter {
            (!withoutReceipt || ($0.attachments ?? []).isEmpty)
                && matches(query, $0.payee, category($0)?.name ?? "", $0.total.money)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { expense in
                MasterRow(title: expense.payee, amount: "−\(expense.total.money)",
                          subtitle: "\(category(expense)?.name ?? String(localized: "Sin categoría")) · \(expense.date.dayMonth)",
                          amountColor: Palette.outflow) {
                    if !(expense.attachments ?? []).isEmpty {
                        Image(systemName: "paperclip").font(.caption).foregroundStyle(Palette.ink3).accessibilityLabel("Recibo adjunto")
                    }
                }
                .masterRow(expense.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(expenses.isEmpty ? String(localized: "Sin gastos todavía") : String(localized: "Ningún gasto coincide"))
                    .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Gastos"), query: $query, prompt: "Beneficiario, categoría o monto")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle(isOn: $withoutReceipt) { Label("Solo sin recibo", systemImage: "paperclip") }
                    .headerButton()
            }
        }
        .masterAddButton(String(localized: "Gasto"), label: String(localized: "Nuevo gasto")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { ExpenseEditorView() }.editorSheetSizing() }
    }
}

private struct VendorMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var filter: VendorFilter = .all
    @State private var query = ""
    @State private var creating = false

    private var filtered: [Vendor] {
        vendors.filter { vendor in
            let inFilter = switch filter {
            case .all: true
            case .withBalance: vendor.openBalance > 0
            case .form1099: vendor.is1099
            }
            return !vendor.isArchived && inFilter && matches(query, vendor.name, vendor.email)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { vendor in
                MasterRow(title: vendor.name, amount: vendor.openBalance.money,
                          subtitle: vendor.email.isEmpty ? String(localized: "Proveedor") : vendor.email) {
                    if vendor.is1099 {
                        StatusChip(text: "1099", foreground: Palette.ink2, background: Palette.surface2)
                    }
                }
                .masterRow(vendor.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(vendors.isEmpty ? String(localized: "Sin proveedores") : String(localized: "Ningún proveedor coincide"))
                    .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Proveedores"), query: $query, prompt: "Nombre o correo")
        .masterFilter { MasterFilterBar(options: VendorFilter.allCases, selection: $filter) }
        .masterAddButton(String(localized: "Proveedor"), label: String(localized: "Nuevo proveedor")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { VendorEditorView() }.editorSheetSizing() }
    }
}

private struct BillMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var filter: BillFilter = .open
    @State private var query = ""
    @State private var creating = false

    private var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now }

    private func inFilter(_ bill: Bill, _ filter: BillFilter) -> Bool {
        switch filter {
        case .open: bill.isOpen
        case .overdue: bill.isOverdue
        case .thisWeek: bill.isOpen && !bill.isOverdue && bill.dueDate < weekEnd
        case .paid: bill.status == .paid
        }
    }

    private var filtered: [Bill] {
        bills.filter { inFilter($0, filter) && matches(query, $0.vendor?.name ?? "", $0.vendorNumber, $0.total.money) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { bill in
                MasterRow(title: bill.vendor?.name ?? String(localized: "Proveedor"), amount: bill.balanceDue.money,
                          subtitle: bill.vendorNumber.isEmpty ? bill.dueDate.dueLabel : "\(bill.vendorNumber) · \(bill.dueDate.dueLabel)") {
                    StatusChip(bill: bill)
                }
                .masterRow(bill.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(bills.isEmpty ? String(localized: "Sin facturas por pagar") : String(localized: "Ninguna factura coincide"))
                    .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Facturas por pagar"), query: $query, prompt: "Proveedor, número o monto")
        .masterFilter {
            MasterFilterBar(options: BillFilter.allCases, selection: $filter) { option in
                bills.filter { inFilter($0, option) }.count
            }
        }
        .masterAddButton(nil, label: String(localized: "Nueva factura de proveedor")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { BillEditorView() }.editorSheetSizing() }
    }
}

// MARK: - Banca

/// Cuentas de dinero con su saldo en libros; el detalle, los movimientos del mes de la elegida.
private struct BankingMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var adding: NewMovement?

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        List(selection: $selection) {
            ForEach(shown) { account in
                MasterRow(title: account.name, amount: ledger.cashBalance(of: account).money,
                          subtitle: String(localized: "Saldo en libros · \(account.code)")) {
                    Image(systemName: account.subtype == .creditCard ? "creditcard" : "building.columns")
                        .font(.caption).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                .masterRow(account.id, selection: selection)
            }
            Section {
                Label("Importar y conciliar · Próximamente", systemImage: "square.and.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityLabel("Importar y conciliar, disponible en una próxima versión")
                    .selectionDisabled()
                    .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        #if os(iOS)
        .tint(Palette.brandWash)
        #endif
        .navigationTitle("Banca")
        .masterTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Gasto", systemImage: "wallet.bifold") { adding = .expense }
                    Button("Asiento manual", systemImage: "list.bullet.rectangle") { adding = .entry }
                } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Movimiento") }
                }
                .accessibilityLabel("Nuevo movimiento")
                .headerButton()
            }
        }
        .sheet(item: $adding) { kind in
            NavigationStack {
                switch kind {
                case .expense: ExpenseEditorView()
                case .entry: JournalEntryEditorView()
                }
            }
            .editorSheetSizing()
        }
    }
}

// MARK: - Contabilidad

private struct JournalMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var query = ""
    @State private var creating = false

    private var filtered: [JournalEntry] {
        entries.filter { matches(query, $0.memo, "#\($0.number)", $0.source.title, $0.totalDebits.money) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { entry in
                MasterRow(title: entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo,
                          amount: entry.totalDebits.money,
                          subtitle: "#\(entry.number) · \(entry.date.shortDate) · \(entry.source.title)") {
                    if entry.isReversed || entry.reversesEntryID != nil {
                        StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                                   foreground: Palette.ink3, background: Palette.surface2)
                    }
                }
                .masterRow(entry.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(entries.isEmpty ? String(localized: "Sin asientos") : String(localized: "Ningún asiento coincide"))
                    .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .masterList(String(localized: "Asientos de diario"), query: $query, prompt: "Concepto, número o monto")
        .masterAddButton(String(localized: "Asiento"), label: String(localized: "Nuevo asiento")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { JournalEntryEditorView() }.presentationSizing(.page) }
    }
}

private struct ChartMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var showArchived = false
    @State private var query = ""
    @State private var creating = false
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 48

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        List(selection: $selection) {
            ForEach(AccountType.allCases, id: \.self) { type in
                let rows = accounts.filter { $0.type == type && (showArchived || !$0.isArchived) && matches(query, $0.code, $0.name) }
                if !rows.isEmpty {
                    Section(heading: type.title) {
                        ForEach(rows) { account in
                            HStack {
                                Text(account.code).foregroundStyle(Palette.ink3).frame(minWidth: codeWidth, alignment: .leading)
                                // Una línea por dato: en una columna estrecha (Mac de 1000 pt) el importe se partía.
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name).strikethrough(account.isArchived).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text(account.subtype.title).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink2).fixedSize()
                            }
                            .accessibilityElement(children: .combine)
                            .masterRow(account.id, selection: selection)
                            .contextMenu {
                                if !account.isSystem {
                                    Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                                }
                            }
                        }
                    }
                }
            }
        }
        .masterList(String(localized: "Plan de cuentas"), query: $query, prompt: "Código o nombre")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) { Toggle("Archivadas", isOn: $showArchived).headerButton() }
        }
        .masterAddButton(nil, label: String(localized: "Nueva cuenta")) { creating = true }
        .sheet(isPresented: $creating) { NavigationStack { AccountEditorView() } }
    }
}

// MARK: - Factura por pagar

/// Ficha de una factura de proveedor (detalle de «Facturas por pagar»): proveedor, número, fechas, líneas, pagos y
/// «Registrar pago» mientras quede saldo.
struct BillDetailView: View {
    let bill: Bill
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var paying = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(bill.vendor?.name ?? String(localized: "Proveedor")).font(.title3.weight(.semibold))
                        Spacer(minLength: 8)
                        StatusChip(bill: bill)
                    }
                    Text(bill.balanceDue.money).font(.amount(28)).foregroundStyle(Palette.ink)
                    Text(bill.isOpen ? String(localized: "Saldo por pagar · \(bill.dueDate.dueLabel)") : String(localized: "Total \(bill.total.money)"))
                        .font(.subheadline).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                }
                .accessibilityElement(children: .combine)
                if bill.isOpen {
                    Button("Registrar pago") { paying = true }.buttonStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                }
            }
            .listRowBackground(Palette.surface)

            Section("Factura") {
                LabeledContent("Número", value: bill.vendorNumber.isEmpty ? "—" : bill.vendorNumber)
                LabeledContent("Fecha", value: bill.billDate.shortDate)
                LabeledContent("Vence", value: bill.dueDate.shortDate)
                LabeledContent("Total", value: bill.total.money)
                if !bill.memo.isEmpty { LabeledContent("Notas", value: bill.memo) }
            }
            .listRowBackground(Palette.surface)

            if !bill.sortedLines.isEmpty {
                Section("Líneas") {
                    ForEach(bill.sortedLines) { line in
                        LabeledContent {
                            Text(line.amount.money).monospacedDigit()
                        } label: {
                            Text(line.details.isEmpty ? (accounts.first { $0.id == line.accountID }?.name ?? "—") : line.details)
                            if !line.details.isEmpty, let account = accounts.first(where: { $0.id == line.accountID }) {
                                Text(account.name)
                            }
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }

            let payments = (bill.payments ?? []).sorted { $0.date > $1.date }
            if !payments.isEmpty {
                Section("Pagos") {
                    ForEach(payments) { payment in
                        LabeledContent(payment.date.shortDate) { Text(payment.amount.money).monospacedDigit() }
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .navigationTitle(bill.vendorNumber.isEmpty ? String(localized: "Factura por pagar") : bill.vendorNumber)
        .inlineTitle()
        .sheet(isPresented: $paying) { NavigationStack { PayBillView(bill: bill) } }
    }
}

// MARK: - Enlaces a una sección

extension EnvironmentValues {
    /// En iPad y Mac, abre una entrada de la barra lateral (por ejemplo «Ver todas» de Inicio lleva a Ventas, con su
    /// columna maestro). En el iPhone no hay barra lateral y es `nil`: los enlaces abren la pantalla encima.
    @Entry var openSidebarItem: OpenSidebarItemAction? = nil
}

/// Acción de `openSidebarItem`, en una estructura como `OpenURLAction`: un cierre suelto en el entorno invalidaría
/// a quienes lo leen en cada actualización.
struct OpenSidebarItemAction {
    let action: (SidebarItem) -> Void
    func callAsFunction(_ item: SidebarItem) { action(item) }
}

/// Enlace a la pantalla de una sección: en iPad y Mac cambia la barra lateral; en el iPhone, la abre encima.
struct SectionLink<Label: View, Destination: View>: View {
    let item: SidebarItem
    @ViewBuilder let destination: Destination
    @ViewBuilder let label: Label
    @Environment(\.openSidebarItem) private var openSidebarItem

    var body: some View {
        if let openSidebarItem {
            Button { openSidebarItem(item) } label: { label }
        } else {
            NavigationLink { destination } label: { label }
        }
    }
}
