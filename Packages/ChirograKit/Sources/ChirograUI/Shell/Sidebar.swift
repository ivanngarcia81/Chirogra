import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Páginas de Contabilidad. En iPad y Mac son subsecciones de la barra lateral (canvas `MacDiario`).
enum AccountingPage: String, CaseIterable, Identifiable {
    case chart, journal, ledger, close
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chart: String(localized: "Plan de cuentas")
        case .journal: String(localized: "Asientos de diario")
        case .ledger: String(localized: "Libro mayor")
        case .close: String(localized: "Cierre de periodo")
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .chart: ChartOfAccountsView()
        case .journal: JournalListView()
        case .ledger: LedgerBrowserView()
        case .close: PeriodCloseView()
        }
    }
}

/// Entrada de la barra lateral de iPad y Mac: una sección o una subsección (Ventas, Gastos, Reportes, Contabilidad).
enum SidebarItem: Hashable {
    case section(AppSection)
    case sales(SalesView.Segment)
    case expenses(ExpensesView.Segment)
    case report(ReportsView.Kind)
    case accounting(AccountingPage)

    /// Sección principal a la que pertenece (la que se marca en la barra).
    var section: AppSection {
        switch self {
        case .section(let section): section
        case .sales: .sales
        case .expenses: .expenses
        case .report: .reports
        case .accounting: .accounting
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .section(let section): section.destination
        case .sales(let segment): SalesView(fixedSegment: segment)
        case .expenses(let segment): ExpensesView(fixedSegment: segment)
        case .report(let kind): ReportsView(fixedKind: kind)
        case .accounting(let page): page.destination
        }
    }

    /// Subsecciones de una sección, en el orden del canvas `Sidebar`; vacío si no tiene.
    static func subsections(of section: AppSection) -> [(title: String, item: SidebarItem)] {
        switch section {
        case .sales:
            [(String(localized: "Facturas"), .sales(.invoices)), (String(localized: "Clientes"), .sales(.customers))]
        case .expenses:
            [(String(localized: "Gastos"), .expenses(.expenses)), (String(localized: "Proveedores"), .expenses(.vendors)),
             (String(localized: "Facturas por pagar"), .expenses(.bills))]
        case .reports: ReportsView.Kind.allCases.map { ($0.fullTitle, .report($0)) }
        case .accounting: AccountingPage.allCases.map { ($0.title, .accounting($0)) }
        default: []
        }
    }
}

/// Barra lateral de iPad y Mac (canvas `Sidebar`): logotipo, búsqueda, secciones con la activa en índigo lavado,
/// «MÁS», un grupo con las subsecciones de la sección activa y la empresa al pie con el estado de iCloud.
struct Sidebar: View {
    @Binding var selection: SidebarItem
    @Binding var query: String
    @Query private var companies: [Company]
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var sync = SyncMonitor.shared

    /// Estado de iCloud al pie: sincronizando, sin conexión o sincronizado (`MacCargando`, `MacError`).
    private var syncText: String {
        guard iCloudSyncEnabled || SyncMonitor.forced != nil else { return String(localized: "Solo en este dispositivo") }
        switch sync.state {
        case .syncing: return String(localized: "Sincronizando con iCloud…")
        case .failed: return String(localized: "Sin conexión con iCloud")
        case .off, .synced: return String(localized: "Sincronizado con iCloud")
        }
    }

    private var syncColor: Color {
        guard iCloudSyncEnabled || SyncMonitor.forced != nil else { return Palette.ink3 }
        switch sync.state {
        case .syncing: return Palette.brand
        case .failed: return Palette.negative
        case .off, .synced: return Palette.positive
        }
    }
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    LogoMark(size: 28)
                    Text("Chirogra").font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

                searchField.padding(.bottom, 10)

                ForEach(AppSection.primary) { section in sectionRow(section) }

                groupHeader(String(localized: "Más"))
                ForEach(AppSection.more) { section in sectionRow(section) }

