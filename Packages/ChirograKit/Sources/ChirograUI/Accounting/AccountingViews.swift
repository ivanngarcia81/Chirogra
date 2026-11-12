import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Contabilidad del iPhone (canvas `Mas` · Contabilidad): plan de cuentas, asientos, libro mayor y cierre, como filas
/// de Ajustes con su icono de color. En iPad y Mac son subsecciones de la barra lateral.
struct AccountingView: View {
    @CompanyQuery private var accounts: [Account]
    @CompanyQuery private var entries: [JournalEntry]
    @ActiveCompanyQuery private var companies: [Company]

    var body: some View {
        List {
            Section {
                row(String(localized: "Plan de cuentas"), String(localized: "\(accounts.filter { !$0.isArchived }.count) cuentas"),
                    "list.bullet.indent", Palette.blue) { ChartOfAccountsView() }
                row(String(localized: "Asientos de diario"), String(localized: "\(entries.count) asientos"),
                    "doc.plaintext", Palette.indigo) { JournalListView() }
                row(String(localized: "Libro mayor"), String(localized: "Movimientos por cuenta"),
                    "book.closed", Palette.teal) { LedgerAccountPickerView() }
                row(String(localized: "Cierre de periodo"),
                    companies.first?.lockDate.map { String(localized: "Cerrado hasta el \($0.shortDate)") } ?? String(localized: "Sin cierre"),
                    "lock", Palette.gray) { PeriodCloseView() }
                row(String(localized: "Bitácora de cambios"), String(localized: "Quién cambió qué y cuándo"),
                    "clock.arrow.circlepath", Palette.orange) { AuditLogView() }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Contabilidad")
        .headerTitle()
    }

    private func row<Destination: View>(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            LedgerRow(title: title, subtitle: subtitle) { IconTile(systemImage: symbol, foreground: color) } trailing: { EmptyView() }
        }
    }
}

extension AccountType {
    var title: String {
        switch self {
        case .asset: String(localized: "Activos")
        case .liability: String(localized: "Pasivos")
        case .equity: String(localized: "Patrimonio")
        case .income: String(localized: "Ingresos")
        case .expense: String(localized: "Gastos")
        }
    }
}

extension AccountSubtype {
    var title: String {
        switch self {
        case .cash: String(localized: "Efectivo")
        case .bank: String(localized: "Banco")
        case .accountsReceivable: String(localized: "Cuentas por cobrar")
        case .undepositedFunds: String(localized: "Fondos no depositados")
        case .inventory: String(localized: "Inventario")
        case .otherCurrentAsset: String(localized: "Otro activo corriente")
        case .fixedAsset: String(localized: "Activo fijo")
        case .otherAsset: String(localized: "Otro activo")
        case .accountsPayable: String(localized: "Cuentas por pagar")
        case .creditCard: String(localized: "Tarjeta de crédito")
        case .salesTaxPayable: String(localized: "Sales tax por pagar")
        case .otherCurrentLiability: String(localized: "Otro pasivo corriente")
        case .longTermLiability: String(localized: "Pasivo a largo plazo")
        case .ownersEquity: String(localized: "Capital")
        case .ownersDraw: String(localized: "Retiros")
        case .retainedEarnings: String(localized: "Resultados acumulados")
        case .openingBalanceEquity: String(localized: "Saldos de apertura")
        case .sales: String(localized: "Ventas")
        case .salesDiscount: String(localized: "Descuentos sobre ventas")
        case .otherIncome: String(localized: "Otros ingresos")
        case .costOfGoodsSold: String(localized: "Costo de ventas")
        case .operatingExpense: String(localized: "Gasto operativo")
        case .otherExpense: String(localized: "Otro gasto")
        }
    }
}

/// Plan de cuentas del iPhone: grupos por tipo con código, nombre, tipo de detalle y saldo (canvas `MacPlanCuentas`,
/// en lista). Cada cuenta abre su libro mayor.
struct ChartOfAccountsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 48
    @CompanyQuery private var journalLines: [JournalLine]
    @State private var showingNew = false
    @State private var editing: Account?
    @State private var showArchived = false
    @State private var query = ""

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let text = query.trimmingCharacters(in: .whitespaces)
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                let rows = accounts.filter {
                    $0.type == type && (showArchived || !$0.isArchived)
                        && (text.isEmpty || $0.code.localizedStandardContains(text) || $0.name.localizedStandardContains(text))
                }
                if !rows.isEmpty {
                    Section {
                        ForEach(Self.outline(rows), id: \.account.id) { item in
                            let account = item.account
                            NavigationLink { LedgerView(account: account) } label: {
                                if dynamicTypeSize.isAccessibilitySize {
                                    // Con letra de accesibilidad, en líneas: en fila, el nombre y el saldo se partían
                                    // («corrien-te», «$39,29 / 0.00», QA del 10-nov).
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.maskedName).strikethrough(account.isArchived).foregroundStyle(Palette.ink)
                                        Text(verbatim: "\(account.code) · \(account.subtype.title)").font(.footnote).foregroundStyle(Palette.ink2)
                                        Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink)
                                    }
                                    .padding(.leading, CGFloat(item.depth) * 16)
                                    .accessibilityElement(children: .combine)
                                } else {
                                HStack(spacing: 12) {
                                    Text(account.code).foregroundStyle(Palette.ink2).monospacedDigit().frame(minWidth: codeWidth, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(account.maskedName).strikethrough(account.isArchived).foregroundStyle(Palette.ink)
                                        Text(account.subtype.title).font(.footnote).foregroundStyle(Palette.ink2)
                                    }
                                    // Subcuenta: sangrada bajo su cuenta principal (canvas `MacPlanCuentas`).
                                    .padding(.leading, CGFloat(item.depth) * 16)
                                    Spacer(minLength: 8)
                                    Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink)
                                }
                                .accessibilityElement(children: .combine)
                                }
                            }
                            .swipeActions {
                                if !account.isSystem {
                                    Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                                }
                                Button("Editar") { editing = account }.tint(Palette.blue)
                            }
                            .contextMenu {
                                Button("Editar…", systemImage: "pencil") { editing = account }
                                if !account.isSystem {
                                    Button(account.isArchived ? "Restaurar" : "Archivar",
                                           systemImage: account.isArchived ? "arrow.uturn.backward" : "archivebox") { account.isArchived.toggle() }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(type.title)
                            Spacer()
                            Text(String(localized: "\(rows.count) cuentas"))
                        }
                        .font(.label).foregroundStyle(Palette.ink2).textCase(nil)
                    }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .searchable(text: $query, prompt: Text("Código o nombre"))
        .navigationTitle("Plan de cuentas")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddButton(title: "Nueva cuenta") { showingNew = true } }
            ToolbarItem { Toggle("Archivadas", isOn: $showArchived).headerButton() }
        }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() }.editorSheetSizing() }
        .sheet(item: $editing) { account in NavigationStack { AccountEditorView(account: account) }.editorSheetSizing() }
    }

    /// Las cuentas con sus subcuentas justo debajo y su nivel (0 = principal). Una subcuenta cuya principal no está en
    /// la lista (búsqueda, archivada) va en el primer nivel.
    static func outline(_ accounts: [Account]) -> [(account: Account, depth: Int)] {
        let ids = Set(accounts.map(\.id))
        func walk(_ account: Account, _ depth: Int) -> [(account: Account, depth: Int)] {
            let kids = accounts.filter { $0.parent?.id == account.id }
            return [(account, depth)] + kids.flatMap { walk($0, min(depth + 1, 4)) }
        }
        return accounts.filter { $0.parent.map { !ids.contains($0.id) } ?? true }.flatMap { walk($0, 0) }
    }
}

