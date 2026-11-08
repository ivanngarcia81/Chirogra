import ChirograCore
import Foundation
import SwiftData

// MARK: - Sesión de conciliación (DISEÑO §4.6, docs/DATOS-V4.md §2.5)
//
// Se abre con la fecha y el saldo final del extracto; el saldo inicial es el final de la última conciliación terminada
// de la cuenta (o el que se dé, la primera vez). Se marcan las líneas del diario que salen en el extracto
// (`JournalLine.reconciliationID`); cuando saldo inicial + marcadas = saldo final del extracto (diferencia 0) se
// termina. Después, revertir o editar un asiento con líneas conciliadas falla con `BookkeepingError.reconciledLines`
// salvo con `allowingReconciledChanges()` (la UI avisa y pide confirmación). Los saldos van en el lado normal de la
// cuenta: en un banco, lo que hay; en una tarjeta, lo que se debe.

/// Estado de una conciliación.
public struct ReconciliationSummary: Sendable, Equatable {
    public var beginningBalance: Int64
    public var statementEndingBalance: Int64
    /// Marcadas que aumentan el saldo (depósitos; en una tarjeta, compras).
    public var clearedIncreases: Int64
    /// Marcadas que lo disminuyen (pagos y cargos; en una tarjeta, pagos y devoluciones), en positivo.
    public var clearedDecreases: Int64
    public var clearedCount: Int

    /// Saldo inicial + marcadas.
    public var clearedBalance: Int64 { beginningBalance + clearedIncreases - clearedDecreases }
    /// Saldo final del extracto − saldo marcado: tiene que llegar a 0 para terminar.
    public var difference: Int64 { statementEndingBalance - clearedBalance }
    public var isBalanced: Bool { difference == 0 }
}

extension Bookkeeper {