                let subsections = SidebarItem.subsections(of: selection.section)
                if !subsections.isEmpty {
                    groupHeader(selection.section.title)
                    ForEach(subsections, id: \.item) { subRow($0.title, item: $0.item) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) { companyCard }
        // Al vaciar la búsqueda se suelta el foco del campo.
        .onChange(of: query) { _, text in if text.isEmpty { searching = false } }
        .background(Palette.sidebar)
        // ⌘K lleva a la búsqueda, como en el canvas.
        .background {
            Button("Buscar") { searching = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    private func groupHeader(_ title: String) -> some View {
        SectionLabel(text: title)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Búsqueda

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3).accessibilityHidden(true)
            TextField("Buscar", text: $query, prompt: Text(Self.searchPrompt))
                .focused($searching)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(minHeight: Self.rowHeight)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    #if os(macOS)
    private static let searchPrompt = String(localized: "Buscar ⌘K")
    #else
    private static let searchPrompt = String(localized: "Buscar")
    #endif

    // MARK: Filas

    /// Las secciones con subsecciones abren la primera, para que siempre se vea marcada la página abierta.
    private func target(for section: AppSection) -> SidebarItem {
        SidebarItem.subsections(of: section).first?.item ?? .section(section)
    }

    private func sectionRow(_ section: AppSection) -> some View {
        let isActive = query.isEmpty && selection.section == section
        return Button {
            query = ""
            selection = target(for: section)
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.subheadline.weight(isActive ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isActive ? Palette.brand : Palette.ink2)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .background(isActive ? Palette.brandWash : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Subsección de la sección activa: sangrada, sin icono; la abierta con fondo de superficie y en negrita.
    private func subRow(_ title: String, item: SidebarItem) -> some View {
        let isActive = query.isEmpty && selection == item
        return Button {
            query = ""
            selection = item
        } label: {
            // Hasta dos líneas en vez de encogerse: «Balanza de comprobación» quedaba más pequeña que las demás.
            Text(title)
                .font(.footnote.weight(isActive ? .semibold : .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isActive ? Palette.ink : Palette.ink2)
                .padding(.leading, 38)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: Self.subRowHeight, alignment: .leading)
                .background(isActive ? Self.activeSubRow : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Fondo de la subsección abierta: superficie en claro (canvas); en oscuro, un gris más claro que la barra,
    /// porque la superficie oscura casi no se distingue de ella.
    private static let activeSubRow = Color(light: 0xFFFFFF, dark: 0x2B2F47)

    #if os(macOS)
    private static let rowHeight: CGFloat = 34
    private static let subRowHeight: CGFloat = 30
    #else
    private static let rowHeight: CGFloat = 44
    private static let subRowHeight: CGFloat = 44
    #endif

    // MARK: Empresa

    @ViewBuilder
    private var companyCard: some View {
        if let company = companies.first {
            let name = company.displayName.isEmpty ? company.legalName : company.displayName
            Button {
                query = ""
                selection = .section(.settings)
            } label: {
                HStack(spacing: 10) {
                    Text(Initials.from(name))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.background)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .frame(width: 32, height: 32)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                        // Punto verde con iCloud activado, como el canvas («● iCloud»).
                        HStack(spacing: 5) {
                            Circle().fill(syncColor).frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(syncText)
                        }
                        .font(.caption).foregroundStyle(Palette.ink3)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre los ajustes")
            .padding(12)
            .background(Palette.sidebar)
        }
    }
}

/// Resultados de la búsqueda de la barra lateral: facturas, clientes, proveedores, gastos y cuentas.
struct SearchResultsView: View {
    let query: String
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]

    private var text: String { query.trimmingCharacters(in: .whitespaces) }
    /// Sin distinguir mayúsculas ni tildes.
    private func matches(_ value: String) -> Bool { value.localizedStandardContains(text) }

    var body: some View {
        let foundInvoices = invoices.filter { matches($0.number) || matches($0.customer?.name ?? "") || $0.total.money.contains(text) }
        let foundCustomers = customers.filter { !$0.isArchived && (matches($0.name) || matches($0.email)) }
        let foundVendors = vendors.filter { matches($0.name) || matches($0.email) }
        let foundExpenses = expenses.filter { matches($0.payee) || $0.total.money.contains(text) }
        let foundAccounts = accounts.filter { !$0.isArchived && (matches($0.name) || $0.code.hasPrefix(text)) }
        List {
            if foundInvoices.isEmpty && foundCustomers.isEmpty && foundVendors.isEmpty && foundExpenses.isEmpty && foundAccounts.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: String(localized: "Sin resultados"),
                               message: String(localized: "Prueba con un cliente, un número de factura, un proveedor o un monto."))
            }
            if !foundInvoices.isEmpty {
                Section(title: "Facturas") {
                    ForEach(foundInvoices.prefix(20)) { invoice in
                        NavigationLink { InvoiceDetailView(invoice: invoice) } label: { InvoiceRow(invoice: invoice) }
                    }
                }
            }
            if !foundCustomers.isEmpty {
                Section(title: "Clientes") {
                    ForEach(foundCustomers.prefix(20)) { customer in
                        NavigationLink { CustomerDetailView(customer: customer) } label: {
                            LedgerRow(title: customer.name, subtitle: customer.email) {
                                InitialsTile(text: customer.initials)
                            } trailing: {
                                Text(customer.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            if !foundVendors.isEmpty {
                Section(title: "Proveedores") {
                    ForEach(foundVendors.prefix(20)) { vendor in
                        NavigationLink { VendorDetailView(vendor: vendor) } label: {
                            LedgerRow(title: vendor.name, subtitle: vendor.email) {
                                InitialsTile(text: Initials.from(vendor.name), foreground: Palette.outflow, background: Palette.outflowWash)
                            } trailing: {
                                Text(vendor.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            if !foundExpenses.isEmpty {
                Section(title: "Gastos") {
                    ForEach(foundExpenses.prefix(20)) { expense in
                        NavigationLink { ExpenseDetailView(expense: expense) } label: {
                            LedgerRow(title: expense.payee, subtitle: expense.date.shortDate) {
                                IconTile(systemImage: "receipt", foreground: Palette.outflow, background: Palette.outflowWash)
                            } trailing: {
                                Text("−\(expense.total.money)").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.outflow)
                            }
                        }
                    }
                }
            }
            if !foundAccounts.isEmpty {
                Section(title: "Cuentas") {
                    ForEach(foundAccounts.prefix(20)) { account in
                        NavigationLink(account.displayName) { LedgerView(account: account) }
                    }
                }
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationTitle("Resultados de búsqueda")
        .headerTitle()
    }
}
