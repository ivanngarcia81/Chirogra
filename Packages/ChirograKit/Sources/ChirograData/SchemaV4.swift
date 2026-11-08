import ChirograCore
import Foundation
import SwiftData

// Esquema 4.0.0 (7-nov-2026, fase 2 sin servidor; docs/DATOS-V4.md). Un solo esquema para todo lo de PLAN-FASE2:
// - **varias empresas**: `companyID` en todos los modelos salvo `Company` (también en los hijos, como las líneas, para
//   que cualquier `@Query` filtre igual y la copia por empresa sea un filtro), y en `Company` orden, archivo, código
//   postal y enlace de pago;
// - **banca**: `BankTransaction`, `BankRule`, `BankImportProfile`, `Reconciliation` y, en `JournalLine`,
//   `reconciliationID` y `clearedAt`;
// - **presupuestos**: `Budget` y `BudgetLine`;
// - **deducibles**: `Account.taxFormLineRaw`; **sales tax por código postal**: `Customer.postalCode`.
//
// Todo es aditivo (propiedades nuevas opcionales o con valor por defecto, modelos nuevos), así que CloudKit lo admite;
// la migración es a medida solo para **rellenar** `companyID` (`migrateV3toV4`). Como casi todos los modelos cambian,
// el esquema 4 tiene sus propias clases (`SchemaV4Models.swift`, `SchemaV4Models2.swift`, `SchemaV4Banking.swift`) y
// los esquemas 2 y 3 quedan congelados.

public enum SchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Company.self, Account.self, JournalEntry.self, JournalLine.self,
            Customer.self, Vendor.self, Item.self,
            Invoice.self, InvoiceLine.self, InvoiceTaxLine.self, CreditNote.self, CreditApplication.self, PaymentReceived.self, PaymentApplication.self,
            Bill.self, BillLine.self, BillPayment.self, Expense.self, ExpenseLine.self, Attachment.self,
            TaxAgency.self, TaxRate.self, TaxGroup.self,
            NumberSequence.self, AuditEvent.self,
            RecurringTemplate.self, RecurringTemplateLine.self, CustomerNote.self, InvoiceEvent.self,
            Estimate.self, EstimateLine.self, PeriodClose.self, NoticeState.self,
            // Nuevos en 4.0.0
            BankTransaction.self, BankRule.self, BankImportProfile.self, Reconciliation.self, Budget.self, BudgetLine.self,
        ]
    }
}

public enum ChirograMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self] }
    public static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3, migrateV3toV4] }

    /// Ligera: SwiftData/Core Data añade las columnas y tablas nuevas con sus valores por defecto.
    public static var migrateV1toV2: MigrationStage { .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) }

    // `migrateV2toV3` (a medida) está en `SchemaV3.swift`.

    /// A medida: los cambios son aditivos (Core Data los aplica solo) y después `didMigrate` da a todo la empresa que
    /// había (`CompanyOwnership.adoptOrphans`). Si los libros tenían varias empresas (dos aparatos que hicieron el alta
    /// y se mezclaron por iCloud), todo pasa a la más antigua y las demás, que no tienen nada propio, quedan archivadas.
    /// Es determinista (fecha de alta y después id), así que dos aparatos que migran a la vez escriben lo mismo.
    public static var migrateV3toV4: MigrationStage {
        .custom(fromVersion: SchemaV3.self, toVersion: SchemaV4.self, willMigrate: nil, didMigrate: { context in
            try CompanyOwnership.adoptOrphans(in: context, archivingExtraCompanies: true)
            try context.save()
        })
    }
}

