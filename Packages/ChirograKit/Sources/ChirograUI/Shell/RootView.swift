import ChirograCore
import ChirograData
import LocalAuthentication
import SwiftData
import SwiftUI

/// Secciones de navegación del canvas (DISEÑO §7.1).
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case home, sales, expenses, banking, reports, accounting, taxes, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Inicio")
        case .sales: String(localized: "Ventas")
        case .expenses: String(localized: "Gastos")
        case .banking: String(localized: "Banca")
        case .reports: String(localized: "Reportes")
        case .accounting: String(localized: "Contabilidad")
        case .taxes: String(localized: "Impuestos")
        case .settings: String(localized: "Ajustes")
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .sales: "doc.text"
        case .expenses: "wallet.bifold"
        case .banking: "building.columns"
        case .reports: "chart.bar"
        case .accounting: "book.closed"
        case .taxes: "receipt"
        case .settings: "gearshape"
        }
    }

    static let primary: [AppSection] = [.home, .sales, .expenses, .banking, .reports]
    /// iPhone muestra como máximo 5 pestañas sin que el sistema agrupe el resto en su propio "Más".
    /// Banca (casi todo de fase 2) vive dentro de "Más" hasta que llegue la bandeja de movimientos.
    static let phoneTabs: [AppSection] = [.home, .sales, .expenses, .reports]
    static let more: [AppSection] = [.accounting, .taxes, .settings]

    @ViewBuilder
    var destination: some View {
        switch self {
        case .home: HomeView()
        case .sales: SalesView()
        case .expenses: ExpensesView()
        case .banking: BankingView()
        case .reports: ReportsView()
        case .accounting: AccountingView()
        case .taxes: TaxesView()
        case .settings: SettingsView()
        }
    }
}

/// Raíz de la app: alta de empresa la primera vez, bloqueo opcional con Face ID y navegación principal.
public struct ChirograRootView: View {
    @Query private var companies: [Company]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var lock = AppLockState()
    @State private var sync = SyncMonitor.shared
    /// «Crear una empresa nueva» desde la pantalla de sincronización.
    @State private var skipsSyncWait = false
    #if os(iOS)
    @State private var lockWindow = LockWindow()
    #endif

    public init() {}

    private var isLocked: Bool { appLockEnabled && !lock.isUnlocked && !companies.isEmpty }

    public var body: some View {
        Group {
            // Con iCloud, en un dispositivo nuevo los libros tardan en llegar: no se pide crear la empresa
            // mientras se importan (`MacCargando`).
            if sync.isSyncing && !skipsSyncWait && companies.isEmpty {
                SyncLoadingView { skipsSyncWait = true }
            } else if companies.isEmpty {
                OnboardingView()
            } else {
                #if os(iOS)
                // La app sigue montada debajo de la ventana de bloqueo: al desbloquear, todo está donde estaba.
                AppShell()
                #else
                if isLocked { LockView(lock: lock) } else { AppShell() }
                #endif
            }
        }
        .tint(Palette.brand)
        .background(Palette.background)
        .monitorsCloudSync()
        // Fechas y selectores de fecha en el idioma de la app, con el orden de su región (B3). En el Mac los
        // selectores son campos en cifras: con el locale de los textos (es_419) salían en día/mes en EE. UU.
        #if os(macOS)
        .environment(\.locale, .app)
        #else
        .environment(\.locale, .appText)
        #endif
        #if os(iOS)
        // Valores de las filas en `ink`, como en el canvas. En el Mac los formularios usan este estilo también
        // para sus controles, así que allí se deja el del sistema.
        .labeledContentStyle(InkValueLabeledContentStyle())
        .background(WindowSceneReader { lockWindow.scene = $0 })
        .onChange(of: isLocked, initial: true) { _, locked in lockWindow.update(isLocked: locked, lock: lock) }
        #endif
        .onChange(of: scenePhase, initial: true) { _, phase in
            lock.isActive = phase == .active
            // Al pasar a segundo plano se vuelve a bloquear; al volver se pide Face ID otra vez.
            if phase == .background { lock.isUnlocked = false }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            // Quien activa el bloqueo ya está dentro: se bloquea la próxima vez que la app pase a segundo plano.
            if enabled { lock.isUnlocked = true }
        }
    }
}

/// Estado del bloqueo de una escena, compartido entre la raíz y la pantalla de bloqueo.
@Observable
final class AppLockState {
    var isUnlocked = false
    /// Face ID solo se puede pedir con la escena activa: en segundo plano el sistema lo cancela al instante.
    var isActive = false
}

