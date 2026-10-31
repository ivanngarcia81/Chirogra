import ChirograCore
import ChirograData
import Foundation

/// Vista de solo lectura del libro mayor a partir de los resultados de `@Query`.
/// Los cálculos de saldos y reportes los hace `ChirograCore`; aquí solo se adaptan los modelos.
struct Ledger {
    let accounts: [Account]
    let ledgerAccounts: [LedgerAccount]
    let lines: [LedgerLine]

    init(accounts: [Account], lines: [JournalLine]) {
        self.accounts = accounts
        self.ledgerAccounts = accounts.map(\.ledgerAccount)
        self.lines = lines.compactMap { line in
            guard let entry = line.entry, entry.status == .posted, let accountID = line.account?.id else { return nil }
            return LedgerLine(accountID: accountID, date: entry.date, debit: line.debit, credit: line.credit)
        }
    }

    func balance(of account: Account, asOf: Date? = nil) -> Int64 {
        ReportBuilder.balance(of: account.ledgerAccount, lines: lines, asOf: asOf)
    }

    var moneyAccounts: [Account] {
        accounts.filter { $0.subtype.isMoneyAccount && !$0.isArchived }
    }

    /// Efectivo disponible: caja y bancos (las tarjetas restan).
    var availableCash: Int64 {
        moneyAccounts.reduce(0) { total, account in
            let balance = self.balance(of: account)
            switch account.subtype {
            case .creditCard: return total - balance
            case .undepositedFunds: return total
            default: return total + balance
            }
        }
    }

    func incomeStatement(_ interval: DateInterval) -> IncomeStatement {
        ReportBuilder.incomeStatement(accounts: ledgerAccounts, lines: lines, from: interval.start, to: interval.end)
    }
}

extension DateInterval {
    static func month(containing date: Date, offset: Int = 0, calendar: Calendar = .current) -> DateInterval {
        let shifted = calendar.date(byAdding: .month, value: offset, to: date) ?? date
        return calendar.dateInterval(of: .month, for: shifted) ?? DateInterval(start: shifted, duration: 0)
    }
}

extension Array where Element == Account {
    func filtered(_ include: (AccountSubtype) -> Bool) -> [Account] {
        filter { !$0.isArchived && $0.isLeaf && include($0.subtype) }
    }
}
