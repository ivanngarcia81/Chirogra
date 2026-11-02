#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Plan de cuentas como tabla + inspector (canvas `MacPlanCuentas`). Arriba el segmentado por tipo con su cuenta
/// (y «Mostrar archivadas» si hay alguna) y la tabla Número · Cuenta · Tipo · Tipo de detalle · Saldo, con las
/// subcuentas sangradas bajo su cuenta principal, a la que suman. El inspector muestra la cuenta elegida (saldo de hoy,
/// Cuenta, Grupo) con «Ver libro mayor» y «Archivar»; doble clic abre su libro mayor (`MacLibroMayor`, `LedgerView`).
/// «Exportar CSV» en la barra, como el canvas.
struct ChartTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var companies: [Company]
    @State private var filter: ChartFilter = .all
    @State private var showArchived = false
    @State private var query = ""
    @State private var creating = false
    @State private var openedLedger: Account?

    var body: some View {
        let chart = ChartBalances(accounts: accounts, lines: journalLines)
        let visible = accounts.filter { showArchived || !$0.isArchived }
        let rows = visible.filter { filter.matches($0) && matches($0) }.map { chart.row(for: $0) }
        let hasArchived = accounts.contains(where: \.isArchived)
        MacTablePage(
            title: String(localized: "Plan de cuentas"),
            subtitle: subtitle,
            rows: rows, footer: footer(shown: rows.count, total: visible.count, hasSubaccounts: chart.hasSubaccounts),
            query: $query, searchPrompt: Text("Número o nombre"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\ChartRow.code)],
            addTitle: String(localized: "Nueva cuenta"), onAdd: { creating = true },
            onOpen: { openedLedger = $0.account },
            empty: accounts.isEmpty
                ? MacTableEmpty(systemImage: "list.bullet.indent", title: String(localized: "Sin cuentas"),
                                message: String(localized: "El plan de cuentas está vacío."),
                                actionTitle: String(localized: "Nueva cuenta"), action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ninguna cuenta coincide con la búsqueda."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { row in row.map { "\($0.code) · \($0.name)" } ?? String(localized: "Cuenta") },
            inspectorPlaceholder: String(localized: "Selecciona una cuenta para ver su saldo.")
        ) {
            TableColumn("Número", value: \.code) { row in
                MacCellText(text: row.code).monospacedDigit()
            }
            .width(min: 58, ideal: 66, max: 100)
            TableColumn("Cuenta", value: \.name) { row in
                Text(row.name)
                    .strikethrough(row.account.isArchived)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(row.depth) * 16)
            }
            .width(min: 140, ideal: 190)
            TableColumn("Tipo", value: \.typeRank) { row in
                MacCellText(text: row.account.type.title)
            }
            .width(min: 70, ideal: 88, max: 140)
            TableColumn("Tipo de detalle", value: \.detail) { row in
                MacCellText(text: row.detail)
            }
            .width(min: 90, ideal: 150, max: 240)
            TableColumn("Saldo", value: \.balance) { row in
                Text(row.balance.money).monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 150)
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
            ChartAccountInspector(row: row, groupTotal: chart.total(of: row.account.type))
        } actions: { row in
            Button("Ver libro mayor") { openedLedger = row.account }.buttonStyle(.primary)
            if !row.account.isSystem {
                Button(row.account.isArchived ? "Restaurar" : "Archivar") { row.account.isArchived.toggle() }
                    .buttonStyle(.secondary)
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
        .navigationDestination(item: $openedLedger) { LedgerView(account: $0, inDetailColumn: true) }
        #if DEBUG
        // `-qa.abrir 1` abre el libro mayor de la fila elegida con `-qa.fila`.
        .task {
            try? await Task.sleep(for: .seconds(1))
            guard UserDefaults.standard.bool(forKey: "qa.abrir"), let id = selection,
                  let account = accounts.first(where: { $0.id == id }) else { return }
            openedLedger = account
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

/// Filtro por tipo (canvas: «Tipo: Todas · Activo · Pasivo · …»). El canvas separa «Costo de ventas», que en el modelo
/// es un tipo de detalle de los gastos: va con Gastos.
private enum ChartFilter: Hashable, CaseIterable {
    case all
    case type(AccountType)

    static var allCases: [ChartFilter] { [.all] + AccountType.allCases.map { .type($0) } }

    var title: String {
        switch self {
        case .all: String(localized: "Todas")
        case .type(let type): type.title
        }
    }

    func matches(_ account: Account) -> Bool {
        switch self {
        case .all: true
        case .type(let type): account.type == type
        }
    }
}

/// Saldos de hoy de todas las cuentas, calculados una vez: el propio de cada cuenta y, en una cuenta principal, la
/// suma con sus subcuentas (canvas: «Las subcuentas suman en su cuenta principal»).
private struct ChartBalances {
    private var own: [UUID: Int64] = [:]
    private var totalsByType: [AccountType: Int64] = [:]
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
            totalsByType[account.type, default: 0] += balance
        }
        hasSubaccounts = accounts.contains { $0.parent != nil }
    }

    /// Saldo de la cuenta con el de sus subcuentas.
    func balance(of account: Account) -> Int64 {
        (own[account.id] ?? 0) + (account.children ?? []).reduce(0) { $0 + balance(of: $1) }
    }

    /// Total del grupo (todas las cuentas del tipo; cada movimiento cuenta una sola vez).
    func total(of type: AccountType) -> Int64 { totalsByType[type] ?? 0 }

    func row(for account: Account) -> ChartRow {
        var depth = 0
        var parent = account.parent
        while let current = parent, depth < 4 { depth += 1; parent = current.parent }
        return ChartRow(id: account.id, account: account, code: account.code, name: account.name, depth: depth,
                        typeRank: AccountType.allCases.firstIndex(of: account.type) ?? 0,
                        detail: account.subtype.title, balance: balance(of: account))
    }
}

/// Fila de la tabla: la cuenta con su saldo (con subcuentas) y claves de orden `nonisolated`.
private nonisolated struct ChartRow: Identifiable {
    let id: UUID
    let account: Account
    let code: String
    let name: String
    /// Nivel de subcuenta (0 = cuenta principal), para la sangría.
    let depth: Int
    /// Orden del tipo: Activos, Pasivos, Patrimonio, Ingresos, Gastos.
    let typeRank: Int
    let detail: String
    let balance: Int64
}

/// Inspector de la cuenta (canvas `MacPlanCuentas`): «Saldo al …» de 24 con el tipo debajo; Cuenta (Número, Nombre,
/// Tipo, Tipo de detalle, Cuenta principal, Subcuentas, Estado) y Grupo (total del tipo).
private struct ChartAccountInspector: View {
    let row: ChartRow
    let groupTotal: Int64

    var body: some View {
        let account = row.account
        let children = (account.children ?? []).filter { !$0.isArchived }.count
        VStack(alignment: .leading, spacing: 2) {
            Text("Saldo al \(Date.now.shortDate)").font(.label).foregroundStyle(Palette.ink2)
            Text(row.balance.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: "\(account.type.title) · \(account.subtype.title)").font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        MacInspectorSection(title: String(localized: "Cuenta")) {
            MacInspectorRow(String(localized: "Número"), value: account.code)
            MacInspectorRow(String(localized: "Nombre"), value: account.name)
            MacInspectorRow(String(localized: "Tipo"), value: account.type.title)
            MacInspectorRow(String(localized: "Tipo de detalle"), value: account.subtype.title)
            if !account.details.isEmpty { MacInspectorRow(String(localized: "Descripción"), value: account.details) }
            MacInspectorRow(String(localized: "Cuenta principal"), value: account.parent?.displayName ?? "—")
            MacInspectorRow(String(localized: "Subcuentas"), value: children == 0 ? String(localized: "Ninguna") : "\(children)")
            MacInspectorRow(String(localized: "Estado"),
                            value: account.isArchived ? String(localized: "Archivada") : String(localized: "Activa"),
                            color: account.isArchived ? Palette.ink2 : Palette.ink)
        }
        MacInspectorSection(title: String(localized: "Grupo")) {
            MacInspectorRow(String(localized: "Total de \(account.type.title.lowercased())"), value: groupTotal.money, bold: true)
        }
        if account.isSystem {
            Text("Cuenta del sistema: Chirogra la usa al contabilizar los documentos y no se puede archivar.")
                .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
