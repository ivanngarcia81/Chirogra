import Foundation

/// Formulario 1099-NEC: a partir de qué cantidad pagada en el año a un proveedor hay que enviárselo.
///
/// El mínimo depende del año en que se hacen los pagos (IRC §6041(a)):
/// - **2025 y antes:** $600.
/// - **Desde el 1 de enero de 2026:** $2,000. Lo subió la One Big Beautiful Bill Act (Public Law 119-21, §70433),
///   que también lo aplica a la mayoría de los pagos del 1099-MISC.
/// - **Desde 2027:** los $2,000 se ajustan cada año por inflación. El IRS publica la cifra de cada año (en el
///   Revenue Procedure de ajustes por inflación y en las instrucciones de los formularios 1099-MISC y 1099-NEC).
///
/// La regla es única: la ficha del proveedor (tabla e inspector del Mac, detalle de iPhone, iPad y Mac) la usa con
/// el año que muestra, nunca con una cifra fija.
public enum Form1099 {
    /// Mínimo de 2025 y años anteriores, en centavos ($600).
    public static let thresholdThrough2025: Int64 = 60_000

    /// Mínimo desde 2026, en centavos ($2,000).
    public static let thresholdFrom2026: Int64 = 200_000

    /// Mínimos ya publicados por el IRS para los años con ajuste por inflación, en centavos.
    ///
    /// ACTUALIZAR CADA AÑO: cuando el IRS publique la cifra de un año (a partir de 2027), añadirla aquí,
    /// p. ej. `2027: 205_000`. Mientras un año no esté en la tabla se usa el último conocido (hoy, $2,000 para 2027
    /// y siguientes). Revisado el 4-nov-2026: el IRS aún no ha publicado la de 2027.
    static let inflationAdjusted: [Int: Int64] = [:]

    /// Mínimo del 1099-NEC, en centavos, para los pagos hechos en el año fiscal `year`.
    public static func threshold(forTaxYear year: Int) -> Int64 {
        if year <= 2025 { return thresholdThrough2025 }
        if let published = inflationAdjusted.filter({ $0.key <= year }).max(by: { $0.key < $1.key }) {
            return published.value
        }
        return thresholdFrom2026
    }

    /// `true` si lo pagado en el año (`paid`, en centavos) llega al mínimo de ese año: hay que enviar el 1099-NEC.
    public static func reachesThreshold(paid: Int64, taxYear year: Int) -> Bool {
        paid >= threshold(forTaxYear: year)
    }

    /// Qué dice la nota del 1099 de un proveedor en un año (las vistas ponen el texto).
    public enum Notice: Equatable, Sendable {
        /// El proveedor no está marcado para el 1099.
        case notReportable
        /// Marcado para el 1099, pero lo pagado en el año aún no llega al mínimo (`threshold`, en centavos).
        case belowThreshold(threshold: Int64)
        /// Lo pagado en el año (`paid`) llega al mínimo (`threshold`): hay que enviarle el 1099-NEC.
        case reached(paid: Int64, threshold: Int64)
    }

    /// La nota del 1099 para un proveedor con `is1099` al que se le ha pagado `paid` (centavos) en `taxYear`.
    public static func notice(is1099: Bool, paid: Int64, taxYear year: Int) -> Notice {
        guard is1099 else { return .notReportable }
        let minimum = threshold(forTaxYear: year)
        return paid >= minimum ? .reached(paid: paid, threshold: minimum) : .belowThreshold(threshold: minimum)
    }
}
