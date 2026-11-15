import Foundation

/// Estado de las conciliaciones bancarias a una fecha, para el paquete del contador (QA Hudson, H19): por cuenta de
/// banco o tarjeta, la última conciliación terminada, el saldo en libros y lo que queda sin conciliar; las conciliaciones
/// terminadas en el periodo; y las partidas sin conciliar. Los saldos van en el lado normal de la cuenta (en una tarjeta,
/// lo que se debe), como en la conciliación.
public struct ReconciliationReport: Sendable, Equatable {
    public struct AccountRow: Sendable, Equatable {
        public var code: String
        public var name: String
        /// Fecha y saldo final del extracto de la última conciliación terminada hasta la fecha del reporte.
        public var lastStatementDate: Date?
        public var lastStatementBalance: Int64?
        /// Saldo en libros a la fecha del reporte.
        public var bookBalance: Int64
        public var unclearedCount: Int
        /// Suma de las partidas sin conciliar (con su signo: + aumenta el saldo).
        public var unclearedTotal: Int64
        /// Hay una conciliación sin terminar.
        public var inProgress: Bool

        public init(code: String, name: String, lastStatementDate: Date?, lastStatementBalance: Int64?, bookBalance: Int64,
                    unclearedCount: Int, unclearedTotal: Int64, inProgress: Bool) {
            self.code = code
            self.name = name
            self.lastStatementDate = lastStatementDate
            self.lastStatementBalance = lastStatementBalance
            self.bookBalance = bookBalance
            self.unclearedCount = unclearedCount
            self.unclearedTotal = unclearedTotal
            self.inProgress = inProgress
        }
    }

    /// Conciliación terminada con fecha de extracto dentro del periodo.
    public struct Completed: Sendable, Equatable {
        public var code: String
        public var name: String
        public var statementDate: Date
        public var beginningBalance: Int64
        public var endingBalance: Int64
        public var clearedCount: Int
        public var closedAt: Date?

        public init(code: String, name: String, statementDate: Date, beginningBalance: Int64, endingBalance: Int64,
                    clearedCount: Int, closedAt: Date?) {
            self.code = code
            self.name = name
            self.statementDate = statementDate
            self.beginningBalance = beginningBalance
            self.endingBalance = endingBalance
            self.clearedCount = clearedCount
            self.closedAt = closedAt
        }
    }

    /// Partida sin conciliar a la fecha del reporte.
    public struct Uncleared: Sendable, Equatable {
        public var code: String
        public var name: String
        public var date: Date
        public var entryNumber: Int
        public var memo: String
        /// Con su signo: + aumenta el saldo de la cuenta.
        public var amount: Int64

        public init(code: String, name: String, date: Date, entryNumber: Int, memo: String, amount: Int64) {
            self.code = code
            self.name = name
            self.date = date
            self.entryNumber = entryNumber
            self.memo = memo
            self.amount = amount
        }
    }

    public var from: Date
    public var asOf: Date
    public var accounts: [AccountRow]
    public var completed: [Completed]
    public var uncleared: [Uncleared]

    public init(from: Date, asOf: Date, accounts: [AccountRow], completed: [Completed], uncleared: [Uncleared]) {
        self.from = from
        self.asOf = asOf
        self.accounts = accounts
        self.completed = completed
        self.uncleared = uncleared
    }

    /// Estado de una cuenta en palabras: «Conciliada al 2026-10-31», «Conciliación en curso», «Sin conciliar».
    public static func status(of row: AccountRow, calendar: Calendar = .current) -> String {
        if row.inProgress { return String(localized: "Conciliación en curso") }
        if let date = row.lastStatementDate { return String(localized: "Conciliada al \(CSVExport.date(date, calendar: calendar))") }
        return String(localized: "Nunca conciliada")
    }
}

extension CSVExport {
    /// «Conciliaciones.csv»: el estado por cuenta, las terminadas en el periodo y las partidas sin conciliar.
    public static func reconciliations(_ report: ReconciliationReport, calendar: Calendar = .current) -> String {
        let asOf = date(report.asOf, calendar: calendar)
        var rows: [[String]] = [[String(localized: "Conciliaciones bancarias")], [String(localized: "Al"), asOf], [],
                                [String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Último extracto"),
                                 String(localized: "Saldo del extracto"), String(localized: "Saldo en libros"),
                                 String(localized: "Partidas sin conciliar"), String(localized: "Importe sin conciliar"), String(localized: "Estado")]]
        rows += report.accounts.map { row in
            [row.code, row.name, row.lastStatementDate.map { date($0, calendar: calendar) } ?? "",
             row.lastStatementBalance.map(amount) ?? "", amount(row.bookBalance), String(row.unclearedCount),
             amount(row.unclearedTotal), ReconciliationReport.status(of: row, calendar: calendar)]
        }
        rows += [[], [String(localized: "Conciliaciones terminadas en el periodo")],
                 [String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Fecha del extracto"),
                  String(localized: "Saldo inicial"), String(localized: "Saldo final"), String(localized: "Partidas"),
                  String(localized: "Terminada el")]]
        if report.completed.isEmpty { rows.append([String(localized: "Ninguna")]) }
        rows += report.completed.map { item in
            [item.code, item.name, date(item.statementDate, calendar: calendar), amount(item.beginningBalance), amount(item.endingBalance),
             String(item.clearedCount), item.closedAt.map { date($0, calendar: calendar) } ?? ""]
        }
        rows += [[], [String(localized: "Partidas sin conciliar al \(asOf)")],
                 [String(localized: "Código"), String(localized: "Cuenta"), String(localized: "Fecha"), String(localized: "Asiento"),
                  String(localized: "Concepto"), String(localized: "Importe")]]
        if report.uncleared.isEmpty { rows.append([String(localized: "Ninguna")]) }
        rows += report.uncleared.map { item in
            [item.code, item.name, date(item.date, calendar: calendar), String(item.entryNumber), item.memo, amount(item.amount)]
        }
        return lines(rows)
    }
}
