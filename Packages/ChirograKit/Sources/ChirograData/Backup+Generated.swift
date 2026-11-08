// Generado por scripts/gen-backup.py a partir del esquema actual (SchemaV4). No editar a mano: cambia el modelo y vuelve a
// ejecutar el script (BackupTests comprueba que cubre todas las propiedades del esquema).

import ChirograCore
import Foundation
import SwiftData

// MARK: - Registros

extension BackupPayload {
    struct CompanyRecord: Codable {
        var id: UUID?
        var legalName: String?
        var displayName: String?
        var ein: String?
        var entityTypeRaw: String?
        var state: String?
        var sectorRaw: String?
        var address: String?
        var email: String?
        var phone: String?
        var currencyCode: String?
        var fiscalYearStartMonth: Int?
        var lockDate: Date?
        var createdAt: Date?
        var website: String?
        var defaultPaymentTermsDays: Int?
        var defaultTaxGroupID: UUID?
        var pricesIncludeTax: Bool?
        var salesTaxSourcingRaw: String?
        var invoiceAccentHex: String?
        var invoiceStyleRaw: String?
        var invoiceShowLogo: Bool?
        var invoiceShowEIN: Bool?
        var invoiceShowAddress: Bool?
        var invoiceShowPhone: Bool?
        var defaultInvoiceMessage: String?
        var invoiceFooter: String?
        var logo: UUID?
        var closingPasswordHash: String?
        var sortOrder: Int?
        var isArchived: Bool?
        var archivedAt: Date?
        var postalCode: String?
        var paymentLinkURL: String?
        var paymentInstructions: String?
        var showPayNowOnInvoice: Bool?
    }

    struct AccountRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var code: String?
        var name: String?
        var subtypeRaw: String?
        var details: String?
        var isSystem: Bool?
        var isArchived: Bool?
        var createdAt: Date?
        var last4: String?
        var taxFormLineRaw: String?
        var parent: UUID?
    }

    struct JournalEntryRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var number: Int?
        var date: Date?
        var memo: String?
        var statusRaw: String?
        var sourceRaw: String?
        var sourceDocumentID: UUID?
        var reversesEntryID: UUID?
        var reversedByEntryID: UUID?
        var createdAt: Date?
        var replacesEntryID: UUID?
        var replacedByEntryID: UUID?
    }

    struct JournalLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var debit: Int64?
        var credit: Int64?
        var memo: String?
        var order: Int?
        var customerID: UUID?
        var vendorID: UUID?
        var reconciliationID: UUID?
        var clearedAt: Date?
        var entry: UUID?
        var account: UUID?
    }

    struct CustomerRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var companyName: String?
        var email: String?
        var phone: String?
        var billingAddress: String?
        var shippingAddress: String?
        var paymentTermsDays: Int?
        var isTaxExempt: Bool?
        var exemptionReason: String?
        var defaultTaxGroupID: UUID?
        var notes: String?
        var isArchived: Bool?
        var createdAt: Date?
        var contactName: String?
        var contactTitle: String?
        var taxID: String?
        var postalCode: String?
    }

    struct VendorRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var companyName: String?
        var email: String?
        var phone: String?
        var address: String?
        var paymentTermsDays: Int?
        var defaultExpenseAccountID: UUID?
        var is1099: Bool?
        var tinLast4: String?
        var notes: String?
        var isArchived: Bool?
        var createdAt: Date?
        var w9Received: Bool?
        var w9ReceivedDate: Date?
        var w9Attachment: UUID?
        var preferredPaymentMethodRaw: String?
        var preferredPaymentAccountID: UUID?
    }

    struct ItemRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var details: String?
        var unitPrice: Int64?
        var isTaxable: Bool?
        var incomeAccountID: UUID?
        var isArchived: Bool?
    }

    struct InvoiceRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var number: String?
        var issueDate: Date?
        var dueDate: Date?
        var statusRaw: String?
        var memo: String?
        var customerMessage: String?
        var shippingAddress: String?
        var taxGroupID: UUID?
        var journalEntryID: UUID?
        var subtotal: Int64?
        var discount: Int64?
        var taxTotal: Int64?
        var total: Int64?
        var amountPaid: Int64?
        var creditsApplied: Int64?
        var createdAt: Date?
        var pricesIncludeTax: Bool?
        var estimateID: UUID?
        var customer: UUID?
    }

    struct InvoiceLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var details: String?
        var quantity: String?
        var unitPrice: Int64?
        var isTaxable: Bool?
        var incomeAccountID: UUID?
        var itemID: UUID?
        var order: Int?
        var invoice: UUID?
    }

    struct InvoiceTaxLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var taxRateID: UUID?
        var name: String?
        var rateMillionths: Int64?
        var taxableBase: Int64?
        var amount: Int64?
        var invoice: UUID?
    }

    struct CreditNoteRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var number: String?
        var date: Date?
        var reason: String?
        var amount: Int64?
        var isTaxable: Bool?
        var incomeAccountID: UUID?
        var taxTotal: Int64?
        var total: Int64?
        var unappliedAmount: Int64?
        var refundedAmount: Int64?
        var journalEntryID: UUID?
        var createdAt: Date?
        var customer: UUID?
        var invoice: UUID?
    }

    struct CreditApplicationRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var amount: Int64?
        var note: UUID?
        var invoice: UUID?
    }

    struct PaymentReceivedRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var amount: Int64?
        var methodRaw: String?
        var reference: String?
        var depositAccountID: UUID?
        var journalEntryID: UUID?
        var customer: UUID?
    }

    struct PaymentApplicationRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var amount: Int64?
        var payment: UUID?
        var invoice: UUID?
    }

    struct BillRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var vendorNumber: String?
        var billDate: Date?
        var dueDate: Date?
        var statusRaw: String?
        var memo: String?
        var payableAccountID: UUID?
        var journalEntryID: UUID?
        var total: Int64?
        var amountPaid: Int64?
        var createdAt: Date?
        var scheduledPaymentDate: Date?
        var scheduledPaymentAccountID: UUID?
        var scheduledPaymentMethodRaw: String?
        var autoPay: Bool?
        var recurringTemplateID: UUID?
        var recurrenceDate: Date?
        var vendor: UUID?
    }

    struct BillLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var details: String?
        var amount: Int64?
        var accountID: UUID?
        var order: Int?
        var bill: UUID?
    }

    struct BillPaymentRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var amount: Int64?
        var methodRaw: String?
        var reference: String?
        var paymentAccountID: UUID?
        var journalEntryID: UUID?
        var bill: UUID?
    }

    struct ExpenseRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var payee: String?
        var methodRaw: String?
        var reference: String?
        var memo: String?
        var paymentAccountID: UUID?
        var journalEntryID: UUID?
        var total: Int64?
        var createdAt: Date?
        var salesTaxIncluded: Int64?
        var customer: UUID?
        var recurringTemplateID: UUID?
        var recurrenceDate: Date?
        var revision: Int?
        var voidedAt: Date?
        var vendor: UUID?
    }

    struct ExpenseLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var details: String?
        var amount: Int64?
        var accountID: UUID?
        var order: Int?
        var expense: UUID?
    }

    struct AttachmentRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var filename: String?
        var contentType: String?
        var data: Data?
        var createdAt: Date?
        var expense: UUID?
        var bill: UUID?
        var w9OfVendor: UUID?
        var logoOfCompany: UUID?
    }

    struct TaxAgencyRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var filingFrequencyRaw: String?
        var liabilityAccountID: UUID?
        var isArchived: Bool?
    }

    struct TaxRateRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var rateMillionths: Int64?
        var effectiveFrom: Date?
        var effectiveTo: Date?
        var isArchived: Bool?
        var agency: UUID?
        var groups: [UUID]?
    }

    struct TaxGroupRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var isArchived: Bool?
    }

    struct NumberSequenceRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var kindRaw: String?
        var prefix: String?
        var nextNumber: Int?
        var minimumDigits: Int?
    }

    struct AuditEventRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var actor: String?
        var entityName: String?
        var entityID: UUID?
        var action: String?
        var summary: String?
    }

    struct RecurringTemplateRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var kindRaw: String?
        var payee: String?
        var memo: String?
        var frequencyRaw: String?
        var startDate: Date?
        var nextDate: Date?
        var endDate: Date?
        var isActive: Bool?
        var autoCharge: Bool?
        var paymentAccountID: UUID?
        var methodRaw: String?
        var billTermsDays: Int?
        var lastGeneratedDate: Date?
        var lastRunAt: Date?
        var createdAt: Date?
        var vendor: UUID?
    }

    struct RecurringTemplateLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var details: String?
        var amount: Int64?
        var accountID: UUID?
        var order: Int?
        var template: UUID?
    }

    struct CustomerNoteRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var date: Date?
        var text: String?
        var author: String?
        var createdAt: Date?
        var customer: UUID?
    }

    struct InvoiceEventRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var kindRaw: String?
        var date: Date?
        var recipient: String?
        var subject: String?
        var message: String?
        var createdAt: Date?
        var invoice: UUID?
    }

    struct EstimateRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var number: String?
        var title: String?
        var issueDate: Date?
        var expirationDate: Date?
        var statusRaw: String?
        var customerMessage: String?
        var memo: String?
        var taxGroupID: UUID?
        var discount: Int64?
        var discountInvoiced: Int64?
        var pricesIncludeTax: Bool?
        var subtotal: Int64?
        var taxTotal: Int64?
        var total: Int64?
        var sentDate: Date?
        var acceptedDate: Date?
        var acceptedBy: String?
        var convertedDate: Date?
        var createdAt: Date?
        var customer: UUID?
    }

    struct EstimateLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var details: String?
        var quantity: String?
        var unitPrice: Int64?
        var isTaxable: Bool?
        var incomeAccountID: UUID?
        var itemID: UUID?
        var order: Int?
        var invoicedQuantity: String?
        var estimate: UUID?
    }

    struct PeriodCloseRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var actionRaw: String?
        var lockDate: Date?
        var previousLockDate: Date?
        var date: Date?
        var actor: String?
        var device: String?
        var note: String?
    }

    struct NoticeStateRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var key: String?
        var isRead: Bool?
        var isDismissed: Bool?
        var updatedAt: Date?
    }

    struct BankTransactionRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var accountID: UUID?
        var date: Date?
        var amount: Int64?
        var details: String?
        var payee: String?
        var memo: String?
        var checkNumber: String?
        var externalID: String?
        var sourceRaw: String?
        var statusRaw: String?
        var categoryAccountID: UUID?
        var vendorID: UUID?
        var customerID: UUID?
        var ruleID: UUID?
        var matchedEntryID: UUID?
        var matchedLineID: UUID?
        var createdDocumentID: UUID?
        var importBatchID: UUID?
        var importedAt: Date?
        var reviewedAt: Date?
    }

    struct BankRuleRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var matchText: String?
        var amountSignRaw: String?
        var bankAccountID: UUID?
        var targetAccountID: UUID?
        var vendorID: UUID?
        var payee: String?
        var autoApply: Bool?
        var priority: Int?
        var isActive: Bool?
        var createdAt: Date?
    }

    struct BankImportProfileRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var accountID: UUID?
        var name: String?
        var columnsJSON: String?
        var dateFormat: String?
        var amountSignRaw: String?
        var delimiter: String?
        var hasHeaderRow: Bool?
        var createdAt: Date?
        var lastUsedAt: Date?
    }

    struct ReconciliationRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var accountID: UUID?
        var statementDate: Date?
        var statementEndingBalance: Int64?
        var beginningBalance: Int64?
        var statusRaw: String?
        var closedAt: Date?
        var createdAt: Date?
    }

    struct BudgetRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var name: String?
        var fiscalYear: Int?
        var createdAt: Date?
    }

    struct BudgetLineRecord: Codable {
        var id: UUID?
        var companyID: UUID?
        var accountID: UUID?
        var month: Int?
        var amount: Int64?
        var budget: UUID?
    }
}

