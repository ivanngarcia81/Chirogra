import ChirograCore
import Foundation
import SwiftData

// Modelos que añadió el esquema 2 (docs/DATOS-V2.md), en su forma del esquema 4. Mismas reglas que el resto (ver
// `SchemaV4Models.swift`):
// valores por defecto en todo, relaciones opcionales con inversa, sin `.unique`, dinero en centavos.

extension SchemaV4 {

    /// Plantilla de gasto o factura por pagar que se repite (canvas `MacGastoNuevo`, `MacPorPagar`).
    /// `Bookkeeper.generateRecurring(through:)` crea lo que toque; cada documento generado guarda
    /// `recurringTemplateID` y `recurrenceDate`, que son la clave para no duplicar.
    @Model
    public final class RecurringTemplate {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        /// Nombre para listas («Renta del taller»).
        public var name: String = ""
        public var kindRaw: String = RecurringKind.expense.rawValue
        /// Beneficiario que se escribe en el gasto (si hay proveedor y queda vacío, se usa su nombre).
        public var payee: String = ""
        public var memo: String = ""
        public var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
        /// Primera repetición; las siguientes se calculan desde aquí (31 ene → 28 feb → 31 mar).
        public var startDate: Date = Date()
        /// Próxima repetición pendiente de generar.
        public var nextDate: Date = Date()
        /// Última repetición que puede generarse (incluida). `nil` = sin fin.
        public var endDate: Date?
        /// Activa o en pausa.
        public var isActive: Bool = true
        /// Cargo automático: el gasto se registra solo (con asiento); en una factura por pagar, su pago queda
        /// programado al vencimiento y se registra solo (`Bill.autoPay`). Sin cargo automático, el gasto se crea
        /// sin asiento («por confirmar») y la factura queda registrada sin pago programado.
        public var autoCharge: Bool = false
        /// Cuenta de pago (gasto) o cuenta de origen del pago automático (factura), y método (`PaymentMethod`).
        public var paymentAccountID: UUID?
        public var methodRaw: String = PaymentMethod.card.rawValue
        /// Días hasta el vencimiento de cada factura por pagar generada.
        public var billTermsDays: Int = 30
        /// Fecha de la última repetición generada y momento en que se generó.
        public var lastGeneratedDate: Date?
        public var lastRunAt: Date?
        public var createdAt: Date = Date()

        public var vendor: Vendor?
        @Relationship(deleteRule: .cascade, inverse: \RecurringTemplateLine.template)
        public var lines: [RecurringTemplateLine]? = []

        public init(name: String, kind: RecurringKind, frequency: RecurrenceFrequency, startDate: Date) {
            self.name = name
            self.kindRaw = kind.rawValue
            self.frequencyRaw = frequency.rawValue
            self.startDate = startDate
            self.nextDate = startDate
        }

        public var kind: RecurringKind {
            get { RecurringKind(rawValue: kindRaw) ?? .expense }
            set { kindRaw = newValue.rawValue }
        }

        public var frequency: RecurrenceFrequency {
            get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
            set { frequencyRaw = newValue.rawValue }
        }

        public var method: PaymentMethod {
            get { PaymentMethod(rawValue: methodRaw) ?? .card }
            set { methodRaw = newValue.rawValue }
        }

        public var sortedLines: [RecurringTemplateLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var total: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }

        /// Ya no quedan repeticiones (pasó la fecha final).
        public var isFinished: Bool { endDate.map { nextDate > $0 } ?? false }

        /// Repetición número `n` (0 = `startDate`), anclada al inicio para no arrastrar el día del mes.
        public func occurrence(_ n: Int, calendar: Calendar = .current) -> Date {
            let step = frequency.step
            return calendar.date(byAdding: step.component, value: step.value * n, to: startDate) ?? startDate
        }

