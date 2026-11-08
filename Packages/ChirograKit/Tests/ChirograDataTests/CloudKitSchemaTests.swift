import CoreData
import SwiftData
import Testing
@testable import ChirograData

@Suite("Esquema de CloudKit")
struct CloudKitSchemaTests {
    @Test("El modelo de Core Data del esquema actual cumple las reglas de CloudKit")
    func modelFollowsCloudKitRules() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV3.models))
        #expect(model.entities.count == SchemaV3.models.count)
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship != nil, "\(entity.name ?? "").\(relationship.name) sin inversa")
                #expect(relationship.isOptional, "\(entity.name ?? "").\(relationship.name) no es opcional")
                #expect(relationship.deleteRule != .denyDeleteRule, "\(entity.name ?? "").\(relationship.name) con .deny")
            }
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        "\(entity.name ?? "").\(attribute.name) sin valor por defecto")
            }
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "") con restricciones de unicidad")
        }
    }

    /// Core Data guarda cada propiedad en CloudKit como `CD_<nombre>` y pone en todos los registros sus propios campos
    /// `CD_…`. Una propiedad con el nombre de uno de ellos lo pisa: con `entityName` (esquema 2) el valor llegaba vacío a
    /// los otros aparatos y producción rechazaba la subida entera (SchemaV3.swift).
    @Test("Ninguna propiedad usa un nombre que Core Data reserva en CloudKit")
    func noReservedFieldNames() throws {
        let reserved: Set<String> = ["entityName", "moveReceipt", "recordName", "recordID", "recordType"]
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV3.models))
        for entity in model.entities {
            for name in entity.propertiesByName.keys {
                #expect(!reserved.contains(name), "\(entity.name ?? "").\(name) choca con un campo reservado de CloudKit")
            }
        }
    }

    /// Con CloudKit, Core Data no deja renombrar propiedades al migrar («Properties cannot be renamed in stores that are
    /// used with CloudKit»): `subjectEntity` es una propiedad nueva y el valor lo copia la migración a medida.
    @Test("El historial guarda la entidad en subjectEntity, sin renombrar ninguna propiedad")
    func auditEventSubject() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV3.models))
        let audit = try #require(model.entitiesByName["AuditEvent"])
        #expect(audit.attributesByName["subjectEntity"] != nil)
        #expect(audit.attributesByName["entityName"] == nil)
        for entity in model.entities {
            for (name, property) in entity.propertiesByName {
                #expect(property.renamingIdentifier == nil || property.renamingIdentifier == name,
                        "\(entity.name ?? "").\(name) renombrada: CloudKit no lo admite")
            }
        }
    }
}
