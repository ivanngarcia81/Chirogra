import ChirograCore
import Foundation
import SwiftData

// MARK: - Alta: sales tax del estado y saldos de apertura

extension Bookkeeper {

    /// Crea la agencia del estado de la empresa y su tasa **estatal base** (`StateSalesTax`) y, si la empresa aún no
    /// tiene impuesto predeterminado, la deja como predeterminado de facturas y estimados nuevos. Para Texas:
    /// «Texas Comptroller» y «Texas» 6.25 %. Sin sales tax estatal (Oregon, Alaska…) o con un estado desconocido no
    /// crea nada y devuelve `nil`. Si ya existe la misma tasa en esa agencia, la reutiliza (no duplica).
    @discardableResult
    public func setUpStateSalesTax(state code: String? = nil) throws -> TaxRate? {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        guard let info = StateSalesTax.forState(code ?? company.state), let millionths = info.rateMillionths else { return nil }

        let agencies = try context.fetch(FetchDescriptor<TaxAgency>())
        let agency: TaxAgency
        if let existing = agencies.first(where: { $0.name == info.agency && !$0.isArchived }) {
            agency = existing
        } else {
            agency = TaxAgency(name: info.agency, filingFrequency: .quarterly, liabilityAccountID: try systemAccount(.salesTaxPayable).id)
            context.insert(agency)
        }
        let rate: TaxRate
        if let existing = (agency.rates ?? []).first(where: { $0.name == info.name && $0.rateMillionths == millionths && !$0.isArchived }) {
            rate = existing
        } else {
            rate = TaxRate(name: info.name, rateMillionths: millionths, agency: agency)
            context.insert(rate)
            audit("TaxRate", rate.id, "create", String(localized: "Tasa estatal creada en el alta: \(info.name) \(rate.percent)%"))
        }
        if company.defaultTaxGroupID == nil {
            company.defaultTaxGroupID = rate.id
            audit("Company", company.id, "defaultTax", String(localized: "Impuesto predeterminado cambiado"))
        }
        try saveOrRollback()
        return rate
    }

    // MARK: Tasas locales

    /// Impuesto predeterminado de la empresa (`Company.defaultTaxGroupID`) con sus tasas: la tasa sola o las de su
    /// grupo. `nil` si no hay predeterminado o ya no existe.
    public func defaultTaxCode() throws -> TaxCodeSummary? {
        guard let id = try company()?.defaultTaxGroupID else { return nil }
        var descriptor = FetchDescriptor<TaxGroup>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let group = try context.fetch(descriptor).first {
            return TaxCodeSummary(id: group.id, name: group.name, rates: (group.rates ?? []).filter { !$0.isArchived })
        }
        guard let rate = try taxRate(id: id), !rate.isArchived else { return nil }
        return TaxCodeSummary(id: rate.id, name: rate.name, rates: [rate])
    }

    /// Crea una tasa de sales tax en `agency` (o en una agencia nueva con `newAgencyName`) y decide qué cobran las
    /// facturas nuevas (`use`):
    /// - `.addToDefault`: la **suma al impuesto predeterminado** en un grupo nuevo (tasa combinada) que pasa a ser el
    ///   predeterminado. Es el caso de la ciudad o el condado: en Austin, «Texas» 6.25 % del alta + «Austin» 2 % =
    ///   grupo «Austin, TX» 8.25 %. Sin predeterminado, hace lo mismo que `.makeDefault`.
    /// - `.makeDefault`: la tasa sola pasa a ser el predeterminado.
    /// - `.keep`: solo la crea.
    /// Las facturas ya emitidas guardan su impuesto y no cambian. Sin cambios de esquema: grupo y predeterminado son
    /// los de siempre (`TaxGroup`, `Company.defaultTaxGroupID`).
    @discardableResult
    public func addTaxRate(name: String, rateMillionths: Int64, agency: TaxAgency?, newAgencyName: String = "",
                           use: NewTaxRateUse = .keep) throws -> (rate: TaxRate, group: TaxGroup?) {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La tasa necesita un nombre.")) }
        guard rateMillionths > 0, rateMillionths <= SalesTaxCalculator.millionth else {
            throw BookkeepingError.invalidState(String(localized: "La tasa debe estar entre 0 % y 100 %."))
        }
        let base = use == .addToDefault ? try defaultTaxCode() : nil

        let owner: TaxAgency
        if let agency {
            owner = agency
        } else {
            let agencyName = newAgencyName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !agencyName.isEmpty else {
                throw BookkeepingError.invalidState(String(localized: "La tasa necesita una agencia."))
            }
            owner = TaxAgency(name: agencyName, filingFrequency: .quarterly, liabilityAccountID: try systemAccount(.salesTaxPayable).id)
            context.insert(owner)
        }
        let rate = TaxRate(name: name, rateMillionths: rateMillionths, agency: owner)
        context.insert(rate)
        audit("TaxRate", rate.id, "create", String(localized: "Tasa creada: \(name) \(rate.percent)%"))

        var group: TaxGroup?
        if let base, !base.rates.isEmpty {
            let combined = TaxGroup(name: combinedTaxName(base: base, adding: name, state: company.state), rates: base.rates + [rate])
            context.insert(combined)
            audit("TaxGroup", combined.id, "create", String(localized: "Grupo creado: \(combined.name) \(combined.percent)%"))
            company.defaultTaxGroupID = combined.id
            audit("Company", company.id, "defaultTax", String(localized: "Impuesto predeterminado cambiado"))
            group = combined
        } else if use != .keep {
            company.defaultTaxGroupID = rate.id
            audit("Company", company.id, "defaultTax", String(localized: "Impuesto predeterminado cambiado"))
        }
        try saveOrRollback()
        return (rate, group)
    }

