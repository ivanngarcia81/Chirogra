import ChirograCore
import Foundation

// MARK: - Deducibles: cuenta → línea del formulario (PLAN-FASE2 §5, docs/DATOS-V4.md §5)
//
// Cada cuenta de resultados va a una línea del Schedule C o del Form 1120-S. Por defecto, la que corresponde a su
// número en las plantillas del plan de cuentas (`ChartTemplate`); las cuentas propias, por su tipo de detalle. El
// usuario puede cambiarla (`Account.taxFormLineRaw`) o excluirla (`TaxFormCatalog.none`).

extension TaxForm {
    /// Formulario según el tipo de empresa: Schedule C para dueño único y LLC (se supone de un solo miembro), Form 1120-S
    /// para S corp. `nil` para sociedades (1065) y C corp (1120), que Chirogra aún no prepara.
    public static func forEntity(_ type: EntityType) -> TaxForm? {
        switch type {
        case .soleProprietorship, .llc: .scheduleC
        case .sCorp: .form1120S
        case .partnership, .cCorp: nil
        }
    }
}

extension TaxFormCatalog {

    /// Número de línea sugerido para una cuenta por su código en las plantillas y, si no está, por su tipo de detalle.
    /// `nil` = no va en el formulario (cuentas de balance).
    public static func defaultLineNumber(code: String, subtype: AccountSubtype, sector: BusinessSector, form: TaxForm) -> String? {
        guard !subtype.accountType.isBalanceSheet else { return nil }
        let byCode: [String: (scheduleC: String, form1120S: String)] = [
            "4000": ("1", "1a"), "4100": ("1", "1a"), "4900": ("2", "1b"),
            "7000": ("6", "5"), "7010": ("6", "K4"),
            "5000": (sector == .retail ? "36" : "38", "2"),
            "5100": (sector == .retail ? "39" : "37", "2"),
            "5200": ("39", "2"), "5300": ("39", "2"),
            "6000": ("8", "16"), "6050": ("9", "20"), "6100": ("27b", "20"), "6120": ("10", "20"),
            "6150": ("11", "20"), "6200": ("15", "20"), "6250": ("16b", "13"), "6300": ("17", "20"),
            "6350": ("18", "20"), "6400": ("20b", "11"), "6450": ("21", "9"), "6500": ("22", "20"),
            "6550": ("23", "12"), "6600": ("24a", "20"), "6650": ("24b", "20-meals"), "6700": ("25", "20"),
            "6750": ("27b", "20"), "6800": ("25", "20"), "6850": ("26", "8"), "6900": ("13", "14"),
            "8000": ("27b", "20"),
        ]
        if let mapped = byCode[code] { return form == .scheduleC ? mapped.scheduleC : mapped.form1120S }
        switch (subtype, form) {
        case (.sales, .scheduleC): return "1"
        case (.sales, .form1120S): return "1a"
        case (.salesDiscount, .scheduleC): return "2"
        case (.salesDiscount, .form1120S): return "1b"
        case (.otherIncome, .scheduleC): return "6"
        case (.otherIncome, .form1120S): return "5"
        case (.costOfGoodsSold, .scheduleC): return "39"
        case (.costOfGoodsSold, .form1120S): return "2"
        case (_, .scheduleC): return "27b"
        case (_, .form1120S): return "20"
        }
    }
}

extension Bookkeeper {

    /// Formulario de la empresa según su tipo (`nil` sin empresa o si no tiene formulario en Chirogra).
    public func taxForm() throws -> TaxForm? {
        try company().flatMap { TaxForm.forEntity($0.entityType) }
    }

    /// Línea del formulario de una cuenta: la elegida (`taxFormLineRaw`) si es de ese formulario; si no, la sugerida.
    /// `nil` si está excluida o no va en el formulario.
    public func taxLine(for account: Account, form: TaxForm, year: Int = 2025) throws -> TaxFormLine? {
        Self.taxLine(for: account, form: form, year: year, sector: try companySector())
    }

    func companySector() throws -> BusinessSector {
        try company().flatMap { BusinessSector(rawValue: $0.sectorRaw) } ?? .services
    }

    static func taxLine(for account: Account, form: TaxForm, year: Int, sector: BusinessSector) -> TaxFormLine? {
        let raw = account.taxFormLineRaw
        if raw == TaxFormCatalog.none { return nil }
        if !raw.isEmpty, let line = TaxFormCatalog.line(id: raw, year: year), line.form == form { return line }
        return TaxFormCatalog.defaultLineNumber(code: account.code, subtype: account.subtype, sector: sector, form: form)
            .flatMap { TaxFormCatalog.line($0, in: form, year: year) }
    }

    /// Elige la línea de una cuenta: el `id` de una `TaxFormLine`, `TaxFormCatalog.none` para excluirla o `nil` para
    /// volver a la sugerida.
    public func setTaxLine(_ lineID: String?, for account: Account) throws {
        if let lineID, lineID != TaxFormCatalog.none, TaxFormCatalog.line(id: lineID) == nil {
            throw BookkeepingError.invalidState(String(localized: "Esa línea del formulario no existe."))
        }
        account.taxFormLineRaw = lineID ?? ""
        audit("Account", account.id, "taxLine", String(localized: "Línea de impuestos de \(account.displayName): \(lineID ?? "—")"))
        try saveOrRollback()
    }

    /// Totales por línea del formulario en el periodo, en la base pedida. Sin `form`, el de la empresa (Schedule C si no
    /// tiene uno).
    public func taxSummary(from: Date, to: Date, basis: AccountingBasis = .accrual, form: TaxForm? = nil,
                           year: Int? = nil, calendar: Calendar = .current) throws -> TaxFormSummary {
        let form = try form ?? taxForm() ?? .scheduleC
        let year = year ?? calendar.component(.year, from: to)
        let accounts = try accounts(includeArchived: true)
        let sector = try companySector()
        var lineByAccount: [UUID: TaxFormLine] = [:]
        for account in accounts {
            if let line = Self.taxLine(for: account, form: form, year: year, sector: sector) { lineByAccount[account.id] = line }
        }
        return ReportBuilder.taxFormSummary(form: form, year: year, accounts: accounts.map(\.ledgerAccount),
                                            lines: try ledgerLines(basis: basis), from: from, to: to) { lineByAccount[$0.id] }
    }
}
