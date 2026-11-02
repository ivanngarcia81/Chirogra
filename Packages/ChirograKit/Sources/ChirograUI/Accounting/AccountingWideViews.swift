import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Plan de cuentas (`MacPlanCuentas`)

/// Búsqueda, chips por tipo y dos columnas (cuentas de balance | de resultados) con Nº · NOMBRE · TIPO DE DETALLE ·
/// SALDO y el total de cada grupo. Cada cuenta abre su libro mayor.
struct ChartOfAccountsWideView: View {
    enum Group: String, CaseIterable, Identifiable {
        case all = "Todas", asset = "Activo", liability = "Pasivo", equity = "Patrimonio", income = "Ingresos"
        case costOfSales = "Costo de ventas", expense = "Gastos"
        var id: String { rawValue }

        /// Título del grupo en la tabla, en mayúsculas como en el canvas.
        var heading: String {
            switch self {
            case .all: ""
            case .asset: String(localized: "ACTIVO")
            case .liability: String(localized: "PASIVO")
            case .equity: String(localized: "PATRIMONIO")
            case .income: String(localized: "INGRESOS")
            case .costOfSales: String(localized: "COSTO DE VENTAS")
            case .expense: String(localized: "GASTOS")
            }
        }

        func contains(_ account: Account) -> Bool {
            switch self {
            case .all: true
            case .asset: account.type == .asset
            case .liability: account.type == .liability
            case .equity: account.type == .equity
            case .income: account.type == .income
            case .costOfSales: account.subtype == .costOfGoodsSold
            case .expense: account.type == .expense && account.subtype != .costOfGoodsSold
            }
        }
    }

    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var query = ""
    @State private var filter: Group = .all
    @State private var showArchived = false
    @State private var showingNew = false
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    private var visible: [Account] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return accounts.filter { account in
            (showArchived || !account.isArchived) && filter.contains(account)
                && (text.isEmpty || account.code.localizedStandardContains(text) || account.name.localizedStandardContains(text))
        }
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let balanceGroups: [Group] = [.asset, .liability, .equity]
        let resultGroups: [Group] = [.income, .costOfSales, .expense]
        // Dos columnas sólo si los nombres caben enteros; si no, una debajo de otra.
        let twoColumns = width - 40 >= 2 * 540 + 16
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MacPageTitle(String(localized: "Plan de cuentas"))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { search.frame(maxWidth: 280); chips }
                    VStack(alignment: .leading, spacing: 10) { search; ScrollView(.horizontal, showsIndicators: false) { chips } }
                }
                let left = table(balanceGroups, ledger)
                let right = table(resultGroups, ledger)
                if twoColumns {
                    HStack(alignment: .top, spacing: 16) { left.frame(maxWidth: .infinity); right.frame(maxWidth: .infinity) }
                } else {
                    left
                    right
                }
                if visible.isEmpty {
                    Text("Ninguna cuenta coincide").font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Plan de cuentas")
        .headerTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Archivadas", isOn: $showArchived).headerButton()
                ShareLink(item: csvFile(ledger), preview: SharePreview("\(String(localized: "Plan de cuentas")).csv")) {
                    Text("Exportar CSV")
                }
                .headerButton()
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Cuenta") }
                }
                .accessibilityLabel("Nueva cuenta")
                .headerButton()
            }
        }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() } }
    }

    private var search: some View { WideSearchField(prompt: "Número o nombre", text: $query) }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(Group.allCases) { option in
                FilterChip(title: option.localizedTitle, isSelected: filter == option) { filter = option }
            }
        }
    }

    @ViewBuilder
    private func table(_ groups: [Group], _ ledger: Ledger) -> some View {
        let shown = groups.filter { group in visible.contains { group.contains($0) } }
        if !shown.isEmpty {
            TableCard {
                Text("Nº").frame(width: 52, alignment: .leading)
                Text("Nombre").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tipo de detalle").frame(width: 150, alignment: .leading)
                Text("Saldo").frame(width: amountWidth, alignment: .trailing)
            } rows: {
                ForEach(shown) { group in
                    let members = accounts.filter { group.contains($0) && (showArchived || !$0.isArchived) }
                    HStack {
                        Text(group.heading).tracking(0.6)
                        Spacer(minLength: 8)
                        Text(members.reduce(0) { $0 + ledger.balance(of: $1) }.money)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink2)
                    .monospacedDigit()
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
                    .background { Rectangle().fill(Palette.background) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(visible.filter { group.contains($0) }) { account in
                        NavigationLink { LedgerView(account: account) } label: { row(account, ledger) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !account.isSystem {
                                    Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                                }
                            }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(_ account: Account, _ ledger: Ledger) -> some View {
        TableRow {
            Text(account.code).foregroundStyle(Palette.ink3).frame(width: 52, alignment: .leading)
            Text(account.name).fontWeight(account.parent == nil ? .semibold : .regular).strikethrough(account.isArchived)
                .lineLimit(1).padding(.leading, account.parent == nil ? 0 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(account.subtype.title).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 150, alignment: .leading)
            Text(ledger.balance(of: account).money).fontWeight(.semibold).frame(width: amountWidth, alignment: .trailing)
        }
    }

    private func csvFile(_ ledger: Ledger) -> CSVFile {
        let rows = accounts.filter { showArchived || !$0.isArchived }
            .map { (code: $0.code, name: $0.name, type: $0.type.title, detail: $0.subtype.title, balance: ledger.balance(of: $0)) }
        return CSVFile(name: String(localized: "Plan de cuentas"), text: CSVExport.chartOfAccounts(rows, asOf: .now))
    }
}

// MARK: - Cierre de periodo (`MacCierre`)

/// Fecha de cierre con su candado, aviso, nueva fecha y «Cerrar … / Reabrir …», y la lista de revisión del mes.
/// La contraseña de cierre y el historial de cierres del canvas no se guardan en el modelo: quedan fuera.
struct PeriodCloseWideView: View {
    @Environment(\.modelContext) private var context
    @Query private var companies: [Company]
    @Query private var invoices: [Invoice]
    @Query private var expenses: [Expense]
    @Query private var bills: [Bill]
    @State private var newDate: Date?

    private let calendar = Calendar.current

    /// Último día del mes de `date`.
    private func endOfMonth(_ date: Date) -> Date {
        let month = DateInterval.month(containing: date)
        return calendar.startOfDay(for: month.end.addingTimeInterval(-1))
    }

    /// Propuesta: el mes siguiente al cierre actual o, sin cierre, el mes pasado.
    private func proposedDate(_ company: Company) -> Date {
        if let lock = company.lockDate { return endOfMonth(calendar.date(byAdding: .day, value: 1, to: lock) ?? lock) }
        return endOfMonth(calendar.date(byAdding: .month, value: -1, to: .now) ?? .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MacPageTitle(String(localized: "Cierre de periodo"))
                Text("Bloquea los meses ya revisados para que nadie los cambie por error.")
                    .font(.subheadline).foregroundStyle(Palette.ink3)
                if let company = companies.first {
                    let target = newDate ?? proposedDate(company)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            lockCard(company, target: target).frame(maxWidth: .infinity)
                            checklist(for: target).frame(width: 340)
                        }
                        VStack(spacing: 16) { lockCard(company, target: target); checklist(for: target) }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Cierre de periodo")
        .headerTitle()
        .onDisappear { try? context.save() }
    }

    private func lockCard(_ company: Company, target: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(systemImage: company.lockDate == nil ? "lock.open" : "lock")
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.lockDate == nil ? String(localized: "Libros abiertos") : String(localized: "Libros cerrados hasta"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                    Text(company.lockDate?.shortDate ?? String(localized: "Sin cierre")).font(.amount(28)).foregroundStyle(Palette.ink)
                }
            }
            .accessibilityElement(children: .combine)
            if let lock = company.lockDate {
                Label("Las transacciones con fecha hasta el \(lock.shortDate) están bloqueadas. Para corregirlas, reabre el periodo.",
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.warning)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warningWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Nueva fecha de cierre").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
                DatePicker("Nueva fecha de cierre", selection: Binding(get: { target }, set: { newDate = $0 }), in: ...Date.now,
                           displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    // En cifras sigue la región (1e6efbf): «10/31/26» en EE. UU.
                    .environment(\.locale, .app)
            }
            HStack(spacing: 10) {
                Button(String(localized: "Cerrar hasta el \(target.shortDate)")) {
                    company.lockDate = calendar.startOfDay(for: target)
                    newDate = nil
                    try? context.save()
                }
                .glassActionButton()
                .disabled(company.lockDate.map { calendar.startOfDay(for: target) <= $0 } ?? false)
                if let lock = company.lockDate {
                    Button(String(localized: "Reabrir \(lock.formatted(.appDateTime.month(.wide).year()))")) {
                        let previous = calendar.date(byAdding: .day, value: -1, to: DateInterval.month(containing: lock).start)
                        // Si el cierre no estaba a fin de mes, reabrir quita sólo ese tramo del mes.
                        company.lockDate = previous.map { calendar.startOfDay(for: $0) }
                        newDate = nil
                        try? context.save()
                    }
                    .buttonStyle(.bordered)
                    Button("Quitar cierre", role: .destructive) {
                        company.lockDate = nil
                        newDate = nil
                        try? context.save()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .controlSize(.large)
        }
        .card()
    }

    /// Lo que conviene revisar del mes que se va a cerrar, con enlace a cada pantalla.
    private func checklist(for target: Date) -> some View {
        let month = DateInterval.month(containing: target)
        let name = target.formatted(.appDateTime.month(.wide))
        let issued = invoices.filter { $0.status != .draft && $0.status != .void && month.contains($0.issueDate) }.count
        let drafts = invoices.filter { $0.status == .draft && month.contains($0.issueDate) }.count
        let monthExpenses = expenses.filter { month.contains($0.date) }
        let noReceipt = monthExpenses.filter { ($0.attachments ?? []).isEmpty }.count
        let monthBills = bills.filter { $0.status != .void && month.contains($0.billDate) }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Antes de cerrar \(name)").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            checkRow(ok: true, String(localized: "Facturas de \(name) emitidas (\(issued))")) { SalesView(fixedSegment: .invoices) }
            if drafts > 0 {
                checkRow(ok: false, String(localized: "\(drafts) borradores de factura sin emitir")) { SalesView(fixedSegment: .invoices) }
            }
            checkRow(ok: true, String(localized: "Gastos de \(name) registrados (\(monthExpenses.count))")) { ExpensesView(fixedSegment: .expenses) }
            checkRow(ok: noReceipt == 0, noReceipt == 0 ? String(localized: "Todos los gastos tienen recibo")
                                                        : String(localized: "\(noReceipt) gastos sin recibo adjunto")) { ExpensesView(fixedSegment: .expenses) }
            checkRow(ok: true, String(localized: "Facturas de proveedor de \(name) (\(monthBills))")) { ExpensesView(fixedSegment: .bills) }
            checkRow(ok: true, String(localized: "Revisa el impuesto sobre ventas")) { ReportsView(fixedKind: .salesTax) }
        }
        .card()
    }

    private func checkRow<Destination: View>(ok: Bool, _ title: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        VStack(spacing: 0) {
            Divider()
            NavigationLink(destination: destination) {
                HStack(spacing: 10) {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(ok ? Palette.positive : Palette.warning)
                        .background(ok ? Palette.positiveWash : Palette.warningWash, in: Circle())
                        .accessibilityLabel(ok ? String(localized: "Listo") : String(localized: "Revisar"))
                    Text(title).font(.subheadline).foregroundStyle(Palette.ink)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