        /// Primera repetición con día posterior a `date`.
        public func occurrence(after date: Date, calendar: Calendar = .current) -> Date {
            let limit = calendar.startOfDay(for: date)
            var n = 0
            while n < 100_000 {
                let candidate = occurrence(n, calendar: calendar)
                if calendar.startOfDay(for: candidate) > limit { return candidate }
                n += 1
            }
            return occurrence(n, calendar: calendar)
        }
    }

    @Model
    public final class RecurringTemplateLine {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var details: String = ""
        public var amount: Int64 = 0
        public var accountID: UUID?
        public var order: Int = 0

        public var template: RecurringTemplate?

        public init(details: String, amount: Int64, accountID: UUID?, order: Int = 0) {
            self.details = details
            self.amount = amount
            self.accountID = accountID
            self.order = order
        }
    }

    /// Nota fechada en la ficha del cliente (canvas `ClienteFicha`: «22 oct · Ana R.»).
    @Model
    public final class CustomerNote {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var date: Date = Date()
        public var text: String = ""
        /// Quién la escribió (el `actor` del `Bookkeeper`).
        public var author: String = ""
        public var createdAt: Date = Date()

        public var customer: Customer?

        public init(customer: Customer?, date: Date, text: String, author: String = "") {
            self.customer = customer
            self.date = date
            self.text = text
            self.author = author
        }
    }

    /// Envío o recordatorio de una factura (canvas `FacturaEnviar`, `MacClienteFicha`, `MacInicio` «Actividad»).
    @Model
    public final class InvoiceEvent {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var kindRaw: String = InvoiceEventKind.sent.rawValue
        public var date: Date = Date()
        /// Correo o correos de destino, tal como se escribieron en «Para».
        public var recipient: String = ""
        public var subject: String = ""
        public var message: String = ""
        public var createdAt: Date = Date()

        public var invoice: Invoice?

        public init(invoice: Invoice?, kind: InvoiceEventKind, date: Date, recipient: String, subject: String, message: String = "") {
            self.invoice = invoice
            self.kindRaw = kind.rawValue
            self.date = date
            self.recipient = recipient
            self.subject = subject
            self.message = message
        }

        public var kind: InvoiceEventKind { InvoiceEventKind(rawValue: kindRaw) ?? .sent }
    }

    /// Estimado (cotización) al cliente: sin asiento contable. Se convierte en una o varias facturas en borrador
    /// (`Bookkeeper.convertToInvoice`); cada línea lleva la cantidad ya facturada.
    @Model
    public final class Estimate {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        /// Número de la serie `E-` (se asigna al guardar por primera vez).
        public var number: String = ""
        /// Concepto corto («Remodelación del lobby»).
        public var title: String = ""
        public var issueDate: Date = Date()
        /// Válido hasta.
        public var expirationDate: Date = Date()
        public var statusRaw: String = EstimateStatus.draft.rawValue
        public var customerMessage: String = ""
        public var memo: String = ""
        public var taxGroupID: UUID?
        public var discount: Int64 = 0
        /// Parte del descuento que ya pasó a facturas.
        public var discountInvoiced: Int64 = 0
        public var pricesIncludeTax: Bool = false
        // Totales calculados al guardar, para listas.
        public var subtotal: Int64 = 0
        public var taxTotal: Int64 = 0
        public var total: Int64 = 0
        public var sentDate: Date?
        public var acceptedDate: Date?
        /// Quién lo aceptó («Laura Méndez»).
        public var acceptedBy: String = ""
        public var convertedDate: Date?
        public var createdAt: Date = Date()

        public var customer: Customer?
        @Relationship(deleteRule: .cascade, inverse: \EstimateLine.estimate)
        public var lines: [EstimateLine]? = []

        public init(customer: Customer?, issueDate: Date = Date(), expirationDate: Date? = nil) {
            self.customer = customer
            self.issueDate = issueDate
            self.expirationDate = expirationDate ?? Calendar.current.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        }

        public var status: EstimateStatus {
            get { EstimateStatus(rawValue: statusRaw) ?? .draft }
            set { statusRaw = newValue.rawValue }
        }

