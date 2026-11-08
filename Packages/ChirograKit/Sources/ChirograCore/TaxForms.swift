import Foundation

// MARK: - Deducibles: líneas del Schedule C y del Form 1120-S (fase 2, PLAN-FASE2 §5)
//
// Chirogra no calcula impuestos sobre la renta: prepara los números por línea del formulario para el contador
// (DISEÑO §4.8). El catálogo es el de los formularios de 2025; 2026 usa el mismo hasta que el IRS publique el definitivo
// (revisarlo entonces: si cambia una línea, se añade aquí con su año).

/// Formulario de la declaración del negocio.
public enum TaxForm: String, CaseIterable, Sendable, Codable {
    /// Schedule C (Form 1040): dueño único y LLC de un solo miembro.
    case scheduleC
    /// Form 1120-S: S corporation.
    case form1120S

    public var title: String {
        switch self {
        case .scheduleC: "Schedule C (Form 1040)"
        case .form1120S: "Form 1120-S"
        }
    }
}

/// Una línea del formulario.
public struct TaxFormLine: Hashable, Sendable, Identifiable {
    /// Si la línea suma ingresos (haber − debe) o deducciones (debe − haber).
    public enum Kind: String, Sendable, Hashable { case income, deduction }

    public var form: TaxForm
    /// Número como en el formulario: «1», «24b», «36», «K4», «20-meals» (parte de la 20 al 50 %).
    public var number: String
    /// Nombre oficial (en inglés, como en el formulario) y en español.
    public var english: String
    public var spanish: String
    public var kind: Kind
    /// Parte del formulario («Part I», «Part II», «Part III»…).
    public var part: String
    /// Línea del formulario en la que se suma esta (Part III → 4 en el Schedule C; «20-meals» → 20).
    public var rollsUpTo: String?
    /// Porcentaje deducible (comidas de negocio: 50).
    public var deductiblePercent: Int

    public init(form: TaxForm, number: String, english: String, spanish: String, kind: Kind = .deduction, part: String,
                rollsUpTo: String? = nil, deductiblePercent: Int = 100) {
        self.form = form
        self.number = number
        self.english = english
        self.spanish = spanish
        self.kind = kind
        self.part = part
        self.rollsUpTo = rollsUpTo
        self.deductiblePercent = deductiblePercent
    }

    /// Lo que se guarda en `Account.taxFormLineRaw`: «scheduleC:22».
    public var id: String { "\(form.rawValue):\(number)" }

    public func name(for locale: Locale) -> String {
        locale.language.languageCode?.identifier == "es" ? spanish : english
    }

    /// «Line 22 · Supplies».
    public func label(for locale: Locale) -> String {
        let prefix = locale.language.languageCode?.identifier == "es" ? "Línea" : "Line"
        return "\(prefix) \(number) · \(name(for: locale))"
    }
}

public enum TaxFormCatalog {
    /// Valor de `Account.taxFormLineRaw` para excluir una cuenta (no deducible o no va en el formulario).
    public static let none = "none"
    /// Años con catálogo.
    public static let supportedYears = [2025, 2026]

    public static func lines(for form: TaxForm, year: Int = 2025) -> [TaxFormLine] {
        // 2026: el mismo catálogo que 2025 hasta que salga el formulario definitivo.
        switch form {
        case .scheduleC: scheduleC2025
        case .form1120S: form1120S2025
        }
    }

    public static func line(id: String, year: Int = 2025) -> TaxFormLine? {
        guard let form = TaxForm(rawValue: String(id.prefix { $0 != ":" })) else { return nil }
        return lines(for: form, year: year).first { $0.id == id }
    }

    public static func line(_ number: String, in form: TaxForm, year: Int = 2025) -> TaxFormLine? {
        lines(for: form, year: year).first { $0.number == number }
    }

