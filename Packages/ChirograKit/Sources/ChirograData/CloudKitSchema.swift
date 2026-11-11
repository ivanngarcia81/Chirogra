import CoreData
import Foundation
import SwiftData

extension ChirograStore {
    /// Crea en el entorno de **desarrollo** de CloudKit todos los tipos de registro del esquema actual, como pide Apple
    /// antes de desplegar a producción (SwiftData no lo hace: solo sube los tipos que ya tienen registros). Usa un
    /// `NSPersistentCloudKitContainer` con el mismo modelo sobre un almacén temporal, así no toca los libros.
    /// Después hay que desplegar el esquema a producción en la consola de CloudKit (docs/CONTEXTO.md).
    ///
    /// Necesita una versión firmada con la capacidad de iCloud y una sesión de iCloud en el aparato.
    public static func initializeCloudKitSchema(containerIdentifier: String) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SchemaV5.models) else {
            throw CocoaError(.featureUnsupported)
        }
        let url = URL.temporaryDirectory.appending(path: "chirogra-esquema-cloudkit.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "Chirogra", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
            }
        }
        try container.initializeCloudKitSchema(options: [])
    }
}
