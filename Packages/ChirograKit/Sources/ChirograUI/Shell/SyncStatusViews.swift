import ChirograData
import CloudKit
import CoreData
import SwiftData
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

    /// Importaciones de iCloud terminadas bien en esta sesión (`waitForImport`).
    @ObservationIgnored private var importsDone = 0

    /// Inicio de la última subida a iCloud que terminó bien: lo que se guardó antes de esa fecha ya está en iCloud
    /// («Borrar todo y empezar de cero» espera a una que empiece después del borrado).
    @ObservationIgnored private(set) var lastExportStart: Date?

    /// Espera a que termine la siguiente importación de iCloud (lo que otros aparatos cambiaron mientras este estaba
    /// cerrado), hasta `timeout`, o a que falle. Sin iCloud en este aparato vuelve enseguida. Las automatizaciones la
    /// esperan al abrir y al volver al primer plano: así un aparato atrasado recibe primero el borrado de una empresa y
    /// no escribe en ella (lo que escribía volvía a subir y la empresa «volvía», 13-nov).
    func waitForImport(timeout: Duration = .seconds(15)) async {
        guard DeletedCompanies.isEnabled, Self.forced == nil else { return }
        let start = importsDone
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while importsDone == start, !isFailed, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

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

    /// En el Mac, «Seguir sin conexión» en la tarjeta de error: se trabaja con los datos del dispositivo y la tarjeta
    /// no vuelve hasta el próximo fallo de esta sesión.
    var continuesOffline = false

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
            if event.type == .import { importsDone += 1 }
            if event.type == .export { lastExportStart = event.startDate }
            if event.type == .import && !hasImported {
                hasImported = true
                UserDefaults.standard.set(true, forKey: Self.importedKey)
            }
        }
    }
}

extension View {
    /// Escucha los eventos de sincronización y los pasa a `SyncMonitor.shared` en el hilo principal. Además corre las
    /// automatizaciones (`AppAutomations`): al abrir y al volver al primer plano, y tras traer cambios de iCloud.
    func monitorsCloudSync() -> some View {
        modifier(CloudSyncMonitor())
    }
}

private struct CloudSyncMonitor: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).receive(on: RunLoop.main)) { note in
                if let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                    SyncMonitor.shared.apply(event)
                    // Tras traer cambios de otro aparato: si los dos generaron la misma repetición sin conexión, se anula la
                    // copia; después se pone al día lo que toque (lo que ya generó el otro aparato no se repite).
                    if event.type == .import, event.endDate != nil, event.succeeded {
                        AppAutomations.afterSync(container: context.container)
                    }
                }
            }
            // Al abrir (también si el Mac la abre en segundo plano) y cada vez que vuelve al primer plano, después de traer
            // lo que cambió en iCloud mientras tanto.
            .task { AppAutomations.run(container: context.container, waitingForImport: true) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { AppAutomations.run(container: context.container, waitingForImport: true) }
            }
            // Otro aparato borró una empresa (`DeletedCompanies`): se borra aquí lo que quede de ella.
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification).receive(on: RunLoop.main)) { _ in
                AppAutomations.sweepDeletedCompanies(container: context.container)
            }
    }
}

