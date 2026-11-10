import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Panel de clientes (plan para contadores)
//
// Canvas «Chirogra — Panel de clientes» (https://claude.ai/artifact/46eihuFoKbh8RrMEvHHNxA), encargo en
// docs/PANEL-CLIENTES.md. iPhone (`Main`): una tarjeta por cliente con su estado, sus pendientes (cada uno lleva a su
// pantalla) y cómo están sus libros; filtros con su número, orden en la barra y búsqueda abajo. iPad (`iPadPanel`) y Mac
// (`Panel`): tabla con columnas ordenables; en el Mac, además, inspector a la derecha y menú contextual.

/// Filtro del panel.
enum ClientFilter: String, CaseIterable, Identifiable {
    case all, attention, upToDate, archived
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "Todos")
        case .attention: String(localized: "Necesitan atención")
        case .upToDate: String(localized: "Al día")
        case .archived: String(localized: "Archivados")
        }
    }

    func matches(_ client: ClientSummary) -> Bool {
        switch self {
        case .all: !client.isArchived
        case .attention: client.needsAttention
        case .upToDate: client.status == .upToDate
        case .archived: client.isArchived
        }
    }
}

/// Orden del panel (menú de la barra; en la tabla, además, cada columna).
enum ClientSort: String, CaseIterable, Identifiable {
    case urgency, name, deadline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgency: String(localized: "Urgencia")
        case .name: String(localized: "Nombre")
        case .deadline: String(localized: "Próxima fecha límite")
        }
    }
}

struct ClientsView: View {
    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @Query private var companies: [Company]
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @State private var clients: [ClientSummary] = []
    @State private var loaded = false
    @State private var filter: ClientFilter = .all
    /// El orden elegido se conserva al salir y volver (QA del 10-nov).
    @AppStorage("clients.sort") private var sort: ClientSort = .urgency
    /// La tabla está ordenada por una columna que no es ninguno de los órdenes del menú.
    @State private var columnOrder = false
    /// Ancho del panel (iPad y Mac): si no caben todas las columnas, se quitan las menos importantes.
    @State private var width: CGFloat = .infinity
    @State private var query = ""
    @State private var selection: UUID?
    @State private var tableOrder = [KeyPathComparator(\ClientRow.urgency)]
    #if os(macOS)
    /// Mostrado u oculto, igual que en las demás tablas del Mac.
    @AppStorage("macInspectorShown") private var showsInspector = true
    #endif
    @State private var deleting: ClientSummary?
    @State private var backup: BackupDocument?
    @State private var backupName = ""
    @State private var errorMessage: String?
    @State private var reloadTask: Task<Void, Never>?
    @State private var monitor = SyncMonitor.shared
    private let router = ClientsRouter.shared
    private let store = SubscriptionStore.shared