public typealias Company = SchemaV4.Company
public typealias Account = SchemaV4.Account
public typealias JournalEntry = SchemaV4.JournalEntry
public typealias JournalLine = SchemaV4.JournalLine
public typealias Customer = SchemaV4.Customer
public typealias Vendor = SchemaV4.Vendor
public typealias Item = SchemaV4.Item
public typealias Invoice = SchemaV4.Invoice
public typealias InvoiceLine = SchemaV4.InvoiceLine
public typealias InvoiceTaxLine = SchemaV4.InvoiceTaxLine
public typealias CreditNote = SchemaV4.CreditNote
public typealias CreditApplication = SchemaV4.CreditApplication
public typealias PaymentReceived = SchemaV4.PaymentReceived
public typealias PaymentApplication = SchemaV4.PaymentApplication
public typealias Bill = SchemaV4.Bill
public typealias BillLine = SchemaV4.BillLine
public typealias BillPayment = SchemaV4.BillPayment
public typealias Expense = SchemaV4.Expense
public typealias ExpenseLine = SchemaV4.ExpenseLine
public typealias Attachment = SchemaV4.Attachment
public typealias TaxAgency = SchemaV4.TaxAgency
public typealias TaxRate = SchemaV4.TaxRate
public typealias TaxGroup = SchemaV4.TaxGroup
public typealias NumberSequence = SchemaV4.NumberSequence
public typealias AuditEvent = SchemaV4.AuditEvent
public typealias RecurringTemplate = SchemaV4.RecurringTemplate
public typealias RecurringTemplateLine = SchemaV4.RecurringTemplateLine
public typealias CustomerNote = SchemaV4.CustomerNote
public typealias InvoiceEvent = SchemaV4.InvoiceEvent
public typealias Estimate = SchemaV4.Estimate
public typealias EstimateLine = SchemaV4.EstimateLine
public typealias PeriodClose = SchemaV4.PeriodClose
public typealias NoticeState = SchemaV4.NoticeState
public typealias BankTransaction = SchemaV4.BankTransaction
public typealias BankRule = SchemaV4.BankRule
public typealias BankImportProfile = SchemaV4.BankImportProfile
public typealias Reconciliation = SchemaV4.Reconciliation
public typealias Budget = SchemaV4.Budget
public typealias BudgetLine = SchemaV4.BudgetLine

// MARK: - Empresa dueña

/// Modelo que pertenece a una empresa (`companyID`). Todos salvo `Company`.
public protocol CompanyOwned: PersistentModel {
    var id: UUID { get }
    var companyID: UUID? { get set }
    /// Los de la empresa `companyID` y, si `includeOrphans`, también los que no tienen empresa (son de la principal).
    static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Self>
}

extension CompanyOwnership {
    /// Todos los modelos con empresa, en el orden del esquema.
    public static let ownedTypes: [any CompanyOwned.Type] = [
        Account.self, JournalEntry.self, JournalLine.self, Customer.self, Vendor.self, Item.self,
        Invoice.self, InvoiceLine.self, InvoiceTaxLine.self, CreditNote.self, CreditApplication.self, PaymentReceived.self,
        PaymentApplication.self, Bill.self, BillLine.self, BillPayment.self, Expense.self, ExpenseLine.self,
        Attachment.self, TaxAgency.self, TaxRate.self, TaxGroup.self, NumberSequence.self, AuditEvent.self,
        RecurringTemplate.self, RecurringTemplateLine.self, CustomerNote.self, InvoiceEvent.self, Estimate.self, EstimateLine.self,
        PeriodClose.self, NoticeState.self, BankTransaction.self, BankRule.self, BankImportProfile.self, Reconciliation.self,
        Budget.self, BudgetLine.self,
    ]
}

