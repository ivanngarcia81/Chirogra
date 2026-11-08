import Foundation
import SwiftData

// Esquema 3.0.0 (7-nov-2026, versión 1.0.1): un solo cambio sobre `SchemaV2`, en `AuditEvent`.
//
// La propiedad `entityName` se guardaba en CloudKit como el campo `CD_entityName`, que es el mismo que Core Data pone
// en **todos** los registros para anotar su entidad. Los dos chocaban: en el entorno de desarrollo el valor llegaba
// vacío a los otros aparatos, y en producción CloudKit rechazaba el registro («Cannot create or modify field
// 'CD_entityName' in record 'CD_AuditEvent' in production schema») y con él todo el lote, así que iCloud no subía nada.
// Ahora se guarda como `subjectEntity` (`CD_subjectEntity`). No puede ser un cambio de nombre (`originalName`): Core Data
// no deja renombrar propiedades en un almacén con CloudKit («Properties cannot be renamed in stores that are used with
// CloudKit»). Así que `entityName` se quita, `subjectEntity` se añade y la migración es a medida (`migrateV2toV3`):
// antes de migrar se leen los valores y después se escriben en la propiedad nueva, lo que además los sube a iCloud.
// `CloudKitSchemaTests` impide volver a usar un nombre reservado.
//
// Los demás modelos son los de `SchemaV2`, sin cambios: este esquema los reutiliza. Las copias de seguridad siguen
// guardando el campo con la clave `entityName` (`scripts/gen-backup.py`), así que el formato no cambia.
//
// CONGELADO desde el esquema 4 (7-nov-2026): `AuditEvent` solo lleva sus propiedades guardadas; la app usa el de
// `SchemaV4`. No cambiar nada aquí (`FrozenSchemaTests`).

public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV2.models.map { ObjectIdentifier($0) == ObjectIdentifier(SchemaV2.AuditEvent.self) ? AuditEvent.self : $0 }
    }

    @Model
    public final class AuditEvent {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var actor: String = ""
        /// La entidad a la que se refiere el evento («Company», «Invoice»…). Antes `entityName` (ver arriba).
        public var subjectEntity: String = ""
        public var entityID: UUID?
        public var action: String = ""
        public var summary: String = ""

        public init() {}
    }
}

/// Los valores de `AuditEvent.entityName` entre `willMigrate` (esquema 2) y `didMigrate` (esquema 3).
final class AuditSubjectCarry: @unchecked Sendable {
    static let shared = AuditSubjectCarry()
    private let lock = NSLock()
    private var subjects: [UUID: String] = [:]

    func keep(_ values: [UUID: String]) { lock.withLock { subjects = values } }
    func take() -> [UUID: String] { lock.withLock { defer { subjects = [:] }; return subjects } }
}

extension ChirograMigrationPlan {
    /// A medida: guarda la entidad de cada evento del historial antes de migrar y la escribe en `subjectEntity` después
    /// (la propiedad cambia de nombre, pero con CloudKit no se puede renombrar; ver arriba).
    public static var migrateV2toV3: MigrationStage {
        .custom(fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: { context in
            var values: [UUID: String] = [:]
            for event in try context.fetch(FetchDescriptor<SchemaV2.AuditEvent>()) where !event.entityName.isEmpty {
                values[event.id] = event.entityName
            }
            AuditSubjectCarry.shared.keep(values)
        }, didMigrate: { context in
            let values = AuditSubjectCarry.shared.take()
            guard !values.isEmpty else { return }
            for event in try context.fetch(FetchDescriptor<SchemaV3.AuditEvent>()) {
                if let subject = values[event.id] { event.subjectEntity = subject }
            }
            try context.save()
        })
    }
}
