import ChirograData
import Foundation
import SwiftData
import Testing

/// Valor inicial del interruptor de iCloud (`ChirograStore.resolveSyncPreference`).
struct SyncPreferenceTests {
    private func scratch() -> (UserDefaults, URL) {
        let suite = "SyncPreferenceTests.\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appending(path: "\(suite).store")
        return (UserDefaults(suiteName: suite)!, url)
    }

    @Test func aparatoNuevoEnciendeICloud() {
        let (defaults, url) = scratch()
        #expect(ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
        #expect(defaults.object(forKey: ChirograStore.syncEnabledKey) as? Bool == true)
    }

    @MainActor @Test func librosLocalesDeAntesSiguenSinICloud() throws {
        let (defaults, url) = scratch()
        defer { removeStore(url) }
        do {
            let container = try ChirograStore.makeContainer(url: url)
            try Bookkeeper(context: ModelContext(container)).setUpCompany(legalName: "Taller Luna LLC")
        }
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
        // Ya fijado: aunque el almacén desaparezca, no cambia.
        removeStore(url)
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }

    /// Quien abrió la app y no terminó el alta (o borró los datos de ejemplo) tiene el almacén, pero sin empresa.
    @Test func almacenVacioEnciendeICloud() throws {
        let (defaults, url) = scratch()
        defer { removeStore(url) }
        _ = try ChirograStore.makeContainer(url: url)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }

    /// Un archivo que no se puede abrir cuenta como libros: no se arriesga una mezcla.
    @Test func almacenIlegibleSigueSinICloud() throws {
        let (defaults, url) = scratch()
        defer { removeStore(url) }
        try Data("no es una base".utf8).write(to: url)
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }

    private func removeStore(_ url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
        }
    }

    @Test func elegidoAntesNoSeToca() {
        let (defaults, url) = scratch()
        defaults.set(false, forKey: ChirograStore.syncEnabledKey)
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }
}
