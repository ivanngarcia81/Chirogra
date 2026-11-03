import ChirograCore
import Foundation
import SwiftData

/// Documento creado por una plantilla recurrente.
public enum GeneratedDocument {
    case expense(Expense)
    case bill(Bill)

    public var id: UUID {
        switch self {
        case .expense(let expense): expense.id
        case .bill(let bill): bill.id
        }
    }
}

/// Resultado de `Bookkeeper.generateRecurring(through:)`.
public struct RecurringRun {
    public var created: [GeneratedDocument] = []
    /// Plantillas que no pudieron generar su repetición (p. ej. periodo cerrado o cuenta archivada). No avanzan:
    /// se reintentan en la próxima ejecución.
    public var failures: [(template: RecurringTemplate, date: Date, error: Error)] = []
}

// MARK: - Recurrentes (canvas `MacGastoNuevo` «Repetición», `MacPorPagar` «Recurrente · cargo automático»)

extension Bookkeeper {

    public func recurringTemplates(includePaused: Bool = true) throws -> [RecurringTemplate] {
        try context.fetch(FetchDescriptor<RecurringTemplate>(sortBy: [SortDescriptor(\.nextDate)]))
            .filter { includePaused || $0.isActive }
    }

    /// Crea o edita una plantilla. Si cambia el inicio o la frecuencia, la próxima fecha se recalcula a partir de la
    /// última repetición generada, así que lo ya generado no se repite.
    @discardableResult
    public func saveRecurringTemplate(_ input: RecurringTemplateInput, into existing: RecurringTemplate? = nil,
                                      calendar: Calendar = .current) throws -> RecurringTemplate {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BookkeepingError.invalidState(String(localized: "La plantilla necesita un nombre.")) }
        guard !input.lines.isEmpty, input.lines.allSatisfy({ $0.amount > 0 && $0.accountID != nil }) else {
            throw BookkeepingError.invalidDocument(.nonPositiveAmount)
        }
        if input.kind == .expense || input.autoCharge {
            guard try account(id: input.paymentAccountID) != nil else { throw BookkeepingError.unknownAccount }
        }
        if input.kind == .bill, input.vendor == nil {
            throw BookkeepingError.invalidState(String(localized: "Una factura por pagar recurrente necesita proveedor."))
        }
        let start = calendar.startOfDay(for: input.startDate)
        if let end = input.endDate, calendar.startOfDay(for: end) < start {
            throw BookkeepingError.invalidState(String(localized: "La fecha final es anterior al inicio."))
        }

