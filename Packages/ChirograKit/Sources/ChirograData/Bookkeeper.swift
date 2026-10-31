import ChirograCore
import Foundation
import SwiftData

public enum BookkeepingError: Error, Equatable, LocalizedError {
    case noCompany
    case companyAlreadyExists
    case missingSystemAccount(AccountSubtype)
    case unknownAccount
    case invalidEntry(JournalValidationError)
    case invalidDocument(PostingError)
    case invalidState(String)
    case overpayment(balanceDue: Int64)

    public var errorDescription: String? {
        switch self {
        case .noCompany: "Todavía no hay una empresa configurada."
        case .companyAlreadyExists: "La empresa ya está configurada."
        case .missingSystemAccount(let subtype): "Falta la cuenta de sistema «\(subtype.rawValue)»."
        case .unknownAccount: "La cuenta indicada no existe."
        case .invalidEntry(let error): error.localizedMessage
        case .invalidDocument(let error): error.localizedMessage
        case .invalidState(let message): message
        case .overpayment(let balance): "El importe supera el saldo pendiente (\(Money(minorUnits: balance).formatted()))."
        }
    }
}

extension JournalValidationError {
    public var localizedMessage: String {
        switch self {
        case .tooFewLines: "Un asiento necesita al menos dos líneas."
        case .emptyLine(let index): "La línea \(index + 1) no tiene importe."
        case .negativeAmount(let index): "La línea \(index + 1) tiene un importe negativo."
        case .bothSides(let index): "La línea \(index + 1) tiene importe en el debe y en el haber."
        case .singleAccount: "El asiento necesita al menos dos cuentas distintas."
        case .unbalanced(let debits, let credits):
            "El debe (\(Money(minorUnits: debits).formatted())) y el haber (\(Money(minorUnits: credits).formatted())) no cuadran."
        case .unknownAccount(let index): "La cuenta de la línea \(index + 1) no existe."
        case .accountNotPostable(let index): "La cuenta de la línea \(index + 1) está archivada o es una cuenta padre."
        case .periodLocked(let lockDate): "El periodo está cerrado hasta el \(lockDate.formatted(date: .abbreviated, time: .omitted))."
        }
    }
}

extension PostingError {
    public var localizedMessage: String {
        switch self {
        case .noLines: "El documento no tiene líneas."
        case .nonPositiveAmount: "Todos los importes deben ser mayores que cero."
        case .sameAccount: "La cuenta de origen y la de destino no pueden ser la misma."
        }
    }
}

/// Punto único de escritura contable: convierte documentos en asientos con `ChirograCore`,
/// los valida y los guarda en una sola operación (DISEÑO §6.3). Las vistas no escriben asientos por su cuenta.
@MainActor
public struct Bookkeeper {
    public let context: ModelContext
    public var actor: String

    public init(context: ModelContext, actor: String = "") {
        self.context = context
        self.actor = actor
    }

    // MARK: - Consultas

    public func company() throws -> Company? {
        try context.fetch(FetchDescriptor<Company>()).first
    }

