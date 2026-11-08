#if DEBUG
import ChirograData
import Foundation

/// Argumentos de QA de Banca (solo Debug, docs/REDISEÑO-NATIVO.md §5), para llegar a cada pantalla sin ratón:
/// `-qa.importar <ruta>` abre «Importar movimientos» con ese archivo (`-qa.importarAuto 1` además importa);
/// `-qa.revisar N` abre «Revisar transacción» del N.º por revisar (`-qa.revisarModo emparejar|categorizar|regla`,
/// `-qa.revisarCategoria 1` elige la primera categoría); `-qa.aceptarSugeridas 1`; `-qa.bandeja 1` y `-qa.reglas 1`
/// abren la bandeja completa y las reglas en el iPhone; `-qa.reglaNueva 1`; `-qa.conciliar N` abre la conciliación de la
/// N.ª cuenta de banco o tarjeta, con `-qa.conciliarFecha AAAA-MM-DD`, `-qa.conciliarSaldo <centavos>`,
/// `-qa.conciliarEmpezar 1`, `-qa.conciliarMarcar todas`, `-qa.conciliarCuadrar 1` y `-qa.conciliarTerminar 1`.
@MainActor
enum QABanking {
    private static var defaults: UserDefaults { .standard }
    /// La hoja de importar ya importó el archivo de QA (o se cerró): no se vuelve a abrir. No basta con leerlo una vez:
    /// al arrancar, la app se rehace (empresa activa) y la primera hoja se pierde con la vista.
    static var importHandled = false
    /// El archivo de `-qa.importar` que espera una hoja de importar (la del iPad lo recoge al abrirse).
    static var pendingImport: BankImportFile?

    /// El archivo de `-qa.importar`, hasta que una hoja lo importe.
    static var importFile: BankImportFile? {
        guard !importHandled, let path = defaults.string(forKey: "qa.importar"),
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return BankImportFile(name: URL(fileURLWithPath: path).lastPathComponent, data: data)
    }

    static var reviewIndex: Int? {
        defaults.object(forKey: "qa.revisar") == nil ? nil : defaults.integer(forKey: "qa.revisar")
    }

    static var reconcileIndex: Int? {
        defaults.object(forKey: "qa.conciliar") == nil ? nil : defaults.integer(forKey: "qa.conciliar")
    }

    static var statementBalance: Int64? {
        defaults.object(forKey: "qa.conciliarSaldo") == nil ? nil : Int64(defaults.integer(forKey: "qa.conciliarSaldo"))
    }

    static var statementDate: Date? {
        guard let text = defaults.string(forKey: "qa.conciliarFecha") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static var opensInbox: Bool { defaults.bool(forKey: "qa.bandeja") }
    static var opensRules: Bool { defaults.bool(forKey: "qa.reglas") }
}
#endif
