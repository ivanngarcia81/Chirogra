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
    /// Banca 1.2: Cuentas · Por revisar · Reglas · Conciliación (`BankingPage`, en `Banking/BankInboxViews.swift`).
    case banking(BankingPage)

    /// Sección principal a la que pertenece (la que se marca en la barra).
    var section: AppSection {
        switch self {
        case .section(let section): section
        case .sales: .sales
        case .expenses: .expenses
        case .report: .reports
        case .accounting: .accounting
        case .banking: .banking
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .section(let section): section.destination
        #if os(macOS)
        // Mac: Estimados con tabla + inspector (`EstimateTablePage`). No es una `MasterPage`: así no cambia el `switch`
        // de `MacTablePage.swift`.
        case .sales(.estimates): EstimatesMacPage()
        #endif
        case .sales(let segment): SalesView(fixedSegment: segment)
        case .expenses(let segment): ExpensesView(fixedSegment: segment)
        case .report(let kind): ReportsView(fixedKind: kind)
        case .accounting(let page): page.destination
        case .banking(let page): page.destination
        }
    }

    /// Subsecciones de una sección, en el orden del canvas `Sidebar`; vacío si no tiene.
    static func subsections(of section: AppSection) -> [(title: String, item: SidebarItem)] {
        switch section {
        case .sales:
            [(String(localized: "Facturas"), .sales(.invoices)), (String(localized: "Estimados"), .sales(.estimates)),
             (String(localized: "Clientes"), .sales(.customers))]
        case .expenses:
            [(String(localized: "Gastos"), .expenses(.expenses)), (String(localized: "Proveedores"), .expenses(.vendors)),
             (String(localized: "Facturas por pagar"), .expenses(.bills))]
        case .reports: ReportsView.Kind.allCases.map { ($0.fullTitle, .report($0)) }
        case .accounting: AccountingPage.allCases.map { ($0.title, .accounting($0)) }
        case .banking: BankingPage.allCases.map { ($0.title, .banking($0)) }
        default: []
        }
    }
}

/// Barra lateral de iPad y Mac (canvas `Sidebar`): búsqueda, grupos «Negocio» y «Libros» con los iconos en Tinta, las
/// subsecciones de la sección abierta sangradas debajo de ella, y la empresa al pie con el estado de iCloud.
/// iPad: título «Chirogra» de 28 bold, filas de 46 pt y la elegida rellena de Tinta con texto blanco. Mac: filas de
/// 28 pt sobre el material del sistema y la elegida en el gris de relleno (`fill2`), como las barras del sistema.
struct Sidebar: View {
    @Binding var selection: SidebarItem
    @Binding var query: String
    @ActiveCompanyQuery private var companies: [Company]
    /// Todas, para el selector de la ficha del pie.
    @Query private var selectorCompanies: [Company]
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @State private var sync = SyncMonitor.shared
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = Self.iconSide

    /// Estado de iCloud al pie: sincronizando, sin conexión o sincronizado (`MacCargando`, `MacError`).
    private var syncText: String {
        guard iCloudSyncEnabled || SyncMonitor.forced != nil else { return String(localized: "Solo en este dispositivo") }
        switch sync.state {
        case .syncing: return String(localized: "Sincronizando con iCloud…")
        case .failed: return String(localized: "Sin conexión con iCloud")
        case .off, .synced: return String(localized: "Sincronizado con iCloud")
        }
    }

    private var syncSymbol: String {
        guard iCloudSyncEnabled || SyncMonitor.forced != nil else { return "iphone" }
        return sync.isFailed ? "icloud.slash" : "icloud"
    }

    private var syncColor: Color {
        guard iCloudSyncEnabled || SyncMonitor.forced != nil else { return Palette.ink2 }
        return sync.isFailed ? Palette.warning : Palette.ink2
    }
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                #if os(iOS)
                Text("Chirogra")
                    .font(.title.bold())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                #endif

                searchField.padding(.bottom, 4)

