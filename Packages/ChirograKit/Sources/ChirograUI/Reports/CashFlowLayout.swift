import ChirograCore
import Foundation

// MARK: - Estado de flujo de efectivo: cómo se presenta (fase 2, DISEÑO §4.7)
//
// `ReportBuilder.cashFlow` (método indirecto) da las cifras; aquí se ordenan en las secciones que ven la pantalla, el
// PDF y el CSV: operación (ganancia neta, partidas que no mueven dinero y capital de trabajo), inversión,
// financiamiento y la conciliación con el efectivo (variación, al inicio y al final). Al comparar, cada fila trae
// también el periodo anterior (con 0 en las cuentas que solo se movieron en uno de los dos).

enum CashFlowLayout {
    struct Line: Identifiable {
        enum Style { case line, total, grand }
        let key: String
        let name: String
        let amount: Int64
        var previous: Int64? = nil
        var style: Style = .line
        /// Cuenta de la fila (las de totales no tienen).
        var account: LedgerAccount? = nil
        var id: String { key }
    }

    struct Section: Identifiable {
        /// `nil`: la conciliación con el efectivo, en su propia tarjeta.
        let title: String?
        let lines: [Line]
        var id: String { title ?? "cash" }
    }

    static func sections(_ report: CashFlowStatement, previous: CashFlowStatement? = nil) -> [Section] {
        func rows(_ now: [CashFlowStatement.Row], _ before: [CashFlowStatement.Row]?, prefix: String) -> [Line] {
            let accounts = now.map(\.account) + (before ?? []).map(\.account).filter { old in !now.contains { $0.account.id == old.id } }
            return accounts.sorted { ($0.code, $0.name) < ($1.code, $1.name) }.map { account in
                Line(key: "\(prefix):\(account.id.uuidString)", name: account.name,
                     amount: now.first { $0.account.id == account.id }?.amount ?? 0,
                     previous: before.map { list in list.first { $0.account.id == account.id }?.amount ?? 0 }, account: account)
            }
        }
        let operating = [Line(key: "netIncome", name: String(localized: "Ganancia neta"), amount: report.netIncome, previous: previous?.netIncome)]
            + rows(report.nonCashAdjustments, previous?.nonCashAdjustments, prefix: "noncash")
            + rows(report.workingCapital, previous?.workingCapital, prefix: "working")
            + [Line(key: "operatingTotal", name: String(localized: "Efectivo neto de operación"), amount: report.operatingTotal,
                    previous: previous?.operatingTotal, style: .total)]
        let investing = rows(report.investing, previous?.investing, prefix: "investing")
            + [Line(key: "investingTotal", name: String(localized: "Efectivo neto de inversión"), amount: report.investingTotal,
                    previous: previous?.investingTotal, style: .total)]
        let financing = rows(report.financing, previous?.financing, prefix: "financing")
            + [Line(key: "financingTotal", name: String(localized: "Efectivo neto de financiamiento"), amount: report.financingTotal,
                    previous: previous?.financingTotal, style: .total)]
        let cash = [
            Line(key: "netChange", name: String(localized: "Variación neta del efectivo"), amount: report.netCashChange,
                 previous: previous?.netCashChange, style: .total),
            Line(key: "beginning", name: String(localized: "Efectivo al inicio"), amount: report.beginningCash, previous: previous?.beginningCash),
            Line(key: "ending", name: String(localized: "Efectivo al final"), amount: report.endingCash, previous: previous?.endingCash, style: .grand),
        ]
        return [
            Section(title: String(localized: "Actividades de operación"), lines: operating),
            Section(title: String(localized: "Actividades de inversión"), lines: investing),
            Section(title: String(localized: "Actividades de financiamiento"), lines: financing),
            Section(title: nil, lines: cash),
        ]
    }

    /// Qué es cada fila, para el inspector del Mac.
    static func explanation(for key: String) -> String {
        switch key.split(separator: ":").first.map(String.init) ?? key {
        case "netIncome": String(localized: "La ganancia del periodo en la base elegida. Es el punto de partida: después se quita lo que no movió dinero.")
        case "noncash": String(localized: "Gasto que no sacó dinero del banco (como la depreciación): se vuelve a sumar.")
        case "working": String(localized: "Si sube lo que te deben o el inventario, entra menos dinero del que dice la ganancia; si sube lo que debes, sale menos.")
        case "investing": String(localized: "Compra o venta de equipo, vehículos y otros activos de largo plazo.")
        case "financing": String(localized: "Préstamos, lo que pones o retiras del negocio y los saldos de apertura.")
        case "operatingTotal", "investingTotal", "financingTotal": String(localized: "Total de la sección: el dinero que entró (o salió, si es negativo) por esas actividades.")
        default: String(localized: "Efectivo al inicio + variación neta = efectivo al final, contando caja, bancos y fondos no depositados.")
        }
    }
}