/// Filtro por origen: todos, los manuales (con los ajustes del contador), los ajustes del contador (1.2), los que generan
/// los documentos (facturas, cobros, gastos…) y los revertidos o de reversión. En el Mac va en la tabla; en el iPad, en
/// la columna, y en el iPhone, en la barra (QA del 11-nov: el editor promete que los ajustes «se pueden filtrar»).
enum JournalFilter: String, CaseIterable, Hashable {
    case all, manual, accountant, automatic, reversals

    var title: String {
        switch self {
        case .all: String(localized: "Todos")
        case .manual: String(localized: "Manuales")
        case .accountant: String(localized: "Del contador")
        case .automatic: String(localized: "De documentos")
        case .reversals: String(localized: "Reversiones")
        }
    }

    func matches(_ entry: JournalEntry) -> Bool {
        switch self {
        case .all: true
        case .manual: entry.source.isManual
        case .accountant: entry.source == .accountantAdjustment
        case .automatic: !entry.source.isManual && entry.source != .reversal
        case .reversals: entry.source == .reversal || entry.isReversed || entry.reversesEntryID != nil
        }
    }
}

/// Asientos de diario del iPhone: concepto, número, fecha y origen, e importe.
struct JournalListView: View {
    @CompanyQuery(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var showingEditor = false
    @State private var filter: JournalFilter = .all

    var body: some View {
        let shown = entries.filter(filter.matches)
        List {
            if entries.isEmpty {
                EmptyStateView(guide: .journal) { showingEditor = true }
            } else if shown.isEmpty {
                Text("Ningún asiento coincide").foregroundStyle(Palette.ink2).frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(shown) { entry in
                    NavigationLink { JournalEntryDetailView(entry: entry) } label: { JournalEntryRow(entry: entry) }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationTitle("Asientos de diario")
        .headerTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !entries.isEmpty {
                    FilterMenu(options: JournalFilter.allCases, selection: $filter, label: \.title) { option in
                        entries.filter(option.matches).count
                    }
                    .accessibilityLabel("Filtrar por origen")
                }
                AddButton(title: "Nuevo asiento") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { JournalEntryEditorView() }
                .presentationSizing(.page)
        }
    }
}

/// Fila de asiento: concepto, número, fecha y origen, importe y si está revertido.
struct JournalEntryRow: View {
    let entry: JournalEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo,
                  subtitle: "#\(entry.number) · \(entry.date.shortDate) · \(entry.source.title)") {
            EmptyView()
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text(entry.totalDebits.money).monospacedDigit().foregroundStyle(Palette.ink)
                if entry.source == .accountantAdjustment {
                    StatusChip(text: String(localized: "Del contador"), foreground: Palette.info, background: Palette.infoWash, compact: true, dot: Palette.info)
                }
                if entry.isReversed || entry.reversesEntryID != nil {
                    StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                               foreground: Palette.ink2, background: Palette.surface2, compact: true, dot: Palette.gray)
                }
            }
        }
    }
}

extension EntrySource {
    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .invoice: String(localized: "Factura")
        case .creditNote: String(localized: "Nota de crédito")
        case .paymentReceived: String(localized: "Cobro")
        case .bill: String(localized: "Factura de proveedor")
        case .billPayment: String(localized: "Pago a proveedor")
        case .expense: String(localized: "Gasto")
        case .salesTaxPayment: String(localized: "Pago de sales tax")
        case .customerRefund: String(localized: "Reembolso a cliente")
        case .reversal: String(localized: "Reversión")
        case .opening: String(localized: "Saldos iniciales")
        case .bankDeposit: String(localized: "Depósito")
        case .transfer: String(localized: "Transferencia")
        case .accountantAdjustment: String(localized: "Ajuste del contador")
        }
    }
}

/// Editor de asiento: totales en vivo y aviso hasta que débitos = créditos. En iPhone es un formulario; en iPad y
/// Mac sigue `MacDiario`: datos del asiento en una caja, la tabla de líneas, el estado y, si cabe, el plan de cuentas.
struct JournalEntryEditorView: View {
    struct LineDraft: Identifiable {
        let id = UUID()
        var accountID: UUID?
        var memo = ""
        var debit: Int64 = 0
        var credit: Int64 = 0
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 110
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @ActiveCompanyQuery private var companies: [Company]

    /// Qué se registra: una plantilla en llano o el asiento a mano; `nil` hasta elegir (build 4).
    @State private var mode: Mode?
    @State private var date = Date()
    @State private var editorWidth: CGFloat = 0
    @State private var memo = ""
    @State private var lines: [LineDraft] = [LineDraft(), LineDraft()]
    /// Plantilla: importe, cuenta de dinero y, en el traspaso, la de destino.
    @State private var templateAmount: Int64 = 0
    @State private var templateMoney: UUID?
    @State private var templateDestination: UUID?
    /// 1.2: el asiento a mano se marca como ajuste del contador. Encendido de entrada con el plan para contadores
    /// (decisión del usuario del 10-nov); se puede apagar.
    @State private var isAccountantAdjustment = SubscriptionStore.shared.plan == .accountant

