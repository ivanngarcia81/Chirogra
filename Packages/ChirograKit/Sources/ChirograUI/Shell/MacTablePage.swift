import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Mac: tabla + inspector (decisión del usuario del 2-nov). En el Mac, las páginas de lista son como el canvas
// (`MacVentas`, `MacClientes`, `MacGastos`, `MacProveedores`, `MacPorPagar`, `BancaCuentas`, `MacPlanCuentas`,
// `MacDiario`): barra lateral + contenido, con la tabla a todo el ancho y un inspector de ~300 pt a la derecha con lo
// elegido. El iPad sigue con columna maestro + detalle (`MasterDetail.swift`). Cómo usar la pieza: docs/REDISEÑO-NATIVO.md,
// «Mac: tabla + inspector».

extension MasterPage {
    /// La página ya tiene su tabla del Mac. Cada página lo dice en su propio archivo (`static let isReady`); mientras
    /// sea `false`, el Mac la sigue mostrando con la columna maestro de antes (tres columnas).
    var hasMacTable: Bool {
        #if os(macOS)
        switch self {
        case .invoices: InvoiceTablePage.isReady
        case .customers: CustomerTablePage.isReady
        case .expenses: ExpenseTablePage.isReady
        case .vendors: VendorTablePage.isReady
        case .bills: BillTablePage.isReady
        case .banking: BankingTablePage.isReady
        case .journal: JournalTablePage.isReady
        case .chart: ChartTablePage.isReady
        }
        #else
        false
        #endif
    }

    #if os(macOS)
    /// Contenido de la página en el Mac: su tabla con el inspector. La selección vive en `AppShell` (se vacía al
    /// cambiar de página), como la de la columna maestro.
    @ViewBuilder
    func macTable(selection: Binding<UUID?>) -> some View {
        switch self {
        case .invoices: InvoiceTablePage(selection: selection)
        case .customers: CustomerTablePage(selection: selection)
        case .expenses: ExpenseTablePage(selection: selection)
        case .vendors: VendorTablePage(selection: selection)
        case .bills: BillTablePage(selection: selection)
        case .banking: BankingTablePage(selection: selection)
        case .journal: JournalTablePage(selection: selection)
        case .chart: ChartTablePage(selection: selection)
        }
    }
    #endif
}

#if os(macOS)

/// Estado vacío de la tabla: sin datos todavía, o sin resultados con «Quitar filtros» (canvas `MacVentas`).
struct MacTableEmpty {
    var systemImage = "magnifyingglass"
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// La guía de una sección vacía: el botón para empezar va como botón principal.
    var isGuide = false
}

extension MacTableEmpty {
    /// Sección vacía (empresa nueva): qué es, para qué sirve y el botón para empezar (`EmptyGuide`), igual que en el
    /// iPhone y el iPad.
    init(guide: EmptyGuide, action: (() -> Void)?) {
        self.init(systemImage: guide.systemImage, title: guide.title, message: guide.message,
                  actionTitle: action == nil ? nil : guide.actionTitle, action: action, isGuide: true)
    }
}

