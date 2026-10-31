import ChirograData
import ChirograUI
import SwiftData
import SwiftUI

@main
struct ChirograApp: App {
    /// Identificador del contenedor de iCloud. Para activar la sincronización, añade la capacidad
    /// de iCloud (CloudKit) con este contenedor al target y firma con tu equipo (ver README).
    static let cloudKitContainer = "iCloud.com.chirogra.app"

    let container: ModelContainer

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            ChirograRootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}