    static let scheduleC2025: [TaxFormLine] = {
        func line(_ number: String, _ english: String, _ spanish: String, _ kind: TaxFormLine.Kind = .deduction, part: String = "Part II",
                  rollsUpTo: String? = nil, percent: Int = 100) -> TaxFormLine {
            TaxFormLine(form: .scheduleC, number: number, english: english, spanish: spanish, kind: kind, part: part,
                        rollsUpTo: rollsUpTo, deductiblePercent: percent)
        }
        return [
            line("1", "Gross receipts or sales", "Ingresos brutos o ventas", .income, part: "Part I"),
            line("2", "Returns and allowances", "Devoluciones y descuentos", part: "Part I"),
            line("4", "Cost of goods sold", "Costo de los bienes vendidos", part: "Part I"),
            line("6", "Other income", "Otros ingresos", .income, part: "Part I"),
            line("8", "Advertising", "Publicidad"),
            line("9", "Car and truck expenses", "Gastos de vehículo"),
            line("10", "Commissions and fees", "Comisiones y honorarios"),
            line("11", "Contract labor", "Trabajo por contrato"),
            line("12", "Depletion", "Agotamiento"),
            line("13", "Depreciation and section 179 expense deduction", "Depreciación y deducción de la sección 179"),
            line("14", "Employee benefit programs", "Programas de beneficios a empleados"),
            line("15", "Insurance (other than health)", "Seguros (salvo de salud)"),
            line("16a", "Interest: mortgage (paid to banks, etc.)", "Intereses hipotecarios"),
            line("16b", "Interest: other", "Otros intereses"),
            line("17", "Legal and professional services", "Servicios legales y profesionales"),
            line("18", "Office expense", "Gastos de oficina"),
            line("19", "Pension and profit-sharing plans", "Planes de pensiones y de participación en las ganancias"),
            line("20a", "Rent or lease: vehicles, machinery, and equipment", "Alquiler de vehículos, maquinaria y equipo"),
            line("20b", "Rent or lease: other business property", "Alquiler de otros bienes del negocio"),
            line("21", "Repairs and maintenance", "Reparaciones y mantenimiento"),
            line("22", "Supplies (not included in Part III)", "Suministros (fuera de la parte III)"),
            line("23", "Taxes and licenses", "Impuestos y licencias"),
            line("24a", "Travel", "Viajes"),
            line("24b", "Deductible meals", "Comidas deducibles (50 %)", percent: 50),
            line("25", "Utilities", "Servicios públicos"),
            line("26", "Wages (less employment credits)", "Sueldos (menos créditos por empleo)"),
            line("27a", "Energy efficient commercial buildings deduction", "Deducción por edificios comerciales eficientes"),
            line("27b", "Other expenses", "Otros gastos"),
            line("30", "Business use of your home", "Uso de la vivienda para el negocio"),
            line("36", "Purchases less cost of items withdrawn for personal use", "Compras (menos lo retirado para uso personal)",
                 part: "Part III", rollsUpTo: "4"),
            line("37", "Cost of labor", "Costo de mano de obra", part: "Part III", rollsUpTo: "4"),
            line("38", "Materials and supplies", "Materiales y suministros", part: "Part III", rollsUpTo: "4"),
            line("39", "Other costs", "Otros costos", part: "Part III", rollsUpTo: "4"),
        ]
    }()

    static let form1120S2025: [TaxFormLine] = {
        func line(_ number: String, _ english: String, _ spanish: String, _ kind: TaxFormLine.Kind = .deduction,
                  part: String = "Deductions", rollsUpTo: String? = nil, percent: Int = 100) -> TaxFormLine {
            TaxFormLine(form: .form1120S, number: number, english: english, spanish: spanish, kind: kind, part: part,
                        rollsUpTo: rollsUpTo, deductiblePercent: percent)
        }
        return [
            line("1a", "Gross receipts or sales", "Ingresos brutos o ventas", .income, part: "Income"),
            line("1b", "Returns and allowances", "Devoluciones y descuentos", part: "Income"),
            line("2", "Cost of goods sold (Form 1125-A)", "Costo de los bienes vendidos (Form 1125-A)", part: "Income"),
            line("5", "Other income (loss)", "Otros ingresos", .income, part: "Income"),
            line("7", "Compensation of officers", "Compensación de directivos"),
            line("8", "Salaries and wages", "Sueldos y salarios"),
            line("9", "Repairs and maintenance", "Reparaciones y mantenimiento"),
            line("10", "Bad debts", "Cuentas incobrables"),
            line("11", "Rents", "Alquileres"),
            line("12", "Taxes and licenses", "Impuestos y licencias"),
            line("13", "Interest", "Intereses"),
            line("14", "Depreciation not claimed on Form 1125-A or elsewhere", "Depreciación"),
            line("15", "Depletion", "Agotamiento"),
            line("16", "Advertising", "Publicidad"),
            line("17", "Pension, profit-sharing, etc., plans", "Planes de pensiones y de participación en las ganancias"),
            line("18", "Employee benefit programs", "Programas de beneficios a empleados"),
            line("19", "Energy efficient commercial buildings deduction", "Deducción por edificios comerciales eficientes"),
            line("20", "Other deductions", "Otras deducciones"),
            line("20-meals", "Other deductions: business meals (50%)", "Otras deducciones: comidas de negocio (50 %)",
                 rollsUpTo: "20", percent: 50),
            line("K4", "Interest income (Schedule K, line 4)", "Intereses ganados (Schedule K, línea 4)", .income, part: "Schedule K"),
        ]
    }()
}

