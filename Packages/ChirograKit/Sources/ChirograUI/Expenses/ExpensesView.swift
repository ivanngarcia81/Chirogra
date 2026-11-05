import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import TipKit
import UniformTypeIdentifiers

/// Gastos (canvas `Gastos`): gastos pagados, facturas por pagar y recurrentes con el segmentado, y los proveedores
/// desde una fila. Es la pantalla del iPhone (y la de la columna estrecha del iPad, o con AX4 o más); en iPad y Mac
/// cada subsección va con columna maestro (`MasterPage`) o tabla.
struct ExpensesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case expenses = "Gastos"
        case bills = "Por pagar"
        case recurring = "Recurrentes"
        case vendors = "Proveedores"
        var id: String { rawValue }
    }

    /// Desde la barra lateral o un enlace, la subsección ya elegida y sin el segmentado.
    var fixedSegment: Segment? = nil

    @State private var selectedSegment: Segment = .expenses
    @State private var showingEditor = false

    private var segment: Segment { fixedSegment ?? selectedSegment }

    /// El segmentado del canvas es Gastos · Por pagar · Recurrentes; Proveedores va como fila de la pantalla de Gastos.
    private var picker: Binding<Segment>? { fixedSegment == nil ? $selectedSegment : nil }

    private var title: String {
        // En iPhone van bajo «Gastos» con el selector; desde un enlace cada una tiene su título.
        guard fixedSegment != nil else { return String(localized: "Gastos") }
        return switch segment {
        case .expenses: String(localized: "Gastos")
        case .bills: String(localized: "Facturas por pagar")
        case .recurring: String(localized: "Recurrentes")
        case .vendors: String(localized: "Proveedores")
        }
    }

    private var addTitle: LocalizedStringResource {
        switch segment {
        case .expenses: "Nuevo gasto"
        case .bills: "Nueva factura de proveedor"
        case .recurring: "Nueva recurrente"
        case .vendors: "Nuevo proveedor"
        }
    }

    var body: some View {
        Group {
            switch segment {
            case .expenses: ExpenseListView(section: picker, showBills: { selectedSegment = .bills }) { showingEditor = true }
            case .bills: BillListView(section: picker) { showingEditor = true }
            case .recurring: RecurringListView(section: picker)
            case .vendors: VendorListView { showingEditor = true }
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
                case .recurring: RecurringTemplateEditorView()
                case .vendors: VendorEditorView()
                }
            }
            .editorSheetSizing()
        }
        // Lo que la app hace sola (recurrentes de hoy y cargos automáticos) también al abrir Gastos: es idempotente.
        .task { RecurringAutomation.run(in: context) }
    }

    @Environment(\.modelContext) private var context
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

/// Segmentado Gastos · Por pagar · Recurrentes arriba de la lista, bajo el título grande (se desplaza con ella, como
/// en el canvas).
struct ExpensesSegmentRow: View {
    @Binding var selection: ExpensesView.Segment

