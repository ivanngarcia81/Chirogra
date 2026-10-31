import ChirograCore
import Foundation
import SwiftData

// Reglas del esquema (DISEÑO §5.1), pensadas para la sincronización con CloudKit desde la v1:
// - todas las propiedades tienen valor por defecto y todas las relaciones son opcionales;
// - sin `@Attribute(.unique)`: la unicidad (números de documento) la valida la capa de dominio;
// - sin la regla de borrado `.deny` (CloudKit no la admite): impedir borrar cuentas o clientes con movimientos
//   es responsabilidad de la capa de dominio (se archivan);
// - toda relación tiene inversa. Las referencias secundarias (cuenta de ingreso de una línea,
//   asiento generado por un documento…) se guardan como `UUID` para no multiplicar inversas en `Account`;
// - el dinero va en `Int64` de centavos; los enums se guardan como `String` (`…Raw`).

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Company.self, Account.self, JournalEntry.self, JournalLine.self,
            Customer.self, Vendor.self, Item.self,
            Invoice.self, InvoiceLine.self, InvoiceTaxLine.self, PaymentReceived.self, PaymentApplication.self,
            Bill.self, BillLine.self, BillPayment.self, Expense.self, ExpenseLine.self, Attachment.self,
            TaxAgency.self, TaxRate.self, TaxGroup.self,
            NumberSequence.self, AuditEvent.self,
        ]
    }
}

public enum ChirograMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public typealias Company = SchemaV1.Company
public typealias Account = SchemaV1.Account
public typealias JournalEntry = SchemaV1.JournalEntry
public typealias JournalLine = SchemaV1.JournalLine
public typealias Customer = SchemaV1.Customer
public typealias Vendor = SchemaV1.Vendor
public typealias Item = SchemaV1.Item
public typealias Invoice = SchemaV1.Invoice
public typealias InvoiceLine = SchemaV1.InvoiceLine
public typealias InvoiceTaxLine = SchemaV1.InvoiceTaxLine
public typealias PaymentReceived = SchemaV1.PaymentReceived
public typealias PaymentApplication = SchemaV1.PaymentApplication
public typealias Bill = SchemaV1.Bill
public typealias BillLine = SchemaV1.BillLine
public typealias BillPayment = SchemaV1.BillPayment
public typealias Expense = SchemaV1.Expense
public typealias ExpenseLine = SchemaV1.ExpenseLine
public typealias Attachment = SchemaV1.Attachment
public typealias TaxAgency = SchemaV1.TaxAgency
public typealias TaxRate = SchemaV1.TaxRate
public typealias TaxGroup = SchemaV1.TaxGroup
public typealias NumberSequence = SchemaV1.NumberSequence
public typealias AuditEvent = SchemaV1.AuditEvent

// MARK: - Enums persistidos como texto

public enum EntityType: String, CaseIterable, Sendable, Codable {
    case soleProprietorship, llc, sCorp, cCorp, partnership
}

public enum EntryStatus: String, Sendable, Codable {
    case draft, posted
}

public enum InvoiceStatus: String, CaseIterable, Sendable, Codable {
    case draft, sent, partiallyPaid, paid, void
}

public enum BillStatus: String, CaseIterable, Sendable, Codable {
    case open, partiallyPaid, paid, void
}

public enum PaymentMethod: String, CaseIterable, Sendable, Codable {
    case cash, check, bankTransfer, card, other
}

public enum DocumentKind: String, CaseIterable, Sendable, Codable {
    case journalEntry, invoice, creditNote
}

public enum FilingFrequency: String, CaseIterable, Sendable, Codable {
    case monthly, quarterly, annual
}

// MARK: - Modelos

extension SchemaV1 {

