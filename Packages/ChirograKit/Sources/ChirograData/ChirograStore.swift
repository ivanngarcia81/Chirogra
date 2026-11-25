import Foundation
import SwiftData

/// Crea el `ModelContainer` de Chirogra (DISEÑO §6.4 y §6.5).
public enum ChirograStore {
    /// Esquema actual. Los almacenes con un esquema anterior se migran con `ChirograMigrationPlan` al abrirlos.
    public static var schema: Schema { Schema(versionedSchema: SchemaV6.self) }

    /// Clave de `UserDefaults` del interruptor «Sincronizar con iCloud» (por aparato; la leen la app y Ajustes).
    public static let syncEnabledKey = "iCloudSyncEnabled"

    /// Si al abrir con iCloud el contenedor falló y la app abrió el mismo almacén solo en local (`ChirograApp`), el
    /// detalle del error («NSCocoaErrorDomain 134060»). Los libros están enteros y lo que se cambie queda en el historial
    /// del almacén, que iCloud sube la próxima vez que abra bien; la franja de iCloud lo dice (`SyncMonitor`) en vez de
    /// aparentar que sincroniza (auditoría del 23-nov).
    @MainActor public static var cloudKitOpenFailure: String?

    /// Archivo del almacén de siempre (`Application Support/Chirogra.store`).
    public static var defaultStoreURL: URL { ModelConfiguration("Chirogra", schema: schema).url }

    /// Fija el valor inicial del interruptor de iCloud la primera vez, antes de abrir el almacén:
    /// - aparato sin libros (sin almacén, o con el almacén vacío de quien abrió la app sin terminar el alta):
    ///   **encendido**, así un segundo aparato espera los libros del primero (`SyncLoadingView`) en vez de pedir el
    ///   alta y mezclar dos libros al encender iCloud después;
    /// - aparato con libros locales de antes que nunca tocó el interruptor: **apagado**, como estaba (encenderlo
    ///   subiría esos libros y los mezclaría con los de iCloud).
    /// Si el interruptor ya tiene valor (también uno pasado como argumento de arranque), no lo toca.
    /// - Returns: si la sincronización queda encendida.
    @discardableResult
    public static func resolveSyncPreference(defaults: UserDefaults = .standard, storeURL: URL = defaultStoreURL) -> Bool {
        if defaults.object(forKey: syncEnabledKey) == nil {
            defaults.set(!hasLocalBooks(at: storeURL), forKey: syncEnabledKey)
        }
        return defaults.bool(forKey: syncEnabledKey)
    }

    /// El almacén existe y tiene alguna empresa. Se abre solo en local (sin CloudKit) y se suelta al volver. Si no se
    /// puede abrir, se da por hecho que sí hay libros: mejor dejar iCloud apagado que arriesgar una mezcla.
    static func hasLocalBooks(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        do {
            let container = try makeContainer(url: url)
            return try ModelContext(container).fetchCount(FetchDescriptor<Company>()) > 0
        } catch {
            return true
        }
    }

    /// - Parameters:
    ///   - inMemory: para pruebas y vistas previas.
    ///   - cloudKitContainer: identificador `iCloud.…` para sincronizar con la base privada del usuario;
    ///     `nil` = 100 % local. Requiere la capacidad de iCloud firmada en la app.
    ///   - url: archivo del almacén; `nil` = el de siempre (pruebas de migración).
    public static func makeContainer(inMemory: Bool = false, cloudKitContainer: String? = nil, url: URL? = nil) throws -> ModelContainer {
        let database: ModelConfiguration.CloudKitDatabase = cloudKitContainer.map { .private($0) } ?? .none
        let configuration = if let url {
            ModelConfiguration("Chirogra", schema: schema, url: url, cloudKitDatabase: database)
        } else {
            ModelConfiguration("Chirogra", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        }
        return try ModelContainer(for: schema, migrationPlan: ChirograMigrationPlan.self, configurations: configuration)
    }

    /// Aparta el almacén que no se abre (pantalla de recuperación, `StoreRecoveryView`): mueve `Chirogra.store` con sus
    /// `-shm` y `-wal` y lo que CloudKit guarda al lado (`Chirogra_ckAssets`, `.Chirogra_SUPPORT`) a una carpeta nueva
    /// «Chirogra apartado <fecha>» en la misma carpeta. No borra nada: la app abre después un almacén nuevo (con iCloud,
    /// los libros vuelven a bajar). - Returns: la carpeta con lo apartado.
    @discardableResult
    public static func setAsideStore(at url: URL = defaultStoreURL, now: Date = .now, fileManager: FileManager = .default) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let stamp = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        let destination = directory.appending(path: "\(name) apartado \(stamp)", directoryHint: .isDirectory)
        let items = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { item in
            let file = item.lastPathComponent
            return file.hasPrefix(url.lastPathComponent) || file.hasPrefix("\(name)_ckAssets") || file.hasPrefix(".\(name)_SUPPORT")
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in items {
            try fileManager.moveItem(at: item, to: destination.appending(path: item.lastPathComponent))
        }
        return destination
    }
}
