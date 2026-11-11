import ChirograCore
import Foundation
import SwiftData

// MARK: - Presupuestos (PLAN-FASE2 §6, docs/DATOS-V4.md §3)
//
// Un `Budget` por año fiscal (puede haber varios: «Base», «Optimista»…) con importes por cuenta y mes natural
// (`BudgetLine`). Real contra presupuesto se calcula de las líneas contabilizadas, por mes, trimestre o año fiscal.

/// Cómo se agrupan los meses en real contra presupuesto.
public enum BudgetGrouping: String, CaseIterable, Sendable {
    case month, quarter, year
}

/// Un mes del año fiscal de un presupuesto.
public struct BudgetMonth: Hashable, Sendable {
    /// Mes natural (1–12) y su año.
    public var month: Int
    public var year: Int
    public var start: Date
    /// Último instante del mes.
    public var end: Date
}

extension Bookkeeper {

    /// Presupuestos de la empresa, del año más reciente al más antiguo.
    public func budgets() throws -> [Budget] {
        try fetch(Budget.self).sorted { ($1.fiscalYear, $0.createdAt) < ($0.fiscalYear, $1.createdAt) }
    }

    /// Crea un presupuesto vacío o copia de otro (`copying`), opcionalmente ajustado por `factorPercent` (110 = +10 %).
    @discardableResult
    public func createBudget(name: String, fiscalYear: Int, copying source: Budget? = nil, factorPercent: Int = 100) throws -> Budget {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "El presupuesto necesita un nombre.")) }
        let budget = Budget(name: name, fiscalYear: fiscalYear)
        insert(budget)
        for line in source?.lines ?? [] {
            let amount = (line.amount * Int64(factorPercent)).dividedRoundingHalfAwayFromZero(by: 100)
            guard amount != 0 else { continue }
            let copy = BudgetLine(accountID: line.accountID, month: line.month, amount: amount)
            copy.budget = budget
            insert(copy)
        }
        // Sin repetir el año si el nombre ya lo lleva («Presupuesto 2026»).
        let title = name.contains(String(fiscalYear)) ? name : "\(name) \(String(fiscalYear))"
        audit("Budget", budget.id, "create", String(localized: "Presupuesto creado: \(title)"))
        try saveOrRollback()
        return budget
    }

    /// Crea un presupuesto con lo real de un año fiscal anterior (cuentas de ingresos y gastos), ajustado por `factorPercent`.
    @discardableResult
    public func createBudget(name: String, fiscalYear: Int, fromActualsOf sourceYear: Int, factorPercent: Int = 100,
                             calendar: Calendar = .current) throws -> Budget {
        let budget = try createBudget(name: name, fiscalYear: fiscalYear)
        let months = try self.months(ofFiscalYear: sourceYear, calendar: calendar)
        let lines = try ledgerLines()
        for account in try accounts() where !account.type.isBalanceSheet {
            for month in months {
                let raw = lines.filter { $0.accountID == account.id && $0.date >= month.start && $0.date <= month.end }
                    .reduce(Int64(0)) { $0 + $1.debit - $1.credit }
                let natural = account.type.normalBalance == .debit ? raw : -raw
                let amount = (natural * Int64(factorPercent)).dividedRoundingHalfAwayFromZero(by: 100)
                guard amount != 0 else { continue }
                let line = BudgetLine(accountID: account.id, month: month.month, amount: amount)
                line.budget = budget
                insert(line)
            }
        }
        try saveOrRollback()
        return budget
    }

    public func renameBudget(_ budget: Budget, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "El presupuesto necesita un nombre.")) }
        var changes = AuditChanges()
        changes.field(String(localized: "Nombre"), budget.name, name)
        if !changes.isEmpty { audit("Budget", budget.id, "update", String(localized: "Presupuesto renombrado: \(name)"), changes: changes) }
        budget.name = name
        try saveOrRollback()
    }

    public func deleteBudget(_ budget: Budget) throws {
        audit("Budget", budget.id, "delete", String(localized: "Presupuesto borrado: \(budget.name)"))
        context.delete(budget)
        try saveOrRollback()
    }

    /// Fija el importe de una cuenta en un mes (1–12, natural). 0 quita la línea.
    public func setBudgetAmount(_ amount: Int64, account: Account, month: Int, in budget: Budget) throws {
        try setAmounts([month: amount], account: account, in: budget)
        try saveOrRollback()
    }

    /// Fija los 12 importes de una cuenta, en el orden del año fiscal (el primero es el del mes de inicio).
    public func setBudgetAmounts(_ amounts: [Int64], account: Account, in budget: Budget, calendar: Calendar = .current) throws {
        guard amounts.count == 12 else { throw BookkeepingError.invalidState(String(localized: "Hacen falta los 12 meses.")) }
        let months = try self.months(ofFiscalYear: budget.fiscalYear, calendar: calendar)
        try setAmounts(Dictionary(uniqueKeysWithValues: zip(months.map(\.month), amounts)), account: account, in: budget)
        try saveOrRollback()
    }

    /// Reparte un importe anual entre los 12 meses a partes iguales (los centavos que sobran, en los primeros meses).
    public func setAnnualBudget(_ total: Int64, account: Account, in budget: Budget, calendar: Calendar = .current) throws {
        let shares = PostingRules.allocate(abs(total), weights: Array(repeating: 1, count: 12)).map { total < 0 ? -$0 : $0 }
        try setBudgetAmounts(shares, account: account, in: budget, calendar: calendar)
    }

    private func setAmounts(_ amounts: [Int: Int64], account: Account, in budget: Budget) throws {
        for (month, amount) in amounts {
            guard (1...12).contains(month) else { throw BookkeepingError.invalidState(String(localized: "El mes debe estar entre 1 y 12.")) }
            let existing = (budget.lines ?? []).filter { $0.accountID == account.id && $0.month == month }
            for extra in existing.dropFirst() { context.delete(extra) }
            if amount == 0 {
                existing.first.map(context.delete)
            } else if let line = existing.first {
                line.amount = amount
            } else {
                let line = BudgetLine(accountID: account.id, month: month, amount: amount)
                line.budget = budget
                insert(line)
            }
        }
    }

    /// Los 12 meses del año fiscal que empieza en `fiscalYear` (según el mes de inicio de la empresa).
    public func months(ofFiscalYear fiscalYear: Int, calendar: Calendar = .current) throws -> [BudgetMonth] {
        let startMonth = try company()?.fiscalYearStartMonth ?? 1
        guard let first = calendar.date(from: DateComponents(year: fiscalYear, month: startMonth, day: 1)) else { return [] }
        return (0..<12).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: offset, to: first),
                  let next = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: start)
            return BudgetMonth(month: parts.month ?? 1, year: parts.year ?? fiscalYear, start: start, end: next.addingTimeInterval(-1))
        }
    }

    /// Real contra presupuesto del año fiscal del presupuesto, agrupado por mes, trimestre o año, en la base pedida.
    public func budgetVsActual(_ budget: Budget, grouping: BudgetGrouping = .month, basis: AccountingBasis = .accrual,
                               calendar: Calendar = .current) throws -> BudgetReport {
        let months = try self.months(ofFiscalYear: budget.fiscalYear, calendar: calendar)
        let size = switch grouping { case .month: 1; case .quarter: 3; case .year: 12 }
        let groups = stride(from: 0, to: months.count, by: size).map { Array(months[$0..<min($0 + size, months.count)]) }
        let periods = groups.compactMap { group in group.first.flatMap { first in group.last.map { BudgetReport.Period(start: first.start, end: $0.end) } } }
        var planned: [UUID: [Int64]] = [:]
        for line in budget.lines ?? [] {
            guard let accountID = line.accountID, let index = groups.firstIndex(where: { $0.contains { $0.month == line.month } }) else { continue }
            planned[accountID, default: Array(repeating: 0, count: periods.count)][index] += line.amount
        }
        return ReportBuilder.budgetVsActual(accounts: try ledgerAccounts(), lines: try ledgerLines(basis: basis), budget: planned, periods: periods)
    }
}
