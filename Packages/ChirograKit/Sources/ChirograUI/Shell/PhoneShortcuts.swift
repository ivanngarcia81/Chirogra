import SwiftUI

// MARK: - Pestañas y favoritos a elección del usuario (iPhone)
//
// Decisiones del usuario (12-nov): las dos cosas (pestañas a elección y favoritos arriba en «Más»); Inicio se queda
// fijo (y «Más» al final, porque ahí vive todo lo demás); la elección se guarda en cada aparato (`@AppStorage`, sin
// iCloud). Sin tocar nada, la barra es la de siempre: Inicio · Ventas · Gastos · Banca · Más (decisión del 2-nov).

/// Herramienta que se puede poner como pestaña del iPhone o como favorito de «Más».
enum PhoneTool: Hashable, Identifiable {
    case sales, expenses, banking
    /// Reportes con la lista «Otros reportes» al final (como hoy desde Más).
    case reports
    case report(ReportsView.Kind)
    case taxes, taxRates, deductions
    case chartOfAccounts, journal, ledger, periodClose, auditLog
    case companies

    /// Catálogo en grupos, en el orden de «Más».
    static let groups: [(title: String, tools: [PhoneTool])] = [
        (String(localized: "Día a día"), [.sales, .expenses, .banking]),
        (String(localized: "Reportes"), [.reports] + ReportsView.Kind.allCases.map(PhoneTool.report)),
        (String(localized: "Impuestos"), [.taxes, .taxRates, .deductions]),
        (String(localized: "Contabilidad"), [.journal, .chartOfAccounts, .ledger, .periodClose, .auditLog]),
        (String(localized: "Empresas"), [.companies]),
    ]
    static let all: [PhoneTool] = groups.flatMap(\.tools)

    var id: String {
        switch self {
        case .sales: "sales"
        case .expenses: "expenses"
        case .banking: "banking"
        case .reports: "reports"
        case .report(let kind): "report.\(kind)"
        case .taxes: "taxes"
        case .taxRates: "taxes.rates"
        case .deductions: "taxes.deductions"
        case .chartOfAccounts: "chartOfAccounts"
        case .journal: "journal"
        case .ledger: "ledger"
        case .periodClose: "periodClose"
        case .auditLog: "auditLog"
        case .companies: "companies"
        }
    }

    init?(id: String) {
        guard let tool = Self.all.first(where: { $0.id == id }) else { return nil }
        self = tool
    }

    /// Sección de la app que es la herramienta (las rutas del panel de clientes la buscan en la barra).
    var section: AppSection? {
        switch self {
        case .sales: .sales
        case .expenses: .expenses
        case .banking: .banking
        default: nil
        }
    }

    /// Nombre completo (filas de «Más» y de «Personalizar»).
    var title: String {
        switch self {
        case .sales: AppSection.sales.title
        case .expenses: AppSection.expenses.title
        case .banking: AppSection.banking.title
        case .reports: String(localized: "Todos los reportes")
        case .report(let kind): kind.fullTitle
        case .taxes: String(localized: "Impuestos")
        case .taxRates: String(localized: "Tasas de sales tax")
        case .deductions: String(localized: "Deducibles")
        case .chartOfAccounts: String(localized: "Plan de cuentas")
        case .journal: String(localized: "Asientos de diario")
        case .ledger: String(localized: "Libro mayor")
        case .periodClose: String(localized: "Cierre de periodo")
        case .auditLog: String(localized: "Bitácora de cambios")
        case .companies: String(localized: "Empresas")
        }
    }

    /// Nombre corto, para la etiqueta de la pestaña.
    var tabTitle: String {
        switch self {
        case .reports: String(localized: "Reportes")
        // «Balance general» y «Flujo de efectivo» no caben en la pestaña.
        case .report(.balance): String(localized: "Balance", comment: "Pestaña del iPhone: balance general")
        case .report(.cashFlow): String(localized: "Flujo", comment: "Pestaña del iPhone: flujo de efectivo")
        case .report(let kind): kind.localizedTitle
        case .taxRates: String(localized: "Tasas")
        case .chartOfAccounts: String(localized: "Cuentas")
        case .journal: String(localized: "Diario")
        case .ledger: String(localized: "Mayor")
        case .periodClose: String(localized: "Cierre")
        case .auditLog: String(localized: "Bitácora")
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .sales: AppSection.sales.systemImage
        case .expenses: AppSection.expenses.systemImage
        case .banking: AppSection.banking.systemImage
        case .reports: "chart.bar.doc.horizontal"
        case .report(let kind): kind.moreSymbol
        case .taxes: "percent"
        case .taxRates: "list.number"
        case .deductions: "dollarsign"
        case .chartOfAccounts: "list.bullet.indent"
        case .journal: "doc.plaintext"
        case .ledger: "book.closed"
        case .periodClose: "lock"
        case .auditLog: "clock.arrow.circlepath"
        case .companies: "building.2"
        }
    }

