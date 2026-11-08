import Foundation

/// Una línea del libro diario para exportar (paquete del contador).
public struct JournalExportRow: Hashable, Sendable {
    public var date: Date
    public var entryNumber: Int
    public var entryMemo: String
    public var source: String
    public var accountCode: String
    public var accountName: String
    public var debit: Int64
    public var credit: Int64
    public var lineMemo: String

    public init(date: Date, entryNumber: Int, entryMemo: String, source: String, accountCode: String, accountName: String,
                debit: Int64, credit: Int64, lineMemo: String = "") {
        self.date = date
        self.entryNumber = entryNumber
        self.entryMemo = entryMemo
        self.source = source
        self.accountCode = accountCode
        self.accountName = accountName
        self.debit = debit
        self.credit = credit
        self.lineMemo = lineMemo
    }
}

extension CSVExport {

    /// Libro diario: una fila por línea de asiento.
    public static func journal(_ rows: [JournalExportRow], calendar: Calendar = .current) -> String {
        var table: [[String]] = [[String(localized: "Fecha"), String(localized: "Asiento"), String(localized: "Concepto"), String(localized: "Origen"),
                                  String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Débito"), String(localized: "Crédito"),
                                  String(localized: "Nota")]]
        table += rows.map { row in
            [date(row.date, calendar: calendar), String(row.entryNumber), row.entryMemo, row.source, row.accountCode, row.accountName,
             row.debit > 0 ? amount(row.debit) : "", row.credit > 0 ? amount(row.credit) : "", row.lineMemo]
        }
        return lines(table)
    }

    /// Flujo de efectivo (método indirecto).
    public static func cashFlow(_ report: CashFlowStatement, calendar: Calendar = .current) -> String {
        func section(_ rows: [CashFlowStatement.Row]) -> [[String]] { rows.map { ["  \($0.account.name)", amount($0.amount)] } }
        var rows: [[String]] = [[String(localized: "Flujo de efectivo")],
                                [String(localized: "Periodo"), date(report.from, calendar: calendar), date(report.to, calendar: calendar)], [],
                                [String(localized: "Actividades de operación")],
                                ["  " + String(localized: "Ganancia neta"), amount(report.netIncome)]]
        rows += section(report.nonCashAdjustments)
        rows += section(report.workingCapital)
        rows.append([String(localized: "Efectivo neto de operación"), amount(report.operatingTotal)])
        rows.append([String(localized: "Actividades de inversión")])
        rows += section(report.investing)
        rows.append([String(localized: "Efectivo neto de inversión"), amount(report.investingTotal)])
        rows.append([String(localized: "Actividades de financiamiento")])
        rows += section(report.financing)
        rows.append([String(localized: "Efectivo neto de financiamiento"), amount(report.financingTotal)])
        rows += [[], [String(localized: "Variación neta del efectivo"), amount(report.netCashChange)],
                 [String(localized: "Efectivo al inicio"), amount(report.beginningCash)],
                 [String(localized: "Efectivo al final"), amount(report.endingCash)]]
        return lines(rows)
    }

    /// Deducibles por línea del formulario, con las cuentas de cada línea.
    public static func taxSummary(_ report: TaxFormSummary, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var rows: [[String]] = [[report.form.title, String(report.year)],
                                [String(localized: "Periodo"), date(report.from, calendar: calendar), date(report.to, calendar: calendar)], [],
                                [String(localized: "Línea"), String(localized: "Concepto"), String(localized: "Importe"), String(localized: "Deducible")]]
        for row in report.rows {
            rows.append([row.line.number, row.line.name(for: locale), amount(row.amount), amount(row.deductibleAmount)])
            rows += row.accounts.map { ["", "  \($0.account.code) · \($0.account.name)", amount($0.amount), ""] }
        }
        if !report.excluded.isEmpty {
            rows += [[], [String(localized: "Cuentas excluidas")]]
            rows += report.excluded.map { ["", "  \($0.account.code) · \($0.account.name)", amount($0.amount), ""] }
        }
        return lines(rows)
    }

    /// Real contra presupuesto, una fila por cuenta con el total y una columna por periodo.
    public static func budget(_ report: BudgetReport, calendar: Calendar = .current) -> String {
        var header = [String(localized: "Cuenta")]
        for period in report.periods {
            let label = date(period.start, calendar: calendar)
            header += ["\(label) · " + String(localized: "Presupuesto"), "\(label) · " + String(localized: "Real")]
        }
        header += [String(localized: "Presupuesto"), String(localized: "Real"), String(localized: "Diferencia")]
        var rows: [[String]] = [[String(localized: "Real contra presupuesto")], [], header]
        for row in report.income + report.expenses + report.other {
            var cells = ["\(row.account.code) · \(row.account.name)"]
            for index in report.periods.indices { cells += [amount(row.budget[index]), amount(row.actual[index])] }
            cells += [amount(row.totalBudget), amount(row.totalActual), amount(row.variance)]
            rows.append(cells)
        }
        return lines(rows)
    }
}
