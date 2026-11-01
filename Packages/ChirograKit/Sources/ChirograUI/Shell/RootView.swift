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
        case .home: "Inicio"
        case .sales: "Ventas"
        case .expenses: "Gastos"
        case .banking: "Banca"
        case .reports: "Reportes"
        case .accounting: "Contabilidad"
        case .taxes: "Impuestos"
        case .settings: "Ajustes"
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
        case .taxes: "percent"
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
    #if os(iOS)
    @State private var lockWindow = LockWindow()
    #endif

    public init() {}

    private var isLocked: Bool { appLockEnabled && !lock.isUnlocked && !companies.isEmpty }

    public var body: some View {
        Group {
            if companies.isEmpty {
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
        #if os(iOS)
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
    #endif
    @State private var tab: AppSection = .home
    @State private var selection: AppSection? = .home

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact { tabs } else { split }
        #else
        split
        #endif
    }

    /// iPhone: 5 pestañas (Inicio · Ventas · Gastos · Reportes · Más).
    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(AppSection.phoneTabs) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    NavigationStack { section.destination }
                }
            }
            Tab("Más", systemImage: "ellipsis.circle", value: AppSection.settings) {
                NavigationStack { MoreView() }
            }
        }
    }

    /// iPad y Mac: barra lateral con la sección "MÁS".
    private var split: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppSection.primary) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                } header: {
                    HStack(spacing: 10) {
                        LogoMark(size: 24)
                        Text("Chirogra").font(.headline).foregroundStyle(Palette.ink)
                    }
                    .padding(.bottom, 6)
                    .textCase(nil)
                }
                Section("Más") {
                    ForEach(AppSection.more) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .scrollContentBackground(.hidden)
            .background(Palette.sidebar)
        } detail: {
            NavigationStack {
                (selection ?? .home).destination
            }
            .id(selection)
        }
    }
}

/// Pestaña "Más" del iPhone: Contabilidad, Impuestos y Ajustes.
struct MoreView: View {
    @Query private var companies: [Company]

    var body: some View {
        List {
            if let company = companies.first {
                Section {
                    NavigationLink { CompanyProfileView(company: company) } label: {
                        LedgerRow(title: company.displayName, subtitle: company.legalName) {
                            InitialsTile(text: Initials.from(company.displayName),
                                         foreground: Palette.background, background: Palette.ink)
                        } trailing: { EmptyView() }
                    }
                }
            }
            Section("Banca") {
                NavigationLink { BankingView() } label: { Label("Cuentas y saldos", systemImage: "building.columns") }
            }
            Section("Contabilidad") {
                NavigationLink { ChartOfAccountsView() } label: { Label("Plan de cuentas", systemImage: "list.bullet.indent") }
                NavigationLink { JournalListView() } label: { Label("Asientos de diario", systemImage: "doc.plaintext") }
                NavigationLink { LedgerAccountPickerView() } label: { Label("Libro mayor", systemImage: "book.closed") }
                NavigationLink { PeriodCloseView() } label: { Label("Cierre de periodo", systemImage: "lock") }
            }
            Section("Impuestos") {
                NavigationLink { TaxesView() } label: { Label("Sales tax", systemImage: "percent") }
            }
            Section("Ajustes") {
                SettingsLinks(showsCompanyProfile: false)
            }
        }
        .screenBackground()
        .navigationTitle("Más")
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
                                                                       localizedReason: "Desbloquear tus libros")
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