    @Model
    public final class Company {
        public var id: UUID = UUID()
        public var legalName: String = ""
        public var displayName: String = ""
        public var ein: String = ""
        public var entityTypeRaw: String = EntityType.soleProprietorship.rawValue
        public var state: String = ""
        /// Sector elegido en el alta (`BusinessSector`); decidió la plantilla del plan de cuentas.
        public var sectorRaw: String = BusinessSector.services.rawValue
        public var address: String = ""
        public var email: String = ""
        public var phone: String = ""
        public var currencyCode: String = "USD"
        /// Mes (1–12) en que empieza el año fiscal.
        public var fiscalYearStartMonth: Int = 1
        /// Fecha de cierre: no se contabiliza en o antes de este día.
        public var lockDate: Date?
        public var createdAt: Date = Date()

        public init(legalName: String, displayName: String = "", entityType: EntityType = .soleProprietorship, state: String = "") {
            self.legalName = legalName
            self.displayName = displayName.isEmpty ? legalName : displayName
            self.entityTypeRaw = entityType.rawValue
            self.state = state
        }

        public var entityType: EntityType {
            get { EntityType(rawValue: entityTypeRaw) ?? .soleProprietorship }
            set { entityTypeRaw = newValue.rawValue }
        }

        public var currency: CurrencyCode { CurrencyCode(code: currencyCode) }
    }

    @Model
    public final class Account {
        public var id: UUID = UUID()
        public var code: String = ""
        public var name: String = ""
        public var subtypeRaw: String = AccountSubtype.otherAsset.rawValue
        public var details: String = ""
        /// Cuentas de sistema (CxC, CxP, Sales Tax Payable…): no se borran ni cambian de tipo.
        public var isSystem: Bool = false
        public var isArchived: Bool = false
        public var createdAt: Date = Date()

        public var parent: Account?
        @Relationship(deleteRule: .nullify, inverse: \Account.parent)
        public var children: [Account]? = []
        @Relationship(deleteRule: .nullify, inverse: \JournalLine.account)
        public var lines: [JournalLine]? = []

        public init(code: String, name: String, subtype: AccountSubtype, isSystem: Bool = false, parent: Account? = nil) {
            self.code = code
            self.name = name
            self.subtypeRaw = subtype.rawValue
            self.isSystem = isSystem
            self.parent = parent
        }

        public var subtype: AccountSubtype {
            get { AccountSubtype(rawValue: subtypeRaw) ?? .otherAsset }
            set { subtypeRaw = newValue.rawValue }
        }

        public var type: AccountType { subtype.accountType }
        public var isLeaf: Bool { (children ?? []).isEmpty }
        public var isPostable: Bool { !isArchived && isLeaf }
        public var displayName: String { code.isEmpty ? name : "\(code) · \(name)" }

        public var ledgerAccount: LedgerAccount {
            LedgerAccount(id: id, code: code, name: name, subtype: subtype)
        }

        public var accountInfo: AccountInfo {
            AccountInfo(id: id, type: type, isPostable: isPostable)
        }
    }

    @Model
    public final class JournalEntry {
        public var id: UUID = UUID()
        public var number: Int = 0
        public var date: Date = Date()
        public var memo: String = ""
        public var statusRaw: String = EntryStatus.posted.rawValue
        public var sourceRaw: String = EntrySource.manual.rawValue
        /// Documento que generó el asiento (factura, pago, gasto…), si lo hay.
        public var sourceDocumentID: UUID?
        /// Asiento al que este revierte / asiento que revirtió a este.
        public var reversesEntryID: UUID?
        public var reversedByEntryID: UUID?
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \JournalLine.entry)
        public var lines: [JournalLine]? = []

        public init(number: Int, date: Date, memo: String, source: EntrySource, status: EntryStatus = .posted) {
            self.number = number
            self.date = date
            self.memo = memo
            self.sourceRaw = source.rawValue
            self.statusRaw = status.rawValue
        }

