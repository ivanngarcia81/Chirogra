import ChirograCore
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Bitácora de cambios (1.2, docs/DATOS-V5.md)
//
// Cada cambio que hace `Bookkeeper` deja un `AuditEvent` en el mismo guardado: qué, a qué, un resumen, el detalle campo
// por campo (`AuditChanges`) y el aparato (`Bookkeeper.deviceName`, decisión del usuario del 10-nov: «quién» es el
// aparato en que se hizo). Lo que una pantalla cambia sin pasar por un servicio (clientes, proveedores, artículos…) lo
// anota con `logChange` antes de guardar. La bitácora no se edita ni se borra (salvo con la empresa entera).

/// El antes y el después de los campos de un cambio, una línea por campo («Correo: ana@x.com → ana@y.com»); o, al borrar
/// algo, lo que tenía («Total: $1,250.00»). Se guarda en `AuditEvent.changeDetails`.
public struct AuditChanges: Sendable, Equatable {
    public private(set) var lines: [String] = []

    public init() {}

    /// Anota el campo si cambió. Un valor vacío se escribe «—».
    public mutating func field(_ label: String, _ before: String, _ after: String) {
        let old = before.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = after.trimmingCharacters(in: .whitespacesAndNewlines)
        guard old != new else { return }
        lines.append("\(label): \(Self.shown(old)) → \(Self.shown(new))")
    }

    public mutating func money(_ label: String, _ before: Int64, _ after: Int64) {
        guard before != after else { return }
        field(label, Money(minorUnits: before).formatted(), Money(minorUnits: after).formatted())
    }

    public mutating func date(_ label: String, _ before: Date?, _ after: Date?, calendar: Calendar = .current) {
        switch (before, after) {
        case (nil, nil): return
        case let (old?, new?) where calendar.isDate(old, inSameDayAs: new): return
        default: field(label, Self.day(before), Self.day(after))
        }
    }

    public mutating func flag(_ label: String, _ before: Bool, _ after: Bool) {
        guard before != after else { return }
        field(label, Self.yesNo(before), Self.yesNo(after))
    }

    /// Un valor suelto (lo que tenía algo que se borró, el motivo de una exclusión…). Vacío no se anota.
    public mutating func value(_ label: String, _ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append("\(label): \(text)")
    }

    public mutating func value(_ label: String, money: Int64) { value(label, Money(minorUnits: money).formatted()) }

    /// Una línea tal cual.
    public mutating func note(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { lines.append(text) }
    }

    public var isEmpty: Bool { lines.isEmpty }
    public var text: String { lines.joined(separator: "\n") }

    static func shown(_ value: String) -> String { value.isEmpty ? "—" : value }
    static func day(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .omitted) ?? "" }
    static func yesNo(_ value: Bool) -> String { value ? String(localized: "Sí") : String(localized: "No") }
}

extension Bookkeeper {
    /// Nombre del aparato que se guarda en cada cambio («Mac de Iván», «iPhone»). En el iPhone y el iPad el sistema da
    /// solo el modelo («iPhone», «iPad») salvo con el permiso de Apple para el nombre que le puso el usuario. Las
    /// pruebas lo fijan con `deviceNameOverride`.
    public static var deviceName: String {
        if let deviceNameOverride { return deviceNameOverride }
        #if os(macOS)
        return Host.current().localizedName ?? ""
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return ""
        #endif
    }

    public static var deviceNameOverride: String?

    /// Anota un cambio en la bitácora (sin guardar: va en el guardado de quien llama).
    func audit(_ entity: String, _ id: UUID?, _ action: String, _ summary: String, changes: AuditChanges? = nil) {
        insert(AuditEvent(actor: actor, entityName: entity, entityID: id, action: action, summary: summary,
                          device: Self.deviceName, changeDetails: changes?.text ?? ""))
    }

    /// Para las pantallas que cambian algo sin pasar por un servicio (clientes, proveedores, artículos…): anota el
    /// cambio; lo guarda el `context.save()` de la pantalla. Una edición sin campos cambiados no se anota.
    public func logChange(_ entity: AuditSubject, id: UUID?, action: AuditAction, summary: String, changes: AuditChanges = AuditChanges()) {
        if action == .update && changes.isEmpty { return }
        audit(entity.rawValue, id, action.rawValue, summary, changes: changes)
    }

