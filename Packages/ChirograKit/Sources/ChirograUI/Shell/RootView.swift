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
    @State private var isUnlocked = false

    public init() {}

    public var body: some View {
        Group {
            if companies.isEmpty {
                OnboardingView()
            } else if appLockEnabled && !isUnlocked {
                LockView(isUnlocked: $isUnlocked)
            } else {
                AppShell()
            }
        }
        .tint(Palette.brand)
        .background(Palette.background)
        .onChange(of: scenePhase) { _, phase in
            // Al pasar a segundo plano se vuelve a bloquear; al volver se pide Face ID otra vez.
            if phase == .background { isUnlocked = false }
        }
    }
}

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

    /// iPhone: 6 pestañas (Inicio · Ventas · Gastos · Banca · Reportes · Más).
    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(AppSection.primary) { section in
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
                            InitialsTile(text: String(company.displayName.prefix(2)).uppercased(),
                                         foreground: Palette.background, background: Palette.ink)
                        } trailing: { EmptyView() }
                    }
                }
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
                SettingsLinks()
            }
        }
        .screenBackground()
        .navigationTitle("Más")
    }
}

struct LockView: View {
    @Binding var isUnlocked: Bool
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            LogoMark(size: 64)
            Text("Chirogra está bloqueada").font(.title2.weight(.semibold))
            if failed { Text("No se pudo verificar tu identidad.").foregroundStyle(Palette.negative) }
            Button("Desbloquear", action: unlock).buttonStyle(.primary).frame(maxWidth: 280)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .task { unlock() }
    }

    private func unlock() {
        let context = LAContext()
        guard AppLock.isAvailable else {
            // El dispositivo ya no tiene código ni biometría: desactivar el bloqueo antes que dejar fuera al usuario.
            appLockEnabled = false
            isUnlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Desbloquear tus libros") { success, _ in
            Task { @MainActor in
                isUnlocked = success
                failed = !success
            }
        }
    }
}
