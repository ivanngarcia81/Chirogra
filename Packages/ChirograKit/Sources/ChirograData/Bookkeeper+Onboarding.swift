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
