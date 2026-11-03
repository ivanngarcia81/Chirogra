import ChirograCore
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Gastos: alta, edición (también contabilizados) y anulación

extension Bookkeeper {

    /// Crea un gasto con sus líneas y, si `post`, lo contabiliza (Debe Gastos / Haber cuenta de pago).
    /// Sin `post` queda sin asiento («por confirmar»); se contabiliza después con `record(_:)`.
    @discardableResult
    public func createExpense(_ input: ExpenseInput, post: Bool = true) throws -> Expense {
        let expense = Expense(date: input.date, payee: input.payee, paymentAccountID: input.paymentAccountID, vendor: input.vendor)
        context.insert(expense)
        apply(input, to: expense)
        do {
            if post { try record(expense, save: false) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return expense
    }

    /// Edita un gasto.
    ///
    /// - Sin asiento: se reescriben los datos y nada más.
    /// - Contabilizado y con cambios contables (fecha, cuenta de pago, líneas, proveedor o cliente): el asiento original
    ///   **no se toca** (es inmutable); se revierte con un asiento espejo **en su misma fecha** y se contabiliza uno
    ///   nuevo con los datos nuevos. Los dos quedan enlazados (`replacesEntryID` / `replacedByEntryID`), el gasto sigue
    ///   siendo el mismo y apunta al asiento vigente, y queda un `AuditEvent` «edit». Los reportes cuadran porque el
    ///   original y su reversión se anulan entre sí.
    /// - Contabilizado y solo cambios de texto (beneficiario, nota, referencia, método, impuesto incluido): se guardan sin asientos.
    ///
    /// Si la fecha original o la nueva caen en un periodo cerrado falla; usa `unlockedForClosedPeriod(password:)`.
    /// Devuelve el asiento nuevo, o `nil` si no hizo falta.
    @discardableResult
    public func updateExpense(_ expense: Expense, with input: ExpenseInput, calendar: Calendar = .current) throws -> JournalEntry? {
        guard !expense.isVoid else { throw BookkeepingError.invalidState(String(localized: "El gasto está anulado.")) }
        guard expense.isPosted, let original = try entry(id: expense.journalEntryID) else {
            apply(input, to: expense)
            try saveOrRollback()
            return nil
        }
        let before = ExpenseInput(expense)
        let accountingChanged = !calendar.isDate(before.date, inSameDayAs: input.date)
            || before.paymentAccountID != input.paymentAccountID
            || before.lines.map { [$0.accountID?.uuidString ?? "", String($0.amount)] } != input.lines.map { [$0.accountID?.uuidString ?? "", String($0.amount)] }
            || before.vendor?.id != input.vendor?.id
            || before.customer?.id != input.customer?.id
        guard accountingChanged else {
            apply(input, to: expense)
            audit("Expense", expense.id, "edit", String(localized: "Gasto editado (sin cambios contables): \(input.payee)"))
            try saveOrRollback()
            return nil
        }
        guard original.status == .posted, !original.isReversed else {
            throw BookkeepingError.invalidState(String(localized: "El asiento del gasto ya fue revertido."))
        }
        do {
            apply(input, to: expense)
            let draft = try expenseDraft(for: expense)
            try validate(draft)
            try reverse(original, on: original.date, memo: String(localized: "Reversión por edición: \(original.memo)"), save: false)
            let replacement = try post(draft, sourceDocumentID: expense.id, save: false)
            replacement.lines?.forEach { $0.vendorID = expense.vendor?.id; $0.customerID = expense.customer?.id }
            replacement.replacesEntryID = original.id
            original.replacedByEntryID = replacement.id
            expense.journalEntryID = replacement.id
            expense.total = draft.totalCredits
            expense.revision += 1
            audit("Expense", expense.id, "edit", String(localized: "Gasto editado: \(Money(minorUnits: before.total).formatted()) → \(Money(minorUnits: draft.totalCredits).formatted()) (asiento \(original.number) revertido, nuevo \(replacement.number))"))
            try context.save()
            return replacement
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Anula un gasto: revierte su asiento (en su misma fecha) y lo marca anulado. Sin asiento, solo lo marca.
    public func void(_ expense: Expense, reason: String = "", on date: Date = Date()) throws {
        guard !expense.isVoid else { return }
        do {
            if let original = try entry(id: expense.journalEntryID), original.status == .posted, !original.isReversed {
                try reverse(original, on: original.date, memo: String(localized: "Anulación: \(original.memo)"), save: false)
            }
            expense.voidedAt = date
            audit("Expense", expense.id, "void", String(localized: "Gasto anulado: \(expense.payee)\(reason.isEmpty ? "" : " · \(reason)")"))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Historial de asientos de un gasto (originales, reversiones y vigente), del más antiguo al más nuevo.
    public func entries(ofExpense expense: Expense) throws -> [JournalEntry] {
        let expenseID: UUID? = expense.id
        return try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.sourceDocumentID == expenseID },
                                                               sortBy: [SortDescriptor(\.number)]))
    }

    private func apply(_ input: ExpenseInput, to expense: Expense) {
        expense.date = input.date
        expense.payee = input.payee
        expense.vendor = input.vendor
        expense.customer = input.customer
        expense.paymentAccountID = input.paymentAccountID
        expense.method = input.method
        expense.reference = input.reference
        expense.memo = input.memo
        expense.salesTaxIncluded = max(0, input.salesTaxIncluded)
        for line in expense.lines ?? [] { context.delete(line) }
        expense.lines = []
        for (index, line) in input.lines.enumerated() {
            let model = ExpenseLine(details: line.details, amount: line.amount, accountID: line.accountID, order: index)
            model.expense = expense
            context.insert(model)
        }
        expense.total = input.total
    }
}

// MARK: - Plan de cuentas

extension AccountInput {
    @MainActor
    public init(_ account: Account) {
        self.init(code: account.code, name: account.name, subtype: account.subtype, details: account.details,
                  parentID: account.parent?.id, last4: account.last4)
    }
}

extension Bookkeeper {

    /// Edita una cuenta del plan.
    ///
    /// - Nombre obligatorio; el número, si lo hay, único entre las cuentas activas.
    /// - Tipo de detalle (`subtype`) dentro del mismo tipo: siempre, salvo en cuentas de sistema.
    /// - Cambiar de tipo (activo, pasivo…): solo si la cuenta no tiene movimientos ni subcuentas.
    /// - Cuenta principal: del mismo tipo, activa, sin movimientos propios y sin crear ciclos.
    /// - Últimos 4 dígitos: vacío o 4 dígitos.
    public func updateAccount(_ account: Account, with input: AccountInput) throws {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = input.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La cuenta necesita un nombre.")) }
        if !code.isEmpty, try accounts().contains(where: { $0.id != account.id && $0.code == code }) {
            throw BookkeepingError.duplicateAccountCode(code)
        }
        if input.subtype != account.subtype {
            if account.isSystem {
                throw BookkeepingError.invalidState(String(localized: "Las cuentas de sistema no cambian de tipo."))
            }
            if input.subtype.accountType != account.type {
                guard (account.lines ?? []).isEmpty else {
                    throw BookkeepingError.invalidState(String(localized: "Una cuenta con movimientos no cambia de tipo; crea una cuenta nueva y reclasifica con un asiento."))
                }
                guard (account.children ?? []).isEmpty else {
                    throw BookkeepingError.invalidState(String(localized: "Una cuenta con subcuentas no cambia de tipo."))
                }
            }
        }
        let parent = try self.account(id: input.parentID)
        if input.parentID != nil, parent == nil { throw BookkeepingError.unknownAccount }
        if let parent, parent.id != account.parent?.id {
            guard parent.id != account.id, !isDescendant(parent, of: account) else {
                throw BookkeepingError.invalidState(String(localized: "Una cuenta no puede ser subcuenta de sí misma."))
            }
            guard parent.type == input.subtype.accountType, !parent.isArchived else {
                throw BookkeepingError.invalidState(String(localized: "La cuenta principal debe ser activa y del mismo tipo."))
            }
            guard (parent.lines ?? []).isEmpty else {
                throw BookkeepingError.invalidState(String(localized: "La cuenta principal ya tiene movimientos propios."))
            }
        }
        let last4 = input.last4.trimmingCharacters(in: .whitespacesAndNewlines)
        guard last4.isEmpty || (last4.count == 4 && last4.allSatisfy(\.isASCII) && last4.allSatisfy(\.isNumber)) else {
            throw BookkeepingError.invalidState(String(localized: "Los últimos dígitos deben ser 4 números."))
        }

        let summary = account.displayName
        account.name = name
        account.code = code
        account.subtype = input.subtype
        account.details = input.details
        account.parent = parent
        account.last4 = last4
        audit("Account", account.id, "update", String(localized: "Cuenta editada: \(summary) → \(account.displayName)"))
        try saveOrRollback()
    }

    private func isDescendant(_ candidate: Account, of account: Account) -> Bool {
        var current = candidate.parent
        while let node = current {
            if node.id == account.id { return true }
            current = node.parent
        }
        return false
    }
}

// MARK: - Impuestos: tasas y predeterminado

extension Bookkeeper {

    /// Edita una tasa de impuesto. Las facturas ya emitidas guardan su impuesto (`InvoiceTaxLine`) y no cambian;
    /// las notas de crédito de esas facturas usan también la tasa guardada. Los borradores toman la tasa nueva al emitirse.
    public func updateTaxRate(_ rate: TaxRate, name: String, agency: TaxAgency?, rateMillionths: Int64) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La tasa necesita un nombre.")) }
        guard (0...SalesTaxCalculator.millionth).contains(rateMillionths) else {
            throw BookkeepingError.invalidState(String(localized: "La tasa debe estar entre 0 % y 100 %."))
        }
        let before = "\(rate.name) \(rate.percent)%"
        rate.name = name
        rate.agency = agency
        rate.rateMillionths = rateMillionths
        let after = "\(name) \(rate.percent)%"
        audit("TaxRate", rate.id, "update", String(localized: "Tasa editada: \(before) → \(after)"))
        try saveOrRollback()
    }

    /// Fija el impuesto predeterminado de la empresa para facturas y estimados nuevos: id de un grupo o de una tasa, o `nil`.
    public func setDefaultTax(_ id: UUID?) throws {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        if let id {
            var descriptor = FetchDescriptor<TaxGroup>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).first != nil || taxRate(id: id) != nil else {
                throw BookkeepingError.invalidState(String(localized: "Esa tasa de impuesto no existe."))
            }
        }
        company.defaultTaxGroupID = id
        audit("Company", company.id, "defaultTax", String(localized: "Impuesto predeterminado cambiado"))
        try saveOrRollback()
    }

    /// Nombre del grupo o tasa con ese id («Austin, TX», «Texas»).
    public func taxCodeName(_ id: UUID?) throws -> String? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<TaxGroup>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.name ?? taxRate(id: id)?.name
    }