    var color: Color {
        switch self {
        case .sales: Palette.indigo
        case .expenses: Palette.orange
        case .banking: Palette.blue
        case .reports: Palette.green
        case .report(let kind): kind.moreColor
        case .taxes: Palette.red
        case .taxRates: Palette.pink
        case .deductions: Palette.green
        case .chartOfAccounts: Palette.indigo
        case .journal: Palette.blue
        case .ledger: Palette.teal
        case .periodClose: Palette.gray
        case .auditLog: Palette.orange
        case .companies: Palette.orange
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .sales: SalesView()
        case .expenses: ExpensesView()
        case .banking: BankingView()
        case .reports: ReportsView()
        case .report(let kind): ReportsView(fixedKind: kind)
        case .taxes: TaxesView()
        case .taxRates: TaxesView(tab: .rates)
        case .deductions: TaxesView(tab: .deductions)
        case .chartOfAccounts: ChartOfAccountsView()
        case .journal: JournalListView()
        case .ledger: LedgerAccountPickerView()
        case .periodClose: PeriodCloseView()
        case .auditLog: AuditLogView()
        case .companies: CompaniesView()
        }
    }
}

/// Lo elegido en este aparato: las pestañas entre Inicio y «Más», y los favoritos de «Más». Se guarda como ids
/// separados por comas en `UserDefaults` (por aparato, sin iCloud).
enum PhoneShortcuts {
    static let tabsKey = "phone.tabs"
    static let favoritesKey = "more.favorites"
    /// Inicio + 3 + «Más» = 5: con más, el sistema agruparía el resto en su propio «Más».
    static let maxTabs = 3
    static let defaultTabs: [PhoneTool] = [.sales, .expenses, .banking]
    static let defaultTabsRaw = encode(defaultTabs)

    static func decode(_ raw: String) -> [PhoneTool] {
        var seen = Set<String>()
        return raw.split(separator: ",").compactMap { PhoneTool(id: String($0)) }.filter { seen.insert($0.id).inserted }
    }

    static func encode(_ tools: [PhoneTool]) -> String { tools.map(\.id).joined(separator: ",") }

    static func tabs(from raw: String) -> [PhoneTool] { Array(decode(raw).prefix(maxTabs)) }
}

// MARK: - Personalizar

#if os(iOS)

/// «Más › Personalizar › Pestañas»: como «Personalizar controles» de iOS, lo puesto arriba (quitar con el signo menos y
/// ordenar arrastrando) y el resto abajo, con el signo más.
struct CustomizeTabsView: View {
    @AppStorage(PhoneShortcuts.tabsKey) private var raw = PhoneShortcuts.defaultTabsRaw

    private var tabs: [PhoneTool] { PhoneShortcuts.tabs(from: raw) }
    private var isFull: Bool { tabs.count >= PhoneShortcuts.maxTabs }