/// Automatizaciones de la app (DATOS-V2 §1–2): `runAutomations()` genera los recurrentes que tocan hasta hoy y registra
/// los pagos con cargo automático; `resolveRecurringDuplicates()` repara repeticiones duplicadas tras sincronizar. Antes,
/// `DeletedCompanies.sweep` borra lo que quede de las empresas borradas en otro aparato (también en solo lectura) y
/// `adoptOrphanRecords()` da la empresa principal a lo que llegó sin empresa. Corren para cada empresa sin archivar.
/// Al abrir y al volver al primer plano esperan antes a la importación de iCloud (`SyncMonitor.waitForImport`).
///
/// No bloquean la interfaz: corren en una tarea de prioridad baja cuando la pantalla ya está dibujada, cada vez con un
/// `ModelContext` propio (no el de las pantallas: así nunca guardan ni deshacen lo que el usuario tiene a medias) y lo
/// que guardan llega solo a las pantallas. `Bookkeeper` es `@MainActor`, así que el trabajo en sí va en el hilo
/// principal; son unas pocas consultas. Son idempotentes: llamarlas de más no duplica nada. Mientras se traen los
/// libros de iCloud por primera vez no corren (generarían lo que el otro aparato ya generó). Si un pago automático
/// falla, queda programado y la campana de Inicio lo avisa (`Notice.scheduledPaymentDue`).
/// Cargos automáticos que fallaron en la última pasada de `AppAutomations` (id de la factura → motivo).
@Observable
final class AutomationFailures {
    static let shared = AutomationFailures()
    var byBill: [UUID: String] = [:]
}

enum AppAutomations {
    private static var running = false
    private static var pendingResolve = false

    static func run(container: ModelContainer, resolvingDuplicates: Bool = false, waitingForImport: Bool = false) {
        guard !SyncMonitor.shared.isFirstImport else { return }
        // En solo lectura no se genera ni se cobra nada (los recurrentes se ponen al día al renovar), pero se barre.
        guard !Bookkeeper.isReadOnly else {
            sweepDeletedCompanies(container: container)
            return
        }
        if running {
            if resolvingDuplicates { pendingResolve = true }
            return
        }
        running = true
        let resolve = resolvingDuplicates || pendingResolve
        pendingResolve = false
        Task(priority: .utility) {
            // Que la pantalla se dibuje antes.
            try? await Task.sleep(for: .milliseconds(400))
            if waitingForImport { await SyncMonitor.shared.waitForImport() }
            let context = ModelContext(container)
            let base = Bookkeeper(context: context)
            // Lo que quede de las empresas borradas (otro aparato atrasado pudo volver a subirlo), antes de escribir nada.
            _ = try? DeletedCompanies.sweep(in: context)
            // Lo que llegó sin empresa (de un aparato con la 1.0.x, o de una pantalla) pasa a ser de la principal para
            // siempre (DATOS-V4 §1). Al abrir y tras cada importación de iCloud, antes de las automatizaciones.
            _ = try? base.adoptOrphanRecords()
            // Para cada empresa, no solo la activa: los recurrentes y los cargos automáticos de los clientes de un
            // contador tienen que correr aunque esté mirando otra. Las archivadas no: están guardadas, sin uso (al
            // volver a mostrarlas se ponen al día, porque `runAutomations` genera todo lo que toca hasta hoy).
            var failures: [UUID: String] = [:]
            for company in (try? base.companies()) ?? [] {
                let books = base.forCompany(company.id)
                if resolve { _ = try? books.resolveRecurringDuplicates() }
                await Task.yield()
                if let result = try? books.runAutomations() {
                    // Cargos automáticos que no se pudieron registrar (periodo cerrado, cuenta archivada…): la campana los
                    // marca en su aviso de pago programado. Se recuerdan solo mientras la app está abierta.
                    for failure in result.autoPayments.failures where failures[failure.bill.id] == nil {
                        failures[failure.bill.id] = failure.error.localizedDescription
                    }
                }
            }
            AutomationFailures.shared.byBill = failures
            running = false
            if pendingResolve { run(container: container, resolvingDuplicates: true) }
        }
    }

    /// Solo el barrido de las empresas borradas (`DeletedCompanies`), con un contexto propio.
    static func sweepDeletedCompanies(container: ModelContainer) {
        _ = try? DeletedCompanies.sweep(in: ModelContext(container))
    }

    static func afterSync(container: ModelContainer) {
        run(container: container, resolvingDuplicates: true)
    }
}

// MARK: - Cargando (`MacCargando`, `EstadoCargando`)

