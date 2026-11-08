#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Plan de cuentas como tabla + inspector (canvas `MacPlanCuentas`). Arriba el segmentado por grupo con su cuenta
/// (y «Mostrar archivadas» si hay alguna) y la tabla agrupada por tipo: una fila por grupo (Activos, Pasivos,
/// Patrimonio, Ingresos, Costo de ventas, Gastos) con su número de cuentas, su total y el triángulo para plegarlo; debajo
/// las cuentas (Cuenta · Tipo de detalle · Saldo) y, con su propio triángulo, sus subcuentas, que suman en la cuenta
/// principal. El inspector muestra la cuenta elegida (saldo de hoy, Cuenta, Grupo) con «Editar…», «Ver libro mayor» y
/// «Archivar», o el grupo elegido; doble clic abre su libro mayor (`MacLibroMayor`, `LedgerView`). «Exportar CSV» en la
/// barra, como el canvas.
struct ChartTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @ActiveCompanyQuery private var companies: [Company]
    @Environment(\.modelContext) private var context
    @State private var filter: ChartFilter = .all
    @State private var showArchived = false
    @State private var query = ""
    @State private var creating = false
    @State private var editing: Account?
    @State private var openedLedger: Account?

    var body: some View {
        let chart = ChartBalances(accounts: accounts, lines: journalLines)
        let visible = accounts.filter { showArchived || !$0.isArchived }
        let matching = visible.filter { filter.matches($0) && matches($0) }
        let rows = chart.tree(of: matching, all: visible)
        let hasArchived = accounts.contains(where: \.isArchived)
        MacTablePage(
            title: String(localized: "Plan de cuentas"),
            subtitle: subtitle,
            rows: rows, footer: footer(shown: matching.count, total: visible.count, hasSubaccounts: chart.hasSubaccounts),
            query: $query, searchPrompt: Text("Número o nombre"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\ChartRow.code)],
            addTitle: String(localized: "Nueva cuenta"), onAdd: { creating = true },
            onOpen: { row in if let account = row.account { openedLedger = account } },
            empty: accounts.isEmpty
                ? MacTableEmpty(systemImage: "list.bullet.indent", title: String(localized: "Sin cuentas"),
                                message: String(localized: "El plan de cuentas está vacío."),
                                actionTitle: String(localized: "Nueva cuenta"), action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ninguna cuenta coincide con la búsqueda."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            children: \.children,
            inspectorTitle: { row in
                guard let row else { return String(localized: "Cuenta") }
                return row.account == nil ? row.name : "\(row.code) · \(row.name)"
            },
            inspectorPlaceholder: String(localized: "Selecciona una cuenta para ver su saldo.")
        ) {
            TableColumn("Cuenta", value: \.code) { row in
                ChartNameCell(row: row)
            }
            .width(min: 180, ideal: 280)
            TableColumn("Tipo de detalle", value: \.detail) { row in
                MacCellText(text: row.detail)
            }
            .width(min: 90, ideal: 170, max: 260)
            TableColumn("Saldo", value: \.balance) { row in
                Text(row.balance.money).monospacedDigit().fontWeight(row.account == nil ? .semibold : .regular)
            }
            .width(min: 80, ideal: 110, max: 160)
            .alignment(.trailing)
        } filter: {
            HStack(spacing: 12) {
                MacTableFilter(title: String(localized: "Filtrar por tipo"), options: ChartFilter.allCases,
                               selection: $filter, label: \.title) { option in
                    visible.filter(option.matches).count
                }
                Spacer(minLength: 0)
                if hasArchived {
                    Toggle("Mostrar archivadas", isOn: $showArchived).toggleStyle(.checkbox).fixedSize()
                }
            }
        } inspector: { row in
            if row.account != nil {
                ChartAccountInspector(row: row, groupTotal: chart.total(of: row.group))
            } else {
                ChartGroupInspector(row: row)
            }
        } actions: { row in
            if let account = row.account {
                Button("Ver libro mayor") { openedLedger = account }.buttonStyle(.primary)
                HStack(spacing: 8) {
                    Button("Editar…") { editing = account }.buttonStyle(.secondary)
                    if !account.isSystem {
                        Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                            .buttonStyle(.secondary)
                    }
                }
            } else {
                Button("Nueva cuenta") { creating = true }.buttonStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let file = csvFile(chart)
                ShareLink(item: file, preview: SharePreview("\(file.name).csv")) {
                    Label("Exportar CSV", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                }
                .help("Exportar CSV")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { AccountEditorView() }.editorSheetSizing() }
        .sheet(item: $editing) { account in NavigationStack { AccountEditorView(account: account) }.editorSheetSizing() }
        .navigationDestination(item: $openedLedger) { LedgerView(account: $0, inDetailColumn: true) }
        #if DEBUG
        // `-qa.abrir 1` abre el libro mayor de la fila elegida con `-qa.fila`; `-qa.editar 1`, su editor.
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nuevo") { creating = true; return }
            // `-qa.subcuenta 1510>1500`: hace de 1510 una subcuenta de 1500 (con `updateAccount`, como el editor).
            if let pair = UserDefaults.standard.string(forKey: "qa.subcuenta")?.split(separator: ">").map(String.init), pair.count == 2,
               let child = accounts.first(where: { $0.code == pair[0] }), let parent = accounts.first(where: { $0.code == pair[1] }) {
                var input = AccountInput(child)
                input.parentID = parent.id
                try? Bookkeeper(context: context).updateAccount(child, with: input)
            }
            guard let id = selection, let account = accounts.first(where: { $0.id == id }) else { return }
            if UserDefaults.standard.bool(forKey: "qa.editar") { editing = account; return }
            if UserDefaults.standard.bool(forKey: "qa.abrir") { openedLedger = account }
        }
        #endif
    }

    /// «Construcción y oficios · saldos al 2 nov 2026» (el sector que eligió la plantilla del plan).
    private var subtitle: String {
        let date = Date.now.shortDate
        guard let company = companies.first, let sector = BusinessSector(rawValue: company.sectorRaw) else {
            return String(localized: "Saldos al \(date)")
        }
        return String(localized: "\(sector.title) · saldos al \(date)")
    }

    private func matches(_ account: Account) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || account.code.localizedStandardContains(text) || account.name.localizedStandardContains(text)
    }

    private func footer(shown: Int, total: Int, hasSubaccounts: Bool) -> String {
        let count = shown == total ? String(localized: "\(total) cuentas") : String(localized: "\(shown) de \(total) cuentas")
        return hasSubaccounts ? "\(count) · \(String(localized: "Las subcuentas suman en su cuenta principal."))" : count
    }

    /// El plan de cuentas activo con su tipo, tipo de detalle y saldo de hoy (`CSVExport.chartOfAccounts`).
    private func csvFile(_ chart: ChartBalances) -> CSVFile {
        let rows = accounts.filter { !$0.isArchived }.map { account in
            (code: account.code, name: account.name, type: account.type.title, detail: account.subtype.title,
             balance: chart.balance(of: account))
        }
        return CSVFile(name: String(localized: "Plan de cuentas"), text: CSVExport.chartOfAccounts(rows, asOf: .now))
    }
}