    /// La bitácora de la empresa, la más reciente primero. Con `entityID`, solo la de esa cosa (el historial de una
    /// factura, de un cliente…).
    public func auditLog(entityID: UUID? = nil, limit: Int? = nil) throws -> [AuditEvent] {
        var descriptor = FetchDescriptor<AuditEvent>(predicate: try scoped(entityID.map { id in
            let target: UUID? = id
            return #Predicate<AuditEvent> { $0.entityID == target }
        }), sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}

/// Las cosas que aparecen en la bitácora (`AuditEvent.subjectEntity`). Son los nombres de los modelos, así que los
/// eventos de antes de la 1.2 encajan.
public enum AuditSubject: String, CaseIterable, Sendable {
    case company = "Company"
    case account = "Account"
    case journalEntry = "JournalEntry"
    case customer = "Customer"
    case vendor = "Vendor"
    case item = "Item"
    case invoice = "Invoice"
    case estimate = "Estimate"
    case bill = "Bill"
    case billPayment = "BillPayment"
    case expense = "Expense"
    case attachment = "Attachment"
    case taxRate = "TaxRate"
    case taxGroup = "TaxGroup"
    case recurringTemplate = "RecurringTemplate"
    case bankTransaction = "BankTransaction"
    case bankRule = "BankRule"
    case reconciliation = "Reconciliation"
    case budget = "Budget"
    case backup = "Backup"
}

/// Acciones que las pantallas anotan con `logChange` (los servicios usan además las suyas: «post», «void»…).
public enum AuditAction: String, Sendable {
    case create
    case update
    case delete
    case archive
    case unarchive
}

extension AuditEvent {
    public var subject: AuditSubject? { AuditSubject(rawValue: subjectEntity) }
    /// Borrado de algo (también al quitar un recibo o una regla).
    public var isDeletion: Bool { action == AuditAction.delete.rawValue }
}

// MARK: - Antes y después

/// Los campos de algo, con su etiqueta, para comparar el antes y el después de una edición (`changes(to:)`) o anotar
/// lo que tenía algo que se crea o se borra (`values`).
public struct AuditSnapshot: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public var label: String
        public var value: String
    }

    public var fields: [Field]

    public init(_ fields: [(String, String)]) {
        self.fields = fields.map { Field(label: $0.0, value: $0.1) }
    }

    /// Los campos que cambiaron, en el orden de `self`.
    public func changes(to after: AuditSnapshot) -> AuditChanges {
        var changes = AuditChanges()
        let new = Dictionary(after.fields.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
        for field in fields { changes.field(field.label, field.value, new[field.label] ?? "") }
        return changes
    }

    /// Los campos con valor, uno por línea.
    public var values: AuditChanges {
        var changes = AuditChanges()
        for field in fields { changes.value(field.label, field.value) }
        return changes
    }

    static func money(_ amount: Int64) -> String { Money(minorUnits: amount).formatted() }
    static func days(_ days: Int) -> String { String(localized: "\(days) días") }
}

@MainActor
extension AuditSnapshot {
    public init(_ customer: Customer) {
        self.init([
            (String(localized: "Nombre"), customer.name), (String(localized: "Contacto"), customer.contactName),
            (String(localized: "Cargo"), customer.contactTitle), (String(localized: "Correo"), customer.email),
            (String(localized: "Teléfono"), customer.phone), (String(localized: "Dirección"), customer.billingAddress),
            (String(localized: "Código postal"), customer.postalCode), (String(localized: "Identificación fiscal"), customer.taxID),
            (String(localized: "Plazo de pago"), Self.days(customer.paymentTermsDays)),
            (String(localized: "Exento de sales tax"), AuditChanges.yesNo(customer.isTaxExempt)),
            (String(localized: "Motivo de la exención"), customer.exemptionReason),
            (String(localized: "Archivado"), AuditChanges.yesNo(customer.isArchived)),
        ])
    }

    public init(_ vendor: Vendor) {
        self.init([
            (String(localized: "Nombre"), vendor.name), (String(localized: "Empresa"), vendor.companyName),
            (String(localized: "Correo"), vendor.email), (String(localized: "Teléfono"), vendor.phone),
            (String(localized: "Dirección"), vendor.address), (String(localized: "Plazo de pago"), Self.days(vendor.paymentTermsDays)),
            (String(localized: "Notas"), vendor.notes), (String(localized: "Archivado"), AuditChanges.yesNo(vendor.isArchived)),
        ])
    }

