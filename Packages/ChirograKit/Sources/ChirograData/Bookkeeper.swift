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
    case exceedsCreditable(Int64)
    case wrongClosingPassword
    /// Sin contraseña de cierre, registrar en un periodo cerrado pide un motivo (QA Hudson, H02).
    case closedPeriodReasonRequired
    case duplicateAccountCode(String)
    /// La suscripción terminó: los libros se pueden ver y exportar, pero no se registra nada (`Bookkeeper.isReadOnly`).
    case readOnly
    /// Esquema 4: ya hay tantas empresas activas como permite el plan (`Bookkeeper.companyLimit`).
    case companyLimitReached(Int)
    /// Esquema 4: el asiento tiene líneas de una conciliación terminada; para cambiarlo hay que confirmarlo
    /// (`Bookkeeper.allowingReconciledChanges()`).
    case reconciledLines

    public var errorDescription: String? {
        switch self {
        case .noCompany: String(localized: "Todavía no hay una empresa configurada.")
        case .companyAlreadyExists: String(localized: "La empresa ya está configurada.")
        case .missingSystemAccount(let subtype): String(localized: "Falta la cuenta de sistema «\(subtype.rawValue)».")
        case .unknownAccount: String(localized: "La cuenta indicada no existe.")
        case .invalidEntry(let error): error.localizedMessage
        case .invalidDocument(let error): error.localizedMessage
        case .invalidState(let message): message
        case .overpayment(let balance): String(localized: "El importe supera el saldo pendiente (\(Money(minorUnits: balance).formatted())).")
        case .exceedsCreditable(let available):
            String(localized: "La nota supera lo que queda por acreditar de la factura (\(Money(minorUnits: available).formatted())).")
        case .wrongClosingPassword: String(localized: "La contraseña de cierre no es correcta.")
        case .closedPeriodReasonRequired: String(localized: "Escribe el motivo para registrar en un periodo cerrado.")
        case .duplicateAccountCode(let code): String(localized: "Ya hay una cuenta activa con el número \(code).")
        case .readOnly: String(localized: "Tus libros están en solo lectura porque la suscripción terminó. Suscríbete para seguir registrando.")
        case .companyLimitReached(let limit):
            limit == 1 ? String(localized: "Tu plan incluye una empresa. Con el plan para contadores llevas todas las que quieras.")
                : String(localized: "Tu plan incluye hasta \(limit) empresas. Archiva una para añadir otra.")
        case .reconciledLines:
            String(localized: "Este movimiento ya está conciliado con el extracto del banco. Si lo cambias, la conciliación dejará de cuadrar.")
        }
    }
}

extension JournalValidationError {
    public var localizedMessage: String {
        switch self {
        case .tooFewLines: String(localized: "Un asiento necesita al menos dos líneas.")
        case .emptyLine(let index): String(localized: "La línea \(index + 1) no tiene importe.")
        case .negativeAmount(let index): String(localized: "La línea \(index + 1) tiene un importe negativo.")
        case .bothSides(let index): String(localized: "La línea \(index + 1) tiene importe en el debe y en el haber.")
        case .singleAccount: String(localized: "El asiento necesita al menos dos cuentas distintas.")
        case .unbalanced(let debits, let credits):
            String(localized: "El debe (\(Money(minorUnits: debits).formatted())) y el haber (\(Money(minorUnits: credits).formatted())) no cuadran.")
        case .unknownAccount(let index): String(localized: "La cuenta de la línea \(index + 1) no existe.")
        case .accountNotPostable(let index): String(localized: "La cuenta de la línea \(index + 1) está archivada o es una cuenta padre.")
        case .periodLocked(let lockDate): String(localized: "El periodo está cerrado hasta el \(AuditFormat.day(lockDate)).")
        }
    }
}

extension PostingError {
    public var localizedMessage: String {
        switch self {
        case .noLines: String(localized: "El documento no tiene líneas.")
        case .nonPositiveAmount: String(localized: "Todos los importes deben ser mayores que cero.")
        case .sameAccount: String(localized: "La cuenta de origen y la de destino no pueden ser la misma.")
        case .invalidDiscount: String(localized: "El descuento no puede ser negativo ni mayor que el subtotal.")
        }
    }
}

/// Punto único de escritura contable: convierte documentos en asientos con `ChirograCore`,
/// los valida y los guarda en una sola operación (DISEÑO §6.3). Las vistas no escriben asientos por su cuenta.
@MainActor
public struct Bookkeeper {
    public let context: ModelContext
    public var actor: String
    /// Esquema 4: empresa con la que trabaja. `nil` = la activa del aparato (`ActiveCompany`) o, si no hay, la primera
    /// (`resolvedCompanyID()`, `Bookkeeper+Companies.swift`).
    public var companyID: UUID?
    /// `true` en la copia que devuelve `unlockedForClosedPeriod(password:)`: deja registrar en un periodo cerrado.
    public private(set) var allowsPostingInClosedPeriod = false
    /// `true` en la copia que devuelve `allowingReconciledChanges()`: deja revertir asientos con líneas conciliadas.
    public private(set) var allowsChangingReconciled = false

    public init(context: ModelContext, actor: String = "", companyID: UUID? = nil) {
        self.context = context
        self.actor = actor
        self.companyID = companyID
    }

