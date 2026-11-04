import CoreData
import SwiftData
import Testing
@testable import ChirograData

@Suite("Esquema de CloudKit")
struct CloudKitSchemaTests {
    @Test("El modelo de Core Data del esquema 2 cumple las reglas de CloudKit")
    func modelFollowsCloudKitRules() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV2.models))
        #expect(model.entities.count == SchemaV2.models.count)
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
}
