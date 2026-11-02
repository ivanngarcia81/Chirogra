import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Gastos (canvas `Gastos`): gastos pagados y facturas por pagar con el segmentado, y los proveedores desde una fila.
/// Es la pantalla del iPhone (y la de la columna estrecha del iPad, o con AX4 o más); en iPad y Mac cada subsección va
/// con columna maestro (`MasterPage`).
struct ExpensesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case expenses = "Gastos"
        case bills = "Por pagar"
        case vendors = "Proveedores"
        var id: String { rawValue }
    }

    /// Desde la barra lateral o un enlace, la subsección ya elegida y sin el segmentado.
    var fixedSegment: Segment? = nil

    @State private var selectedSegment: Segment = .expenses
    @State private var showingEditor = false

    private var segment: Segment { fixedSegment ?? selectedSegment }

    /// El segmentado del canvas es Gastos · Por pagar · Recurrentes; Recurrentes es de la fase 2 y Proveedores va como
    /// fila de la pantalla de Gastos.
    private var picker: Binding<Segment>? { fixedSegment == nil ? $selectedSegment : nil }

    private var title: String {
        // En iPhone las dos van bajo «Gastos» con el selector; desde un enlace cada una tiene su título.
        guard fixedSegment != nil else { return String(localized: "Gastos") }
        return switch segment {
        case .expenses: String(localized: "Gastos")
        case .bills: String(localized: "Facturas por pagar")
        case .vendors: String(localized: "Proveedores")
        }
    }

    private var addTitle: LocalizedStringResource {
        switch segment {
        case .expenses: "Nuevo gasto"
        case .bills: "Nueva factura de proveedor"
        case .vendors: "Nuevo proveedor"
        }
    }

    var body: some View {
        Group {
            switch segment {
            case .expenses: ExpenseListView(section: picker) { selectedSegment = .bills }
            case .bills: BillListView(section: picker)
            case .vendors: VendorListView()
            }
        }
        .navigationTitle(title)
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddButton(title: addTitle) { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                switch segment {
                case .expenses: ExpenseEditorView()
                case .bills: BillEditorView()
                case .vendors: VendorEditorView()
                }
            }
            .editorSheetSizing()
        }
    }
}

extension View {
    /// Lista agrupada del iPhone (celdas de radio 24 sobre el fondo agrupado); en el Mac, la del sistema.
    @ViewBuilder
    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}

/// Segmentado Gastos · Por pagar arriba de la lista, bajo el título grande (se desplaza con ella, como en el canvas).
private struct ExpensesSegmentRow: View {
    @Binding var selection: ExpensesView.Segment

    var body: some View {
        Section {
            FilterPicker(title: String(localized: "Sección"), options: [.expenses, .bills], selection: $selection) { $0.localizedTitle }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
    }
}

/// Encabezado de un grupo dentro de una lista: título `.title3` bold a la izquierda y algo a la derecha (canvas
/// «Octubre · Por categoría», «Recientes · Filtrar»).
private struct ListGroupHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Con texto de accesibilidad, uno debajo del otro: lado a lado partían «Noviembre» en sílabas.
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title).font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

// MARK: - Gastos

/// Filtro de «Recientes» (canvas `Gastos` · Filtrar; `MacGastos` · Solo sin recibo).
enum ExpenseReceiptFilter: String, CaseIterable, Identifiable {
    case all = "Todos", withoutReceipt = "Sin recibo", withReceipt = "Con recibo"
    var id: String { rawValue }

    func includes(_ expense: Expense) -> Bool {
        switch self {
        case .all: true
        case .withoutReceipt: (expense.attachments ?? []).isEmpty
        case .withReceipt: !(expense.attachments ?? []).isEmpty
        }
    }
}

