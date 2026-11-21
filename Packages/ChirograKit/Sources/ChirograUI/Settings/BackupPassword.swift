import ChirograData
import SwiftUI

// MARK: - Contraseña de la copia (revisión externa del 21-nov; decisión del usuario: opcional, marcada de entrada)
//
// Al crear una copia `.chirogra` (Ajustes, la lista de empresas y el panel de clientes) sale `BackupPasswordSheet`:
// «Proteger con contraseña» viene encendido; apagarlo deja la copia como antes. Al abrir una copia con contraseña
// (restaurar, importar la de un cliente), `backupUnlockAlert` la pide antes de leerla. La contraseña no se guarda en
// ningún sitio: solo cifra el archivo (`BackupArchive.encrypt`, `Backup+Encryption.swift`).

/// Una copia por crear: de qué empresa y cómo se sacan sus datos.
struct BackupRequest: Identifiable {
    let id = UUID()
    let companyName: String
    let make: @MainActor () throws -> Data
}

/// Una copia con contraseña elegida para abrir, y qué hacer con ella ya abierta.
struct LockedBackup: Identifiable {
    let id = UUID()
    let data: Data
    let open: @MainActor (Data) -> Void
}

extension BackupArchive {
    /// Mínimo de caracteres de la contraseña de una copia.
    static let minimumPasswordLength = 8
}

extension View {
    /// Hoja de la contraseña al crear una copia; con el archivo listo (cifrado o no), `onReady`.
    func backupPasswordSheet(_ request: Binding<BackupRequest?>, onReady: @escaping (BackupDocument) -> Void,
                             onError: @escaping (Error) -> Void) -> some View {
        sheet(item: request) { request in
            BackupPasswordSheet(companyName: request.companyName) { password in
                Task { @MainActor in
                    // Que la hoja termine de cerrarse antes de abrir el panel de guardar (en el iPhone no se presenta
                    // una cosa mientras otra se va).
                    try? await Task.sleep(for: .milliseconds(450))
                    do {
                        let data = try request.make()
                        guard let password else { return onReady(BackupDocument(data: data)) }
                        // PBKDF2 tarda unas décimas: fuera del hilo principal.
                        let locked = try await Task.detached(priority: .userInitiated) {
                            try BackupArchive.encrypt(data, password: password)
                        }.value
                        onReady(BackupDocument(data: locked))
                    } catch {
                        onError(error)
                    }
                }
            }
        }
    }

    /// Pide la contraseña de una copia cifrada; con la correcta, `locked.open` recibe la copia abierta.
    func backupUnlockAlert(_ locked: Binding<LockedBackup?>) -> some View {
        modifier(BackupUnlockModifier(locked: locked))
    }
}

/// «Proteger con contraseña» (encendido de entrada), la contraseña dos veces y el aviso de que no se puede recuperar.
struct BackupPasswordSheet: View {
    let companyName: String
    let onCreate: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var protect = true
    @State private var password = ""
    @State private var repeated = ""

    private var tooShort: Bool { password.count < BackupArchive.minimumPasswordLength }
    private var mismatch: Bool { !repeated.isEmpty && repeated != password }
    private var canCreate: Bool { !protect || (!tooShort && password == repeated) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Proteger con contraseña", isOn: $protect.animation())
                } footer: {
                    Text("La copia lleva tus libros, los recibos y los W-9 de tus proveedores. Con contraseña, nadie puede abrirla sin ella, aunque la guardes en iCloud Drive o la mandes por correo.")
                }
                if protect {
                    Section {
                        SecureField("Contraseña", text: $password)
                            .passwordContentType()
                        SecureField("Repite la contraseña", text: $repeated)
                            .passwordContentType()
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if mismatch {
                                Text("Las dos contraseñas no coinciden.").foregroundStyle(Palette.negative)
                            } else if !password.isEmpty && tooShort {
                                Text("Al menos \(BackupArchive.minimumPasswordLength) caracteres.").foregroundStyle(Palette.ink2)
                            }
                            Text("Si la olvidas, esta copia no se podrá abrir: nadie puede recuperarla, tampoco nosotros. Guárdala en un sitio seguro.")
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(companyName.isEmpty ? String(localized: "Crear copia") : String(localized: "Copia de «\(companyName)»"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear copia") {
                        let chosen = protect ? password : nil
                        dismiss()
                        onCreate(chosen)
                    }
                    .disabled(!canCreate)
                }
            }
        }
        // Hoja pequeña (no `editorSheetSizing`, que en el iPad la haría de página entera).
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }
}

private extension View {
    @ViewBuilder func passwordContentType() -> some View {
        #if os(iOS)
        textContentType(.newPassword)
        #else
        self
        #endif
    }
}

/// Alerta «Esta copia tiene contraseña» con el campo; si no es la correcta, vuelve a salir con el aviso.
private struct BackupUnlockModifier: ViewModifier {
    @Binding var locked: LockedBackup?
    @State private var password = ""
    @State private var wrong = false
    @State private var opening = false

    func body(content: Content) -> some View {
        content
            .alert(wrong ? String(localized: "La contraseña no es correcta") : String(localized: "Esta copia tiene contraseña"),
                   isPresented: Binding(get: { locked != nil && !opening }, set: { if !$0 && !opening { locked = nil; password = ""; wrong = false } }),
                   presenting: locked) { backup in
                SecureField("Contraseña", text: $password)
                Button("Abrir") { open(backup) }
                Button("Cancelar", role: .cancel) {}
            } message: { _ in
                Text(wrong ? String(localized: "Prueba otra vez. Sin la contraseña con que se creó, la copia no se puede abrir.")
                           : String(localized: "Escribe la contraseña con que se creó la copia."))
            }
    }

    private func open(_ backup: LockedBackup) {
        let typed = password
        opening = true
        Task {
            let opened = try? await Task.detached(priority: .userInitiated) {
                try BackupArchive.decrypt(backup.data, password: typed)
            }.value
            opening = false
            password = ""
            if let opened {
                wrong = false
                locked = nil
                backup.open(opened)
            } else {
                wrong = true
            }
        }
    }
}
