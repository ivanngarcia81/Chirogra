import ChirograCore
import ChirograData
import ChirograUI
import SwiftData
import SwiftUI

@main
struct ChirograApp: App {
    /// Contenedor de iCloud (capacidad de iCloud con CloudKit en `App/Chirogra.entitlements`).
    static let cloudKitContainer = "iCloud.com.chirogra.app"

    let container: ModelContainer
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ChirograAppDelegate.self) private var appDelegate
    #endif

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
            // Sale sin abrir los libros: esta compilación lleva un esquema nuevo y migraría el almacén del aparato, que la
            // versión instalada ya no podría abrir (1.2, 10-nov).
            exit(0)
        }
        #endif
        // Pistas de una sola vez (TipKit; en Debug, `-qa.pistas reset|todas|ocultas`).
        ChirograTips.configure()
        // iCloud encendido en los aparatos nuevos; los que ya tenían libros locales siguen como estaban.
        let wantsSync = ChirograStore.resolveSyncPreference()
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
        // `-qa.prueba12 1` (solo Debug): empresa «Prueba 1.2» con todo lo de la 1.2, para probar iCloud en Producción.
        if UserDefaults.standard.bool(forKey: "qa.prueba12") { QAVersion12.makeTestCompany(in: container.mainContext) }
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

#if os(macOS)
import AppKit

/// En el Mac, iCloud avisa de los cambios de otros aparatos con un aviso push silencioso, y la app tiene que registrarse
/// para recibirlo: sin esto, lo que se guarda en el iPhone o el iPad solo llega al volver a abrir la app del Mac.
final class ChirograAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: ChirograStore.syncEnabledKey) {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }
}
#endif

#if DEBUG
/// `-qa.prueba12 1`: una empresa aparte, «Prueba 1.2 LLC», con un ajuste del contador, un cliente creado y editado, un
/// movimiento del banco dividido y otro excluido con motivo. Solo toca esa empresa; si ya existe, no hace nada.
@MainActor
enum QAVersion12 {
    static func makeTestCompany(in context: ModelContext) {
        let legalName = "Prueba 1.2 LLC"
        guard (try? context.fetch(FetchDescriptor<Company>()))?.contains(where: { $0.legalName == legalName }) == false else { return }
        let savedLimit = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = savedLimit }
        do {
            let books = try Bookkeeper(context: context).forNewCompany()
            try books.setUpCompany(legalName: legalName, displayName: "Prueba 1.2", entityType: .llc, state: "TX")
            func account(_ code: String) throws -> Account {
                guard let found = try books.accounts().first(where: { $0.code == code }) else { throw BookkeepingError.unknownAccount }
                return found
            }
            let checking = try account("1010")
            try books.post(JournalEntryDraft(date: .now, memo: "Prueba 1.2: renta pagada por adelantado", source: .accountantAdjustment,
                                             lines: [.debit(try account("1300").id, 100_000), .credit(try account("6400").id, 100_000)]))
            let customer = Customer(name: "Cliente de prueba 1.2")
            books.insert(customer)
            books.logSave(.customer, id: customer.id, name: customer.name, before: nil, after: AuditSnapshot(customer))
            let before = AuditSnapshot(customer)
            customer.phone = "555-0112"
            books.logSave(.customer, id: customer.id, name: customer.name, before: before, after: AuditSnapshot(customer))
            try context.save()
            let stamp = UUID().uuidString.prefix(8)
            let imported = try books.importStatementLines([
                BankStatementLine(date: .now, amount: -12_000, details: "COSTCO PRUEBA 1.2", externalID: "prueba12-a-\(stamp)"),
                BankStatementLine(date: .now, amount: -1_840, details: "CAFE PRUEBA 1.2", externalID: "prueba12-b-\(stamp)"),
            ], source: .csv, into: checking, applyRules: false).imported
            if imported.count == 2 {
                try books.categorize(imported[0], splitInto: [BankSplitPart(accountID: try account("6500").id, amount: 9_000, memo: "Papel"),
                                                              BankSplitPart(accountID: try account("6650").id, amount: 3_000)])
                try books.ignore(imported[1], reason: "Gasto personal")
            }
            NSLog("Chirogra QA prueba12: %@", "lista")
        } catch {
            NSLog("Chirogra QA prueba12: %@", "error \(error)")
        }
    }
}
#endif
