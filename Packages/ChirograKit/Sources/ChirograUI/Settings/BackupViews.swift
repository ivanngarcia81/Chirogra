import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Copia de seguridad de Chirogra (`.chirogra`), declarada en `App/Info.plist` (`UTExportedTypeDeclarations`).
    nonisolated static let chirograBackup = UTType(exportedAs: "com.chirogra.backup", conformingTo: .data)
}

/// El archivo que se guarda con «Crear copia ahora».
nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.chirograBackup]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.damaged }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Avisa a la raíz de que los libros se reemplazaron: rehace la navegación (las pantallas abiertas apuntaban a
/// registros borrados) y muestra «Copia restaurada».
@MainActor
@Observable
final class BooksReplacement {
    static let shared = BooksReplacement()
    private(set) var generation = 0
    var restored: BackupArchive.Info?

    func didRestore(_ info: BackupArchive.Info) {
        restored = info
        generation += 1
    }
}

/// Copias que la app guarda sola antes de restaurar, para poder deshacerlo (las 3 últimas, dentro de la app).
enum SafetyCopies {
    static var directory: URL { URL.applicationSupportDirectory.appending(path: "Copias antes de restaurar", directoryHint: .isDirectory) }

    static func save(_ data: Data, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "Antes de restaurar \(now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))"
            .replacingOccurrences(of: ":", with: "-")
        try data.write(to: directory.appending(path: "\(name).\(BackupArchive.fileExtension)"), options: .atomic)
        for old in all().dropFirst(3) { try? FileManager.default.removeItem(at: old) }
    }

    /// De la más nueva a la más vieja.
    static func all() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == BackupArchive.fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// «Copias de seguridad» de Datos y seguridad (canvas `AjustesDatos`, DISEÑO §6.5), **por empresa** (DATOS-V4 §2):
/// «Crear copia de esta empresa» guarda los libros de la activa con sus recibos en un archivo `.chirogra` (también sirve
/// para entregárselos a un cliente); «Restaurar desde una copia…» la pone **en lugar de la empresa activa** (guardando
/// antes una copia de lo actual, que «Deshacer la restauración» vuelve a poner) o **como empresa nueva** (dentro del
/// límite del plan). Las demás empresas no se tocan.
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @ActiveCompanyQuery private var companies: [Company]
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @AppStorage("lastBackupAt") private var lastBackupAt: Double = 0
    @State private var document: BackupDocument?
    @State private var importing = false
    @State private var pending: PendingRestore?
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var safetyCopy: URL? = SafetyCopies.all().first

    private struct PendingRestore: Identifiable {
        let id = UUID()
        let data: Data
        let info: BackupArchive.Info
        let isUndo: Bool
    }

    private var companyName: String {
        companies.first.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? ""
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        SettingsSection {
            row(systemImage: "externaldrive.fill.badge.plus", color: Palette.green) {
                Button("Crear copia de esta empresa", action: makeBackup)
            }
            row(systemImage: "clock.arrow.circlepath", color: Palette.blue) {
                Button("Restaurar desde una copia…") { importing = true }
            }
            if let safetyCopy {
                row(systemImage: "arrow.uturn.backward", color: Palette.gray) {
                    Button("Deshacer la última restauración") { prepare(url: safetyCopy, isUndo: true) }
                }
            }
        } header: {
            SectionLabel(text: String(localized: "Copias de seguridad"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let savedMessage {
                    Text(savedMessage).foregroundStyle(Palette.positive)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(Palette.negative)
                }
                if lastBackupAt > 0 {
                    Text("Última copia: \(Date(timeIntervalSinceReferenceDate: lastBackupAt).formatted(date: .abbreviated, time: .shortened))")
                }
                Text("Guarda los libros de «\(companyName)», con los recibos, en un archivo .chirogra que puedes restaurar en cualquier aparato con Chirogra, sin depender de iCloud. Cada empresa tiene su copia.")
            }
        }
        .buttonStyle(.borderless)
        .fileExporter(isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } }),
                      document: document, contentType: .chirograBackup,
                      defaultFilename: BackupArchive.suggestedFilename(companyName: companyName)) { result in
            switch result {
            case .success:
                lastBackupAt = Date().timeIntervalSinceReferenceDate
                errorMessage = nil
                savedMessage = String(localized: "Copia guardada.")
            case .failure(let error):
                savedMessage = nil
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.chirograBackup]) { result in
            guard case .success(let url) = result else { return }
            prepare(url: url, isUndo: false)
        }
        .alert("¿Deshacer la restauración?",
               isPresented: Binding(get: { pending?.isUndo == true }, set: { if !$0 { pending = nil } }), presenting: pending) { pending in
            Button("Deshacer", role: .destructive) { restore(pending, mode: .replaceCompany(nil)) }
            Button("Cancelar", role: .cancel) {}
        } message: { pending in
            Text(confirmation(for: pending))
        }
        // Una copia elegida: en lugar de la empresa activa o como otra empresa.
        .alert("¿Restaurar esta copia?",
               isPresented: Binding(get: { pending.map { !$0.isUndo } ?? false }, set: { if !$0 { pending = nil } }),
               presenting: pending) { pending in
            Button("Sustituir «\(companyName)»", role: .destructive) { restore(pending, mode: .replaceCompany(nil)) }
            Button("Restaurar como empresa nueva") { restore(pending, mode: .newCompany) }
            Button("Cancelar", role: .cancel) {}
        } message: { pending in
            Text(confirmation(for: pending))
        }
        #if DEBUG
        // `-qa.copia <ruta>` escribe una copia en la ruta (sin el panel de guardar); `-qa.restaurar <ruta>` abre la
        // confirmación de restaurar ese archivo, como al elegirlo.
        .task {
            let defaults = UserDefaults.standard
            if let path = defaults.string(forKey: "qa.copia") {
                do {
                    try BackupArchive.make(from: context, appVersion: Self.appVersion).write(to: URL(filePath: path))
                    savedMessage = String(localized: "Copia guardada.")
                } catch { errorMessage = error.localizedDescription }
            }
            if let path = defaults.string(forKey: "qa.restaurar") { prepare(url: URL(filePath: path), isUndo: false) }
        }
        #endif
    }

    private func row(systemImage: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, foreground: color)
            content().foregroundStyle(Palette.brand)
            Spacer(minLength: 0)
        }
    }

    private func confirmation(for pending: PendingRestore) -> String {
        let info = pending.info
        let when = info.createdAt.formatted(date: .abbreviated, time: .shortened)
        let source = info.companyName.isEmpty ? String(localized: "Copia del \(when)") : String(localized: "«\(info.companyName)», copia del \(when)")
        if pending.isUndo {
            let scope = iCloudSyncEnabled
                ? String(localized: "Los libros de «\(companyName)» vuelven a ser los de antes de restaurar, también en tus otros aparatos con iCloud.")
                : String(localized: "Los libros de «\(companyName)» vuelven a ser los de antes de restaurar.")
            return "\(source) · \(String(localized: "\(info.recordCount) registros")). \(scope)"
        }
        let replace = iCloudSyncEnabled
            ? String(localized: "Al sustituir, los libros de «\(companyName)» se reemplazan en este aparato y en tus otros aparatos con iCloud; antes se guarda una copia para poder deshacerlo.")
            : String(localized: "Al sustituir, los libros de «\(companyName)» se reemplazan; antes se guarda una copia para poder deshacerlo.")
        let others = String(localized: "Como empresa nueva, se añade junto a las que ya tienes. Las demás empresas no se tocan.")
        return "\(source) · \(String(localized: "\(info.recordCount) registros")). \(replace) \(others)"
    }

    private func makeBackup() {
        savedMessage = nil
        do {
            document = BackupDocument(data: try BackupArchive.make(from: context, appVersion: Self.appVersion))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepare(url: URL, isUndo: Bool) {
        savedMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = PendingRestore(data: data, info: try BackupArchive.info(of: data), isUndo: isUndo)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ pending: PendingRestore, mode: BackupArchive.RestoreMode) {
        do {
            // Antes de sustituir la empresa activa, una copia de ella para poder deshacerlo (como empresa nueva no hace
            // falta: no se pierde nada).
            if !pending.isUndo, case .replaceCompany = mode {
                try SafetyCopies.save(try BackupArchive.make(from: context, appVersion: Self.appVersion))
            }
            let result = try BackupArchive.restoreCompany(pending.data, into: context, mode: mode)
            if pending.isUndo, let used = safetyCopy { try? FileManager.default.removeItem(at: used) }
            safetyCopy = SafetyCopies.all().first
            errorMessage = nil
            BooksReplacement.shared.didRestore(result.info)
        } catch BookkeepingError.companyLimitReached {
            // Como empresa nueva no cabe en el plan: el plan para contadores (o por qué no se puede).
            CompanyHub.shared.requestAdd(in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