/// Página de tabla del Mac (canvas `MacVentas` y siguientes): título y subtítulo de la ventana, búsqueda y «+» en la
/// barra, el filtro (segmentado) arriba del contenido, las cajas de cifras si las hay, la `Table` del sistema con
/// columnas ordenables y cebra, el pie con la cuenta y, a la derecha, el inspector nativo (`.inspector`) de ~300 pt con
/// lo elegido y sus botones al pie. Elegir una fila abre el inspector; ⌥⌘I o el botón de la barra lo muestra u oculta;
/// doble clic (o «Abrir» del menú contextual) llama a `onOpen`.
///
/// La página pone los datos ya filtrados (`rows`); la pieza los ordena con el orden de las columnas.
///
/// Filas jerárquicas (canvas `MacPlanCuentas`): con `children:` (key path a las filas hijas, `nil` o vacío en una hoja),
/// cada fila con hijas lleva el triángulo del sistema para plegarla (`DisclosureTableRow`); las hermanas se ordenan
/// entre sí con el orden de las columnas. Todo empieza desplegado y, mientras hay texto en la búsqueda, todo se
/// muestra desplegado. Sin `children:`, la tabla plana de siempre (las demás páginas no cambian).
struct MacTablePage<Value, Sort, Columns, Filter, Inspector, Actions>: View
where Value: Identifiable, Value.ID == UUID,
      Sort: SortComparator, Sort.Compared == Value,
      Columns: TableColumnContent, Columns.TableRowValue == Value, Columns.TableColumnSortComparator == Sort,
      Filter: View, Inspector: View, Actions: View {
    let title: String
    let subtitle: String
    let rows: [Value]
    /// Pie bajo la tabla («14 facturas», «3 de 14 facturas»).
    let footer: String
    @Binding var query: String
    let searchPrompt: Text
    @Binding var selection: UUID?
    let kpis: [KPIItem]
    let addTitle: String
    let onAdd: () -> Void
    let onOpen: ((Value) -> Void)?
    let empty: MacTableEmpty
    /// Filas hijas de cada fila (tabla jerárquica); `nil` = tabla plana.
    let children: KeyPath<Value, [Value]?>?
    let inspectorTitle: (Value?) -> String
    /// Inspector sin nada elegido («Selecciona una factura para ver sus detalles.»).
    let inspectorPlaceholder: String
    private let columns: Columns
    private let filter: Filter
    private let inspector: (Value) -> Inspector
    private let actions: (Value) -> Actions
    @State private var sortOrder: [Sort]
    /// Filas plegadas de la tabla jerárquica (todas empiezan desplegadas).
    @State private var collapsed: Set<UUID> = []
    /// Mostrado u oculto, igual en todas las páginas y entre arranques (como el inspector de Finder o Mail).
    @AppStorage("macInspectorShown") private var showsInspector = true

    init(title: String, subtitle: String, rows: [Value], footer: String, query: Binding<String>, searchPrompt: Text,
         selection: Binding<UUID?>, sortOrder: [Sort], kpis: [KPIItem] = [], addTitle: String, onAdd: @escaping () -> Void,
         onOpen: ((Value) -> Void)? = nil, empty: MacTableEmpty, children: KeyPath<Value, [Value]?>? = nil,
         inspectorTitle: @escaping (Value?) -> String,
         inspectorPlaceholder: String,
         @TableColumnBuilder<Value, Sort> columns: () -> Columns,
         @ViewBuilder filter: () -> Filter,
         @ViewBuilder inspector: @escaping (Value) -> Inspector,
         @ViewBuilder actions: @escaping (Value) -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.footer = footer
        _query = query
        self.searchPrompt = searchPrompt
        _selection = selection
        _sortOrder = State(initialValue: sortOrder)
        self.kpis = kpis
        self.addTitle = addTitle
        self.onAdd = onAdd
        self.onOpen = onOpen
        self.empty = empty
        self.children = children
        self.inspectorTitle = inspectorTitle
        self.inspectorPlaceholder = inspectorPlaceholder
        self.columns = columns()
        self.filter = filter()
        self.inspector = inspector
        self.actions = actions
    }

    var body: some View {
        let sorted = rows.sorted(using: sortOrder)
        // En la tabla jerárquica, lo elegido puede ser una fila hija (o estar dentro de una plegada).
        let selected = flattened(sorted, onlyVisible: false).first { $0.id == selection }
        VStack(alignment: .leading, spacing: 12) {
            filter
            if !kpis.isEmpty { KPIGrid(items: kpis) }
            table(sorted)
            Text(footer).font(.subheadline).foregroundStyle(Palette.ink2).padding(.horizontal, 2)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .searchable(text: $query, placement: .toolbar, prompt: searchPrompt)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { SubscriptionStore.shared.whenWritable(onAdd) } label: { Label(addTitle, systemImage: "plus").labelStyle(.titleAndIcon) }
                    .help(addTitle)
                    .headerButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsInspector.toggle() } label: {
                    Label(showsInspector ? "Ocultar inspector" : "Mostrar inspector", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help(showsInspector ? "Ocultar inspector (⌥⌘I)" : "Mostrar inspector (⌥⌘I)")
                .tint(showsInspector ? Palette.brand : Palette.ink)
            }
        }
        .inspector(isPresented: $showsInspector) {
            inspectorColumn(selected)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        // Elegir una fila abre el inspector con su detalle.
        .onChange(of: selection) { _, id in if id != nil { showsInspector = true } }
        #if DEBUG
        .onAppear {
            QALaunch.applyRow(in: flattened(sorted, onlyVisible: true).map(\.id), selection: $selection, inspector: $showsInspector)
            // `-qa.plegar N`: pliega la fila N (orden de la tabla) de una tabla jerárquica.
            if children != nil, UserDefaults.standard.object(forKey: "qa.plegar") != nil {
                let ids = flattened(sorted, onlyVisible: true).map(\.id)
                let index = UserDefaults.standard.integer(forKey: "qa.plegar")
                if ids.indices.contains(index) { collapsed.insert(ids[index]) }
            }
        }
        #endif
    }

    /// Las filas en el orden de la tabla: las hijas tras su madre (las de una plegada, solo si `onlyVisible` es falso).
    private func flattened(_ items: [Value], onlyVisible: Bool) -> [Value] {
        guard let children else { return items }
        return items.flatMap { item -> [Value] in
            let kids = (item[keyPath: children] ?? []).sorted(using: sortOrder)
            let hidden = onlyVisible && collapsed.contains(item.id) && query.isEmpty
            return [item] + (hidden ? [] : flattened(kids, onlyVisible: onlyVisible))
        }
    }

    @ViewBuilder
    private func table(_ sorted: [Value]) -> some View {
        if let children {
            styled(Table(of: Value.self, selection: $selection, sortOrder: $sortOrder) { columns } rows: {
                MacOutlineRows(items: sorted, children: children, sortOrder: sortOrder, collapsed: $collapsed,
                               expandsAll: !query.isEmpty)
            }, sorted: flattened(sorted, onlyVisible: false))
        } else {
            styled(Table(sorted, selection: $selection, sortOrder: $sortOrder) { columns }, sorted: sorted)
        }
    }

    private func styled(_ table: some View, sorted: [Value]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous)
        return table
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
            .environment(\.defaultMinListRowHeight, Metrics.rowHeight)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let onOpen, let id = ids.first, let value = sorted.first(where: { $0.id == id }) {
                    Button("Abrir") { onOpen(value) }
                }
            } primaryAction: { ids in
                if let onOpen, let id = ids.first, let value = sorted.first(where: { $0.id == id }) { onOpen(value) }
            }
            .overlay {
                if sorted.isEmpty { emptyState }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: empty.systemImage)
        } description: {
            Text(empty.message)
        } actions: {
            if let title = empty.actionTitle, let action = empty.action {
                if empty.isGuide {
                    Button(title) { SubscriptionStore.shared.whenWritable(action) }.buttonStyle(.primaryCompact)
                } else {
                    Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    /// Inspector (canvas: título de 15 bold, secciones de filas «etiqueta · valor» y los botones al pie).
    private func inspectorColumn(_ selected: Value?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(inspectorTitle(selected))
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            if let selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { inspector(selected) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                VStack(spacing: 8) { actions(selected) }
                    .padding(16)
            } else {
                ContentUnavailableView {
                    Label("Sin selección", systemImage: "sidebar.trailing")
                } description: {
                    Text(inspectorPlaceholder)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }
}

/// Filas de una tabla jerárquica: cada fila con hijas es un `DisclosureTableRow` (triángulo del sistema, también con
/// ← y → del teclado y en VoiceOver) cuyo estado vive en `collapsed`; las hijas se ordenan con el orden de la tabla.
struct MacOutlineRows<Value, Sort>: TableRowContent
where Value: Identifiable, Value.ID == UUID, Sort: SortComparator, Sort.Compared == Value {
    let items: [Value]
    let children: KeyPath<Value, [Value]?>
    let sortOrder: [Sort]
    @Binding var collapsed: Set<UUID>
    /// Con búsqueda, todo desplegado (como el canvas).
    let expandsAll: Bool

    var tableRowBody: some TableRowContent<Value> {
        ForEach(items) { item in
            if let kids = item[keyPath: children], !kids.isEmpty {
                DisclosureTableRow(item, isExpanded: expanded(item.id)) {
                    MacOutlineRows(items: kids.sorted(using: sortOrder), children: children, sortOrder: sortOrder,
                                   collapsed: $collapsed, expandsAll: expandsAll)
                }
            } else {
                SwiftUI.TableRow(item)
            }
        }
    }

    private func expanded(_ id: UUID) -> Binding<Bool> {
        Binding(get: { expandsAll || !collapsed.contains(id) },
                set: { open in if open { collapsed.remove(id) } else { collapsed.insert(id) } })
    }
}

/// Filtro de la página (canvas `MacVentas`: «Todas 14 · Borrador 1 · …»): el segmentado del sistema con la cuenta de
/// cada opción; si no cabe a lo ancho (ventana estrecha, inspector abierto), un menú con la opción elegida. Así el
/// segmentado no fija el ancho mínimo de la ventana.
struct MacTableFilter<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var count: ((Option) -> Int)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented).fixedSize()
            picker.pickerStyle(.menu).fixedSize()
        }
        .accessibilityLabel(title)
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                if let count { Text(verbatim: "\(label(option)) \(count(option))").tag(option) } else { Text(label(option)).tag(option) }
            }
        }
        .labelsHidden()
    }
}

