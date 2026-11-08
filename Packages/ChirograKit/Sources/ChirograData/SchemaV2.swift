import ChirograCore
import Foundation
import SwiftData

// Esquema 2.0.0, CONGELADO (esquema 4, 7-nov-2026). Es la forma exacta con la que la app guardó los datos con el
// esquema 2 (versión 1.0, build 11) y, salvo `AuditEvent`, con el 3 (1.0.1, build 15): SwiftData lo necesita para
// reconocer esos almacenes y migrarlos (`ChirograMigrationPlan`).
//
// No cambiar nada aquí: ni nombres, ni tipos, ni relaciones, ni `@Attribute`. Solo lleva las propiedades guardadas; la
// lógica vive en los modelos de `SchemaV4`, que es lo que usa la app por los `typealias` de `SchemaV4.swift`.
// `FrozenSchemaTests` comprueba que los hashes de las entidades siguen siendo los publicados.

public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Company.self, Account.self, JournalEntry.self, JournalLine.self,
            Customer.self, Vendor.self, Item.self,
            Invoice.self, InvoiceLine.self, InvoiceTaxLine.self, CreditNote.self, CreditApplication.self, PaymentReceived.self, PaymentApplication.self,
            Bill.self, BillLine.self, BillPayment.self, Expense.self, ExpenseLine.self, Attachment.self,
            TaxAgency.self, TaxRate.self, TaxGroup.self,
            NumberSequence.self, AuditEvent.self,
            // Nuevos en 2.0.0
            RecurringTemplate.self, RecurringTemplateLine.self, CustomerNote.self, InvoiceEvent.self,
            Estimate.self, EstimateLine.self, PeriodClose.self, NoticeState.self,
        ]
    }
}

extension SchemaV2 {

    @Model
    public final class Company {
        public var id: UUID = UUID()
        public var legalName: String = ""
        public var displayName: String = ""
        public var ein: String = ""
        public var entityTypeRaw: String = EntityType.soleProprietorship.rawValue
        public var state: String = ""
        public var sectorRaw: String = BusinessSector.services.rawValue
        public var address: String = ""
        public var email: String = ""
        public var phone: String = ""
        public var currencyCode: String = "USD"
        public var fiscalYearStartMonth: Int = 1
        public var lockDate: Date?
        public var createdAt: Date = Date()
        public var website: String = ""
        public var defaultPaymentTermsDays: Int = 30
        public var defaultTaxGroupID: UUID?
        public var pricesIncludeTax: Bool = false
        public var salesTaxSourcingRaw: String = SalesTaxSourcing.origin.rawValue
        public var invoiceAccentHex: String = InvoiceAccent.ink.hex
        public var invoiceStyleRaw: String = InvoiceStyle.classic.rawValue
        public var invoiceShowLogo: Bool = true
        public var invoiceShowEIN: Bool = false
        public var invoiceShowAddress: Bool = true
        public var invoiceShowPhone: Bool = true
        public var defaultInvoiceMessage: String = ""
        public var invoiceFooter: String = ""
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.Attachment.logoOfCompany)
        public var logo: SchemaV2.Attachment?
        public var closingPasswordHash: String = ""