    /// Copia que deja cambiar (revertir, editar, anular) asientos con líneas de una conciliación terminada, después de
    /// que el usuario confirme el aviso (DISEÑO §4.6). Queda en la auditoría al revertir.
    public func allowingReconciledChanges() -> Bookkeeper {
        var copy = self
        copy.allowsChangingReconciled = true
        return copy
    }

    /// Copia de este `Bookkeeper` que puede registrar con fecha en un periodo cerrado. Si la empresa tiene
    /// contraseña de cierre hay que darla; si no tiene, hay que escribir el motivo (QA Hudson, H02: antes bastaba un
    /// toque). El motivo, si lo hay, queda en la auditoría junto con la autorización (DISEÑO §6.6).
    public func unlockedForClosedPeriod(password: String?, reason: String = "") throws -> Bookkeeper {
        let company = try company()
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let company, company.hasClosingPassword {
            guard let password, ClosingPassword.verify(password, against: company.closingPasswordHash) else {
                throw BookkeepingError.wrongClosingPassword
            }
        } else if reason.isEmpty {
            throw BookkeepingError.closedPeriodReasonRequired
        }
        var unlocked = self
        unlocked.allowsPostingInClosedPeriod = true
        // El motivo va también solo, en el detalle del evento, para la lista «Cambios después del cierre».
        insert(AuditEvent(actor: actor, entityName: "Company", entityID: company?.id, action: "unlockClosedPeriod",
                          summary: reason.isEmpty
                              ? String(localized: "Registro en periodo cerrado autorizado")
                              : String(localized: "Registro en periodo cerrado autorizado. Motivo: \(reason)"),
                          device: Self.deviceName, changeDetails: reason))
        return unlocked
    }

    // MARK: - Consultas