/// Contenido de una sección: mientras llegan los libros de iCloud por primera vez, su esqueleto con el título y
/// «Sincronizando con iCloud…»; la barra lateral y las pestañas siguen disponibles.
struct SyncAwareContent<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var monitor = SyncMonitor.shared

    var body: some View {
        if monitor.isFirstImport {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // El título va en la barra, grande (`headerTitle`), como en el resto de pantallas; el estado, debajo.
                    SyncingPill()
                    SyncSkeleton()
                    Text("Estamos trayendo tus libros desde iCloud. Puedes seguir usando la app mientras tanto.")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .padding(.horizontal, Metrics.cardPadding)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 8)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle(title)
            .headerTitle()
        } else {
            content
        }
    }
}

/// «Sincronizando con iCloud…» con el indicador del sistema, en gris bajo el título (canvas `EstadoCargando`,
/// `MacCargando`). Ya no es una cápsula de color.
struct SyncingPill: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Sincronizando con iCloud…")
        }
        .font(Self.font)
        .foregroundStyle(Palette.ink2)
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    #if os(macOS)
    private static let font = Font.subheadline
    #else
    private static let font = Font.footnote
    #endif
}

/// Esqueleto de una pantalla mientras carga, en los grises de relleno del sistema y con un pulso suave (quieto con
/// «Reducir movimiento»). iPhone e iPad (`EstadoCargando`): buscador, segmentado, tarjeta de resumen y una lista de
/// filas de 60 pt. Mac (`MacCargando`): cajas de cifras y una tabla con cebra de filas de 28 pt.
struct SyncSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Group {
            #if os(macOS)
            macSkeleton
            #else
            phoneSkeleton
            #endif
        }
        .opacity(dim ? 0.5 : 1)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private static let rows: [(CGFloat, CGFloat, CGFloat)] = [
        (0.70, 0.45, 52), (0.55, 0.38, 40), (0.80, 0.50, 58), (0.62, 0.40, 46),
        (0.48, 0.35, 52), (0.74, 0.44, 40), (0.58, 0.42, 56), (0.66, 0.36, 44),
    ]

    #if os(macOS)
    private var macSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach([(0.58, 0.72), (0.50, 0.64), (0.62, 0.58), (0.46, 0.68)], id: \.0) { title, value in
                    VStack(alignment: .leading, spacing: 8) {
                        bar(fraction: title, height: 9, fill: Palette.fill2)
                        bar(fraction: value, height: 20, fill: Palette.fill2)
                        bar(fraction: 0.46, height: 9, fill: Palette.surface2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
                }
            }
            VStack(spacing: 0) {
                HStack { Spacer() }.frame(height: 26)
                    .overlay(alignment: .bottom) { Palette.separator.frame(height: 0.5) }
                ForEach(0..<16, id: \.self) { index in
                    let row = Self.rows[index % Self.rows.count]
                    HStack(spacing: 12) {
                        bar(width: 44, height: 8, fill: Palette.fill2)
                        GeometryReader { proxy in bar(width: proxy.size.width * row.0, height: 8, fill: Palette.fill2) }
                            .frame(height: 8)
                        bar(width: 48, height: 8, fill: Palette.surface2)
                        bar(width: 48, height: 8, fill: Palette.surface2)
                        bar(width: row.2, height: 8, fill: Palette.fill2)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(index.isMultiple(of: 2) ? Palette.background : Palette.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        }
    }
    #else
    private var phoneSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Buscador y segmentado, como los de las listas.
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface2).frame(height: 36)
            Capsule().fill(Palette.surface2).frame(height: 32).padding(.top, 14)
            // Tarjeta de resumen: cifra grande y tres columnas.
            VStack(alignment: .leading, spacing: 12) {
                bar(width: 110, height: 12, fill: Palette.surface2)
                bar(width: 190, height: 28, fill: Palette.surface2)
                Palette.separator.frame(height: 0.5)
                HStack(spacing: 8) {
                    ForEach([(56.0, 76.0), (48.0, 70.0), (60.0, 64.0)], id: \.0) { label, value in
                        VStack(alignment: .leading, spacing: 7) {
                            bar(width: label, height: 10, fill: Palette.surface2)
                            bar(width: value, height: 14, fill: Palette.surface2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .padding(.top, 16)
            bar(width: 120, height: 16, fill: Palette.fill2)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, 26).padding(.bottom, 10)
            // Filas de lista de 60 pt: dos líneas a la izquierda, importe y estado a la derecha, y el chevron.
            VStack(spacing: 0) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 10) {
                        GeometryReader { proxy in
                            VStack(alignment: .leading, spacing: 8) {
                                bar(width: proxy.size.width * row.0, height: 13, fill: Palette.surface2)
                                bar(width: proxy.size.width * row.1, height: 10, fill: Palette.surface2)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            bar(width: 72, height: 13, fill: Palette.surface2)
                            bar(width: row.2, height: 10, fill: Palette.surface2)
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                    }
                    .frame(height: Metrics.rowHeight)
                    .padding(.trailing, 14)
                    .overlay(alignment: .top) { if index > 0 { Palette.separator.frame(height: 0.5) } }
                    .padding(.leading, 16)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
    #endif

    private func bar(width: CGFloat? = nil, fraction: CGFloat? = nil, height: CGFloat, fill: Color) -> some View {
        Group {
            if let fraction {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(fill)
                        .frame(width: proxy.size.width * fraction, height: height)
                }
                .frame(height: height)
            } else {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(fill).frame(width: width, height: height)
            }
        }
    }
}

/// Primera apertura con iCloud en un dispositivo nuevo y todavía sin empresa: mientras llegan los datos se muestra
/// el esqueleto con «Sincronizando con iCloud…», en vez del alta de empresa. Se puede crear una empresa nueva igualmente.
struct SyncLoadingView: View {
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LogoMark(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chirogra").font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                        SyncingPill()
                    }
                }
                SyncSkeleton()
                Text("Estamos trayendo tus libros desde iCloud. Si es la primera vez que usas Chirogra, puedes crear tu empresa.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Button("Crear una empresa nueva", action: onSkip)
                    .buttonStyle(.primaryCompact)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

// MARK: - Sin conexión (`EstadoError`, `MacError`)

/// Aviso de arriba cuando iCloud no responde: los datos siguen en este dispositivo y los cambios se envían solos al
/// volver la conexión. En iPhone e iPad, el grupo «Sin conexión» del canvas sobre un fondo naranja tenue, con
/// «Reintentar» y «Detalles» (la tarjeta con la última sincronización y el detalle técnico). En el Mac, como en
/// `MacError`, la alerta centrada sobre el contenido hasta «Seguir sin conexión»; después, una franja con «Reintentar».
struct SyncErrorBanner: View {
    @State private var monitor = SyncMonitor.shared
    @State private var showingDetails = false
    @State private var dismissed = false
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    var body: some View {
        #if os(macOS)
        if case let .failed(code, network) = monitor.state, !monitor.continuesOffline {
            details(code: code, network: network)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
                .padding(.top, 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        #else
        banner
        #endif
    }

    @ViewBuilder
    private var banner: some View {
        if case let .failed(code, network) = monitor.state, !dismissed {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: "icloud.slash", foreground: Palette.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(network ? String(localized: "Sin conexión") : String(localized: "No pudimos sincronizar"))
                        .font(.body.weight(.semibold))
                    // En `ink` y no en gris: sobre el naranja tenue el gris no llega a 4,5:1.
                    Text("Tus cambios se guardan en este dispositivo y se sincronizan después.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    // Con texto de accesibilidad, uno debajo del otro: lado a lado se partían en sílabas («De-tails»).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { retryLink; detailsLink }
                        VStack(alignment: .leading, spacing: 4) { retryLink; detailsLink }
                    }
                    .font(.body)
                    .buttonStyle(.borderless)
                    // El `foregroundStyle` del aviso pasaba a los botones: sin esto salían en `ink`, no en Tinta.
                    .foregroundStyle(Palette.brand)
                    .frame(minHeight: Metrics.target)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
            .background {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.warningWash))
            }
            .accessibilityElement(children: .contain)
            .padding(.horizontal, margin).padding(.top, 8)
            #if os(iOS)
            // En iOS, hoja centrada: la tarjeta de cristal del popover quedaba sobre la franja y su título apenas se leía.
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

    private var retryLink: some View {
        Button("Reintentar") { monitor.retry() }.fixedSize().frame(minHeight: Metrics.target)
    }

    private var detailsLink: some View {
        Button("Detalles") { showingDetails = true }.fixedSize().frame(minHeight: Metrics.target)
    }

    /// Tarjeta de `MacError`: icono, «No pudimos sincronizar tus datos», el porqué, los datos de la sincronización y
    /// «Reintentar» (principal) sobre «Seguir sin conexión» (secundario).
    private func details(code: String, network: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: Self.iconSize))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(Palette.orange)
                .accessibilityHidden(true)
            Text("No pudimos sincronizar tus datos").font(Self.titleFont).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(network ? String(localized: "Tus cambios están a salvo en este dispositivo y se enviarán solos cuando vuelva la conexión. Revisa tu red.")
                         : String(localized: "Tus cambios están a salvo en este dispositivo. Revisa tu sesión de iCloud en los ajustes del sistema."))
                .font(Self.messageFont).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
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
            .font(Self.messageFont)
            .padding(.horizontal, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Self.rowsRadius, style: .continuous))
            VStack(spacing: 8) {
                retryButton
                continueButton
            }
            .padding(.top, 4)
        }
        .padding(Self.padding)
        #if os(macOS)
        .frame(width: 300)
        #else
        .frame(maxWidth: 480)
        #endif
    }

    #if os(macOS)
    private static let iconSize: CGFloat = 40
    private static let titleFont = Font.headline
    private static let messageFont = Font.subheadline
    private static let rowsRadius: CGFloat = 8
    private static let padding: CGFloat = 16
    #else
    private static let iconSize: CGFloat = 44
    private static let titleFont = Font.title3.weight(.bold)
    private static let messageFont = Font.subheadline
    private static let rowsRadius: CGFloat = 16
    private static let padding: CGFloat = 24
    #endif

    /// Alineado con las tarjetas: margen del iPhone en pantallas compactas.
    private var margin: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? Metrics.gutter : 20
        #else
        20
        #endif
    }

    private var retryButton: some View {
        Button("Reintentar") { showingDetails = false; monitor.retry() }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
    }

    private var continueButton: some View {
        Button("Seguir sin conexión") {
            showingDetails = false
            dismissed = true
            monitor.continuesOffline = true
        }
        .buttonStyle(.secondary)
    }

    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
                value().foregroundStyle(Palette.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.ink2)
                value().foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: Metrics.target)
        .accessibilityElement(children: .combine)
    }
}

#if os(macOS)
/// `MacError` tras «Seguir sin conexión»: una franja fina encima del contenido con «Reintentar», mientras siga sin
/// conexión. Desaparece sola cuando iCloud vuelve a responder.
struct SyncOfflineStrip: View {
    @State private var monitor = SyncMonitor.shared

    var body: some View {
        if monitor.isFailed, monitor.continuesOffline {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash").foregroundStyle(Palette.warning).accessibilityHidden(true)
                Text("Sin conexión con iCloud. Estás trabajando con los datos guardados en este dispositivo.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Reintentar") { monitor.retry() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.body)
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
            .frame(minHeight: 40)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
        }
    }
}
#endif