    /// Conciliaciones de una cuenta (o de todas), de la más reciente a la más antigua.
    public func reconciliations(for account: Account? = nil) throws -> [Reconciliation] {
        let accountID: UUID? = account?.id
        let all = account == nil
        return try fetch(Reconciliation.self, #Predicate { all || $0.accountID == accountID },
                         sortBy: [SortDescriptor(\.statementDate, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
    }

    /// La que está abierta para la cuenta, si hay.
    public func openReconciliation(for account: Account) throws -> Reconciliation? {
        try reconciliations(for: account).first { !$0.isCompleted }
    }

    public func lastCompletedReconciliation(for account: Account) throws -> Reconciliation? {
        try reconciliations(for: account).first(where: \.isCompleted)
    }

    /// Abre una conciliación. Solo una abierta por cuenta, con fecha posterior a la última terminada. Saldo inicial: el
    /// final de la última terminada o, si no hay, `beginningBalance` (0 por defecto: entonces el asiento de saldos
    /// iniciales es una línea más que marcar).
    @discardableResult
    public func startReconciliation(for account: Account, statementDate: Date, endingBalance: Int64,
                                    beginningBalance: Int64? = nil, calendar: Calendar = .current) throws -> Reconciliation {
        guard account.subtype.isMoneyAccount else {
            throw BookkeepingError.invalidState(String(localized: "Elige una cuenta de banco, caja o tarjeta para el pago."))
        }
        guard try openReconciliation(for: account) == nil else {
            throw BookkeepingError.invalidState(String(localized: "Ya hay una conciliación abierta para esta cuenta."))
        }
        let last = try lastCompletedReconciliation(for: account)
        if let last, calendar.startOfDay(for: statementDate) <= calendar.startOfDay(for: last.statementDate) {
            throw BookkeepingError.invalidState(String(localized: "La fecha del extracto debe ser posterior a la de la última conciliación."))
        }
        let reconciliation = Reconciliation(accountID: account.id, statementDate: calendar.startOfDay(for: statementDate),
                                            statementEndingBalance: endingBalance,
                                            beginningBalance: last?.statementEndingBalance ?? beginningBalance ?? 0)
        insert(reconciliation)
        audit("Reconciliation", reconciliation.id, "start", String(localized: "Conciliación abierta: \(account.maskedName)"))
        try saveOrRollback()
        return reconciliation
    }

    /// Cambia la fecha o el saldo final del extracto de una conciliación abierta.
    public func updateReconciliation(_ reconciliation: Reconciliation, statementDate: Date? = nil, endingBalance: Int64? = nil,
                                     calendar: Calendar = .current) throws {
        try ensureOpen(reconciliation)
        if let statementDate { reconciliation.statementDate = calendar.startOfDay(for: statementDate) }
        if let endingBalance { reconciliation.statementEndingBalance = endingBalance }
        try saveOrRollback()
    }

    /// Líneas que se pueden marcar: las de la cuenta, de asientos contabilizados con fecha hasta la del extracto, sin
    /// conciliar en otra; las ya marcadas en esta van incluidas. Por fecha.
    public func reconciliationLines(_ reconciliation: Reconciliation, calendar: Calendar = .current) throws -> [JournalLine] {
        guard let account = try account(id: reconciliation.accountID) else { return [] }
        let limit = Self.endOfDay(reconciliation.statementDate, calendar)
        return (account.lines ?? []).filter { line in
            guard let entry = line.entry, entry.status == .posted else { return false }
            return line.reconciliationID == reconciliation.id || (line.reconciliationID == nil && entry.date <= limit)
        }
        .sorted { ($0.entry?.date ?? .distantPast, $0.entry?.number ?? 0) < ($1.entry?.date ?? .distantPast, $1.entry?.number ?? 0) }
    }

    /// Las que conviene marcar de entrada: las emparejadas con un movimiento del banco de hasta la fecha del extracto.
    public func suggestedClearedLines(_ reconciliation: Reconciliation, calendar: Calendar = .current) throws -> [JournalLine] {
        guard let account = try account(id: reconciliation.accountID) else { return [] }
        let limit = Self.endOfDay(reconciliation.statementDate, calendar)
        let accountID: UUID? = account.id
        let fromBank = Set(try fetch(BankTransaction.self, #Predicate { $0.accountID == accountID && $0.matchedLineID != nil })
            .filter { $0.date <= limit }.compactMap(\.matchedLineID))
        return try reconciliationLines(reconciliation, calendar: calendar).filter { $0.reconciliationID == nil && fromBank.contains($0.id) }
    }

    /// Marca (o desmarca) líneas en una conciliación abierta.
    public func setCleared(_ lines: [JournalLine], _ cleared: Bool, in reconciliation: Reconciliation) throws {
        try ensureOpen(reconciliation)
        let now = Date()
        for line in lines {
            guard line.account?.id == reconciliation.accountID else {
                throw BookkeepingError.invalidState(String(localized: "La línea no es de la cuenta que se concilia."))
            }
            if cleared {
                guard line.reconciliationID == nil || line.reconciliationID == reconciliation.id else {
                    throw BookkeepingError.invalidState(String(localized: "La línea ya está conciliada en otra conciliación."))
                }
                line.reconciliationID = reconciliation.id
                line.clearedAt = now
            } else if line.reconciliationID == reconciliation.id {
                line.reconciliationID = nil
                line.clearedAt = nil
            }
        }
        try saveOrRollback()
    }

    /// Saldo inicial, marcadas y diferencia.
    public func summary(of reconciliation: Reconciliation) throws -> ReconciliationSummary {
        guard let account = try account(id: reconciliation.accountID) else { throw BookkeepingError.unknownAccount }
        let cleared = (account.lines ?? []).filter { $0.reconciliationID == reconciliation.id }
        var summary = ReconciliationSummary(beginningBalance: reconciliation.beginningBalance,
                                            statementEndingBalance: reconciliation.statementEndingBalance,
                                            clearedIncreases: 0, clearedDecreases: 0, clearedCount: cleared.count)
        for line in cleared {
            let effect = account.type.naturalBalance(debit: line.debit, credit: line.credit)
            if effect >= 0 { summary.clearedIncreases += effect } else { summary.clearedDecreases -= effect }
        }
        return summary
    }

    /// Termina la conciliación: solo si la diferencia es 0.
    public func completeReconciliation(_ reconciliation: Reconciliation) throws {
        try ensureOpen(reconciliation)
        let summary = try summary(of: reconciliation)
        guard summary.isBalanced else {
            throw BookkeepingError.invalidState(String(localized: "La conciliación no cuadra: faltan \(Money(minorUnits: summary.difference).formatted())."))
        }
        reconciliation.status = .completed
        reconciliation.closedAt = Date()
        audit("Reconciliation", reconciliation.id, "complete", String(localized: "Conciliación terminada al \(reconciliation.statementDate.formatted(date: .abbreviated, time: .omitted))"))
        try saveOrRollback()
    }

    /// Reabre la última conciliación terminada de su cuenta (para corregirla). Sus líneas siguen marcadas.
    public func reopenReconciliation(_ reconciliation: Reconciliation) throws {
        guard reconciliation.isCompleted else { return }
        guard let account = try account(id: reconciliation.accountID),
              try lastCompletedReconciliation(for: account)?.id == reconciliation.id, try openReconciliation(for: account) == nil else {
            throw BookkeepingError.invalidState(String(localized: "Solo se reabre la última conciliación de la cuenta, y si no hay otra abierta."))
        }
        reconciliation.status = .inProgress
        reconciliation.closedAt = nil
        audit("Reconciliation", reconciliation.id, "reopen", String(localized: "Conciliación reabierta"))
        try saveOrRollback()
    }

    /// Descarta una conciliación abierta: desmarca sus líneas y la borra.
    public func cancelReconciliation(_ reconciliation: Reconciliation) throws {
        try ensureOpen(reconciliation)
        if let account = try account(id: reconciliation.accountID) {
            for line in account.lines ?? [] where line.reconciliationID == reconciliation.id {
                line.reconciliationID = nil
                line.clearedAt = nil
            }
        }
        context.delete(reconciliation)
        try saveOrRollback()
    }

    /// El asiento tiene alguna línea de una conciliación **terminada** (cambiarlo descuadra esa conciliación).
    public func hasReconciledLines(_ entry: JournalEntry) throws -> Bool {
        let ids = Set((entry.lines ?? []).compactMap(\.reconciliationID))
        guard !ids.isEmpty else { return false }
        let completed = ReconciliationStatus.completed.rawValue
        return try fetch(Reconciliation.self, #Predicate { $0.statusRaw == completed }).contains { ids.contains($0.id) }
    }

    /// La línea está en una conciliación terminada.
    public func isReconciled(_ line: JournalLine) throws -> Bool {
        guard let id = line.reconciliationID else { return false }
        return try fetch(Reconciliation.self, #Predicate { $0.id == id }, limit: 1).first?.isCompleted ?? false
    }

    private func ensureOpen(_ reconciliation: Reconciliation) throws {
        guard !reconciliation.isCompleted else {
            throw BookkeepingError.invalidState(String(localized: "La conciliación ya está terminada."))
        }
    }
}
