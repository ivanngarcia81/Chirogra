import Foundation
import SwiftData

/// Crea el `ModelContainer` de Chirogra (DISEÑO §6.4 y §6.5).
public enum ChirograStore {
    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    /// - Parameters:
    ///   - inMemory: para pruebas y vistas previas.
    ///   - cloudKitContainer: identificador `iCloud.…` para sincronizar con la base privada del usuario;
    ///     `nil` = 100 % local. Requiere la capacidad de iCloud firmada en la app.
    public static func makeContainer(inMemory: Bool = false, cloudKitContainer: String? = nil) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Chirogra",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitContainer.map { .private($0) } ?? .none
        )
        return try ModelContainer(for: schema, migrationPlan: ChirograMigrationPlan.self, configurations: configuration)
    }
}