    public init(_ item: Item) {
        self.init([
            (String(localized: "Nombre"), item.name), (String(localized: "Descripción"), item.details),
            (String(localized: "Precio"), Self.money(item.unitPrice)),
            (String(localized: "Lleva sales tax"), AuditChanges.yesNo(item.isTaxable)),
            (String(localized: "Archivado"), AuditChanges.yesNo(item.isArchived)),
        ])
    }

    /// Un gasto: los datos y una línea por categoría (con el nombre de la cuenta).
    init(_ input: ExpenseInput, accountName: (UUID?) -> String) {
        var fields: [(String, String)] = [
            (String(localized: "Fecha"), AuditChanges.day(input.date)), (String(localized: "Beneficiario"), input.payee),
            (String(localized: "Proveedor"), input.vendor?.name ?? ""), (String(localized: "Cliente"), input.customer?.name ?? ""),
            (String(localized: "Pagado con"), accountName(input.paymentAccountID)),
            (String(localized: "Referencia"), input.reference), (String(localized: "Nota"), input.memo),
            (String(localized: "Total"), Self.money(input.total)),
        ]
        for (index, line) in input.lines.enumerated() {
            fields.append((String(localized: "Línea \(index + 1)"),
                           "\(accountName(line.accountID)) · \(Self.money(line.amount))\(line.details.isEmpty ? "" : " · \(line.details)")"))
        }
        self.init(fields)
    }
}

extension Bookkeeper {
    /// Anota el alta (`before == nil`) o la edición de un cliente, proveedor o artículo guardado por una pantalla.
    public func logSave(_ subject: AuditSubject, id: UUID, name: String, before: AuditSnapshot?, after: AuditSnapshot) {
        switch (subject, before) {
        case (_, nil):
            logChange(subject, id: id, action: .create, summary: Self.createdTitle(subject, name), changes: after.values)
        case (_, let before?):
            logChange(subject, id: id, action: .update, summary: Self.editedTitle(subject, name), changes: before.changes(to: after))
        }
    }

    static func createdTitle(_ subject: AuditSubject, _ name: String) -> String {
        switch subject {
        case .customer: String(localized: "Cliente nuevo: \(name)")
        case .vendor: String(localized: "Proveedor nuevo: \(name)")
        case .item: String(localized: "Artículo nuevo: \(name)")
        default: String(localized: "Creado: \(name)")
        }
    }

    static func editedTitle(_ subject: AuditSubject, _ name: String) -> String {
        switch subject {
        case .customer: String(localized: "Cliente editado: \(name)")
        case .vendor: String(localized: "Proveedor editado: \(name)")
        case .item: String(localized: "Artículo editado: \(name)")
        default: String(localized: "Editado: \(name)")
        }
    }

    func accountName(_ id: UUID?) -> String {
        guard let id, let account = try? account(id: id) else { return "" }
        return account.displayName
    }

    /// Borra un borrador de factura (nunca emitido, sin asiento) dejando en la bitácora lo que tenía.
    public func deleteDraft(_ invoice: Invoice) throws {
        guard invoice.status == .draft, invoice.journalEntryID == nil else {
            throw BookkeepingError.invalidState(String(localized: "Solo se borran borradores; una factura emitida se anula."))
        }
        var changes = AuditChanges()
        changes.value(String(localized: "Cliente"), invoice.customer?.name ?? "")
        changes.value(String(localized: "Fecha"), AuditChanges.day(invoice.issueDate))
        changes.value(String(localized: "Total"), money: invoice.total)
        audit("Invoice", invoice.id, "delete", String(localized: "Borrador de factura borrado: \(invoice.number.isEmpty ? String(localized: "sin número") : invoice.number)"),
              changes: changes)
        context.delete(invoice)
        try saveOrRollback()
    }

    /// Borra un estimado dejando en la bitácora lo que tenía.
    public func deleteEstimate(_ estimate: Estimate) throws {
        var changes = AuditChanges()
        changes.value(String(localized: "Cliente"), estimate.customer?.name ?? "")
        changes.value(String(localized: "Título"), estimate.title)
        changes.value(String(localized: "Fecha"), AuditChanges.day(estimate.issueDate))
        changes.value(String(localized: "Total"), money: estimate.total)
        audit("Estimate", estimate.id, "delete", String(localized: "Estimado borrado: \(estimate.number)"), changes: changes)
        context.delete(estimate)
        try saveOrRollback()
    }
}
