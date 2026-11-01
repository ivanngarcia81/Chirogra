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

    var isSyncing: Bool { state == .syncing }

    var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    func apply(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            state = .syncing
        } else if let error = event.error {
            let ckError = error as? CKError
            let network = [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(ckError?.code)
            state = .failed(code: ckError.map { "CKError.\($0.code)" } ?? (error as NSError).domain, network: network)
        } else {
            let date = event.endDate ?? .now
            lastSync = date
            state = .synced(date)
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

// MARK: - Cargando (`MacCargando`)

/// Primera apertura con iCloud en un dispositivo nuevo: mientras llegan los datos se muestra el esqueleto de la
/// pantalla con «Sincronizando con iCloud», en vez del alta de empresa. Se puede crear una empresa nueva igualmente.
struct SyncLoadingView: View {
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LogoMark(size: 34)
                    Text("Chirogra").font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
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
                Group {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                bar(width: 90, height: 10)
                                bar(width: 140, height: 20)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach([0.22, 0.16, 0.26, 0.18, 0.24, 0.14, 0.2, 0.28], id: \.self) { share in
                            VStack(spacing: 0) {
                                Divider()
                                GeometryReader { proxy in
                                    HStack(spacing: 16) {
                                        bar(width: 56, height: 10)
                                        bar(width: proxy.size.width * share, height: 10)
                                        Spacer(minLength: 0)
                                        bar(width: 64, height: 10)
                                        bar(width: 80, height: 18)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .frame(height: 44)
                                .padding(.horizontal, 18)
                            }
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .opacity(dim ? 0.45 : 1)
                .accessibilityHidden(true)
                Text("Estamos trayendo tus libros desde iCloud. Si es la primera vez que usas Chirogra, puedes crear tu empresa.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                Button("Crear una empresa nueva", action: onSkip).font(.body.weight(.semibold)).frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(Palette.surface2).frame(width: width, height: height)
    }
}

// MARK: - Sin conexión (`MacError`)

/// Franja de arriba cuando iCloud no responde: los datos siguen en este dispositivo y los cambios se envían solos
/// al volver la conexión. «Detalles» abre la tarjeta del canvas con la última sincronización y el detalle técnico.
struct SyncErrorBanner: View {
    @State private var monitor = SyncMonitor.shared
    @State private var showingDetails = false
    @State private var dismissed = false

    var body: some View {
        if case let .failed(code, network) = monitor.state, !dismissed {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash").accessibilityHidden(true)
                Text(network ? String(localized: "Sin conexión con iCloud. Estás trabajando con los datos guardados en este dispositivo.")
                             : String(localized: "No pudimos sincronizar con iCloud. Tus datos siguen guardados en este dispositivo."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Detalles") { showingDetails = true }
                    .fontWeight(.semibold)
                    .popover(isPresented: $showingDetails) { details(code: code, network: network) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20).padding(.top, 8)
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
            Text(network ? String(localized: "Tus cambios están a salvo en este dispositivo y se enviarán solos cuando vuelva la conexión. Revisa tu red.")
                         : String(localized: "Tus cambios están a salvo en este dispositivo. Revisa tu sesión de iCloud en los ajustes del sistema."))
                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                LabeledContent("Última sincronización", value: monitor.lastSync?.formatted(.appDateTime.day().month(.abbreviated).hour().minute()) ?? "—")
                    .frame(minHeight: 40)
                Divider()
                LabeledContent("Detalle técnico") { Text(code).font(.caption.monospaced()).foregroundStyle(Palette.ink2) }
                    .frame(minHeight: 40)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("Seguir sin conexión") { showingDetails = false; dismissed = true }
                .buttonStyle(.borderedProminent).tint(Palette.brand).controlSize(.large)
        }
        .padding(24)
        .frame(width: 420)
        .presentationCompactAdaptation(.sheet)
    }
}