/// Grupo del plan (canvas: Activo · Pasivo · Patrimonio · Ingresos · Costo de ventas · Gastos). «Costo de ventas» es
/// en el modelo un tipo de detalle de los gastos: aquí va en su propio grupo, como el canvas.
enum ChartGroup: Int, CaseIterable, Hashable, Sendable {
    case asset, liability, equity, income, costOfSales, expense

    init(_ account: Account) {
        switch account.type {
        case .asset: self = .asset
        case .liability: self = .liability
        case .equity: self = .equity
        case .income: self = .income
        case .expense: self = account.subtype == .costOfGoodsSold ? .costOfSales : .expense
        }
    }

    var title: String {
        switch self {
        case .asset: AccountType.asset.title
        case .liability: AccountType.liability.title
        case .equity: AccountType.equity.title
        case .income: AccountType.income.title
        case .costOfSales: AccountSubtype.costOfGoodsSold.title
        case .expense: AccountType.expense.title
        }
    }

    /// Identificador fijo de la fila del grupo (no choca con los de las cuentas).
    var rowID: UUID { UUID(uuidString: String(format: "C0A10000-0000-4000-8000-%012d", rawValue + 1))! }
}

/// Filtro por grupo (canvas: «Tipo: Todas · Activo · Pasivo · …»).
private enum ChartFilter: Hashable, CaseIterable {
    case all
    case group(ChartGroup)

