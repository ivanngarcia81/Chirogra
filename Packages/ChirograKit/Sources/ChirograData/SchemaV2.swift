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
//
// Esquema 2.0.0 (docs/DATOS-V2.md): solo cambios aditivos sobre `SchemaV1` (propiedades nuevas con valor por
// defecto u opcionales, modelos nuevos con relaciones opcionales), así que la migración es ligera y CloudKit
// la admite. `SchemaV1` queda congelado en `SchemaV1.swift`; la app usa los modelos de aquí por los `typealias`.

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

public enum ChirograMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    public static var stages: [MigrationStage] { [migrateV1toV2] }

    /// Ligera: SwiftData/Core Data añade las columnas y tablas nuevas con sus valores por defecto.
    public static var migrateV1toV2: MigrationStage { .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) }
}

public typealias Company = SchemaV2.Company
public typealias Account = SchemaV2.Account
public typealias JournalEntry = SchemaV2.JournalEntry
public typealias JournalLine = SchemaV2.JournalLine
public typealias Customer = SchemaV2.Customer
public typealias Vendor = SchemaV2.Vendor
public typealias Item = SchemaV2.Item
public typealias Invoice = SchemaV2.Invoice
public typealias InvoiceLine = SchemaV2.InvoiceLine
public typealias InvoiceTaxLine = SchemaV2.InvoiceTaxLine
public typealias CreditNote = SchemaV2.CreditNote
public typealias CreditApplication = SchemaV2.CreditApplication
public typealias PaymentReceived = SchemaV2.PaymentReceived
public typealias PaymentApplication = SchemaV2.PaymentApplication
public typealias Bill = SchemaV2.Bill
public typealias BillLine = SchemaV2.BillLine
public typealias BillPayment = SchemaV2.BillPayment
public typealias Expense = SchemaV2.Expense
public typealias ExpenseLine = SchemaV2.ExpenseLine
public typealias Attachment = SchemaV2.Attachment
public typealias TaxAgency = SchemaV2.TaxAgency
public typealias TaxRate = SchemaV2.TaxRate
public typealias TaxGroup = SchemaV2.TaxGroup
public typealias NumberSequence = SchemaV2.NumberSequence
public typealias AuditEvent = SchemaV2.AuditEvent
public typealias RecurringTemplate = SchemaV2.RecurringTemplate
public typealias RecurringTemplateLine = SchemaV2.RecurringTemplateLine
public typealias CustomerNote = SchemaV2.CustomerNote
public typealias InvoiceEvent = SchemaV2.InvoiceEvent
public typealias Estimate = SchemaV2.Estimate
public typealias EstimateLine = SchemaV2.EstimateLine
public typealias PeriodClose = SchemaV2.PeriodClose
public typealias NoticeState = SchemaV2.NoticeState

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
    /// Nuevo en el esquema 2: serie `E-0001` de los estimados.
    case estimate

    /// Prefijo y dígitos con que se crea la serie si aún no existe (p. ej. empresas dadas de alta con el esquema 1).
    public var defaultFormat: (prefix: String, firstNumber: Int, minimumDigits: Int) {
        switch self {
        case .journalEntry: ("", 1, 1)
        case .invoice: ("F-", 1001, 4)
        case .creditNote: ("NC-", 1, 4)
        case .estimate: ("E-", 1, 4)
        }
    }
}

public enum FilingFrequency: String, CaseIterable, Sendable, Codable {
    case monthly, quarterly, annual
}

// MARK: Nuevos en el esquema 2

/// Cada cuánto se repite una plantilla recurrente.
public enum RecurrenceFrequency: String, CaseIterable, Sendable, Codable {
    case weekly, monthly, quarterly, annual

    /// Unidad y número de unidades entre dos repeticiones.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .annual: (.year, 1)
        }
    }
}

/// Qué documento genera una plantilla recurrente.
public enum RecurringKind: String, CaseIterable, Sendable, Codable {
    /// Gasto pagado al momento (`Expense`).
    case expense
    /// Factura por pagar (`Bill`).
    case bill
}