        let template = existing ?? RecurringTemplate(name: name, kind: input.kind, frequency: input.frequency, startDate: start)
        if existing == nil { context.insert(template) }
        let scheduleChanged = existing != nil && (template.startDate != start || template.frequency != input.frequency)
        template.name = name
        template.kind = input.kind
        template.vendor = input.vendor
        template.payee = input.payee
        template.memo = input.memo
        template.paymentAccountID = input.paymentAccountID
        template.method = input.method
        template.frequency = input.frequency
        template.startDate = start
        template.endDate = input.endDate.map { calendar.startOfDay(for: $0) }
        template.autoCharge = input.autoCharge
        template.isActive = input.isActive
        template.billTermsDays = max(0, input.billTermsDays)
        if existing == nil {
            template.nextDate = start
        } else if scheduleChanged {
            template.nextDate = template.lastGeneratedDate.map { template.occurrence(after: $0, calendar: calendar) } ?? start
        }
        for line in template.lines ?? [] { context.delete(line) }
        template.lines = []
        for (index, line) in input.lines.enumerated() {
            let model = RecurringTemplateLine(details: line.details, amount: line.amount, accountID: line.accountID, order: index)
            model.template = template
            context.insert(model)
        }
        audit("RecurringTemplate", template.id, existing == nil ? "create" : "update", String(localized: "Recurrente: \(name)"))
        try saveOrRollback()
        return template
    }

    /// Pausa o reanuda una plantilla. Al reanudar no se generan las repeticiones que pasaron en pausa: la próxima
    /// fecha salta a la primera de hoy en adelante.
    public func setRecurringTemplate(_ template: RecurringTemplate, active: Bool, asOf date: Date = Date(), calendar: Calendar = .current) throws {
        guard template.isActive != active else { return }
        template.isActive = active
        if active, calendar.startOfDay(for: template.nextDate) < calendar.startOfDay(for: date) {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            template.nextDate = template.occurrence(after: yesterday, calendar: calendar)
        }
        audit("RecurringTemplate", template.id, active ? "resume" : "pause", String(localized: "Recurrente: \(template.name)"))
        try saveOrRollback()
    }

    /// Borra la plantilla. Lo ya generado se queda (conserva `recurringTemplateID` como referencia).
    public func deleteRecurringTemplate(_ template: RecurringTemplate) throws {
        audit("RecurringTemplate", template.id, "delete", String(localized: "Recurrente borrada: \(template.name)"))
        context.delete(template)
        try saveOrRollback()
    }

    /// Genera las repeticiones pendientes de todas las plantillas activas hasta `date` (incluido).
    ///
    /// Idempotente: antes de crear una repetición busca un gasto o factura con el mismo `recurringTemplateID` y
    /// `recurrenceDate`; si ya existe (otra llamada, u otro aparato que sincronizó primero), solo avanza la fecha.
    /// Si dos aparatos sin conexión generan la misma repetición, `resolveRecurringDuplicates()` anula la copia.
    @discardableResult
    public func generateRecurring(through date: Date = Date(), calendar: Calendar = .current) throws -> RecurringRun {
        var run = RecurringRun()
        let limit = calendar.startOfDay(for: date)
        for template in try recurringTemplates(includePaused: false) {
            let existing = try generatedDates(of: template, calendar: calendar)
            while calendar.startOfDay(for: template.nextDate) <= limit, !template.isFinished {
                let occurrence = calendar.startOfDay(for: template.nextDate)
                do {
                    if !existing.contains(occurrence) {
                        run.created.append(try generate(template, on: occurrence, calendar: calendar))
                    }
                    template.lastGeneratedDate = occurrence
                    template.lastRunAt = Date()
                    template.nextDate = template.occurrence(after: occurrence, calendar: calendar)
                    try saveOrRollback()
                } catch {
                    context.rollback()
                    run.failures.append((template, occurrence, error))
                    break
                }
            }
        }
        return run
    }

    /// Fechas (inicio del día) de las repeticiones ya generadas por la plantilla.
    func generatedDates(of template: RecurringTemplate, calendar: Calendar) throws -> Set<Date> {
        let templateID: UUID? = template.id
        let expenses = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.recurringTemplateID == templateID }))
        let bills = try context.fetch(FetchDescriptor<Bill>(predicate: #Predicate { $0.recurringTemplateID == templateID }))
        let dates = expenses.filter { !$0.isVoid }.compactMap(\.recurrenceDate) + bills.filter { $0.status != .void }.compactMap(\.recurrenceDate)
        return Set(dates.map { calendar.startOfDay(for: $0) })
    }

    private func generate(_ template: RecurringTemplate, on date: Date, calendar: Calendar) throws -> GeneratedDocument {
        let payee = template.payee.isEmpty ? (template.vendor?.name ?? template.name) : template.payee
        switch template.kind {
        case .expense:
            let expense = Expense(date: date, payee: payee, paymentAccountID: template.paymentAccountID, vendor: template.vendor)
            expense.method = template.method
            expense.memo = template.memo.isEmpty ? template.name : template.memo
            expense.recurringTemplateID = template.id
            expense.recurrenceDate = date
            context.insert(expense)
            for line in template.sortedLines {
                let model = ExpenseLine(details: line.details.isEmpty ? payee : line.details, amount: line.amount, accountID: line.accountID, order: line.order)
                model.expense = expense
                context.insert(model)
            }
            expense.total = template.total
            if template.autoCharge {
                try record(expense, save: false)
            }
            audit("Expense", expense.id, "generate", String(localized: "Gasto recurrente generado: \(template.name)"))
            return .expense(expense)
        case .bill:
            let due = calendar.date(byAdding: .day, value: template.billTermsDays, to: date) ?? date
            let bill = Bill(vendor: template.vendor, vendorNumber: "", billDate: date, dueDate: due)
            bill.memo = template.memo.isEmpty ? template.name : template.memo
            bill.recurringTemplateID = template.id
            bill.recurrenceDate = date
            context.insert(bill)
            for line in template.sortedLines {
                let model = BillLine(details: line.details.isEmpty ? template.name : line.details, amount: line.amount, accountID: line.accountID, order: line.order)
                model.bill = bill
                context.insert(model)
            }
            try record(bill, save: false)
            if template.autoCharge {
                bill.scheduledPaymentDate = calendar.startOfDay(for: due)
                bill.scheduledPaymentAccountID = template.paymentAccountID
                bill.scheduledPaymentMethodRaw = template.method.rawValue
                bill.autoPay = true
            }
            audit("Bill", bill.id, "generate", String(localized: "Factura recurrente generada: \(template.name)"))
            return .bill(bill)
        }
    }

    /// Repara repeticiones duplicadas (dos aparatos sin conexión generaron la misma): conserva la más antigua y
    /// anula las demás (los gastos con asiento se revierten; las facturas sin pagos se anulan; las que ya tienen
    /// pagos se dejan y se informan). Devuelve cuántas anuló.
    @discardableResult
    public func resolveRecurringDuplicates(calendar: Calendar = .current) throws -> Int {
        var voided = 0
        let expenses = try context.fetch(FetchDescriptor<Expense>()).filter { $0.recurringTemplateID != nil && !$0.isVoid }
        for group in Dictionary(grouping: expenses, by: { RecurrenceKey($0.recurringTemplateID, $0.recurrenceDate, calendar) }).values where group.count > 1 {
            for duplicate in group.sorted(by: Self.olderFirst).dropFirst() {
                try void(duplicate, reason: String(localized: "Repetición duplicada"))
                voided += 1
            }
        }
        let bills = try context.fetch(FetchDescriptor<Bill>()).filter { $0.recurringTemplateID != nil && $0.status != .void }
        for group in Dictionary(grouping: bills, by: { RecurrenceKey($0.recurringTemplateID, $0.recurrenceDate, calendar) }).values where group.count > 1 {
            for duplicate in group.sorted(by: Self.olderFirst).dropFirst() where duplicate.amountPaid == 0 {
                try void(duplicate)
                voided += 1
            }
        }
        return voided
    }

    private static func olderFirst(_ a: Expense, _ b: Expense) -> Bool {
        (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
    }

    private static func olderFirst(_ a: Bill, _ b: Bill) -> Bool {
        (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
    }
}

private struct RecurrenceKey: Hashable {
    var templateID: UUID?
    var day: Date?

    init(_ templateID: UUID?, _ date: Date?, _ calendar: Calendar) {
        self.templateID = templateID
        self.day = date.map { calendar.startOfDay(for: $0) }
    }
}