    /// Nombre del grupo que suma una tasa local al predeterminado: «Austin, TX» si el predeterminado es la tasa estatal
    /// del alta; si no, «Austin, TX + Travis County».
    public func combinedTaxName(base: TaxCodeSummary, adding local: String, state: String) -> String {
        if base.rates.count == 1, let info = StateSalesTax.forState(state), base.name == info.name {
            return "\(local), \(info.code)"
        }
        return "\(base.name) + \(local)"
    }

    /// Saldos con que empiezan los libros: lo que hay hoy en la cuenta del banco y, si se quiere, lo que se debe en
    /// la tarjeta de crédito, en un asiento de apertura (`EntrySource.opening`) contra **3900 · Saldos de apertura**
    /// (*Opening Balance Equity*, DISEÑO §4.1): Debe Banco / Haber Saldos de apertura y Debe Saldos de apertura /
    /// Haber Tarjeta. Las dos partes van en un solo asiento y Saldos de apertura queda por la diferencia. Con los dos
    /// importes en cero no registra nada y devuelve `nil`. Las cuentas son la primera de banco y la primera de
    /// tarjeta del plan (1010 Cuenta corriente y 2100 Tarjeta de crédito en las plantillas), o las que se den.
    @discardableResult
    public func recordOpeningBalances(
        bank: Int64, creditCard: Int64 = 0, on date: Date = Date(), bankAccount: Account? = nil, cardAccount: Account? = nil
    ) throws -> JournalEntry? {
        guard bank >= 0, creditCard >= 0 else {
            throw BookkeepingError.invalidState(String(localized: "Los saldos iniciales no pueden ser negativos."))
        }
        guard bank > 0 || creditCard > 0 else { return nil }
        let equity = try systemAccount(.openingBalanceEquity)
        var lines: [JournalLineDraft] = []
        if bank > 0 {
            let account = try bankAccount ?? firstAccount(.bank)
            lines.append(.debit(account.id, bank))
        }
        if creditCard > 0 {
            let account = try cardAccount ?? firstAccount(.creditCard)
            lines.append(.credit(account.id, creditCard))
        }
        let difference = bank - creditCard
        if difference > 0 {
            lines.append(.credit(equity.id, difference))
        } else if difference < 0 {
            lines.append(.debit(equity.id, -difference))
        }
        return try post(JournalEntryDraft(date: date, memo: String(localized: "Saldos iniciales"), source: .opening, lines: lines))
    }

    /// Ya hay un asiento de apertura contabilizado (del alta, de «Pon el saldo de tu banco» o de los datos de ejemplo).
    public func hasOpeningBalances() throws -> Bool {
        let opening = EntrySource.opening.rawValue
        let posted = EntryStatus.posted.rawValue
        return try context.fetchCount(FetchDescriptor<JournalEntry>(predicate: #Predicate {
            $0.sourceRaw == opening && $0.statusRaw == posted
        })) > 0
    }

    private func firstAccount(_ subtype: AccountSubtype) throws -> Account {
        guard let account = try accounts().first(where: { $0.subtype == subtype && $0.isPostable }) else {
            throw BookkeepingError.missingSystemAccount(subtype)
        }
        return account
    }
}

/// Qué cobran las facturas nuevas tras crear una tasa (`Bookkeeper.addTaxRate`).
public enum NewTaxRateUse: Sendable {
    /// Solo crearla.
    case keep
    /// La tasa sola pasa a ser el impuesto predeterminado.
    case makeDefault
    /// Sumarla al impuesto predeterminado en un grupo nuevo, que pasa a ser el predeterminado.
    case addToDefault
}

/// Un impuesto que se puede elegir en una factura: una tasa sola o un grupo, con sus tasas.
public struct TaxCodeSummary {
    public let id: UUID
    public let name: String
    public let rates: [TaxRate]

    /// Tasa total en millonésimas (6.25 % = 62 500).
    public var rateMillionths: Int64 { rates.reduce(0) { $0 + $1.rateMillionths } }
}

// MARK: - Tipo de empresa por el nombre

extension EntityType {
    /// Tipo que sugiere el final del nombre de la empresa, para preelegirlo en el alta: «Pintura Martínez LLC» →
    /// LLC; «Inc.», «Corp.», «Corporation» → C corporation (lo es por ley mientras no elija tributar como S corp);
    /// «LP», «LLP», «Partnership» → sociedad. `nil` si el nombre no lo dice (el usuario elige).
    public static func suggested(forName name: String) -> EntityType? {
        let words = name.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard let last = words.last else { return nil }
        let lastTwo = words.suffix(2).joined(separator: " ")
        if last == "llc" || lastTwo == "ltd co" || lastTwo == "limited company" { return .llc }
        if ["inc", "incorporated", "corp", "corporation"].contains(last) { return .cCorp }
        if ["lp", "llp", "lllp", "partnership"].contains(last) { return .partnership }
        return nil
    }
}
