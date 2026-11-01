import Foundation

/// Exportación de reportes a CSV (DISEÑO §3.1). Cada reporte tiene su propio formato, con periodo,
/// secciones y subtotales; los importes van con dos decimales y punto ("1250.50") para hojas de cálculo.
public enum CSVExport {

    /// Centavos → "1250.50" / "-18.40".
    public static func amount(_ minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let value = minorUnits.magnitude
        let cents = value % 100
        return "\(sign)\(value / 100).\(cents < 10 ? "0" : "")\(cents)"
    }

    /// Fecha de negocio "2026-10-31" en la zona horaria indicada.
    public static func date(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func field(_ value: String) -> String {
        value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            : value
    }

    static func lines(_ rows: [[String]]) -> String {
        rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    public static func incomeStatement(_ report: IncomeStatement, previous: IncomeStatement? = nil, calendar: Calendar = .current) -> String {
        let header = previous == nil ? [String(localized: "Cuenta"), String(localized: "Importe")] : [String(localized: "Cuenta"), String(localized: "Actual"), String(localized: "Anterior")]
        func values(_ current: Int64, _ prior: Int64?) -> [String] {
            previous == nil ? [amount(current)] : [amount(current), amount(prior ?? 0)]
        }
        func section(_ title: String, _ rows: [ReportRow], _ prior: [ReportRow]?, total: (String, Int64, Int64?)) -> [[String]] {
            let ids = rows.map(\.account.id) + (prior ?? []).map(\.account.id).filter { id in !rows.contains { $0.account.id == id } }
            let all = rows + (prior ?? []).filter { row in !rows.contains { $0.account.id == row.account.id } }
            var result: [[String]] = [[title]]
            for id in ids {
                guard let account = all.first(where: { $0.account.id == id })?.account else { continue }
                let current = rows.first { $0.account.id == id }?.amount ?? 0
                let prior = prior?.first { $0.account.id == id }?.amount
                result.append(["  \(account.name)"] + values(current, prior))
            }
            result.append([total.0] + values(total.1, total.2))
            return result
        }

        var rows: [[String]] = [[String(localized: "Estado de resultados")], [String(localized: "Periodo"), date(report.from, calendar: calendar), date(report.to, calendar: calendar)], [], header]
        rows += section(String(localized: "Ingresos"), report.income, previous?.income, total: (String(localized: "Total ingresos"), report.totalIncome, previous?.totalIncome))
        rows += section(String(localized: "Costo de ventas"), report.costOfGoodsSold, previous?.costOfGoodsSold,
                        total: (String(localized: "Total costo de ventas"), report.totalCostOfGoodsSold, previous?.totalCostOfGoodsSold))
        rows.append([String(localized: "Utilidad bruta")] + values(report.grossProfit, previous?.grossProfit))
        rows += section(String(localized: "Gastos"), report.expenses, previous?.expenses, total: (String(localized: "Total gastos"), report.totalExpenses, previous?.totalExpenses))
        rows.append([String(localized: "Ganancia neta")] + values(report.netIncome, previous?.netIncome))
        return lines(rows)
    }

    public static func balanceSheet(_ report: BalanceSheet, calendar: Calendar = .current) -> String {
        func section(_ title: String, _ rows: [ReportRow]) -> [[String]] {
            [[title]] + rows.map { ["  \($0.account.code)", $0.account.name, amount($0.amount)] }
        }
        var rows: [[String]] = [[String(localized: "Balance general")], [String(localized: "Al"), date(report.asOf, calendar: calendar)], [], [String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Importe")]]
        rows += section(String(localized: "Activos"), report.assets)
        rows.append([String(localized: "Total activos"), "", amount(report.totalAssets)])
        rows += section(String(localized: "Pasivos"), report.liabilities)
        rows.append([String(localized: "Total pasivos"), "", amount(report.totalLiabilities)])
        rows += section(String(localized: "Patrimonio"), report.equity)
        rows.append(["", String(localized: "Resultados de años anteriores"), amount(report.priorYearsEarnings)])
        rows.append(["", String(localized: "Resultado del ejercicio"), amount(report.currentYearEarnings)])
        rows.append([String(localized: "Total patrimonio"), "", amount(report.totalEquity)])
        rows.append([String(localized: "Total pasivo + patrimonio"), "", amount(report.totalLiabilities + report.totalEquity)])
        return lines(rows)
    }

    public static func trialBalance(_ report: TrialBalance, calendar: Calendar = .current) -> String {
        var rows: [[String]] = [[String(localized: "Balanza de comprobación")], [String(localized: "Al"), date(report.asOf, calendar: calendar)], [], [String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Debe"), String(localized: "Haber")]]
        rows += report.rows.map { [$0.account.code, $0.account.name, amount($0.debit), amount($0.credit)] }
        rows.append([String(localized: "Totales"), "", amount(report.totalDebit), amount(report.totalCredit)])
        return lines(rows)
    }

    public static func aging(_ report: AgingReport, title: String, partyTitle: String, calendar: Calendar = .current) -> String {
        let buckets = AgingReport.Bucket.allCases
        var rows: [[String]] = [[title], ["Al", date(report.asOf, calendar: calendar)], [],
                                [partyTitle, String(localized: "Corriente"), "1-30", "31-60", "61-90", String(localized: "Más de 90"), String(localized: "Total")]]
        rows += report.rows.map { row in [row.party] + buckets.map { amount(row.amounts[$0] ?? 0) } + [amount(row.total)] }
        rows.append([String(localized: "Total")] + buckets.map { amount(report.total(for: $0)) } + [amount(report.total)])
        return lines(rows)
    }
}

extension CSVExport {
    public static func salesTaxSummary(_ report: SalesTaxSummary, calendar: Calendar = .current) -> String {
        var rows: [[String]] = [[String(localized: "Resumen de sales tax")], [String(localized: "Periodo"), date(report.from, calendar: calendar), date(report.to, calendar: calendar)], [],
                                [String(localized: "Ventas totales"), amount(report.totalSales)],
                                [String(localized: "Ventas gravables"), amount(report.taxableSales)],
                                [String(localized: "Ventas no gravables"), amount(report.nonTaxableSales)],
                                [String(localized: "Ventas exentas"), amount(report.exemptSales)], [],
                                [String(localized: "Tasa"), String(localized: "Porcentaje"), String(localized: "Ventas gravables"), String(localized: "Impuesto")]]
        rows += report.rows.map { [$0.name, "\($0.percent)", amount($0.taxableSales), amount($0.tax)] }
        rows.append([String(localized: "Total impuesto"), "", "", amount(report.totalTax)])
        return lines(rows)
    }
}