#if os(iOS)
/// Ventana por encima de todo (hojas y alertas incluidas) que tapa la app mientras está bloqueada,
/// también en la captura del selector de apps. Al quitarla, la app sigue en la misma pestaña y pantalla.
final class LockWindow {
    var scene: UIWindowScene? { didSet { refresh() } }
    private var lock: AppLockState?
    private var isLocked = false
    private var window: UIWindow?

    func update(isLocked: Bool, lock: AppLockState) {
        self.isLocked = isLocked
        self.lock = lock
        refresh()
    }

    private func refresh() {
        if isLocked, window == nil, let scene, let lock {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: LockView(lock: lock).tint(Palette.brand))
            window.makeKeyAndVisible()
            self.window = window
        } else if !isLocked, let window {
            window.isHidden = true
            self.window = nil
            scene?.windows.first { $0.windowLevel == .normal }?.makeKey()
        }
    }
}

/// Lee la `UIWindowScene` en la que vive la vista (en iPad puede haber varias ventanas de la app).
private struct WindowSceneReader: UIViewRepresentable {
    let onChange: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> SceneView {
        let view = SceneView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SceneView, context: Context) {}

    final class SceneView: UIView {
        var onChange: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window?.windowScene)
        }
    }
}
#endif

/// Bloqueo de la app con Face ID / Touch ID o, si no hay biometría, con el código del dispositivo.
enum AppLock {
    /// `true` si el dispositivo puede autenticar (biometría o código). Sin código configurado no se puede
    /// bloquear la app: el usuario quedaría fuera.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

struct AppShell: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Ancho de la columna de detalle: en un iPad vertical con la barra lateral abierta puede quedar estrecha.
    @State private var detailWidth: CGFloat = .infinity
    #endif
    @State private var tab: AppSection = .home
    @State private var selection: SidebarItem = .section(.home)
    @State private var query = ""
    /// Cambios sin guardar del editor de la columna de detalle: antes de cambiar de pantalla se pregunta.
    @State private var unsavedChanges = UnsavedChanges()
    @State private var pendingSelection: SidebarItem?
    /// Se guarda aquí para que la barra lateral siga abierta o cerrada al rehacer la vista dividida.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact { tabs } else { split }
        #else
        split
        #endif
    }

    #if os(iOS)
    private var isDetailNarrow: Bool { detailWidth < (dynamicTypeSize.isAccessibilitySize ? 960 : 760) }
    #endif

    /// Con un editor con cambios abierto, la barra lateral pregunta antes de cambiar de pantalla (como «Cancelar»).
    /// Si hay un aviso de «Cancelar» abierto o cerrándose, se espera a que su acción termine antes de decidir: en el iPad
    /// el toque en la barra llegaba antes que «Descartar», y se preguntaba sin ningún editor a la vista.
    private var sidebarSelection: Binding<SidebarItem> {
        Binding(get: { selection }, set: { item in
            guard item != selection else { return }
            Task { @MainActor in
                while unsavedChanges.hasChanges && unsavedChanges.isSettling() {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard item != selection else { return }
                if unsavedChanges.hasChanges { pendingSelection = item } else { selection = item }
            }
        })
    }

    /// iPhone: 5 pestañas (Inicio · Ventas · Gastos · Reportes · Más).
    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(AppSection.phoneTabs) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    NavigationStack {
                        // Dentro de la pila, debajo de la barra de navegación: fuera de ella tapaba el título.
                        SyncAwareContent(title: section.title) { section.destination }
                            .safeAreaInset(edge: .top, spacing: 0) { SyncErrorBanner() }
                    }
                }
            }
            Tab("Más", systemImage: "ellipsis.circle", value: AppSection.settings) {
                NavigationStack { MoreView().safeAreaInset(edge: .top, spacing: 0) { SyncErrorBanner() } }
            }
        }
    }

    /// iPad y Mac: barra lateral propia (`Sidebar`); con texto en la búsqueda, el detalle muestra los resultados.
    private var split: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(selection: sidebarSelection, query: $query)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                #if os(iOS)
                .toolbar(removing: .title)
                #endif
        } detail: {
            NavigationStack {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SyncAwareContent(title: selection.section.title) { selection.destination }
                } else {
                    SearchResultsView(query: query)
                }
            }
            #if os(iOS)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            #endif
            .safeAreaInset(edge: .top, spacing: 0) { SyncErrorBanner() }
        }
        #if os(iOS)
        // Si la columna de detalle queda estrecha, sus pantallas usan el diseño de iPhone: las tablas de Gastos y la
        // vista dividida de Ventas no caben (iPad vertical con la barra abierta: 712 pt en el de 13", y con texto
        // grande se cortaba también Ventas). En la vista dividida y no en la pila: las pantallas que se abren encima
        // toman el entorno de aquí.
        .environment(\.isNarrowColumn, isDetailNarrow)
        #endif
        .environment(\.unsavedChanges, unsavedChanges)
        // Al cambiar de pantalla se rehace la vista dividida: los editores de la columna ya no existen.
        .onChange(of: selection) { unsavedChanges.removeAll() }
        .alert("¿Descartar los cambios?", isPresented: Binding(get: { pendingSelection != nil }, set: { if !$0 { pendingSelection = nil } })) {
            Button("Descartar", role: .destructive) {
                unsavedChanges.discardAll()
                if let pendingSelection { selection = pendingSelection }
                pendingSelection = nil
            }
            Button("Seguir editando", role: .cancel) { pendingSelection = nil }
        } message: {
            Text("Si cambias de pantalla se pierde lo que escribiste.")
        }
        // Al elegir otro elemento de la barra lateral se rehace la vista dividida entera: las pantallas abiertas con
        // `NavigationLink(destination:)` quedan en la pila propia de la columna de detalle, que no se vacía al
        // cambiar la raíz ni con `.id` en el `NavigationStack` interior.
        .id(selection)
    }
}