struct BackupPayload: Codable {
    var company: [CompanyRecord]?
    var account: [AccountRecord]?
    var journalEntry: [JournalEntryRecord]?
    var journalLine: [JournalLineRecord]?
    var customer: [CustomerRecord]?
    var vendor: [VendorRecord]?
    var item: [ItemRecord]?
    var invoice: [InvoiceRecord]?
    var invoiceLine: [InvoiceLineRecord]?
    var invoiceTaxLine: [InvoiceTaxLineRecord]?
    var creditNote: [CreditNoteRecord]?
    var creditApplication: [CreditApplicationRecord]?
    var paymentReceived: [PaymentReceivedRecord]?
    var paymentApplication: [PaymentApplicationRecord]?
    var bill: [BillRecord]?
    var billLine: [BillLineRecord]?
    var billPayment: [BillPaymentRecord]?
    var expense: [ExpenseRecord]?
    var expenseLine: [ExpenseLineRecord]?
    var attachment: [AttachmentRecord]?
    var taxAgency: [TaxAgencyRecord]?
    var taxRate: [TaxRateRecord]?
    var taxGroup: [TaxGroupRecord]?
    var numberSequence: [NumberSequenceRecord]?
    var auditEvent: [AuditEventRecord]?
    var recurringTemplate: [RecurringTemplateRecord]?
    var recurringTemplateLine: [RecurringTemplateLineRecord]?
    var customerNote: [CustomerNoteRecord]?
    var invoiceEvent: [InvoiceEventRecord]?
    var estimate: [EstimateRecord]?
    var estimateLine: [EstimateLineRecord]?
    var periodClose: [PeriodCloseRecord]?
    var noticeState: [NoticeStateRecord]?
    var bankTransaction: [BankTransactionRecord]?
    var bankRule: [BankRuleRecord]?
    var bankImportProfile: [BankImportProfileRecord]?
    var reconciliation: [ReconciliationRecord]?
    var budget: [BudgetRecord]?
    var budgetLine: [BudgetLineRecord]?
}

// MARK: - Propiedades cubiertas (para BackupTests)

extension BackupArchive {
    /// Por entidad, las propiedades del esquema que la copia guarda o rehace por su inversa.
    static let coveredProperties: [String: Set<String>] = [
        "Company": ["id", "legalName", "displayName", "ein", "entityTypeRaw", "state", "sectorRaw", "address", "email", "phone", "currencyCode", "fiscalYearStartMonth", "lockDate", "createdAt", "website", "defaultPaymentTermsDays", "defaultTaxGroupID", "pricesIncludeTax", "salesTaxSourcingRaw", "invoiceAccentHex", "invoiceStyleRaw", "invoiceShowLogo", "invoiceShowEIN", "invoiceShowAddress", "invoiceShowPhone", "defaultInvoiceMessage", "invoiceFooter", "logo", "closingPasswordHash", "sortOrder", "isArchived", "archivedAt", "postalCode", "paymentLinkURL", "paymentInstructions", "showPayNowOnInvoice"],
        "Account": ["id", "companyID", "code", "name", "subtypeRaw", "details", "isSystem", "isArchived", "createdAt", "last4", "taxFormLineRaw", "parent", "children", "lines"],
        "JournalEntry": ["id", "companyID", "number", "date", "memo", "statusRaw", "sourceRaw", "sourceDocumentID", "reversesEntryID", "reversedByEntryID", "createdAt", "replacesEntryID", "replacedByEntryID", "lines"],
        "JournalLine": ["id", "companyID", "debit", "credit", "memo", "order", "customerID", "vendorID", "reconciliationID", "clearedAt", "entry", "account"],
        "Customer": ["id", "companyID", "name", "companyName", "email", "phone", "billingAddress", "shippingAddress", "paymentTermsDays", "isTaxExempt", "exemptionReason", "defaultTaxGroupID", "notes", "isArchived", "createdAt", "contactName", "contactTitle", "taxID", "postalCode", "invoices", "payments", "creditNotes", "datedNotes", "estimates", "billableExpenses"],
        "Vendor": ["id", "companyID", "name", "companyName", "email", "phone", "address", "paymentTermsDays", "defaultExpenseAccountID", "is1099", "tinLast4", "notes", "isArchived", "createdAt", "w9Received", "w9ReceivedDate", "w9Attachment", "preferredPaymentMethodRaw", "preferredPaymentAccountID", "bills", "expenses", "recurringTemplates"],
        "Item": ["id", "companyID", "name", "details", "unitPrice", "isTaxable", "incomeAccountID", "isArchived"],
        "Invoice": ["id", "companyID", "number", "issueDate", "dueDate", "statusRaw", "memo", "customerMessage", "shippingAddress", "taxGroupID", "journalEntryID", "subtotal", "discount", "taxTotal", "total", "amountPaid", "creditsApplied", "createdAt", "pricesIncludeTax", "estimateID", "customer", "creditNotes", "creditApplications", "lines", "taxLines", "paymentApplications", "events"],
        "InvoiceLine": ["id", "companyID", "details", "quantity", "unitPrice", "isTaxable", "incomeAccountID", "itemID", "order", "invoice"],
        "InvoiceTaxLine": ["id", "companyID", "taxRateID", "name", "rateMillionths", "taxableBase", "amount", "invoice"],
        "CreditNote": ["id", "companyID", "number", "date", "reason", "amount", "isTaxable", "incomeAccountID", "taxTotal", "total", "unappliedAmount", "refundedAmount", "journalEntryID", "createdAt", "customer", "invoice", "applications"],
        "CreditApplication": ["id", "companyID", "date", "amount", "note", "invoice"],
        "PaymentReceived": ["id", "companyID", "date", "amount", "methodRaw", "reference", "depositAccountID", "journalEntryID", "customer", "applications"],
        "PaymentApplication": ["id", "companyID", "amount", "payment", "invoice"],
        "Bill": ["id", "companyID", "vendorNumber", "billDate", "dueDate", "statusRaw", "memo", "payableAccountID", "journalEntryID", "total", "amountPaid", "createdAt", "scheduledPaymentDate", "scheduledPaymentAccountID", "scheduledPaymentMethodRaw", "autoPay", "recurringTemplateID", "recurrenceDate", "vendor", "lines", "payments", "attachments"],
        "BillLine": ["id", "companyID", "details", "amount", "accountID", "order", "bill"],
        "BillPayment": ["id", "companyID", "date", "amount", "methodRaw", "reference", "paymentAccountID", "journalEntryID", "bill"],
        "Expense": ["id", "companyID", "date", "payee", "methodRaw", "reference", "memo", "paymentAccountID", "journalEntryID", "total", "createdAt", "salesTaxIncluded", "customer", "recurringTemplateID", "recurrenceDate", "revision", "voidedAt", "vendor", "lines", "attachments"],
        "ExpenseLine": ["id", "companyID", "details", "amount", "accountID", "order", "expense"],
        "Attachment": ["id", "companyID", "filename", "contentType", "data", "createdAt", "expense", "bill", "w9OfVendor", "logoOfCompany"],
        "TaxAgency": ["id", "companyID", "name", "filingFrequencyRaw", "liabilityAccountID", "isArchived", "rates"],
        "TaxRate": ["id", "companyID", "name", "rateMillionths", "effectiveFrom", "effectiveTo", "isArchived", "agency", "groups"],
        "TaxGroup": ["id", "companyID", "name", "isArchived", "rates"],
        "NumberSequence": ["id", "companyID", "kindRaw", "prefix", "nextNumber", "minimumDigits"],
        "AuditEvent": ["id", "companyID", "date", "actor", "subjectEntity", "entityID", "action", "summary"],
        "RecurringTemplate": ["id", "companyID", "name", "kindRaw", "payee", "memo", "frequencyRaw", "startDate", "nextDate", "endDate", "isActive", "autoCharge", "paymentAccountID", "methodRaw", "billTermsDays", "lastGeneratedDate", "lastRunAt", "createdAt", "vendor", "lines"],
        "RecurringTemplateLine": ["id", "companyID", "details", "amount", "accountID", "order", "template"],
        "CustomerNote": ["id", "companyID", "date", "text", "author", "createdAt", "customer"],
        "InvoiceEvent": ["id", "companyID", "kindRaw", "date", "recipient", "subject", "message", "createdAt", "invoice"],
        "Estimate": ["id", "companyID", "number", "title", "issueDate", "expirationDate", "statusRaw", "customerMessage", "memo", "taxGroupID", "discount", "discountInvoiced", "pricesIncludeTax", "subtotal", "taxTotal", "total", "sentDate", "acceptedDate", "acceptedBy", "convertedDate", "createdAt", "customer", "lines"],
        "EstimateLine": ["id", "companyID", "details", "quantity", "unitPrice", "isTaxable", "incomeAccountID", "itemID", "order", "invoicedQuantity", "estimate"],
        "PeriodClose": ["id", "companyID", "actionRaw", "lockDate", "previousLockDate", "date", "actor", "device", "note"],
        "NoticeState": ["id", "companyID", "key", "isRead", "isDismissed", "updatedAt"],
        "BankTransaction": ["id", "companyID", "accountID", "date", "amount", "details", "payee", "memo", "checkNumber", "externalID", "sourceRaw", "statusRaw", "categoryAccountID", "vendorID", "customerID", "ruleID", "matchedEntryID", "matchedLineID", "createdDocumentID", "importBatchID", "importedAt", "reviewedAt"],
        "BankRule": ["id", "companyID", "name", "matchText", "amountSignRaw", "bankAccountID", "targetAccountID", "vendorID", "payee", "autoApply", "priority", "isActive", "createdAt"],
        "BankImportProfile": ["id", "companyID", "accountID", "name", "columnsJSON", "dateFormat", "amountSignRaw", "delimiter", "hasHeaderRow", "createdAt", "lastUsedAt"],
        "Reconciliation": ["id", "companyID", "accountID", "statementDate", "statementEndingBalance", "beginningBalance", "statusRaw", "closedAt", "createdAt"],
        "Budget": ["id", "companyID", "name", "fiscalYear", "createdAt", "lines"],
        "BudgetLine": ["id", "companyID", "accountID", "month", "amount", "budget"],
    ]