    var body: some View {
        List {
            Section {
                TabBarPreview(tools: tabs)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                SectionLabel(text: String(localized: "Así se verá"))
            }

            Section {
                FixedToolRow(title: AppSection.home.title, systemImage: AppSection.home.systemImage, color: Palette.brand)
                ForEach(tabs) { tool in ToolLabel(tool: tool) }
                    .onMove { from, to in
                        var list = tabs
                        list.move(fromOffsets: from, toOffset: to)
                        raw = PhoneShortcuts.encode(list)
                    }
                    .onDelete { offsets in
                        var list = tabs
                        list.remove(atOffsets: offsets)
                        raw = PhoneShortcuts.encode(list)
                    }
                FixedToolRow(title: String(localized: "Más"), systemImage: "ellipsis.circle", color: Palette.gray)
            } header: {
                SectionLabel(text: String(localized: "En la barra"))
            } footer: {
                Text("Inicio y Más siempre están. Entre ellos caben \(PhoneShortcuts.maxTabs) herramientas: arrastra para ordenarlas.")
            }

            AddToolSections(chosen: tabs, isFull: isFull,
                            fullNote: String(localized: "La barra está llena: quita una pestaña para poner otra.")) { tool in
                raw = PhoneShortcuts.encode(tabs + [tool])
            }

            Section {
                Button("Restablecer la barra") { raw = PhoneShortcuts.defaultTabsRaw }
                    .disabled(raw == PhoneShortcuts.defaultTabsRaw)
            } footer: {
                Text("Vuelve a Inicio · Ventas · Gastos · Banca · Más. Lo que elijas se guarda solo en este aparato.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Pestañas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Más › Personalizar › Favoritos»: lo que sale arriba de «Más», sin límite.
struct CustomizeFavoritesView: View {
    @AppStorage(PhoneShortcuts.favoritesKey) private var raw = ""

    private var favorites: [PhoneTool] { PhoneShortcuts.decode(raw) }

    var body: some View {
        List {
            Section {
                if favorites.isEmpty {
                    Text("Todavía no hay favoritos.").foregroundStyle(Palette.ink2)
                }
                ForEach(favorites) { tool in ToolLabel(tool: tool) }
                    .onMove { from, to in
                        var list = favorites
                        list.move(fromOffsets: from, toOffset: to)
                        raw = PhoneShortcuts.encode(list)
                    }
                    .onDelete { offsets in
                        var list = favorites
                        list.remove(atOffsets: offsets)
                        raw = PhoneShortcuts.encode(list)
                    }
            } header: {
                SectionLabel(text: String(localized: "Favoritos"))
            } footer: {
                Text("Salen arriba en Más, en este orden. También puedes mantener pulsada cualquier herramienta de Más para añadirla.")
            }

            AddToolSections(chosen: favorites, isFull: false, fullNote: "") { tool in
                raw = PhoneShortcuts.encode(favorites + [tool])
            }

            if !favorites.isEmpty {
                Section {
                    Button("Quitar todos los favoritos", role: .destructive) { raw = "" }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Las herramientas que aún no están, en grupos, con el signo más verde.
private struct AddToolSections: View {
    let chosen: [PhoneTool]
    let isFull: Bool
    let fullNote: String
    let add: (PhoneTool) -> Void

    var body: some View {
        let ids = Set(chosen.map(\.id))
        // El aviso de barra llena va bajo el primer grupo que se ve (con la barra de fábrica, «Día a día» no sale).
        let firstVisible = PhoneTool.groups.first { $0.tools.contains { !ids.contains($0.id) } }?.title
        ForEach(PhoneTool.groups, id: \.title) { group in
            let available = group.tools.filter { !ids.contains($0.id) }
            if !available.isEmpty {
                Section {
                    ForEach(available) { tool in
                        Button { add(tool) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, isFull ? Palette.gray : Palette.green)
                                ToolLabel(tool: tool)
                            }
                        }
                        .disabled(isFull)
                        .accessibilityLabel(String(localized: "Añadir \(tool.title)"))
                    }
                } header: {
                    SectionLabel(text: group.title)
                } footer: {
                    if isFull, group.title == firstVisible { Text(fullNote) }
                }
            }
        }
    }
}

/// Icono de color y nombre, como las filas de «Más».
struct ToolLabel: View {
    let tool: PhoneTool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: tool.systemImage, foreground: tool.color).accessibilityHidden(true)
            Text(tool.title).foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inicio y Más en «Personalizar»: se ven en su sitio, con un candado, y no se pueden mover ni quitar.
private struct FixedToolRow: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, foreground: color)
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Image(systemName: "lock.fill").foregroundStyle(Palette.ink2).font(.footnote)
                .accessibilityLabel("Fija")
        }
        .moveDisabled(true)
        .deleteDisabled(true)
    }
}

/// Dibujo de la barra con lo elegido, para ver el resultado antes de salir.
private struct TabBarPreview: View {
    let tools: [PhoneTool]

    var body: some View {
        HStack(spacing: 0) {
            item(AppSection.home.title, AppSection.home.systemImage, selected: true)
            ForEach(tools) { item($0.tabTitle, $0.systemImage) }
            item(String(localized: "Más"), "ellipsis.circle")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Capsule().fill(Palette.background))
        .accessibilityElement(children: .combine)
    }

    private func item(_ title: String, _ systemImage: String, selected: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 19))
            Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(selected ? Palette.brand : Palette.ink2)
        .frame(maxWidth: .infinity)
    }
}
#endif