#if os(iOS)
extension EnvironmentValues {
    /// La columna de detalle del iPad es estrecha (vertical con la barra lateral abierta): sus pantallas usan el
    /// diseño de iPhone. Llega también a las que se abren encima, que toman el `horizontalSizeClass` de la columna.
    @Entry var isNarrowColumn = false
}

/// Tamaño horizontal para elegir el diseño: el del sistema, o compacto si la columna es estrecha.
@propertyWrapper
struct LayoutSizeClass: DynamicProperty {
    @Environment(\.horizontalSizeClass) private var system
    @Environment(\.isNarrowColumn) private var isNarrowColumn

    var wrappedValue: UserInterfaceSizeClass? { isNarrowColumn ? .compact : system }
}
#endif

/// Pestaña "Más" del iPhone: Contabilidad, Impuestos y Ajustes.
struct MoreView: View {
    @Query private var companies: [Company]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var entries: [JournalEntry]
    @Query private var rates: [TaxRate]
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let company = companies.first { companyCard(company) }

                section(String(localized: "Banca"))
                MoreTile(title: String(localized: "Cuentas y saldos"), subtitle: String(localized: "\(bankCount) cuentas"),
                         systemImage: "building.columns") { BankingView() }

                section(String(localized: "Contabilidad"))
                LazyVGrid(columns: columns, spacing: 8) {
                    MoreTile(title: String(localized: "Plan de cuentas"), subtitle: String(localized: "\(accounts.filter { !$0.isArchived }.count) cuentas"),
                             systemImage: "list.bullet.indent") { ChartOfAccountsView() }
                    MoreTile(title: String(localized: "Asientos de diario"), subtitle: String(localized: "\(entriesThisMonth) este mes"),
                             systemImage: "doc.plaintext") { JournalListView() }
                    MoreTile(title: String(localized: "Libro mayor"), subtitle: String(localized: "Por cuenta"),
                             systemImage: "book.closed") { LedgerAccountPickerView() }
                    MoreTile(title: String(localized: "Cierre de periodo"), subtitle: closeSubtitle,
                             systemImage: "lock") { PeriodCloseView() }
                }

                section(String(localized: "Impuestos"))
                LazyVGrid(columns: columns, spacing: 8) {
                    MoreTile(title: String(localized: "Resumen"), subtitle: taxSubtitle, subtitleColor: taxOwed > 0 ? Palette.warning : Palette.ink3,
                             systemImage: "percent") { TaxesView() }
                    MoreTile(title: String(localized: "Tasas"), subtitle: String(localized: "\(rates.count) activas"),
                             systemImage: "list.number") { TaxesView(tab: .rates) }
                }

