import ChirograData
import Foundation
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

    @Test func librosLocalesDeAntesSiguenSinICloud() throws {
        let (defaults, url) = scratch()
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
        // Ya fijado: aunque el almacén desaparezca, no cambia.
        try FileManager.default.removeItem(at: url)
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }

    @Test func elegidoAntesNoSeToca() {
        let (defaults, url) = scratch()
        defaults.set(false, forKey: ChirograStore.syncEnabledKey)
        #expect(!ChirograStore.resolveSyncPreference(defaults: defaults, storeURL: url))
    }
}
