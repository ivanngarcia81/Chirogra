import ChirograCore
import Foundation
import SwiftData

// Modelos del esquema 4 (docs/DATOS-V4.md), los que usa la app por los `typealias` de `SchemaV4.swift`. Vienen de los
// del esquema 2/3 con lo que añade el 4: `companyID` en todos salvo `Company` y los campos nuevos (marcados
// «Esquema 4»). Reglas de siempre (DISEÑO §5.1), y las de CloudKit en Producción (7-nov-2026):
// - todas las propiedades tienen valor por defecto u son opcionales y todas las relaciones son opcionales con inversa;
// - sin `@Attribute(.unique)` ni `.deny`; el dinero en `Int64` de centavos; los enums como `String` (`…Raw`);
// - **solo añadir**: nunca renombrar (ni con `originalName`) ni reutilizar un nombre; nada de nombres reservados por
//   Core Data en CloudKit (`entityName`, `description`, `recordName`… ver `CloudKitSchemaTests`).
// Los esquemas anteriores están congelados en `SchemaV1.swift`, `SchemaV2.swift` y `SchemaV3.swift`.

extension SchemaV4 {

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

        // MARK: Esquema 4
        /// Orden en el selector de empresas (de menor a mayor; a igualdad, la más antigua primero).
        public var sortOrder: Int = 0
        /// Archivada: no sale en el selector ni cuenta para el límite del plan; sus libros siguen ahí (`archiveCompany`).
        public var isArchived: Bool = false
        public var archivedAt: Date?
        /// Código postal del negocio (ZIP, 5 dígitos): con origen (`SalesTaxSourcing.origin`) decide la tasa sugerida.
        public var postalCode: String = ""
        /// Enlace de pago propio (Stripe Payment Link, PayPal.me, Square…) para «Pagar ahora» y el QR de la factura.
        /// Admite `{amount}`, `{number}` y `{customer}` (`Bookkeeper.paymentLink(for:)`). Vacío = sin enlace.
        public var paymentLinkURL: String = ""
        /// Instrucciones de pago que se imprimen en la factura (transferencia, Zelle, cheque…).
        public var paymentInstructions: String = ""
        /// Mostrar «Pagar ahora» y el QR en el PDF y el correo de la factura (si hay enlace).
        public var showPayNowOnInvoice: Bool = true

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

        /// Nombre para listas y el selector: el comercial o, si no hay, el legal.
        public var name: String { displayName.isEmpty ? legalName : displayName }
    }

    @Model
    public final class Account {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: línea del formulario de impuestos (`TaxFormLine.id`, p. ej. «scheduleC:22»), `TaxFormCatalog.none`
        /// para excluirla, o vacío = la sugerida por el código de la cuenta (`TaxFormCatalog.defaultLine`).
        public var taxFormLineRaw: String = ""

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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var debit: Int64 = 0
        public var credit: Int64 = 0
        public var memo: String = ""
        public var order: Int = 0
        public var customerID: UUID?
        public var vendorID: UUID?
        /// Esquema 4: conciliación en la que se marcó la línea (`Reconciliation.id`) y cuándo. Las líneas de una
        /// conciliación terminada no se revierten sin `Bookkeeper.allowingReconciledChanges()`.
        public var reconciliationID: UUID?
        public var clearedAt: Date?

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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: código postal de entrega (ZIP), para sugerir la tasa de sales tax con destino.
        public var postalCode: String = ""

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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Un borrador no se debe nada todavía, aunque guarde su total provisional.
        public var balanceDue: Int64 { status == .draft ? 0 : total - amountPaid - creditsApplied }
        public var isOpen: Bool { status == .sent || status == .partiallyPaid }

        /// Vencida es un estado derivado: emitida, con saldo y pasada la fecha de vencimiento.
        public func daysOverdue(asOf date: Date = Date(), calendar: Calendar = .current) -> Int? {
            guard isOpen, balanceDue > 0 else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: date)).day ?? 0
            return days > 0 ? days : nil
        }

        /// Subtotal provisional (borradores) a partir de las líneas.
        public var linesSubtotal: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }

        /// Importe provisional de un borrador: el total con impuesto que guarda `Bookkeeper.saveDraft`; si aún no lo
        /// tiene (borradores de antes), líneas menos descuento.
        public var draftAmount: Int64 { total != 0 ? total : linesSubtotal - discount }

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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
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
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var date: Date = Date()
        public var actor: String = ""
        /// La entidad a la que se refiere el evento («Company», «Invoice»…). En el esquema 2 era `entityName`, que
        /// chocaba con `CD_entityName` en CloudKit (`SchemaV3.swift`).
        public var subjectEntity: String = ""
        public var entityID: UUID?
        public var action: String = ""
        public var summary: String = ""

        public init(actor: String, entityName: String, entityID: UUID?, action: String, summary: String) {
            self.actor = actor
            self.subjectEntity = entityName
            self.entityID = entityID
            self.action = action
            self.summary = summary
        }
    }
}
