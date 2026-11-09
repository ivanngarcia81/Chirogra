import Foundation

/// Cuenta tal como la ven los reportes (independiente de la persistencia).
public struct LedgerAccount: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var code: String
    public var name: String
    public var subtype: AccountSubtype

    public init(id: UUID, code: String, name: String, subtype: AccountSubtype) {
        self.id = id
        self.code = code
        self.name = name
        self.subtype = subtype
    }

    public var type: AccountType { subtype.accountType }
}

/// Línea contabilizada del diario: la única fuente de verdad de los reportes (§4.7).
public struct LedgerLine: Hashable, Sendable {
    public var accountID: UUID
    public var date: Date
    public var debit: Int64
    public var credit: Int64
    /// Asiento al que pertenece (opcional): el flujo de efectivo lo usa para reconocer las partidas no monetarias.
    public var entryID: UUID?

    public init(accountID: UUID, date: Date, debit: Int64, credit: Int64, entryID: UUID? = nil) {
        self.accountID = accountID
        self.date = date
        self.debit = debit
        self.credit = credit
        self.entryID = entryID
    }
}

public struct ReportRow: Hashable, Sendable, Identifiable {
    public var account: LedgerAccount
    /// Saldo en el lado normal de la cuenta (positivo = saldo habitual).
    public var amount: Int64
    public var id: UUID { account.id }

    public init(account: LedgerAccount, amount: Int64) {
        self.account = account
        self.amount = amount
    }
}

public struct TrialBalance: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var account: LedgerAccount
        public var debit: Int64
        public var credit: Int64
        public var id: UUID { account.id }
    }

    public var asOf: Date
    public var rows: [Row]
    public var totalDebit: Int64 { rows.reduce(0) { $0 + $1.debit } }
    public var totalCredit: Int64 { rows.reduce(0) { $0 + $1.credit } }
    public var isBalanced: Bool { totalDebit == totalCredit }
}

public struct IncomeStatement: Hashable, Sendable {
    public var from: Date
    public var to: Date
    public var income: [ReportRow]
    public var costOfGoodsSold: [ReportRow]
    public var expenses: [ReportRow]

    public var totalIncome: Int64 { income.reduce(0) { $0 + $1.amount } }
    public var totalCostOfGoodsSold: Int64 { costOfGoodsSold.reduce(0) { $0 + $1.amount } }
    public var grossProfit: Int64 { totalIncome - totalCostOfGoodsSold }
    public var totalExpenses: Int64 { expenses.reduce(0) { $0 + $1.amount } }
    public var netIncome: Int64 { grossProfit - totalExpenses }
}

public struct BalanceSheet: Hashable, Sendable {
    public var asOf: Date
    public var assets: [ReportRow]
    public var liabilities: [ReportRow]
    public var equity: [ReportRow]
    /// Resultado de ejercicios anteriores aún no cerrado contra Resultados acumulados.
    public var priorYearsEarnings: Int64
    /// Resultado del ejercicio en curso, calculado al vuelo.
    public var currentYearEarnings: Int64

    public var totalAssets: Int64 { assets.reduce(0) { $0 + $1.amount } }
    public var totalLiabilities: Int64 { liabilities.reduce(0) { $0 + $1.amount } }
    public var totalEquity: Int64 { equity.reduce(0) { $0 + $1.amount } + priorYearsEarnings + currentYearEarnings }
    /// Activo = Pasivo + Patrimonio.
    public var isBalanced: Bool { totalAssets == totalLiabilities + totalEquity }
}

public struct AgingReport: Hashable, Sendable {
    public enum Bucket: Int, CaseIterable, Hashable, Sendable {
        case current, days1to30, days31to60, days61to90, over90
    }

    public struct OpenItem: Hashable, Sendable {
        public var party: String
        public var document: String
        public var dueDate: Date
        public var balance: Int64

        public init(party: String, document: String, dueDate: Date, balance: Int64) {
            self.party = party
            self.document = document
            self.dueDate = dueDate
            self.balance = balance
        }
    }