                section(String(localized: "Ajustes"))
                VStack(spacing: 0) {
                    if let company = companies.first {
                        settingsRow(String(localized: "Perfil de la empresa"), "building.2", value: nil) { CompanyProfileView(company: company) }
                        Divider().padding(.leading, 52)
                        settingsRow(String(localized: "Moneda y formatos"), "dollarsign.circle", value: company.currencyCode) { FormatsView(company: company) }
                        Divider().padding(.leading, 52)
                    }
                    settingsRow(String(localized: "iCloud y copias"), "icloud",
                                value: iCloudSyncEnabled ? String(localized: "Activado") : String(localized: "Desactivado")) { DataAndSecurityView() }
                    Divider().padding(.leading, 52)
                    settingsRow(String(localized: "Seguridad"), "faceid",
                                value: appLockEnabled ? String(localized: "Face ID") : String(localized: "Desactivado")) { DataAndSecurityView() }
                }
                .padding(.horizontal, 12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Más")
    }

    private var bankCount: Int { accounts.filter { !$0.isArchived && ($0.subtype == .bank || $0.subtype == .creditCard) }.count }

    private var entriesThisMonth: Int {
        let month = DateInterval.month(containing: .now)
        return entries.filter { month.contains($0.date) }.count
    }

    private var closeSubtitle: String {
        companies.first?.lockDate.map { String(localized: "Cerrado hasta \($0.dayMonth)") } ?? String(localized: "Sin cerrar")
    }

    private var taxOwed: Int64 {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        return accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
    }

    private var taxSubtitle: String {
        taxOwed > 0 ? String(localized: "\(taxOwed.money) por pagar") : String(localized: "Al día")
    }

    private func section(_ title: String) -> some View {
        SectionLabel(text: title).padding(.top, 4).accessibilityAddTraits(.isHeader)
    }

    private func companyCard(_ company: Company) -> some View {
        NavigationLink { CompanyProfileView(company: company) } label: {
            HStack(spacing: 12) {
                Text(Initials.from(company.displayName))
                    .font(.headline.weight(.bold)).foregroundStyle(Palette.background)
                    .frame(width: 44, height: 44)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(company.displayName).font(.headline).foregroundStyle(Palette.ink)
                    Text(company.legalName).font(.footnote).foregroundStyle(Palette.ink3)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsRow<Destination: View>(_ title: String, _ image: String, value: String?,
                                                 @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: image).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(width: 30, height: 30)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 8)
                if let value { Text(value).font(.subheadline).foregroundStyle(Palette.ink3).lineLimit(1) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tarjeta de «Más» (canvas `Mas`): icono, título y subtítulo con un dato.
struct MoreTile<Destination: View>: View {
    let title: String
    let subtitle: String
    var subtitleColor: Color = Palette.ink3
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Palette.brand)
                    .frame(height: 26, alignment: .leading).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                Text(subtitle).font(.caption.weight(.semibold)).foregroundStyle(subtitleColor).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LockView: View {
    let lock: AppLockState
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var failed = false
    @State private var isEvaluating = false
    /// Face ID se pide solo una vez por sí solo; si el usuario cancela, queda el botón «Desbloquear».
    @State private var didPromptAutomatically = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 20) {
            LogoMark(size: 64)
            Text("Chirogra está bloqueada").font(.title2.weight(.semibold))
            if failed { Text("No se pudo verificar tu identidad.").foregroundStyle(Palette.negative) }
            // Con texto grande el botón ocupa todo el ancho: a 280 pt «Desbloquear» se partía en dos líneas.
            Button(action: unlock) {
                Text("Desbloquear").lineLimit(1).minimumScaleFactor(0.7)
            }
            .buttonStyle(.primary)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 280)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onChange(of: lock.isActive, initial: true) { _, active in
            guard active, !didPromptAutomatically else { return }
            didPromptAutomatically = true
            unlock()
        }
    }

    private func unlock() {
        guard !isEvaluating, !lock.isUnlocked else { return }
        guard AppLock.isAvailable else {
            // El dispositivo ya no tiene código ni biometría: desactivar el bloqueo antes que dejar fuera al usuario.
            appLockEnabled = false
            lock.isUnlocked = true
            return
        }
        isEvaluating = true
        failed = false
        Task {
            do {
                lock.isUnlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                                                                       localizedReason: String(localized: "Desbloquear tus libros"))
            } catch {
                failed = Self.isFailure(error)
            }
            isEvaluating = false
        }
    }

    /// Solo un fallo real se muestra en rojo: cancelar, o que el sistema interrumpa (app en segundo plano,
    /// llamada entrante), no es un error de identidad.
    nonisolated static func isFailure(_ error: any Error) -> Bool {
        guard let code = (error as? LAError)?.code else { return true }
        return ![.userCancel, .appCancel, .systemCancel, .notInteractive].contains(code)
    }
}