        public var status: EntryStatus { EntryStatus(rawValue: statusRaw) ?? .draft }
        public var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
        public var isReversed: Bool { reversedByEntryID != nil }
        public var sortedLines: [JournalLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var totalDebits: Int64 { (lines ?? []).reduce(0) { $0 + $1.debit } }
        public var totalCredits: Int64 { (lines ?? []).reduce(0) { $0 + $1.credit } }

        public var draft: JournalEntryDraft {
            JournalEntryDraft(date: date, memo: memo, source: source, lines: sortedLines.compactMap { line in
                guard let accountID = line.account?.id else { return nil }
                return JournalLineDraft(accountID: accountID, debit: line.debit, credit: line.credit, memo: line.memo)
            })
        }
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

        public var entry: JournalEntry?
        public var account: Account?

        public init(account: Account, debit: Int64, credit: Int64, memo: String = "", order: Int) {
            self.account = account
            self.debit = debit
            self.credit = credit
            self.memo = memo
            self.order = order
        }
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
        /// 0 = al recibir (Due on receipt).
        public var paymentTermsDays: Int = 30
        public var isTaxExempt: Bool = false
        public var exemptionReason: String = ""
        public var defaultTaxGroupID: UUID?
        public var notes: String = ""
        public var isArchived: Bool = false
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \Invoice.customer)
        public var invoices: [Invoice]? = []
        @Relationship(deleteRule: .nullify, inverse: \PaymentReceived.customer)
        public var payments: [PaymentReceived]? = []

        public init(name: String, email: String = "", paymentTermsDays: Int = 30) {
            self.name = name
            self.email = email
            self.paymentTermsDays = paymentTermsDays
        }

