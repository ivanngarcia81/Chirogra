import ChirograCore
import ChirograData
import LocalAuthentication
import SwiftData
import SwiftUI
import TipKit

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

    /// Grupo «Negocio» de la barra lateral (canvas `Sidebar`).
    static let business: [AppSection] = [.home, .sales, .expenses, .banking, .reports]
    /// Grupo «Libros» de la barra lateral.
    static let books: [AppSection] = [.accounting, .taxes, .settings]
    /// Pestañas del iPhone como el canvas (decisión del usuario del 2-nov): Inicio · Ventas · Gastos · Banca, y «Más»
    /// con Reportes, Contabilidad, Impuestos y Ajustes. Cinco como máximo, para que el sistema no agrupe el resto.
    static let phoneTabs: [AppSection] = [.home, .sales, .expenses, .banking]

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
    /// Todas las empresas (también las archivadas): la raíz decide entre el alta y la app, y calcula la activa.
    @Query private var companies: [Company]
    /// Empresa activa de este aparato (`ActiveCompany`): al cambiarla, la app se rehace con la nueva.
    @AppStorage(ActiveCompany.defaultsKey) private var activeCompanyID: String?
    @State private var companyHub = CompanyHub.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var lock = AppLockState()
    @State private var sync = SyncMonitor.shared
    @State private var replacement = BooksReplacement.shared
    @State private var subscription = SubscriptionStore.shared
    /// La pantalla de suscripción ya salió sola en esta sesión (después solo con «Suscribirme» o al intentar registrar).
    @State private var paywallShownOnce = false
    /// «Crear una empresa nueva» desde la pantalla de sincronización.
    @State private var skipsSyncWait = false
    /// La bienvenida (`WelcomeView`) ya se pasó en este aparato: sin empresas (p. ej. tras «Empezar con mi empresa»), se
    /// va directo al alta.
    @AppStorage(WelcomeView.seenKey) private var welcomeSeen = false
    /// Página con que abre la bienvenida: la última al volver con «Atrás» desde el paso 1 del alta.
    @State private var welcomeStartPage = 0
    #if os(iOS)
    @State private var lockWindow = LockWindow()
    #endif

    public init() {
        // Lo que una pantalla inserta sin empresa toma la activa al guardar (`CompanyStamp`).
        CompanyStamp.install()
        #if DEBUG
        _welcomeStartPage = State(initialValue: Self.applyQAWelcome())
        #endif
    }

    /// Ámbito de la empresa activa (`Bookkeeper.companyScope()`), que se deja en `CompanySession` antes de dibujar la
    /// app: las `@CompanyQuery` de todas las pantallas lo leen al crearse. Depende de `companies` y `activeCompanyID`,
    /// así que se recalcula al cambiar de empresa, al crear o borrar una y al llegar otra por iCloud.
    private var companyScope: CompanyScope? {
        _ = activeCompanyID
        _ = companies.count
        let scope = (try? Bookkeeper(context: modelContext).companyScope()) ?? nil
        CompanySession.scope = scope
        return scope
    }

    #if DEBUG
    private static var qaLoadedSample = false
    private static var qaAppliedWelcome = false

    /// `-qa.bienvenida N` abre la bienvenida en la página N (desde 1) aunque ya se hubiera visto; `-qa.muestra` y
    /// `-qa.alta` la saltan, para que sus capturas sigan llegando a los libros de ejemplo y al alta. Devuelve la página.
    private static func applyQAWelcome() -> Int {
        let defaults = UserDefaults.standard
        guard !qaAppliedWelcome else { return 0 }
        qaAppliedWelcome = true
        if defaults.object(forKey: "qa.bienvenida") != nil {
            defaults.set(false, forKey: WelcomeView.seenKey)
            return max(defaults.integer(forKey: "qa.bienvenida") - 1, 0)
        }
        if QALaunch.loadsSample || defaults.object(forKey: "qa.alta") != nil {
            defaults.set(true, forKey: WelcomeView.seenKey)
        }
        return 0
    }
    private static var qaAppliedCompanies = false

    /// Argumentos de QA de varias empresas (solo Debug, REDISEÑO-NATIVO §5), una vez por sesión y cuando ya hay
    /// empresa: `-qa.segundaEmpresa <nombre>` da de alta otra empresa vacía con ese nombre (si no existe; dentro del
    /// límite del plan, p. ej. con `-qa.suscripcion contador`), que queda activa; `-qa.empresa N` deja activa la N.ª del
    /// selector (desde 1); `-qa.empresas lista|alta` abre la lista de empresas o «Añadir empresa…».
    private func applyQACompanies() {
        let defaults = UserDefaults.standard
        guard !Self.qaAppliedCompanies, !companies.isEmpty else { return }
        Self.qaAppliedCompanies = true
        let books = Bookkeeper(context: modelContext, actor: "QA")
        if let name = defaults.string(forKey: "qa.segundaEmpresa"), !companies.contains(where: { $0.displayName == name }) {
            do {
                let created = try books.forNewCompany()
                try created.setUpCompany(legalName: "\(name) LLC", displayName: name, entityType: .llc, state: "TX")
                _ = try created.setUpSalesTax(totalMillionths: nil, localName: "")
            } catch {
                NSLog("Chirogra QA segundaEmpresa: %@", "\(error)")
            }
        }
        let index = defaults.integer(forKey: "qa.empresa")
        if index > 0, let list = try? books.companies(), list.indices.contains(index - 1) {
            ActiveCompany.id = list[index - 1].id
        }
        switch defaults.string(forKey: "qa.empresas") {
        case "lista": companyHub.sheet = .list
        case "alta": companyHub.requestAdd(in: modelContext)
        default: break
        }
    }
    #endif

    private var isLocked: Bool { appLockEnabled && !lock.isUnlocked && !companies.isEmpty }

    public var body: some View {
        Group {
            // Primero la empresa activa (también sin empresas: así `CompanySession` no se queda con una borrada).
            let companyKey = CompanySession.key(companyScope)
            // Con iCloud, en un dispositivo nuevo los libros tardan en llegar: no se pide crear la empresa
            // mientras se importan (`MacCargando`).
            if sync.isSyncing && !skipsSyncWait && companies.isEmpty {
                SyncLoadingView { skipsSyncWait = true }
            } else if companies.isEmpty && !welcomeSeen {
                // La primera vez: la bienvenida en carrusel, y de ahí al alta o a los datos de ejemplo.
                WelcomeView(startPage: welcomeStartPage, onCreate: { welcomeSeen = true }, onSample: { welcomeSeen = true })
            } else if companies.isEmpty {
                OnboardingView(onBack: { welcomeStartPage = WelcomeView.pageCount - 1; welcomeSeen = false })
                    #if DEBUG
                    // `-qa.muestra 1`: los datos de ejemplo sin pasar por el alta («Probar con datos de ejemplo»). Una sola
                    // vez por sesión: tras «Empezar con mi empresa» el alta tiene que quedar vacía.
                    .onAppear {
                        if QALaunch.loadsSample && !Self.qaLoadedSample {
                            Self.qaLoadedSample = true
                            try? SampleData.populate(modelContext)
                        }
                    }
                    #endif
            } else {
                // Al restaurar una copia se rehace la navegación: las pantallas abiertas apuntaban a registros borrados.
                // iPhone y iPad: el aviso de solo lectura encima y no superpuesto. En el Mac va al pie de la barra
                // lateral (`ReadOnlySidebarNote`): arriba de las columnas, el contenido quedaba debajo del aviso.
                VStack(spacing: 0) {
                    #if os(iOS)
                    if subscription.isReadOnly { ReadOnlyBanner() }
                    #endif
                    #if os(iOS)
                    // La app sigue montada debajo de la ventana de bloqueo: al desbloquear, todo está donde estaba.
                    AppShell(companyKey: companyKey).id(replacement.generation)
                    #else
                    if isLocked { LockView(lock: lock) } else { AppShell(companyKey: companyKey).id(replacement.generation) }
                    #endif
                }
            }
        }
        .sheet(isPresented: $subscription.showsPaywall) { PaywallView(focus: subscription.paywallFocus) }
        // Lista de empresas, «Añadir empresa» y el plan para contadores al llegar al límite (`CompanyHub`).
        .companySheets()
        // «Empezar con mi empresa» (aviso de Inicio y Ajustes): tras borrar los datos de ejemplo no queda empresa y sale el
        // alta. La pantalla de suscripción vuelve a salir sola al crear la empresa propia (si salió con los de ejemplo, ya
        // se había gastado su «una vez»), y no se espera a iCloud: el borrado que se sube no son libros que lleguen.
        .sampleBooksConfirmation {
            paywallShownOnce = false
            skipsSyncWait = true
            #if DEBUG
            Self.qaLoadedSample = true
            #endif
        }
        .task { subscription.start() }
        // La primera lectura de un recibo tras instalar tarda (el sistema prepara su modelo de texto): se adelanta en segundo
        // plano poco después de abrir, para que al escanear ya esté listo (decisión del usuario, 8-nov).
        .task {
            try? await Task.sleep(for: .seconds(6))
            ReceiptTextRecognizer.warmUp()
        }
        #if DEBUG
        .task(id: companies.count) {
            // Después de `-qa.muestra` y de que la suscripción de QA fije el límite.
            try? await Task.sleep(for: .milliseconds(300))
            applyQACompanies()
        }
        #endif
        .onChange(of: subscription.isReadOnly && !companies.isEmpty, initial: true) { _, readOnly in
            Bookkeeper.isReadOnly = readOnly
            // Al crear la empresa sin suscripción, o al abrir la app con la suscripción vencida, una vez.
            if readOnly && !paywallShownOnce {
                paywallShownOnce = true
                subscription.showsPaywall = true
            }
        }
        .alert("Copia restaurada", isPresented: Binding(get: { replacement.restored != nil }, set: { if !$0 { replacement.restored = nil } }),
               presenting: replacement.restored) { _ in
            Button("Aceptar", role: .cancel) {}
        } message: { info in
            if info.companyName.isEmpty {
                Text("Tus libros son ahora los de la copia del \(info.createdAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Los libros de «\(info.companyName)» son ahora los de la copia del \(info.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .tint(Palette.brand)
        .background(Palette.background)
        #if DEBUG
        .preferredColorScheme(QALaunch.colorScheme)
        #endif
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
    /// Empresa activa (`CompanySession.key`): al cambiar, las pestañas y las columnas se rehacen con la nueva. La
    /// pestaña y la sección elegidas se quedan.
    let companyKey: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Ancho de la columna de detalle: en un iPad vertical con la barra lateral abierta puede quedar estrecha.
    @State private var detailWidth: CGFloat = .infinity
    /// La ventana es más alta que ancha (iPad en vertical): ahí no caben barra lateral, lista y detalle a la vez.
    @State private var isPortrait = false
    /// La barra lateral se cerró sola en vertical: al girar a horizontal vuelve a abrirse, como antes.
    @State private var sidebarAutoClosed = false
    /// Hasta cuándo se vuelve a cerrar la barra lateral si la vista dividida recién hecha la abre.
    @State private var keepsSidebarClosedUntil = Date.distantPast
    #endif
    #if DEBUG
    /// `-qa.pestana sales|expenses|banking|reports` (solo Debug): la pestaña del iPhone con la que arranca; `reports`
    /// abre Más › Estado de resultados.
    @State private var tab: AppSection = UserDefaults.standard.string(forKey: "qa.pestana").map { $0 == "reports" ? "settings" : $0 }
        .flatMap(AppSection.init(rawValue:)) ?? .home
    @State private var qaOpensReports = UserDefaults.standard.string(forKey: "qa.pestana") == "reports"
    #else
    @State private var tab: AppSection = .home
    #endif
    #if DEBUG
    /// Con `-qa.seccion` (solo Debug), la página con la que arranca.
    @State private var selection: SidebarItem = QALaunch.salesItem ?? QALaunch.sidebarItem ?? .section(.home)
    #else
    @State private var selection: SidebarItem = .section(.home)
    #endif
    @State private var query = ""
    /// Cambios sin guardar del editor de la columna de detalle: antes de cambiar de pantalla se pregunta.
    @State private var unsavedChanges = UnsavedChanges()
    @State private var pendingSelection: SidebarItem?
    /// Se guarda aquí para que la barra lateral siga abierta o cerrada al rehacer la vista dividida.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Lo elegido en la columna maestro de las páginas de lista y detalle (`MasterPage`).
    @State private var masterSelection: UUID?
    /// La columna maestro oculta (solo el detalle a la vista).
    @State private var masterHidden = false
    @State private var monitor = SyncMonitor.shared
    @State private var companyHub = CompanyHub.shared
    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var masterWidth: CGFloat = 280
    #else
    /// Columna maestro con la barra lateral a la vista (horizontal): 320 pt. Con los 280 de la barra, el detalle de un
    /// iPad de 13" en horizontal queda en 776 pt, por encima del umbral de `isDetailNarrow` (los 340 del canvas lo
    /// dejarían en 756).
    @ScaledMetric(relativeTo: .body) private var sideBySideMasterWidth: CGFloat = 320
    /// Con la barra lateral cerrada (iPad en vertical) la lista tiene sitio: a 320 pt se cortaban «Accounts Receiv…»,
    /// «Accumulated Depreci…» y el título «Chart of accou…». El detalle ya usa ahí el diseño de iPhone (estrecho).
    @ScaledMetric(relativeTo: .body) private var soloMasterWidth: CGFloat = 400

    private var masterWidth: CGFloat {
        isPortrait && columnVisibility == .detailOnly ? soloMasterWidth : sideBySideMasterWidth
    }
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if sizeClass == .compact { tabs } else { split }
            #else
            split
            #endif
        }
        // Cambiar de empresa con un editor sin guardar pregunta antes, como cambiar de pantalla (`CompanyHub.select`).
        .onAppear { companyHub.unsavedChanges = unsavedChanges }
        .alert("¿Descartar los cambios?", isPresented: Binding(get: { companyHub.pendingCompanyID != nil },
                                                               set: { if !$0 { companyHub.pendingCompanyID = nil } })) {
            Button("Descartar", role: .destructive) { companyHub.discardAndSwitch() }
            Button("Seguir editando", role: .cancel) { companyHub.pendingCompanyID = nil }
        } message: {
            Text("Si cambias de empresa se pierde lo que escribiste.")
        }
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
                if unsavedChanges.hasChanges { pendingSelection = item } else { show(item) }
            }
        })
    }

    /// iPhone: 5 pestañas (Inicio · Ventas · Gastos · Banca · Más), como el canvas.
    private var tabs: some View {
        tabView.id(companyKey)
    }

    private var tabView: some View {
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
                NavigationStack {
                    MoreView().safeAreaInset(edge: .top, spacing: 0) { SyncErrorBanner() }
                        #if DEBUG
                        // Con `-qa.reporte <kind>`, ese reporte (fase 2: flujo de efectivo, presupuesto…).
                        .stableDestination(isPresented: $qaOpensReports) { ReportsView(fixedKind: ReportsView.qaKind ?? .income) }
                        #endif
                }
            }
        }
    }

    /// Página de lista y detalle con columna maestro (§7.4). No mientras llegan los libros de iCloud por primera vez
    /// (esqueleto de `SyncAwareContent`) ni con AX4 o más, donde la columna no cabe y se usan las listas del iPhone.
    private var masterPage: MasterPage? { masterPage(for: selection) }

    private func masterPage(for item: SidebarItem) -> MasterPage? {
        guard !monitor.isFirstImport, dynamicTypeSize < .accessibility4 else { return nil }
        return MasterPage(item)
    }

    /// Cambia de pantalla. En un iPad vertical, al elegir una página de lista la barra lateral se cierra sola y quedan
    /// la lista y el detalle: con las tres columnas, la lista medía ~300 pt y cortaba nombres y el buscador.
    /// El botón de la barra la vuelve a abrir. En horizontal y en el Mac no cambia nada.
    private func show(_ item: SidebarItem) {
        #if os(iOS)
        if isPortrait, masterPage(for: item) != nil {
            columnVisibility = .detailOnly
            sidebarAutoClosed = true
            // La vista dividida nueva (`.id(selection)`) se crea con la barra abierta aunque se le pida cerrada, y lo
            // avisa enseguida: ese aviso se contesta cerrándola otra vez (`masterVisibility`).
            keepsSidebarClosedUntil = .now + 1
        }
        #endif
        selection = item
    }

    #if os(iOS)
    /// Al girar el iPad: en vertical, una página de lista cierra la barra lateral como al elegirla; de vuelta en
    /// horizontal, la barra que se cerró sola se abre otra vez.
    private func orientationChanged(isPortrait: Bool) {
        if isPortrait {
            guard masterPage != nil, !masterHidden, columnVisibility != .detailOnly else { return }
            columnVisibility = .detailOnly
            sidebarAutoClosed = true
        } else if sidebarAutoClosed {
            sidebarAutoClosed = false
            if columnVisibility == .detailOnly { columnVisibility = .all }
        }
    }
    #endif

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Visibilidad con tres columnas a partir de la de dos: con la barra lateral cerrada se ven la lista y el detalle;
    /// ocultar también la lista deja solo el detalle. Así la barra queda como estaba al pasar de una página a otra.
    private var masterVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: {
            if masterHidden { return .detailOnly }
            return columnVisibility == .detailOnly ? .doubleColumn : columnVisibility
        }, set: { visibility in
            #if os(iOS)
            if visibility == .all, Date.now < keepsSidebarClosedUntil {
                // Primero el valor que dice la vista dividida y luego el cierre: así cambia y se lo vuelve a pedir.
                masterHidden = false
                columnVisibility = .all
                Task { @MainActor in columnVisibility = .detailOnly }
                return
            }
            // Quien abre la barra con su botón decide: ya no se cierra ni se abre sola al girar.
            if visibility == .all { sidebarAutoClosed = false }
            #endif
            masterHidden = visibility == .detailOnly
            columnVisibility = visibility == .all || visibility == .automatic ? visibility : .detailOnly
        })
    }

    private var sidebar: some View {
        Sidebar(selection: sidebarSelection, query: $query)
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 280)
            #else
            // Solo en iOS: en el Mac, quitar el título de la barra lateral la dejaba en ~144 pt.
            .toolbar(removing: .title)
            // Después de `.toolbar(removing:)`: antes de él no llegaba a la vista dividida, y la barra medía 320 pt
            // con dos columnas y 280 con tres (cambiaba de ancho al pasar de Inicio a Ventas). Con 280, el detalle
            // de Ventas en un iPad de 13" en horizontal sigue por encima del umbral de `isDetailNarrow`.
            .navigationSplitViewColumnWidth(280)
            #endif
    }

    /// Columna de detalle: lo de la página o, con texto en la búsqueda de la barra lateral, los resultados.
    private func detailColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            if isSearching { SearchResultsView(query: query) } else { content() }
        }
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        .safeAreaInset(edge: .top, spacing: 0) { SyncErrorBanner() }
        #else
        // `MacError`: la alerta sobre el contenido; tras «Seguir sin conexión», una franja encima con «Reintentar».
        .safeAreaInset(edge: .top, spacing: 0) { SyncOfflineStrip() }
        .overlay { SyncErrorBanner() }
        #endif
    }

    /// iPad y Mac: barra lateral propia (`Sidebar`) y, en las páginas de lista y detalle, la columna maestro (iPad).
    /// En el Mac, las páginas de lista son barra lateral + contenido: la tabla a todo el ancho con el inspector a la
    /// derecha (`MacTablePage`, decisión del usuario del 2-nov). Las que aún no tienen su tabla (`hasMacTable`) siguen
    /// con la columna maestro.
    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        if let page = masterPage, page.hasMacTable {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailColumn { page.macTable(selection: $masterSelection) }
            }
        } else {
            listColumns
        }
        #else
        listColumns
        #endif
    }

    @ViewBuilder
    private var listColumns: some View {
        if let page = masterPage {
            NavigationSplitView(columnVisibility: masterVisibility) {
                sidebar
            } content: {
                MasterColumn(page: page, selection: $masterSelection)
                    .navigationSplitViewColumnWidth(min: masterWidth * 0.85, ideal: masterWidth, max: masterWidth * 1.4)
            } detail: {
                // Con otra elección, el detalle empieza de cero: no se queda en lo que se abrió encima de la anterior.
                detailColumn { MasterDetailColumn(page: page, selection: masterSelection) }
                    .id(masterSelection)
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailColumn { SyncAwareContent(title: selection.section.title) { selection.destination } }
            }
        }
    }

    private var split: some View {
        columns
        #if os(iOS)
        // Si la columna de detalle queda estrecha, sus pantallas usan el diseño de iPhone: las tablas de Gastos y la
        // vista dividida de Ventas no caben (iPad vertical con la barra abierta: 712 pt en el de 13", y con texto
        // grande se cortaba también Ventas). En la vista dividida y no en la pila: las pantallas que se abren encima
        // toman el entorno de aquí.
        .environment(\.isNarrowColumn, isDetailNarrow)
        #endif
        .environment(\.unsavedChanges, unsavedChanges)
        .environment(\.openSidebarItem, OpenSidebarItemAction { sidebarSelection.wrappedValue = $0 })
        .alert("¿Descartar los cambios?", isPresented: Binding(get: { pendingSelection != nil }, set: { if !$0 { pendingSelection = nil } })) {
            Button("Descartar", role: .destructive) {
                unsavedChanges.discardAll()
                if let pendingSelection { show(pendingSelection) }
                pendingSelection = nil
            }
            Button("Seguir editando", role: .cancel) { pendingSelection = nil }
        } message: {
            Text("Si cambias de pantalla se pierde lo que escribiste.")
        }
        // Al elegir otro elemento de la barra lateral se rehace la vista dividida entera: las pantallas abiertas con
        // `NavigationLink(destination:)` quedan en la pila propia de la columna de detalle, que no se vacía al
        // cambiar la raíz ni con `.id` en el `NavigationStack` interior.
        // También con otra empresa: todo se crea de nuevo con la empresa activa (`CompanySession`).
        .id(ShellIdentity(selection: selection, companyKey: companyKey))
        // Después de `.id`, en la vista que no se rehace: antes de él no llegaba a ejecutarse, y el Plan de cuentas se
        // abría con la cuenta elegida en Banca. Al cambiar de pantalla, los editores de la columna ya no existen.
        .onChange(of: selection) {
            unsavedChanges.removeAll()
            masterSelection = nil
        }
        .onChange(of: companyKey) {
            unsavedChanges.removeAll()
            masterSelection = nil
            pendingSelection = nil
            query = ""
        }
        #if os(iOS)
        .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { isPortrait = $0 }
        .onChange(of: isPortrait) { _, portrait in orientationChanged(isPortrait: portrait) }
        #endif
    }
}

