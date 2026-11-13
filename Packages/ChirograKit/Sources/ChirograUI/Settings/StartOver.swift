import ChirograData
import SwiftData
import SwiftUI

/// «Borrar todo y empezar de cero» (1.2, build 42; pedido del usuario el 13-nov: lo que borraba volvía de iCloud).
///
/// - Ajustes › iCloud y copias tiene la acción (`StartOverSection`) cuando los libros no son los de ejemplo (para esos
///   está «Empezar con mi empresa», `SampleBooksSection`).
/// - La raíz pide confirmarlo escribiendo «BORRAR» (`startOverFlow`), borra todos los libros (`BackupArchive.eraseAll`,
///   que apunta las empresas en `DeletedCompanies` para que ningún aparato atrasado las vuelva a subir) y, con iCloud,
///   no dice «listo» hasta que el borrado haya subido (`SyncMonitor.lastExportStart`); sin conexión, avisa de que se
///   subirá al volver a tenerla. Después sale el alta «Creemos tu empresa», como tras «Empezar con mi empresa».
@MainActor
@Observable
final class StartOver {
    static let shared = StartOver()

    enum Phase: Equatable {
        case idle
        /// Borrado en este aparato; esperando a que suba a iCloud.
        case uploading
        /// `uploaded`: ya está en iCloud; si no, se subirá al volver la conexión.
        case finished(uploaded: Bool)
    }

    /// La confirmación a la vista (la presenta la raíz).
    var isConfirming = false
    var phase: Phase = .idle
    var errorMessage: String?

    func confirm() { isConfirming = true }

    /// Lo que hay que escribir para confirmar.
    static var confirmationWord: String { String(localized: "BORRAR") }

    /// Cuánto se espera a la subida antes de darla por pendiente.
    static let uploadTimeout: Duration = .seconds(45)
}

/// La sección de Ajustes › iCloud y copias, al final (lo más destructivo, abajo del todo).
struct StartOverSection: View {
    @Query private var companies: [Company]
    @Query(filter: SampleData.sampleCreationsPredicate) private var sampleCreations: [AuditEvent]

    var body: some View {
        if !companies.isEmpty, !SampleData.isSample(companies: companies, sampleCreations: sampleCreations) {
            SettingsSection {
                HStack(spacing: 12) {
                    IconTile(systemImage: "trash.fill", foreground: Palette.negative)
                    Button("Borrar todo y empezar de cero…") { StartOver.shared.confirm() }
                        .foregroundStyle(Palette.negative)
                    Spacer(minLength: 0)
                }
                .buttonStyle(.borderless)
            } header: {
                SectionLabel(text: String(localized: "Empezar de cero"))
            } footer: {
                Text(DeletedCompanies.isEnabled
                     ? String(localized: "Borra todas tus empresas con sus libros, también en iCloud y en tus otros aparatos, y vuelve al alta. Para borrar una sola, usa Empresas.")
                     : String(localized: "Borra todas tus empresas con sus libros y vuelve al alta. Para borrar una sola, usa Empresas."))
            }
        }
    }
}

extension View {
    /// En la raíz: la confirmación de «Borrar todo y empezar de cero», el borrado y la espera a iCloud. `onErase` se
    /// llama después de borrar (la raíz deja de esperar a iCloud para mostrar el alta).
    func startOverFlow(onErase: @escaping () -> Void) -> some View {
        modifier(StartOverFlow(onErase: onErase))
    }
}