/// Estado guardado de un estimado. «Vencido» también se deriva (`Estimate.effectiveStatus(asOf:)`).
public enum EstimateStatus: String, CaseIterable, Sendable, Codable {
    case draft, sent, accepted, declined, expired, converted
}

/// Tipo de evento en el historial de envíos de una factura.
public enum InvoiceEventKind: String, CaseIterable, Sendable, Codable {
    case sent, reminder
}

/// Regla de origen del sales tax (informativa en el MVP: la tasa la elige el usuario, DISEÑO §4.8).
public enum SalesTaxSourcing: String, CaseIterable, Sendable, Codable {
    /// Se cobra la tasa del lugar del negocio (p. ej. Texas para ventas dentro del estado).
    case origin
    /// Se cobra la tasa del lugar de entrega.
    case destination
}

/// Estilo de la plantilla de factura (canvas `AjustesPlantilla`).
public enum InvoiceStyle: String, CaseIterable, Sendable, Codable {
    case classic, compact
}

/// Colores de acento predefinidos de la plantilla de factura (canvas `AjustesPlantilla`).
/// En `Company.invoiceAccentHex` se guarda el hexadecimal, así que también cabe un color libre.
public enum InvoiceAccent: String, CaseIterable, Sendable {
    case ink, graphite, copper, petroleum, forest

    public var hex: String {
        switch self {
        case .ink: "#3A3FD1"
        case .graphite: "#12142B"
        case .copper: "#B4500F"
        case .petroleum: "#0E6A86"
        case .forest: "#2F6B4F"
        }
    }

    /// Fondo suave para cabeceras de tabla en el PDF.
    public var softHex: String {
        switch self {
        case .ink: "#E7E8FB"
        case .graphite: "#ECEEF5"
        case .copper: "#FCEBDD"
        case .petroleum: "#DCEFF5"
        case .forest: "#E1F0E7"
        }
    }

    public init?(hex: String) {
        guard let match = Self.allCases.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) else { return nil }
        self = match
    }
}

// MARK: - Modelos

extension SchemaV2 {

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

        // MARK: Esquema 2
        public var website: String = ""
        /// Condiciones de pago para clientes nuevos (0 = al recibir).
        public var defaultPaymentTermsDays: Int = 30
        /// Impuesto que usan las facturas y estimados nuevos: id de un `TaxGroup` **o** de una `TaxRate`
        /// (una tasa sola cuenta como grupo de un componente; ver `Bookkeeper.taxComponents`).
        public var defaultTaxGroupID: UUID?
        /// Si está activo, el precio de las líneas gravables ya incluye el sales tax y el cálculo lo separa.
        /// Cada factura copia el valor al guardarse (`Invoice.pricesIncludeTax`), así que cambiarlo no toca las emitidas.
        public var pricesIncludeTax: Bool = false
        /// Origen o destino (`SalesTaxSourcing`). Informativo.
        public var salesTaxSourcingRaw: String = SalesTaxSourcing.origin.rawValue
        // Plantilla de factura
        public var invoiceAccentHex: String = InvoiceAccent.ink.hex
        public var invoiceStyleRaw: String = InvoiceStyle.classic.rawValue
        public var invoiceShowLogo: Bool = true
        public var invoiceShowEIN: Bool = false
        public var invoiceShowAddress: Bool = true
        public var invoiceShowPhone: Bool = true
        /// Mensaje al cliente con que nacen las facturas nuevas.
        public var defaultInvoiceMessage: String = ""
        /// Pie / términos que se imprimen al final de cada factura.
        public var invoiceFooter: String = ""
        /// Logo de la empresa (imagen) para facturas y estimados.
        @Relationship(deleteRule: .cascade, inverse: \Attachment.logoOfCompany)
        public var logo: Attachment?
        /// Contraseña de cierre: solo un hash PBKDF2 con sal (`ClosingPassword`), nunca la contraseña. Vacío = sin contraseña.
        public var closingPasswordHash: String = ""

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

