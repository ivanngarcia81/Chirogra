import CloudKit
import CoreData
import SwiftUI

/// Estado de la sincronización con iCloud a partir de los eventos del contenedor de CloudKit que usa SwiftData.
/// Empieza en `.off` y cambia con el primer evento: sin iCloud (o sin la capacidad firmada) no llega ninguno.
@Observable
final class SyncMonitor {
    enum State: Equatable {
        case off
        case syncing
        case synced(Date)
        /// `code`: detalle técnico («CKError.networkUnavailable»); `network`: falta conexión, no es un fallo de la cuenta.
        case failed(code: String, network: Bool)
    }

    static let shared = SyncMonitor()

    var lastSync: Date?

    var state: State = .off

    /// Este dispositivo ya terminó de traer los libros de iCloud alguna vez. Hasta entonces, si ya hay empresa,
    /// las secciones muestran su esqueleto con «Sincronizando con iCloud» (`MacCargando`, `EstadoCargando`).
    private(set) var hasImported = UserDefaults.standard.bool(forKey: SyncMonitor.importedKey)

    private static let importedKey = "iCloudFirstImportDone"

    /// Solo en Debug, para QA sin iCloud: lanzar con `-ChirograForceSync loading` (esqueleto «Sincronizando con iCloud»,
    /// también con empresa) o `-ChirograForceSync error` (franja de sin conexión). En Release no existe.
    #if DEBUG
    static let forced = UserDefaults.standard.string(forKey: "ChirograForceSync")
    #else
    static let forced: String? = nil
    #endif

    /// El esqueleto forzado se muestra aunque ya haya empresa.
    static var forcesLoading: Bool { forced == "loading" }

    init() {
        switch Self.forced {
        case "loading": state = .syncing; hasImported = false
        case "error":
            state = .failed(code: "CKError.networkUnavailable", network: true)
            hasFailed = true
            lastSync = Calendar.current.date(byAdding: .day, value: -1, to: .now)
        default: break
        }
    }

    var isSyncing: Bool { state == .syncing }

    /// Primera importación en curso: el esqueleto sustituye al contenido de la sección.
    /// Tras un fallo se muestran los datos del dispositivo con la franja, no el esqueleto.
    var isFirstImport: Bool { isSyncing && !hasImported && !hasFailed }

    private var hasFailed = false

    /// «Reintentar»: CloudKit reintenta solo; se vuelve a «Sincronizando» y la franja reaparece si el siguiente
    /// evento también falla. Con la bandera de QA, el fallo vuelve a los 2 segundos.
    func retry() {
        state = .syncing
        if Self.forced == "error" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                state = .failed(code: "CKError.networkUnavailable", network: true)
            }
        }
    }

    var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    func apply(_ event: NSPersistentCloudKitContainer.Event) {
        guard Self.forced == nil else { return }
        if event.endDate == nil {
            state = .syncing
        } else if let error = event.error {
            let ckError = error as? CKError
            let network = [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(ckError?.code)
            state = .failed(code: ckError.map { "CKError.\($0.code)" } ?? (error as NSError).domain, network: network)
            hasFailed = true
        } else {
            let date = event.endDate ?? .now
            lastSync = date
            state = .synced(date)
            if event.type == .import && !hasImported {
                hasImported = true
                UserDefaults.standard.set(true, forKey: Self.importedKey)
            }
        }
    }
}

extension View {
    /// Escucha los eventos de sincronización y los pasa a `SyncMonitor.shared` en el hilo principal.
    func monitorsCloudSync() -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).receive(on: RunLoop.main)) { note in
            if let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                SyncMonitor.shared.apply(event)
            }
        }
    }
}

// MARK: - Cargando (`MacCargando`, `EstadoCargando`)

/// Contenido de una sección: mientras llegan los libros de iCloud por primera vez, su esqueleto con el título y
/// «Sincronizando con iCloud»; la barra lateral y las pestañas siguen disponibles.
struct SyncAwareContent<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var monitor = SyncMonitor.shared

    var body: some View {
        if monitor.isFirstImport {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // En iOS el título va en la barra de navegación (con el botón de la barra lateral); en el Mac,
                    // grande dentro del contenido como en `MacCargando`.
                    #if os(macOS)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { MacPageTitle(title); Spacer(minLength: 8); SyncingPill() }
                        VStack(alignment: .leading, spacing: 8) { MacPageTitle(title); SyncingPill() }
                    }
                    #else
                    SyncingPill()
                    #endif
                    SyncSkeleton()
                    Text("Estamos trayendo tus libros desde iCloud. Puedes seguir usando la app mientras tanto.")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .padding(20)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle(title)
        } else {
            content
        }
    }
}

