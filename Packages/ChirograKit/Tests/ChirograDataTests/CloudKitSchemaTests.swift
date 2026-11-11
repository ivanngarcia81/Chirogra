import CoreData
import SwiftData
import Testing
@testable import ChirograData

@Suite("Esquema de CloudKit")
struct CloudKitSchemaTests {
    @Test("El modelo de Core Data del esquema actual cumple las reglas de CloudKit")
    func modelFollowsCloudKitRules() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV5.models))
        #expect(model.entities.count == SchemaV5.models.count)
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
        // Los campos que Core Data pone en cada registro de CloudKit, y nombres de `NSObject`/`NSManagedObject` que no
        // pueden ser propiedades de una entidad (esquema 4: también `description`).
        let reserved: Set<String> = ["entityName", "moveReceipt", "recordName", "recordID", "recordType",
                                     "description", "debugDescription", "hash", "superclass", "className", "objectID", "entity",
                                     "managedObjectContext", "isFault", "isDeleted", "isInserted", "isUpdated", "hasChanges",
                                     "changedValues", "faultingState", "hasPersistentChangedValues", "self", "zone"]
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV5.models))
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
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV5.models))
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

    /// En Producción solo se puede **añadir** (7-nov-2026): ninguna propiedad de un esquema desaparece ni cambia de tipo
    /// en el siguiente, y lo nuevo es opcional o tiene valor por defecto (lo comprueba `modelFollowsCloudKitRules`).
    static func expectOnlyAdds(from oldModels: [any PersistentModel.Type], to newModels: [any PersistentModel.Type]) throws -> (old: NSManagedObjectModel, new: NSManagedObjectModel) {
        let old = try #require(NSManagedObjectModel.makeManagedObjectModel(for: oldModels))
        let new = try #require(NSManagedObjectModel.makeManagedObjectModel(for: newModels))
        for entity in old.entities {
            let name = try #require(entity.name)
            let current = try #require(new.entitiesByName[name], "falta la entidad \(name)")
            for (property, attribute) in entity.attributesByName {
                let now = current.attributesByName[property]
                #expect(now?.attributeType == attribute.attributeType, "\(name).\(property) cambió o falta")
                #expect(now?.allowsExternalBinaryDataStorage == attribute.allowsExternalBinaryDataStorage, "\(name).\(property)")
            }
            for (property, relationship) in entity.relationshipsByName {
                let now = current.relationshipsByName[property]
                #expect(now?.destinationEntity?.name == relationship.destinationEntity?.name, "\(name).\(property) cambió o falta")
                #expect(now?.isToMany == relationship.isToMany, "\(name).\(property)")
                #expect(now?.inverseRelationship?.name == relationship.inverseRelationship?.name, "\(name).\(property)")
            }
        }
        return (old, new)
    }

    @Test("El esquema 4 solo añade: nada del 3 se quita, se renombra ni cambia de tipo")
    func schema4OnlyAdds() throws {
        let (old, new) = try Self.expectOnlyAdds(from: SchemaV3.models, to: SchemaV4.models)
        // Todos los modelos salvo Company llevan la empresa.
        for entity in new.entities where entity.name != "Company" {
            #expect(entity.attributesByName["companyID"]?.attributeType == .UUIDAttributeType, "\(entity.name ?? "")")
        }
        #expect(Set(new.entities.compactMap(\.name)).subtracting(old.entities.compactMap(\.name))
                == ["BankTransaction", "BankRule", "BankImportProfile", "Reconciliation", "Budget", "BudgetLine"])
    }

    @Test("El esquema 5 solo añade: tres propiedades de texto con valor por defecto y ninguna entidad nueva")
    func schema5OnlyAdds() throws {
        let (old, new) = try Self.expectOnlyAdds(from: SchemaV4.models, to: SchemaV5.models)
        #expect(Set(new.entities.compactMap(\.name)) == Set(old.entities.compactMap(\.name)))
        var added: [String] = []
        for entity in new.entities {
            let name = try #require(entity.name)
            let before = try #require(old.entitiesByName[name])
            for property in entity.propertiesByName.keys where before.propertiesByName[property] == nil {
                added.append("\(name).\(property)")
                let attribute = try #require(entity.attributesByName[property])
                #expect(attribute.attributeType == .stringAttributeType && attribute.defaultValue as? String == "", "\(name).\(property)")
            }
        }
        #expect(Set(added) == ["AuditEvent.device", "AuditEvent.changeDetails", "BankTransaction.ignoreReason"])
    }
}
