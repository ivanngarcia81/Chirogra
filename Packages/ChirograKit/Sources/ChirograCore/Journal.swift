import Foundation

/// Origen de un asiento: manual o generado por un documento de negocio.
public enum EntrySource: String, CaseIterable, Sendable, Codable {
    case manual
    case invoice
    case creditNote
    case paymentReceived
    case bill
    case billPayment
    case expense
    case salesTaxPayment
    case reversal
    case opening
}

/// Línea de un asiento: un importe al debe **o** al haber, en unidades mínimas.
public struct JournalLineDraft: Hashable, Sendable {
    public var accountID: UUID
    public var debit: Int64
    public var credit: Int64
    public var memo: String

    public init(accountID: UUID, debit: Int64 = 0, credit: Int64 = 0, memo: String = "") {
        self.accountID = accountID
        self.debit = debit
        self.credit = credit
        self.memo = memo
    }

    public static func debit(_ accountID: UUID, _ amount: Int64, memo: String = "") -> JournalLineDraft {
        JournalLineDraft(accountID: accountID, debit: amount, memo: memo)
    }

    public static func credit(_ accountID: UUID, _ amount: Int64, memo: String = "") -> JournalLineDraft {
        JournalLineDraft(accountID: accountID, credit: amount, memo: memo)
    }

    /// La misma línea en el lado contrario (para reversiones y notas de crédito).
    public var swapped: JournalLineDraft {
        JournalLineDraft(accountID: accountID, debit: credit, credit: debit, memo: memo)
    }
}

/// Asiento aún no guardado. Es el formato común que producen las reglas de contabilización
/// y que valida `JournalValidator` antes de persistirlo.
public struct JournalEntryDraft: Hashable, Sendable {
    public var date: Date
    public var memo: String
    public var source: EntrySource
    public var lines: [JournalLineDraft]

    public init(date: Date, memo: String = "", source: EntrySource = .manual, lines: [JournalLineDraft]) {
        self.date = date
        self.memo = memo
        self.source = source
        self.lines = lines
    }

    public var totalDebits: Int64 { lines.reduce(0) { $0 + $1.debit } }
    public var totalCredits: Int64 { lines.reduce(0) { $0 + $1.credit } }
    public var difference: Int64 { totalDebits - totalCredits }
    public var isBalanced: Bool { difference == 0 }

    /// Asiento espejo que anula a este (§4.2): mismas cuentas, lados intercambiados.
    public func reversal(on date: Date, memo: String? = nil) -> JournalEntryDraft {
        JournalEntryDraft(
            date: date,
            memo: memo ?? "Reversión: \(self.memo)",
            source: .reversal,
            lines: lines.map(\.swapped)
        )
    }
}

/// Lo que el validador necesita saber de una cuenta.
public struct AccountInfo: Hashable, Sendable {
    public var id: UUID
    public var type: AccountType
    /// `false` si la cuenta está archivada o es una cuenta padre (solo las hojas admiten movimientos).
    public var isPostable: Bool

    public init(id: UUID, type: AccountType, isPostable: Bool = true) {
        self.id = id
        self.type = type
        self.isPostable = isPostable
    }
}

public enum JournalValidationError: Error, Hashable, Sendable {
    case tooFewLines(count: Int)
    case emptyLine(index: Int)
    case negativeAmount(index: Int)
    case bothSides(index: Int)
    case singleAccount
    case unbalanced(debits: Int64, credits: Int64)
    case unknownAccount(index: Int)
    case accountNotPostable(index: Int)
    case periodLocked(lockDate: Date)
}

/// Invariantes de la doble partida (§4.2). Ningún asiento llega a la base de datos sin pasar por aquí.
public struct JournalValidator: Sendable {
    /// Fecha de cierre: no se admiten asientos con fecha igual o anterior a este día.
    public var lockDate: Date?
    public var calendar: Calendar
    /// Si es `nil` no se comprueban las cuentas (útil para validar solo la estructura).
    public var accountLookup: (@Sendable (UUID) -> AccountInfo?)?

    public init(
        lockDate: Date? = nil,
        calendar: Calendar = .current,
        accountLookup: (@Sendable (UUID) -> AccountInfo?)? = nil
    ) {
        self.lockDate = lockDate
        self.calendar = calendar
        self.accountLookup = accountLookup
    }

    /// Todos los problemas del asiento, en orden, para mostrarlos en el editor.
    public func errors(for entry: JournalEntryDraft) -> [JournalValidationError] {
        var errors: [JournalValidationError] = []

        if entry.lines.count < 2 {
            errors.append(.tooFewLines(count: entry.lines.count))
        }

        for (index, line) in entry.lines.enumerated() {
            if line.debit < 0 || line.credit < 0 {
                errors.append(.negativeAmount(index: index))
            } else if line.debit > 0 && line.credit > 0 {
                errors.append(.bothSides(index: index))
            } else if line.debit == 0 && line.credit == 0 {
                errors.append(.emptyLine(index: index))
            }

            if let accountLookup {
                if let account = accountLookup(line.accountID) {
                    if !account.isPostable { errors.append(.accountNotPostable(index: index)) }
                } else {
                    errors.append(.unknownAccount(index: index))
                }
            }
        }

        if entry.lines.count >= 2 && Set(entry.lines.map(\.accountID)).count < 2 {
            errors.append(.singleAccount)
        }

        if !entry.isBalanced {
            errors.append(.unbalanced(debits: entry.totalDebits, credits: entry.totalCredits))
        }

        if let lockDate, calendar.startOfDay(for: entry.date) <= calendar.startOfDay(for: lockDate) {
            errors.append(.periodLocked(lockDate: lockDate))
        }

        return errors
    }

    /// Lanza el primer error encontrado.
    public func validate(_ entry: JournalEntryDraft) throws(JournalValidationError) {
        if let first = errors(for: entry).first { throw first }
    }

    public func isValid(_ entry: JournalEntryDraft) -> Bool {
        errors(for: entry).isEmpty
    }
}