        public init() {}
    }

    @Model
    public final class Account {
        public var id: UUID = UUID()
        public var code: String = ""
        public var name: String = ""
        public var subtypeRaw: String = AccountSubtype.otherAsset.rawValue
        public var details: String = ""
        public var isSystem: Bool = false
        public var isArchived: Bool = false
        public var createdAt: Date = Date()
        public var last4: String = ""
        public var parent: SchemaV2.Account?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Account.parent)
        public var children: [SchemaV2.Account]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.JournalLine.account)
        public var lines: [SchemaV2.JournalLine]? = []

        public init() {}
    }

    @Model
    public final class JournalEntry {
        public var id: UUID = UUID()
        public var number: Int = 0
        public var date: Date = Date()
        public var memo: String = ""
        public var statusRaw: String = EntryStatus.posted.rawValue
        public var sourceRaw: String = EntrySource.manual.rawValue
        public var sourceDocumentID: UUID?
        public var reversesEntryID: UUID?
        public var reversedByEntryID: UUID?
        public var createdAt: Date = Date()
        public var replacesEntryID: UUID?
        public var replacedByEntryID: UUID?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.JournalLine.entry)
        public var lines: [SchemaV2.JournalLine]? = []

        public init() {}
    }

    @Model
    public final class JournalLine {
        public var id: UUID = UUID()
        public var debit: Int64 = 0
        public var credit: Int64 = 0
        public var memo: String = ""
        public var order: Int = 0
        public var customerID: UUID?
        public var vendorID: UUID?
        public var entry: SchemaV2.JournalEntry?
        public var account: SchemaV2.Account?

        public init() {}
    }

    @Model
    public final class Customer {
        public var id: UUID = UUID()
        public var name: String = ""
        public var companyName: String = ""
        public var email: String = ""
        public var phone: String = ""
        public var billingAddress: String = ""
        public var shippingAddress: String = ""
        public var paymentTermsDays: Int = 30
        public var isTaxExempt: Bool = false
        public var exemptionReason: String = ""
        public var defaultTaxGroupID: UUID?
        public var notes: String = ""
        public var isArchived: Bool = false
        public var createdAt: Date = Date()
        public var contactName: String = ""
        public var contactTitle: String = ""
        public var taxID: String = ""
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Invoice.customer)
        public var invoices: [SchemaV2.Invoice]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.PaymentReceived.customer)
        public var payments: [SchemaV2.PaymentReceived]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.CreditNote.customer)
        public var creditNotes: [SchemaV2.CreditNote]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.CustomerNote.customer)
        public var datedNotes: [SchemaV2.CustomerNote]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Estimate.customer)
        public var estimates: [SchemaV2.Estimate]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Expense.customer)
        public var billableExpenses: [SchemaV2.Expense]? = []

        public init() {}
    }

    @Model
    public final class Vendor {
        public var id: UUID = UUID()
        public var name: String = ""
        public var companyName: String = ""
        public var email: String = ""
        public var phone: String = ""
        public var address: String = ""
        public var paymentTermsDays: Int = 30
        public var defaultExpenseAccountID: UUID?
        public var is1099: Bool = false
        public var tinLast4: String = ""
        public var notes: String = ""
        public var isArchived: Bool = false
        public var createdAt: Date = Date()
        public var w9Received: Bool = false
        public var w9ReceivedDate: Date?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.Attachment.w9OfVendor)
        public var w9Attachment: SchemaV2.Attachment?
        public var preferredPaymentMethodRaw: String = ""
        public var preferredPaymentAccountID: UUID?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Bill.vendor)
        public var bills: [SchemaV2.Bill]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Expense.vendor)
        public var expenses: [SchemaV2.Expense]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.RecurringTemplate.vendor)
        public var recurringTemplates: [SchemaV2.RecurringTemplate]? = []

        public init() {}
    }

    @Model
    public final class Item {
        public var id: UUID = UUID()
        public var name: String = ""
        public var details: String = ""
        public var unitPrice: Int64 = 0
        public var isTaxable: Bool = true
        public var incomeAccountID: UUID?
        public var isArchived: Bool = false

        public init() {}
    }

    @Model
    public final class Invoice {
        public var id: UUID = UUID()
        public var number: String = ""
        public var issueDate: Date = Date()
        public var dueDate: Date = Date()
        public var statusRaw: String = InvoiceStatus.draft.rawValue
        public var memo: String = ""
        public var customerMessage: String = ""
        public var shippingAddress: String = ""
        public var taxGroupID: UUID?
        public var journalEntryID: UUID?
        public var subtotal: Int64 = 0
        public var discount: Int64 = 0
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var amountPaid: Int64 = 0
        public var creditsApplied: Int64 = 0
        public var createdAt: Date = Date()
        public var pricesIncludeTax: Bool = false
        public var estimateID: UUID?
        public var customer: SchemaV2.Customer?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.CreditNote.invoice)
        public var creditNotes: [SchemaV2.CreditNote]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.CreditApplication.invoice)
        public var creditApplications: [SchemaV2.CreditApplication]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.InvoiceLine.invoice)
        public var lines: [SchemaV2.InvoiceLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.InvoiceTaxLine.invoice)
        public var taxLines: [SchemaV2.InvoiceTaxLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.PaymentApplication.invoice)
        public var paymentApplications: [SchemaV2.PaymentApplication]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.InvoiceEvent.invoice)
        public var events: [SchemaV2.InvoiceEvent]? = []

        public init() {}
    }

    @Model
    public final class InvoiceLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var quantity: Decimal = 1
        public var unitPrice: Int64 = 0
        public var isTaxable: Bool = true
        public var incomeAccountID: UUID?
        public var itemID: UUID?
        public var order: Int = 0
        public var invoice: SchemaV2.Invoice?

        public init() {}
    }

    @Model
    public final class InvoiceTaxLine {
        public var id: UUID = UUID()
        public var taxRateID: UUID?
        public var name: String = ""
        public var rateMillionths: Int64 = 0
        public var taxableBase: Int64 = 0
        public var amount: Int64 = 0
        public var invoice: SchemaV2.Invoice?

        public init() {}
    }

    @Model
    public final class CreditNote {
        public var id: UUID = UUID()
        public var number: String = ""
        public var date: Date = Date()
        public var reason: String = ""
        public var amount: Int64 = 0
        public var isTaxable: Bool = true
        public var incomeAccountID: UUID?
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var unappliedAmount: Int64 = 0
        public var refundedAmount: Int64 = 0
        public var journalEntryID: UUID?
        public var createdAt: Date = Date()
        public var customer: SchemaV2.Customer?
        public var invoice: SchemaV2.Invoice?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.CreditApplication.note)
        public var applications: [SchemaV2.CreditApplication]? = []

        public init() {}
    }

    @Model
    public final class CreditApplication {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Int64 = 0
        public var note: SchemaV2.CreditNote?
        public var invoice: SchemaV2.Invoice?

        public init() {}
    }

    @Model
    public final class PaymentReceived {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Int64 = 0
        public var methodRaw: String = PaymentMethod.bankTransfer.rawValue
        public var reference: String = ""
        public var depositAccountID: UUID?
        public var journalEntryID: UUID?
        public var customer: SchemaV2.Customer?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.PaymentApplication.payment)
        public var applications: [SchemaV2.PaymentApplication]? = []

        public init() {}
    }

    @Model
    public final class PaymentApplication {
        public var id: UUID = UUID()
        public var amount: Int64 = 0
        public var payment: SchemaV2.PaymentReceived?
        public var invoice: SchemaV2.Invoice?

        public init() {}
    }

    @Model
    public final class Bill {
        public var id: UUID = UUID()
        public var vendorNumber: String = ""
        public var billDate: Date = Date()
        public var dueDate: Date = Date()
        public var statusRaw: String = BillStatus.open.rawValue
        public var memo: String = ""
        public var payableAccountID: UUID?
        public var journalEntryID: UUID?
        public var total: Int64 = 0
        public var amountPaid: Int64 = 0
        public var createdAt: Date = Date()
        public var scheduledPaymentDate: Date?
        public var scheduledPaymentAccountID: UUID?
        public var scheduledPaymentMethodRaw: String = ""
        public var autoPay: Bool = false
        public var recurringTemplateID: UUID?
        public var recurrenceDate: Date?
        public var vendor: SchemaV2.Vendor?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.BillLine.bill)
        public var lines: [SchemaV2.BillLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.BillPayment.bill)
        public var payments: [SchemaV2.BillPayment]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.Attachment.bill)
        public var attachments: [SchemaV2.Attachment]? = []

        public init() {}
    }

    @Model
    public final class BillLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0
        public var bill: SchemaV2.Bill?

        public init() {}
    }

    @Model
    public final class BillPayment {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Int64 = 0
        public var methodRaw: String = PaymentMethod.bankTransfer.rawValue
        public var reference: String = ""
        public var paymentAccountID: UUID?
        public var journalEntryID: UUID?
        public var bill: SchemaV2.Bill?

        public init() {}
    }

    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var payee: String = ""
        public var methodRaw: String = PaymentMethod.card.rawValue
        public var reference: String = ""
        public var memo: String = ""
        public var paymentAccountID: UUID?
        public var journalEntryID: UUID?
        public var total: Int64 = 0
        public var createdAt: Date = Date()
        public var salesTaxIncluded: Int64 = 0
        public var customer: SchemaV2.Customer?
        public var recurringTemplateID: UUID?
        public var recurrenceDate: Date?
        public var revision: Int = 0
        public var voidedAt: Date?
        public var vendor: SchemaV2.Vendor?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.ExpenseLine.expense)
        public var lines: [SchemaV2.ExpenseLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.Attachment.expense)
        public var attachments: [SchemaV2.Attachment]? = []

        public init() {}
    }

    @Model
    public final class ExpenseLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0
        public var expense: SchemaV2.Expense?

        public init() {}
    }

    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        public var filename: String = ""
        public var contentType: String = ""
        @Attribute(.externalStorage) public var data: Data?
        public var createdAt: Date = Date()
        public var expense: SchemaV2.Expense?
        public var bill: SchemaV2.Bill?
        public var w9OfVendor: SchemaV2.Vendor?
        public var logoOfCompany: SchemaV2.Company?

        public init() {}
    }

    @Model
    public final class TaxAgency {
        public var id: UUID = UUID()
        public var name: String = ""
        public var filingFrequencyRaw: String = FilingFrequency.quarterly.rawValue
        public var liabilityAccountID: UUID?
        public var isArchived: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.TaxRate.agency)
        public var rates: [SchemaV2.TaxRate]? = []

        public init() {}
    }

    @Model
    public final class TaxRate {
        public var id: UUID = UUID()
        public var name: String = ""
        public var rateMillionths: Int64 = 0
        public var effectiveFrom: Date?
        public var effectiveTo: Date?
        public var isArchived: Bool = false
        public var agency: SchemaV2.TaxAgency?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.TaxGroup.rates)
        public var groups: [SchemaV2.TaxGroup]? = []

        public init() {}
    }

    @Model
    public final class TaxGroup {
        public var id: UUID = UUID()
        public var name: String = ""
        public var isArchived: Bool = false
        public var rates: [SchemaV2.TaxRate]? = []

        public init() {}
    }

    @Model
    public final class NumberSequence {
        public var id: UUID = UUID()
        public var kindRaw: String = DocumentKind.invoice.rawValue
        public var prefix: String = ""
        public var nextNumber: Int = 1
        public var minimumDigits: Int = 4

        public init() {}
    }

    @Model
    public final class AuditEvent {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var actor: String = ""
        public var entityName: String = ""
        public var entityID: UUID?
        public var action: String = ""
        public var summary: String = ""

        public init() {}
    }

    @Model
    public final class RecurringTemplate {
        public var id: UUID = UUID()
        public var name: String = ""
        public var kindRaw: String = RecurringKind.expense.rawValue
        public var payee: String = ""
        public var memo: String = ""
        public var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
        public var startDate: Date = Date()
        public var nextDate: Date = Date()
        public var endDate: Date?
        public var isActive: Bool = true
        public var autoCharge: Bool = false
        public var paymentAccountID: UUID?
        public var methodRaw: String = PaymentMethod.card.rawValue
        public var billTermsDays: Int = 30
        public var lastGeneratedDate: Date?
        public var lastRunAt: Date?
        public var createdAt: Date = Date()
        public var vendor: SchemaV2.Vendor?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.RecurringTemplateLine.template)
        public var lines: [SchemaV2.RecurringTemplateLine]? = []

        public init() {}
    }

    @Model
    public final class RecurringTemplateLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0
        public var template: SchemaV2.RecurringTemplate?

        public init() {}
    }

    @Model
    public final class CustomerNote {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var text: String = ""
        public var author: String = ""
        public var createdAt: Date = Date()
        public var customer: SchemaV2.Customer?

        public init() {}
    }

    @Model
    public final class InvoiceEvent {
        public var id: UUID = UUID()
        public var kindRaw: String = InvoiceEventKind.sent.rawValue
        public var date: Date = Date()
        public var recipient: String = ""
        public var subject: String = ""
        public var message: String = ""
        public var createdAt: Date = Date()
        public var invoice: SchemaV2.Invoice?

        public init() {}
    }

    @Model
    public final class Estimate {
        public var id: UUID = UUID()
        public var number: String = ""
        public var title: String = ""
        public var issueDate: Date = Date()
        public var expirationDate: Date = Date()
        public var statusRaw: String = EstimateStatus.draft.rawValue
        public var customerMessage: String = ""
        public var memo: String = ""
        public var taxGroupID: UUID?
        public var discount: Int64 = 0
        public var discountInvoiced: Int64 = 0
        public var pricesIncludeTax: Bool = false
        public var subtotal: Int64 = 0
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var sentDate: Date?
        public var acceptedDate: Date?
        public var acceptedBy: String = ""
        public var convertedDate: Date?
        public var createdAt: Date = Date()
        public var customer: SchemaV2.Customer?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.EstimateLine.estimate)
        public var lines: [SchemaV2.EstimateLine]? = []

        public init() {}
    }

    @Model
    public final class EstimateLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var quantity: Decimal = 1
        public var unitPrice: Int64 = 0
        public var isTaxable: Bool = true
        public var incomeAccountID: UUID?
        public var itemID: UUID?
        public var order: Int = 0
        public var invoicedQuantity: Decimal = 0
        public var estimate: SchemaV2.Estimate?

        public init() {}
    }

    @Model
    public final class PeriodClose {
        public var id: UUID = UUID()
        public var actionRaw: String = "close"
        public var lockDate: Date?
        public var previousLockDate: Date?
        public var date: Date = Date()
        public var actor: String = ""
        public var device: String = ""
        public var note: String = ""

        public init() {}
    }

    @Model
    public final class NoticeState {
        public var id: UUID = UUID()
        public var key: String = ""
        public var isRead: Bool = false
        public var isDismissed: Bool = false
        public var updatedAt: Date = Date()

        public init() {}
    }
}