                // Plan para contadores (canvas «Panel de clientes»): «Clientes» arriba, y el primer grupo lleva el nombre
                // de la empresa abierta, para que se vea de quién son las secciones de debajo.
                if ClientsRouter.isAvailable(companies: selectorCompanies) {
                    sectionRow(.clients).padding(.top, 6)
                    group(companies.first?.shownName ?? String(localized: "Negocio"), sections: AppSection.business)
                } else {
                    group(String(localized: "Negocio"), sections: AppSection.business)
                }
                group(String(localized: "Libros"), sections: AppSection.books)
            }
            .padding(.horizontal, Self.panelPadding)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                #if os(macOS)
                // En el Mac el aviso de solo lectura va aquí: arriba de las columnas desplazaba el contenido.
                if SubscriptionStore.shared.isReadOnly { ReadOnlySidebarNote() }
                #endif
                companyCard
            }
        }
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

    @ViewBuilder
    private func group(_ title: String, sections: [AppSection]) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 10)
            .padding(.top, Self.groupTopPadding)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
        ForEach(sections) { section in
            sectionRow(section)
            // Las subsecciones de la sección abierta, debajo de ella (canvas: sangradas a 48 pt en el iPad y 34 en el Mac).
            if selection.section == section {
                ForEach(SidebarItem.subsections(of: section), id: \.item) { subRow($0.title, item: $0.item) }
            }
        }
    }

    // MARK: Búsqueda

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink2).accessibilityHidden(true)
            TextField("Buscar", text: $query, prompt: Text(Self.searchPrompt))
                .focused($searching)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(minHeight: Self.searchHeight)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Self.searchRadius, style: .continuous))
        .padding(.horizontal, 2)
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

    /// Fila de una sección: icono en Tinta y nombre. Si tiene subsecciones, un chevron (abajo si está abierta) y no se
    /// marca: se marca la subsección abierta, como en el canvas.
    private func sectionRow(_ section: AppSection) -> some View {
        let hasSubsections = !SidebarItem.subsections(of: section).isEmpty
        let isOpen = query.isEmpty && selection.section == section
        let isActive = isOpen && !hasSubsections
        return Button {
            query = ""
            selection = target(for: section)
        } label: {
            HStack(spacing: Self.iconGap) {
                // El icono crece poco con el texto: en la barra de 280 pt, con AX3, dejaba «Ex-penses» partido en sílabas.
                Image(systemName: section.systemImage)
                    .font(Self.iconFont)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(isActive && Self.fillsSelection ? Palette.onBrandFill : Palette.brand)
                    .frame(width: min(iconWidth, Self.iconSide * 1.3))
                    .accessibilityHidden(true)
                // Una sola palabra casi siempre: se encoge un poco antes que partirse.
                Text(section.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Banca cerrada: cuántos movimientos esperan en «Por revisar» (abierta, el número va en la subsección).
                if section == .banking && !isOpen { BankPendingBadge(isActive: false) }
                if section == .clients, let count = ClientsRouter.shared.attentionCount, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isActive && Self.fillsSelection ? Palette.onBrandFill : Palette.ink2)
                        .accessibilityLabel(Text("\(count) necesitan atención"))
                }
                if hasSubsections {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .foregroundStyle(foreground(isActive))
            .padding(.horizontal, Self.rowPadding)
            .frame(minHeight: Self.rowHeight)
            .background(background(isActive), in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(hasSubsections ? (isOpen ? Text("Abierta") : Text("Cerrada")) : Text(verbatim: ""))
    }

    /// Subsección de la sección abierta: sangrada, sin icono; la abierta marcada como las secciones.
    private func subRow(_ title: String, item: SidebarItem) -> some View {
        let isActive = query.isEmpty && selection == item
        return Button {
            query = ""
            selection = item
        } label: {
            // Hasta dos líneas en vez de encogerse: «Balanza de comprobación» quedaba más pequeña que las demás.
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item == .banking(.inbox) { BankPendingBadge(isActive: isActive && Self.fillsSelection) }
            }
                .font(.body)
                .foregroundStyle(foreground(isActive))
                .padding(.leading, Self.subIndent)
                .padding(.trailing, Self.rowPadding)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: Self.subRowHeight, alignment: .leading)
                .background(background(isActive), in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func foreground(_ isActive: Bool) -> Color {
        isActive && Self.fillsSelection ? Palette.onBrandFill : Palette.ink
    }

    private func background(_ isActive: Bool) -> Color {
        guard isActive else { return .clear }
        return Self.fillsSelection ? Palette.brandFill : Palette.fill2
    }

    #if os(macOS)
    /// Mac: la elegida en el gris del sistema con el texto en `label`, como las barras laterales de macOS.
    private static let fillsSelection = false
    private static let rowHeight: CGFloat = Metrics.target
    private static let subRowHeight: CGFloat = Metrics.target
    private static let rowRadius: CGFloat = 7
    private static let rowPadding: CGFloat = 8
    private static let subIndent: CGFloat = 34
    private static let iconGap: CGFloat = 8
    private static let iconSide: CGFloat = 18
    private static let iconFont = Font.body
    private static let panelPadding: CGFloat = 8
    private static let groupTopPadding: CGFloat = 12
    private static let searchHeight: CGFloat = 28
    private static let searchRadius: CGFloat = 7
    #else
    /// iPad: la elegida rellena de Tinta con el texto y el icono en blanco (canvas `Sidebar`, device=ipad).
    private static let fillsSelection = true
    private static let rowHeight: CGFloat = 46
    private static let subRowHeight: CGFloat = 44
    private static let rowRadius: CGFloat = 12
    private static let rowPadding: CGFloat = 12
    private static let subIndent: CGFloat = 48
    private static let iconGap: CGFloat = 14
    private static let iconSide: CGFloat = 26
    private static let iconFont = Font.title3
    private static let panelPadding: CGFloat = 10
    private static let groupTopPadding: CGFloat = 18
    private static let searchHeight: CGFloat = 44
    private static let searchRadius: CGFloat = 12
    #endif

    // MARK: Empresa

    /// Empresa al pie (canvas: monograma, nombre, «iCloud · …» y «⌃⌄»): el selector de empresa. Abre el menú con las
    /// empresas, «Añadir empresa…», «Empresas…» y «Ajustes de la empresa».
    @ViewBuilder
    private var companyCard: some View {
        if let company = companies.first {
            let name = company.displayName.isEmpty ? company.legalName : company.displayName
            Menu {
                CompanyMenuItems(companies: selectorCompanies)
                Section {
                    Button("Ajustes de la empresa", systemImage: "gearshape") {
                        query = ""
                        selection = .section(.settings)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    CompanyMonogram(name: name, side: Self.monogramSide)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Label {
                            Text(syncText)
                        } icon: {
                            Image(systemName: syncSymbol).accessibilityHidden(true)
                        }
                        .labelStyle(SidebarCaptionLabelStyle())
                        .font(Self.captionFont)
                        .foregroundStyle(syncColor)
                    }
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Self.captionFont.weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                        .accessibilityHidden(true)
                }
                .padding(8)
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Empresa: \(name)"))
            .accessibilityValue(Text(syncText))
            .accessibilityHint("Cambia de empresa, añade otra o abre sus ajustes")
            .padding(.horizontal, Self.panelPadding)
            .padding(.vertical, 8)
            .background(Palette.sidebar)
        }
    }

    #if os(macOS)
    private static let monogramSide: CGFloat = 28
    private static let captionFont = Font.subheadline
    #else
    private static let monogramSide: CGFloat = 36
    private static let captionFont = Font.footnote
    #endif
}

/// Icono y texto juntos, a 5 pt, como el «☁ iCloud · hace 2 min» del canvas.
private struct SidebarCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

/// Resultados de la búsqueda de la barra lateral: facturas, clientes, proveedores, gastos y cuentas.
struct SearchResultsView: View {
    let query: String
    @CompanyQuery(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @CompanyQuery(sort: \Estimate.issueDate, order: .reverse) private var estimates: [Estimate]
    @CompanyQuery(sort: \Customer.name) private var customers: [Customer]
    @CompanyQuery(sort: \Vendor.name) private var vendors: [Vendor]
    @CompanyQuery(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]

    private var text: String { query.trimmingCharacters(in: .whitespaces) }
    /// Sin distinguir mayúsculas ni tildes.
    private func matches(_ value: String) -> Bool { value.localizedStandardContains(text) }

    var body: some View {
        let foundInvoices = invoices.filter { matches($0.number) || matches($0.customer?.name ?? "") || $0.total.money.contains(text) }
        let foundEstimates = estimates.filter { EstimateFilter.search($0, text) }
        let foundCustomers = customers.filter { !$0.isArchived && (matches($0.name) || matches($0.email)) }
        let foundVendors = vendors.filter { matches($0.name) || matches($0.email) }
        let foundExpenses = expenses.filter { matches($0.payee) || $0.total.money.contains(text) }
        let foundAccounts = accounts.filter { !$0.isArchived && (matches($0.name) || $0.code.hasPrefix(text)) }
        List {
            if foundInvoices.isEmpty && foundEstimates.isEmpty && foundCustomers.isEmpty && foundVendors.isEmpty && foundExpenses.isEmpty
                && foundAccounts.isEmpty {
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
            if !foundEstimates.isEmpty {
                Section(title: "Estimados") {
                    ForEach(foundEstimates.prefix(20)) { estimate in
                        NavigationLink { EstimateDetailView(estimate: estimate) } label: { EstimateRow(estimate: estimate) }
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
                                Text(customer.openBalance.money).monospacedDigit()
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
                                InitialsTile(text: Initials.from(vendor.name))
                            } trailing: {
                                Text(vendor.openBalance.money).monospacedDigit()
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
                                IconTile(systemImage: "receipt", foreground: Palette.orange)
                            } trailing: {
                                Text("−\(expense.total.money)").monospacedDigit().foregroundStyle(Palette.ink)
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

/// Número de movimientos del banco por revisar en la barra lateral (decisión del usuario, 8-nov). Vista aparte para
/// que la consulta no haga redibujar toda la barra; sin pendientes no enseña nada.
private struct BankPendingBadge: View {
    let isActive: Bool
    @CompanyQuery(filter: #Predicate<BankTransaction> { $0.statusRaw == "toReview" }) private var pending: [BankTransaction]

    var body: some View {
        if !pending.isEmpty {
            Text(verbatim: "\(pending.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isActive ? Palette.onBrandFill : Palette.ink2)
                .accessibilityLabel(Text("\(pending.count) por revisar"))
        }
    }
}