    /// La empresa de este `Bookkeeper` (`resolvedCompanyID()`).
    public func company() throws -> Company? {
        guard let id = try resolvedCompanyID() else { return nil }
        var descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func accounts(includeArchived: Bool = false) throws -> [Account] {
        let all = try fetch(Account.self, sortBy: [SortDescriptor(\.code), SortDescriptor(\.name)])
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    public func account(id: UUID?) throws -> Account? {
        guard let id else { return nil }
        return try fetch(Account.self, #Predicate { $0.id == id }, limit: 1).first
    }

    /// Primera cuenta activa de sistema (o, si no hay, cualquiera) con ese subtipo.
    public func systemAccount(_ subtype: AccountSubtype) throws -> Account {
        let raw = subtype.rawValue
        let candidates = try fetch(Account.self, #Predicate { $0.subtypeRaw == raw && !$0.isArchived },
                                   sortBy: [SortDescriptor(\.code)])
        guard let account = candidates.first(where: \.isSystem) ?? candidates.first else {
            throw BookkeepingError.missingSystemAccount(subtype)
        }
        return account
    }

    public func entry(id: UUID?) throws -> JournalEntry? {
        guard let id else { return nil }
        return try fetch(JournalEntry.self, #Predicate { $0.id == id }, limit: 1).first
    }

    /// Asientos contabilizados de la empresa.
    public func postedEntries() throws -> [JournalEntry] {
        let posted = EntryStatus.posted.rawValue
        return try fetch(JournalEntry.self, #Predicate { $0.statusRaw == posted })
    }

    /// Líneas contabilizadas en el formato de los reportes de `ChirograCore` (con el asiento, para el flujo de efectivo).
    public func ledgerLines() throws -> [LedgerLine] {
        try postedEntries().flatMap { entry in
            (entry.lines ?? []).compactMap { line in
                guard let accountID = line.account?.id else { return nil }
                return LedgerLine(accountID: accountID, date: entry.date, debit: line.debit, credit: line.credit, entryID: entry.id)
            }
        }
    }

    /// Las líneas contabilizadas de **una** cuenta (por su relación, sin recorrer todo el diario): para saldos sueltos,
    /// como el sales tax de cada empresa en la lista de empresas o el aviso de sales tax, que con muchas empresas
    /// (plan para contadores sin límite) no pueden leer todos los asientos de cada una.
    public func postedLedgerLines(of account: Account) -> [LedgerLine] {
        (account.lines ?? []).compactMap { line in
            guard let entry = line.entry, entry.status == .posted else { return nil }
            return LedgerLine(accountID: account.id, date: entry.date, debit: line.debit, credit: line.credit, entryID: entry.id)
        }
    }

    /// Saldo contabilizado de una cuenta (sus propias líneas), hasta `asOf` si se da.
    public func postedBalance(of account: Account, asOf: Date? = nil) -> Int64 {
        ReportBuilder.balance(of: account.ledgerAccount, lines: postedLedgerLines(of: account), asOf: asOf)
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

    /// Crea la empresa, el plan de cuentas de la plantilla de su sector y las series de numeración, y la deja activa
    /// en este aparato. Esquema 4: con un `Bookkeeper` de `forNewCompany()` da de alta **otra** empresa (con el id de
    /// ese `Bookkeeper`), dentro del límite del plan; con uno sin `companyID`, solo la primera (si ya hay una, falla
    /// con `companyAlreadyExists`, como antes).
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
        let existing = try companies(includeArchived: true)
        if !existing.isEmpty, try !canAddCompany() { throw BookkeepingError.companyLimitReached(Self.companyLimit) }
        let company = Company(legalName: legalName, displayName: displayName, entityType: entityType, state: state)
        if let companyID { company.id = companyID }
        company.sectorRaw = sector.rawValue
        company.sortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        context.insert(company)
        let books = forCompany(company.id)
        for entry in sector.template.entries {
            books.insert(Account(code: entry.code, name: entry.name(for: locale), subtype: entry.subtype, isSystem: entry.isSystem))
        }
        for kind in DocumentKind.allCases {
            let format = kind.defaultFormat
            books.insert(NumberSequence(kind: kind, prefix: format.prefix, nextNumber: format.firstNumber, minimumDigits: format.minimumDigits))
        }
        books.audit("Company", company.id, "create", String(localized: "Alta de \(legalName)"))
        try context.save()
        ActiveCompany.select(company)
        return company
    }

    // MARK: - Asientos

    public func validator() throws -> JournalValidator {
        let infos = Dictionary(uniqueKeysWithValues: try accounts(includeArchived: true).map { ($0.id, $0.accountInfo) })
        let lockDate = allowsPostingInClosedPeriod ? nil : try company()?.lockDate
        return JournalValidator(lockDate: lockDate, accountLookup: { infos[$0] })
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
        insert(entry)
        for (index, line) in draft.lines.enumerated() {
            guard let account = accountsByID[line.accountID] else { throw BookkeepingError.unknownAccount }
            let model = JournalLine(account: account, debit: line.debit, credit: line.credit, memo: line.memo, order: index)
            model.entry = entry
            insert(model)
        }
        audit("JournalEntry", entry.id, "post", draft.source == .accountantAdjustment
              ? String(localized: "Ajuste del contador \(entry.number): \(draft.memo)")
              : String(localized: "Asiento \(entry.number): \(draft.memo)"))
        if save { try saveOrRollback() }
        return entry
    }

    /// Revierte un asiento contabilizado con un asiento espejo (los asientos nunca se editan ni se borran).
    @discardableResult
    public func reverse(_ entry: JournalEntry, on date: Date = Date(), memo: String? = nil, save: Bool = true) throws -> JournalEntry {
        try reverse(entry, on: date, memo: memo, save: save, keepingReconciliation: false)
    }

    /// `keepingReconciliation`: quien llama pasa la conciliación al asiento nuevo (`carryReconciliation`), así que no
    /// hace falta confirmarlo ni anotar «Asiento conciliado cambiado».
    func reverse(_ entry: JournalEntry, on date: Date = Date(), memo: String? = nil, save: Bool = true,
                 keepingReconciliation: Bool) throws -> JournalEntry {
        guard entry.status == .posted, !entry.isReversed, entry.reversesEntryID == nil else {
            throw BookkeepingError.invalidState(String(localized: "Este asiento ya fue revertido o es una reversión."))
        }
        if !keepingReconciliation, try hasReconciledLines(entry) {
            guard allowsChangingReconciled else { throw BookkeepingError.reconciledLines }
            audit("JournalEntry", entry.id, "changeReconciled", String(localized: "Asiento conciliado cambiado: \(entry.number)"))
        }
        var draft = entry.draft.reversal(on: date, memo: memo)
        // La reversión de un ajuste del contador también es suya: sale con la marca y en el filtro «Del contador»
        // (decisión del usuario del 11-nov). Sigue enlazada con `reversesEntryID`, así que cuenta como reversión.
        if entry.source == .accountantAdjustment { draft.source = .accountantAdjustment }
        let reversal = try post(draft, sourceDocumentID: entry.sourceDocumentID, save: false)
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
            throw BookkeepingError.invalidState(String(localized: "Solo se pueden editar facturas en borrador."))
        }
        let invoice = existing ?? Invoice(customer: input.customer, issueDate: input.issueDate, dueDate: input.dueDate)
        if existing == nil {
            insert(invoice)
            invoice.pricesIncludeTax = try company()?.pricesIncludeTax ?? false
        }
        apply(input, to: invoice)
        try storeDraftTotals(of: invoice)
        try saveOrRollback()
        return invoice
    }

    /// Copia en la factura los datos del editor y reemplaza sus líneas (borrador o, al editar, factura emitida).
    func apply(_ input: InvoiceDraftInput, to invoice: Invoice) {
        if let pricesIncludeTax = input.pricesIncludeTax { invoice.pricesIncludeTax = pricesIncludeTax }
        invoice.customer = input.customer
        invoice.issueDate = input.issueDate
        invoice.dueDate = input.dueDate
        invoice.taxGroupID = input.taxGroupID
        invoice.discount = input.discount
        invoice.customerMessage = input.customerMessage
        for line in invoice.lines ?? [] { context.delete(line) }
        invoice.lines = []
        for (index, line) in input.lines.enumerated() {
            let model = InvoiceLine(details: line.details, quantity: line.quantity, unitPrice: line.unitPrice,
                                    isTaxable: line.isTaxable, incomeAccountID: line.incomeAccountID, order: index)
            model.invoice = invoice
            insert(model)
        }
    }

    /// Guarda en el borrador los totales con las reglas de emisión (impuesto, descuento, impuesto incluido), para que
    /// las listas muestren lo mismo que el detalle sin calcularlos por fila. Devuelve si cambió algo.
    @discardableResult
    func storeDraftTotals(of invoice: Invoice) throws -> Bool {
        guard invoice.status == .draft else { return false }
        let totals = try totals(for: invoice)
        guard invoice.subtotal != totals.subtotal || invoice.taxTotal != totals.tax || invoice.total != totals.total else { return false }
        invoice.subtotal = totals.subtotal
        invoice.taxTotal = totals.tax
        invoice.total = totals.total
        return true
    }

    /// Recalcula los totales guardados de los borradores (los de antes de guardarse así, o si cambió una tasa o la
    /// exención del cliente). Solo guarda si alguno cambió. Devuelve cuántos cambiaron.
    @discardableResult
    public func refreshDraftTotals() throws -> Int {
        let draft = InvoiceStatus.draft.rawValue
        let drafts = try fetch(Invoice.self, #Predicate { $0.statusRaw == draft })
        var changed = 0
        for invoice in drafts where try storeDraftTotals(of: invoice) { changed += 1 }
        if changed > 0 { try saveOrRollback() }
        return changed
    }

    /// Componentes de impuesto de un grupo, con la cuenta de pasivo de cada agencia. El id también puede ser
    /// el de una sola `TaxRate` (esquema 2: «tasa predeterminada»), que cuenta como grupo de un componente.
    public func taxComponents(groupID: UUID?, on date: Date) throws -> [TaxComponent] {
        guard let groupID else { return [] }
        let rates: [TaxRate]
        if let group = try taxGroup(id: groupID) {
            rates = group.sortedRates
        } else if let rate = try taxRate(id: groupID) {
            rates = [rate]
        } else {
            return []
        }
        let fallback = try systemAccount(.salesTaxPayable).id
        return rates.filter { $0.isEffective(on: date) }.map { rate in
            TaxComponent(id: rate.id, name: rate.name, rateMillionths: rate.rateMillionths,
                         liabilityAccountID: rate.agency?.liabilityAccountID ?? fallback)
        }
    }

    public func taxRate(id: UUID?) throws -> TaxRate? {
        guard let id else { return nil }
        return try fetch(TaxRate.self, #Predicate { $0.id == id }, limit: 1).first
    }

    public func taxGroup(id: UUID?) throws -> TaxGroup? {
        guard let id else { return nil }
        return try fetch(TaxGroup.self, #Predicate { $0.id == id }, limit: 1).first
    }

    /// Componentes con que se **emitió** una factura (tasas guardadas en `taxLines`), para que las notas de crédito
    /// y los reportes no cambien si después se edita una tasa. La cuenta de pasivo es la actual de cada agencia.
    public func issuedTaxComponents(of invoice: Invoice) throws -> [TaxComponent] {
        let fallback = try systemAccount(.salesTaxPayable).id
        return try (invoice.taxLines ?? []).sorted { $0.name < $1.name }.map { line in
            TaxComponent(id: line.taxRateID ?? line.id, name: line.name, rateMillionths: line.rateMillionths,
                         liabilityAccountID: try taxRate(id: line.taxRateID)?.agency?.liabilityAccountID ?? fallback)
        }
    }

    /// Emite una factura en borrador: calcula impuestos, asigna número y contabiliza
    /// Debe CxC / Haber Ingresos + Sales Tax Payable.
    @discardableResult
    public func issue(_ invoice: Invoice) throws -> JournalEntry {
        guard invoice.status == .draft else { throw BookkeepingError.invalidState(String(localized: "La factura ya fue emitida.")) }
        // Nada se modifica hasta que el asiento es válido: el número se reserva después.
        let number = invoice.number.isEmpty ? try peekDocumentNumber(.invoice) : invoice.number
        let components = try taxComponents(groupID: invoice.taxGroupID, on: invoice.issueDate)
        let posting = try invoicePosting(for: invoice, number: number, taxComponents: components)

        try validate(posting.entry)
        if invoice.number.isEmpty { invoice.number = try nextDocumentNumber(.invoice) }
        let entry = try post(posting.entry, sourceDocumentID: invoice.id, save: false)
        entry.lines?.forEach { $0.customerID = invoice.customer?.id }
        invoice.journalEntryID = entry.id
        store(posting, in: invoice)
        invoice.status = .sent
        try saveOrRollback()
        return entry
    }

    /// Asiento de emisión de la factura con sus datos actuales: Debe CxC / Haber Ingresos (+ Sales Tax Payable, − descuento).
    func invoicePosting(for invoice: Invoice, number: String, taxComponents components: [TaxComponent]) throws -> InvoicePosting {
        try invoicePosting(number: number, customer: invoice.customer, date: invoice.issueDate,
                           lines: invoice.sortedLines.map { ($0.incomeAccountID, $0.amount, $0.isTaxable, $0.details) },
                           discount: invoice.discount, pricesIncludeTax: invoice.pricesIncludeTax, taxComponents: components)
    }

    /// El mismo asiento a partir de los datos sueltos (p. ej. los del editor, antes de tocar la factura).
    func invoicePosting(number: String, customer: Customer?, date: Date, lines raw: [(UUID?, Int64, Bool, String)],
                        discount: Int64, pricesIncludeTax: Bool, taxComponents components: [TaxComponent]) throws -> InvoicePosting {
        let receivable = try systemAccount(.accountsReceivable)
        let defaultIncome = try systemAccount(.sales).id
        let lines = raw.map { SalesLine(incomeAccountID: $0.0 ?? defaultIncome, amount: $0.1, isTaxable: $0.2, memo: $0.3) }
        let discountAccountID = discount > 0 ? try systemAccount(.salesDiscount).id : nil
        do {
            return try PostingRules.invoice(
                date: date,
                memo: String(localized: "Factura \(number) · \(customer?.name ?? "")"),
                receivableAccountID: receivable.id,
                lines: lines,
                taxComponents: components,
                customerIsTaxExempt: customer?.isTaxExempt ?? false,
                discount: discount,
                discountAccountID: discountAccountID,
                pricesIncludeTax: pricesIncludeTax
            )
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
    }

    /// Guarda en la factura los totales y el desglose de impuesto (`InvoiceTaxLine`) de su asiento de emisión.
    func store(_ posting: InvoicePosting, in invoice: Invoice) {
        invoice.subtotal = posting.subtotal
        invoice.taxTotal = posting.totalTax
        invoice.total = posting.total
        for line in invoice.taxLines ?? [] { context.delete(line) }
        invoice.taxLines = posting.taxes.map {
            InvoiceTaxLine(taxRateID: $0.component.id, name: $0.component.name, rateMillionths: $0.component.rateMillionths,
                           taxableBase: $0.taxableBase, amount: $0.amount)
        }
    }

    /// Registra un cobro aplicado a una factura: Debe Banco / Haber CxC.
    @discardableResult
    public func recordPayment(
        for invoice: Invoice, amount: Int64, date: Date = Date(), depositAccount: Account, method: PaymentMethod = .bankTransfer,
        save: Bool = true
    ) throws -> PaymentReceived {
        guard invoice.isOpen else { throw BookkeepingError.invalidState(String(localized: "La factura no está pendiente de cobro.")) }
        guard amount <= invoice.balanceDue else { throw BookkeepingError.overpayment(balanceDue: invoice.balanceDue) }
        let receivable = try systemAccount(.accountsReceivable)

        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.paymentReceived(
                date: date, memo: String(localized: "Cobro \(invoice.number) · \(invoice.customer?.name ?? "")"),
                amount: amount, depositAccountID: depositAccount.id, receivableAccountID: receivable.id
            )
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }

        let payment = PaymentReceived(customer: invoice.customer, date: date, amount: amount, method: method, depositAccountID: depositAccount.id)
        let entry = try post(draft, sourceDocumentID: payment.id, save: false)
        insert(payment)
        entry.lines?.forEach { $0.customerID = invoice.customer?.id }
        payment.journalEntryID = entry.id
        let application = PaymentApplication(amount: amount, invoice: invoice)
        application.payment = payment
        insert(application)

        invoice.amountPaid += amount
        invoice.status = invoice.balanceDue == 0 ? .paid : .partiallyPaid
        if save { try saveOrRollback() }
        return payment
    }

    /// Emite una nota de crédito contra una factura emitida: Debe Ingresos (+ Sales Tax Payable) / Haber CxC.
    /// El impuesto se calcula con las tasas con que se emitió la factura (`issuedTaxComponents`), aunque
    /// después se hayan editado. `amount` es siempre sin impuesto, también en facturas con precios con impuesto incluido.
    ///
    /// Se aplica primero al saldo pendiente de la factura; lo que sobra (p. ej. una devolución sobre una factura
    /// ya pagada) queda como **saldo a favor** del cliente: un saldo acreedor en CxC que luego se aplica a otra
    /// factura (`applyCustomerCredit`) o se reembolsa (`refundCustomerCredit`).
    @discardableResult
    public func issueCreditNote(
        for invoice: Invoice, amount: Int64, isTaxable: Bool, reason: String, date: Date = Date(), lineID: UUID? = nil
    ) throws -> CreditNote {
        guard [.sent, .partiallyPaid, .paid].contains(invoice.status) else {
            throw BookkeepingError.invalidState(String(localized: "Solo se acreditan facturas emitidas."))
        }
        let receivable = try systemAccount(.accountsReceivable)
        let lines = try creditLines(for: invoice, amount: amount, isTaxable: isTaxable, lineID: lineID)
        let components = try issuedTaxComponents(of: invoice)
        let number = try peekDocumentNumber(.creditNote)
        let posting: InvoicePosting
        do {
            posting = try PostingRules.creditNote(
                date: date, memo: String(localized: "Nota de crédito \(number) · \(invoice.number) · \(invoice.customer?.name ?? "")"),
                receivableAccountID: receivable.id,
                lines: lines, taxComponents: components, customerIsTaxExempt: invoice.customer?.isTaxExempt ?? false
            )
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let creditable = invoice.total - (invoice.creditNotes ?? []).reduce(0) { $0 + $1.total }
        guard posting.total <= creditable else { throw BookkeepingError.exceedsCreditable(creditable) }
        try validate(posting.entry)

        let note = CreditNote(invoice: invoice, date: date, amount: amount, isTaxable: isTaxable, reason: reason)
        note.number = try nextDocumentNumber(.creditNote)
        let accounts = Set(lines.map(\.incomeAccountID))
        note.incomeAccountID = accounts.count == 1 ? accounts.first : nil
        note.taxTotal = posting.totalTax
        note.total = posting.total
        note.unappliedAmount = posting.total
        let entry = try post(posting.entry, sourceDocumentID: note.id, save: false)
        entry.lines?.forEach { $0.customerID = invoice.customer?.id }
        note.journalEntryID = entry.id
        insert(note)
        if invoice.isOpen { apply(note, to: invoice, amount: min(posting.total, invoice.balanceDue), date: date) }
        try saveOrRollback()
        return note
    }

    /// Líneas de ingreso que rebaja una nota de crédito: las de la línea elegida de la factura o, sin línea,
    /// el importe repartido entre todas en proporción, cada parte en la cuenta de ingresos de su línea original.
    /// Sin impuesto (`isTaxable == false`) ninguna parte es gravable; con impuesto, cada parte conserva el de su línea.
    public func creditLines(for invoice: Invoice, amount: Int64, isTaxable: Bool, lineID: UUID? = nil) throws -> [SalesLine] {
        let fallback = try systemAccount(.sales).id
        let source = invoice.sortedLines.filter { lineID == nil || $0.id == lineID }.map {
            SalesLine(incomeAccountID: $0.incomeAccountID ?? fallback, amount: $0.amount, isTaxable: isTaxable && $0.isTaxable)
        }
        guard !source.isEmpty else {
            return amount > 0 ? [SalesLine(incomeAccountID: fallback, amount: amount, isTaxable: isTaxable)] : []
        }
        return PostingRules.prorated(amount, across: source)
    }

    /// Aplica saldo a favor del cliente a una de sus facturas pendientes, consumiendo sus notas de crédito
    /// de la más antigua a la más reciente. No genera asiento.
    public func applyCustomerCredit(to invoice: Invoice, amount: Int64, date: Date = Date()) throws {
        guard let customer = invoice.customer, invoice.isOpen else {
            throw BookkeepingError.invalidState(String(localized: "Solo se aplica saldo a favor a facturas pendientes de un cliente."))
        }
        guard amount > 0, amount <= customer.creditBalance, amount <= invoice.balanceDue else {
            throw BookkeepingError.overpayment(balanceDue: min(customer.creditBalance, invoice.balanceDue))
        }
        var remaining = amount
        for note in openCredits(of: customer) where remaining > 0 {
            let portion = min(note.unappliedAmount, remaining)
            apply(note, to: invoice, amount: portion, date: date)
            remaining -= portion
        }
        audit("Invoice", invoice.id, "applyCredit", String(localized: "Saldo a favor aplicado a \(invoice.number): \(Money(minorUnits: amount).formatted())"))
        try saveOrRollback()
    }

    /// Reembolsa saldo a favor al cliente: Debe CxC / Haber Banco.
    @discardableResult
    public func refundCustomerCredit(
        _ customer: Customer, amount: Int64, date: Date = Date(), from paymentAccount: Account
    ) throws -> JournalEntry {
        guard amount > 0, amount <= customer.creditBalance else { throw BookkeepingError.overpayment(balanceDue: customer.creditBalance) }
        let receivable = try systemAccount(.accountsReceivable)
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.customerRefund(date: date, memo: String(localized: "Reembolso a \(customer.name)"), amount: amount,
                                                    receivableAccountID: receivable.id, paymentAccountID: paymentAccount.id)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let entry = try post(draft, sourceDocumentID: customer.id, save: false)
        entry.lines?.forEach { $0.customerID = customer.id }
        var remaining = amount
        for note in openCredits(of: customer) where remaining > 0 {
            let portion = min(note.unappliedAmount, remaining)
            note.unappliedAmount -= portion
            note.refundedAmount += portion
            remaining -= portion
        }
        try saveOrRollback()
        return entry
    }

    private func openCredits(of customer: Customer) -> [CreditNote] {
        (customer.creditNotes ?? []).filter { $0.unappliedAmount > 0 }.sorted { $0.date < $1.date }
    }

    private func apply(_ note: CreditNote, to invoice: Invoice, amount: Int64, date: Date) {
        guard amount > 0 else { return }
        insert(CreditApplication(note: note, invoice: invoice, amount: amount, date: date))
        note.unappliedAmount -= amount
        invoice.creditsApplied += amount
        invoice.status = invoice.balanceDue == 0 ? .paid : .partiallyPaid
    }

    /// Anula una factura sin cobros ni notas de crédito revirtiendo su asiento.
    public func void(_ invoice: Invoice, on date: Date = Date()) throws {
        guard invoice.status == .sent, invoice.amountPaid == 0, invoice.creditsApplied == 0 else {
            throw BookkeepingError.invalidState(String(localized: "Solo se anulan facturas emitidas sin cobros ni notas de crédito."))
        }
        if let entry = try entry(id: invoice.journalEntryID) {
            try reverse(entry, on: date, memo: String(localized: "Anulación factura \(invoice.number)"), save: false)
        }
        invoice.status = .void
        audit("Invoice", invoice.id, "void", String(localized: "Factura \(invoice.number) anulada"),
              changes: { var c = AuditChanges(); c.value(String(localized: "Total"), money: invoice.total); return c }())
        try saveOrRollback()
    }

    // MARK: - Compras y gastos

    /// Registra una factura de proveedor: Debe Gastos / Haber CxP.
    @discardableResult
    public func record(_ bill: Bill, save: Bool = true) throws -> JournalEntry {
        guard bill.journalEntryID == nil else { throw BookkeepingError.invalidState(String(localized: "La factura del proveedor ya está registrada.")) }
        let payable = try account(id: bill.payableAccountID) ?? systemAccount(.accountsPayable)
        let lines = try costLines(bill.sortedLines.map { ($0.accountID, $0.amount, $0.details) })
        let reference = bill.vendorNumber.isEmpty ? bill.memo : bill.vendorNumber
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.bill(date: bill.billDate, memo: String(localized: "Factura \(reference) · \(bill.vendor?.name ?? "")"),
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
        if save { try saveOrRollback() }
        return entry
    }

    /// Paga (total o parcialmente) una factura de proveedor: Debe CxP / Haber Banco.
    @discardableResult
    public func pay(
        _ bill: Bill, amount: Int64, date: Date = Date(), from paymentAccount: Account, method: PaymentMethod = .bankTransfer,
        reference: String = "", save: Bool = true
    ) throws -> BillPayment {
        guard bill.isOpen, bill.journalEntryID != nil else { throw BookkeepingError.invalidState(String(localized: "La factura del proveedor no está pendiente.")) }
        guard amount <= bill.balanceDue else { throw BookkeepingError.overpayment(balanceDue: bill.balanceDue) }
        let payable = try account(id: bill.payableAccountID) ?? systemAccount(.accountsPayable)
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.billPayment(date: date, memo: String(localized: "Pago \(bill.vendorNumber) · \(bill.vendor?.name ?? "")"),
                                                 amount: amount, payableAccountID: payable.id, paymentAccountID: paymentAccount.id)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        let payment = BillPayment(bill: bill, date: date, amount: amount, method: method, paymentAccountID: paymentAccount.id)
        payment.reference = reference
        let entry = try post(draft, sourceDocumentID: payment.id, save: false)
        insert(payment)
        entry.lines?.forEach { $0.vendorID = bill.vendor?.id }
        payment.journalEntryID = entry.id
        bill.amountPaid += amount
        bill.status = bill.balanceDue == 0 ? .paid : .partiallyPaid
        if bill.balanceDue == 0 { clearSchedule(of: bill) }
        if save { try saveOrRollback() }
        return payment
    }

    /// Registra un gasto pagado al momento: Debe Gastos / Haber cuenta de pago.
    @discardableResult
    public func record(_ expense: Expense, save: Bool = true) throws -> JournalEntry {
        guard !expense.isPosted else { throw BookkeepingError.invalidState(String(localized: "El gasto ya está registrado.")) }
        guard !expense.isVoid else { throw BookkeepingError.invalidState(String(localized: "El gasto está anulado.")) }
        let draft = try expenseDraft(for: expense)
        let entry = try post(draft, sourceDocumentID: expense.id, save: false)
        entry.lines?.forEach { $0.vendorID = expense.vendor?.id; $0.customerID = expense.customer?.id }
        expense.journalEntryID = entry.id
        expense.total = draft.totalCredits
        if save { try saveOrRollback() }
        return entry
    }

    /// Asiento que corresponde a los datos actuales de un gasto: Debe Gastos / Haber cuenta de pago.
    func expenseDraft(for expense: Expense) throws -> JournalEntryDraft {
        guard let paymentAccount = try account(id: expense.paymentAccountID) else { throw BookkeepingError.unknownAccount }
        let lines = try costLines(expense.sortedLines.map { ($0.accountID, $0.amount, $0.details) })
        do {
            return try PostingRules.expense(date: expense.date, memo: String(localized: "Gasto · \(expense.payee)"),
                                            paymentAccountID: paymentAccount.id, lines: lines)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
    }

    // MARK: - Antigüedad

    /// Antigüedad de cuentas por cobrar: facturas emitidas con saldo, por cliente.
    public func receivablesAging(asOf date: Date = Date(), calendar: Calendar = .current) throws -> AgingReport {
        let items = try fetch(Invoice.self).filter { $0.isOpen && $0.balanceDue != 0 }.map {
            AgingReport.OpenItem(party: $0.customer?.name ?? String(localized: "Sin cliente"), document: $0.number, dueDate: $0.dueDate, balance: $0.balanceDue)
        }
        return ReportBuilder.aging(items: items, asOf: date, calendar: calendar)
    }

    /// Antigüedad de cuentas por pagar: facturas de proveedor registradas con saldo, por proveedor.
    public func payablesAging(asOf date: Date = Date(), calendar: Calendar = .current) throws -> AgingReport {
        let items = try fetch(Bill.self).filter { $0.isOpen && $0.journalEntryID != nil && $0.balanceDue != 0 }.map {
            AgingReport.OpenItem(party: $0.vendor?.name ?? String(localized: "Sin proveedor"), document: $0.vendorNumber, dueDate: $0.dueDate, balance: $0.balanceDue)
        }
        return ReportBuilder.aging(items: items, asOf: date, calendar: calendar)
    }

    // MARK: - Impuestos

    /// Resumen de sales tax del periodo con facturas emitidas (no anuladas) y notas de crédito.
    public func salesTaxSummary(from: Date, to: Date) throws -> SalesTaxSummary {
        let invoices = try fetch(Invoice.self).filter { $0.status != .draft && $0.status != .void }
        var documents = invoices.map { invoice in
            let exempt = invoice.customer?.isTaxExempt ?? false
            let taxes = (invoice.taxLines ?? []).map {
                SalesTaxDocument.Tax(rateID: $0.taxRateID, name: $0.name, rateMillionths: $0.rateMillionths,
                                     taxableBase: $0.taxableBase, amount: $0.amount)
            }
            // Misma base que al emitir: líneas gravables menos su parte proporcional del descuento
            // (con precios con impuesto incluido, la base ya sin impuesto que quedó en el desglose).
            let taxableLines = invoice.sortedLines.filter(\.isTaxable).reduce(0) { $0 + $1.amount }
            let taxableDiscount = invoice.subtotal == 0 ? 0
                : (invoice.discount * taxableLines).dividedRoundingHalfAwayFromZero(by: invoice.subtotal)
            let grossBase = taxableLines - taxableDiscount
            let base = invoice.pricesIncludeTax ? (invoice.taxLines?.first?.taxableBase ?? grossBase) : grossBase
            return SalesTaxDocument(date: invoice.issueDate, netSales: invoice.netSales,
                                    taxableBase: exempt ? 0 : base, isExempt: exempt, taxes: taxes)
        }
        for note in try fetch(CreditNote.self) {
            guard let invoice = note.invoice else { continue }
            let exempt = invoice.customer?.isTaxExempt ?? false
            let base = note.isTaxable && !exempt ? note.amount : 0
            // Mismo cálculo que al emitir la nota: tasas con que se emitió la factura.
            let taxes = base > 0
                ? SalesTaxCalculator.taxes(onTaxableBase: base, components: try issuedTaxComponents(of: invoice))
                    .map { SalesTaxDocument.Tax(rateID: $0.component.id, name: $0.component.name, rateMillionths: $0.component.rateMillionths,
                                                taxableBase: -$0.taxableBase, amount: -$0.amount) }
                : []
            documents.append(SalesTaxDocument(date: note.date, netSales: -note.amount, taxableBase: -base, isExempt: exempt, taxes: taxes))
        }
        return ReportBuilder.salesTaxSummary(documents: documents, from: from, to: to)
    }

    /// Pago de sales tax a la agencia: Debe Sales Tax Payable (cuenta de la agencia) / Haber Banco.
    /// No puede superar el saldo pendiente de esa cuenta.
    @discardableResult
    public func paySalesTax(
        to agency: TaxAgency?, amount: Int64, date: Date = Date(), from paymentAccount: Account, reference: String = ""
    ) throws -> JournalEntry {
        let liability = try account(id: agency?.liabilityAccountID) ?? systemAccount(.salesTaxPayable)
        let owed = ReportBuilder.balance(of: liability.ledgerAccount, lines: try ledgerLines())
        guard amount <= owed else { throw BookkeepingError.overpayment(balanceDue: owed) }
        let memo = [String(localized: "Pago de sales tax"), agency?.name, reference.isEmpty ? nil : reference].compactMap { $0 }.joined(separator: " · ")
        let draft: JournalEntryDraft
        do {
            draft = try PostingRules.salesTaxPayment(date: date, memo: memo, amount: amount,
                                                     liabilityAccountID: liability.id, paymentAccountID: paymentAccount.id)
        } catch {
            throw BookkeepingError.invalidDocument(error)
        }
        return try post(draft, sourceDocumentID: agency?.id)
    }

    // MARK: - Auxiliares

    func costLines(_ raw: [(UUID?, Int64, String)]) throws -> [CostLine] {
        try raw.map { accountID, amount, memo in
            guard let accountID else { throw BookkeepingError.unknownAccount }
            return CostLine(accountID: accountID, amount: amount, memo: memo)
        }
    }

    func sequence(_ kind: DocumentKind) throws -> NumberSequence {
        let raw = kind.rawValue
        if let existing = try fetch(NumberSequence.self, #Predicate { $0.kindRaw == raw }).first {
            return existing
        }
        let format = kind.defaultFormat
        let created = NumberSequence(kind: kind, prefix: format.prefix, nextNumber: format.firstNumber, minimumDigits: format.minimumDigits)
        insert(created)
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

    // `audit(_:_:_:_:changes:)` (la bitácora) está en `Bookkeeper+AuditLog.swift`.

    /// Libros en solo lectura: la app lo activa cuando la suscripción terminó (`SubscriptionStore`). Se pueden ver,
    /// exportar y sacar copias, pero ningún servicio de `Bookkeeper` guarda. Las pruebas lo dejan en `false`.
    public static var isReadOnly = false

    func ensureWritable() throws {
        if Self.isReadOnly { throw BookkeepingError.readOnly }
    }

    /// Guarda sin deshacer si falla (lo hace quien llama): comprueba solo lectura y pone la empresa a lo insertado.
    func commit() throws {
        try ensureWritable()
        stampInsertedModels()
        try context.save()
    }

    func saveOrRollback() throws {
        do {
            try ensureWritable()
            stampInsertedModels()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