/// Gastos (canvas `Gastos`): el mes por categoría, las facturas por pagar esta semana y los proveedores, y los gastos
/// recientes con el icono de su categoría.
struct ExpenseListView: View {
    var section: Binding<ExpensesView.Segment>? = nil
    /// Abre «Por pagar» desde la fila de esta semana.
    var showBills: () -> Void = {}
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var filter: ExpenseReceiptFilter = .all
    @State private var cardWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func category(_ expense: Expense) -> Account? {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }
    }

    var body: some View {
        let shown = expenses.filter(filter.includes)
        List {
            if let section { ExpensesSegmentRow(selection: section) }

            Section {
                monthCard
            } header: {
                ListGroupHeader(title: Date.now.formatted(.appDateTime.month(.wide)).sentenceCased) {
                    Text("Por categoría").font(.subheadline).foregroundStyle(Palette.ink2)
                }
            }

            Section {
                dueThisWeekRow
                NavigationLink { ExpensesView(fixedSegment: .vendors) } label: {
                    Label { Text("Proveedores") } icon: { IconTile(systemImage: "truck.box", foreground: Palette.purple) }
                        .labelStyle(TileLabelStyle())
                }
            }

            Section {
                if expenses.isEmpty {
                    EmptyStateView(systemImage: "wallet.bifold", title: String(localized: "Sin gastos todavía"),
                                   message: String(localized: "Registra un gasto con el botón + y adjunta el recibo."))
                } else if shown.isEmpty {
                    EmptyStateView(systemImage: "line.3.horizontal.decrease.circle", title: String(localized: "Sin resultados"),
                                   message: String(localized: "Ningún gasto coincide con el filtro."),
                                   actionTitle: String(localized: "Quitar filtro")) { filter = .all }
                }
                ForEach(shown) { expense in
                    NavigationLink { ExpenseDetailView(expense: expense) } label: {
                        ExpenseRow(expense: expense, category: category(expense))
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                }
            } header: {
                ListGroupHeader(title: String(localized: "Recientes")) { filterMenu }
            }
        }
        .groupedList()
        .screenBackground()
    }

    /// «Filtrar» en Tinta; con un filtro puesto, su nombre.
    private var filterMenu: some View {
        Menu {
            Picker(String(localized: "Filtrar"), selection: $filter) {
                ForEach(ExpenseReceiptFilter.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(filter == .all ? String(localized: "Filtrar") : filter.localizedTitle)
                .font(.body)
                .frame(minHeight: Metrics.target)
        }
        .tint(Palette.brand)
        .accessibilityLabel("Filtrar")
        .accessibilityValue(filter.localizedTitle)
    }

    /// Facturas abiertas que vencen en los próximos 7 días (también las ya vencidas): toca para verlas.
    private var dueThisWeekRow: some View {
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let due = bills.filter { $0.isOpen && $0.dueDate < limit }
        let total = due.reduce(0) { $0 + $1.balanceDue }
        let isAX = dynamicTypeSize.isAccessibilitySize
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        return Button(action: showBills) {
            layout {
                IconTile(systemImage: "calendar", foreground: Palette.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Por pagar esta semana").foregroundStyle(Palette.ink)
                    Text(due.isEmpty ? String(localized: "Nada pendiente") : String(localized: "\(due.count) facturas"))
                        .font(.footnote).foregroundStyle(due.isEmpty ? Palette.ink2 : Palette.warning)
                }
                if !isAX { Spacer(minLength: 8) }
                if total > 0 { Text(total.money).foregroundStyle(Palette.ink).monospacedDigit() }
                if !isAX {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Gasto del mes por categoría: las mismas cifras que el estado de resultados (gastos y costo de ventas), para que
    /// coincida con «Gastos» de Inicio. Las cuatro mayores y el resto en «Otros».
    private var monthCard: some View {
        let month = DateInterval.month(containing: .now)
        let statement = Ledger(accounts: accounts, lines: journalLines).incomeStatement(month)
        let rows = (statement.costOfGoodsSold + statement.expenses).filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
        let total = rows.reduce(0) { $0 + $1.amount }
        var slices = rows.prefix(4).map { (name: $0.account.name, amount: $0.amount) }
        let colors = ExpenseCategoryStyle.barColors(for: slices.map(\.name))
        let rest = rows.dropFirst(4).reduce(0) { $0 + $1.amount }
        if rest > 0 { slices.append((String(localized: "Otros"), rest)) }
        let color = { (index: Int) -> Color in index < colors.count ? colors[index] : Palette.fill2 }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total del mes").font(.subheadline).foregroundStyle(Palette.ink2)
                Text(total.money).font(.amount(28)).foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .combine)
            if total > 0 {
                CategoryBar(amounts: slices.map(\.amount), colors: slices.indices.map(color))
                    .accessibilityLabel(String(localized: "Gastos del mes por categoría"))
                    .accessibilityValue(slices.map { "\($0.name) \($0.amount.money)" }.joined(separator: ", "))
                // Dos columnas, como en el canvas, si caben los nombres; en un iPhone, una por línea.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .leading), count: cardWidth >= 520 ? 2 : 1),
                          spacing: 8) {
                    ForEach(slices.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(index < colors.count ? colors[index] : Palette.gray).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            // Con texto de accesibilidad, el nombre entero y el importe debajo.
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(slices[index].name).foregroundStyle(Palette.ink2)
                                    Text(slices[index].amount.money).foregroundStyle(Palette.ink).monospacedDigit()
                                }
                            } else {
                                Text(slices[index].name).foregroundStyle(Palette.ink2).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(slices[index].amount.money).foregroundStyle(Palette.ink).monospacedDigit()
                            }
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("Sin gastos este mes").font(.subheadline).foregroundStyle(Palette.ink2)
            }
        }
        .padding(.vertical, 6)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
    }
}

/// Barra apilada de 10 pt (8 en el Mac) con un hueco de 2 pt entre tramos.
struct CategoryBar: View {
    let amounts: [Int64]
    let colors: [Color]

    var body: some View {
        let total = max(1, amounts.reduce(0, +))
        GeometryReader { proxy in
            let room = proxy.size.width - CGFloat(max(0, amounts.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(amounts.indices, id: \.self) { index in
                    Rectangle().fill(colors[index])
                        .frame(width: max(2, room * CGFloat(amounts[index]) / CGFloat(total)))
                }
            }
        }
        #if os(macOS)
        .frame(height: 8)
        #else
        .frame(height: 10)
        #endif
        .clipShape(Capsule())
        .accessibilityElement()
    }
}

/// Fila con un icono de color a la izquierda (canvas: «Proveedores» con su cuadrado morado).
struct TileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title.foregroundStyle(Palette.ink)
        }
    }
}

/// Fila de gasto (canvas `Gastos`): icono de la categoría, beneficiario, categoría y día, clip si tiene recibo e
/// importe en `ink`.
struct ExpenseRow: View {
    let expense: Expense
    let category: Account?

    var body: some View {
        LedgerRow(title: expense.payee, subtitle: "\(category?.name ?? String(localized: "Sin categoría")) · \(expense.date.relativeDay)") {
            IconTile(systemImage: ExpenseCategoryStyle.symbol(for: category?.name), foreground: ExpenseCategoryStyle.color(for: category?.name))
        } trailing: {
            HStack(spacing: 6) {
                if !(expense.attachments ?? []).isEmpty {
                    Image(systemName: "paperclip").font(.footnote).foregroundStyle(Palette.ink2).accessibilityLabel("Recibo adjunto")
                }
                Text(expense.total.money).monospacedDigit().foregroundStyle(Palette.ink)
            }
        }
    }
}

extension Date {
    /// «hoy», «ayer» o el día («30 oct»), como en las filas del canvas.
    var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return String(localized: "hoy") }
        if calendar.isDateInYesterday(self) { return String(localized: "ayer") }
        return dayMonth
    }
}