    static var allCases: [ChartFilter] { [.all] + ChartGroup.allCases.map { .group($0) } }

    var title: String {
        switch self {
        case .all: String(localized: "Todas")
        case .group(let group): group.title
        }
    }

    func matches(_ account: Account) -> Bool {
        switch self {
        case .all: true
        case .group(let group): ChartGroup(account) == group
        }
    }
}

/// Saldos de hoy de todas las cuentas, calculados una vez: el propio de cada cuenta y, en una cuenta principal, la
/// suma con sus subcuentas (canvas: «Las subcuentas suman en su cuenta principal»).
private struct ChartBalances {
    private var own: [UUID: Int64] = [:]
    private var totalsByGroup: [ChartGroup: Int64] = [:]
    let hasSubaccounts: Bool

    init(accounts: [Account], lines: [JournalLine]) {
        var sums: [UUID: (debit: Int64, credit: Int64)] = [:]
        for line in lines {
            guard let entry = line.entry, entry.status == .posted, let id = line.account?.id else { continue }
            sums[id, default: (0, 0)].debit += line.debit
            sums[id, default: (0, 0)].credit += line.credit
        }
        for account in accounts {
            let sum = sums[account.id] ?? (0, 0)
            let balance = account.type.naturalBalance(debit: sum.debit, credit: sum.credit)
            own[account.id] = balance
            totalsByGroup[ChartGroup(account), default: 0] += balance
        }
        hasSubaccounts = accounts.contains { $0.parent != nil }
    }

    /// Saldo de la cuenta con el de sus subcuentas.
    func balance(of account: Account) -> Int64 {
        (own[account.id] ?? 0) + (account.children ?? []).reduce(0) { $0 + balance(of: $1) }
    }

    /// Total del grupo (todas sus cuentas; cada movimiento cuenta una sola vez).
    func total(of group: ChartGroup) -> Int64 { totalsByGroup[group] ?? 0 }

    /// Filas de la tabla: un grupo por tipo con las cuentas que coinciden (`matching`); dentro, las cuentas principales
    /// con sus subcuentas. Una subcuenta cuya principal no coincide (búsqueda) sube al nivel del grupo.
    func tree(of matching: [Account], all: [Account]) -> [ChartRow] {
        let ids = Set(matching.map(\.id))
        let shown = Set(all.map(\.id))
        func node(_ account: Account) -> ChartRow {
            let kids = (account.children ?? []).filter { ids.contains($0.id) }.map(node)
            return ChartRow(id: account.id, account: account, group: ChartGroup(account), code: account.code, name: account.name,
                            detail: account.subtype.title, balance: balance(of: account), count: 0,
                            children: kids.isEmpty ? nil : kids)
        }
        return ChartGroup.allCases.compactMap { group in
            let members = matching.filter { ChartGroup($0) == group }
            guard !members.isEmpty else { return nil }
            let roots = members.filter { account in account.parent.map { !ids.contains($0.id) } ?? true }
            let count = all.filter { ChartGroup($0) == group && shown.contains($0.id) }.count
            return ChartRow(id: group.rowID, account: nil, group: group, code: String(group.rawValue), name: group.title,
                            detail: "", balance: total(of: group), count: count, children: roots.map(node))
        }
    }
}