        /// Saldo pendiente de las facturas emitidas.
        public var openBalance: Int64 {
            (invoices ?? []).filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }
        }

        public var initials: String {
            name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
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
        /// Solo los últimos 4 dígitos; el TIN completo iría al llavero (§6.6).
        public var tinLast4: String = ""
        public var notes: String = ""
        public var isArchived: Bool = false
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \Bill.vendor)
        public var bills: [Bill]? = []
        @Relationship(deleteRule: .nullify, inverse: \Expense.vendor)
        public var expenses: [Expense]? = []

        public init(name: String, email: String = "") {
            self.name = name
            self.email = email
        }

        public var openBalance: Int64 {
            (bills ?? []).filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }
        }
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

        public init(name: String, unitPrice: Int64, isTaxable: Bool = true, incomeAccountID: UUID? = nil) {
            self.name = name
            self.unitPrice = unitPrice
            self.isTaxable = isTaxable
            self.incomeAccountID = incomeAccountID
        }
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
        // Totales guardados al emitir, para listas rápidas.
        public var subtotal: Int64 = 0
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var amountPaid: Int64 = 0
        public var createdAt: Date = Date()

        public var customer: Customer?
        @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
        public var lines: [InvoiceLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \InvoiceTaxLine.invoice)
        public var taxLines: [InvoiceTaxLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \PaymentApplication.invoice)
        public var paymentApplications: [PaymentApplication]? = []

        public init(customer: Customer?, issueDate: Date = Date(), dueDate: Date? = nil) {
            self.customer = customer
            self.issueDate = issueDate
            let terms = customer?.paymentTermsDays ?? 30
            self.dueDate = dueDate ?? Calendar.current.date(byAdding: .day, value: terms, to: issueDate) ?? issueDate
        }

        public var status: InvoiceStatus {
            get { InvoiceStatus(rawValue: statusRaw) ?? .draft }
            set { statusRaw = newValue.rawValue }
        }

        public var sortedLines: [InvoiceLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var balanceDue: Int64 { total - amountPaid }
        public var isOpen: Bool { status == .sent || status == .partiallyPaid }

        /// Vencida es un estado derivado: emitida, con saldo y pasada la fecha de vencimiento.
        public func daysOverdue(asOf date: Date = Date(), calendar: Calendar = .current) -> Int? {
            guard isOpen, balanceDue > 0 else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: date)).day ?? 0
            return days > 0 ? days : nil
        }

        /// Subtotal provisional (borradores) a partir de las líneas.
        public var linesSubtotal: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }
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

        public var invoice: Invoice?

        public init(details: String, quantity: Decimal = 1, unitPrice: Int64, isTaxable: Bool = true, incomeAccountID: UUID?, order: Int = 0) {
            self.details = details
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.isTaxable = isTaxable
            self.incomeAccountID = incomeAccountID
            self.order = order
        }

        /// Cantidad × precio, redondeado a centavos.
        public var amount: Int64 {
            Money(decimal: quantity * Money(minorUnits: unitPrice).decimalValue).minorUnits
        }
    }

    @Model
    public final class InvoiceTaxLine {
        public var id: UUID = UUID()
        public var taxRateID: UUID?
        public var name: String = ""
        public var rateMillionths: Int64 = 0
        public var taxableBase: Int64 = 0
        public var amount: Int64 = 0

        public var invoice: Invoice?

        public init(taxRateID: UUID?, name: String, rateMillionths: Int64, taxableBase: Int64, amount: Int64) {
            self.taxRateID = taxRateID
            self.name = name
            self.rateMillionths = rateMillionths
            self.taxableBase = taxableBase
            self.amount = amount
        }
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

        public var customer: Customer?
        @Relationship(deleteRule: .cascade, inverse: \PaymentApplication.payment)
        public var applications: [PaymentApplication]? = []

        public init(customer: Customer?, date: Date, amount: Int64, method: PaymentMethod, depositAccountID: UUID?) {
            self.customer = customer
            self.date = date
            self.amount = amount
            self.methodRaw = method.rawValue
            self.depositAccountID = depositAccountID
        }
    }

    @Model
    public final class PaymentApplication {
        public var id: UUID = UUID()
        public var amount: Int64 = 0

        public var payment: PaymentReceived?
        public var invoice: Invoice?

        public init(amount: Int64, invoice: Invoice) {
            self.amount = amount
            self.invoice = invoice
        }
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

        public var vendor: Vendor?
        @Relationship(deleteRule: .cascade, inverse: \BillLine.bill)
        public var lines: [BillLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \BillPayment.bill)
        public var payments: [BillPayment]? = []
        @Relationship(deleteRule: .cascade, inverse: \Attachment.bill)
        public var attachments: [Attachment]? = []

        public init(vendor: Vendor?, vendorNumber: String, billDate: Date = Date(), dueDate: Date? = nil) {
            self.vendor = vendor
            self.vendorNumber = vendorNumber
            self.billDate = billDate
            let terms = vendor?.paymentTermsDays ?? 30
            self.dueDate = dueDate ?? Calendar.current.date(byAdding: .day, value: terms, to: billDate) ?? billDate
        }

        public var status: BillStatus {
            get { BillStatus(rawValue: statusRaw) ?? .open }
            set { statusRaw = newValue.rawValue }
        }

        public var sortedLines: [BillLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var balanceDue: Int64 { total - amountPaid }
        public var isOpen: Bool { status == .open || status == .partiallyPaid }
    }

    @Model
    public final class BillLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0

        public var bill: Bill?

        public init(details: String, amount: Int64, accountID: UUID?, order: Int = 0) {
            self.details = details
            self.amount = amount
            self.accountID = accountID
            self.order = order
        }
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

        public var bill: Bill?

        public init(bill: Bill, date: Date, amount: Int64, method: PaymentMethod, paymentAccountID: UUID?) {
            self.bill = bill
            self.date = date
            self.amount = amount
            self.methodRaw = method.rawValue
            self.paymentAccountID = paymentAccountID
        }
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

        public var vendor: Vendor?
        @Relationship(deleteRule: .cascade, inverse: \ExpenseLine.expense)
        public var lines: [ExpenseLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \Attachment.expense)
        public var attachments: [Attachment]? = []

        public init(date: Date = Date(), payee: String, paymentAccountID: UUID?, vendor: Vendor? = nil) {
            self.date = date
            self.payee = payee
            self.paymentAccountID = paymentAccountID
            self.vendor = vendor
        }

        public var sortedLines: [ExpenseLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var isPosted: Bool { journalEntryID != nil }
    }

    @Model
    public final class ExpenseLine {
        public var id: UUID = UUID()
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0

        public var expense: Expense?

        public init(details: String, amount: Int64, accountID: UUID?, order: Int = 0) {
            self.details = details
            self.amount = amount
            self.accountID = accountID
            self.order = order
        }
    }

    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        public var filename: String = ""
        public var contentType: String = ""
        @Attribute(.externalStorage) public var data: Data?
        public var createdAt: Date = Date()

        public var expense: Expense?
        public var bill: Bill?

        public init(filename: String, contentType: String, data: Data?) {
            self.filename = filename
            self.contentType = contentType
            self.data = data
        }
    }

    @Model
    public final class TaxAgency {
        public var id: UUID = UUID()
        public var name: String = ""
        public var filingFrequencyRaw: String = FilingFrequency.quarterly.rawValue
        /// Subcuenta de Sales Tax Payable donde se acumula lo cobrado para esta agencia.
        public var liabilityAccountID: UUID?
        public var isArchived: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \TaxRate.agency)
        public var rates: [TaxRate]? = []

        public init(name: String, filingFrequency: FilingFrequency = .quarterly, liabilityAccountID: UUID?) {
            self.name = name
            self.filingFrequencyRaw = filingFrequency.rawValue
            self.liabilityAccountID = liabilityAccountID
        }
    }

    @Model
    public final class TaxRate {
        public var id: UUID = UUID()
        public var name: String = ""
        public var rateMillionths: Int64 = 0
        public var effectiveFrom: Date?
        public var effectiveTo: Date?
        public var isArchived: Bool = false

        public var agency: TaxAgency?
        @Relationship(deleteRule: .nullify, inverse: \TaxGroup.rates)
        public var groups: [TaxGroup]? = []

        public init(name: String, rateMillionths: Int64, agency: TaxAgency?) {
            self.name = name
            self.rateMillionths = rateMillionths
            self.agency = agency
        }

        public var percent: Decimal { Decimal(rateMillionths) / 10_000 }

        public func isEffective(on date: Date) -> Bool {
            !isArchived && (effectiveFrom.map { $0 <= date } ?? true) && (effectiveTo.map { date <= $0 } ?? true)
        }
    }

    @Model
    public final class TaxGroup {
        public var id: UUID = UUID()
        public var name: String = ""
        public var isArchived: Bool = false

        public var rates: [TaxRate]? = []

        public init(name: String, rates: [TaxRate]) {
            self.name = name
            self.rates = rates
        }

        public var combinedRateMillionths: Int64 { (rates ?? []).reduce(0) { $0 + $1.rateMillionths } }
        public var percent: Decimal { Decimal(combinedRateMillionths) / 10_000 }
    }

    @Model
    public final class NumberSequence {
        public var id: UUID = UUID()
        public var kindRaw: String = DocumentKind.invoice.rawValue
        public var prefix: String = ""
        public var nextNumber: Int = 1
        public var minimumDigits: Int = 4

        public init(kind: DocumentKind, prefix: String, nextNumber: Int = 1, minimumDigits: Int = 4) {
            self.kindRaw = kind.rawValue
            self.prefix = prefix
            self.nextNumber = nextNumber
            self.minimumDigits = minimumDigits
        }

        public func format(_ number: Int) -> String {
            let digits = String(number)
            return prefix + String(repeating: "0", count: max(0, minimumDigits - digits.count)) + digits
        }
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

        public init(actor: String, entityName: String, entityID: UUID?, action: String, summary: String) {
            self.actor = actor
            self.entityName = entityName
            self.entityID = entityID
            self.action = action
            self.summary = summary
        }
    }
}