    public struct Row: Hashable, Sendable, Identifiable {
        public var party: String
        public var amounts: [Bucket: Int64]
        public var total: Int64 { amounts.values.reduce(0, +) }
        public var id: String { party }
    }

    public var asOf: Date
    public var rows: [Row]

    public func total(for bucket: Bucket) -> Int64 { rows.reduce(0) { $0 + ($1.amounts[bucket] ?? 0) } }
    public var total: Int64 { rows.reduce(0) { $0 + $1.total } }
}

public enum ReportBuilder {

    /// Débitos y créditos acumulados por cuenta para las líneas que cumplen `include`.
    static func sums(_ lines: [LedgerLine], where include: (LedgerLine) -> Bool) -> [UUID: (debit: Int64, credit: Int64)] {
        var result: [UUID: (debit: Int64, credit: Int64)] = [:]
        for line in lines where include(line) {
            let current = result[line.accountID] ?? (0, 0)
            result[line.accountID] = (current.debit + line.debit, current.credit + line.credit)
        }
        return result
    }

    private static func sorted(_ accounts: [LedgerAccount]) -> [LedgerAccount] {
        accounts.sorted { ($0.code, $0.name) < ($1.code, $1.name) }
    }

    private static func rows(
        _ accounts: [LedgerAccount], sums: [UUID: (debit: Int64, credit: Int64)], matching: (LedgerAccount) -> Bool
    ) -> [ReportRow] {
        sorted(accounts.filter(matching)).compactMap { account in
            guard let total = sums[account.id] else { return nil }
            let amount = account.type.naturalBalance(debit: total.debit, credit: total.credit)
            return amount == 0 ? nil : ReportRow(account: account, amount: amount)
        }
    }

    /// Saldo natural de una cuenta a una fecha (incluida).
    public static func balance(of account: LedgerAccount, lines: [LedgerLine], asOf: Date? = nil) -> Int64 {
        let total = sums(lines) { $0.accountID == account.id && (asOf == nil || $0.date <= asOf!) }[account.id] ?? (0, 0)
        return account.type.naturalBalance(debit: total.debit, credit: total.credit)
    }

    public static func trialBalance(accounts: [LedgerAccount], lines: [LedgerLine], asOf: Date) -> TrialBalance {
        let totals = sums(lines) { $0.date <= asOf }
        let rows = sorted(accounts).compactMap { account -> TrialBalance.Row? in
            guard let total = totals[account.id] else { return nil }
            let net = total.debit - total.credit
            if net == 0 { return nil }
            return TrialBalance.Row(account: account, debit: max(net, 0), credit: max(-net, 0))
        }
        return TrialBalance(asOf: asOf, rows: rows)
    }

    public static func incomeStatement(accounts: [LedgerAccount], lines: [LedgerLine], from: Date, to: Date) -> IncomeStatement {
        let totals = sums(lines) { $0.date >= from && $0.date <= to }
        return IncomeStatement(
            from: from,
            to: to,
            income: rows(accounts, sums: totals) { $0.type == .income },
            costOfGoodsSold: rows(accounts, sums: totals) { $0.subtype == .costOfGoodsSold },
            expenses: rows(accounts, sums: totals) { $0.type == .expense && $0.subtype != .costOfGoodsSold }
        )
    }

