import ChirograCore
import Foundation
import SwiftData

// MARK: - Banca: importar, bandeja «Por revisar», reglas y coincidencias (DISEÑO §4.6, docs/DATOS-V4.md §2)

/// Resultado de una importación.
public struct BankImportResult {
    /// Todos los movimientos de este archivo comparten este id (`BankTransaction.importBatchID`).
    public var batchID: UUID
    /// Movimientos nuevos (los ya importados antes no se repiten).
    public var imported: [BankTransaction] = []
    /// Cuántos ya estaban (mismo `externalID` en la misma cuenta).
    public var duplicates: Int = 0
    /// Registrados solos por una regla con aplicación automática.
    public var autoApplied: [BankTransaction] = []
    /// Reglas automáticas que no pudieron registrar (p. ej. periodo cerrado): el movimiento queda por revisar con la
    /// categoría propuesta.
    public var failures: [(transaction: BankTransaction, error: Error)] = []
}

/// Resultado de aplicar las reglas a la bandeja.
public struct BankRuleRun {
    /// Movimientos a los que una regla les propuso categoría.
    public var categorized: [BankTransaction] = []
    /// Los que además se registraron (regla automática).
    public var applied: [BankTransaction] = []
    public var failures: [(transaction: BankTransaction, error: Error)] = []
}

/// Lo que se creó al registrar un movimiento desde la bandeja.
/// Una parte de un movimiento dividido (`Bookkeeper.categorize(_:splitInto:)`): cuenta, importe (positivo) y nota.
public struct BankSplitPart: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var accountID: UUID
    public var amount: Int64
    public var memo: String

    public init(accountID: UUID, amount: Int64, memo: String = "") {
        self.accountID = accountID
        self.amount = amount
        self.memo = memo
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.accountID, lhs.amount, lhs.memo) == (rhs.accountID, rhs.amount, rhs.memo)
    }
}

public enum BankCategorization {
    /// Gasto contabilizado (salida a una cuenta de gasto, costo…).
    case expense(Expense)
    /// Depósito (entrada a ingreso, aportación del dueño, devolución…) como asiento `EntrySource.bankDeposit`.
    case deposit(JournalEntry)
    /// Transferencia entre cuentas de dinero, asiento `EntrySource.transfer`.
    case transfer(JournalEntry)
    /// Cobro de una factura.
    case payment(PaymentReceived)
    /// Pago de una factura de proveedor.
    case billPayment(BillPayment)

    public var entryID: UUID? {
        switch self {
        case .expense(let expense): expense.journalEntryID
        case .deposit(let entry), .transfer(let entry): entry.id
        case .payment(let payment): payment.journalEntryID
        case .billPayment(let payment): payment.journalEntryID
        }
    }
}

/// Línea del diario que podría ser el mismo movimiento que uno del banco.
public struct BankMatchCandidate: Identifiable {
    public var line: JournalLine
    public var entry: JournalEntry
    /// Días entre el movimiento del banco y el asiento (0 = el mismo día).
    public var daysApart: Int
    public var id: UUID { line.id }
}

/// Datos de una regla del banco (alta y edición).
public struct BankRuleInput {
    public var name: String
    public var matchText: String
    public var amountSign: BankAmountSign
    public var bankAccountID: UUID?
    public var targetAccountID: UUID?
    public var vendorID: UUID?
    public var payee: String
    public var autoApply: Bool
    public var priority: Int
    public var isActive: Bool

    public init(name: String = "", matchText: String, amountSign: BankAmountSign = .any, bankAccountID: UUID? = nil,
                targetAccountID: UUID?, vendorID: UUID? = nil, payee: String = "", autoApply: Bool = false, priority: Int = 0,
                isActive: Bool = true) {
        self.name = name
        self.matchText = matchText
        self.amountSign = amountSign
        self.bankAccountID = bankAccountID
        self.targetAccountID = targetAccountID
        self.vendorID = vendorID
        self.payee = payee
        self.autoApply = autoApply
        self.priority = priority
        self.isActive = isActive
    }

