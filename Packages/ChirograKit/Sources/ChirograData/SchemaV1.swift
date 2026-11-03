import ChirograCore
import Foundation
import SwiftData

// Esquema 1.0.0, CONGELADO. Es la forma exacta con la que la app guardó los datos hasta el esquema 2
// (DISEÑO §6.4). SwiftData lo necesita para reconocer los almacenes viejos y migrarlos a `SchemaV2`.
//
// No cambiar nada aquí: ni nombres, ni tipos, ni valores por defecto, ni relaciones. Solo lleva las
// propiedades guardadas; la lógica (propiedades calculadas, inicializadores con datos) vive en `SchemaV2`,
// que es lo que usa la app a través de los `typealias` de `SchemaV2.swift`.

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Company.self, Account.self, JournalEntry.self, JournalLine.self,
            Customer.self, Vendor.self, Item.self,
            Invoice.self, InvoiceLine.self, InvoiceTaxLine.self, CreditNote.self, CreditApplication.self, PaymentReceived.self, PaymentApplication.self,
            Bill.self, BillLine.self, BillPayment.self, Expense.self, ExpenseLine.self, Attachment.self,
            TaxAgency.self, TaxRate.self, TaxGroup.self,
            NumberSequence.self, AuditEvent.self,
        ]
    }
}

extension SchemaV1 {

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

        public var parent: SchemaV1.Account?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.Account.parent)
        public var children: [SchemaV1.Account]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.JournalLine.account)
        public var lines: [SchemaV1.JournalLine]? = []

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

        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.JournalLine.entry)
        public var lines: [SchemaV1.JournalLine]? = []

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

        public var entry: SchemaV1.JournalEntry?
        public var account: SchemaV1.Account?

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

        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.Invoice.customer)
        public var invoices: [SchemaV1.Invoice]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.PaymentReceived.customer)
        public var payments: [SchemaV1.PaymentReceived]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.CreditNote.customer)
        public var creditNotes: [SchemaV1.CreditNote]? = []

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

        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.Bill.vendor)
        public var bills: [SchemaV1.Bill]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.Expense.vendor)
        public var expenses: [SchemaV1.Expense]? = []

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

        public var customer: SchemaV1.Customer?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.CreditNote.invoice)
        public var creditNotes: [SchemaV1.CreditNote]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.CreditApplication.invoice)
        public var creditApplications: [SchemaV1.CreditApplication]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.InvoiceLine.invoice)
        public var lines: [SchemaV1.InvoiceLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.InvoiceTaxLine.invoice)
        public var taxLines: [SchemaV1.InvoiceTaxLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.PaymentApplication.invoice)
        public var paymentApplications: [SchemaV1.PaymentApplication]? = []

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

        public var invoice: SchemaV1.Invoice?

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

        public var invoice: SchemaV1.Invoice?

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

        public var customer: SchemaV1.Customer?
        public var invoice: SchemaV1.Invoice?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.CreditApplication.note)
        public var applications: [SchemaV1.CreditApplication]? = []

        public init() {}
    }

    @Model
    public final class CreditApplication {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Int64 = 0

        public var note: SchemaV1.CreditNote?
        public var invoice: SchemaV1.Invoice?

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

        public var customer: SchemaV1.Customer?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.PaymentApplication.payment)
        public var applications: [SchemaV1.PaymentApplication]? = []

        public init() {}
    }

    @Model
    public final class PaymentApplication {
        public var id: UUID = UUID()
        public var amount: Int64 = 0

        public var payment: SchemaV1.PaymentReceived?
        public var invoice: SchemaV1.Invoice?

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

        public var vendor: SchemaV1.Vendor?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.BillLine.bill)
        public var lines: [SchemaV1.BillLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.BillPayment.bill)
        public var payments: [SchemaV1.BillPayment]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.Attachment.bill)
        public var attachments: [SchemaV1.Attachment]? = []

        public init() {}
    }

    @Model
    public final class BillLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0

        public var bill: SchemaV1.Bill?

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

        public var bill: SchemaV1.Bill?

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

        public var vendor: SchemaV1.Vendor?
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.ExpenseLine.expense)
        public var lines: [SchemaV1.ExpenseLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.Attachment.expense)
        public var attachments: [SchemaV1.Attachment]? = []

        public init() {}
    }

    @Model
    public final class ExpenseLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0

        public var expense: SchemaV1.Expense?

        public init() {}
    }

    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        public var filename: String = ""
        public var contentType: String = ""
        @Attribute(.externalStorage) public var data: Data?
        public var createdAt: Date = Date()

        public var expense: SchemaV1.Expense?
        public var bill: SchemaV1.Bill?

        public init() {}
    }

    @Model
    public final class TaxAgency {
        public var id: UUID = UUID()
        public var name: String = ""
        public var filingFrequencyRaw: String = FilingFrequency.quarterly.rawValue
        public var liabilityAccountID: UUID?
        public var isArchived: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.TaxRate.agency)
        public var rates: [SchemaV1.TaxRate]? = []

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

        public var agency: SchemaV1.TaxAgency?
        @Relationship(deleteRule: .nullify, inverse: \SchemaV1.TaxGroup.rates)
        public var groups: [SchemaV1.TaxGroup]? = []

        public init() {}
    }

    @Model
    public final class TaxGroup {
        public var id: UUID = UUID()
        public var name: String = ""
        public var isArchived: Bool = false

        public var rates: [SchemaV1.TaxRate]? = []

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
}