/// Píldora «Sincronizando con iCloud».
struct SyncingPill: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Sincronizando con iCloud").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Palette.brand)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Palette.brandWash, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Cifras clave y filas de tabla en gris, con un pulso suave (quieto con «Reducir movimiento»).
struct SyncSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(spacing: 14) {
            // Cuatro cifras en fila o, si no caben, en dos filas de dos.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in kpi } }
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow { kpi; kpi }
                    GridRow { kpi; kpi }
                }
            }
            VStack(spacing: 0) {
                ForEach([0.22, 0.16, 0.26, 0.18, 0.24, 0.14, 0.2, 0.28], id: \.self) { share in
                    VStack(spacing: 0) {
                        Divider()
                        GeometryReader { proxy in
                            // Las barras fijas solo si caben: en el iPhone la fila se salía de la tarjeta.
                            let wide = proxy.size.width >= 420
                            HStack(spacing: 16) {
                                bar(width: 56, height: 10)
                                bar(width: proxy.size.width * share, height: 10)
                                Spacer(minLength: 0)
                                if wide { bar(width: 64, height: 10) }
                                bar(width: wide ? 80 : 60, height: 18)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 18)
                    }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .opacity(dim ? 0.45 : 1)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private var kpi: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar(width: 90, height: 10)
            bar(width: 110, height: 20)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(Palette.surface2).frame(width: width, height: height)
    }
}

/// Primera apertura con iCloud en un dispositivo nuevo y todavía sin empresa: mientras llegan los datos se muestra
/// el esqueleto con «Sincronizando con iCloud», en vez del alta de empresa. Se puede crear una empresa nueva igualmente.
struct SyncLoadingView: View {
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LogoMark(size: 34)
                    Text("Chirogra").font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    SyncingPill()
                }
                SyncSkeleton()
                Text("Estamos trayendo tus libros desde iCloud. Si es la primera vez que usas Chirogra, puedes crear tu empresa.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Button("Crear una empresa nueva", action: onSkip).font(.body.weight(.semibold)).frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

// MARK: - Sin conexión (`MacError`)

/// Franja de arriba cuando iCloud no responde: los datos siguen en este dispositivo y los cambios se envían solos
/// al volver la conexión. «Detalles» abre la tarjeta del canvas con la última sincronización y el detalle técnico.
struct SyncErrorBanner: View {
    @State private var monitor = SyncMonitor.shared
    @State private var showingDetails = false
    @State private var dismissed = false
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    var body: some View {
        if case let .failed(code, network) = monitor.state, !dismissed {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash").accessibilityHidden(true)
                Text(network ? String(localized: "Sin conexión con iCloud. Estás trabajando con los datos guardados en este dispositivo.")
                             : String(localized: "No pudimos sincronizar con iCloud. Tus datos siguen guardados en este dispositivo."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Detalles") { showingDetails = true }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    #if os(macOS)
                    .popover(isPresented: $showingDetails) { details(code: code, network: network) }
                    #endif
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, margin).padding(.top, 8)
            #if os(iOS)
            // En iOS, hoja centrada: la tarjeta de cristal del popover quedaba sobre la franja oscura y su título
            // apenas se leía.
            .sheet(isPresented: $showingDetails) {
                if sizeClass == .compact {
                    ScrollView { details(code: code, network: network) }.presentationDetents([.medium, .large])
                } else {
                    // Ancho fijo: con `.fitted` y sin él, el texto se medía en una sola línea y se cortaba.
                    details(code: code, network: network).frame(width: 440).presentationSizing(.fitted)
                }
            }
            #endif
        }
    }

    private func details(code: String, network: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 30))
                .foregroundStyle(Palette.negative)
                .frame(width: 64, height: 64)
                .background(Palette.negativeWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text("No pudimos sincronizar tus datos").font(.title3.weight(.bold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(network ? String(localized: "Tus cambios están a salvo en este dispositivo y se enviarán solos cuando vuelva la conexión. Revisa tu red.")
                         : String(localized: "Tus cambios están a salvo en este dispositivo. Revisa tu sesión de iCloud en los ajustes del sistema."))
                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                detailRow(String(localized: "Última sincronización")) {
                    Text(monitor.lastSync?.formatted(.appDateTime.day().month(.abbreviated).hour().minute()) ?? "—")
                }
                Divider()
                detailRow(String(localized: "Cambios pendientes")) {
                    Text("Guardados en este dispositivo")
                }
                Divider()
                detailRow(String(localized: "Detalle técnico")) {
                    Text(code).font(.caption.monospaced()).foregroundStyle(Palette.ink2)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { continueButton; retryButton }
                VStack(spacing: 10) { retryButton; continueButton }
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 420)
        #else
        .frame(maxWidth: 480)
        #endif
    }

    /// Alineada con las tarjetas: margen del iPhone en pantallas compactas.
    private var margin: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? Metrics.gutter : 20
        #else
        20
        #endif
    }

    private var retryButton: some View {
        Button { showingDetails = false; monitor.retry() } label: { Text("Reintentar").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(Palette.brand).controlSize(.large)
    }

    private var continueButton: some View {
        Button { showingDetails = false; dismissed = true } label: { Text("Seguir sin conexión").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).tint(Palette.ink).controlSize(.large)
    }

    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(Palette.ink3)
            Spacer(minLength: 8)
            value().foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}