    enum Mode: Hashable {
        case template(JournalTemplate)
        case manual
    }

    init(template: JournalTemplate? = nil) {
        _mode = State(initialValue: template.map(Mode.template))
        if let template { _memo = State(initialValue: template.defaultMemo) }
    }

    private var template: JournalTemplate? { if case .template(let template) = mode { template } else { nil } }
    private var moneyAccounts: [Account] { JournalTemplate.moneyAccounts(in: accounts) }
    /// Cuenta de dinero de la plantilla: la elegida o, sin elegir, la primera (el banco).
    private var templateMoneyID: UUID? { templateMoney ?? moneyAccounts.first?.id }
    /// Destino del traspaso: el elegido o, sin elegir, la primera cuenta distinta del origen.
    private var templateDestinationID: UUID? { templateDestination ?? moneyAccounts.first { $0.id != templateMoneyID }?.id }
    @State private var errorMessage: String?
    /// Registrar en un periodo cerrado: se pide la contraseña de cierre y se repite.
    @State private var closedPeriodRetry: ClosedPeriodRetry?

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var postable: [Account] { accounts.filter(\.isPostable) }

    /// Totales de todo lo escrito, también de las líneas sin cuenta (el asiento sólo cuenta las que la tienen).
    private var typedDebits: Int64 { lines.reduce(0) { $0 + $1.debit } }
    private var typedCredits: Int64 { lines.reduce(0) { $0 + $1.credit } }

    /// Número (desde 1) de la primera línea con importe y sin cuenta.
    private var lineWithoutAccount: Int? {
        lines.firstIndex { $0.accountID == nil && ($0.debit != 0 || $0.credit != 0) }.map { $0 + 1 }
    }

    private var draft: JournalEntryDraft {
        if let template {
            return template.draft(date: date, memo: memo, amount: templateAmount, money: templateMoneyID,
                                  destination: templateDestinationID, accounts: accounts)
                ?? JournalEntryDraft(date: date, memo: memo, source: .manual, lines: [])
        }
        return JournalEntryDraft(date: date, memo: memo, source: isAccountantAdjustment ? .accountantAdjustment : .manual, lines: lines.compactMap { line in
            guard let accountID = line.accountID else { return nil }
            return JournalLineDraft(accountID: accountID, debit: line.debit, credit: line.credit, memo: line.memo)
        })
    }

    /// Errores que impiden registrar. La fecha en un periodo cerrado no impide: al registrar se pide la contraseña.
    private var validationErrors: [JournalValidationError] {
        guard let validator = try? books.validator() else { return [] }
        return validator.errors(for: draft).filter { if case .periodLocked = $0 { false } else { true } }
    }

    /// La fecha cae en un periodo cerrado.
    private var dateIsLocked: Bool {
        guard let lock = companies.first?.lockDate else { return false }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: lock)
    }