    public func accounts(includeArchived: Bool = false) throws -> [Account] {
        let all = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.code), SortDescriptor(\.name)]))
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    public func account(id: UUID?) throws -> Account? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Primera cuenta activa de sistema (o, si no hay, cualquiera) con ese subtipo.
    public func systemAccount(_ subtype: AccountSubtype) throws -> Account {
        let raw = subtype.rawValue
        let candidates = try context.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.subtypeRaw == raw && !$0.isArchived },
            sortBy: [SortDescriptor(\.code)]
        ))
        guard let account = candidates.first(where: \.isSystem) ?? candidates.first else {
            throw BookkeepingError.missingSystemAccount(subtype)
        }
        return account
    }

    public func entry(id: UUID?) throws -> JournalEntry? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Líneas contabilizadas en el formato de los reportes de `ChirograCore`.
    public func ledgerLines() throws -> [LedgerLine] {
        let posted = EntryStatus.posted.rawValue
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.statusRaw == posted }))
        return entries.flatMap { entry in
            (entry.lines ?? []).compactMap { line in
                guard let accountID = line.account?.id else { return nil }
                return LedgerLine(accountID: accountID, date: entry.date, debit: line.debit, credit: line.credit)
            }
        }
    }

    public func ledgerAccounts() throws -> [LedgerAccount] {
        try accounts(includeArchived: true).map(\.ledgerAccount)
    }

    public func fiscalYearStart(containing date: Date, calendar: Calendar = .current) throws -> Date {
        let month = try company()?.fiscalYearStartMonth ?? 1
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = (components.month ?? 1) >= month ? (components.year ?? 2026) : (components.year ?? 2026) - 1
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
    }

    // MARK: - Alta de empresa

    /// Crea la empresa, el plan de cuentas de la plantilla de su sector y las series de numeración.
    @discardableResult
    public func setUpCompany(
        legalName: String,
        displayName: String = "",
        entityType: EntityType = .soleProprietorship,
        state: String = "",
        sector: BusinessSector = .services,
        locale: Locale = .current
    ) throws -> Company {
        guard try company() == nil else { throw BookkeepingError.companyAlreadyExists }
        let company = Company(legalName: legalName, displayName: displayName, entityType: entityType, state: state)
        company.sectorRaw = sector.rawValue
        context.insert(company)
        for entry in sector.template.entries {
            context.insert(Account(code: entry.code, name: entry.name(for: locale), subtype: entry.subtype, isSystem: entry.isSystem))
        }
        context.insert(NumberSequence(kind: .journalEntry, prefix: "", minimumDigits: 1))
        context.insert(NumberSequence(kind: .invoice, prefix: "F-", nextNumber: 1001))
        context.insert(NumberSequence(kind: .creditNote, prefix: "NC-", nextNumber: 1))
        audit("Company", company.id, "create", "Alta de \(legalName)")
        try context.save()
        return company
    }

    // MARK: - Asientos

    public func validator() throws -> JournalValidator {
        let infos = Dictionary(uniqueKeysWithValues: try accounts(includeArchived: true).map { ($0.id, $0.accountInfo) })
        return JournalValidator(lockDate: try company()?.lockDate, accountLookup: { infos[$0] })
    }

    public func validate(_ draft: JournalEntryDraft) throws {
        do {
            try validator().validate(draft)
        } catch let error as JournalValidationError {
            throw BookkeepingError.invalidEntry(error)
        }
    }

    /// Valida y guarda un asiento. Se valida antes de insertar nada, así que si falla no queda nada escrito.
    @discardableResult
    public func post(_ draft: JournalEntryDraft, sourceDocumentID: UUID? = nil, save: Bool = true) throws -> JournalEntry {
        try validate(draft)
        let accountsByID = Dictionary(uniqueKeysWithValues: try accounts(includeArchived: true).map { ($0.id, $0) })

        let entry = JournalEntry(number: try nextNumber(.journalEntry), date: draft.date, memo: draft.memo, source: draft.source)
        entry.sourceDocumentID = sourceDocumentID
        context.insert(entry)
        for (index, line) in draft.lines.enumerated() {
            guard let account = accountsByID[line.accountID] else { throw BookkeepingError.unknownAccount }
            let model = JournalLine(account: account, debit: line.debit, credit: line.credit, memo: line.memo, order: index)
            model.entry = entry
            context.insert(model)
        }
        audit("JournalEntry", entry.id, "post", "Asiento \(entry.number): \(draft.memo)")
        if save { try saveOrRollback() }
        return entry
    }

    /// Revierte un asiento contabilizado con un asiento espejo (los asientos nunca se editan ni se borran).
    @discardableResult
    public func reverse(_ entry: JournalEntry, on date: Date = Date(), memo: String? = nil, save: Bool = true) throws -> JournalEntry {
        guard entry.status == .posted, !entry.isReversed, entry.reversesEntryID == nil else {
            throw BookkeepingError.invalidState("Este asiento ya fue revertido o es una reversión.")
        }
        let reversal = try post(entry.draft.reversal(on: date, memo: memo), sourceDocumentID: entry.sourceDocumentID, save: false)
        reversal.reversesEntryID = entry.id
        entry.reversedByEntryID = reversal.id
        if save { try saveOrRollback() }
        return reversal
    }

    // MARK: - Ventas

    /// Guarda un borrador de factura. Si `existing` ya existe, reescribe **todos** sus campos y
    /// reemplaza sus líneas, para que un reintento de emisión use siempre los datos actuales del editor.
    @discardableResult
    public func saveDraft(_ input: InvoiceDraftInput, into existing: Invoice? = nil) throws -> Invoice {
        if let existing, existing.status != .draft {
            throw BookkeepingError.invalidState("Solo se pueden editar facturas en borrador.")
        }
        let invoice = existing ?? Invoice(customer: input.customer, issueDate: input.issueDate, dueDate: input.dueDate)
        if existing == nil { context.insert(invoice) }

        invoice.customer = input.customer
        invoice.issueDate = input.issueDate
        invoice.dueDate = input.dueDate
        invoice.taxGroupID = input.taxGroupID
        invoice.customerMessage = input.customerMessage
        for line in invoice.lines ?? [] { context.delete(line) }
        invoice.lines = []
        for (index, line) in input.lines.enumerated() {
            let model = InvoiceLine(details: line.details, quantity: line.quantity, unitPrice: line.unitPrice,
                                    isTaxable: line.isTaxable, incomeAccountID: line.incomeAccountID, order: index)
            model.invoice = invoice
            context.insert(model)
        }
        try saveOrRollback()
        return invoice
    }

    /// Componentes de impuesto de un grupo, con la cuenta de pasivo de cada agencia.
    public func taxComponents(groupID: UUID?, on date: Date) throws -> [TaxComponent] {
        guard let groupID else { return [] }
        var descriptor = FetchDescriptor<TaxGroup>(predicate: #Predicate { $0.id == groupID })
        descriptor.fetchLimit = 1
        guard let group = try context.fetch(descriptor).first else { return [] }
        let fallback = try systemAccount(.salesTaxPayable).id
        return (group.rates ?? []).filter { $0.isEffective(on: date) }.map { rate in
            TaxComponent(id: rate.id, name: rate.name, rateMillionths: rate.rateMillionths,
                         liabilityAccountID: rate.agency?.liabilityAccountID ?? fallback)
        }
    }

    /// Emite una factura en borrador: calcula impuestos, asigna número y contabiliza
    /// Debe CxC / Haber Ingresos + Sales Tax Payable.
    @discardableResult
    public func issue(_ invoice: Invoice) throws -> JournalEntry {
        guard invoice.status == .draft else { throw BookkeepingError.invalidState("La factura ya fue emitida.") }
        let receivable = try systemAccount(.accountsReceivable)
        let defaultIncome = try systemAccount(.sales).id
        let lines = invoice.sortedLines.map {
            SalesLine(incomeAccountID: $0.incomeAccountID ?? defaultIncome, amount: $0.amount, isTaxable: $0.isTaxable, memo: $0.details)
        }
        // Nada se modifica hasta que el asiento es válido: el número se reserva después.
        let number = invoice.number.isEmpty ? try peekDocumentNumber(.invoice) : invoice.number

        let components = try taxComponents(groupID: invoice.taxGroupID, on: invoice.issueDate)
        let posting: InvoicePosting
        do {
            posting = try PostingRules.invoice(
                date: invoice.issueDate,
                memo: "Factura \(number) · \(invoice.customer?.name ?? "")",
                receivableAccountID: receivable.id,
                lines: lines,
                taxComponents: components,
                customerIsTaxExempt: invoice.customer?.isTaxExempt ?? false
            )
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }

        try validate(posting.entry)
        if invoice.number.isEmpty { invoice.number = try nextDocumentNumber(.invoice) }
        let entry = try post(posting.entry, sourceDocumentID: invoice.id, save: false)
        entry.lines?.forEach { $0.customerID = invoice.customer?.id }
        invoice.journalEntryID = entry.id
        invoice.subtotal = posting.subtotal
        invoice.taxTotal = posting.totalTax
        invoice.total = posting.total
        invoice.taxLines = posting.taxes.map {
            InvoiceTaxLine(taxRateID: $0.component.id, name: $0.component.name, rateMillionths: $0.component.rateMillionths,
                           taxableBase: $0.taxableBase, amount: $0.amount)
        }
        invoice.status = .sent
        try saveOrRollback()
        return entry
    }

    /// Registra un cobro aplicado a una factura: Debe Banco / Haber CxC.
    @discardableResult
    public func recordPayment(
        for invoice: Invoice, amount: Int64, date: Date = Date(), depositAccount: Account, method: PaymentMethod = .bankTransfer
    ) throws -> PaymentReceived {
        guard invoice.isOpen else { throw BookkeepingError.invalidState("La factura no está pendiente de cobro.") }
        guard amount <= invoice.balanceDue else { throw BookkeepingError.overpayment(balanceDue: invoice.balanceDue) }
        let receivable = try systemAccount(.accountsReceivable)

        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.paymentReceived(
                date: date, memo: "Cobro \(invoice.number) · \(invoice.customer?.name ?? "")",
                amount: amount, depositAccountID: depositAccount.id, receivableAccountID: receivable.id
            )
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }

        let payment = PaymentReceived(customer: invoice.customer, date: date, amount: amount, method: method, depositAccountID: depositAccount.id)
        let entry = try post(draft, sourceDocumentID: payment.id, save: false)
        context.insert(payment)
        entry.lines?.forEach { $0.customerID = invoice.customer?.id }
        payment.journalEntryID = entry.id
        let application = PaymentApplication(amount: amount, invoice: invoice)
        application.payment = payment
        context.insert(application)

        invoice.amountPaid += amount
        invoice.status = invoice.balanceDue == 0 ? .paid : .partiallyPaid
        try saveOrRollback()
        return payment
    }

    /// Anula una factura sin cobros revirtiendo su asiento.
    public func void(_ invoice: Invoice, on date: Date = Date()) throws {
        guard invoice.status == .sent, invoice.amountPaid == 0 else {
            throw BookkeepingError.invalidState("Solo se anulan facturas emitidas sin cobros.")
        }
        if let entry = try entry(id: invoice.journalEntryID) {
            try reverse(entry, on: date, memo: "Anulación factura \(invoice.number)", save: false)
        }
        invoice.status = .void
        try saveOrRollback()
    }

    // MARK: - Compras y gastos

    /// Registra una factura de proveedor: Debe Gastos / Haber CxP.
    @discardableResult
    public func record(_ bill: Bill) throws -> JournalEntry {
        guard bill.journalEntryID == nil else { throw BookkeepingError.invalidState("La factura del proveedor ya está registrada.") }
        let payable = try account(id: bill.payableAccountID) ?? systemAccount(.accountsPayable)
        let lines = try costLines(bill.sortedLines.map { ($0.accountID, $0.amount, $0.details) })
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.bill(date: bill.billDate, memo: "Factura \(bill.vendorNumber) · \(bill.vendor?.name ?? "")",
                                          payableAccountID: payable.id, lines: lines)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let entry = try post(draft, sourceDocumentID: bill.id, save: false)
        entry.lines?.forEach { $0.vendorID = bill.vendor?.id }
        bill.payableAccountID = payable.id
        bill.journalEntryID = entry.id
        bill.total = draft.totalCredits
        bill.status = .open
        try saveOrRollback()
        return entry
    }

    /// Paga (total o parcialmente) una factura de proveedor: Debe CxP / Haber Banco.
    @discardableResult
    public func pay(
        _ bill: Bill, amount: Int64, date: Date = Date(), from paymentAccount: Account, method: PaymentMethod = .bankTransfer
    ) throws -> BillPayment {
        guard bill.isOpen, bill.journalEntryID != nil else { throw BookkeepingError.invalidState("La factura del proveedor no está pendiente.") }
        guard amount <= bill.balanceDue else { throw BookkeepingError.overpayment(balanceDue: bill.balanceDue) }
        let payable = try account(id: bill.payableAccountID) ?? systemAccount(.accountsPayable)
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.billPayment(date: date, memo: "Pago \(bill.vendorNumber) · \(bill.vendor?.name ?? "")",
                                                 amount: amount, payableAccountID: payable.id, paymentAccountID: paymentAccount.id)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let payment = BillPayment(bill: bill, date: date, amount: amount, method: method, paymentAccountID: paymentAccount.id)
        let entry = try post(draft, sourceDocumentID: payment.id, save: false)
        context.insert(payment)
        entry.lines?.forEach { $0.vendorID = bill.vendor?.id }
        payment.journalEntryID = entry.id
        bill.amountPaid += amount
        bill.status = bill.balanceDue == 0 ? .paid : .partiallyPaid
        try saveOrRollback()
        return payment
    }

    /// Registra un gasto pagado al momento: Debe Gastos / Haber cuenta de pago.
    @discardableResult
    public func record(_ expense: Expense) throws -> JournalEntry {
        guard !expense.isPosted else { throw BookkeepingError.invalidState("El gasto ya está registrado.") }
        guard let paymentAccount = try account(id: expense.paymentAccountID) else { throw BookkeepingError.unknownAccount }
        let lines = try costLines(expense.sortedLines.map { ($0.accountID, $0.amount, $0.details) })
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.expense(date: expense.date, memo: "Gasto · \(expense.payee)",
                                             paymentAccountID: paymentAccount.id, lines: lines)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let entry = try post(draft, sourceDocumentID: expense.id, save: false)
        entry.lines?.forEach { $0.vendorID = expense.vendor?.id }
        expense.journalEntryID = entry.id
        expense.total = draft.totalCredits
        try saveOrRollback()
        return entry
    }

    // MARK: - Auxiliares

    private func costLines(_ raw: [(UUID?, Int64, String)]) throws -> [CostLine] {
        try raw.map { accountID, amount, memo in
            guard let accountID else { throw BookkeepingError.unknownAccount }
            return CostLine(accountID: accountID, amount: amount, memo: memo)
        }
    }

    private func sequence(_ kind: DocumentKind) throws -> NumberSequence {
        let raw = kind.rawValue
        if let existing = try context.fetch(FetchDescriptor<NumberSequence>(predicate: #Predicate { $0.kindRaw == raw })).first {
            return existing
        }
        let created = NumberSequence(kind: kind, prefix: "")
        context.insert(created)
        return created
    }

    private func nextNumber(_ kind: DocumentKind) throws -> Int {
        let sequence = try sequence(kind)
        defer { sequence.nextNumber += 1 }
        return sequence.nextNumber
    }

    /// Siguiente número con formato, sin reservarlo.
    public func peekDocumentNumber(_ kind: DocumentKind) throws -> String {
        let sequence = try sequence(kind)
        return sequence.format(sequence.nextNumber)
    }

    /// Número de documento con formato. Se asigna al emitir; tras sincronizar habría que validar colisiones (§6.5).
    public func nextDocumentNumber(_ kind: DocumentKind) throws -> String {
        let sequence = try sequence(kind)
        return sequence.format(try nextNumber(kind))
    }

    private func audit(_ entity: String, _ id: UUID?, _ action: String, _ summary: String) {
        context.insert(AuditEvent(actor: actor, entityName: entity, entityID: id, action: action, summary: summary))
    }

    private func saveOrRollback() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
