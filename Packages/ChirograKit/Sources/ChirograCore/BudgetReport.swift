import Foundation

// MARK: - Presupuesto contra real (fase 2)

/// Real contra presupuesto por cuenta y periodo (mes, trimestre o año). Importes en el lado normal de cada cuenta:
/// lo ingresado en las de ingresos y lo gastado en las de gastos.
public struct BudgetReport: Hashable, Sendable {
    public struct Period: Hashable, Sendable {
        public var start: Date
        /// Último instante incluido.
        public var end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    public struct Row: Hashable, Sendable, Identifiable {
        public var account: LedgerAccount
        /// Por periodo, en el mismo orden que `BudgetReport.periods`.
        public var budget: [Int64]
        public var actual: [Int64]
        public var id: UUID { account.id }

        public var totalBudget: Int64 { budget.reduce(0, +) }
        public var totalActual: Int64 { actual.reduce(0, +) }
        /// Real − presupuesto.
        public var variance: Int64 { totalActual - totalBudget }
        public func variance(at index: Int) -> Int64 { actual[index] - budget[index] }
        /// Ingresar más de lo previsto o gastar menos es favorable.
        public var isFavorable: Bool { account.type == .expense ? variance <= 0 : variance >= 0 }
        /// Real como porcentaje del presupuesto (nil sin presupuesto).
        public var percentOfBudget: Decimal? {
            totalBudget == 0 ? nil : Decimal(totalActual) * 100 / Decimal(totalBudget)
        }
    }

    public var periods: [Period]
    public var income: [Row]
    public var expenses: [Row]
    /// Cuentas de balance con presupuesto (poco habitual), aparte.
    public var other: [Row]

    /// Utilidad neta presupuestada y real por periodo.
    public var budgetedNetIncome: [Int64] { Self.net(income, expenses, \.budget, count: periods.count) }
    public var actualNetIncome: [Int64] { Self.net(income, expenses, \.actual, count: periods.count) }

    static func net(_ income: [Row], _ expenses: [Row], _ values: KeyPath<Row, [Int64]>, count: Int) -> [Int64] {
        (0..<count).map { index in
            income.reduce(0) { $0 + $1[keyPath: values][index] } - expenses.reduce(0) { $0 + $1[keyPath: values][index] }
        }
    }
}

extension ReportBuilder {

    /// - Parameters:
    ///   - budget: importe presupuestado por cuenta y por periodo (índice en `periods`).
    ///   - periods: periodos consecutivos.
    /// Salen las cuentas con presupuesto y las de ingresos y gastos con movimientos en los periodos.
    public static func budgetVsActual(accounts: [LedgerAccount], lines: [LedgerLine], budget: [UUID: [Int64]],
                                      periods: [BudgetReport.Period]) -> BudgetReport {
        var actual: [UUID: [Int64]] = [:]
        for line in lines {
            guard let index = periods.firstIndex(where: { line.date >= $0.start && line.date <= $0.end }) else { continue }
            actual[line.accountID, default: Array(repeating: 0, count: periods.count)][index] += line.debit - line.credit
        }
        var income: [BudgetReport.Row] = [], expenses: [BudgetReport.Row] = [], other: [BudgetReport.Row] = []
        let zeros = Array(repeating: Int64(0), count: periods.count)
        for account in accounts.sorted(by: { ($0.code, $0.name) < ($1.code, $1.name) }) {
            let planned = budget[account.id].map { values in (0..<periods.count).map { $0 < values.count ? values[$0] : 0 } } ?? zeros
            let raw = actual[account.id] ?? zeros
            let real = raw.map { account.type.normalBalance == .debit ? $0 : -$0 }
            let hasBudget = planned.contains { $0 != 0 }
            let hasActual = real.contains { $0 != 0 }
            guard hasBudget || (hasActual && !account.type.isBalanceSheet) else { continue }
            let row = BudgetReport.Row(account: account, budget: planned, actual: real)
            switch account.type {
            case .income: income.append(row)
            case .expense: expenses.append(row)
            default: other.append(row)
            }
        }
        return BudgetReport(periods: periods, income: income, expenses: expenses, other: other)
    }
}