    /// Diseño de `MacDiario` en iPad y Mac, salvo con los dos tamaños de accesibilidad más grandes.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass == .compact { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        let entry = draft
        let isValid: Bool = switch mode {
        case .manual: validationErrors.isEmpty && lines.allSatisfy { $0.accountID != nil || ($0.debit == 0 && $0.credit == 0) }
        case .template: !entry.lines.isEmpty && validationErrors.isEmpty
        case nil: false
        }
        Group {
            if mode == .manual {
                if isWide { wideEditor(entry) } else { formEditor(entry) }
            } else {
                templateEditor(entry)
            }
        }
        #if os(macOS)
        // La hoja del Mac toma el tamaño del contenido: sin esto, la tabla de líneas quedaba en 470 pt y cortaba «Cuenta».
        .frame(minWidth: mode == .manual ? 780 : 560, minHeight: mode == .manual ? 640 : 600)
        #endif
        .navigationTitle("Nuevo asiento")
        .inlineTitle()
        .discardableEditor(tracking: trackedText, token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Registrar", action: save).disabled(!isValid).headerButton().accessibilityLabel("Registrar asiento") }
        }
        .closedPeriodUnlock($closedPeriodRetry) { errorMessage = $0 }
        // Los importes usan el teclado decimal, que no tiene tecla para cerrarse (QA Hudson, H10).
        .keyboardDoneButton()
        #if DEBUG
        // `-qa.asiento aportacion|retiro|traspaso|manual`: el editor con esa plantilla (y $500) o a mano.
        .task {
            switch UserDefaults.standard.string(forKey: "qa.asiento") {
            case "aportacion": choose(.template(.ownerContribution)); templateAmount = 50_000
            case "retiro": choose(.template(.ownerDraw)); templateAmount = 50_000
            case "traspaso": choose(.template(.transfer)); templateAmount = 50_000
            case "manual": choose(.manual)
            default: break
            }
        }
        // `-qa.asiento cerrado`: un asiento de $10 que cuadra, con la fecha de cierre (para probar la contraseña).
        .task {
            guard UserDefaults.standard.string(forKey: "qa.asiento") == "cerrado", let lock = companies.first?.lockDate,
                  let bank = postable.first(where: { $0.subtype == .bank }),
                  let expense = postable.first(where: { $0.type == .expense }) else { return }
            mode = .manual
            date = lock
            memo = "QA"
            lines = [LineDraft(accountID: expense.id, debit: 1_000), LineDraft(accountID: bank.id, credit: 1_000)]
        }
        #endif
    }

    /// Lo que cuenta como cambio para «¿Descartar los cambios?»: elegir una plantilla sin escribir nada no lo es.
    private var trackedText: String {
        switch mode {
        case .template:
            return "\(date)|\(templateAmount)"
        case .manual, nil:
            return "\(date)|\(JournalTemplate.allCases.map(\.defaultMemo).contains(memo) ? "" : memo)|"
                + lines.map { "\($0.accountID?.uuidString ?? "")/\($0.debit)/\($0.credit)" }.joined(separator: ";")
        }
    }

    /// Elige plantilla o asiento a mano; el concepto propuesto cambia con la plantilla si no se había escrito otro.
    private func choose(_ newMode: Mode) {
        let proposed = JournalTemplate.allCases.map(\.defaultMemo)
        if memo.isEmpty || proposed.contains(memo) {
            if case .template(let template) = newMode { memo = template.defaultMemo } else { memo = "" }
        }
        withAnimation { mode = newMode }
    }

    // MARK: Plantillas (build 4)

    /// Las opciones: tres plantillas en llano y el asiento a mano.
    private var choices: [Mode] { JournalTemplate.allCases.map(Mode.template) + [.manual] }

    private func choiceTitle(_ choice: Mode) -> String {
        switch choice {
        case .template(let template): template.title
        case .manual: String(localized: "Asiento a mano, para tu contador")
        }
    }

    private func choiceImage(_ choice: Mode) -> String {
        switch choice {
        case .template(let template): template.systemImage
        case .manual: "list.bullet.rectangle"
        }
    }

    /// Una opción del selector: icono, texto y la marca si es la elegida.
    private func choiceRow(_ choice: Mode) -> some View {
        Button { choose(choice) } label: {
            HStack(spacing: 12) {
                Image(systemName: choiceImage(choice)).font(.title3).foregroundStyle(Palette.brand).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choiceTitle(choice)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    if choice == .manual {
                        Text("Con débitos y créditos, cuenta por cuenta").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                Spacer(minLength: 8)
                if mode == choice {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Palette.brand).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == choice ? [.isSelected] : [])
    }

    private var chooserTitle: String { String(localized: "¿Qué quieres registrar?") }

    /// Las cuatro opciones en un solo bloque con sus líneas (en el formulario del Mac, filas sueltas con dos textos
    /// salían fuera del grupo).
    private var chooserRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                if index > 0 { Divider().padding(.leading, 40) }
                choiceRow(choice)
            }
        }
    }

    /// El selector en una caja, encima del editor ancho del asiento a mano.
    private var chooserBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: chooserTitle)
            chooserRows
                .padding(.horizontal, 12)
                .card(padding: 0)
        }
    }

    /// Editor de las plantillas (y la pantalla de elegir): un formulario corto con las cuentas de dinero, el importe y
    /// la fecha, y abajo cómo queda en los libros.
    private func templateEditor(_ entry: JournalEntryDraft) -> some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                chooserRows
            } header: {
                SectionLabel(text: chooserTitle)
            } footer: {
                if mode == nil {
                    Text("Elige una opción y Chirogra hace las cuentas por ti. Las facturas, los cobros y los gastos se registran solos: para ellos no hace falta un asiento.")
                }
            }
            if let template {
                Section {
                    templateMoneyPicker(template.moneyAccountLabel, selection: Binding(get: { templateMoneyID }, set: { templateMoney = $0 }))
                    if template.needsDestination {
                        templateMoneyPicker(String(localized: "¿A qué cuenta entró?"),
                                            selection: Binding(get: { templateDestinationID }, set: { templateDestination = $0 }))
                    }
                    LabeledContent("Importe") {
                        MoneyField(title: String(localized: "Importe"), minorUnits: $templateAmount).labelsHidden().multilineTextAlignment(.trailing)
                    }
                    .fieldRow()
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    TextField("Concepto", text: $memo)
                } footer: {
                    if moneyAccounts.isEmpty {
                        Text("No tienes cuentas de dinero: añade tu banco en el plan de cuentas.")
                    } else if template.needsDestination, templateDestinationID == templateMoneyID {
                        Text("Elige dos cuentas distintas.").foregroundStyle(Palette.negative)
                    } else if dateIsLocked, let lock = companies.first?.lockDate {
                        Label(lockedNote(lock), systemImage: "lock").foregroundStyle(Palette.warning)
                    }
                }
                if !entry.lines.isEmpty {
                    Section {
                        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in templateLine(line) }
                    } header: {
                        HStack(spacing: 0) {
                            SectionLabel(text: String(localized: "Así queda en tus libros"))
                            TermHelp(.debitCredit)
                        }
                    } footer: {
                        Text("No tienes que hacer nada más: Chirogra ya puso cada importe en su lado.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    private func templateMoneyPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            if selection.wrappedValue == nil { Text("Elegir…").tag(UUID?.none) }
            ForEach(moneyAccounts) { Text($0.maskedName).tag(Optional($0.id)) }
        }
    }

    /// Una línea del asiento de la plantilla: la cuenta y «Débito $500» o «Crédito $500»; en Capital del dueño, su ⓘ.
    private func templateLine(_ line: JournalLineDraft) -> some View {
        let account = accounts.first { $0.id == line.accountID }
        let side = line.debit > 0 ? String(localized: "Débito \(line.debit.money)") : String(localized: "Crédito \(line.credit.money)")
        return HStack(spacing: 0) {
            Text(account?.displayName ?? "—").foregroundStyle(Palette.ink)
            if account?.subtype == .ownersEquity { TermHelp(.ownersEquity) }
            Spacer(minLength: 8)
            Text(side).monospacedDigit().foregroundStyle(Palette.ink2)
        }
        .frame(minHeight: Metrics.target)
    }

    private func formEditor(_ entry: JournalEntryDraft) -> some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                chooserRows
            } header: {
                SectionLabel(text: chooserTitle)
            }
            Section {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Concepto", text: $memo)
                Toggle("Ajuste del contador", isOn: $isAccountantAdjustment)
            } header: {
                SectionLabel(text: String(localized: "Datos del asiento"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(accountantNote)
                    if dateIsLocked, let lock = companies.first?.lockDate {
                        Label(lockedNote(lock), systemImage: "lock").foregroundStyle(Palette.warning)
                    }
                }
            }
            Section {
                ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                    VStack(alignment: .leading, spacing: 8) {
                        AccountPicker(title: String(localized: "Cuenta \(index + 1)"), accounts: postable, selection: $line.accountID)
                        TextField("Descripción", text: $line.memo).font(.subheadline)
                        HStack {
                            MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit).fieldBox()
                            MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit).fieldBox()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
            } header: {
                HStack(spacing: 0) {
                    SectionLabel(text: String(localized: "Líneas del asiento"))
                    TermHelp(.debitCredit)
                }
            } footer: {
                Text("Los débitos deben ser iguales a los créditos.")
            }

            Section {
                statusBanner(entry)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    // MARK: iPad y Mac (`MacDiario`)

    private func wideEditor(_ entry: JournalEntryDraft) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    chooserBox
                    entryBox
                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                linesTitle
                                Spacer(minLength: 12)
                                linesNote
                            }
                            VStack(alignment: .leading, spacing: 2) { linesTitle; linesNote }
                        }
                        linesTable(entry)
                    }
                    statusBanner(entry)
                    if let lockDate = companies.first?.lockDate {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "lock").foregroundStyle(dateIsLocked ? Palette.warning : Palette.ink2).accessibilityHidden(true)
                            Text(lockedNote(lockDate))
                                .font(.footnote).foregroundStyle(dateIsLocked ? Palette.warning : Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 0)
                    }
                }
                // El plan de cuentas de consulta sólo si queda sitio para la tabla (en la hoja del iPad, no).
                if editorWidth >= 1000 { chartOfAccounts.frame(width: 300) }
            }
            .padding(Metrics.gutter)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
        .background(Palette.background)
    }

    private var linesTitle: some View {
        HStack(spacing: 0) {
            Text("Líneas del asiento").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TermHelp(.debitCredit)
        }
    }

    private var linesNote: some View {
        Text("Los débitos deben ser iguales a los créditos").font(.footnote).foregroundStyle(Palette.ink2)
    }

    /// Datos del asiento (canvas: caja con filas «Fecha» y «Concepto», la etiqueta a la izquierda y el campo a la derecha).
    private var entryBox: some View {
        VStack(spacing: 0) {
            formRow(String(localized: "Fecha")) {
                DatePicker("Fecha", selection: $date, displayedComponents: .date).labelsHidden()
            }
            Divider()
            formRow(String(localized: "Concepto")) {
                TextField("Concepto", text: $memo).fieldBox().frame(maxWidth: 440)
            }
            Divider()
            formRow(String(localized: "Ajuste del contador")) {
                Toggle("Ajuste del contador", isOn: $isAccountantAdjustment).labelsHidden()
            }
            .help(accountantNote)
        }
        .padding(.horizontal, 12)
        .card(padding: 0)
    }

    /// Qué hace la marca del contador.
    private var accountantNote: String {
        String(localized: "Los ajustes del contador salen marcados en el libro diario y se pueden filtrar.")
    }

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(Palette.ink).frame(minWidth: 90, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
        .frame(minHeight: Self.formRowHeight)
    }

    #if os(macOS)
    private static let formRowHeight: CGFloat = 38
    #else
    private static let formRowHeight: CGFloat = 52
    #endif

    /// Tabla de líneas: # · Cuenta · Descripción · Débito · Crédito, con «Añadir línea» y totales al pie.
    private func linesTable(_ entry: JournalEntryDraft) -> some View {
        TableCard {
            Text("#").frame(width: 22, alignment: .leading)
            Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
            Text("Débito").frame(width: amountWidth, alignment: .trailing)
            Text("Crédito").frame(width: amountWidth, alignment: .trailing)
            Color.clear.frame(width: Metrics.target, height: 1)
        } rows: {
            ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                TableRow {
                    Text("\(index + 1)").foregroundStyle(Palette.ink2).frame(width: 22, alignment: .leading)
                        .accessibilityHidden(true)
                    AccountPicker(title: String(localized: "Cuenta de la línea \(index + 1)"), accounts: postable, selection: $line.accountID)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Descripción", text: $line.memo).fieldBox().frame(maxWidth: .infinity)
                    MoneyField(title: String(localized: "Débito"), minorUnits: $line.debit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    MoneyField(title: String(localized: "Crédito"), minorUnits: $line.credit)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountWidth)
                    Button { lines.remove(at: index) } label: {
                        Image(systemName: "minus.circle").frame(width: Metrics.target, height: Metrics.target)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink2)
                    .disabled(lines.count <= 2)
                    .accessibilityLabel("Quitar la línea \(index + 1)")
                }
                .padding(.vertical, 2)
                .zebra(index)
            }
            TableRow {
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: Metrics.target)
                Spacer()
                Text("Totales").fontWeight(.semibold).foregroundStyle(Palette.ink2)
                Text(typedDebits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Text(typedCredits.money).fontWeight(.bold).frame(width: amountWidth, alignment: .trailing)
                Color.clear.frame(width: Metrics.target, height: 1)
            }
            .background(Palette.surface)
            .accessibilityElement(children: .contain)
        }
    }

    /// Plan de cuentas de consulta (`MacDiario`, inspector): grupos por tipo con código, nombre y saldo.
    private var chartOfAccounts: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let active = accounts.filter { !$0.isArchived }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: String(localized: "Plan de cuentas"))
                Spacer()
                Text("\(active.count) cuentas").font(.footnote).foregroundStyle(Palette.ink2)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Text(type.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 6)
                    ForEach(active.filter { $0.type == type }) { account in
                        HStack(spacing: 8) {
                            Text(account.code).foregroundStyle(Palette.ink2).frame(width: 40, alignment: .leading)
                            Text(account.name).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(ledger.balance(of: account).money).foregroundStyle(Palette.ink2).lineLimit(1)
                        }
                        .font(.footnote)
                        .monospacedDigit()
                        .padding(.leading, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .card(padding: 12)
        }
    }

    /// Estado del asiento (canvas `MacDiario`): círculo verde o rojo, el mensaje, los totales y la diferencia.
    @ViewBuilder
    private func statusBanner(_ entry: JournalEntryDraft) -> some View {
        let balanced = entry.isBalanced && entry.totalDebits > 0
        let message: String = if let line = lineWithoutAccount {
            String(localized: "Elige la cuenta de la línea \(line)")
        } else if balanced {
            validationErrors.first?.localizedMessage ?? String(localized: "El asiento cuadra: débitos = créditos")
        } else if entry.difference > 0 {
            String(localized: "No cuadra: faltan créditos por \(abs(entry.difference).money)")
        } else if entry.difference < 0 {
            String(localized: "No cuadra: faltan débitos por \(abs(entry.difference).money)")
        } else {
            String(localized: "Escribe los importes al debe y al haber")
        }
        let ok = balanced && validationErrors.isEmpty && lineWithoutAccount == nil
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ok ? Palette.green : Palette.red, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(ok ? Palette.positive : Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Débitos \(typedDebits.money) · Créditos \(typedCredits.money)").font(.footnote).foregroundStyle(Palette.ink2)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(abs(typedDebits - typedCredits).money).font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(ok ? Palette.positive : Palette.negative)
                .accessibilityLabel("Diferencia \(abs(typedDebits - typedCredits).money)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Aviso del cierre: con la fecha dentro del periodo cerrado, que se pedirá la contraseña.
    private func lockedNote(_ lock: Date) -> String {
        let hasPassword = companies.first?.hasClosingPassword ?? false
        if dateIsLocked {
            return hasPassword
                ? String(localized: "La fecha cae en un periodo cerrado (hasta el \(lock.shortDate)). Al registrar te pediremos la contraseña de cierre.")
                : String(localized: "La fecha cae en un periodo cerrado (hasta el \(lock.shortDate)). Al registrar te pediremos el motivo.")
        }
        return String(localized: "El periodo está cerrado hasta el \(lock.shortDate). Para registrar con una fecha anterior te pediremos la contraseña de cierre.")
    }

    private func save() {
        let entry = draft
        do {
            try books.post(entry)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            if let lock = PeriodClosing.lockDate(of: error) {
                closedPeriodRetry = ClosedPeriodRetry(lockDate: lock, perform: { unlocked in
                    try unlocked.post(entry)
                    unsavedChanges?.remove(editorToken); dismiss()
                }, redate: { firstOpenDay in
                    date = firstOpenDay
                    save()
                })
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Un asiento contabilizado: número, fecha, origen y concepto, y sus líneas con el debe y el haber. Los manuales se
/// corrigen con una reversión.
struct JournalEntryDetailView: View {
    /// Lo que lee VoiceOver de una línea del asiento, como frase completa para traducirla entera.
    static func spokenLine(account: String, memo: String, debit: Int64, credit: Int64) -> String {
        let name = memo.isEmpty ? account : "\(account), \(memo)"
        return debit > 0 ? String(localized: "\(name), debe \(debit.money)") : String(localized: "\(name), haber \(credit.money)")
    }

    let entry: JournalEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 100

    /// Fila con columnas Debe/Haber; con tamaños de accesibilidad los importes van debajo, rotulados.
    @ViewBuilder
    private func entryRow(_ title: String, memo: String, debit: Int64, credit: Int64, bold: Bool = false) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(bold ? .semibold : .regular)
                if !memo.isEmpty { Text(memo).font(.footnote).foregroundStyle(Palette.ink2) }
                if debit > 0 { Text("Debe \(debit.money)") }
                if credit > 0 { Text("Haber \(credit.money)") }
            }
            .monospacedDigit()
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(bold ? .semibold : .regular)
                    if !memo.isEmpty { Text(memo).font(.footnote).foregroundStyle(Palette.ink2) }
                }
                Spacer()
                Text(debit > 0 ? debit.money : "").frame(width: columnWidth, alignment: .trailing)
                Text(credit > 0 ? credit.money : "").frame(width: columnWidth, alignment: .trailing)
            }
            .fontWeight(bold ? .semibold : .regular)
            .monospacedDigit()
        }
    }
    @State private var errorMessage: String?
    @State private var confirming = false
    /// Banca 1.2: revertir un asiento conciliado pide confirmación (`ReconciledChange`).
    @State private var reconciledRetry: ReconciledChangeRetry?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.memo.isEmpty ? String(localized: "Asiento \(entry.number)") : entry.memo)
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                    Text(entry.totalDebits.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                    if entry.isReversed || entry.reversesEntryID != nil {
                        StatusChip(text: entry.isReversed ? String(localized: "Revertido") : String(localized: "Reversión"),
                                   foreground: Palette.ink2, background: Palette.surface2, dot: Palette.gray)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            Section {
                LabeledContent("Número", value: "#\(entry.number)")
                LabeledContent("Fecha", value: entry.date.shortDate)
                LabeledContent("Origen", value: entry.source.title)
                if !entry.memo.isEmpty { LabeledContent("Concepto", value: entry.memo) }
            } header: {
                SectionLabel(text: String(localized: "Asiento"))
            }
            Section {
                ForEach(entry.sortedLines) { line in
                    let account = line.account?.displayName ?? String(localized: "Cuenta eliminada")
                    entryRow(account, memo: line.memo, debit: line.debit, credit: line.credit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spokenLine(account: account, memo: line.memo, debit: line.debit, credit: line.credit))
                }
                entryRow(String(localized: "Totales"), memo: "", debit: entry.totalDebits, credit: entry.totalCredits, bold: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Totales: debe \(entry.totalDebits.money), haber \(entry.totalCredits.money)")
            } header: {
                HStack {
                    Text("Cuenta")
                    Spacer()
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Debe").frame(width: columnWidth, alignment: .trailing)
                        Text("Haber").frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.label).foregroundStyle(Palette.ink2).textCase(nil)
                .accessibilityHidden(true)
            }
            if entry.source.isManual && !entry.isReversed && entry.reversesEntryID == nil {
                Section {
                    Button("Revertir asiento", role: .destructive) { confirming = true }
                } footer: {
                    Text("Los asientos contabilizados no se editan ni se borran: se corrigen con un asiento de reversión.")
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Asiento #\(entry.number)")
        .inlineTitle()
        .confirmationDialog("¿Revertir este asiento?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Revertir", role: .destructive) {
                do { try Bookkeeper(context: context).reverse(entry) } catch {
                    // Banca 1.2: revertir un asiento conciliado pide confirmación (`ReconciledChange`).
                    if let retry = ReconciledChange.retry(for: error, { try $0.reverse(entry) }) { reconciledRetry = retry } else { errorMessage = error.localizedDescription }
                }
            }
        }
        .reconciledChangeConfirmation($reconciledRetry) { errorMessage = $0 }
    }
}

/// Libro mayor del iPhone: elegir la cuenta, por tipo.
struct LedgerAccountPickerView: View {
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]

    var body: some View {
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                let rows = accounts.filter { $0.type == type && !$0.isArchived }
                if !rows.isEmpty {
                    Section(heading: type.title) {
                        ForEach(rows) { account in
                            NavigationLink { LedgerView(account: account) } label: {
                                HStack(spacing: 12) {
                                    Text(account.code).foregroundStyle(Palette.ink2).monospacedDigit()
                                    Text(account.name).foregroundStyle(Palette.ink)
                                }
                            }
                        }
                    }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Libro mayor")
        .headerTitle()
    }
}

/// Libro mayor de una cuenta con saldo acumulado (canvas `MacLibroMayor`, `iPadBancaCuentas`). Con sitio (columna de
/// detalle del iPad o del Mac): la cuenta y su saldo en grande, el resumen del periodo y la tabla de movimientos; en
/// el iPhone o una columna estrecha, la lista. El signo de cada movimiento sigue la naturaleza de la cuenta: en pasivo,
/// patrimonio e ingreso un crédito aumenta el saldo (+); en activo y gasto lo aumenta un débito.
struct LedgerView: View {
    let account: Account
    /// En la columna de detalle de iPad y Mac (Plan de cuentas, Banca): título pequeño en la barra, como la factura,
    /// el gasto y las demás fichas, sin repetir en grande lo que el contenido ya dice (canvas `iPadVentas`,
    /// `iPadBancaCuentas`: lo grande es la cifra). Abierto encima de otra pantalla, el título de pantalla de siempre.
    var inDetailColumn = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filterByDate = false
    @State private var from = DateInterval.month(containing: .now).start
    @State private var to = Date()
    @State private var width: CGFloat = 0
    @State private var editing = false
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 58
    /// Cabe «Ajuste del contador» (QA del 11-nov: salía «Ajuste del cont…»).
    @ScaledMetric(relativeTo: .subheadline) private var kindWidth: CGFloat = 140

    /// Rango de fechas completo de los días elegidos (del inicio de `from` al final de `to`).
    private var range: (from: Date, to: Date)? {
        guard filterByDate else { return nil }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: to)) ?? to
        return (calendar.startOfDay(for: from), end)
    }

    /// Lo que lee VoiceOver de un movimiento: una frase completa por caso, para que se traduzca entera.
    static func spokenMovement(_ row: AccountLedger.Row) -> String {
        let memo = row.movement.memo, date = row.movement.date.shortDate, balance = row.balance.money
        let amount = max(row.movement.debit, row.movement.credit).money
        switch (row.movement.debit > 0, row.increasesBalance) {
        case (true, true): return String(localized: "\(memo), \(date), débito de \(amount), aumenta el saldo a \(balance)")
        case (true, false): return String(localized: "\(memo), \(date), débito de \(amount), reduce el saldo a \(balance)")
        case (false, true): return String(localized: "\(memo), \(date), crédito de \(amount), aumenta el saldo a \(balance)")
        case (false, false): return String(localized: "\(memo), \(date), crédito de \(amount), reduce el saldo a \(balance)")
        }
    }

    private var ledger: AccountLedger { Self.ledger(for: account, from: range?.from, to: range?.to) }

    /// Movimientos contabilizados de la cuenta con saldo acumulado; también lo usa `LedgerBrowserView`.
    static func ledger(for account: Account, from: Date?, to: Date?) -> AccountLedger {
        let movements = (account.lines ?? []).compactMap { line -> LedgerMovement? in
            guard let entry = line.entry, entry.status == .posted else { return nil }
            return LedgerMovement(id: line.id, date: entry.date, memo: entry.memo, debit: line.debit, credit: line.credit)
        }
        return ReportBuilder.accountLedger(account: account.ledgerAccount, movements: movements, from: from, to: to)
    }

    /// Tipo de cada movimiento (cobro, gasto…) según el documento que generó el asiento.
    static func kinds(for account: Account) -> [UUID: String] {
        Dictionary((account.lines ?? []).compactMap { line in line.entry.map { (line.id, $0.source.title) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Tabla si la vista mide al menos 640 pt y el texto no es de accesibilidad.
    private var isWide: Bool { width >= 640 && !dynamicTypeSize.isAccessibilitySize }

    /// Una cuenta de dinero (banco, caja) muestra en verde lo que entra, como Banca.
    private var isCashAccount: Bool { account.type == .asset && account.subtype.isMoneyAccount }

    var body: some View {
        let ledger = ledger
        Group {
            if isWide { wideBody(ledger) } else { listBody(ledger) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .safeAreaInset(edge: .top, spacing: 0) {
            // 3900 · Saldos de apertura: qué es y qué suele hacer el contador con ella (QA Hudson, H15: el capital
            // inicial no salía en «Capital del dueño» y no se explicaba por qué).
            if account.subtype == .openingBalanceEquity {
                Label("Aquí van los saldos con que empezaste los libros. Tu contador suele pasarlos a «Capital del dueño» con un asiento al cerrar el año.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.background)
            }
        }
        .navigationTitle(account.name)
        .modifier(LedgerTitle(inDetailColumn: inDetailColumn))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: { Label("Editar cuenta", systemImage: "pencil") }
                    .help("Editar cuenta")
                    .headerButton()
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { AccountEditorView(account: account) }.editorSheetSizing() }
    }

    /// Nombre, saldo en grande y tipo (canvas `iPadBancaCuentas`: «Corriente ••4821 · $42,130.18 · Saldo en libros»).
    private func hero(_ ledger: AccountLedger) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Con el título grande ya a la vista, no se repite el nombre.
            if inDetailColumn || isWide { Text(account.displayName).font(.subheadline).foregroundStyle(Palette.ink2) }
            Text(ledger.closingBalance.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(filterByDate ? String(localized: "Saldo final del periodo") : String(localized: "Saldo en libros · \(account.type.title) · \(account.subtype.title)"))
                .font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var dateFilter: some View {
        Group {
            Toggle("Filtrar por fechas", isOn: $filterByDate)
            if filterByDate {
                DatePicker("Desde", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date)
            }
        }
    }

    // MARK: Lista (iPhone, columna estrecha)

    private func listBody(_ ledger: AccountLedger) -> some View {
        List {
            Section { hero(ledger) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            Section {
                LabeledContent("Aumenta con", value: account.type.normalBalance == .debit ? String(localized: "Débitos") : String(localized: "Créditos"))
                dateFilter
                if filterByDate { LabeledContent("Saldo inicial", value: ledger.openingBalance.money).monospacedDigit() }
                LabeledContent("Débitos", value: ledger.totalDebit.money).monospacedDigit()
                LabeledContent("Créditos", value: ledger.totalCredit.money).monospacedDigit()
            } header: {
                SectionLabel(text: String(localized: "Cuenta"))
            }
            Section {
                if ledger.rows.isEmpty { Text("Sin movimientos").foregroundStyle(Palette.ink2) }
                ForEach(ledger.rows.reversed()) { row in
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo).lineLimit(2)
                                .foregroundStyle(Palette.ink)
                            Text(row.movement.debit > 0 ? "\(row.movement.date.dayMonth) · \(String(localized: "Débito"))"
                                                        : "\(row.movement.date.dayMonth) · \(String(localized: "Crédito"))")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                            Text("\(row.increasesBalance ? "+" : "−")\(abs(row.effect).money)")
                                .foregroundStyle(row.increasesBalance && isCashAccount ? Palette.positive : Palette.ink)
                            Text("Saldo \(row.balance.money)").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                        .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Self.spokenMovement(row))
                }
            } header: {
                SectionLabel(text: String(localized: "Movimientos"))
            } footer: {
                Text("+ aumenta el saldo de la cuenta y − lo reduce, según su naturaleza.")
            }
        }
        .groupedList()
        .screenBackground()
    }

    // MARK: Tabla (iPad y Mac, `MacLibroMayor`)

    private func wideBody(_ ledger: AccountLedger) -> some View {
        let kinds = Self.kinds(for: account)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(ledger)
                LedgerSummary(opening: ledger.openingBalance, debits: ledger.totalDebit, credits: ledger.totalCredit,
                              closing: ledger.closingBalance,
                              debitCount: ledger.rows.filter { $0.movement.debit > 0 }.count,
                              creditCount: ledger.rows.filter { $0.movement.credit > 0 }.count,
                              from: range?.from, to: range?.to ?? .now)
                HStack(spacing: 12) {
                    Toggle("Filtrar por fechas", isOn: $filterByDate).fixedSize()
                    if filterByDate {
                        DatePicker("Desde", selection: $from, in: ...to, displayedComponents: .date).fixedSize()
                        DatePicker("Hasta", selection: $to, in: from..., displayedComponents: .date).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                LedgerTable(ledger: ledger, kinds: kinds, from: range?.from, to: range?.to ?? .now,
                            dateWidth: dateWidth, kindWidth: kindWidth, amountWidth: amountWidth)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
    }
}

/// Saldo inicial · Débitos · Créditos · Saldo final en una caja con separadores verticales (canvas `MacLibroMayor`).
struct LedgerSummary: View {
    let opening: Int64
    let debits: Int64
    let credits: Int64
    let closing: Int64
    let debitCount: Int
    let creditCount: Int
    let from: Date?
    let to: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let items: [(String, Int64, String)] = [
            (String(localized: "Saldo inicial"), opening, from.map { String(localized: "Al \($0.shortDate)") } ?? String(localized: "Desde el inicio")),
            (String(localized: "Débitos"), debits, String(localized: "\(debitCount) movimientos")),
            (String(localized: "Créditos"), credits, String(localized: "\(creditCount) movimientos")),
            (String(localized: "Saldo final"), closing, String(localized: "Al \(to.shortDate)")),
        ]
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { cells(items, dividers: true) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { cell(items[0]); cell(items[1]) }
                GridRow { cell(items[2]); cell(items[3]) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    @ViewBuilder
    private func cells(_ items: [(String, Int64, String)], dividers: Bool) -> some View {
        ForEach(items.indices, id: \.self) { index in
            if index > 0 && dividers { Divider() }
            cell(items[index]).frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cell(_ item: (String, Int64, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.0).font(.label).foregroundStyle(Palette.ink2)
            Text(item.1.money).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(item.2).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tabla Fecha · Tipo · Detalle · Débito · Crédito · Saldo entre el saldo inicial y el final (canvas `MacLibroMayor`),
/// con cebra en el Mac.
struct LedgerTable: View {
    let ledger: AccountLedger
    let kinds: [UUID: String]
    let from: Date?
    let to: Date
    let dateWidth: CGFloat
    let kindWidth: CGFloat
    let amountWidth: CGFloat

    var body: some View {
        TableCard {
            Text("Fecha").frame(width: dateWidth, alignment: .leading)
            Text("Tipo").frame(width: kindWidth, alignment: .leading)
            Text("Detalle").frame(maxWidth: .infinity, alignment: .leading)
            Text("Débito").frame(width: amountWidth, alignment: .trailing)
            Text("Crédito").frame(width: amountWidth, alignment: .trailing)
            Text("Saldo").frame(width: amountWidth, alignment: .trailing)
        } rows: {
            row(date: from?.dayMonth ?? "—", kind: "—", detail: String(localized: "Saldo inicial"), debit: "", credit: "",
                balance: ledger.openingBalance.money)
                .fontWeight(.semibold)
            ForEach(Array(ledger.rows.enumerated()), id: \.element.id) { index, item in
                row(date: item.movement.date.dayMonth, kind: kinds[item.movement.id] ?? "—",
                    detail: item.movement.memo.isEmpty ? String(localized: "Asiento") : item.movement.memo,
                    debit: item.movement.debit > 0 ? item.movement.debit.money : "",
                    credit: item.movement.credit > 0 ? item.movement.credit.money : "",
                    balance: item.balance.money)
                    .zebra(index + 1)
                    .accessibilityLabel(LedgerView.spokenMovement(item))
            }
            if ledger.rows.isEmpty {
                Text("Sin movimientos en el periodo").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            row(date: to.dayMonth, kind: "", detail: String(localized: "Saldo final"), debit: ledger.totalDebit.money,
                credit: ledger.totalCredit.money, balance: ledger.closingBalance.money)
                .fontWeight(.semibold)
                .background(Palette.surface)
        }
    }

    private func row(date: String, kind: String, detail: String, debit: String, credit: String, balance: String) -> some View {
        TableRow {
            Text(date).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
            Text(kind).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: kindWidth, alignment: .leading)
            Text(detail).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(debit).frame(width: amountWidth, alignment: .trailing)
            Text(credit).frame(width: amountWidth, alignment: .trailing)
            Text(balance).frame(width: amountWidth, alignment: .trailing)
        }
    }
}

private struct LedgerTitle: ViewModifier {
    let inDetailColumn: Bool
    func body(content: Content) -> some View {
        if inDetailColumn { content.inlineTitle() } else { content.headerTitle() }
    }
}