        public var salesTaxSourcing: SalesTaxSourcing {
            get { SalesTaxSourcing(rawValue: salesTaxSourcingRaw) ?? .origin }
            set { salesTaxSourcingRaw = newValue.rawValue }
        }

        public var invoiceStyle: InvoiceStyle {
            get { InvoiceStyle(rawValue: invoiceStyleRaw) ?? .classic }
            set { invoiceStyleRaw = newValue.rawValue }
        }

        /// Color predefinido de la plantilla, si el hexadecimal guardado es uno de ellos.
        public var invoiceAccent: InvoiceAccent? { InvoiceAccent(hex: invoiceAccentHex) }

        public var hasClosingPassword: Bool { !closingPasswordHash.isEmpty }
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
        /// Esquema 2: últimos 4 dígitos de la cuenta bancaria o tarjeta, para mostrar «Corriente ••4821». Vacío = sin dígitos.
        public var last4: String = ""

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

        /// «Corriente ••4821» si hay últimos 4 dígitos; si no, el nombre.
        public var maskedName: String { last4.isEmpty ? name : "\(name) ••\(last4)" }

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
        /// Esquema 2: al editar un documento contabilizado (p. ej. un gasto), el asiento nuevo apunta al que sustituye
        /// y el original, ya revertido, al que lo sustituyó.
        public var replacesEntryID: UUID?
        public var replacedByEntryID: UUID?

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
        // MARK: Esquema 2
        /// Persona de contacto y su cargo («Laura Méndez · Gerente»).
        public var contactName: String = ""
        public var contactTitle: String = ""
        /// ID fiscal del cliente (EIN u otro), si lo da.
        public var taxID: String = ""

        @Relationship(deleteRule: .nullify, inverse: \Invoice.customer)
        public var invoices: [Invoice]? = []
        @Relationship(deleteRule: .nullify, inverse: \PaymentReceived.customer)
        public var payments: [PaymentReceived]? = []
        @Relationship(deleteRule: .nullify, inverse: \CreditNote.customer)
        public var creditNotes: [CreditNote]? = []
        /// Notas fechadas (historial de la ficha). `notes` sigue siendo la nota fija.
        @Relationship(deleteRule: .cascade, inverse: \CustomerNote.customer)
        public var datedNotes: [CustomerNote]? = []
        @Relationship(deleteRule: .nullify, inverse: \Estimate.customer)
        public var estimates: [Estimate]? = []
        /// Gastos facturables a este cliente o proyecto.
        @Relationship(deleteRule: .nullify, inverse: \Expense.customer)
        public var billableExpenses: [Expense]? = []

        public init(name: String, email: String = "", paymentTermsDays: Int = 30) {
            self.name = name
            self.email = email
            self.paymentTermsDays = paymentTermsDays
        }

