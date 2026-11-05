import ChirograData
import ChirograUI
import SwiftData
import SwiftUI

@main
struct ChirograApp: App {
    /// Contenedor de iCloud (capacidad de iCloud con CloudKit en `App/Chirogra.entitlements`).
    static let cloudKitContainer = "iCloud.com.chirogra.app"

    let container: ModelContainer

    init() {
        #if DEBUG
        // `-qa.esquemaCloudKit 1` (solo Debug, en un aparato con sesión de iCloud): crea el esquema de CloudKit en
        // desarrollo y anota el resultado en el registro y en `qa.esquemaCloudKit.resultado` de los ajustes.
        if UserDefaults.standard.bool(forKey: "qa.esquemaCloudKit") {
            let result: String
            do {
                try ChirograStore.initializeCloudKitSchema(containerIdentifier: Self.cloudKitContainer)
                result = "listo"
            } catch {
                result = "error \(error)"
            }
            NSLog("Chirogra esquema CloudKit: %@", result)
            // También en los ajustes de la app, para leerlo con `defaults read` (el registro no siempre se ve).
            UserDefaults.standard.set("\(Date.now.formatted(.iso8601)) \(result)", forKey: "qa.esquemaCloudKit.resultado")
        }
        #endif
        // Pistas de una sola vez (TipKit; en Debug, `-qa.pistas reset|todas|ocultas`).
        ChirograTips.configure()
        let wantsSync = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        do {
            container = try ChirograStore.makeContainer(cloudKitContainer: wantsSync ? Self.cloudKitContainer : nil)
        } catch {
            // Sin la capacidad de iCloud firmada, CloudKit no está disponible: se abre el almacén local.
            do {
                container = try ChirograStore.makeContainer()
            } catch {
                fatalError("No se pudo abrir la base de datos de Chirogra: \(error)")
            }
        }
        #if DEBUG
        // `-qa.vacia 1` (solo Debug): una empresa nueva y vacía, sin pasar por el alta (estados vacíos y pistas).
        if UserDefaults.standard.bool(forKey: "qa.vacia") {
            let books = Bookkeeper(context: container.mainContext, actor: "QA")
            if (try? books.company()) == nil {
                try? books.setUpCompany(legalName: "Taller Luna LLC", displayName: "Taller Luna", entityType: .llc, state: "TX")
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ChirograRootView()
        }
        .modelContainer(container)
        .commands { ChirograHelpCommands() }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}