    /// Valores iniciales de una factura o estimado nuevo para el cliente: impuesto (el del cliente o el de la empresa;
    /// ninguno si está exento), vencimiento según sus condiciones, mensaje por defecto y precios con impuesto incluido.
    public func newInvoiceDefaults(for customer: Customer?, issueDate: Date = Date(), calendar: Calendar = .current) throws -> NewInvoiceDefaults {
        let company = try company()
        let terms = customer?.paymentTermsDays ?? company?.defaultPaymentTermsDays ?? 30
        let exempt = customer?.isTaxExempt ?? false
        return NewInvoiceDefaults(
            taxGroupID: exempt ? nil : (customer?.defaultTaxGroupID ?? company?.defaultTaxGroupID),
            dueDate: calendar.date(byAdding: .day, value: terms, to: issueDate) ?? issueDate,
            customerMessage: company?.defaultInvoiceMessage ?? "",
            pricesIncludeTax: company?.pricesIncludeTax ?? false
        )
    }
}

// MARK: - Logo de la empresa y W-9 del proveedor

extension Bookkeeper {

    /// Pone (o cambia) el logo de la empresa. Se reduce a 512 px y se guarda en PNG para conservar la transparencia.
    @discardableResult
    public func setCompanyLogo(_ data: Data, filename: String, contentType: UTType) throws -> Attachment {
        guard let company = try company() else { throw BookkeepingError.noCompany }
        let prepared = try AttachmentProcessing.prepareLogo(data, filename: filename, contentType: contentType)
        if let old = company.logo { context.delete(old) }
        let attachment = Attachment(filename: prepared.filename, contentType: prepared.contentType, data: prepared.data)
        context.insert(attachment)
        company.logo = attachment
        audit("Company", company.id, "logo", String(localized: "Logo cambiado"))
        try saveOrRollback()
        return attachment
    }