/// Sección del inspector (canvas: «Detalles», «Importes»): encabezado de 11 semibold gris y filas separadas por líneas.
struct MacInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.label).foregroundStyle(Palette.ink2).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    subviews[index]
                }
            }
        }
    }
}

/// Fila «etiqueta gris · valor» del inspector, de 26 pt.
struct MacInspectorRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            value.multilineTextAlignment(.trailing)
        }
        .font(.body)
        .monospacedDigit()
        .frame(minHeight: 26)
        .accessibilityElement(children: .combine)
    }
}

extension MacInspectorRow where Value == Text {
    init(_ label: String, value: String, color: Color = Palette.ink, bold: Bool = false) {
        self.label = label
        self.value = Text(value).foregroundStyle(color).fontWeight(bold ? .semibold : .regular)
    }
}

/// Cabecera del inspector (canvas: nombre de 13 semibold, cifra de 24 bold y el estado debajo).
struct MacInspectorSummary<Status: View>: View {
    let title: String
    let amount: String
    @ViewBuilder var status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(amount).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            status
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texto de una celda en su color, o en blanco sobre la fila elegida (relleno de Tinta del sistema): los colores
/// fijos (`Palette.negative`…) no cambian solos al elegir la fila, los jerárquicos (`.secondary`) sí.
struct MacCellText: View {
    let text: String
    var color: Color = Palette.ink2
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(text).foregroundStyle(prominence == .increased ? Color.white : color)
    }
}