    static let modelCount = 39
}

// MARK: - Exportar

extension BackupPayload {
    @MainActor
    /// Los registros de la empresa de `scope` (o de todo, sin empresa).
    init(context: ModelContext, scope: BackupScope) throws {
        company = try context.fetch(scope.companies()).map { model in
            CompanyRecord(
                id: model.id,
                legalName: model.legalName,
                displayName: model.displayName,
                ein: model.ein,
                entityTypeRaw: model.entityTypeRaw,
                state: model.state,
                sectorRaw: model.sectorRaw,
                address: model.address,
                email: model.email,
                phone: model.phone,
                currencyCode: model.currencyCode,
                fiscalYearStartMonth: model.fiscalYearStartMonth,
                lockDate: model.lockDate,
                createdAt: model.createdAt,
                website: model.website,
                defaultPaymentTermsDays: model.defaultPaymentTermsDays,
                defaultTaxGroupID: model.defaultTaxGroupID,
                pricesIncludeTax: model.pricesIncludeTax,
                salesTaxSourcingRaw: model.salesTaxSourcingRaw,
                invoiceAccentHex: model.invoiceAccentHex,
                invoiceStyleRaw: model.invoiceStyleRaw,
                invoiceShowLogo: model.invoiceShowLogo,
                invoiceShowEIN: model.invoiceShowEIN,
                invoiceShowAddress: model.invoiceShowAddress,
                invoiceShowPhone: model.invoiceShowPhone,
                defaultInvoiceMessage: model.defaultInvoiceMessage,
                invoiceFooter: model.invoiceFooter,
                logo: model.logo?.id,
                closingPasswordHash: model.closingPasswordHash,
                sortOrder: model.sortOrder,
                isArchived: model.isArchived,
                archivedAt: model.archivedAt,
                postalCode: model.postalCode,
                paymentLinkURL: model.paymentLinkURL,
                paymentInstructions: model.paymentInstructions,
                showPayNowOnInvoice: model.showPayNowOnInvoice
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        account = try context.fetch(scope.descriptor(Account.self)).map { model in
            AccountRecord(
                id: model.id,
                companyID: model.companyID,
                code: model.code,
                name: model.name,
                subtypeRaw: model.subtypeRaw,
                details: model.details,
                isSystem: model.isSystem,
                isArchived: model.isArchived,
                createdAt: model.createdAt,
                last4: model.last4,
                taxFormLineRaw: model.taxFormLineRaw,
                parent: model.parent?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        journalEntry = try context.fetch(scope.descriptor(JournalEntry.self)).map { model in
            JournalEntryRecord(
                id: model.id,
                companyID: model.companyID,
                number: model.number,
                date: model.date,
                memo: model.memo,
                statusRaw: model.statusRaw,
                sourceRaw: model.sourceRaw,
                sourceDocumentID: model.sourceDocumentID,
                reversesEntryID: model.reversesEntryID,
                reversedByEntryID: model.reversedByEntryID,
                createdAt: model.createdAt,
                replacesEntryID: model.replacesEntryID,
                replacedByEntryID: model.replacedByEntryID
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        journalLine = try context.fetch(scope.descriptor(JournalLine.self)).map { model in
            JournalLineRecord(
                id: model.id,
                companyID: model.companyID,
                debit: model.debit,
                credit: model.credit,
                memo: model.memo,
                order: model.order,
                customerID: model.customerID,
                vendorID: model.vendorID,
                reconciliationID: model.reconciliationID,
                clearedAt: model.clearedAt,
                entry: model.entry?.id,
                account: model.account?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        customer = try context.fetch(scope.descriptor(Customer.self)).map { model in
            CustomerRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                companyName: model.companyName,
                email: model.email,
                phone: model.phone,
                billingAddress: model.billingAddress,
                shippingAddress: model.shippingAddress,
                paymentTermsDays: model.paymentTermsDays,
                isTaxExempt: model.isTaxExempt,
                exemptionReason: model.exemptionReason,
                defaultTaxGroupID: model.defaultTaxGroupID,
                notes: model.notes,
                isArchived: model.isArchived,
                createdAt: model.createdAt,
                contactName: model.contactName,
                contactTitle: model.contactTitle,
                taxID: model.taxID,
                postalCode: model.postalCode
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        vendor = try context.fetch(scope.descriptor(Vendor.self)).map { model in
            VendorRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                companyName: model.companyName,
                email: model.email,
                phone: model.phone,
                address: model.address,
                paymentTermsDays: model.paymentTermsDays,
                defaultExpenseAccountID: model.defaultExpenseAccountID,
                is1099: model.is1099,
                tinLast4: model.tinLast4,
                notes: model.notes,
                isArchived: model.isArchived,
                createdAt: model.createdAt,
                w9Received: model.w9Received,
                w9ReceivedDate: model.w9ReceivedDate,
                w9Attachment: model.w9Attachment?.id,
                preferredPaymentMethodRaw: model.preferredPaymentMethodRaw,
                preferredPaymentAccountID: model.preferredPaymentAccountID
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        item = try context.fetch(scope.descriptor(Item.self)).map { model in
            ItemRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                details: model.details,
                unitPrice: model.unitPrice,
                isTaxable: model.isTaxable,
                incomeAccountID: model.incomeAccountID,
                isArchived: model.isArchived
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        invoice = try context.fetch(scope.descriptor(Invoice.self)).map { model in
            InvoiceRecord(
                id: model.id,
                companyID: model.companyID,
                number: model.number,
                issueDate: model.issueDate,
                dueDate: model.dueDate,
                statusRaw: model.statusRaw,
                memo: model.memo,
                customerMessage: model.customerMessage,
                shippingAddress: model.shippingAddress,
                taxGroupID: model.taxGroupID,
                journalEntryID: model.journalEntryID,
                subtotal: model.subtotal,
                discount: model.discount,
                taxTotal: model.taxTotal,
                total: model.total,
                amountPaid: model.amountPaid,
                creditsApplied: model.creditsApplied,
                createdAt: model.createdAt,
                pricesIncludeTax: model.pricesIncludeTax,
                estimateID: model.estimateID,
                customer: model.customer?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        invoiceLine = try context.fetch(scope.descriptor(InvoiceLine.self)).map { model in
            InvoiceLineRecord(
                id: model.id,
                companyID: model.companyID,
                details: model.details,
                quantity: model.quantity.backupString,
                unitPrice: model.unitPrice,
                isTaxable: model.isTaxable,
                incomeAccountID: model.incomeAccountID,
                itemID: model.itemID,
                order: model.order,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        invoiceTaxLine = try context.fetch(scope.descriptor(InvoiceTaxLine.self)).map { model in
            InvoiceTaxLineRecord(
                id: model.id,
                companyID: model.companyID,
                taxRateID: model.taxRateID,
                name: model.name,
                rateMillionths: model.rateMillionths,
                taxableBase: model.taxableBase,
                amount: model.amount,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        creditNote = try context.fetch(scope.descriptor(CreditNote.self)).map { model in
            CreditNoteRecord(
                id: model.id,
                companyID: model.companyID,
                number: model.number,
                date: model.date,
                reason: model.reason,
                amount: model.amount,
                isTaxable: model.isTaxable,
                incomeAccountID: model.incomeAccountID,
                taxTotal: model.taxTotal,
                total: model.total,
                unappliedAmount: model.unappliedAmount,
                refundedAmount: model.refundedAmount,
                journalEntryID: model.journalEntryID,
                createdAt: model.createdAt,
                customer: model.customer?.id,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        creditApplication = try context.fetch(scope.descriptor(CreditApplication.self)).map { model in
            CreditApplicationRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                amount: model.amount,
                note: model.note?.id,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        paymentReceived = try context.fetch(scope.descriptor(PaymentReceived.self)).map { model in
            PaymentReceivedRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                amount: model.amount,
                methodRaw: model.methodRaw,
                reference: model.reference,
                depositAccountID: model.depositAccountID,
                journalEntryID: model.journalEntryID,
                customer: model.customer?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        paymentApplication = try context.fetch(scope.descriptor(PaymentApplication.self)).map { model in
            PaymentApplicationRecord(
                id: model.id,
                companyID: model.companyID,
                amount: model.amount,
                payment: model.payment?.id,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        bill = try context.fetch(scope.descriptor(Bill.self)).map { model in
            BillRecord(
                id: model.id,
                companyID: model.companyID,
                vendorNumber: model.vendorNumber,
                billDate: model.billDate,
                dueDate: model.dueDate,
                statusRaw: model.statusRaw,
                memo: model.memo,
                payableAccountID: model.payableAccountID,
                journalEntryID: model.journalEntryID,
                total: model.total,
                amountPaid: model.amountPaid,
                createdAt: model.createdAt,
                scheduledPaymentDate: model.scheduledPaymentDate,
                scheduledPaymentAccountID: model.scheduledPaymentAccountID,
                scheduledPaymentMethodRaw: model.scheduledPaymentMethodRaw,
                autoPay: model.autoPay,
                recurringTemplateID: model.recurringTemplateID,
                recurrenceDate: model.recurrenceDate,
                vendor: model.vendor?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        billLine = try context.fetch(scope.descriptor(BillLine.self)).map { model in
            BillLineRecord(
                id: model.id,
                companyID: model.companyID,
                details: model.details,
                amount: model.amount,
                accountID: model.accountID,
                order: model.order,
                bill: model.bill?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        billPayment = try context.fetch(scope.descriptor(BillPayment.self)).map { model in
            BillPaymentRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                amount: model.amount,
                methodRaw: model.methodRaw,
                reference: model.reference,
                paymentAccountID: model.paymentAccountID,
                journalEntryID: model.journalEntryID,
                bill: model.bill?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        expense = try context.fetch(scope.descriptor(Expense.self)).map { model in
            ExpenseRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                payee: model.payee,
                methodRaw: model.methodRaw,
                reference: model.reference,
                memo: model.memo,
                paymentAccountID: model.paymentAccountID,
                journalEntryID: model.journalEntryID,
                total: model.total,
                createdAt: model.createdAt,
                salesTaxIncluded: model.salesTaxIncluded,
                customer: model.customer?.id,
                recurringTemplateID: model.recurringTemplateID,
                recurrenceDate: model.recurrenceDate,
                revision: model.revision,
                voidedAt: model.voidedAt,
                vendor: model.vendor?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        expenseLine = try context.fetch(scope.descriptor(ExpenseLine.self)).map { model in
            ExpenseLineRecord(
                id: model.id,
                companyID: model.companyID,
                details: model.details,
                amount: model.amount,
                accountID: model.accountID,
                order: model.order,
                expense: model.expense?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        attachment = try context.fetch(scope.descriptor(Attachment.self)).map { model in
            AttachmentRecord(
                id: model.id,
                companyID: model.companyID,
                filename: model.filename,
                contentType: model.contentType,
                data: model.data,
                createdAt: model.createdAt,
                expense: model.expense?.id,
                bill: model.bill?.id,
                w9OfVendor: model.w9OfVendor?.id,
                logoOfCompany: model.logoOfCompany?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        taxAgency = try context.fetch(scope.descriptor(TaxAgency.self)).map { model in
            TaxAgencyRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                filingFrequencyRaw: model.filingFrequencyRaw,
                liabilityAccountID: model.liabilityAccountID,
                isArchived: model.isArchived
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        taxRate = try context.fetch(scope.descriptor(TaxRate.self)).map { model in
            TaxRateRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                rateMillionths: model.rateMillionths,
                effectiveFrom: model.effectiveFrom,
                effectiveTo: model.effectiveTo,
                isArchived: model.isArchived,
                agency: model.agency?.id,
                groups: model.groups?.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        taxGroup = try context.fetch(scope.descriptor(TaxGroup.self)).map { model in
            TaxGroupRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                isArchived: model.isArchived
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        numberSequence = try context.fetch(scope.descriptor(NumberSequence.self)).map { model in
            NumberSequenceRecord(
                id: model.id,
                companyID: model.companyID,
                kindRaw: model.kindRaw,
                prefix: model.prefix,
                nextNumber: model.nextNumber,
                minimumDigits: model.minimumDigits
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        auditEvent = try context.fetch(scope.descriptor(AuditEvent.self)).map { model in
            AuditEventRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                actor: model.actor,
                entityName: model.subjectEntity,
                entityID: model.entityID,
                action: model.action,
                summary: model.summary
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        recurringTemplate = try context.fetch(scope.descriptor(RecurringTemplate.self)).map { model in
            RecurringTemplateRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                kindRaw: model.kindRaw,
                payee: model.payee,
                memo: model.memo,
                frequencyRaw: model.frequencyRaw,
                startDate: model.startDate,
                nextDate: model.nextDate,
                endDate: model.endDate,
                isActive: model.isActive,
                autoCharge: model.autoCharge,
                paymentAccountID: model.paymentAccountID,
                methodRaw: model.methodRaw,
                billTermsDays: model.billTermsDays,
                lastGeneratedDate: model.lastGeneratedDate,
                lastRunAt: model.lastRunAt,
                createdAt: model.createdAt,
                vendor: model.vendor?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        recurringTemplateLine = try context.fetch(scope.descriptor(RecurringTemplateLine.self)).map { model in
            RecurringTemplateLineRecord(
                id: model.id,
                companyID: model.companyID,
                details: model.details,
                amount: model.amount,
                accountID: model.accountID,
                order: model.order,
                template: model.template?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        customerNote = try context.fetch(scope.descriptor(CustomerNote.self)).map { model in
            CustomerNoteRecord(
                id: model.id,
                companyID: model.companyID,
                date: model.date,
                text: model.text,
                author: model.author,
                createdAt: model.createdAt,
                customer: model.customer?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        invoiceEvent = try context.fetch(scope.descriptor(InvoiceEvent.self)).map { model in
            InvoiceEventRecord(
                id: model.id,
                companyID: model.companyID,
                kindRaw: model.kindRaw,
                date: model.date,
                recipient: model.recipient,
                subject: model.subject,
                message: model.message,
                createdAt: model.createdAt,
                invoice: model.invoice?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        estimate = try context.fetch(scope.descriptor(Estimate.self)).map { model in
            EstimateRecord(
                id: model.id,
                companyID: model.companyID,
                number: model.number,
                title: model.title,
                issueDate: model.issueDate,
                expirationDate: model.expirationDate,
                statusRaw: model.statusRaw,
                customerMessage: model.customerMessage,
                memo: model.memo,
                taxGroupID: model.taxGroupID,
                discount: model.discount,
                discountInvoiced: model.discountInvoiced,
                pricesIncludeTax: model.pricesIncludeTax,
                subtotal: model.subtotal,
                taxTotal: model.taxTotal,
                total: model.total,
                sentDate: model.sentDate,
                acceptedDate: model.acceptedDate,
                acceptedBy: model.acceptedBy,
                convertedDate: model.convertedDate,
                createdAt: model.createdAt,
                customer: model.customer?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        estimateLine = try context.fetch(scope.descriptor(EstimateLine.self)).map { model in
            EstimateLineRecord(
                id: model.id,
                companyID: model.companyID,
                details: model.details,
                quantity: model.quantity.backupString,
                unitPrice: model.unitPrice,
                isTaxable: model.isTaxable,
                incomeAccountID: model.incomeAccountID,
                itemID: model.itemID,
                order: model.order,
                invoicedQuantity: model.invoicedQuantity.backupString,
                estimate: model.estimate?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        periodClose = try context.fetch(scope.descriptor(PeriodClose.self)).map { model in
            PeriodCloseRecord(
                id: model.id,
                companyID: model.companyID,
                actionRaw: model.actionRaw,
                lockDate: model.lockDate,
                previousLockDate: model.previousLockDate,
                date: model.date,
                actor: model.actor,
                device: model.device,
                note: model.note
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        noticeState = try context.fetch(scope.descriptor(NoticeState.self)).map { model in
            NoticeStateRecord(
                id: model.id,
                companyID: model.companyID,
                key: model.key,
                isRead: model.isRead,
                isDismissed: model.isDismissed,
                updatedAt: model.updatedAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        bankTransaction = try context.fetch(scope.descriptor(BankTransaction.self)).map { model in
            BankTransactionRecord(
                id: model.id,
                companyID: model.companyID,
                accountID: model.accountID,
                date: model.date,
                amount: model.amount,
                details: model.details,
                payee: model.payee,
                memo: model.memo,
                checkNumber: model.checkNumber,
                externalID: model.externalID,
                sourceRaw: model.sourceRaw,
                statusRaw: model.statusRaw,
                categoryAccountID: model.categoryAccountID,
                vendorID: model.vendorID,
                customerID: model.customerID,
                ruleID: model.ruleID,
                matchedEntryID: model.matchedEntryID,
                matchedLineID: model.matchedLineID,
                createdDocumentID: model.createdDocumentID,
                importBatchID: model.importBatchID,
                importedAt: model.importedAt,
                reviewedAt: model.reviewedAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        bankRule = try context.fetch(scope.descriptor(BankRule.self)).map { model in
            BankRuleRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                matchText: model.matchText,
                amountSignRaw: model.amountSignRaw,
                bankAccountID: model.bankAccountID,
                targetAccountID: model.targetAccountID,
                vendorID: model.vendorID,
                payee: model.payee,
                autoApply: model.autoApply,
                priority: model.priority,
                isActive: model.isActive,
                createdAt: model.createdAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        bankImportProfile = try context.fetch(scope.descriptor(BankImportProfile.self)).map { model in
            BankImportProfileRecord(
                id: model.id,
                companyID: model.companyID,
                accountID: model.accountID,
                name: model.name,
                columnsJSON: model.columnsJSON,
                dateFormat: model.dateFormat,
                amountSignRaw: model.amountSignRaw,
                delimiter: model.delimiter,
                hasHeaderRow: model.hasHeaderRow,
                createdAt: model.createdAt,
                lastUsedAt: model.lastUsedAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        reconciliation = try context.fetch(scope.descriptor(Reconciliation.self)).map { model in
            ReconciliationRecord(
                id: model.id,
                companyID: model.companyID,
                accountID: model.accountID,
                statementDate: model.statementDate,
                statementEndingBalance: model.statementEndingBalance,
                beginningBalance: model.beginningBalance,
                statusRaw: model.statusRaw,
                closedAt: model.closedAt,
                createdAt: model.createdAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        budget = try context.fetch(scope.descriptor(Budget.self)).map { model in
            BudgetRecord(
                id: model.id,
                companyID: model.companyID,
                name: model.name,
                fiscalYear: model.fiscalYear,
                createdAt: model.createdAt
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        budgetLine = try context.fetch(scope.descriptor(BudgetLine.self)).map { model in
            BudgetLineRecord(
                id: model.id,
                companyID: model.companyID,
                accountID: model.accountID,
                month: model.month,
                amount: model.amount,
                budget: model.budget?.id
            )
        }.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
    }

    /// Número de registros por entidad.
    var counts: [String: Int] {
        [
            "Company": company?.count ?? 0,
            "Account": account?.count ?? 0,
            "JournalEntry": journalEntry?.count ?? 0,
            "JournalLine": journalLine?.count ?? 0,
            "Customer": customer?.count ?? 0,
            "Vendor": vendor?.count ?? 0,
            "Item": item?.count ?? 0,
            "Invoice": invoice?.count ?? 0,
            "InvoiceLine": invoiceLine?.count ?? 0,
            "InvoiceTaxLine": invoiceTaxLine?.count ?? 0,
            "CreditNote": creditNote?.count ?? 0,
            "CreditApplication": creditApplication?.count ?? 0,
            "PaymentReceived": paymentReceived?.count ?? 0,
            "PaymentApplication": paymentApplication?.count ?? 0,
            "Bill": bill?.count ?? 0,
            "BillLine": billLine?.count ?? 0,
            "BillPayment": billPayment?.count ?? 0,
            "Expense": expense?.count ?? 0,
            "ExpenseLine": expenseLine?.count ?? 0,
            "Attachment": attachment?.count ?? 0,
            "TaxAgency": taxAgency?.count ?? 0,
            "TaxRate": taxRate?.count ?? 0,
            "TaxGroup": taxGroup?.count ?? 0,
            "NumberSequence": numberSequence?.count ?? 0,
            "AuditEvent": auditEvent?.count ?? 0,
            "RecurringTemplate": recurringTemplate?.count ?? 0,
            "RecurringTemplateLine": recurringTemplateLine?.count ?? 0,
            "CustomerNote": customerNote?.count ?? 0,
            "InvoiceEvent": invoiceEvent?.count ?? 0,
            "Estimate": estimate?.count ?? 0,
            "EstimateLine": estimateLine?.count ?? 0,
            "PeriodClose": periodClose?.count ?? 0,
            "NoticeState": noticeState?.count ?? 0,
            "BankTransaction": bankTransaction?.count ?? 0,
            "BankRule": bankRule?.count ?? 0,
            "BankImportProfile": bankImportProfile?.count ?? 0,
            "Reconciliation": reconciliation?.count ?? 0,
            "Budget": budget?.count ?? 0,
            "BudgetLine": budgetLine?.count ?? 0,
        ]
    }
}

// MARK: - Restaurar

@MainActor
struct BackupRegistry {
    var company: [UUID: Company] = [:]
    var account: [UUID: Account] = [:]
    var journalEntry: [UUID: JournalEntry] = [:]
    var journalLine: [UUID: JournalLine] = [:]
    var customer: [UUID: Customer] = [:]
    var vendor: [UUID: Vendor] = [:]
    var item: [UUID: Item] = [:]
    var invoice: [UUID: Invoice] = [:]
    var invoiceLine: [UUID: InvoiceLine] = [:]
    var invoiceTaxLine: [UUID: InvoiceTaxLine] = [:]
    var creditNote: [UUID: CreditNote] = [:]
    var creditApplication: [UUID: CreditApplication] = [:]
    var paymentReceived: [UUID: PaymentReceived] = [:]
    var paymentApplication: [UUID: PaymentApplication] = [:]
    var bill: [UUID: Bill] = [:]
    var billLine: [UUID: BillLine] = [:]
    var billPayment: [UUID: BillPayment] = [:]
    var expense: [UUID: Expense] = [:]
    var expenseLine: [UUID: ExpenseLine] = [:]
    var attachment: [UUID: Attachment] = [:]
    var taxAgency: [UUID: TaxAgency] = [:]
    var taxRate: [UUID: TaxRate] = [:]
    var taxGroup: [UUID: TaxGroup] = [:]
    var numberSequence: [UUID: NumberSequence] = [:]
    var auditEvent: [UUID: AuditEvent] = [:]
    var recurringTemplate: [UUID: RecurringTemplate] = [:]
    var recurringTemplateLine: [UUID: RecurringTemplateLine] = [:]
    var customerNote: [UUID: CustomerNote] = [:]
    var invoiceEvent: [UUID: InvoiceEvent] = [:]
    var estimate: [UUID: Estimate] = [:]
    var estimateLine: [UUID: EstimateLine] = [:]
    var periodClose: [UUID: PeriodClose] = [:]
    var noticeState: [UUID: NoticeState] = [:]
    var bankTransaction: [UUID: BankTransaction] = [:]
    var bankRule: [UUID: BankRule] = [:]
    var bankImportProfile: [UUID: BankImportProfile] = [:]
    var reconciliation: [UUID: Reconciliation] = [:]
    var budget: [UUID: Budget] = [:]
    var budgetLine: [UUID: BudgetLine] = [:]

    func require<M>(_ table: [UUID: M], _ id: UUID?, _ field: String) throws -> M {
        guard let id, let model = table[id] else { throw BackupError.brokenReference(field) }
        return model
    }

    func optional<M>(_ table: [UUID: M], _ id: UUID?, _ field: String) throws -> M? {
        guard let id else { return nil }
        guard let model = table[id] else { throw BackupError.brokenReference(field) }
        return model
    }
}

extension BackupPayload {
    /// Todos los modelos del esquema, para borrar los libros antes de restaurar.
    static let modelTypes: [any PersistentModel.Type] = [
        Company.self,
        Account.self,
        JournalEntry.self,
        JournalLine.self,
        Customer.self,
        Vendor.self,
        Item.self,
        Invoice.self,
        InvoiceLine.self,
        InvoiceTaxLine.self,
        CreditNote.self,
        CreditApplication.self,
        PaymentReceived.self,
        PaymentApplication.self,
        Bill.self,
        BillLine.self,
        BillPayment.self,
        Expense.self,
        ExpenseLine.self,
        Attachment.self,
        TaxAgency.self,
        TaxRate.self,
        TaxGroup.self,
        NumberSequence.self,
        AuditEvent.self,
        RecurringTemplate.self,
        RecurringTemplateLine.self,
        CustomerNote.self,
        InvoiceEvent.self,
        Estimate.self,
        EstimateLine.self,
        PeriodClose.self,
        NoticeState.self,
        BankTransaction.self,
        BankRule.self,
        BankImportProfile.self,
        Reconciliation.self,
        Budget.self,
        BudgetLine.self,
    ]

    /// Crea los modelos en `context` (primero los que otros piden en su inicializador) y después sus relaciones.
    @MainActor
    func insert(into context: ModelContext) throws {
        var registry = BackupRegistry()
        for record in company ?? [] {
            let model = Company(legalName: "")
            model.id = record.id ?? UUID()
            model.legalName = record.legalName ?? ""
            model.displayName = record.displayName ?? ""
            model.ein = record.ein ?? ""
            model.entityTypeRaw = record.entityTypeRaw ?? EntityType.soleProprietorship.rawValue
            model.state = record.state ?? ""
            model.sectorRaw = record.sectorRaw ?? BusinessSector.services.rawValue
            model.address = record.address ?? ""
            model.email = record.email ?? ""
            model.phone = record.phone ?? ""
            model.currencyCode = record.currencyCode ?? "USD"
            model.fiscalYearStartMonth = record.fiscalYearStartMonth ?? 1
            model.lockDate = record.lockDate
            model.createdAt = record.createdAt ?? Date()
            model.website = record.website ?? ""
            model.defaultPaymentTermsDays = record.defaultPaymentTermsDays ?? 30
            model.defaultTaxGroupID = record.defaultTaxGroupID
            model.pricesIncludeTax = record.pricesIncludeTax ?? false
            model.salesTaxSourcingRaw = record.salesTaxSourcingRaw ?? SalesTaxSourcing.origin.rawValue
            model.invoiceAccentHex = record.invoiceAccentHex ?? InvoiceAccent.ink.hex
            model.invoiceStyleRaw = record.invoiceStyleRaw ?? InvoiceStyle.classic.rawValue
            model.invoiceShowLogo = record.invoiceShowLogo ?? true
            model.invoiceShowEIN = record.invoiceShowEIN ?? false
            model.invoiceShowAddress = record.invoiceShowAddress ?? true
            model.invoiceShowPhone = record.invoiceShowPhone ?? true
            model.defaultInvoiceMessage = record.defaultInvoiceMessage ?? ""
            model.invoiceFooter = record.invoiceFooter ?? ""
            model.closingPasswordHash = record.closingPasswordHash ?? ""
            model.sortOrder = record.sortOrder ?? 0
            model.isArchived = record.isArchived ?? false
            model.archivedAt = record.archivedAt
            model.postalCode = record.postalCode ?? ""
            model.paymentLinkURL = record.paymentLinkURL ?? ""
            model.paymentInstructions = record.paymentInstructions ?? ""
            model.showPayNowOnInvoice = record.showPayNowOnInvoice ?? true
            context.insert(model)
            registry.company[model.id] = model
        }
        for record in account ?? [] {
            let model = Account(code: "", name: "", subtype: .cash)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.code = record.code ?? ""
            model.name = record.name ?? ""
            model.subtypeRaw = record.subtypeRaw ?? AccountSubtype.otherAsset.rawValue
            model.details = record.details ?? ""
            model.isSystem = record.isSystem ?? false
            model.isArchived = record.isArchived ?? false
            model.createdAt = record.createdAt ?? Date()
            model.last4 = record.last4 ?? ""
            model.taxFormLineRaw = record.taxFormLineRaw ?? ""
            context.insert(model)
            registry.account[model.id] = model
        }
        for record in journalEntry ?? [] {
            let model = JournalEntry(number: 0, date: Date(), memo: "", source: .manual)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.number = record.number ?? 0
            model.date = record.date ?? Date()
            model.memo = record.memo ?? ""
            model.statusRaw = record.statusRaw ?? EntryStatus.posted.rawValue
            model.sourceRaw = record.sourceRaw ?? EntrySource.manual.rawValue
            model.sourceDocumentID = record.sourceDocumentID
            model.reversesEntryID = record.reversesEntryID
            model.reversedByEntryID = record.reversedByEntryID
            model.createdAt = record.createdAt ?? Date()
            model.replacesEntryID = record.replacesEntryID
            model.replacedByEntryID = record.replacedByEntryID
            context.insert(model)
            registry.journalEntry[model.id] = model
        }
        for record in journalLine ?? [] {
            let model = JournalLine(account: try registry.require(registry.account, record.account, "JournalLine.account"), debit: 0, credit: 0, order: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.debit = record.debit ?? 0
            model.credit = record.credit ?? 0
            model.memo = record.memo ?? ""
            model.order = record.order ?? 0
            model.customerID = record.customerID
            model.vendorID = record.vendorID
            model.reconciliationID = record.reconciliationID
            model.clearedAt = record.clearedAt
            context.insert(model)
            registry.journalLine[model.id] = model
        }
        for record in customer ?? [] {
            let model = Customer(name: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.companyName = record.companyName ?? ""
            model.email = record.email ?? ""
            model.phone = record.phone ?? ""
            model.billingAddress = record.billingAddress ?? ""
            model.shippingAddress = record.shippingAddress ?? ""
            model.paymentTermsDays = record.paymentTermsDays ?? 30
            model.isTaxExempt = record.isTaxExempt ?? false
            model.exemptionReason = record.exemptionReason ?? ""
            model.defaultTaxGroupID = record.defaultTaxGroupID
            model.notes = record.notes ?? ""
            model.isArchived = record.isArchived ?? false
            model.createdAt = record.createdAt ?? Date()
            model.contactName = record.contactName ?? ""
            model.contactTitle = record.contactTitle ?? ""
            model.taxID = record.taxID ?? ""
            model.postalCode = record.postalCode ?? ""
            context.insert(model)
            registry.customer[model.id] = model
        }
        for record in vendor ?? [] {
            let model = Vendor(name: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.companyName = record.companyName ?? ""
            model.email = record.email ?? ""
            model.phone = record.phone ?? ""
            model.address = record.address ?? ""
            model.paymentTermsDays = record.paymentTermsDays ?? 30
            model.defaultExpenseAccountID = record.defaultExpenseAccountID
            model.is1099 = record.is1099 ?? false
            model.tinLast4 = record.tinLast4 ?? ""
            model.notes = record.notes ?? ""
            model.isArchived = record.isArchived ?? false
            model.createdAt = record.createdAt ?? Date()
            model.w9Received = record.w9Received ?? false
            model.w9ReceivedDate = record.w9ReceivedDate
            model.preferredPaymentMethodRaw = record.preferredPaymentMethodRaw ?? ""
            model.preferredPaymentAccountID = record.preferredPaymentAccountID
            context.insert(model)
            registry.vendor[model.id] = model
        }
        for record in item ?? [] {
            let model = Item(name: "", unitPrice: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.details = record.details ?? ""
            model.unitPrice = record.unitPrice ?? 0
            model.isTaxable = record.isTaxable ?? true
            model.incomeAccountID = record.incomeAccountID
            model.isArchived = record.isArchived ?? false
            context.insert(model)
            registry.item[model.id] = model
        }
        for record in invoice ?? [] {
            let model = Invoice(customer: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.number = record.number ?? ""
            model.issueDate = record.issueDate ?? Date()
            model.dueDate = record.dueDate ?? Date()
            model.statusRaw = record.statusRaw ?? InvoiceStatus.draft.rawValue
            model.memo = record.memo ?? ""
            model.customerMessage = record.customerMessage ?? ""
            model.shippingAddress = record.shippingAddress ?? ""
            model.taxGroupID = record.taxGroupID
            model.journalEntryID = record.journalEntryID
            model.subtotal = record.subtotal ?? 0
            model.discount = record.discount ?? 0
            model.taxTotal = record.taxTotal ?? 0
            model.total = record.total ?? 0
            model.amountPaid = record.amountPaid ?? 0
            model.creditsApplied = record.creditsApplied ?? 0
            model.createdAt = record.createdAt ?? Date()
            model.pricesIncludeTax = record.pricesIncludeTax ?? false
            model.estimateID = record.estimateID
            context.insert(model)
            registry.invoice[model.id] = model
        }
        for record in invoiceLine ?? [] {
            let model = InvoiceLine(details: "", unitPrice: 0, incomeAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.details = record.details ?? ""
            model.quantity = record.quantity.flatMap(Decimal.init(backupString:)) ?? 1
            model.unitPrice = record.unitPrice ?? 0
            model.isTaxable = record.isTaxable ?? true
            model.incomeAccountID = record.incomeAccountID
            model.itemID = record.itemID
            model.order = record.order ?? 0
            context.insert(model)
            registry.invoiceLine[model.id] = model
        }
        for record in invoiceTaxLine ?? [] {
            let model = InvoiceTaxLine(taxRateID: nil, name: "", rateMillionths: 0, taxableBase: 0, amount: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.taxRateID = record.taxRateID
            model.name = record.name ?? ""
            model.rateMillionths = record.rateMillionths ?? 0
            model.taxableBase = record.taxableBase ?? 0
            model.amount = record.amount ?? 0
            context.insert(model)
            registry.invoiceTaxLine[model.id] = model
        }
        for record in creditNote ?? [] {
            let model = CreditNote(invoice: try registry.require(registry.invoice, record.invoice, "CreditNote.invoice"), date: Date(), amount: 0, isTaxable: false, reason: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.number = record.number ?? ""
            model.date = record.date ?? Date()
            model.reason = record.reason ?? ""
            model.amount = record.amount ?? 0
            model.isTaxable = record.isTaxable ?? true
            model.incomeAccountID = record.incomeAccountID
            model.taxTotal = record.taxTotal ?? 0
            model.total = record.total ?? 0
            model.unappliedAmount = record.unappliedAmount ?? 0
            model.refundedAmount = record.refundedAmount ?? 0
            model.journalEntryID = record.journalEntryID
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.creditNote[model.id] = model
        }
        for record in creditApplication ?? [] {
            let model = CreditApplication(note: try registry.require(registry.creditNote, record.note, "CreditApplication.note"), invoice: try registry.require(registry.invoice, record.invoice, "CreditApplication.invoice"), amount: 0, date: Date())
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.amount = record.amount ?? 0
            context.insert(model)
            registry.creditApplication[model.id] = model
        }
        for record in paymentReceived ?? [] {
            let model = PaymentReceived(customer: nil, date: Date(), amount: 0, method: .cash, depositAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.amount = record.amount ?? 0
            model.methodRaw = record.methodRaw ?? PaymentMethod.bankTransfer.rawValue
            model.reference = record.reference ?? ""
            model.depositAccountID = record.depositAccountID
            model.journalEntryID = record.journalEntryID
            context.insert(model)
            registry.paymentReceived[model.id] = model
        }
        for record in paymentApplication ?? [] {
            let model = PaymentApplication(amount: 0, invoice: try registry.require(registry.invoice, record.invoice, "PaymentApplication.invoice"))
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.amount = record.amount ?? 0
            context.insert(model)
            registry.paymentApplication[model.id] = model
        }
        for record in bill ?? [] {
            let model = Bill(vendor: nil, vendorNumber: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.vendorNumber = record.vendorNumber ?? ""
            model.billDate = record.billDate ?? Date()
            model.dueDate = record.dueDate ?? Date()
            model.statusRaw = record.statusRaw ?? BillStatus.open.rawValue
            model.memo = record.memo ?? ""
            model.payableAccountID = record.payableAccountID
            model.journalEntryID = record.journalEntryID
            model.total = record.total ?? 0
            model.amountPaid = record.amountPaid ?? 0
            model.createdAt = record.createdAt ?? Date()
            model.scheduledPaymentDate = record.scheduledPaymentDate
            model.scheduledPaymentAccountID = record.scheduledPaymentAccountID
            model.scheduledPaymentMethodRaw = record.scheduledPaymentMethodRaw ?? ""
            model.autoPay = record.autoPay ?? false
            model.recurringTemplateID = record.recurringTemplateID
            model.recurrenceDate = record.recurrenceDate
            context.insert(model)
            registry.bill[model.id] = model
        }
        for record in billLine ?? [] {
            let model = BillLine(details: "", amount: 0, accountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.details = record.details ?? ""
            model.amount = record.amount ?? 0
            model.accountID = record.accountID
            model.order = record.order ?? 0
            context.insert(model)
            registry.billLine[model.id] = model
        }
        for record in billPayment ?? [] {
            let model = BillPayment(bill: try registry.require(registry.bill, record.bill, "BillPayment.bill"), date: Date(), amount: 0, method: .cash, paymentAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.amount = record.amount ?? 0
            model.methodRaw = record.methodRaw ?? PaymentMethod.bankTransfer.rawValue
            model.reference = record.reference ?? ""
            model.paymentAccountID = record.paymentAccountID
            model.journalEntryID = record.journalEntryID
            context.insert(model)
            registry.billPayment[model.id] = model
        }
        for record in expense ?? [] {
            let model = Expense(payee: "", paymentAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.payee = record.payee ?? ""
            model.methodRaw = record.methodRaw ?? PaymentMethod.card.rawValue
            model.reference = record.reference ?? ""
            model.memo = record.memo ?? ""
            model.paymentAccountID = record.paymentAccountID
            model.journalEntryID = record.journalEntryID
            model.total = record.total ?? 0
            model.createdAt = record.createdAt ?? Date()
            model.salesTaxIncluded = record.salesTaxIncluded ?? 0
            model.recurringTemplateID = record.recurringTemplateID
            model.recurrenceDate = record.recurrenceDate
            model.revision = record.revision ?? 0
            model.voidedAt = record.voidedAt
            context.insert(model)
            registry.expense[model.id] = model
        }
        for record in expenseLine ?? [] {
            let model = ExpenseLine(details: "", amount: 0, accountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.details = record.details ?? ""
            model.amount = record.amount ?? 0
            model.accountID = record.accountID
            model.order = record.order ?? 0
            context.insert(model)
            registry.expenseLine[model.id] = model
        }
        for record in attachment ?? [] {
            let model = Attachment(filename: "", contentType: "", data: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.filename = record.filename ?? ""
            model.contentType = record.contentType ?? ""
            model.data = record.data
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.attachment[model.id] = model
        }
        for record in taxAgency ?? [] {
            let model = TaxAgency(name: "", liabilityAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.filingFrequencyRaw = record.filingFrequencyRaw ?? FilingFrequency.quarterly.rawValue
            model.liabilityAccountID = record.liabilityAccountID
            model.isArchived = record.isArchived ?? false
            context.insert(model)
            registry.taxAgency[model.id] = model
        }
        for record in taxRate ?? [] {
            let model = TaxRate(name: "", rateMillionths: 0, agency: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.rateMillionths = record.rateMillionths ?? 0
            model.effectiveFrom = record.effectiveFrom
            model.effectiveTo = record.effectiveTo
            model.isArchived = record.isArchived ?? false
            context.insert(model)
            registry.taxRate[model.id] = model
        }
        for record in taxGroup ?? [] {
            let model = TaxGroup(name: "", rates: [])
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.isArchived = record.isArchived ?? false
            context.insert(model)
            registry.taxGroup[model.id] = model
        }
        for record in numberSequence ?? [] {
            let model = NumberSequence(kind: .journalEntry, prefix: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.kindRaw = record.kindRaw ?? DocumentKind.invoice.rawValue
            model.prefix = record.prefix ?? ""
            model.nextNumber = record.nextNumber ?? 1
            model.minimumDigits = record.minimumDigits ?? 4
            context.insert(model)
            registry.numberSequence[model.id] = model
        }
        for record in auditEvent ?? [] {
            let model = AuditEvent(actor: "", entityName: "", entityID: nil, action: "", summary: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.actor = record.actor ?? ""
            model.subjectEntity = record.entityName ?? ""
            model.entityID = record.entityID
            model.action = record.action ?? ""
            model.summary = record.summary ?? ""
            context.insert(model)
            registry.auditEvent[model.id] = model
        }
        for record in recurringTemplate ?? [] {
            let model = RecurringTemplate(name: "", kind: .expense, frequency: .weekly, startDate: Date())
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.kindRaw = record.kindRaw ?? RecurringKind.expense.rawValue
            model.payee = record.payee ?? ""
            model.memo = record.memo ?? ""
            model.frequencyRaw = record.frequencyRaw ?? RecurrenceFrequency.monthly.rawValue
            model.startDate = record.startDate ?? Date()
            model.nextDate = record.nextDate ?? Date()
            model.endDate = record.endDate
            model.isActive = record.isActive ?? true
            model.autoCharge = record.autoCharge ?? false
            model.paymentAccountID = record.paymentAccountID
            model.methodRaw = record.methodRaw ?? PaymentMethod.card.rawValue
            model.billTermsDays = record.billTermsDays ?? 30
            model.lastGeneratedDate = record.lastGeneratedDate
            model.lastRunAt = record.lastRunAt
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.recurringTemplate[model.id] = model
        }
        for record in recurringTemplateLine ?? [] {
            let model = RecurringTemplateLine(details: "", amount: 0, accountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.details = record.details ?? ""
            model.amount = record.amount ?? 0
            model.accountID = record.accountID
            model.order = record.order ?? 0
            context.insert(model)
            registry.recurringTemplateLine[model.id] = model
        }
        for record in customerNote ?? [] {
            let model = CustomerNote(customer: nil, date: Date(), text: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.date = record.date ?? Date()
            model.text = record.text ?? ""
            model.author = record.author ?? ""
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.customerNote[model.id] = model
        }
        for record in invoiceEvent ?? [] {
            let model = InvoiceEvent(invoice: nil, kind: .sent, date: Date(), recipient: "", subject: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.kindRaw = record.kindRaw ?? InvoiceEventKind.sent.rawValue
            model.date = record.date ?? Date()
            model.recipient = record.recipient ?? ""
            model.subject = record.subject ?? ""
            model.message = record.message ?? ""
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.invoiceEvent[model.id] = model
        }
        for record in estimate ?? [] {
            let model = Estimate(customer: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.number = record.number ?? ""
            model.title = record.title ?? ""
            model.issueDate = record.issueDate ?? Date()
            model.expirationDate = record.expirationDate ?? Date()
            model.statusRaw = record.statusRaw ?? EstimateStatus.draft.rawValue
            model.customerMessage = record.customerMessage ?? ""
            model.memo = record.memo ?? ""
            model.taxGroupID = record.taxGroupID
            model.discount = record.discount ?? 0
            model.discountInvoiced = record.discountInvoiced ?? 0
            model.pricesIncludeTax = record.pricesIncludeTax ?? false
            model.subtotal = record.subtotal ?? 0
            model.taxTotal = record.taxTotal ?? 0
            model.total = record.total ?? 0
            model.sentDate = record.sentDate
            model.acceptedDate = record.acceptedDate
            model.acceptedBy = record.acceptedBy ?? ""
            model.convertedDate = record.convertedDate
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.estimate[model.id] = model
        }
        for record in estimateLine ?? [] {
            let model = EstimateLine(details: "", unitPrice: 0, incomeAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.details = record.details ?? ""
            model.quantity = record.quantity.flatMap(Decimal.init(backupString:)) ?? 1
            model.unitPrice = record.unitPrice ?? 0
            model.isTaxable = record.isTaxable ?? true
            model.incomeAccountID = record.incomeAccountID
            model.itemID = record.itemID
            model.order = record.order ?? 0
            model.invoicedQuantity = record.invoicedQuantity.flatMap(Decimal.init(backupString:)) ?? 0
            context.insert(model)
            registry.estimateLine[model.id] = model
        }
        for record in periodClose ?? [] {
            let model = PeriodClose(isReopen: false, lockDate: nil, previousLockDate: nil, actor: "", device: "", note: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.actionRaw = record.actionRaw ?? "close"
            model.lockDate = record.lockDate
            model.previousLockDate = record.previousLockDate
            model.date = record.date ?? Date()
            model.actor = record.actor ?? ""
            model.device = record.device ?? ""
            model.note = record.note ?? ""
            context.insert(model)
            registry.periodClose[model.id] = model
        }
        for record in noticeState ?? [] {
            let model = NoticeState(key: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.key = record.key ?? ""
            model.isRead = record.isRead ?? false
            model.isDismissed = record.isDismissed ?? false
            model.updatedAt = record.updatedAt ?? Date()
            context.insert(model)
            registry.noticeState[model.id] = model
        }
        for record in bankTransaction ?? [] {
            let model = BankTransaction(accountID: nil, date: Date(), amount: 0, details: "", externalID: "", source: .csv)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.accountID = record.accountID
            model.date = record.date ?? Date()
            model.amount = record.amount ?? 0
            model.details = record.details ?? ""
            model.payee = record.payee ?? ""
            model.memo = record.memo ?? ""
            model.checkNumber = record.checkNumber ?? ""
            model.externalID = record.externalID ?? ""
            model.sourceRaw = record.sourceRaw ?? BankSourceKind.csv.rawValue
            model.statusRaw = record.statusRaw ?? BankTransactionStatus.toReview.rawValue
            model.categoryAccountID = record.categoryAccountID
            model.vendorID = record.vendorID
            model.customerID = record.customerID
            model.ruleID = record.ruleID
            model.matchedEntryID = record.matchedEntryID
            model.matchedLineID = record.matchedLineID
            model.createdDocumentID = record.createdDocumentID
            model.importBatchID = record.importBatchID
            model.importedAt = record.importedAt ?? Date()
            model.reviewedAt = record.reviewedAt
            context.insert(model)
            registry.bankTransaction[model.id] = model
        }
        for record in bankRule ?? [] {
            let model = BankRule(name: "", matchText: "", targetAccountID: nil)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.matchText = record.matchText ?? ""
            model.amountSignRaw = record.amountSignRaw ?? BankAmountSign.any.rawValue
            model.bankAccountID = record.bankAccountID
            model.targetAccountID = record.targetAccountID
            model.vendorID = record.vendorID
            model.payee = record.payee ?? ""
            model.autoApply = record.autoApply ?? false
            model.priority = record.priority ?? 0
            model.isActive = record.isActive ?? true
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.bankRule[model.id] = model
        }
        for record in bankImportProfile ?? [] {
            let model = BankImportProfile(accountID: nil, name: "")
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.accountID = record.accountID
            model.name = record.name ?? ""
            model.columnsJSON = record.columnsJSON ?? ""
            model.dateFormat = record.dateFormat ?? "MM/dd/yyyy"
            model.amountSignRaw = record.amountSignRaw ?? CSVAmountSign.signed.rawValue
            model.delimiter = record.delimiter ?? ","
            model.hasHeaderRow = record.hasHeaderRow ?? true
            model.createdAt = record.createdAt ?? Date()
            model.lastUsedAt = record.lastUsedAt
            context.insert(model)
            registry.bankImportProfile[model.id] = model
        }
        for record in reconciliation ?? [] {
            let model = Reconciliation(accountID: nil, statementDate: Date(), statementEndingBalance: 0, beginningBalance: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.accountID = record.accountID
            model.statementDate = record.statementDate ?? Date()
            model.statementEndingBalance = record.statementEndingBalance ?? 0
            model.beginningBalance = record.beginningBalance ?? 0
            model.statusRaw = record.statusRaw ?? ReconciliationStatus.inProgress.rawValue
            model.closedAt = record.closedAt
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.reconciliation[model.id] = model
        }
        for record in budget ?? [] {
            let model = Budget(name: "", fiscalYear: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.name = record.name ?? ""
            model.fiscalYear = record.fiscalYear ?? 0
            model.createdAt = record.createdAt ?? Date()
            context.insert(model)
            registry.budget[model.id] = model
        }
        for record in budgetLine ?? [] {
            let model = BudgetLine(accountID: nil, month: 0, amount: 0)
            model.id = record.id ?? UUID()
            model.companyID = record.companyID
            model.accountID = record.accountID
            model.month = record.month ?? 1
            model.amount = record.amount ?? 0
            context.insert(model)
            registry.budgetLine[model.id] = model
        }
        for record in company ?? [] {
            guard let id = record.id, let model = registry.company[id] else { continue }
            model.logo = try registry.optional(registry.attachment, record.logo, "Company.logo")
        }
        for record in account ?? [] {
            guard let id = record.id, let model = registry.account[id] else { continue }
            model.parent = try registry.optional(registry.account, record.parent, "Account.parent")
        }
        for record in journalLine ?? [] {
            guard let id = record.id, let model = registry.journalLine[id] else { continue }
            model.entry = try registry.optional(registry.journalEntry, record.entry, "JournalLine.entry")
            model.account = try registry.optional(registry.account, record.account, "JournalLine.account")
        }
        for record in vendor ?? [] {
            guard let id = record.id, let model = registry.vendor[id] else { continue }
            model.w9Attachment = try registry.optional(registry.attachment, record.w9Attachment, "Vendor.w9Attachment")
        }
        for record in invoice ?? [] {
            guard let id = record.id, let model = registry.invoice[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "Invoice.customer")
        }
        for record in invoiceLine ?? [] {
            guard let id = record.id, let model = registry.invoiceLine[id] else { continue }
            model.invoice = try registry.optional(registry.invoice, record.invoice, "InvoiceLine.invoice")
        }
        for record in invoiceTaxLine ?? [] {
            guard let id = record.id, let model = registry.invoiceTaxLine[id] else { continue }
            model.invoice = try registry.optional(registry.invoice, record.invoice, "InvoiceTaxLine.invoice")
        }
        for record in creditNote ?? [] {
            guard let id = record.id, let model = registry.creditNote[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "CreditNote.customer")
            model.invoice = try registry.optional(registry.invoice, record.invoice, "CreditNote.invoice")
        }
        for record in creditApplication ?? [] {
            guard let id = record.id, let model = registry.creditApplication[id] else { continue }
            model.note = try registry.optional(registry.creditNote, record.note, "CreditApplication.note")
            model.invoice = try registry.optional(registry.invoice, record.invoice, "CreditApplication.invoice")
        }
        for record in paymentReceived ?? [] {
            guard let id = record.id, let model = registry.paymentReceived[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "PaymentReceived.customer")
        }
        for record in paymentApplication ?? [] {
            guard let id = record.id, let model = registry.paymentApplication[id] else { continue }
            model.payment = try registry.optional(registry.paymentReceived, record.payment, "PaymentApplication.payment")
            model.invoice = try registry.optional(registry.invoice, record.invoice, "PaymentApplication.invoice")
        }
        for record in bill ?? [] {
            guard let id = record.id, let model = registry.bill[id] else { continue }
            model.vendor = try registry.optional(registry.vendor, record.vendor, "Bill.vendor")
        }
        for record in billLine ?? [] {
            guard let id = record.id, let model = registry.billLine[id] else { continue }
            model.bill = try registry.optional(registry.bill, record.bill, "BillLine.bill")
        }
        for record in billPayment ?? [] {
            guard let id = record.id, let model = registry.billPayment[id] else { continue }
            model.bill = try registry.optional(registry.bill, record.bill, "BillPayment.bill")
        }
        for record in expense ?? [] {
            guard let id = record.id, let model = registry.expense[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "Expense.customer")
            model.vendor = try registry.optional(registry.vendor, record.vendor, "Expense.vendor")
        }
        for record in expenseLine ?? [] {
            guard let id = record.id, let model = registry.expenseLine[id] else { continue }
            model.expense = try registry.optional(registry.expense, record.expense, "ExpenseLine.expense")
        }
        for record in attachment ?? [] {
            guard let id = record.id, let model = registry.attachment[id] else { continue }
            model.expense = try registry.optional(registry.expense, record.expense, "Attachment.expense")
            model.bill = try registry.optional(registry.bill, record.bill, "Attachment.bill")
            model.w9OfVendor = try registry.optional(registry.vendor, record.w9OfVendor, "Attachment.w9OfVendor")
            model.logoOfCompany = try registry.optional(registry.company, record.logoOfCompany, "Attachment.logoOfCompany")
        }
        for record in taxRate ?? [] {
            guard let id = record.id, let model = registry.taxRate[id] else { continue }
            model.agency = try registry.optional(registry.taxAgency, record.agency, "TaxRate.agency")
            model.groups = try record.groups.map { try $0.map { try registry.require(registry.taxGroup, $0, "TaxRate.groups") } } ?? []
        }
        for record in recurringTemplate ?? [] {
            guard let id = record.id, let model = registry.recurringTemplate[id] else { continue }
            model.vendor = try registry.optional(registry.vendor, record.vendor, "RecurringTemplate.vendor")
        }
        for record in recurringTemplateLine ?? [] {
            guard let id = record.id, let model = registry.recurringTemplateLine[id] else { continue }
            model.template = try registry.optional(registry.recurringTemplate, record.template, "RecurringTemplateLine.template")
        }
        for record in customerNote ?? [] {
            guard let id = record.id, let model = registry.customerNote[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "CustomerNote.customer")
        }
        for record in invoiceEvent ?? [] {
            guard let id = record.id, let model = registry.invoiceEvent[id] else { continue }
            model.invoice = try registry.optional(registry.invoice, record.invoice, "InvoiceEvent.invoice")
        }
        for record in estimate ?? [] {
            guard let id = record.id, let model = registry.estimate[id] else { continue }
            model.customer = try registry.optional(registry.customer, record.customer, "Estimate.customer")
        }
        for record in estimateLine ?? [] {
            guard let id = record.id, let model = registry.estimateLine[id] else { continue }
            model.estimate = try registry.optional(registry.estimate, record.estimate, "EstimateLine.estimate")
        }
        for record in budgetLine ?? [] {
            guard let id = record.id, let model = registry.budgetLine[id] else { continue }
            model.budget = try registry.optional(registry.budget, record.budget, "BudgetLine.budget")
        }
    }
}