    var body: some View {
        Section {
            FilterPicker(title: String(localized: "Sección"), options: [.expenses, .bills, .recurring], selection: $selection) { $0.localizedTitle }
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
    /// «Anotar mi primer gasto» del estado vacío (el «+» de `ExpensesView`).
    var onCreate: (() -> Void)? = nil
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var filter: ExpenseReceiptFilter = .all
    @State private var cardWidth: CGFloat = 0
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context

    private func category(_ expense: Expense) -> Account? {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }
    }

    /// Los anulados no cuentan ni se listan; los «por confirmar» (sin asiento, de una recurrente sin cargo automático)
    /// van en su grupo con «Registrar».
    private var posted: [Expense] { expenses.filter { $0.isPosted && !$0.isVoid } }
    private var pending: [Expense] { expenses.filter(\.isPendingConfirmation) }

    var body: some View {
        let shown = posted.filter(filter.includes)
        List {
            if let errorMessage { ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            if let section {
                ExpensesSegmentRow(selection: section)
                #if os(iOS)
                // Recurrentes: cuando ya hay algún gasto, una vez (abre la sección).
                Section {
                    InlineTip(tip: RecurringTip()) { _ in
                        RecurringTip().invalidate(reason: .actionPerformed)
                        section.wrappedValue = .recurring
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                #endif
            }

            Section {
                monthCard
            } header: {
                ListGroupHeader(title: cardMonth.start.formatted(.appDateTime.month(.wide)).sentenceCased) {
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

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { expense in
                        PendingExpenseRow(expense: expense, category: category(expense)) { record(expense) }
                    }
                } header: {
                    ListGroupHeader(title: String(localized: "Por confirmar")) {
                        Text("\(pending.count) de recurrentes").font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                } footer: {
                    Text("Los generó una recurrente sin cargo automático: revisa el importe y regístralos.")
                }
            }

            Section {
                if expenses.isEmpty {
                    EmptyStateView(guide: .expenses, action: onCreate)
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
        .task(id: expenses.isEmpty) { RecurringTip.hasExpenses = !expenses.isEmpty }
    }

    private func record(_ expense: Expense) {
        do {
            try Bookkeeper(context: context).record(expense)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Mes de la tarjeta: el actual o, si aún no tiene gastos (a primeros de mes), el último que sí tiene, como Gastos
    /// en el Mac (decisión del usuario, 2-nov).
    private var cardMonth: DateInterval {
        #if DEBUG
        // `-qa.mes anterior` (solo Debug): el mes anterior, para las capturas de la App Store.
        if UserDefaults.standard.string(forKey: "qa.mes") == "anterior",
           let previous = Calendar.current.date(byAdding: .month, value: -1, to: .now) {
            return DateInterval.month(containing: previous)
        }
        #endif
        let current = DateInterval.month(containing: .now)
        guard !posted.contains(where: { current.contains($0.date) && $0.date < current.end }),
              let latest = posted.first?.date else { return current }
        return DateInterval.month(containing: latest)
    }

    /// Gasto del mes por categoría: solo los gastos de la lista (sus líneas), como la tarjeta de Gastos del Mac
    /// (decisión del usuario, 2-nov: antes salía del estado de resultados e incluía las facturas por pagar). Las cuatro
    /// mayores y el resto en «Otros».
    private var monthCard: some View {
        let month = cardMonth
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Int64] = [:]
        for expense in posted where month.contains(expense.date) && expense.date < month.end {
            var categorized: Int64 = 0
            for line in expense.sortedLines {
                guard let id = line.accountID, let name = names[id] else { continue }
                totals[name, default: 0] += line.amount
                categorized += line.amount
            }
            if expense.total > categorized { totals[String(localized: "Sin categoría"), default: 0] += expense.total - categorized }
        }
        let rows = totals.filter { $0.value > 0 }.map { (name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
        let total = rows.reduce(0) { $0 + $1.amount }
        var slices = rows.prefix(4).map { (name: $0.name, amount: $0.amount) }
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

    /// «Software · recurrente · 27 oct» (canvas `Gastos`): la categoría, si lo generó una recurrente, y el día.
    private var subtitle: String {
        var parts = [category?.name ?? String(localized: "Sin categoría")]
        if expense.recurringTemplateID != nil { parts.append(String(localized: "recurrente")) }
        if expense.isBillable, let customer = expense.customer { parts.append(customer.name) }
        parts.append(expense.date.relativeDay)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LedgerRow(title: expense.payee, subtitle: subtitle) {
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

// MARK: - Por pagar

/// Facturas por pagar (canvas `Gastos` · Por pagar): por grupos (vencidas, esta semana, más adelante, pagadas), cada
/// una con su hoja de calendario. Al tocarla se abre su ficha; deslizando, «Pagar» o «Programar». «Seleccionar» pasa
/// al modo de selección para pagar varias en lote (canvas `MacPorPagar`), con la barra «Pagar $X» al pie.
struct BillListView: View {
    var section: Binding<ExpensesView.Segment>? = nil
    /// «Anotar una factura por pagar» del estado vacío (el «+» de `ExpensesView`).
    var onCreate: (() -> Void)? = nil
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var paying: Bill?
    @State private var scheduling: Bill?
    @State private var isSelecting = false
    @State private var selected: Set<UUID> = []
    @State private var payingBatch = false

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
        var groups = [
            BillGroup(id: "overdue", title: String(localized: "Vencidas"), bills: open.filter(\.isOverdue)),
            BillGroup(id: "week", title: String(localized: "Esta semana"), bills: open.filter { !$0.isOverdue && $0.dueDate < weekEnd }),
            BillGroup(id: "later", title: String(localized: "Más adelante"), bills: open.filter { $0.dueDate >= weekEnd }),
        ]
        // En el modo de selección solo cuentan las abiertas.
        if !isSelecting {
            groups += [
                BillGroup(id: "paid", title: String(localized: "Pagadas"), bills: bills.filter { $0.status == .paid }.sorted { $0.dueDate > $1.dueDate }),
                BillGroup(id: "void", title: String(localized: "Anuladas"), bills: bills.filter { $0.status == .void }),
            ]
        }
        return groups.filter { !$0.bills.isEmpty }
    }

    private var selectedBills: [Bill] { bills.filter { selected.contains($0.id) && $0.isOpen } }

    var body: some View {
        List {
            if let section, !isSelecting { ExpensesSegmentRow(selection: section) }
            if bills.isEmpty {
                Section {
                    EmptyStateView(guide: .bills, action: onCreate)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.bills) { bill in
                        if isSelecting {
                            selectableRow(bill)
                        } else {
                            NavigationLink { BillDetailView(bill: bill) } label: { BillRow(bill: bill, accounts: accounts) }
                                .navigationLinkIndicatorVisibility(.hidden)
                                .swipeActions {
                                    if bill.isOpen {
                                        Button("Pagar") { paying = bill }.tint(Palette.brandFill)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if bill.isOpen {
                                        Button(bill.isScheduled ? "Cambiar" : "Programar", systemImage: "calendar.badge.clock") { scheduling = bill }
                                            .tint(Palette.indigo)
                                    }
                                }
                                .contextMenu {
                                    if bill.isOpen { Button("Registrar pago…", systemImage: "checkmark.circle") { paying = bill } }
                                    BillScheduleMenuItems(bill: bill) { scheduling = bill }
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
        .toolbar {
            if bills.contains(where: \.isOpen) {
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "Listo" : "Seleccionar") { toggleSelecting() }
                        .headerButton()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                BatchPayBar(selected: selectedBills, accounts: accounts, clear: { selected = [] }) { payingBatch = true }
            }
        }
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) }.editorSheetSizing() }
        .sheet(item: $scheduling) { bill in NavigationStack { SchedulePaymentView(bill: bill) }.editorSheetSizing() }
        .sheet(isPresented: $payingBatch) {
            NavigationStack {
                BatchPayView(bills: selectedBills) { selected = []; isSelecting = false }
            }
            .editorSheetSizing()
        }
    }

    private func toggleSelecting() {
        withAnimation {
            isSelecting.toggle()
            if !isSelecting { selected = [] }
        }
    }

    /// Fila del modo de selección: el círculo a la izquierda y la fila de siempre; tocarla la marca o desmarca.
    private func selectableRow(_ bill: Bill) -> some View {
        let isOn = selected.contains(bill.id)
        return Button {
            if isOn { selected.remove(bill.id) } else { selected.insert(bill.id) }
        } label: {
            HStack(spacing: 12) {
                SelectionMark(isOn: isOn)
                BillRow(bill: bill, accounts: accounts)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint(Text("Incluir en el pago en lote"))
    }
}

/// Fila de factura por pagar (canvas `Gastos` · Por pagar): hoja de calendario con el vencimiento, proveedor, número y
/// concepto (o «Programado · Corriente ••4821»), y el saldo con su estado.
struct BillRow: View {
    let bill: Bill
    var accounts: [Account] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        if let payment = bill.paymentSummary(accounts: accounts) { return payment }
        let parts = [bill.vendorNumber, bill.concept].filter { !$0.isEmpty }
        return parts.isEmpty ? bill.dueDate.dueLabel : parts.joined(separator: " · ")
    }

    var body: some View {
        LedgerRow(title: bill.vendor?.name ?? String(localized: "Proveedor"), subtitle: subtitle) {
            DateTile(date: bill.dueDate)
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                Text((bill.isOpen ? bill.balanceDue : bill.total).money).monospacedDigit().foregroundStyle(Palette.ink)
                StatusChip(billWithAge: bill, short: true)
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

    private var paymentAccounts: [Account] { accounts.paymentAccounts }
    private var canPay: Bool { amount > 0 && amount <= bill.balanceDue && accountID != nil }
    @State private var loaded = false

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
                PaymentAccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $accountID)
                Picker("Método", selection: $method) {
                    ForEach(PaymentMethod.billMethods, id: \.self) { Text($0.title).tag($0) }
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
            // El pago programado, si lo hay; si no, el pago preferido del proveedor; si no, la primera cuenta de banco.
            guard !loaded else { return }
            loaded = true
            amount = bill.balanceDue
            accountID = bill.scheduledPaymentAccountID ?? bill.vendor?.preferredPaymentAccountID
                ?? paymentAccounts.first { $0.subtype == .bank }?.id
            method = bill.scheduledPaymentMethod ?? bill.vendor?.preferredPaymentMethod ?? .bankTransfer
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
    /// «Añadir mi primer proveedor» del estado vacío (el «+» de `ExpensesView`).
    var onCreate: (() -> Void)? = nil
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @State private var query = ""

    private var shown: [Vendor] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return vendors.filter { !$0.isArchived && (text.isEmpty || $0.name.localizedStandardContains(text) || $0.email.localizedStandardContains(text)) }
    }

    var body: some View {
        List {
            if vendors.isEmpty {
                EmptyStateView(guide: .vendors, action: onCreate)
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

/// Alta y edición de proveedor: contacto, condiciones, 1099 con el W-9 (recibido, fecha y copia) y el pago preferido
/// (método y cuenta), que es el que se propone al pagarle (canvas `MacProveedorFicha`, docs/DATOS-V2.md §6).
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
    @State private var w9Received = false
    @State private var w9Date = Date()
    /// Copia del W-9 elegida en el editor (se adjunta al guardar).
    @State private var w9File: ReceiptFile?
    @State private var preferredMethod: PaymentMethod?
    @State private var preferredAccountID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
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
                Picker("Método preferido", selection: $preferredMethod) {
                    Text("Sin preferencia").tag(PaymentMethod?.none)
                    ForEach(PaymentMethod.billMethods, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                PaymentAccountPicker(title: String(localized: "Pagar desde"), accounts: accounts.paymentAccounts, selection: $preferredAccountID)
            } header: {
                SectionLabel(text: String(localized: "Pagos"))
            } footer: {
                Text("El pago preferido se propone al pagarle o programar un pago.")
            }
            Section {
                Toggle("Sujeto a 1099", isOn: $is1099)
                if is1099 { TextField("Últimos 4 dígitos del TIN", text: $tinLast4) }
                Toggle("W-9 recibido", isOn: $w9Received.animation())
                if w9Received {
                    DatePicker("Recibido el", selection: $w9Date, displayedComponents: .date)
                }
                if let w9File {
                    HStack(spacing: 12) {
                        ReceiptThumbnail(data: w9File.data, contentType: w9File.type.identifier, side: 40)
                        Text(w9File.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Quitar") { self.w9File = nil }.buttonStyle(.borderless)
                            .accessibilityLabel("Quitar \(w9File.name)")
                    }
                } else if let attachment = vendor?.w9Attachment {
                    HStack(spacing: 12) {
                        ReceiptThumbnail(data: attachment.data, contentType: attachment.contentType, side: 40)
                        Text(attachment.filename).lineLimit(1).truncationMode(.middle)
                    }
                }
                W9PickerButtons { file in
                    w9File = file
                    w9Received = true
                }
            } header: {
                SectionLabel(text: String(localized: "Formulario 1099 y W-9"))
            } footer: {
                Text("Chirogra solo guarda los últimos 4 dígitos del TIN. Pide el W-9 antes de pagarle a un contratista.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(vendor == nil ? String(localized: "Nuevo proveedor") : vendor!.name)
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|\(email)|\(phone)|\(terms)|\(defaultAccountID?.uuidString ?? "")|\(is1099)|\(tinLast4)|\(w9Received)|\(w9Date)|\(w9File?.id.uuidString ?? "")|\(preferredMethod?.rawValue ?? "")|\(preferredAccountID?.uuidString ?? "")", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).headerButton()
            }
        }
        .onAppear {
            guard let vendor else { return }
            name = vendor.name; email = vendor.email; phone = vendor.phone; terms = vendor.paymentTermsDays
            defaultAccountID = vendor.defaultExpenseAccountID; is1099 = vendor.is1099; tinLast4 = vendor.tinLast4
            w9Received = vendor.w9Received; w9Date = vendor.w9ReceivedDate ?? Date()
            preferredMethod = vendor.preferredPaymentMethod; preferredAccountID = vendor.preferredPaymentAccountID
        }
    }

    private func save() {
        let target = vendor ?? Vendor(name: name)
        if vendor == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.email = email; target.phone = phone; target.paymentTermsDays = terms
        target.defaultExpenseAccountID = defaultAccountID; target.is1099 = is1099
        target.tinLast4 = String(tinLast4.filter(\.isNumber).suffix(4))
        let books = Bookkeeper(context: context)
        do {
            try books.setPreferredPayment(for: target, method: preferredMethod, account: accounts.account(preferredAccountID))
            if target.w9Received != w9Received || (w9Received && target.w9ReceivedDate.map { !Calendar.current.isDate($0, inSameDayAs: w9Date) } ?? true) {
                try books.setW9(for: target, received: w9Received, on: w9Date)
            }
            if let w9File {
                try books.attachW9(w9File.data, filename: w9File.name, contentType: w9File.type, to: target, receivedOn: w9Date)
            }
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Foto o archivo (PDF o imagen) del W-9, como los botones del recibo.
private struct W9PickerButtons: View {
    let onPick: (ReceiptFile) -> Void
    @State private var importing = false

    var body: some View {
        Button("Adjuntar copia del W-9 (PDF o foto)", systemImage: "doc.badge.plus") { importing = true }
            .frame(minHeight: Metrics.target)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let file = try? ReceiptFile(url: url, fallback: .data) else { return }
                onPick(file)
            }
    }
}
