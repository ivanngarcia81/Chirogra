import ChirograData
import Foundation
import Observation

// MARK: - Tabla de sales tax por código postal (paso 1, PLAN-FASE2 §7)
//
// La tabla viaja dentro de la app (`PostalTaxTable.bundled()`, generada con `scripts/tasas/generar.py` de los archivos
// oficiales de los estados; docs/DATOS-V5.md) y se carga en `PostalTaxTables.current`, que usan
// `suggestedSalesTax(for:)` y las pantallas. Se lee fuera del hilo principal (son unos 27 000 ZIP). Si algún día se
// publica en chirogra.com (`remoteURL`), la app guarda la descargada y usa la más reciente de las dos; hoy está apagado
// (en el Mac haría falta además el permiso `com.apple.security.network.client`). Para probar, `-qa.tablaZip muestra`
// carga la tabla de muestra inventada (`PostalTaxSample`) o `-qa.tablaZip <ruta>` un JSON con el formato de
// `PostalTaxTable`.

@MainActor
enum PostalTaxTableLoader {
    /// Para que las pantallas se redibujen al llegar la tabla (`PostalTaxTables.current` no se observa).
    @Observable final class Status {
        var hasTable = PostalTaxTables.current != nil
    }
    static let status = Status()

    /// Dónde se publicaría la tabla para tenerla al día sin esperar a una versión nueva. `nil`: solo la de la app.
    static let remoteURL: URL? = nil
    /// Cada cuánto se busca una tabla nueva (las fuentes cambian, como mucho, cada mes).
    static let refreshInterval: TimeInterval = 7 * 86_400
    private static let lastCheckKey = "postalTaxTableLastCheck"
    private static var attempted = false

    /// La copia guardada de la última tabla descargada.
    static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "Chirogra", directoryHint: .isDirectory).appending(path: "sales-tax-zip.json")
    }

    /// Carga la tabla una vez por sesión (la guardada y, si toca, la nueva de chirogra.com). No hace nada si ya hay una.
    static func loadIfNeeded() async {
        guard PostalTaxTables.current == nil, !attempted else { return }
        attempted = true
        #if DEBUG
        if let argument = UserDefaults.standard.string(forKey: "qa.tablaZip") {
            PostalTaxTables.current = argument == "muestra" ? PostalTaxSample.table
                : (try? Data(contentsOf: URL(fileURLWithPath: argument))).flatMap { try? PostalTaxTable(json: $0) }
            status.hasTable = PostalTaxTables.current != nil
            return
        }
        #endif
        let cache = cacheURL
        let table = await Task.detached(priority: .utility) { () -> PostalTaxTable? in
            let downloaded = (try? Data(contentsOf: cache)).flatMap { try? PostalTaxTable(json: $0) }
            // La más reciente: la descargada puede quedar vieja cuando llega una versión nueva de la app.
            return [downloaded, PostalTaxTable.bundled()].compactMap { $0 }.max { $0.effectiveDate < $1.effectiveDate }
        }.value
        if PostalTaxTables.current == nil { PostalTaxTables.current = table }
        status.hasTable = PostalTaxTables.current != nil
        await refreshIfDue()
    }

    /// Descarga la tabla publicada si pasó `refreshInterval` desde la última vez. Solo la guarda si se lee bien.
    static func refreshIfDue(now: Date = .now) async {
        guard let remoteURL else { return }
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: lastCheckKey) as? Date, now.timeIntervalSince(last) < refreshInterval,
           PostalTaxTables.current != nil { return }
        guard let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              (response as? HTTPURLResponse)?.statusCode == 200, let table = try? PostalTaxTable(json: data), table.count > 0
        else { return }
        PostalTaxTables.current = table
        status.hasTable = true
        defaults.set(now, forKey: lastCheckKey)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}

/// Tabla de **muestra inventada**, solo para pruebas y capturas (`-qa.tablaZip muestra`). Las cifras no son tasas
/// reales ni salen de ninguna fuente: no usarlas para cobrar.
enum PostalTaxSample {
    static let json = """
    {"source": "Muestra inventada para pruebas (no son tasas reales)", "effectiveDate": "2026-11-01", "rates": [
      {"postalCode": "78702", "state": "TX", "region": "Austin", "stateRateMillionths": 62500, "localRateMillionths": 20000},
      {"postalCode": "78701", "state": "TX", "region": "Austin", "stateRateMillionths": 62500, "localRateMillionths": 20000},
      {"postalCode": "77002", "state": "TX", "region": "Houston", "stateRateMillionths": 62500, "localRateMillionths": 15000},
      {"postalCode": "79901", "state": "TX", "region": "El Paso", "stateRateMillionths": 62500, "localRateMillionths": 12500},
      {"postalCode": "94103", "state": "CA", "region": "San Francisco", "stateRateMillionths": 72500, "localRateMillionths": 13750},
      {"postalCode": "10001", "state": "NY", "region": "New York City", "stateRateMillionths": 40000, "localRateMillionths": 48750},
      {"postalCode": "33101", "state": "FL", "region": "Miami-Dade", "stateRateMillionths": 60000, "localRateMillionths": 10000},
      {"postalCode": "97201", "state": "OR", "region": "Portland", "stateRateMillionths": 0, "localRateMillionths": 0}
    ]}
    """

    static var table: PostalTaxTable? { try? PostalTaxTable(json: Data(json.utf8)) }
}