    private var isTable: Bool {
        #if os(macOS)
        true
        #else
        // Con letra de accesibilidad, las tarjetas también en el iPad: en la tabla las columnas de cifras quedaban
        // ilegibles («Est…», «2 · $3,…», QA del 10-nov).
        sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var active: [ClientSummary] { clients.filter { !$0.isArchived } }
    private var needing: [ClientSummary] { active.filter(\.needsAttention) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canWrite: Bool { !store.isReadOnly }

    /// Lo que se ve: filtro, búsqueda y orden.
    private var shown: [ClientSummary] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let list = clients.filter { filter.matches($0) && (text.isEmpty || $0.name.localizedStandardContains(text)) }
        switch sort {
        case .urgency: return list.sorted { $0.urgencyKey < $1.urgencyKey }
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .deadline: return list.sorted { ($0.deadlineDays, $0.status, $0.name) < ($1.deadlineDays, $1.status, $1.name) }
        }
    }

    private var summary: String {
        if monitor.isSyncing && !loaded { return String(localized: "Sincronizando con iCloud…") }
        if active.count == 1 {
            return needing.isEmpty ? String(localized: "Tu cliente está al día") : String(localized: "Tu cliente necesita atención")
        }
        if needing.isEmpty { return String(localized: "Tus \(active.count) clientes están al día") }
        if needing.count == 1 { return String(localized: "1 de \(active.count) clientes necesita atención") }
        return String(localized: "\(needing.count) de \(active.count) clientes necesitan atención")
    }

    /// Ningún cliente necesita atención (y hay alguno): se dice arriba.
    private var showsAllGood: Bool { loaded && !active.isEmpty && needing.isEmpty && filter != .archived && !isSearching }
    /// Un solo cliente: invitación a añadir el siguiente.
    private var showsAddNext: Bool { loaded && active.count == 1 && canWrite && filter != .archived && !isSearching }

    var body: some View {
        Group {
            if isTable { tableBody } else { phoneBody }
        }
        .navigationTitle(AppSection.clients.title)
        .navigationSubtitle(summary)
        .searchable(text: $query, prompt: Text("Buscar cliente"))
        .toolbar { toolbar }
        .task(id: companies.map { "\($0.id)\($0.isArchived)\($0.sortOrder)" }) { reload() }
        .onAppear { if !columnOrder { setSort(sort) } }
        // Lo elegido que el filtro o la búsqueda esconden deja de estar elegido (el inspector lo seguía mostrando).
        .onChange(of: filter) { dropHiddenSelection() }
        .onChange(of: query) { dropHiddenSelection() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleReload() }
        .alert(deleting.map { String(localized: "¿Borrar «\($0.name)» y todos sus libros?") } ?? "",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { client in
            Button("Crear una copia antes…") { makeBackup(of: client) }
            Button("Borrar para siempre", role: .destructive) { delete(client) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text(deleteMessage)
        }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fileExporter(isPresented: Binding(get: { backup != nil }, set: { if !$0 { backup = nil } }),
                      document: backup, contentType: .chirograBackup,
                      defaultFilename: BackupArchive.suggestedFilename(companyName: backupName)) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }

    // MARK: Barra

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { sortMenu }
        if canWrite {
            ToolbarItem(placement: .primaryAction) {
                Button { addClient() } label: { Label("Añadir cliente", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            // Como en las demás tablas del Mac (`MacTablePage`).
            Button { showsInspector.toggle() } label: {
                Label(showsInspector ? "Ocultar inspector" : "Mostrar inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(showsInspector ? "Ocultar inspector (⌥⌘I)" : "Mostrar inspector (⌥⌘I)")
            .tint(showsInspector ? Palette.brand : Palette.ink)
        }
        #else
        ToolbarItem(placement: .primaryAction) { sortMenu }
        if canWrite {
            ToolbarItem(placement: .primaryAction) {
                Button { addClient() } label: { Label("Añadir cliente", systemImage: "plus") }
            }
        }
        #endif
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar por", selection: Binding(get: { sort }, set: { setSort($0) })) {
                ForEach(ClientSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            #if os(macOS)
            Text("Orden: \(columnOrder ? String(localized: "columna") : sort.title)")
            #else
            Label("Ordenar", systemImage: "arrow.up.arrow.down")
            #endif
        }
        .accessibilityLabel(Text("Ordenar por \(sort.title)"))
    }

    private var filterPicker: some View {
        Picker("Filtrar clientes", selection: $filter) {
            ForEach(ClientFilter.allCases) { option in
                Text(verbatim: "\(option.title) \(count(option))").tag(option)
            }
        }
        .labelsHidden()
    }

    /// Con texto en la búsqueda, los números de los filtros cuentan solo lo que coincide.
    private func count(_ option: ClientFilter) -> Int {
        let text = query.trimmingCharacters(in: .whitespaces)
        return clients.filter { option.matches($0) && (text.isEmpty || $0.name.localizedStandardContains(text)) }.count
    }

    private func setSort(_ value: ClientSort) {
        sort = value
        columnOrder = false
        switch value {
        case .urgency: tableOrder = [KeyPathComparator(\ClientRow.urgency)]
        case .name: tableOrder = [KeyPathComparator(\ClientRow.name, comparator: .localizedStandard)]
        case .deadline: tableOrder = [KeyPathComparator(\ClientRow.deadlineDays)]
        }
    }

    /// Orden por una columna de la tabla: el menú dice cuál si es uno de los suyos, y «columna» si no (QA del 10-nov:
    /// seguía diciendo «Urgencia»).
    private func columnSorted(_ order: [KeyPathComparator<ClientRow>]) {
        tableOrder = order
        let key = order.first?.keyPath
        if key == \ClientRow.urgency { sort = .urgency; columnOrder = false }
        else if key == \ClientRow.name { sort = .name; columnOrder = false }
        else if key == \ClientRow.deadlineDays { sort = .deadline; columnOrder = false }
        else { columnOrder = true }
    }

    // MARK: iPhone

    private var phoneBody: some View {
        List {
            Section {
                filterChips
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if showsAllGood {
                Section { allGoodNote }
                    .listRowBackground(Color.clear)
            }
            ForEach(shown) { client in
                Section { clientCard(client) }
            }
            if showsAddNext, let only = active.first {
                Section { addNextCard(name: only.name) }
            }
        }
        #if os(iOS)
        .listSectionSpacing(12)
        #endif
        .listRowBackground(Palette.surface)
        .screenBackground()
        .overlay { emptyState }
    }

    /// Filtros con su número (canvas: cápsulas; decisión del usuario del 10-nov: con cuatro filtros y sus números, un
    /// menú escondería justo lo útil).
    private var filterChips: some View {
        // El elegido siempre a la vista: «Archivados» quedaba fuera, en el borde (QA del 10-nov).
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ClientFilter.allCases) { option in
                    let isOn = filter == option
                    Button { filter = option } label: {
                        HStack(spacing: 6) {
                            Text(option.title).fontWeight(isOn ? .semibold : .regular)
                            Text(verbatim: "\(count(option))").foregroundStyle(isOn ? Palette.brand : Palette.ink2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(isOn ? Palette.brand : Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(isOn ? Palette.brandWash : Palette.surface2, in: Capsule())
                        .frame(minHeight: Metrics.target)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityLabel(Text(verbatim: "\(option.title), \(count(option))"))
                    .id(option)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onChange(of: filter) { _, option in withAnimation { proxy.scrollTo(option, anchor: .center) } }
        }
    }

    @ViewBuilder
    private func clientCard(_ client: ClientSummary) -> some View {
        HStack(spacing: 4) {
            Button { open(client) } label: {
                HStack(spacing: 12) {
                    CompanyMonogram(name: client.name, side: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name).font(.headline).foregroundStyle(Palette.ink)
                        HStack(spacing: 10) {
                            ClientStatusLabel(status: client.status)
                            Text(client.kindText).foregroundStyle(Palette.ink2)
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(client.isArchived)
            .accessibilityHint(client.isArchived ? Text("Archivado") : Text("Abre este cliente"))
            actionsMenu(client)
        }
        .padding(.vertical, 2)

        ForEach(client.pendingItems) { item in
            Button { router.open(client.id, route: item.route) } label: {
                HStack(spacing: 14) {
                    Image(systemName: item.systemImage)
                        .font(.title3)
                        .foregroundStyle(Palette.brand)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).foregroundStyle(Palette.ink)
                        Text(item.value).font(.subheadline).foregroundStyle(item.tone.color)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink2.opacity(0.6))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(client.isArchived)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(client.closedText) · \(client.lastActivityLine)")
            Text(verbatim: "\(String(localized: "Por cobrar \(client.receivables.moneyWhole)")) · \(String(localized: "Por pagar \(client.payables.moneyWhole)"))")
            if sort == .deadline, let tax = client.salesTax {
                Text("Próxima fecha límite: \(tax.deadline.dayMonth) · sales tax").foregroundStyle(Palette.ink)
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .padding(.vertical, 2)
    }

    private func actionsMenu(_ client: ClientSummary) -> some View {
        Menu { actions(client) } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Palette.brand)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Acciones de \(client.name)"))
    }

    private var allGoodNote: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Palette.green)
                .accessibilityHidden(true)
            Text("Todos tus clientes están al día").font(.title3.bold())
            Text("Nada vence en los próximos 7 días y no hay movimientos por revisar.")
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func addNextCard(name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2").font(.title2).foregroundStyle(Palette.brand).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("¿Llevas los libros de otro negocio?").font(.headline)
                    Text("Añádelo y lo verás aquí con lo que tiene pendiente, junto a \(name).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
            }
            Button { addClient() } label: {
                Label("Añadir cliente", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var emptyState: some View {
        if loaded && shown.isEmpty {
            if isSearching {
                ContentUnavailableView {
                    Label("Sin resultados para «\(query.trimmingCharacters(in: .whitespaces))»", systemImage: "magnifyingglass")
                } description: {
                    if filter == .archived {
                        Text("Ningún cliente archivado se llama así.")
                    } else {
                        Text("Ningún cliente se llama así. Revisa cómo está escrito o búscalo entre los archivados.")
                    }
                } actions: {
                    if filter == .archived {
                        Button { filter = .all } label: { Text("Buscar en todos").frame(minHeight: Metrics.target).contentShape(Rectangle()) }
                    } else {
                        Button { filter = .archived } label: { Text("Buscar en Archivados").frame(minHeight: Metrics.target).contentShape(Rectangle()) }
                    }
                }
            } else if filter == .archived {
                ContentUnavailableView("No hay clientes archivados", systemImage: "archivebox",
                                       description: Text("Los clientes que archives salen de la lista y del selector, pero sus libros se conservan."))
            } else if filter == .attention || filter == .upToDate {
                ContentUnavailableView("Nada que atender", systemImage: "checkmark.circle",
                                       description: Text("Ningún cliente tiene nada pendiente en este momento."))
            }
        }
    }

    // MARK: iPad y Mac

    private var rows: [ClientRow] {
        let list = shown.map(ClientRow.init)
        return list.sorted(using: tableOrder)
    }

    private var tableBody: some View {
        VStack(spacing: 0) {
            // Como en las demás tablas del Mac (`MacTablePage`): el filtro arriba del contenido, no en la barra.
            filterPicker
                .pickerStyle(.segmented)
                #if os(macOS)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
                .padding(.horizontal, Self.boxMargin)
                .padding(.vertical, 10)
            if showsAllGood {
                notice(icon: "checkmark.circle", color: Palette.green,
                       title: String(localized: "Todos tus clientes están al día"),
                       message: String(localized: "Nada vence en los próximos 7 días y no hay movimientos por revisar."))
            }
            table
            if showsAddNext, let only = active.first {
                addNextBar(name: only.name)
            }
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(macOS)
        .inspector(isPresented: $showsInspector) {
            ClientInspector(client: shown.first { $0.id == selection }, canWrite: canWrite,
                            actions: { AnyView(actions($0)) })
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        #endif
    }

    /// Columnas según el sitio (QA del 10-nov: en el Mac con el inspector y en el iPad vertical con la barra lateral no
    /// cabían): primero se quitan Avisos y Última actividad (Mac), luego Conciliado y Cerrado.
    private var showsAll: Bool { width >= 980 }
    private var showsBooks: Bool { width >= Self.booksMinWidth }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: Binding(get: { tableOrder }, set: { columnSorted($0) })) {
            // «Cliente» a secas es el de Ventas («Customer»): este es el del contador («Client»).
            TableColumn(Text(String(localized: "clients.column", defaultValue: "Cliente")), value: \.name, comparator: .localizedStandard) { row in
                HStack(spacing: 10) {
                    CompanyMonogram(name: row.client.name, side: Self.monogramSide)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.client.name).fontWeight(.semibold).lineLimit(1)
                        ClientCaption(text: row.client.kindText)
                    }
                }
                .padding(.vertical, Self.rowPadding)
            }
            .width(min: 170, ideal: 220)
            TableColumn("Estado", value: \.urgency) { row in
                ClientStatusLabel(status: row.client.status)
            }
            .width(min: Self.w.status.0, ideal: Self.w.status.1, max: Self.w.status.2)
            TableColumn(Self.bankTitle, value: \.bank) { row in
                ClientCell(text: row.client.bankToReview > 0 ? "\(row.client.bankToReview)" : "—")
            }
            .width(min: Self.w.bank.0, ideal: Self.w.bank.1, max: Self.w.bank.2)
            .alignment(.trailing)
            TableColumn("Vencidas", value: \.overdue) { row in
                ClientCell(text: row.client.overdueInvoices > 0
                           ? "\(row.client.overdueInvoices) · \(row.client.overdueAmount.moneyWhole)" : "—",
                           tone: row.client.overdueInvoices > 0 ? .warning : .plain)
            }
            .width(min: Self.w.overdue.0, ideal: Self.w.overdue.1, max: Self.w.overdue.2)
            .alignment(.trailing)
            #if os(macOS)
            if showsAll {
            TableColumn("Avisos", value: \.notices) { row in
                ClientCell(text: row.client.unreadNotices > 0 ? "\(row.client.unreadNotices)" : "—")
            }
            .width(min: 88, ideal: 96)
            .alignment(.trailing)
            }
            #endif
            TableColumn("Sales tax", value: \.deadlineDays) { row in
                ClientCell(text: row.client.salesTax.map { "\($0.amount.moneyWhole) · \($0.deadline.dayMonth)" } ?? "—",
                           tone: row.client.salesTaxIsUrgent ? .bad : .plain)
            }
            .width(min: Self.w.tax.0, ideal: Self.w.tax.1, max: Self.w.tax.2)
            .alignment(.trailing)
            if showsBooks {
            TableColumn(Self.reconciledTitle, value: \.reconciledDays) { row in
                ClientCell(text: row.client.reconciledColumn,
                           tone: row.client.reconciliationIsUrgent ? .bad : row.client.reconciliationIsLate ? .warning : .plain)
            }
            .width(min: Self.w.reconciled.0, ideal: Self.w.reconciled.1, max: Self.w.reconciled.2)
            .alignment(.trailing)
            TableColumn(Self.closedTitle, value: \.lockDate) { row in
                ClientCell(text: row.client.lockDate?.dayMonth ?? String(localized: "Sin cierre"))
            }
            .width(min: Self.w.closed.0, ideal: Self.w.closed.1, max: Self.w.closed.2)
            .alignment(.trailing)
            }
            #if os(macOS)
            if showsAll {
            TableColumn("Última actividad", value: \.lastActivity) { row in
                ClientCell(text: row.client.lastActivityText)
            }
            .width(min: 104, ideal: 108)
            .alignment(.trailing)
            }
            #endif
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let client = clients.first(where: { $0.id == id }) { actions(client) }
        } primaryAction: { ids in
            if let id = ids.first, let client = clients.first(where: { $0.id == id }) { open(client) }
        }
        .overlay { emptyState }
    }

    private func notice(icon: String, color: Color, title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Self.boxRadius, style: .continuous))
        .padding(.horizontal, Self.boxMargin)
        .padding(.bottom, 10)
    }

    private func addNextBar(name: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2").font(.title2).foregroundStyle(Palette.brand).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("¿Llevas los libros de otro negocio?").font(.headline)
                Text("Añádelo y lo verás en esta tabla con lo que tiene pendiente, junto a \(name).")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Button { addClient() } label: { Label("Añadir cliente", systemImage: "plus") }
                .buttonStyle(.glass)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Self.boxRadius, style: .continuous))
        .padding(Self.boxMargin)
    }

    // MARK: Acciones

    /// Menú de un cliente (canvas: «···» en el iPhone, menú contextual en la tabla).
    @ViewBuilder
    private func actions(_ client: ClientSummary) -> some View {
        if !client.isArchived {
            Button("Abrir", systemImage: "arrow.up.forward.app") { open(client) }
        }
        Section {
            if !client.isArchived {
                Button("Paquete para el contador…", systemImage: "doc.zipper") {
                    router.open(client.id, route: .accountantPackage)
                }
            }
            Button("Crear copia…", systemImage: "externaldrive.badge.plus") { makeBackup(of: client) }
            if canWrite && !client.isArchived {
                Button("Cerrar periodo…", systemImage: "lock") { router.open(client.id, route: .periodClose) }
            }
        }
        if canWrite {
            Section {
                if client.isArchived {
                    Button("Mostrar en el selector", systemImage: "tray.and.arrow.up") { setArchived(client, false) }
                } else if active.count > 1 {
                    Button("Archivar", systemImage: "archivebox") { setArchived(client, true) }
                }
                Button("Borrar…", systemImage: "trash", role: .destructive) { deleting = client }
            }
        }
    }

    private func dropHiddenSelection() {
        if let selection, !shown.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    private func open(_ client: ClientSummary) {
        guard !client.isArchived else { return }
        router.open(client.id)
    }

    private func addClient() {
        CompanyHub.shared.requestAdd(in: context)
    }

    private var deleteMessage: String {
        var text = String(localized: "Se borran sus clientes, proveedores, facturas, gastos, asientos, recibos y ajustes. No se puede deshacer.")
        if iCloudSyncEnabled { text += " " + String(localized: "También se borran en iCloud y en tus otros aparatos.") }
        text += " " + String(localized: "Si quieres conservarlos, crea antes una copia.")
        return text
    }

    private func company(_ client: ClientSummary) -> Company? { companies.first { $0.id == client.id } }

    private func setArchived(_ client: ClientSummary, _ archived: Bool) {
        guard let company = company(client) else { return }
        perform {
            let books = Bookkeeper(context: context)
            if archived { try books.archiveCompany(company) } else { try books.unarchiveCompany(company) }
        }
    }

    private func delete(_ client: ClientSummary) {
        guard let company = company(client) else { return }
        perform { try Bookkeeper(context: context).deleteCompany(company) }
    }

    private func makeBackup(of client: ClientSummary) {
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            backupName = client.name
            backup = BackupDocument(data: try BackupArchive.make(from: context, companyID: client.id, appVersion: version))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Datos

    private func reload() {
        clients = (try? Bookkeeper(context: context).clientSummaries()) ?? []
        loaded = true
        router.attentionCount = clients.filter(\.needsAttention).count
        if let selection, !clients.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    /// Tras cada guardado (de este aparato o de iCloud), una vez: los guardados llegan en ráfagas.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    /// Anchos de las columnas (mínimo, ideal, máximo). En el iPad la tabla reparte el sobrante por igual y cortaba el
    /// nombre: ahí las columnas de cifras van con ancho fijo y el resto es para «Cliente».
    private struct ColumnWidths {
        typealias W = (CGFloat, CGFloat, CGFloat)
        let status: W, bank: W, overdue: W, tax: W, reconciled: W, closed: W
    }

    #if os(macOS)
    private static let w = ColumnWidths(status: (80, 92, 130), bank: (52, 70, 130), overdue: (72, 96, 140),
                                        tax: (124, 128, 170), reconciled: (70, 84, 130), closed: (70, 80, 120))
    private static let monogramSide: CGFloat = 26
    private static let booksMinWidth: CGFloat = 700
    private static let rowPadding: CGFloat = 4
    private static let boxRadius: CGFloat = 8
    private static let boxMargin: CGFloat = 16
    private static let bankTitle = String(localized: "Banco")
    private static let reconciledTitle = String(localized: "Conciliado")
    private static let closedTitle = String(localized: "Cerrado")
    #else
    private static let w = ColumnWidths(status: (104, 104, 104), bank: (64, 64, 64), overdue: (116, 116, 116),
                                        tax: (136, 136, 136), reconciled: (104, 104, 104), closed: (92, 92, 92))
    private static let monogramSide: CGFloat = 36
    private static let booksMinWidth: CGFloat = 840
    private static let rowPadding: CGFloat = 6
    private static let boxRadius: CGFloat = 20
    private static let boxMargin: CGFloat = 20
    private static let bankTitle = String(localized: "Banco")
    private static let reconciledTitle = String(localized: "Conciliado")
    private static let closedTitle = String(localized: "Cerrado")
    #endif
}

// MARK: - Piezas

/// Estado con su punto de color y la palabra (sin cápsula: el color nunca va solo). En la fila elegida de la tabla
/// (relleno de Tinta), en blanco: los colores fijos no cambian solos y el rojo sobre Tinta no se leía.
struct ClientStatusLabel: View {
    let status: ClientSummary.Status
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let selected = prominence == .increased
        HStack(spacing: 6) {
            Circle().fill(selected ? Color.white : status.dotColor).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(status.title).fontWeight(.semibold).foregroundStyle(selected ? Color.white : status.textColor)
        }
        .lineLimit(1)
    }
}

/// Celda de la tabla con el tono de su dato, en blanco sobre la fila elegida (como `MacCellText`).
private struct ClientCell: View {
    let text: String
    var tone: ClientTone = .plain
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(verbatim: text)
            .fontWeight(tone == .plain ? .regular : .semibold)
            .foregroundStyle(prominence == .increased ? Color.white : text == "—" ? Palette.ink2 : tone.color)
            .lineLimit(1)
            .monospacedDigit()
    }
}

/// Segunda línea de la columna Cliente («LLC · Texas»), en blanco sobre la fila elegida.
private struct ClientCaption: View {
    let text: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(text).font(.caption).foregroundStyle(prominence == .increased ? Color.white : Palette.ink2).lineLimit(1)
    }
}

enum ClientTone {
    case plain, warning, bad, secondary

    var color: Color {
        switch self {
        case .plain: Palette.ink
        case .warning: Palette.warning
        case .bad: Palette.negative
        case .secondary: Palette.ink2
        }
    }
}

/// Un pendiente de la tarjeta (y del inspector), con la pantalla a la que lleva.
struct ClientPendingItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let tone: ClientTone
    let route: ClientRoute
}

/// Fila de la tabla: el resumen con claves que se pueden ordenar.
nonisolated struct ClientRow: Identifiable, Sendable {
    let client: ClientSummary
    var id: UUID { client.id }
    var name: String { client.name }
    var urgency: ClientSummary.UrgencyKey { client.urgencyKey }
    var bank: Int { client.bankToReview }
    var overdue: Int64 { client.overdueAmount }
    var notices: Int { client.unreadNotices }
    var deadlineDays: Int { client.deadlineDays }
    var reconciledDays: Int { client.reconciliation?.days ?? -1 }
    var lockDate: Date { client.lockDate ?? .distantPast }
    var lastActivity: Date { client.lastActivity ?? .distantPast }
}

extension ClientSummary {
    /// Orden de urgencia: estado, luego la fecha límite más próxima y el nombre.
    nonisolated struct UrgencyKey: Comparable, Sendable {
        let status: Int
        let days: Int
        let name: String
        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.status, lhs.days, lhs.name.lowercased()) < (rhs.status, rhs.days, rhs.name.lowercased())
        }
    }

    nonisolated var urgencyKey: UrgencyKey { UrgencyKey(status: status.rawValue, days: deadlineDays, name: name) }
    nonisolated var deadlineDays: Int { salesTax?.days ?? Int.max }

    /// «LLC · Texas».
    var kindText: String {
        let state = StateSalesTax.forState(state)?.name ?? state
        return [entityType.shortTitle, state].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var closedText: String {
        lockDate.map { String(localized: "Cerrado hasta \($0.dayMonth)") } ?? String(localized: "Sin cierre")
    }

    /// «Hoy», «Ayer», «Hace 12 días».
    var lastActivityText: String {
        guard let lastActivity else { return "—" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastActivity), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case ...0: return String(localized: "Hoy")
        case 1: return String(localized: "Ayer")
        default: return String(localized: "Hace \(days) días")
        }
    }

    var lastActivityLine: String {
        lastActivity == nil ? String(localized: "Sin movimientos")
            : String(localized: "Último movimiento: \(lastActivityText.lowercased())")
    }

    var reconciledColumn: String {
        guard let reconciliation else { return "—" }
        // Corto en la columna («Sin conciliar» y «Not reconciled» se cortaban); la tarjeta y el inspector lo dicen entero.
        return reconciliation.reconciledThrough?.dayMonth ?? String(localized: "Nunca")
    }

    var salesTaxText: String? {
        guard let salesTax else { return nil }
        let amount = salesTax.amount.moneyWhole
        switch salesTax.days {
        case ..<(-1): return String(localized: "\(amount) · vencido hace \(-salesTax.days) días")
        case -1: return String(localized: "\(amount) · vencido ayer")
        case 0: return String(localized: "\(amount) · vence hoy")
        default: return String(localized: "\(amount) · vence el \(salesTax.deadline.dayMonth)")
        }
    }

    /// Los pendientes de la tarjeta, en el orden del canvas: sales tax, conciliación, banco, facturas vencidas y avisos.
    var pendingItems: [ClientPendingItem] {
        var items: [ClientPendingItem] = []
        if salesTaxIsUrgent, let text = salesTaxText {
            items.append(.init(id: "tax", title: String(localized: "Sales tax"), value: text, systemImage: "percent",
                               tone: .bad, route: .salesTax))
        }
        if reconciliationIsLate, let reconciliation {
            let value = reconciliation.reconciledThrough.map { String(localized: "\(reconciliation.accountName): conciliada hasta \($0.dayMonth)") }
                ?? String(localized: "\(reconciliation.accountName): sin conciliar")
            items.append(.init(id: "reconcile", title: String(localized: "Conciliación"), value: value,
                               systemImage: "checkmark.circle", tone: reconciliationIsUrgent ? .bad : .warning,
                               route: .reconcile(reconciliation.accountID)))
        }
        if bankToReview > 0 {
            items.append(.init(id: "bank", title: String(localized: "Banco"), value: String(localized: "\(bankToReview) por revisar"),
                               systemImage: "building.columns", tone: .secondary, route: .bankInbox))
        }
        if overdueInvoices > 0 {
            items.append(.init(id: "invoices", title: String(localized: "Facturas vencidas"),
                               value: "\(overdueInvoices == 1 ? String(localized: "1 vencida") : String(localized: "\(overdueInvoices) vencidas")) · \(overdueAmount.moneyWhole)",
                               systemImage: "doc.text", tone: .warning, route: .overdueInvoices))
        }
        if unreadNotices > 0 {
            items.append(.init(id: "notices", title: String(localized: "Avisos"), value: unreadNotices == 1 ? String(localized: "1 aviso sin leer") : String(localized: "\(unreadNotices) avisos sin leer"),
                               systemImage: "bell", tone: .secondary, route: .notices))
        }
        return items
    }
}

extension ClientSummary.Status {
    var title: String {
        switch self {
        case .urgent: String(localized: "Urgente")
        case .pending: String(localized: "Pendiente")
        case .upToDate: String(localized: "Al día")
        case .archived: String(localized: "Archivado")
        }
    }

    var textColor: Color {
        switch self {
        case .urgent: Palette.negative
        case .pending: Palette.warning
        case .upToDate: Palette.positive
        case .archived: Palette.ink2
        }
    }

    var dotColor: Color {
        switch self {
        case .urgent: Palette.red
        case .pending: Palette.orange
        case .upToDate: Palette.green
        case .archived: Palette.gray
        }
    }
}

extension EntityType {
    /// Nombre corto para la fila del panel («Negocio propio», «LLC», «S corporation»).
    var shortTitle: String {
        switch self {
        case .soleProprietorship: String(localized: "Negocio propio")
        case .llc: String(localized: "LLC")
        case .sCorp: String(localized: "S corporation")
        case .cCorp: String(localized: "C corporation")
        case .partnership: String(localized: "Sociedad")
        }
    }
}

// MARK: - Inspector del Mac

#if os(macOS)
/// Inspector de la tabla (canvas `MacMenu`): el cliente elegido, sus pendientes, cómo están sus libros y las acciones.
private struct ClientInspector: View {
    let client: ClientSummary?
    let canWrite: Bool
    let actions: (ClientSummary) -> AnyView
    private let router = ClientsRouter.shared

    var body: some View {
        if let client {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CompanyMonogram(name: client.name, side: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.name).font(.headline)
                            Text(client.kindText).font(.caption).foregroundStyle(Palette.ink2)
                            ClientStatusLabel(status: client.status).font(.caption)
                        }
                    }
                }
                Section("Pendientes") {
                    if client.pendingItems.isEmpty {
                        Text("Nada pendiente.").foregroundStyle(Palette.ink2)
                    }
                    ForEach(client.pendingItems) { item in
                        Button { router.open(client.id, route: item.route) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.systemImage).foregroundStyle(Palette.brand).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                    Text(item.value).font(.caption).foregroundStyle(item.tone.color)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.ink2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(client.isArchived)
                    }
                }
                Section("Libros") {
                    LabeledContent("Cerrado hasta", value: client.lockDate?.dayMonth ?? String(localized: "Sin cierre"))
                    LabeledContent("Último movimiento", value: client.lastActivityText)
                    LabeledContent("Por cobrar", value: client.receivables.moneyWhole)
                    LabeledContent("Por pagar", value: client.payables.moneyWhole)
                    LabeledContent("Próxima fecha límite",
                                   value: client.salesTax.map { "\($0.deadline.dayMonth) · sales tax" } ?? "—")
                }
                Section {
                    if !client.isArchived {
                        Button("Abrir cliente") { router.open(client.id) }
                            .buttonStyle(.glassProminent)
                            .frame(maxWidth: .infinity)
                    }
                    Menu("Más acciones") { actions(client) }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Sin selección", systemImage: "building.2",
                                   description: Text("Elige un cliente para ver lo que tiene pendiente."))
        }
    }
}
#endif
