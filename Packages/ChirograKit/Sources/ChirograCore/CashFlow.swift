import Foundation

// MARK: - Estado de flujo de efectivo, método indirecto (DISEÑO §4.7, fase 2)

/// Estado de flujo de efectivo por el método indirecto: utilidad neta + partidas que no mueven dinero ± variación del
/// capital de trabajo (operación); inversión; financiamiento. Por construcción cuadra con la variación del efectivo
/// (`isReconciled`) siempre que los asientos estén balanceados.
public struct CashFlowStatement: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var account: LedgerAccount
        /// Efecto en el efectivo del periodo: positivo = entra dinero (p. ej. baja la cuenta por cobrar o sube la deuda).
        public var amount: Int64
        public var id: UUID { account.id }
    }

    public var from: Date
    public var to: Date
    public var netIncome: Int64
    /// Partidas del resultado que no mueven dinero (depreciación, amortización…): se suman.
    public var nonCashAdjustments: [Row]
    /// Variación de cuentas por cobrar, inventario, cuentas por pagar, tarjetas, sales tax y demás corrientes.
    public var workingCapital: [Row]
    /// Activos fijos y otros activos.
    public var investing: [Row]
    /// Préstamos a largo plazo y patrimonio (aportaciones, retiros, saldos de apertura).
    public var financing: [Row]
    /// Efectivo (caja, bancos, fondos no depositados) al empezar y al terminar el periodo.
    public var beginningCash: Int64
    public var endingCash: Int64

    public var operatingTotal: Int64 { netIncome + Self.sum(nonCashAdjustments) + Self.sum(workingCapital) }
    public var investingTotal: Int64 { Self.sum(investing) }
    public var financingTotal: Int64 { Self.sum(financing) }
    public var netCashChange: Int64 { operatingTotal + investingTotal + financingTotal }
    /// Efectivo inicial + flujo neto = efectivo final.
    public var isReconciled: Bool { beginningCash + netCashChange == endingCash }

    static func sum(_ rows: [Row]) -> Int64 { rows.reduce(0) { $0 + $1.amount } }
}

/// Sección del flujo de efectivo de una cuenta de balance.
public enum CashFlowSection: Sendable, Hashable {
    case cash, operating, investing, financing

    public init(_ subtype: AccountSubtype) {
        switch subtype {
        case .cash, .bank, .undepositedFunds: self = .cash
        case .accountsReceivable, .inventory, .otherCurrentAsset,
             .accountsPayable, .creditCard, .salesTaxPayable, .otherCurrentLiability: self = .operating
        case .fixedAsset, .otherAsset: self = .investing
        case .longTermLiability, .ownersEquity, .ownersDraw, .retainedEarnings, .openingBalanceEquity: self = .financing
        // Ingresos y gastos no son de balance: van en la utilidad neta.
        case .sales, .salesDiscount, .otherIncome, .costOfGoodsSold, .operatingExpense, .otherExpense: self = .operating
        }
    }
}

extension ReportBuilder {

    /// Flujo de efectivo del periodo (`from` y `to` incluidos). Una línea de una cuenta de inversión o financiamiento en
    /// un asiento **sin** efectivo y **con** ingresos o gastos (la depreciación: Debe Gasto / Haber Depreciación
    /// acumulada) se presenta como partida no monetaria en la operación. Para reconocerlo hace falta `LedgerLine.entryID`;
    /// sin él, esas líneas van a su sección.
    public static func cashFlow(accounts: [LedgerAccount], lines: [LedgerLine], from: Date, to: Date) -> CashFlowStatement {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inPeriod = lines.filter { $0.date >= from && $0.date <= to }
        var entriesWithCash = Set<UUID>()
        var entriesWithResult = Set<UUID>()
        for line in inPeriod {
            guard let entry = line.entryID, let account = byID[line.accountID] else { continue }
            if !account.type.isBalanceSheet { entriesWithResult.insert(entry) }
            else if CashFlowSection(account.subtype) == .cash { entriesWithCash.insert(entry) }
        }

        var netIncome: Int64 = 0
        var nonCash: [UUID: Int64] = [:], working: [UUID: Int64] = [:], investing: [UUID: Int64] = [:], financing: [UUID: Int64] = [:]
        for line in inPeriod {
            guard let account = byID[line.accountID] else { continue }
            let effect = line.credit - line.debit
            guard account.type.isBalanceSheet else { netIncome += effect; continue }
            switch CashFlowSection(account.subtype) {
            case .cash: continue
            case .operating: working[account.id, default: 0] += effect
            case .investing, .financing:
                if let entry = line.entryID, entriesWithResult.contains(entry), !entriesWithCash.contains(entry) {
                    nonCash[account.id, default: 0] += effect
                } else if CashFlowSection(account.subtype) == .investing {
                    investing[account.id, default: 0] += effect
                } else {
                    financing[account.id, default: 0] += effect
                }
            }
        }

        func rows(_ sums: [UUID: Int64]) -> [CashFlowStatement.Row] {
            sums.compactMap { id, amount in
                guard amount != 0, let account = byID[id] else { return nil }
                return CashFlowStatement.Row(account: account, amount: amount)
            }
            .sorted { ($0.account.code, $0.account.name) < ($1.account.code, $1.account.name) }
        }
        func cash(_ include: (LedgerLine) -> Bool) -> Int64 {
            lines.reduce(0) { total, line in
                guard include(line), let account = byID[line.accountID], account.type.isBalanceSheet,
                      CashFlowSection(account.subtype) == .cash else { return total }
                return total + line.debit - line.credit
            }
        }
        return CashFlowStatement(from: from, to: to, netIncome: netIncome, nonCashAdjustments: rows(nonCash),
                                 workingCapital: rows(working), investing: rows(investing), financing: rows(financing),
                                 beginningCash: cash { $0.date < from }, endingCash: cash { $0.date <= to })
    }

    /// Reparte `total` en proporción a `weights`, que pueden tener signo (p. ej. las líneas de ingreso, impuesto y
    /// descuento de una factura): cada parte conserva el signo de su peso cuando `total` tiene el signo de la suma.
    /// La suma es exacta; los centavos que faltan van a los pesos mayores. Con suma de pesos 0, todo ceros.
    public static func allocateSigned(_ total: Int64, weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(0, +)
        guard sum != 0, total != 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { weight -> Int64 in
            let (quotient, _) = sum.dividingFullWidth(total.multipliedFullWidth(by: weight))
            return quotient
        }
        var leftover = total - shares.reduce(0, +)
        let order = weights.indices.sorted { abs(weights[$0]) > abs(weights[$1]) }
        var cursor = 0
        while leftover != 0, !order.isEmpty {
            let index = order[cursor % order.count]
            let step: Int64 = leftover > 0 ? 1 : -1
            shares[index] += step
            leftover -= step
            cursor += 1
        }
        return shares
    }
}
