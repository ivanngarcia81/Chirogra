import Foundation

/// Sales tax **estatal base** de cada estado de EE. UU., DC y Puerto Rico: la tasa que el alta crea como impuesto
/// predeterminado de la empresa (`Bookkeeper.setUpStateSalesTax`). Es solo la parte del estado; la del condado, la
/// ciudad o el distrito la añade el usuario en Impuestos. Las tasas son responsabilidad del usuario y el alta lo dice.
///
/// **Fuente:** Tax Foundation, «State and Local Sales Tax Rates, Midyear 2026» (tasas al 1 de julio de 2026;
/// https://taxfoundation.org/data/all/state/2026-sales-tax-rates-midyear/), consultada el 5-nov-2026. Ninguna tasa
/// estatal cambió entre enero y julio de 2026. La tabla redondea a dos decimales; aquí van las cifras exactas de ley:
/// Minnesota 6.875 %, Missouri 4.225 %, Nueva Jersey 6.625 % y Nuevo México 4.875 % (gross receipts tax).
/// - California (7.25 %), Utah (6.10 %) y Virginia (5.30 %) incluyen el impuesto local obligatorio en todo el estado
///   (1.25 %, 1.25 % y 1 %), como hace Tax Foundation: lo cobra y declara la misma agencia estatal.
/// - DC: 6 %. La subida al 7 % se aplazó; la Office of Tax and Revenue dice que sigue en 6 % hasta el
///   30-sep-2027 (otr.cfo.dc.gov, aviso de cambios del 1-oct-2025).
/// - Puerto Rico (no está en Tax Foundation): IVU estatal del 10.5 % (Departamento de Hacienda); el 1 % municipal
///   va aparte.
/// - Sin sales tax estatal: Delaware, Montana, New Hampshire y Oregon; Alaska tampoco, pero muchas ciudades y
///   boroughs cobran uno local.
///
/// **Revisar cada año** (Tax Foundation publica la tabla en enero y en julio) y actualizar `asOf`.
public struct StateSalesTax: Sendable, Equatable {
    /// Código postal del estado («TX»), el que guarda `Company.state`.
    public let code: String
    /// Nombre del estado («Texas»). Nombre propio: igual en los dos idiomas.
    public let name: String
    /// Tasa estatal base en millonésimas (6.25 % = 62 500), o `nil` si el estado no tiene sales tax estatal.
    public let rateMillionths: Int64?
    /// Agencia que lo recauda («Texas Comptroller»).
    public let agency: String
    /// No hay sales tax estatal pero sí locales (Alaska).
    public let hasLocalTaxOnly: Bool

    init(_ code: String, _ name: String, _ rateMillionths: Int64?, _ agency: String, localOnly: Bool = false) {
        self.code = code
        self.name = name
        self.rateMillionths = rateMillionths
        self.agency = agency
        self.hasLocalTaxOnly = localOnly
    }