    public func removeCompanyLogo() throws {
        guard let company = try company(), let logo = company.logo else { return }
        company.logo = nil
        context.delete(logo)
        audit("Company", company.id, "logo", String(localized: "Logo quitado"))
        try saveOrRollback()
    }

    /// Marca el W-9 del proveedor como recibido (o no) con su fecha.
    public func setW9(for vendor: Vendor, received: Bool, on date: Date? = Date()) throws {
        vendor.w9Received = received
        vendor.w9ReceivedDate = received ? (date ?? Date()) : nil
        audit("Vendor", vendor.id, "w9", received ? String(localized: "W-9 recibido: \(vendor.name)") : String(localized: "W-9 pendiente: \(vendor.name)"))
        try saveOrRollback()
    }

    /// Adjunta la copia del W-9 (foto o PDF) y lo marca recibido.
    @discardableResult
    public func attachW9(_ data: Data, filename: String, contentType: UTType, to vendor: Vendor, receivedOn date: Date = Date()) throws -> Attachment {
        let prepared = try AttachmentProcessing.prepare(data, filename: filename, contentType: contentType)
        if let old = vendor.w9Attachment { context.delete(old) }
        let attachment = Attachment(filename: prepared.filename, contentType: prepared.contentType, data: prepared.data)
        context.insert(attachment)
        vendor.w9Attachment = attachment
        vendor.w9Received = true
        vendor.w9ReceivedDate = vendor.w9ReceivedDate ?? date
        audit("Vendor", vendor.id, "w9", String(localized: "W-9 adjunto: \(vendor.name)"))
        try saveOrRollback()
        return attachment
    }

    /// Pago preferido del proveedor (método y cuenta de origen); `nil` quita la preferencia.
    public func setPreferredPayment(for vendor: Vendor, method: PaymentMethod?, account: Account?) throws {
        vendor.preferredPaymentMethod = method
        vendor.preferredPaymentAccountID = account?.id
        try saveOrRollback()
    }
}