        /// Saldo pendiente de las facturas emitidas.
        public var openBalance: Int64 {
            (invoices ?? []).filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }
        }

        /// Saldo a favor: notas de crédito aún no aplicadas a una factura ni reembolsadas.
        public var creditBalance: Int64 {
            (creditNotes ?? []).reduce(0) { $0 + $1.unappliedAmount }
        }

        public var initials: String {
            Initials.from(name)
        }

        /// «Laura Méndez · Gerente», o solo el nombre si no hay cargo.
        public var contactLine: String {
            [contactName, contactTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        /// Notas fechadas, de la más reciente a la más antigua.
        public var sortedNotes: [CustomerNote] { (datedNotes ?? []).sorted { $0.date > $1.date } }
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
        // MARK: Esquema 2
        /// Formulario W-9 recibido (para el 1099), fecha y copia opcional.
        public var w9Received: Bool = false
        public var w9ReceivedDate: Date?
        @Relationship(deleteRule: .cascade, inverse: \Attachment.w9OfVendor)
        public var w9Attachment: Attachment?
        /// Pago preferido: método (`PaymentMethod`, vacío = sin preferencia) y cuenta de origen.
        public var preferredPaymentMethodRaw: String = ""
        public var preferredPaymentAccountID: UUID?

        @Relationship(deleteRule: .nullify, inverse: \Bill.vendor)
        public var bills: [Bill]? = []
        @Relationship(deleteRule: .nullify, inverse: \Expense.vendor)
        public var expenses: [Expense]? = []
        @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.vendor)
        public var recurringTemplates: [RecurringTemplate]? = []

        public init(name: String, email: String = "") {
            self.name = name
            self.email = email
        }

        public var openBalance: Int64 {
            (bills ?? []).filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }
        }

        public var preferredPaymentMethod: PaymentMethod? {
            get { PaymentMethod(rawValue: preferredPaymentMethodRaw) }
            set { preferredPaymentMethodRaw = newValue?.rawValue ?? "" }
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
        /// Descuento del documento, antes de impuesto.
        public var discount: Int64 = 0
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var amountPaid: Int64 = 0
        /// Suma de las notas de crédito aplicadas a esta factura.
        public var creditsApplied: Int64 = 0
        public var createdAt: Date = Date()
        // MARK: Esquema 2
        /// Los precios de las líneas gravables ya incluyen el impuesto (copiado de la empresa al crear el borrador).
        /// Entonces `subtotal` es la suma de las líneas con impuesto y `total = subtotal − discount`.
        public var pricesIncludeTax: Bool = false
        /// Estimado del que salió la factura, si lo hay.
        public var estimateID: UUID?

        public var customer: Customer?
        @Relationship(deleteRule: .nullify, inverse: \CreditNote.invoice)
        public var creditNotes: [CreditNote]? = []
        /// Notas de crédito (de esta factura o saldo a favor de otras) aplicadas a su saldo.
        @Relationship(deleteRule: .nullify, inverse: \CreditApplication.invoice)
        public var creditApplications: [CreditApplication]? = []
        @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
        public var lines: [InvoiceLine]? = []
        @Relationship(deleteRule: .cascade, inverse: \InvoiceTaxLine.invoice)
        public var taxLines: [InvoiceTaxLine]? = []
        @Relationship(deleteRule: .nullify, inverse: \PaymentApplication.invoice)
        public var paymentApplications: [PaymentApplication]? = []
        /// Historial de envíos y recordatorios.
        @Relationship(deleteRule: .cascade, inverse: \InvoiceEvent.invoice)
        public var events: [InvoiceEvent]? = []

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
        public var balanceDue: Int64 { total - amountPaid - creditsApplied }
        public var isOpen: Bool { status == .sent || status == .partiallyPaid }

        /// Vencida es un estado derivado: emitida, con saldo y pasada la fecha de vencimiento.
        public func daysOverdue(asOf date: Date = Date(), calendar: Calendar = .current) -> Int? {
            guard isOpen, balanceDue > 0 else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: date)).day ?? 0
            return days > 0 ? days : nil
        }

        /// Subtotal provisional (borradores) a partir de las líneas.
        public var linesSubtotal: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }

        /// Importe provisional de un borrador: líneas menos descuento, sin impuesto.
        public var draftAmount: Int64 { linesSubtotal - discount }

        /// Envíos y recordatorios, del más reciente al más antiguo.
        public var sortedEvents: [InvoiceEvent] { (events ?? []).sorted { $0.date > $1.date } }
        public var lastSentDate: Date? { sortedEvents.first { $0.kind == .sent }?.date }
        public var lastReminderDate: Date? { sortedEvents.first { $0.kind == .reminder }?.date }
        /// Ventas netas sin impuesto (subtotal − descuento, sin el impuesto incluido en los precios).
        public var netSales: Int64 { subtotal - discount - (pricesIncludeTax ? taxTotal : 0) }
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

    /// Nota de crédito contra una factura emitida (DISEÑO §4.3): revierte ingreso e impuesto y reduce lo que se debe.
    @Model
    public final class CreditNote {
        public var id: UUID = UUID()
        public var number: String = ""
        public var date: Date = Date()
        public var reason: String = ""
        /// Importe neto acreditado, antes de impuesto.
        public var amount: Int64 = 0
        public var isTaxable: Bool = true
        public var incomeAccountID: UUID?
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        /// Parte del total que queda como saldo a favor del cliente (no aplicada ni reembolsada).
        public var unappliedAmount: Int64 = 0
        public var refundedAmount: Int64 = 0
        public var journalEntryID: UUID?
        public var createdAt: Date = Date()

        public var customer: Customer?
        /// Factura de origen de la nota.
        public var invoice: Invoice?
        @Relationship(deleteRule: .cascade, inverse: \CreditApplication.note)
        public var applications: [CreditApplication]? = []

        public init(invoice: Invoice, date: Date, amount: Int64, isTaxable: Bool, reason: String) {
            self.invoice = invoice
            self.customer = invoice.customer
            self.date = date
            self.amount = amount
            self.isTaxable = isTaxable
            self.reason = reason
        }
    }

    /// Aplicación de (parte de) una nota de crédito al saldo de una factura. No genera asiento:
    /// el saldo a favor y la factura viven en la misma cuenta por cobrar.
    @Model
    public final class CreditApplication {
        public var id: UUID = UUID()
        public var date: Date = Date()
        public var amount: Int64 = 0

        public var note: CreditNote?
        public var invoice: Invoice?

        public init(note: CreditNote, invoice: Invoice, amount: Int64, date: Date) {
            self.note = note
            self.invoice = invoice
            self.amount = amount
            self.date = date
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
        // MARK: Esquema 2
        /// Pago programado: fecha, cuenta de origen y método (`PaymentMethod`). Chirogra lo recuerda y lo registra
        /// cuando se pide (`Bookkeeper.payScheduledBills`); el dinero lo mueve el banco.
        public var scheduledPaymentDate: Date?
        public var scheduledPaymentAccountID: UUID?
        public var scheduledPaymentMethodRaw: String = ""
        /// Cargo automático: el pago programado se registra solo (`Bookkeeper.runAutomations`). Lo pone una plantilla recurrente.
        public var autoPay: Bool = false
        /// Plantilla recurrente que generó la factura y fecha de la repetición (clave de idempotencia).
        public var recurringTemplateID: UUID?
        public var recurrenceDate: Date?

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

        public var isScheduled: Bool { scheduledPaymentDate != nil && isOpen }
        public var scheduledPaymentMethod: PaymentMethod? { PaymentMethod(rawValue: scheduledPaymentMethodRaw) }
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
        // MARK: Esquema 2
        /// Sales tax pagado incluido en el total (informativo: en EE. UU. es parte del gasto y no cambia el asiento).
        public var salesTaxIncluded: Int64 = 0
        /// Cliente o proyecto al que se puede refacturar (gasto facturable).
        public var customer: Customer?
        /// Plantilla recurrente que generó el gasto y fecha de la repetición (clave de idempotencia).
        public var recurringTemplateID: UUID?
        public var recurrenceDate: Date?
        /// Veces que se editó ya contabilizado (cada edición = reversión + asiento nuevo).
        public var revision: Int = 0
        /// Anulado: su asiento se revirtió y ya no cuenta.
        public var voidedAt: Date?

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
        public var isVoid: Bool { voidedAt != nil }
        public var isBillable: Bool { customer != nil }
        public var method: PaymentMethod {
            get { PaymentMethod(rawValue: methodRaw) ?? .card }
            set { methodRaw = newValue.rawValue }
        }
        /// Importe antes del sales tax incluido (solo para mostrar).
        public var subtotalBeforeTax: Int64 { total - salesTaxIncluded }
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
        // Esquema 2
        public var w9OfVendor: Vendor?
        public var logoOfCompany: Company?

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