private struct StartOverFlow: ViewModifier {
    let onErase: () -> Void
    @Environment(\.modelContext) private var context
    @State private var startOver = StartOver.shared
    @State private var typed = ""
    @Query private var companies: [Company]

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(StartOver.confirmationWord, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func body(content: Content) -> some View {
        content
            .alert("¿Borrar todos tus libros?", isPresented: $startOver.isConfirming) {
                TextField(StartOver.confirmationWord, text: $typed)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                Button("Borrar todo", role: .destructive, action: erase)
                    .disabled(!matches)
                Button("Cancelar", role: .cancel) { typed = "" }
            } message: {
                Text(message)
            }
            .alert("No se pudo borrar",
                   isPresented: Binding(get: { startOver.errorMessage != nil }, set: { if !$0 { startOver.errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(startOver.errorMessage ?? "")
            }
            // Sin empresas no hay nada que borrar (otro aparato pudo borrarlo todo con la confirmación abierta).
            .onChange(of: companies.isEmpty) { _, empty in if empty { startOver.isConfirming = false; typed = "" } }
            .sheet(isPresented: Binding(get: { startOver.phase != .idle }, set: { if !$0 { startOver.phase = .idle } })) {
                StartOverProgress(phase: startOver.phase) { startOver.phase = .idle }
                    .interactiveDismissDisabled(startOver.phase == .uploading)
            }
            #if DEBUG
            // `-qa.empezarDeCero 1` (solo Debug): abre la confirmación; `subiendo`, `listo` o `pendiente` muestran la hoja
            // en ese estado, sin borrar nada.
            .task {
                guard let mode = UserDefaults.standard.string(forKey: "qa.empezarDeCero") else { return }
                try? await Task.sleep(for: .milliseconds(900))
                switch mode {
                case "subiendo": startOver.phase = .uploading
                case "listo": startOver.phase = .finished(uploaded: true)
                case "pendiente": startOver.phase = .finished(uploaded: false)
                default: if !companies.isEmpty { startOver.confirm() }
                }
            }
            #endif
    }

    private var message: String {
        let names = companies.map(\.shownName).sorted().formatted(.list(type: .and))
        let what = companies.count == 1
            ? String(localized: "Se borra «\(names)» con sus clientes, proveedores, facturas, gastos, asientos, recibos y ajustes.")
            : String(localized: "Se borran todas tus empresas (\(names)) con sus clientes, proveedores, facturas, gastos, asientos, recibos y ajustes.")
        let scope = DeletedCompanies.isEnabled ? " " + String(localized: "También se borran en iCloud y en tus otros aparatos.") : ""
        let warning = String(localized: "No se puede deshacer: si quieres conservar algo, crea antes una copia de cada empresa.")
        let instruction = String(localized: "Escribe \(StartOver.confirmationWord) para confirmar.")
        return what + scope + " " + warning + " " + instruction
    }

    private func erase() {
        guard matches else { return }
        typed = ""
        let erasedAt = Date()
        do {
            try BackupArchive.eraseAll(in: context)
        } catch {
            startOver.errorMessage = error.localizedDescription
            return
        }
        onErase()
        guard DeletedCompanies.isEnabled else { return }
        startOver.phase = .uploading
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now + StartOver.uploadTimeout
            while clock.now < deadline {
                if let start = SyncMonitor.shared.lastExportStart, start >= erasedAt {
                    startOver.phase = .finished(uploaded: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            startOver.phase = .finished(uploaded: false)
        }
    }
}

/// La hoja mientras el borrado sube a iCloud, y su resultado.
private struct StartOverProgress: View {
    let phase: StartOver.Phase
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .uploading, .idle:
                ProgressView()
                    .controlSize(.large)
                Text("Borrando en iCloud…")
                    .font(.headline)
                Text("Deja la app abierta un momento: el borrado está subiendo a iCloud para que tus otros aparatos también lo borren.")
            case .finished(let uploaded):
                Image(systemName: uploaded ? "checkmark.icloud.fill" : "icloud.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(uploaded ? Palette.positive : Palette.ink2)
                    .accessibilityHidden(true)
                Text(uploaded ? String(localized: "Listo: se borró también en iCloud") : String(localized: "Borrado en este aparato"))
                    .font(.headline)
                Text(uploaded
                     ? String(localized: "Tus otros aparatos lo borran en cuanto abran Chirogra con conexión. Ya puedes crear tu empresa.")
                     : String(localized: "Todavía no se pudo subir a iCloud (¿sin conexión?). Se subirá solo en cuanto haya conexión con la app abierta, y tus otros aparatos lo borrarán aunque lo tuvieran guardado."))
                Button("Continuar", action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.brand)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Palette.ink)
        .padding(28)
        .frame(maxWidth: 420)
        .presentationDetents([.medium])
    }
}