extension SchemaV4.Account: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Account> {
        let id: UUID? = companyID
        return #Predicate<Account> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.JournalEntry: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<JournalEntry> {
        let id: UUID? = companyID
        return #Predicate<JournalEntry> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.JournalLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<JournalLine> {
        let id: UUID? = companyID
        return #Predicate<JournalLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Customer: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Customer> {
        let id: UUID? = companyID
        return #Predicate<Customer> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Vendor: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Vendor> {
        let id: UUID? = companyID
        return #Predicate<Vendor> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Item: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Item> {
        let id: UUID? = companyID
        return #Predicate<Item> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Invoice: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Invoice> {
        let id: UUID? = companyID
        return #Predicate<Invoice> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.InvoiceLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<InvoiceLine> {
        let id: UUID? = companyID
        return #Predicate<InvoiceLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.InvoiceTaxLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<InvoiceTaxLine> {
        let id: UUID? = companyID
        return #Predicate<InvoiceTaxLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.CreditNote: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<CreditNote> {
        let id: UUID? = companyID
        return #Predicate<CreditNote> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.CreditApplication: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<CreditApplication> {
        let id: UUID? = companyID
        return #Predicate<CreditApplication> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.PaymentReceived: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<PaymentReceived> {
        let id: UUID? = companyID
        return #Predicate<PaymentReceived> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.PaymentApplication: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<PaymentApplication> {
        let id: UUID? = companyID
        return #Predicate<PaymentApplication> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Bill: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Bill> {
        let id: UUID? = companyID
        return #Predicate<Bill> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BillLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BillLine> {
        let id: UUID? = companyID
        return #Predicate<BillLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BillPayment: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BillPayment> {
        let id: UUID? = companyID
        return #Predicate<BillPayment> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Expense: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Expense> {
        let id: UUID? = companyID
        return #Predicate<Expense> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.ExpenseLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<ExpenseLine> {
        let id: UUID? = companyID
        return #Predicate<ExpenseLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Attachment: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Attachment> {
        let id: UUID? = companyID
        return #Predicate<Attachment> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.TaxAgency: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<TaxAgency> {
        let id: UUID? = companyID
        return #Predicate<TaxAgency> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.TaxRate: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<TaxRate> {
        let id: UUID? = companyID
        return #Predicate<TaxRate> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.TaxGroup: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<TaxGroup> {
        let id: UUID? = companyID
        return #Predicate<TaxGroup> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.NumberSequence: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<NumberSequence> {
        let id: UUID? = companyID
        return #Predicate<NumberSequence> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.AuditEvent: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<AuditEvent> {
        let id: UUID? = companyID
        return #Predicate<AuditEvent> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.RecurringTemplate: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<RecurringTemplate> {
        let id: UUID? = companyID
        return #Predicate<RecurringTemplate> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.RecurringTemplateLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<RecurringTemplateLine> {
        let id: UUID? = companyID
        return #Predicate<RecurringTemplateLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.CustomerNote: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<CustomerNote> {
        let id: UUID? = companyID
        return #Predicate<CustomerNote> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.InvoiceEvent: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<InvoiceEvent> {
        let id: UUID? = companyID
        return #Predicate<InvoiceEvent> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Estimate: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Estimate> {
        let id: UUID? = companyID
        return #Predicate<Estimate> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.EstimateLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<EstimateLine> {
        let id: UUID? = companyID
        return #Predicate<EstimateLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.PeriodClose: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<PeriodClose> {
        let id: UUID? = companyID
        return #Predicate<PeriodClose> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.NoticeState: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<NoticeState> {
        let id: UUID? = companyID
        return #Predicate<NoticeState> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BankTransaction: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BankTransaction> {
        let id: UUID? = companyID
        return #Predicate<BankTransaction> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BankRule: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BankRule> {
        let id: UUID? = companyID
        return #Predicate<BankRule> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BankImportProfile: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BankImportProfile> {
        let id: UUID? = companyID
        return #Predicate<BankImportProfile> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Reconciliation: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Reconciliation> {
        let id: UUID? = companyID
        return #Predicate<Reconciliation> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.Budget: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Budget> {
        let id: UUID? = companyID
        return #Predicate<Budget> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
extension SchemaV4.BudgetLine: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<BudgetLine> {
        let id: UUID? = companyID
        return #Predicate<BudgetLine> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