/// Identidad de la vista dividida: la sección elegida y la empresa activa.
private struct ShellIdentity: Hashable {
    let selection: SidebarItem
    let companyKey: String
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

/// Pestaña «Más» del iPhone (canvas `Mas`), como la app Ajustes: la empresa arriba con su monograma y, en grupos,
/// Reportes, Contabilidad, Impuestos y Ajustes en filas con icono de color. Banca tiene su pestaña; Plantilla de
/// factura y Usuarios y permisos son de fase 2 y no salen; Deducibles va en Impuestos (1.3).
struct MoreView: View {
    @ActiveCompanyQuery private var companies: [Company]
    @Query private var allCompanies: [Company]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @CompanyQuery private var entries: [JournalEntry]
    @CompanyQuery private var rates: [TaxRate]
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    /// «Abrir Impuestos» de la pista de arriba.
    @State private var showingTaxes = false

    var body: some View {
        List {
            // Pista de una sola vez: Impuestos queda abajo, después de Reportes.
            Section {
                InlineTip(tip: TaxesTip()) { _ in
                    TaxesTip().invalidate(reason: .actionPerformed)
                    showingTaxes = true
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let company = companies.first {
                Section {
                    companyRow(company)
                    // Varias empresas: la lista con lo pendiente de cada una, cambiar, añadir, archivar y borrar.
                    MoreRow(title: String(localized: "Empresas"), value: "\(allCompanies.filter { !$0.isArchived }.count)",
                            systemImage: "building.2", color: Palette.orange) { CompaniesView() }
                }
            }

            Section(title: "Reportes") {
                ForEach(ReportsView.Kind.allCases) { kind in
                    MoreRow(title: kind.fullTitle, systemImage: kind.moreSymbol, color: kind.moreColor) { ReportsView(fixedKind: kind) }
                }
            }

            // Impuestos antes que Contabilidad (decisión del usuario, 6-nov): el sales tax es de todos los meses y al
            // fondo de «Más» no se encontraba.
            Section {
                MoreRow(title: String(localized: "Resumen"), value: taxSubtitle, valueColor: taxOwed > 0 ? Palette.warning : Palette.ink2,
                        systemImage: "percent", color: Palette.red) { TaxesView() }
                MoreRow(title: String(localized: "Tasas"), value: String(localized: "\(rates.count) activas"),
                        systemImage: "list.number", color: Palette.pink) { TaxesView(tab: .rates) }
                // Fase 2 (canvas `Mas`): deducibles por línea del Schedule C / 1120-S (`Taxes/DeductionsView.swift`).
                MoreRow(title: String(localized: "Deducibles"), systemImage: "dollarsign", color: Palette.green) { TaxesView(tab: .deductions) }
            } header: {
                SectionLabel(text: String(localized: "Impuestos"))
            } footer: {
                Text("Tasas y declaración del sales tax: lo que cobras a tus clientes y le pagas al estado.")
            }

            Section(title: "Contabilidad") {
                MoreRow(title: String(localized: "Plan de cuentas"), value: String(localized: "\(accounts.filter { !$0.isArchived }.count) cuentas"),
                        systemImage: "list.bullet.indent", color: Palette.indigo) { ChartOfAccountsView() }
                MoreRow(title: String(localized: "Asientos de diario"), value: String(localized: "\(entriesThisMonth) este mes"),
                        systemImage: "doc.plaintext", color: Palette.blue) { JournalListView() }
                MoreRow(title: String(localized: "Libro mayor"), value: String(localized: "Por cuenta"),
                        systemImage: "book.closed", color: Palette.teal) { LedgerAccountPickerView() }
                MoreRow(title: String(localized: "Cierre de periodo"), value: closeSubtitle,
                        systemImage: "lock", color: Palette.gray) { PeriodCloseView() }
            }

            Section(title: "Ajustes") {
                if let company = companies.first {
                    MoreRow(title: String(localized: "Perfil de la empresa"), systemImage: "building.2", color: Palette.gray) {
                        CompanyProfileView(company: company)
                    }
                    // Canvas `AjustesPlantilla` (se abre desde «Más»).
                    MoreRow(title: String(localized: "Plantilla de factura"), value: company.invoiceAccent?.title,
                            systemImage: "doc.richtext", color: Palette.indigo) { InvoiceTemplateView(company: company) }
                    MoreRow(title: String(localized: "Moneda y formatos"), value: company.currencyCode,
                            systemImage: "dollarsign", color: Palette.green) { FormatsView(company: company) }
                }
                MoreRow(title: String(localized: "iCloud y copias"),
                        value: iCloudSyncEnabled ? String(localized: "Activado") : String(localized: "Desactivado"),
                        systemImage: "icloud", color: Palette.teal) { DataAndSecurityView() }
                MoreRow(title: String(localized: "Seguridad"),
                        value: appLockEnabled ? String(localized: "Face ID") : String(localized: "Desactivado"),
                        systemImage: "faceid", color: Palette.red) { DataAndSecurityView() }
            }

            Section(title: "Ayuda") { GuideLinkRow() }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Más")
        .headerTitle()
        .stableDestination(isPresented: $showingTaxes) { TaxesView() }
    }

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

    /// Fila de la empresa (canvas: monograma de 56 pt, nombre de 20 semibold y un detalle gris), que abre su perfil.
    private func companyRow(_ company: Company) -> some View {
        let name = company.displayName.isEmpty ? company.legalName : company.displayName
        let detail = company.legalName.isEmpty || company.legalName == name ? company.entityType.title : company.legalName
        return NavigationLink { CompanyProfileView(company: company) } label: {
            HStack(spacing: 14) {
                CompanyMonogram(name: name, side: 56)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(detail).font(.footnote).foregroundStyle(Palette.ink2)
                }
                .lineLimit(2)
            }
            .padding(.vertical, 4)
        }
        .accessibilityHint("Abre el perfil de la empresa")
    }
}

extension ReportsView.Kind {
    /// Icono de la fila en «Más» (canvas `Mas`: resultados en verde, balance en azul, antigüedad en naranja).
    var moreSymbol: String {
        switch self {
        case .income: "chart.bar"
        case .balance: "scalemass"
        case .trial: "list.bullet.rectangle"
        case .cashFlow: "arrow.left.arrow.right"
        case .receivables: "clock"
        case .payables: "clock.arrow.circlepath"
        case .salesTax: "percent"
        case .budget: "target"
        }
    }

    var moreColor: Color {
        switch self {
        case .income: Palette.green
        case .balance: Palette.blue
        case .trial: Palette.indigo
        case .cashFlow: Palette.teal
        case .receivables: Palette.orange
        case .payables: Palette.purple
        case .salesTax: Palette.pink
        case .budget: Palette.red
        }
    }
}

/// Fila de «Más» como las de Ajustes: icono blanco en un cuadrado de color, título, dato gris y el chevron del sistema.
/// Con tamaños de accesibilidad, el dato baja debajo del título.
private struct MoreRow<Destination: View>: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = Palette.ink2
    let systemImage: String
    let color: Color
    @ViewBuilder let destination: () -> Destination
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                IconTile(systemImage: systemImage, foreground: color)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(Palette.ink)
                        if let value { Text(value).foregroundStyle(valueColor) }
                    }
                } else {
                    Text(title).foregroundStyle(Palette.ink).lineLimit(2).layoutPriority(1)
                    Spacer(minLength: 8)
                    if let value { Text(value).foregroundStyle(valueColor).lineLimit(1) }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Monograma de la empresa, como el de un contacto: iniciales blancas en un círculo con el degradado gris del sistema
/// (canvas `Mas`, `Sidebar`). Antes era un cuadrado negro que en oscuro quedaba blanco con texto negro.
struct CompanyMonogram: View {
    let name: String
    var side: CGFloat = 36

    var body: some View {
        Monogram(initials: Initials.from(name), side: side, fontScale: 0.4, maxScale: 1.6)
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
