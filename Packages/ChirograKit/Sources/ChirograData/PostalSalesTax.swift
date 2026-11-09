import ChirograCore
import Foundation

// MARK: - Sales tax por código postal, paso 1 (PLAN-FASE2 §7, docs/DATOS-V4.md §6)
//
// La tabla de tasas por ZIP aún no tiene fuente ni licencia decididas: se publicará en chirogra.com y la app la cargará
// (`PostalTaxTables.current`). Aquí queda el punto de entrada: el formato de la tabla, la búsqueda y la sugerencia para
// un cliente. **Solo sugiere**: el usuario confirma antes de que una factura cobre esa tasa.

/// Tasa de sales tax de un código postal.
public struct PostalTaxRate: Codable, Hashable, Sendable {
    /// ZIP de 5 dígitos.
    public var postalCode: String
    /// Estado (código de 2 letras).
    public var state: String
    /// Ciudad o condado que da nombre a la parte local («Austin»).
    public var region: String
    /// Tasa estatal y local (condado + ciudad + distritos especiales), en millonésimas (6.25 % = 62 500).
    public var stateRateMillionths: Int64
    public var localRateMillionths: Int64

    public init(postalCode: String, state: String, region: String, stateRateMillionths: Int64, localRateMillionths: Int64) {
        self.postalCode = postalCode
        self.state = state
        self.region = region
        self.stateRateMillionths = stateRateMillionths
        self.localRateMillionths = localRateMillionths
    }

    public var combinedRateMillionths: Int64 { stateRateMillionths + localRateMillionths }
}

/// Tabla de tasas por código postal.
///
/// Formato JSON: `{"source": "…", "effectiveDate": "2026-10-01", "rates": [{"postalCode": "78702", "state": "TX",
/// "region": "Austin", "stateRateMillionths": 62500, "localRateMillionths": 20000}, …]}`.
public struct PostalTaxTable: Sendable {
    public var source: String
    /// Fecha desde la que valen las tasas («2026-10-01»).
    public var effectiveDate: String
    private var rates: [String: PostalTaxRate]