/// Totales por línea del formulario en un periodo.
public struct TaxFormSummary: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var line: TaxFormLine
        /// Importe del periodo (positivo: ingresos en las de ingreso, gastos en las de deducción).
        public var amount: Int64
        /// Parte deducible (`amount` × `deductiblePercent`).
        public var deductibleAmount: Int64
        /// Cuentas que forman la línea, con su importe.
        public var accounts: [ReportRow]
        public var id: String { line.id }
    }

    public var form: TaxForm
    public var year: Int
    public var from: Date
    public var to: Date
    public var rows: [Row]
    /// Cuentas de resultados con movimientos que se excluyeron (`TaxFormCatalog.none`).
    public var excluded: [ReportRow]

    /// Total de una línea con lo que se suma en ella (la 4 del Schedule C con la parte III, la 20 con «20-meals»).
    public func total(of number: String, deductible: Bool = true) -> Int64 {
        rows.filter { $0.line.number == number || $0.line.rollsUpTo == number }
            .reduce(0) { $0 + (deductible ? $1.deductibleAmount : $1.amount) }
    }

    public var totalIncome: Int64 { rows.filter { $0.line.kind == .income }.reduce(0) { $0 + $1.amount } }
    public var totalDeductions: Int64 { rows.filter { $0.line.kind == .deduction }.reduce(0) { $0 + $1.deductibleAmount } }
}

extension ReportBuilder {
    /// Suma las líneas contabilizadas del periodo por línea del formulario. `lineFor` da la línea de cada cuenta (`nil` =
    /// excluida); solo cuentan las de resultados (ingresos y gastos).
    public static func taxFormSummary(form: TaxForm, year: Int, accounts: [LedgerAccount], lines: [LedgerLine], from: Date, to: Date,
                                      lineFor: (LedgerAccount) -> TaxFormLine?) -> TaxFormSummary {
        let totals = sums(lines) { $0.date >= from && $0.date <= to }
        var byLine: [String: (line: TaxFormLine, amount: Int64, accounts: [ReportRow])] = [:]
        var excluded: [ReportRow] = []
        for account in accounts.sorted(by: { ($0.code, $0.name) < ($1.code, $1.name) }) where !account.type.isBalanceSheet {
            guard let total = totals[account.id], total.debit != total.credit else { continue }
            guard let line = lineFor(account) else {
                excluded.append(ReportRow(account: account, amount: account.type.naturalBalance(debit: total.debit, credit: total.credit)))
                continue
            }
            let amount = line.kind == .income ? total.credit - total.debit : total.debit - total.credit
            var entry = byLine[line.id] ?? (line, 0, [])
            entry.amount += amount
            entry.accounts.append(ReportRow(account: account, amount: amount))
            byLine[line.id] = entry
        }
        let order = TaxFormCatalog.lines(for: form, year: year).map(\.id)
        let rows = byLine.values.map { entry in
            TaxFormSummary.Row(line: entry.line, amount: entry.amount,
                               deductibleAmount: (entry.amount * Int64(entry.line.deductiblePercent)).dividedRoundingHalfAwayFromZero(by: 100),
                               accounts: entry.accounts)
        }
        .sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        return TaxFormSummary(form: form, year: year, from: from, to: to, rows: rows, excluded: excluded)
    }
}
