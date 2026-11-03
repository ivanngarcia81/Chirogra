import Foundation
import SwiftData

/// Crea el `ModelContainer` de Chirogra (DISEÑO §6.4 y §6.5).
public enum ChirograStore {
    /// Esquema actual. Los almacenes con un esquema anterior se migran con `ChirograMigrationPlan` al abrirlos.
    public static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }

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
}