/// Estado de una fila de la tabla («● Vencida · 8 días»): el `StatusChip` de la fila, en blanco sobre la elegida.
struct MacCellStatus: View {
    let chip: StatusChip
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if prominence == .increased {
            StatusChip(text: chip.text, foreground: .white, background: .clear, compact: true, dot: .white)
        } else {
            chip
        }
    }
}

#endif

#if DEBUG
/// Argumentos de arranque para QA (solo en Debug): abren una sección y eligen una fila sin tocar el ratón.
/// `-qa.seccion invoices -qa.fila 0 -qa.inspector 1`; `-qa.muestra 1` carga los datos de ejemplo si no hay empresa;
/// `-qa.apariencia oscuro`; `-qa.pago 1` abre «Registrar pago…» de la factura elegida (Facturas del Mac).
enum QALaunch {
    private static var defaults: UserDefaults { .standard }

    /// Sección inicial (`home`, `invoices`, `estimates`, `customers`, `expenses`, `vendors`, `bills`, `banking`, `journal`, `chart`,
    /// `reports`, `ledger`, `close`, `taxes`, `settings`).
    static var sidebarItem: SidebarItem? {
        switch defaults.string(forKey: "qa.seccion") {
        case "home": .section(.home)
        case "invoices", "sales": .sales(.invoices)
        case "customers": .sales(.customers)
        case "estimates": .sales(.estimates)
        case "expenses": .expenses(.expenses)
        case "vendors": .expenses(.vendors)
        case "bills": .expenses(.bills)
        case "banking": .section(.banking)
        case "journal": .accounting(.journal)
        case "chart": .accounting(.chart)
        case "ledger": .accounting(.ledger)
        case "close": .accounting(.close)
        case "reports": .section(.reports)
        case "taxes": .section(.taxes)
        case "settings": .section(.settings)
        default: nil
        }
    }

    static var loadsSample: Bool { defaults.bool(forKey: "qa.muestra") }

    /// `-qa.apariencia oscuro` o `claro`: la apariencia de la ventana sin tocar la del sistema (en el Mac,
    /// `-AppleInterfaceStyle Dark` como argumento no la cambia).
    static var colorScheme: ColorScheme? {
        switch defaults.string(forKey: "qa.apariencia") {
        case "oscuro": .dark
        case "claro": .light
        default: nil
        }
    }

    /// Solo la primera vez: al volver a la página no se vuelve a elegir.
    @MainActor private static var appliedRow = false

    @MainActor
    static func applyRow(in ids: [UUID], selection: Binding<UUID?>, inspector: Binding<Bool>) {
        guard !appliedRow else { return }
        appliedRow = true
        if defaults.object(forKey: "qa.inspector") != nil { inspector.wrappedValue = defaults.bool(forKey: "qa.inspector") }
        if defaults.object(forKey: "qa.fila") != nil {
            let index = defaults.integer(forKey: "qa.fila")
            if ids.indices.contains(index) { selection.wrappedValue = ids[index] }
        }
    }
}
#endif