// MARK: - Nuevo gasto

struct ExpenseEditorView: View {
    /// Desde la ficha de un proveedor («+ Gasto», «Recibo»).
    var preselectedVendor: Vendor? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var payee = ""
    @State private var vendorID: UUID?
    @State private var date = Date()
    @State private var amount: Int64 = 0
    @State private var categoryID: UUID?
    @State private var paymentAccountID: UUID?
    @State private var memo = ""
    @State private var receipts: [ReceiptFile] = []
    @State private var method: PaymentMethod = .card
    @State private var errorMessage: String?
    @State private var editorWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacGastoNuevo` en iPad y Mac (hasta AX3): el recibo a la izquierda y el formulario a la derecha. En el
    /// iPhone, el formulario con el recibo como una sección más.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    private var canSave: Bool { amount > 0 && categoryID != nil && paymentAccountID != nil && !(payee.isEmpty && vendorID == nil) }

    private var expenseAccounts: [Account] { accounts.filtered { $0.accountType == .expense || $0 == .fixedAsset || $0 == .otherCurrentAsset } }
    private var paymentAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds } }

    var body: some View {
        Group {
            if isWide { wideForm } else { compactForm }
        }
        .navigationTitle("Nuevo gasto")
        .inlineTitle()
        .discardableEditor(tracking: "\(payee)|\(vendorID?.uuidString ?? "")|\(date)|\(amount)|\(categoryID?.uuidString ?? "")|\(paymentAccountID?.uuidString ?? "")|\(memo)|\(receipts.count)|\(method)", token: editorToken)
        .toolbar {
            #if os(macOS)
            // Una hoja del Mac solo muestra «Cancelar» y la acción de confirmar (con Return); «Guardar y nuevo» va en
            // el contenido.
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar gasto") { save() }.disabled(!canSave)
            }
            #else
            if isWide {
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar y nuevo") { save(another: true) }.disabled(!canSave).headerButton()
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar gasto") { save() }.disabled(!canSave).headerButton()
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(!canSave).headerButton()
                }
            }
            #endif
        }
        .onChange(of: vendorID) {
            guard let vendor = vendors.first(where: { $0.id == vendorID }) else { return }
            if payee.isEmpty { payee = vendor.name }
            if let defaultAccount = vendor.defaultExpenseAccountID { categoryID = defaultAccount }
        }
        .onAppear {
            paymentAccountID = paymentAccountID ?? paymentAccounts.first { $0.subtype == .bank }?.id
            if vendorID == nil, let preselectedVendor { vendorID = preselectedVendor.id }
        }
    }

    // MARK: Secciones (las mismas en las dos formas)

    @ViewBuilder
    private var amountSection: some View {
        Section {
            LabeledContent("Monto") {
                MoneyField(title: String(localized: "Monto"), minorUnits: $amount)
                    .font(.amount(isWide ? 17 : 24))
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
            }
            DatePicker("Fecha", selection: $date, displayedComponents: .date)
        } header: {
            SectionLabel(text: String(localized: "Importe"))
        } footer: {
            Text("En EE. UU. el sales tax de tus compras forma parte del gasto.")
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            Picker("Proveedor", selection: $vendorID) {
                Text("Ninguno").tag(UUID?.none)
                ForEach(vendors.filter { !$0.isArchived || $0.id == vendorID }) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("Pagado a (comercio o persona)", text: $payee)
            AccountPicker(title: String(localized: "Categoría"), accounts: expenseAccounts, selection: $categoryID)
            AccountPicker(title: String(localized: "Cuenta de pago"), accounts: paymentAccounts, selection: $paymentAccountID)
            Picker("Método de pago", selection: $method) {
                ForEach(Self.methods, id: \.self) { Text(Self.title(for: $0)).tag($0) }
            }
        } header: {
            SectionLabel(text: String(localized: "Detalles"))
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section {
            TextField("Ej. materiales para una obra", text: $memo, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityLabel("Nota")
        } header: {
            SectionLabel(text: String(localized: "Nota"))
        }
    }

    // MARK: iPhone

    private var compactForm: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            amountSection
            detailsSection
            noteSection
            Section {
                ForEach(receipts) { receipt in
                    HStack(spacing: 12) {
                        ReceiptThumbnail(data: receipt.data, contentType: receipt.type.identifier, side: 48)
                        Text(receipt.name).lineLimit(1)
                    }
                }
                .onDelete { receipts.remove(atOffsets: $0) }
                ReceiptPickerButtons { receipts.append($0) }
            } header: {
                SectionLabel(text: String(localized: "Recibo"))
            }
        }
        .formStyle(.grouped)
        .screenBackground()
    }

    // MARK: iPad y Mac (`MacGastoNuevo`)

    /// Recibo a la izquierda (zona para arrastrar una foto o un PDF) y el formulario agrupado a la derecha. «Impuesto
    /// incluido», «Cliente o proyecto» y «Gasto recurrente» del canvas no tienen columna en el modelo: quedan fuera.
    private var wideForm: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    ReceiptDropPanel(receipts: $receipts)
                    #if os(macOS)
                    Button("Guardar y nuevo") { save(another: true) }
                        .disabled(!canSave)
                    #endif
                }
                .padding(Metrics.gutter)
            }
            .frame(width: editorWidth >= 700 ? 300 : 260)
            Divider()
            Form {
                amountSection
                detailsSection
                noteSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 600)
        #endif
    }

    private static let methods: [PaymentMethod] = [.card, .bankTransfer, .cash, .check]

    static func title(for method: PaymentMethod) -> String {
        switch method {
        case .card: String(localized: "Tarjeta")
        case .bankTransfer: String(localized: "Transferencia")
        case .cash: String(localized: "Efectivo")
        case .check: String(localized: "Cheque")
        case .other: String(localized: "Otro")
        }
    }

    /// Con `another`, deja el formulario limpio para el siguiente gasto («Guardar y nuevo»).
    private func save(another: Bool = false) {
        let vendor = vendors.first { $0.id == vendorID }
        let expense = Expense(date: date, payee: payee.isEmpty ? (vendor?.name ?? "") : payee, paymentAccountID: paymentAccountID, vendor: vendor)
        expense.memo = memo
        expense.methodRaw = method.rawValue
        let line = ExpenseLine(details: memo.isEmpty ? expense.payee : memo, amount: amount, accountID: categoryID)
        context.insert(expense)
        line.expense = expense
        context.insert(line)
        let books = Bookkeeper(context: context)
        do {
            try books.record(expense)
        } catch {
            context.delete(expense)
            errorMessage = error.localizedDescription
            return
        }
        // El gasto ya está registrado; un recibo ilegible no lo deshace, solo se avisa.
        var failed: [String] = []
        for receipt in receipts {
            do { try books.attachReceipt(receipt.data, filename: receipt.name, contentType: receipt.type, to: expense) }
            catch { failed.append(receipt.name) }
        }
        if failed.isEmpty, another {
            amount = 0; payee = ""; vendorID = nil; memo = ""; receipts = []; categoryID = nil; errorMessage = nil
        } else if failed.isEmpty { unsavedChanges?.remove(editorToken); dismiss() } else {
            errorMessage = String(localized: "El gasto se guardó, pero no se pudo adjuntar: \(failed.joined(separator: ", ")). Ábrelo desde la lista para reintentar.")
        }
    }
}

// MARK: - Por pagar

/// Facturas por pagar (canvas `Gastos` · Por pagar): por grupos (vencidas, esta semana, más adelante, pagadas), cada
/// una con su hoja de calendario. Al tocarla se abre su ficha; deslizando, «Pagar».
struct BillListView: View {
    var section: Binding<ExpensesView.Segment>? = nil
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var paying: Bill?

    private struct BillGroup: Identifiable {
        let id: String
        let title: String
        let bills: [Bill]
        var total: Int64 { bills.reduce(0) { $0 + ($1.isOpen ? $1.balanceDue : $1.total) } }
    }

    private var groups: [BillGroup] {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)) ?? .now
        let open = bills.filter(\.isOpen)
        return [
            BillGroup(id: "overdue", title: String(localized: "Vencidas"), bills: open.filter(\.isOverdue)),
            BillGroup(id: "week", title: String(localized: "Esta semana"), bills: open.filter { !$0.isOverdue && $0.dueDate < weekEnd }),
            BillGroup(id: "later", title: String(localized: "Más adelante"), bills: open.filter { $0.dueDate >= weekEnd }),
            BillGroup(id: "paid", title: String(localized: "Pagadas"), bills: bills.filter { $0.status == .paid }.sorted { $0.dueDate > $1.dueDate }),
            BillGroup(id: "void", title: String(localized: "Anuladas"), bills: bills.filter { $0.status == .void }),
        ].filter { !$0.bills.isEmpty }
    }

    var body: some View {
        List {
            if let section { ExpensesSegmentRow(selection: section) }
            if bills.isEmpty {
                Section {
                    EmptyStateView(systemImage: "doc.text", title: String(localized: "Sin facturas por pagar"),
                                   message: String(localized: "Registra las facturas de tus proveedores para saber qué vence y cuándo."))
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.bills) { bill in
                        NavigationLink { BillDetailView(bill: bill) } label: { BillRow(bill: bill) }
                            .navigationLinkIndicatorVisibility(.hidden)
                            .swipeActions {
                                if bill.isOpen {
                                    Button("Pagar") { paying = bill }.tint(Palette.brandFill)
                                }
                            }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(group.title) · \(String(localized: "\(group.bills.count) facturas"))")
                        Spacer(minLength: 8)
                        Text(group.total.money).monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .groupedList()
        .screenBackground()
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) }.editorSheetSizing() }
    }
}

/// Fila de factura por pagar (canvas `Gastos` · Por pagar): hoja de calendario con el vencimiento, proveedor, número y
/// concepto, y el saldo con su estado.
struct BillRow: View {
    let bill: Bill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        let parts = [bill.vendorNumber, bill.concept].filter { !$0.isEmpty }
        return parts.isEmpty ? bill.dueDate.dueLabel : parts.joined(separator: " · ")
    }

    var body: some View {
        LedgerRow(title: bill.vendor?.name ?? String(localized: "Proveedor"), subtitle: subtitle) {
            DateTile(date: bill.dueDate)
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text((bill.isOpen ? bill.balanceDue : bill.total).money).monospacedDigit().foregroundStyle(Palette.ink)
                StatusChip(billWithAge: bill)
            }
        }
        .accessibilityHint(Text(String(localized: "Vence el \(bill.dueDate.shortDate)")))
    }
}

struct BillEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var vendorID: UUID?
    @State private var number = ""
    @State private var billDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var amount: Int64 = 0
    @State private var accountID: UUID?
    @State private var details = ""
    @State private var errorMessage: String?
    @FocusState private var editingDetails: Bool

    private var costAccounts: [Account] { accounts.filtered { $0.accountType == .expense || $0 == .fixedAsset || $0 == .inventory } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Picker("Proveedor", selection: $vendorID) {
                    Text("Elegir…").tag(UUID?.none)
                    ForEach(vendors.filter { !$0.isArchived || $0.id == vendorID }) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Número de la factura del proveedor", text: $number)
                DatePicker("Fecha", selection: $billDate, displayedComponents: .date)
                DatePicker("Vence", selection: $dueDate, in: billDate..., displayedComponents: .date)
            } header: {
                SectionLabel(text: String(localized: "Factura"))
            }
            Section {
                LabeledContent("Importe total") {
                    // Sin su propia etiqueta: en el Mac salía «Importe total Importe total».
                    MoneyField(title: String(localized: "Importe total"), minorUnits: $amount).multilineTextAlignment(.trailing).labelsHidden()
                }
                AccountPicker(title: String(localized: "Categoría"), accounts: costAccounts, selection: $accountID)
                // Toda la fila da el foco al campo: en el iPad en horizontal, tocar la descripción a veces no lo hacía.
                TextField("Descripción", text: $details)
                    .focused($editingDetails)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { editingDetails = true }
            } header: {
                SectionLabel(text: String(localized: "Importe"))
            }
        }
        // Agrupado también en el Mac: con el estilo por defecto los campos llegaban a los bordes de la hoja.
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Factura por pagar")
        .inlineTitle()
        .discardableEditor(tracking: "\(vendorID?.uuidString ?? "")|\(number)|\(billDate)|\(dueDate)|\(amount)|\(accountID?.uuidString ?? "")|\(details)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(vendorID == nil || amount <= 0 || accountID == nil).headerButton()
            }
        }
        .onChange(of: vendorID) {
            guard let vendor = vendors.first(where: { $0.id == vendorID }) else { return }
            accountID = vendor.defaultExpenseAccountID ?? accountID
            dueDate = Calendar.current.date(byAdding: .day, value: vendor.paymentTermsDays, to: billDate) ?? dueDate
        }
    }

    private func save() {
        let bill = Bill(vendor: vendors.first { $0.id == vendorID }, vendorNumber: number, billDate: billDate, dueDate: dueDate)
        let line = BillLine(details: details, amount: amount, accountID: accountID)
        context.insert(bill)
        line.bill = bill
        context.insert(line)
        do {
            try Bookkeeper(context: context).record(bill)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            context.delete(bill)
            errorMessage = error.localizedDescription
        }
    }
}

/// Registrar el pago de una factura por pagar (canvas `MacPorPagar`, inspector: Detalles y Pago): la factura arriba y,
/// debajo, monto, fecha, cuenta y método.
struct PayBillView: View {
    let bill: Bill
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer
    @State private var errorMessage: String?

    private var paymentAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds } }
    private var canPay: Bool { amount > 0 && amount <= bill.balanceDue && accountID != nil }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Proveedor", value: bill.vendor?.name ?? "—")
                if !bill.vendorNumber.isEmpty { LabeledContent("Número", value: bill.vendorNumber) }
                LabeledContent("Vence") {
                    Text(bill.dueDate.shortDate).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                }
                LabeledContent("Saldo", value: bill.balanceDue.money).monospacedDigit()
            } header: {
                SectionLabel(text: String(localized: "Factura"))
            }
            Section {
                LabeledContent("Monto") {
                    MoneyField(title: String(localized: "Monto"), minorUnits: $amount).multilineTextAlignment(.trailing).labelsHidden()
                }
                DatePicker("Fecha de pago", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $accountID)
                Picker("Método", selection: $method) {
                    ForEach([PaymentMethod.bankTransfer, .check, .card, .cash], id: \.self) { Text(ExpenseEditorView.title(for: $0)).tag($0) }
                }
            } header: {
                SectionLabel(text: String(localized: "Pago"))
            } footer: {
                if amount > bill.balanceDue {
                    Text("El monto supera el saldo de \(bill.balanceDue.money).").foregroundStyle(Palette.negative)
                } else {
                    Text("El pago se registra en tus libros; el dinero se mueve desde tu banco.")
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Pagar factura")
        .inlineTitle()
        .discardableEditor(tracking: "\(amount)|\(date)|\(accountID?.uuidString ?? "")|\(method)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Registrar pago", action: pay).disabled(!canPay).headerButton() }
        }
        .onAppear {
            amount = bill.balanceDue
            accountID = accountID ?? paymentAccounts.first { $0.subtype == .bank }?.id
        }
    }

    private func pay() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).pay(bill, amount: amount, date: date, from: account, method: method)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Proveedores

/// Proveedores del iPhone (canvas `MacProveedores` en lista): monograma, 1099 o correo, y lo que se le debe.
struct VendorListView: View {
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var query = ""

    private var shown: [Vendor] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return vendors.filter { !$0.isArchived && (text.isEmpty || $0.name.localizedStandardContains(text) || $0.email.localizedStandardContains(text)) }
    }

    var body: some View {
        List {
            if vendors.isEmpty {
                EmptyStateView(systemImage: "truck.box", title: String(localized: "Sin proveedores"), message: String(localized: "Añade a quienes te venden bienes o servicios."))
            } else if shown.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: String(localized: "Sin resultados"), message: String(localized: "Ningún proveedor coincide"))
            }
            Section {
                ForEach(shown) { vendor in
                    NavigationLink { VendorDetailView(vendor: vendor) } label: { VendorRow(vendor: vendor) }
                }
            }
        }
        .groupedList()
        .screenBackground()
        .searchable(text: $query, prompt: Text("Nombre o correo"))
    }
}

/// Fila de proveedor: monograma gris, 1099 o correo, y lo que se le debe.
struct VendorRow: View {
    let vendor: Vendor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: vendor.name, subtitle: vendor.email.isEmpty ? String(localized: "Proveedor") : vendor.email) {
            InitialsTile(text: Initials.from(vendor.name))
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text(vendor.openBalance.money).monospacedDigit().foregroundStyle(Palette.ink)
                if vendor.is1099 {
                    Text("1099").font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
        }
    }
}

struct VendorEditorView: View {
    var vendor: Vendor?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var terms = 30
    @State private var defaultAccountID: UUID?
    @State private var is1099 = false
    @State private var tinLast4 = ""

    var body: some View {
        Form {
            Section {
                TextField("Nombre o empresa", text: $name)
                TextField("Correo", text: $email)
                    #if os(iOS)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    #endif
                TextField("Teléfono", text: $phone)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
            } header: {
                SectionLabel(text: String(localized: "Contacto"))
            }
            Section {
                Picker("Condiciones de pago", selection: $terms) {
                    Text("Al recibir").tag(0); Text("Neto 15").tag(15); Text("Neto 30").tag(30); Text("Neto 60").tag(60)
                }
                AccountPicker(title: String(localized: "Categoría por defecto"), accounts: accounts.filtered { $0.accountType == .expense }, selection: $defaultAccountID)
                Toggle("Sujeto a 1099", isOn: $is1099)
                if is1099 { TextField("Últimos 4 dígitos del TIN", text: $tinLast4) }
            } header: {
                SectionLabel(text: String(localized: "Pagos"))
            } footer: {
                Text("Chirogra solo guarda los últimos 4 dígitos del TIN.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(vendor == nil ? String(localized: "Nuevo proveedor") : vendor!.name)
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|\(email)|\(phone)|\(terms)|\(defaultAccountID?.uuidString ?? "")|\(is1099)|\(tinLast4)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).headerButton()
            }
        }
        .onAppear {
            guard let vendor else { return }
            name = vendor.name; email = vendor.email; phone = vendor.phone; terms = vendor.paymentTermsDays
            defaultAccountID = vendor.defaultExpenseAccountID; is1099 = vendor.is1099; tinLast4 = vendor.tinLast4
        }
    }

    private func save() {
        let target = vendor ?? Vendor(name: name)
        if vendor == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.email = email; target.phone = phone; target.paymentTermsDays = terms
        target.defaultExpenseAccountID = defaultAccountID; target.is1099 = is1099
        target.tinLast4 = String(tinLast4.filter(\.isNumber).suffix(4))
        try? context.save()
        unsavedChanges?.remove(editorToken); dismiss()
    }
}