/// Fila de la tabla: un grupo (sin cuenta) o una cuenta con su saldo (con subcuentas), y claves de orden `nonisolated`.
nonisolated struct ChartRow: Identifiable {
    let id: UUID
    /// `nil` en la fila del grupo.
    let account: Account?
    let group: ChartGroup
    /// Número de la cuenta; en el grupo, su orden (así «Cuenta ↑» deja los grupos en su orden de siempre).
    let code: String
    let name: String
    let detail: String
    let balance: Int64
    /// Cuentas del grupo (solo en la fila del grupo).
    let count: Int
    var children: [ChartRow]?
}

/// Celda «Cuenta» (canvas: número gris de ancho fijo y nombre; en el grupo, el nombre en negrita y «5 cuentas»).
private struct ChartNameCell: View {
    let row: ChartRow
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 40

    var body: some View {
        if let account = row.account {
            HStack(spacing: 8) {
                MacCellText(text: row.code).monospacedDigit().frame(minWidth: codeWidth, alignment: .leading)
                Text(account.maskedName).strikethrough(account.isArchived).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                Text(row.name).fontWeight(.semibold).lineLimit(1)
                MacCellText(text: String(localized: "\(row.count) cuentas"))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Inspector de la cuenta (canvas `MacPlanCuentas`): «Saldo al …» de 24 con el tipo debajo; Cuenta (Número, Nombre,
/// Tipo, Tipo de detalle, Últimos 4 dígitos, Cuenta principal, Subcuentas, Estado) y Grupo (total del grupo).
private struct ChartAccountInspector: View {
    let row: ChartRow
    let groupTotal: Int64

    var body: some View {
        if let account = row.account {
            let children = (account.children ?? []).filter { !$0.isArchived }.count
            VStack(alignment: .leading, spacing: 2) {
                Text("Saldo al \(Date.now.shortDate)").font(.label).foregroundStyle(Palette.ink2)
                Text(row.balance.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: "\(account.type.title) · \(account.subtype.title)").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)
            MacInspectorSection(title: String(localized: "Cuenta")) {
                MacInspectorRow(String(localized: "Número"), value: account.code.isEmpty ? "—" : account.code)
                MacInspectorRow(String(localized: "Nombre"), value: account.name)
                MacInspectorRow(String(localized: "Tipo"), value: account.type.title)
                MacInspectorRow(String(localized: "Tipo de detalle"), value: account.subtype.title)
                if !account.last4.isEmpty { MacInspectorRow(String(localized: "Últimos 4 dígitos"), value: "••\(account.last4)") }
                if !account.details.isEmpty { MacInspectorRow(String(localized: "Descripción"), value: account.details) }
                MacInspectorRow(String(localized: "Cuenta principal"), value: account.parent?.displayName ?? "—")
                MacInspectorRow(String(localized: "Subcuentas"), value: children == 0 ? String(localized: "Ninguna") : "\(children)")
                MacInspectorRow(String(localized: "Estado"),
                                value: account.isArchived ? String(localized: "Archivada") : String(localized: "Activa"),
                                color: account.isArchived ? Palette.ink2 : Palette.ink)
            }
            MacInspectorSection(title: String(localized: "Grupo")) {
                MacInspectorRow(String(localized: "Total de \(row.group.title.lowercased())"), value: groupTotal.money, bold: true)
            }
            if account.isSystem {
                Text("Cuenta del sistema: Chirogra la usa al contabilizar los documentos y no se puede archivar.")
                    .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Inspector del grupo: su total, cuántas cuentas tiene y sus cuentas principales con su saldo.
private struct ChartGroupInspector: View {
    let row: ChartRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total de \(row.group.title.lowercased())").font(.label).foregroundStyle(Palette.ink2)
            Text(row.balance.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(row.count) cuentas").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        MacInspectorSection(title: String(localized: "Cuentas")) {
            ForEach(row.children ?? []) { child in
                MacInspectorRow(child.account?.displayName ?? child.name, value: child.balance.money)
            }
        }
    }
}
#endif