    public init(rates: [PostalTaxRate], source: String = "", effectiveDate: String = "") {
        self.source = source
        self.effectiveDate = effectiveDate
        self.rates = Dictionary(rates.map { ($0.postalCode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(json data: Data) throws {
        struct File: Decodable {
            var source: String?
            var effectiveDate: String?
            var rates: [PostalTaxRate]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(rates: file.rates, source: file.source ?? "", effectiveDate: file.effectiveDate ?? "")
    }

    public var count: Int { rates.count }

    public func rate(for postalCode: String) -> PostalTaxRate? {
        Self.normalized(postalCode).flatMap { rates[$0] }
    }

    /// «78702-1234» o « 78702 » → «78702». `nil` si no son 5 dígitos.
    public static func normalized(_ postalCode: String) -> String? {
        let digits = postalCode.trimmingCharacters(in: .whitespaces).prefix { $0 != "-" }.filter { !$0.isWhitespace }
        guard digits.count == 5, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(digits)
    }
}

/// La tabla cargada en la app (la carga quien descargue la de chirogra.com; las pruebas ponen la suya).
@MainActor
public enum PostalTaxTables {
    public static var current: PostalTaxTable?
}

/// Tasa sugerida para una venta.
public struct SalesTaxSuggestion: Sendable, Equatable {
    public enum Basis: String, Sendable { case origin, destination }

    public var rate: PostalTaxRate
    /// Con qué código postal se buscó: el del negocio (origen) o el del cliente (destino).
    public var basis: Basis
    /// Impuesto de la empresa (grupo o tasa) con la misma tasa total, si ya existe: se puede usar tal cual.
    public var existingTaxCodeID: UUID?
}

extension Bookkeeper {

    /// Sugerencia de sales tax para una venta a `customer` con la tabla cargada. Con origen (`Company.salesTaxSourcing`,
    /// p. ej. Texas) se usa el ZIP del negocio, salvo que el cliente esté en otro estado; con destino, el del cliente (o
    /// el del negocio si el cliente no tiene). `nil` sin tabla, sin código postal o si la tabla no lo tiene.
    public func suggestedSalesTax(for customer: Customer?, table: PostalTaxTable? = nil) throws -> SalesTaxSuggestion? {
        guard let table = table ?? PostalTaxTables.current, let company = try company() else { return nil }
        let own = table.rate(for: company.postalCode)
        let theirs = customer.flatMap { table.rate(for: $0.postalCode) }
        let chosen: (PostalTaxRate, SalesTaxSuggestion.Basis)?
        switch company.salesTaxSourcing {
        case .origin:
            if let theirs, let own, theirs.state != own.state { chosen = (theirs, .destination) }
            else { chosen = own.map { ($0, .origin) } ?? theirs.map { ($0, .destination) } }
        case .destination:
            chosen = theirs.map { ($0, .destination) } ?? own.map { ($0, .origin) }
        }
        guard let (rate, basis) = chosen else { return nil }
        return SalesTaxSuggestion(rate: rate, basis: basis, existingTaxCodeID: try taxCodeID(withRate: rate.combinedRateMillionths))
    }

    /// Un grupo o una tasa activa de la empresa con esa tasa total (primero los grupos).
    func taxCodeID(withRate millionths: Int64, on date: Date = Date()) throws -> UUID? {
        if let group = try fetch(TaxGroup.self).first(where: { !$0.isArchived && $0.combinedRateMillionths == millionths }) { return group.id }
        return try fetch(TaxRate.self).first { $0.isEffective(on: date) && $0.rateMillionths == millionths }?.id
    }

    /// Crea el impuesto de una sugerencia que aún no existe: la tasa estatal (la del estado, en su agencia) más la local
    /// («Austin» 2 %) en un grupo «Austin, TX». No cambia el predeterminado. Si ya existe uno igual, lo devuelve.
    @discardableResult
    public func createTaxCode(for suggestion: SalesTaxSuggestion) throws -> TaxCodeSummary {
        if let id = try suggestion.existingTaxCodeID ?? taxCodeID(withRate: suggestion.rate.combinedRateMillionths) {
            if let group = try taxGroup(id: id) { return TaxCodeSummary(id: group.id, name: group.name, rates: group.rates ?? []) }
            if let rate = try taxRate(id: id) { return TaxCodeSummary(id: rate.id, name: rate.name, rates: [rate]) }
        }
        let rate = suggestion.rate
        let info = StateSalesTax.forState(rate.state)
        let agencyName = info?.agency ?? rate.state
        let agency = try fetch(TaxAgency.self).first { $0.name == agencyName && !$0.isArchived }
        let stateName = info?.name ?? rate.state
        let stateRate = try agency.flatMap { agency in
            (agency.rates ?? []).first { $0.name == stateName && $0.rateMillionths == rate.stateRateMillionths && !$0.isArchived }
        } ?? addTaxRate(name: stateName, rateMillionths: rate.stateRateMillionths, agency: agency, newAgencyName: agencyName).rate
        guard rate.localRateMillionths > 0 else { return TaxCodeSummary(id: stateRate.id, name: stateRate.name, rates: [stateRate]) }
        let region = rate.region.isEmpty ? String(localized: "Local") : rate.region
        let local = try addTaxRate(name: region, rateMillionths: rate.localRateMillionths, agency: stateRate.agency).rate
        let group = TaxGroup(name: "\(region), \(rate.state)", rates: [stateRate, local])
        insert(group)
        audit("TaxGroup", group.id, "create", String(localized: "Grupo creado: \(group.name) \(group.percent)%"))
        try saveOrRollback()
        return TaxCodeSummary(id: group.id, name: group.name, rates: [stateRate, local])
    }
}

// MARK: - Enlace de pago propio, paso 1 (PLAN-FASE2 §8)

public enum PaymentLinkTemplate {
    /// Sustituye en la plantilla `{amount}` («1250.50»), `{number}` («F-1001») y `{customer}`, codificados para URL.
    /// `nil` si el resultado no es una URL http(s).
    public static func url(_ template: String, amount: Int64, number: String, customer: String) -> URL? {
        let encode = { (value: String) in value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/"))) ?? value }
        let text = template.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{amount}", with: CSVExport.amount(amount))
            .replacingOccurrences(of: "{number}", with: encode(number))
            .replacingOccurrences(of: "{customer}", with: encode(customer))
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }
}

extension Bookkeeper {

    /// Guarda el enlace de pago, las instrucciones y si se muestra «Pagar ahora». Un enlace no vacío tiene que ser una
    /// URL http(s) (con o sin `{amount}`…).
    public func setPaymentSettings(link: String, instructions: String, showPayNow: Bool) throws {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty, PaymentLinkTemplate.url(link, amount: 100, number: "F-1001", customer: "Cliente") == nil {
            throw BookkeepingError.invalidState(String(localized: "El enlace de pago debe ser una dirección web (https://…)."))
        }
        company.paymentLinkURL = link
        company.paymentInstructions = instructions
        company.showPayNowOnInvoice = showPayNow
        audit("Company", company.id, "paymentLink", String(localized: "Enlace de pago cambiado"))
        try saveOrRollback()
    }

    /// Dirección de «Pagar ahora» (y del QR) de una factura: el enlace de la empresa con el saldo pendiente, el número y
    /// el cliente. `nil` si no hay enlace, si la empresa no lo muestra o si la factura no tiene nada que pagar.
    public func paymentLink(for invoice: Invoice) throws -> URL? {
        guard let company = try company(), company.showPayNowOnInvoice, !company.paymentLinkURL.isEmpty,
              invoice.isOpen, invoice.balanceDue > 0 else { return nil }
        return PaymentLinkTemplate.url(company.paymentLinkURL, amount: invoice.balanceDue, number: invoice.number,
                                       customer: invoice.customer?.name ?? "")
    }
}