    /// - Parameter fiscalYearStart: inicio del ejercicio en curso; separa el resultado del ejercicio
    ///   del de años anteriores. Si es `nil`, todo el resultado se considera del ejercicio.
    public static func balanceSheet(
        accounts: [LedgerAccount], lines: [LedgerLine], asOf: Date, fiscalYearStart: Date? = nil
    ) -> BalanceSheet {
        let totals = sums(lines) { $0.date <= asOf }
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        func earnings(_ include: (LedgerLine) -> Bool) -> Int64 {
            var result: Int64 = 0
            for line in lines where include(line) {
                guard let account = byID[line.accountID], !account.type.isBalanceSheet else { continue }
                result += line.credit - line.debit
            }
            return result
        }

        let prior = fiscalYearStart.map { start in earnings { $0.date < start && $0.date <= asOf } } ?? 0
        let current = earnings { $0.date <= asOf && (fiscalYearStart == nil || $0.date >= fiscalYearStart!) }

        return BalanceSheet(
            asOf: asOf,
            assets: rows(accounts, sums: totals) { $0.type == .asset },
            liabilities: rows(accounts, sums: totals) { $0.type == .liability },
            equity: rows(accounts, sums: totals) { $0.type == .equity },
            priorYearsEarnings: prior,
            currentYearEarnings: current
        )
    }

    public static func aging(items: [AgingReport.OpenItem], asOf: Date, calendar: Calendar = .current) -> AgingReport {
        var byParty: [String: [AgingReport.Bucket: Int64]] = [:]
        for item in items where item.balance != 0 {
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: item.dueDate), to: calendar.startOfDay(for: asOf)
            ).day ?? 0
            let bucket: AgingReport.Bucket = switch days {
            case ..<1: .current
            case 1...30: .days1to30
            case 31...60: .days31to60
            case 61...90: .days61to90
            default: .over90
            }
            byParty[item.party, default: [:]][bucket, default: 0] += item.balance
        }
        let rows = byParty.map { AgingReport.Row(party: $0.key, amounts: $0.value) }.sorted { $0.party < $1.party }
        return AgingReport(asOf: asOf, rows: rows)
    }
}

/// Movimiento de una cuenta tal como lo necesita el libro mayor.
public struct LedgerMovement: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var memo: String
    public var debit: Int64
    public var credit: Int64

    public init(id: UUID = UUID(), date: Date, memo: String = "", debit: Int64, credit: Int64) {
        self.id = id
        self.date = date
        self.memo = memo
        self.debit = debit
        self.credit = credit
    }
}

/// Libro mayor de una cuenta: saldo inicial, movimientos del rango con su efecto y saldo acumulado.
public struct AccountLedger: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var movement: LedgerMovement
        /// Efecto sobre el saldo de la cuenta según su naturaleza: positivo si lo aumenta.
        /// Un crédito aumenta pasivo, patrimonio e ingreso; un débito aumenta activo y gasto.
        public var effect: Int64
        public var balance: Int64
        public var id: UUID { movement.id }
        public var increasesBalance: Bool { effect > 0 }
    }

    public var account: LedgerAccount
    public var from: Date?
    public var to: Date?
    public var openingBalance: Int64
    public var rows: [Row]

    public var closingBalance: Int64 { rows.last?.balance ?? openingBalance }
    public var totalDebit: Int64 { rows.reduce(0) { $0 + $1.movement.debit } }
    public var totalCredit: Int64 { rows.reduce(0) { $0 + $1.movement.credit } }
}

extension ReportBuilder {
    /// - Parameters:
    ///   - from: inicio del rango (incluido); lo anterior se suma al saldo inicial.
    ///   - to: fin del rango (incluido).
    public static func accountLedger(
        account: LedgerAccount, movements: [LedgerMovement], from: Date? = nil, to: Date? = nil
    ) -> AccountLedger {
        let sorted = movements.sorted { $0.date < $1.date }
        let opening = sorted
            .filter { movement in from.map { movement.date < $0 } ?? false }
            .reduce(0) { $0 + account.type.naturalBalance(debit: $1.debit, credit: $1.credit) }
        var running = opening
        let rows = sorted
            .filter { movement in (from.map { movement.date >= $0 } ?? true) && (to.map { movement.date <= $0 } ?? true) }
            .map { movement -> AccountLedger.Row in
                let effect = account.type.naturalBalance(debit: movement.debit, credit: movement.credit)
                running += effect
                return AccountLedger.Row(movement: movement, effect: effect, balance: running)
            }
        return AccountLedger(account: account, from: from, to: to, openingBalance: opening, rows: rows)
    }
}