        /// Estado a mostrar: un estimado enviado cuya validez pasó se ve «vencido».
        public func effectiveStatus(asOf date: Date = Date(), calendar: Calendar = .current) -> EstimateStatus {
            if status == .sent, calendar.startOfDay(for: expirationDate) < calendar.startOfDay(for: date) { return .expired }
            return status
        }

        public var sortedLines: [EstimateLine] { (lines ?? []).sorted { $0.order < $1.order } }
        public var linesSubtotal: Int64 { (lines ?? []).reduce(0) { $0 + $1.amount } }
        /// Importe (antes de impuesto y descuento) de lo que ya se facturó.
        public var invoicedSubtotal: Int64 { (lines ?? []).reduce(0) { $0 + $1.invoicedAmount } }
        public var isFullyInvoiced: Bool { !(lines ?? []).isEmpty && (lines ?? []).allSatisfy { $0.remainingQuantity <= 0 } }
        public var hasInvoices: Bool { (lines ?? []).contains { $0.invoicedQuantity > 0 } }
    }

    @Model
    public final class EstimateLine {
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
        /// Cantidad que ya pasó a facturas (facturación por etapas o anticipos).
        public var invoicedQuantity: Decimal = 0

        public var estimate: Estimate?

        public init(details: String, quantity: Decimal = 1, unitPrice: Int64, isTaxable: Bool = true, incomeAccountID: UUID?, order: Int = 0) {
            self.details = details
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.isTaxable = isTaxable
            self.incomeAccountID = incomeAccountID
            self.order = order
        }

        public var amount: Int64 { Self.amount(quantity: quantity, unitPrice: unitPrice) }
        public var remainingQuantity: Decimal { quantity - invoicedQuantity }
        public var invoicedAmount: Int64 { Self.amount(quantity: invoicedQuantity, unitPrice: unitPrice) }

        static func amount(quantity: Decimal, unitPrice: Int64) -> Int64 {
            Money(decimal: quantity * Money(minorUnits: unitPrice).decimalValue).minorUnits
        }
    }

    /// Una vez que se cerraron o reabrieron los libros (canvas `MacCierre`, «Historial de cierres»).
    @Model
    public final class PeriodClose {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        /// `close` o `reopen`.
        public var actionRaw: String = "close"
        /// Fecha de cierre que quedó vigente (`nil` = libros abiertos).
        public var lockDate: Date?
        /// Fecha de cierre que había antes.
        public var previousLockDate: Date?
        /// Cuándo se hizo.
        public var date: Date = Date()
        /// Quién (actor del `Bookkeeper`) y en qué aparato.
        public var actor: String = ""
        public var device: String = ""
        public var note: String = ""

        public init(isReopen: Bool, lockDate: Date?, previousLockDate: Date?, actor: String, device: String, note: String) {
            self.actionRaw = isReopen ? "reopen" : "close"
            self.lockDate = lockDate
            self.previousLockDate = previousLockDate
            self.actor = actor
            self.device = device
            self.note = note
        }

        public var isReopen: Bool { actionRaw == "reopen" }
    }

    /// Aviso de la campana marcado como leído o descartado. Los avisos se calculan (`Bookkeeper.notices`);
    /// aquí solo se guarda lo que hizo el usuario, por la clave estable del aviso (`Notice.id`).
    @Model
    public final class NoticeState {
        public var id: UUID = UUID()
        /// Esquema 4: empresa a la que pertenece (`Company.id`). `nil` = registro huérfano (de antes de la migración o de
        /// un aparato con una versión anterior): cuenta como de la empresa principal (`Bookkeeper+Companies.swift`).
        public var companyID: UUID?
        public var key: String = ""
        public var isRead: Bool = false
        public var isDismissed: Bool = false
        public var updatedAt: Date = Date()

        public init(key: String) {
            self.key = key
        }
    }
}