    public init(_ rule: BankRule) {
        self.init(name: rule.name, matchText: rule.matchText, amountSign: rule.amountSign, bankAccountID: rule.bankAccountID,
                  targetAccountID: rule.targetAccountID, vendorID: rule.vendorID, payee: rule.payee, autoApply: rule.autoApply,
                  priority: rule.priority, isActive: rule.isActive)
    }
}

extension BankImportProfile {
    /// El perfil como `CSVImportSettings` (`nil` si las columnas guardadas no se leen).
    public var settings: CSVImportSettings? {
        guard let data = columnsJSON.data(using: .utf8),
              let mapping = try? JSONDecoder().decode(CSVColumnMapping.self, from: data) else { return nil }
        return CSVImportSettings(mapping: mapping, dateFormat: dateFormat, amountSign: CSVAmountSign(rawValue: amountSignRaw) ?? .signed,
                                 delimiter: delimiter.first ?? ",", hasHeaderRow: hasHeaderRow)
    }
}

extension Bookkeeper {

    // MARK: Movimientos

    /// Movimientos del banco de la empresa, del más reciente al más antiguo; de una cuenta y un estado, si se piden.
    public func bankTransactions(account: Account? = nil, status: BankTransactionStatus? = nil) throws -> [BankTransaction] {
        let accountID: UUID? = account?.id
        let filterAccount = account != nil
        let statusRaw = status?.rawValue ?? ""
        let filterStatus = status != nil
        return try fetch(BankTransaction.self, #Predicate {
            (!filterAccount || $0.accountID == accountID) && (!filterStatus || $0.statusRaw == statusRaw)
        }, sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.importedAt)])
    }

    /// Bandeja «Por revisar».
    public func bankInbox(account: Account? = nil) throws -> [BankTransaction] {
        try bankTransactions(account: account, status: .toReview)
    }

    public func bankTransaction(id: UUID?) throws -> BankTransaction? {
        guard let id else { return nil }
        return try fetch(BankTransaction.self, #Predicate { $0.id == id }, limit: 1).first
    }

    // MARK: Importar

    /// Importa los movimientos de una fuente (CSV, OFX/QFX y, en el futuro, Plaid) a la cuenta de banco o tarjeta.
    @discardableResult
    public func importTransactions(from source: some BankTransactionSource, into account: Account,
                                   applyRules: Bool = true) async throws -> BankImportResult {
        let lines = try await source.statementLines()
        return try importStatementLines(lines, source: source.kind, into: account, applyRules: applyRules)
    }

    /// Guarda como «por revisar» los movimientos que aún no estaban (mismo `externalID` en la misma cuenta = el mismo,
    /// también si se ignoró) y, si `applyRules`, les aplica las reglas (las automáticas los registran).
    @discardableResult
    public func importStatementLines(_ lines: [BankStatementLine], source: BankSourceKind, into account: Account,
                                     applyRules: Bool = true) throws -> BankImportResult {
        guard account.subtype.isMoneyAccount, !account.isArchived else {
            throw BookkeepingError.invalidState(String(localized: "Elige una cuenta de banco, caja o tarjeta para el pago."))
        }
        let accountID: UUID? = account.id
        var seen = Set(try fetch(BankTransaction.self, #Predicate { $0.accountID == accountID }).map(\.externalID))
        var result = BankImportResult(batchID: UUID())
        let now = Date()
        for line in BankStatementLine.assigningStableIDs(lines) {
            guard !seen.contains(line.externalID) else { result.duplicates += 1; continue }
            seen.insert(line.externalID)
            let transaction = BankTransaction(accountID: account.id, date: line.date, amount: line.amount, details: line.details,
                                              externalID: line.externalID, source: source)
            transaction.payee = line.payee
            transaction.memo = line.memo
            transaction.checkNumber = line.checkNumber
            transaction.importBatchID = result.batchID
            transaction.importedAt = now
            insert(transaction)
            result.imported.append(transaction)
        }
        audit("BankTransaction", result.batchID, "import",
              String(localized: "Movimientos importados en \(account.maskedName): \(result.imported.count) nuevos, \(result.duplicates) repetidos"))
        try saveOrRollback()
        if applyRules, !result.imported.isEmpty {
            let run = try applyBankRules(to: result.imported)
            result.autoApplied = run.applied
            result.failures = run.failures
        }
        return result
    }

    // MARK: Perfiles de CSV

    public func importProfiles(for account: Account? = nil) throws -> [BankImportProfile] {
        let accountID: UUID? = account?.id
        let all = account == nil
        return try fetch(BankImportProfile.self, #Predicate { all || $0.accountID == accountID },
                         sortBy: [SortDescriptor(\.createdAt)])
    }

    /// Guarda (o actualiza) cómo se lee el CSV de una cuenta, para la próxima importación.
    @discardableResult
    public func saveImportProfile(_ settings: CSVImportSettings, name: String = "", for account: Account,
                                  into existing: BankImportProfile? = nil) throws -> BankImportProfile {
        let profile = try existing ?? importProfiles(for: account).first ?? {
            let created = BankImportProfile(accountID: account.id, name: name)
            insert(created)
            return created
        }()
        if !name.isEmpty { profile.name = name }
        if profile.name.isEmpty { profile.name = account.maskedName }
        profile.accountID = account.id
        profile.columnsJSON = String(decoding: try JSONEncoder().encode(settings.mapping), as: UTF8.self)
        profile.dateFormat = settings.dateFormat
        profile.amountSignRaw = settings.amountSign.rawValue
        profile.delimiter = String(settings.delimiter)
        profile.hasHeaderRow = settings.hasHeaderRow
        profile.lastUsedAt = Date()
        try saveOrRollback()
        return profile
    }

    // MARK: Reglas

    /// Reglas en el orden en que se prueban: prioridad (mayor primero) y, a igualdad, la más antigua.
    public func bankRules(includeInactive: Bool = true) throws -> [BankRule] {
        try fetch(BankRule.self).filter { includeInactive || $0.isActive }
            .sorted { ($1.priority, $0.createdAt, $0.id.uuidString) < ($0.priority, $1.createdAt, $1.id.uuidString) }
    }

    @discardableResult
    public func saveBankRule(_ input: BankRuleInput, into existing: BankRule? = nil) throws -> BankRule {
        let text = input.matchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La regla necesita un texto que buscar.")) }
        guard let target = try account(id: input.targetAccountID), target.isPostable else { throw BookkeepingError.unknownAccount }
        if input.bankAccountID != nil, try account(id: input.bankAccountID) == nil { throw BookkeepingError.unknownAccount }
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = existing ?? BankRule(name: name, matchText: text, targetAccountID: target.id)
        if existing == nil { insert(rule) }
        rule.name = name.isEmpty ? text : name
        rule.matchText = text
        rule.amountSign = input.amountSign
        rule.bankAccountID = input.bankAccountID
        rule.targetAccountID = target.id
        rule.vendorID = input.vendorID
        rule.payee = input.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.autoApply = input.autoApply
        rule.priority = input.priority
        rule.isActive = input.isActive
        audit("BankRule", rule.id, existing == nil ? "create" : "update", String(localized: "Regla del banco: \(rule.name)"))
        try saveOrRollback()
        return rule
    }

    public func deleteBankRule(_ rule: BankRule) throws {
        audit("BankRule", rule.id, "delete", String(localized: "Regla del banco borrada: \(rule.name)"))
        context.delete(rule)
        try saveOrRollback()
    }

    /// Primera regla activa que encaja con el movimiento (texto en la descripción o el beneficiario, signo y cuenta).
    public func rule(matching transaction: BankTransaction, among rules: [BankRule]? = nil) throws -> BankRule? {
        let haystack = BankStatementLine.normalized(transaction.details + " " + transaction.payee)
        return try (rules ?? bankRules(includeInactive: false)).first { rule in
            rule.isActive && rule.amountSign.matches(transaction.amount)
                && (rule.bankAccountID == nil || rule.bankAccountID == transaction.accountID)
                && haystack.contains(BankStatementLine.normalized(rule.matchText))
        }
    }

    /// Aplica las reglas a los movimientos por revisar (todos los de la bandeja, o los dados): la primera que encaja
    /// propone cuenta, proveedor y beneficiario; si es automática, además lo registra (`categorize`). Los que ya tienen
    /// categoría elegida a mano no se tocan.
    @discardableResult
    public func applyBankRules(to transactions: [BankTransaction]? = nil) throws -> BankRuleRun {
        let rules = try bankRules(includeInactive: false)
        var run = BankRuleRun()
        guard !rules.isEmpty else { return run }
        var automatic: [(BankTransaction, BankRule)] = []
        for transaction in try transactions ?? bankInbox() where transaction.status == .toReview {
            guard transaction.categoryAccountID == nil || transaction.ruleID != nil,
                  let rule = try rule(matching: transaction, among: rules) else { continue }
            transaction.categoryAccountID = rule.targetAccountID
            transaction.vendorID = rule.vendorID ?? transaction.vendorID
            transaction.ruleID = rule.id
            if !rule.payee.isEmpty { transaction.payee = rule.payee }
            run.categorized.append(transaction)
            if rule.autoApply { automatic.append((transaction, rule)) }
        }
        try saveOrRollback()
        for (transaction, _) in automatic {
            do {
                try categorize(transaction)
                run.applied.append(transaction)
            } catch {
                context.rollback()
                run.failures.append((transaction, error))
            }
        }
        return run
    }

    // MARK: Coincidencias

    /// Líneas del diario de la cuenta del movimiento, sin conciliar ni emparejar, con el mismo importe (debe − haber) y
    /// a no más de `toleranceDays` días; las más cercanas primero. Quedan fuera los asientos revertidos y las reversiones.
    public func matchCandidates(for transaction: BankTransaction, toleranceDays: Int = 5,
                                calendar: Calendar = .current) throws -> [BankMatchCandidate] {
        guard let account = try account(id: transaction.accountID) else { return [] }
        let taken = try matchedLineIDs(account: account, excluding: transaction)
        let day = calendar.startOfDay(for: transaction.date)
        return (account.lines ?? []).compactMap { line -> BankMatchCandidate? in
            guard let entry = line.entry, entry.status == .posted, !entry.isReversed, entry.reversesEntryID == nil,
                  line.reconciliationID == nil, !taken.contains(line.id), line.debit - line.credit == transaction.amount else { return nil }
            let days = abs(calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: entry.date)).day ?? .max)
            return days <= toleranceDays ? BankMatchCandidate(line: line, entry: entry, daysApart: days) : nil
        }
        .sorted { ($0.daysApart, $0.entry.number) < ($1.daysApart, $1.entry.number) }
    }

    /// Líneas ya emparejadas con algún movimiento de la cuenta.
    func matchedLineIDs(account: Account, excluding transaction: BankTransaction? = nil) throws -> Set<UUID> {
        let accountID: UUID? = account.id
        return Set(try fetch(BankTransaction.self, #Predicate { $0.accountID == accountID && $0.matchedLineID != nil })
            .filter { $0.id != transaction?.id }.compactMap(\.matchedLineID))
    }

    /// Empareja el movimiento con una línea del diario que ya existe (p. ej. el cobro registrado a mano).
    public func match(_ transaction: BankTransaction, to line: JournalLine) throws {
        try ensurePending(transaction)
        guard let account = line.account, account.id == transaction.accountID, line.debit - line.credit == transaction.amount,
              let entry = line.entry, entry.status == .posted else {
            throw BookkeepingError.invalidState(String(localized: "La línea no es de la misma cuenta o no tiene el mismo importe."))
        }
        guard try !matchedLineIDs(account: account, excluding: transaction).contains(line.id) else {
            throw BookkeepingError.invalidState(String(localized: "Esa línea ya está emparejada con otro movimiento."))
        }
        link(transaction, to: entry, documentID: nil, status: .matched)
        audit("BankTransaction", transaction.id, "match", String(localized: "Movimiento emparejado con el asiento \(entry.number)"))
        try saveOrRollback()
    }

    /// Deja de lado un movimiento (duplicado, ya registrado de otra forma, personal…) con su motivo (1.2), que queda en
    /// el movimiento (`ignoreReason`) y en la bitácora.
    public func ignore(_ transaction: BankTransaction, reason: String = "") throws {
        try ensurePending(transaction)
        transaction.status = .ignored
        transaction.ignoreReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.reviewedAt = Date()
        var changes = Self.bankDetails(transaction)
        changes.value(String(localized: "Motivo"), transaction.ignoreReason)
        audit("BankTransaction", transaction.id, "ignore", String(localized: "Movimiento excluido: \(transaction.details)"), changes: changes)
        try saveOrRollback()
    }

    /// Fecha e importe de un movimiento, para la bitácora.
    static func bankDetails(_ transaction: BankTransaction) -> AuditChanges {
        var changes = AuditChanges()
        changes.value(String(localized: "Fecha"), AuditChanges.day(transaction.date))
        changes.value(String(localized: "Importe"), money: transaction.amount)
        return changes
    }

    /// Lo devuelve a la bandeja: quita el emparejamiento o el «ignorado». Si se creó un documento desde él, el documento
    /// **se queda** (si sobra, anúlalo aparte); su línea vuelve a salir como candidata.
    public func returnToInbox(_ transaction: BankTransaction) throws {
        var changes = Self.bankDetails(transaction)
        changes.value(String(localized: "Estado anterior"), transaction.status.auditTitle)
        changes.value(String(localized: "Motivo de exclusión"), transaction.ignoreReason)
        audit("BankTransaction", transaction.id, "returnToInbox", String(localized: "Movimiento devuelto a «Por revisar»: \(transaction.details)"), changes: changes)
        transaction.ignoreReason = ""
        transaction.status = .toReview
        transaction.matchedEntryID = nil
        transaction.matchedLineID = nil
        transaction.createdDocumentID = nil
        transaction.reviewedAt = nil
        try saveOrRollback()
    }

    // MARK: Registrar desde el movimiento

    /// Registra el movimiento según la cuenta elegida (o la que propuso una regla):
    /// - una cuenta de dinero (banco, caja, tarjeta) → **transferencia** entre las dos;
    /// - una salida → **gasto** pagado con la cuenta del movimiento (con proveedor y cliente facturable, si se dan);
    /// - una entrada → **depósito** a esa cuenta (ingreso sin factura, aportación del dueño, devolución de un gasto…).
    /// El movimiento queda «categorizado» y enlazado con el asiento. Todo en un solo guardado.
    @discardableResult
    public func categorize(_ transaction: BankTransaction, as category: Account? = nil, vendor: Vendor? = nil,
                           customer: Customer? = nil, payee: String? = nil, memo: String = "") throws -> BankCategorization {
        try ensurePending(transaction)
        guard let category = try category ?? account(id: transaction.categoryAccountID) else {
            throw BookkeepingError.invalidState(String(localized: "Elige una cuenta para registrar el movimiento."))
        }
        return try register(transaction, parts: [(category, abs(transaction.amount), "")], vendor: vendor, customer: customer,
                            payee: payee, memo: memo)
    }

    /// Registra el movimiento **dividido** en varias cuentas (1.2): una salida → un gasto con una línea por parte; una
    /// entrada → un depósito con una línea al haber por parte. Las partes suman el importe del movimiento y ninguna va a
    /// una cuenta de dinero (una transferencia se registra sola, sin dividir). El movimiento queda con la cuenta de la
    /// parte mayor en `categoryAccountID`; las partes son las líneas del documento (`splitParts(of:)`).
    @discardableResult
    public func categorize(_ transaction: BankTransaction, splitInto parts: [BankSplitPart], vendor: Vendor? = nil,
                           customer: Customer? = nil, payee: String? = nil, memo: String = "") throws -> BankCategorization {
        try ensurePending(transaction)
        guard parts.count >= 2 else {
            throw BookkeepingError.invalidState(String(localized: "Para dividir el movimiento hacen falta al menos dos partes."))
        }
        guard parts.allSatisfy({ $0.amount > 0 }) else { throw BookkeepingError.invalidDocument(.nonPositiveAmount) }
        let total = parts.reduce(Int64(0)) { $0 + $1.amount }
        guard total == abs(transaction.amount) else {
            throw BookkeepingError.invalidState(String(localized: "Las partes suman \(Money(minorUnits: total).formatted()) y el movimiento es de \(Money(minorUnits: abs(transaction.amount)).formatted())."))
        }
        let accounts = try parts.map { part -> (Account, Int64, String) in
            guard let account = try account(id: part.accountID) else { throw BookkeepingError.unknownAccount }
            guard !account.subtype.isMoneyAccount else {
                throw BookkeepingError.invalidState(String(localized: "Una transferencia entre cuentas no se puede dividir: regístrala sola."))
            }
            return (account, part.amount, part.memo.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try register(transaction, parts: accounts, vendor: vendor, customer: customer, payee: payee, memo: memo)
    }

    /// Las partes de un movimiento registrado dividido (las líneas del gasto o del depósito que creó); vacío si no se
    /// dividió.
    public func splitParts(of transaction: BankTransaction) throws -> [BankSplitPart] {
        guard transaction.status == .categorized else { return [] }
        let parts: [BankSplitPart]
        if let expense = try fetch(Expense.self, Self.expensePredicate(transaction.createdDocumentID), limit: 1).first {
            parts = expense.sortedLines.compactMap { line in
                line.accountID.map { BankSplitPart(accountID: $0, amount: line.amount, memo: line.details) }
            }
        } else if let entry = try entry(id: transaction.matchedEntryID), entry.source == .bankDeposit {
            parts = entry.sortedLines.filter { $0.account?.id != transaction.accountID }.compactMap { line in
                line.account.map { BankSplitPart(accountID: $0.id, amount: line.credit - line.debit, memo: line.memo) }
            }
        } else {
            parts = []
        }
        return parts.count >= 2 ? parts : []
    }

    private static func expensePredicate(_ id: UUID?) -> Predicate<Expense> {
        let target = id ?? UUID()
        return #Predicate<Expense> { $0.id == target }
    }

    /// Núcleo de `categorize`: una parte a una cuenta de dinero → transferencia; si no, gasto (salida) o depósito
    /// (entrada) con una línea por parte. Todo en un solo guardado.
    private func register(_ transaction: BankTransaction, parts: [(account: Account, amount: Int64, memo: String)],
                          vendor: Vendor?, customer: Customer?, payee: String?, memo: String) throws -> BankCategorization {
        guard let bank = try account(id: transaction.accountID) else { throw BookkeepingError.unknownAccount }
        guard parts.allSatisfy({ $0.account.id != bank.id }) else { throw BookkeepingError.invalidDocument(.sameAccount) }
        guard transaction.amount != 0 else { throw BookkeepingError.invalidDocument(.nonPositiveAmount) }
        let vendor = try vendor ?? self.vendor(id: transaction.vendorID)
        let name = payee ?? (transaction.payee.isEmpty ? (vendor?.name ?? transaction.details) : transaction.payee)
        let main = parts.max { $0.amount < $1.amount }!.account
        do {
            let result: BankCategorization
            if parts.count == 1, main.subtype.isMoneyAccount {
                let amount = abs(transaction.amount)
                let lines: [JournalLineDraft] = transaction.amount > 0
                    ? [.debit(bank.id, amount), .credit(main.id, amount)]
                    : [.debit(main.id, amount), .credit(bank.id, amount)]
                let entry = try post(JournalEntryDraft(date: transaction.date, memo: memo.isEmpty ? String(localized: "Transferencia · \(transaction.details)") : memo,
                                                       source: .transfer, lines: lines), sourceDocumentID: transaction.id, save: false)
                result = .transfer(entry)
            } else if transaction.amount < 0 {
                let input = ExpenseInput(date: transaction.date, payee: name, vendor: vendor, customer: customer, paymentAccountID: bank.id,
                                         method: bank.subtype == .creditCard ? .card : .bankTransfer, reference: transaction.checkNumber,
                                         memo: memo, lines: parts.map { .init(details: $0.memo.isEmpty ? transaction.details : $0.memo, amount: $0.amount, accountID: $0.account.id) })
                let expense = Expense(date: input.date, payee: input.payee, paymentAccountID: bank.id, vendor: vendor)
                insert(expense)
                apply(input, to: expense)
                try record(expense, save: false)
                result = .expense(expense)
            } else {
                let lines: [JournalLineDraft] = [.debit(bank.id, transaction.amount)] + parts.map { .credit($0.account.id, $0.amount, memo: $0.memo) }
                let entry = try post(JournalEntryDraft(date: transaction.date, memo: memo.isEmpty ? String(localized: "Depósito · \(name)") : memo,
                                                       source: .bankDeposit, lines: lines),
                                     sourceDocumentID: transaction.id, save: false)
                entry.lines?.forEach { $0.customerID = customer?.id; $0.vendorID = vendor?.id }
                result = .deposit(entry)
            }
            transaction.categoryAccountID = main.id
            transaction.vendorID = vendor?.id
            transaction.customerID = customer?.id
            var changes = Self.bankDetails(transaction)
            if parts.count > 1 {
                for part in parts {
                    changes.value(part.account.displayName, AuditFormat.money(part.amount) + (part.memo.isEmpty ? "" : " · \(part.memo)"))
                }
            } else {
                changes.value(String(localized: "Cuenta"), main.displayName)
            }
            try finish(transaction, with: result, changes: changes,
                       summary: parts.count > 1 ? String(localized: "Movimiento dividido en \(parts.count) cuentas: \(transaction.details)") : nil)
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Registra la entrada como **cobro** de una factura pendiente (importe del movimiento, que no puede superar el saldo).
    @discardableResult
    public func recordPayment(from transaction: BankTransaction, for invoice: Invoice) throws -> PaymentReceived {
        try ensurePending(transaction)
        guard transaction.amount > 0, let bank = try account(id: transaction.accountID) else {
            throw BookkeepingError.invalidState(String(localized: "Solo una entrada de dinero puede ser un cobro."))
        }
        do {
            let payment = try recordPayment(for: invoice, amount: transaction.amount, date: transaction.date, depositAccount: bank,
                                            method: .bankTransfer, save: false)
            payment.reference = transaction.checkNumber
            transaction.customerID = invoice.customer?.id
            try finish(transaction, with: .payment(payment))
            return payment
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Registra la salida como **pago** de una factura de proveedor (importe del movimiento, sin superar el saldo).
    @discardableResult
    public func payBill(from transaction: BankTransaction, bill: Bill) throws -> BillPayment {
        try ensurePending(transaction)
        guard transaction.amount < 0, let bank = try account(id: transaction.accountID) else {
            throw BookkeepingError.invalidState(String(localized: "Solo una salida de dinero puede ser un pago."))
        }
        do {
            let payment = try pay(bill, amount: -transaction.amount, date: transaction.date, from: bank,
                                  method: bank.subtype == .creditCard ? .card : .bankTransfer, reference: transaction.checkNumber, save: false)
            transaction.vendorID = bill.vendor?.id
            try finish(transaction, with: .billPayment(payment))
            return payment
        } catch {
            context.rollback()
            throw error
        }
    }

    private func finish(_ transaction: BankTransaction, with result: BankCategorization, changes: AuditChanges? = nil,
                        summary: String? = nil) throws {
        guard let entry = try entry(id: result.entryID) else { throw BookkeepingError.invalidState(String(localized: "No se pudo registrar el movimiento.")) }
        let documentID: UUID? = switch result {
        case .expense(let expense): expense.id
        case .payment(let payment): payment.id
        case .billPayment(let payment): payment.id
        case .deposit, .transfer: entry.id
        }
        link(transaction, to: entry, documentID: documentID, status: .categorized)
        audit("BankTransaction", transaction.id, "categorize", summary ?? String(localized: "Movimiento registrado: \(transaction.details)"),
              changes: changes ?? Self.bankDetails(transaction))
        try commit()
    }

    private func link(_ transaction: BankTransaction, to entry: JournalEntry, documentID: UUID?, status: BankTransactionStatus) {
        let lines = (entry.lines ?? []).filter { $0.account?.id == transaction.accountID }
        transaction.matchedEntryID = entry.id
        transaction.matchedLineID = (lines.first { $0.debit - $0.credit == transaction.amount } ?? lines.first)?.id
        transaction.createdDocumentID = documentID
        transaction.status = status
        transaction.reviewedAt = Date()
    }

    private func ensurePending(_ transaction: BankTransaction) throws {
        guard transaction.status == .toReview else {
            throw BookkeepingError.invalidState(String(localized: "Este movimiento ya está revisado."))
        }
    }

    func vendor(id: UUID?) throws -> Vendor? {
        guard let id else { return nil }
        return try fetch(Vendor.self, #Predicate { $0.id == id }, limit: 1).first
    }
}