    /// Fecha de las tasas de la tabla.
    public static let asOf = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 1)

    /// El estado del código («TX»), o `nil` si no está en la tabla.
    public static func forState(_ code: String) -> StateSalesTax? {
        let code = code.trimmingCharacters(in: .whitespaces).uppercased()
        return all.first { $0.code == code }
    }

    /// Los 50 estados, DC y Puerto Rico, por nombre.
    public static let all: [StateSalesTax] = [
        StateSalesTax("AL", "Alabama", 40_000, "Alabama Department of Revenue"),
        StateSalesTax("AK", "Alaska", nil, "", localOnly: true),
        StateSalesTax("AZ", "Arizona", 56_000, "Arizona Department of Revenue"),
        StateSalesTax("AR", "Arkansas", 65_000, "Arkansas Department of Finance and Administration"),
        StateSalesTax("CA", "California", 72_500, "California Department of Tax and Fee Administration"),
        StateSalesTax("CO", "Colorado", 29_000, "Colorado Department of Revenue"),
        StateSalesTax("CT", "Connecticut", 63_500, "Connecticut Department of Revenue Services"),
        StateSalesTax("DE", "Delaware", nil, ""),
        StateSalesTax("DC", "District of Columbia", 60_000, "DC Office of Tax and Revenue"),
        StateSalesTax("FL", "Florida", 60_000, "Florida Department of Revenue"),
        StateSalesTax("GA", "Georgia", 40_000, "Georgia Department of Revenue"),
        StateSalesTax("HI", "Hawaii", 40_000, "Hawaii Department of Taxation"),
        StateSalesTax("ID", "Idaho", 60_000, "Idaho State Tax Commission"),
        StateSalesTax("IL", "Illinois", 62_500, "Illinois Department of Revenue"),
        StateSalesTax("IN", "Indiana", 70_000, "Indiana Department of Revenue"),
        StateSalesTax("IA", "Iowa", 60_000, "Iowa Department of Revenue"),
        StateSalesTax("KS", "Kansas", 65_000, "Kansas Department of Revenue"),
        StateSalesTax("KY", "Kentucky", 60_000, "Kentucky Department of Revenue"),
        StateSalesTax("LA", "Louisiana", 50_000, "Louisiana Department of Revenue"),
        StateSalesTax("ME", "Maine", 55_000, "Maine Revenue Services"),
        StateSalesTax("MD", "Maryland", 60_000, "Comptroller of Maryland"),
        StateSalesTax("MA", "Massachusetts", 62_500, "Massachusetts Department of Revenue"),
        StateSalesTax("MI", "Michigan", 60_000, "Michigan Department of Treasury"),
        StateSalesTax("MN", "Minnesota", 68_750, "Minnesota Department of Revenue"),
        StateSalesTax("MS", "Mississippi", 70_000, "Mississippi Department of Revenue"),
        StateSalesTax("MO", "Missouri", 42_250, "Missouri Department of Revenue"),
        StateSalesTax("MT", "Montana", nil, ""),
        StateSalesTax("NE", "Nebraska", 55_000, "Nebraska Department of Revenue"),
        StateSalesTax("NV", "Nevada", 68_500, "Nevada Department of Taxation"),
        StateSalesTax("NH", "New Hampshire", nil, ""),
        StateSalesTax("NJ", "New Jersey", 66_250, "New Jersey Division of Taxation"),
        StateSalesTax("NM", "New Mexico", 48_750, "New Mexico Taxation and Revenue Department"),
        StateSalesTax("NY", "New York", 40_000, "New York State Department of Taxation and Finance"),
        StateSalesTax("NC", "North Carolina", 47_500, "North Carolina Department of Revenue"),
        StateSalesTax("ND", "North Dakota", 50_000, "North Dakota Office of State Tax Commissioner"),
        StateSalesTax("OH", "Ohio", 57_500, "Ohio Department of Taxation"),
        StateSalesTax("OK", "Oklahoma", 45_000, "Oklahoma Tax Commission"),
        StateSalesTax("OR", "Oregon", nil, ""),
        StateSalesTax("PA", "Pennsylvania", 60_000, "Pennsylvania Department of Revenue"),
        // IVU: 10.5 % estatal + 1 % municipal (11.5 %); el municipal va como tasa local. Comprobado el 10-nov-2026.
        StateSalesTax("PR", "Puerto Rico", 105_000, "Departamento de Hacienda de Puerto Rico"),
        StateSalesTax("RI", "Rhode Island", 70_000, "Rhode Island Division of Taxation"),
        StateSalesTax("SC", "South Carolina", 60_000, "South Carolina Department of Revenue"),
        StateSalesTax("SD", "South Dakota", 42_000, "South Dakota Department of Revenue"),
        StateSalesTax("TN", "Tennessee", 70_000, "Tennessee Department of Revenue"),
        StateSalesTax("TX", "Texas", 62_500, "Texas Comptroller"),
        StateSalesTax("UT", "Utah", 61_000, "Utah State Tax Commission"),
        StateSalesTax("VT", "Vermont", 60_000, "Vermont Department of Taxes"),
        StateSalesTax("VA", "Virginia", 53_000, "Virginia Tax"),
        StateSalesTax("WA", "Washington", 65_000, "Washington Department of Revenue"),
        StateSalesTax("WV", "West Virginia", 60_000, "West Virginia Tax Division"),
        StateSalesTax("WI", "Wisconsin", 50_000, "Wisconsin Department of Revenue"),
        StateSalesTax("WY", "Wyoming", 40_000, "Wyoming Department of Revenue"),
    ]
}
