import ChirograCore
import Foundation

/// Datos de un borrador de factura tal como los edita el usuario, antes de guardarlos en el modelo.
@MainActor
public struct InvoiceDraftInput {
    public struct Line: Sendable {
        public var details: String
        public var quantity: Decimal
        public var unitPrice: Int64
        public var isTaxable: Bool
        public var incomeAccountID: UUID?

        public init(details: String, quantity: Decimal = 1, unitPrice: Int64, isTaxable: Bool = true, incomeAccountID: UUID?) {
            self.details = details
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.isTaxable = isTaxable
            self.incomeAccountID = incomeAccountID
        }

        /// Cantidad × precio, redondeado a centavos (como `InvoiceLine.amount`).
        public var amount: Int64 { Money(decimal: quantity * Money(minorUnits: unitPrice).decimalValue).minorUnits }
    }

    public var customer: Customer?
    public var issueDate: Date
    public var dueDate: Date
    public var taxGroupID: UUID?
    public var discount: Int64
    public var customerMessage: String
    public var lines: [Line]
    /// Esquema 2: `nil` = la factura nueva toma el ajuste de la empresa y una existente conserva el suyo.
    public var pricesIncludeTax: Bool?

    public init(customer: Customer?, issueDate: Date, dueDate: Date, taxGroupID: UUID? = nil, discount: Int64 = 0,
                customerMessage: String = "", lines: [Line], pricesIncludeTax: Bool? = nil) {
        self.discount = discount
        self.customer = customer
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.taxGroupID = taxGroupID
        self.customerMessage = customerMessage
        self.lines = lines
        self.pricesIncludeTax = pricesIncludeTax
    }
}

/// Valores con que nace una factura o un estimado nuevo para un cliente (`Bookkeeper.newInvoiceDefaults(for:)`).
public struct NewInvoiceDefaults: Sendable {
    /// Grupo o tasa: el del cliente, o el predeterminado de la empresa; `nil` si el cliente está exento.
    public var taxGroupID: UUID?
    public var dueDate: Date
    public var customerMessage: String
    public var pricesIncludeTax: Bool
}

/// Datos de un gasto tal como los edita el usuario (alta y edición, también ya contabilizado).
@MainActor
public struct ExpenseInput {
    public struct Line: Sendable, Equatable {
        public var details: String
        public var amount: Int64
        public var accountID: UUID?

        public init(details: String = "", amount: Int64, accountID: UUID?) {
            self.details = details
            self.amount = amount
            self.accountID = accountID
        }
    }

    public var date: Date
    public var payee: String
    public var vendor: Vendor?
    /// Cliente o proyecto al que se puede refacturar.
    public var customer: Customer?
    public var paymentAccountID: UUID?
    public var method: PaymentMethod
    public var reference: String
    public var memo: String
    /// Sales tax incluido en el total (informativo).
    public var salesTaxIncluded: Int64
    public var lines: [Line]

    public init(date: Date, payee: String, vendor: Vendor? = nil, customer: Customer? = nil, paymentAccountID: UUID?,
                method: PaymentMethod = .card, reference: String = "", memo: String = "", salesTaxIncluded: Int64 = 0, lines: [Line]) {
        self.date = date
        self.payee = payee
        self.vendor = vendor
        self.customer = customer
        self.paymentAccountID = paymentAccountID
        self.method = method
        self.reference = reference
        self.memo = memo
        self.salesTaxIncluded = salesTaxIncluded
        self.lines = lines
    }

    /// Los datos actuales de un gasto, para precargar el editor.
    public init(_ expense: Expense) {
        self.init(date: expense.date, payee: expense.payee, vendor: expense.vendor, customer: expense.customer,
                  paymentAccountID: expense.paymentAccountID, method: expense.method, reference: expense.reference,
                  memo: expense.memo, salesTaxIncluded: expense.salesTaxIncluded,
                  lines: expense.sortedLines.map { Line(details: $0.details, amount: $0.amount, accountID: $0.accountID) })
    }

    public var total: Int64 { lines.reduce(0) { $0 + $1.amount } }
}

/// Datos de un estimado tal como los edita el usuario.
@MainActor
public struct EstimateInput {
    public var customer: Customer?
    public var title: String
    public var issueDate: Date
    public var expirationDate: Date
    public var taxGroupID: UUID?
    public var discount: Int64
    public var customerMessage: String
    public var memo: String
    public var lines: [InvoiceDraftInput.Line]
    /// `nil` = el estimado nuevo toma el ajuste de la empresa y uno existente conserva el suyo.
    public var pricesIncludeTax: Bool?

    public init(customer: Customer?, title: String = "", issueDate: Date, expirationDate: Date, taxGroupID: UUID? = nil,
                discount: Int64 = 0, customerMessage: String = "", memo: String = "", lines: [InvoiceDraftInput.Line],
                pricesIncludeTax: Bool? = nil) {
        self.customer = customer
        self.title = title
        self.issueDate = issueDate
        self.expirationDate = expirationDate
        self.taxGroupID = taxGroupID
        self.discount = discount
        self.customerMessage = customerMessage
        self.memo = memo
        self.lines = lines
        self.pricesIncludeTax = pricesIncludeTax
    }
}

/// Qué parte de un estimado pasa a la factura (canvas `Estimado`: todo, anticipo o líneas elegidas).
public enum EstimateConversion: Sendable, Equatable {
    /// Todo lo que queda por facturar.
    case all
    /// Un porcentaje (p. ej. 50 = anticipo del 50 %) de cada línea, sin pasar de lo que queda.
    case percent(Decimal)
    /// Lo que queda de las líneas elegidas.
    case lines([UUID])
}

/// Datos de una plantilla recurrente tal como los edita el usuario.
@MainActor
public struct RecurringTemplateInput {
    public var name: String
    public var kind: RecurringKind
    public var vendor: Vendor?
    public var payee: String
    public var memo: String
    public var lines: [ExpenseInput.Line]
    /// Gasto: cuenta de pago. Factura: cuenta de origen del pago automático.
    public var paymentAccountID: UUID?
    public var method: PaymentMethod
    public var frequency: RecurrenceFrequency
    public var startDate: Date
    public var endDate: Date?
    public var autoCharge: Bool
    public var isActive: Bool
    public var billTermsDays: Int

    public init(name: String, kind: RecurringKind, vendor: Vendor? = nil, payee: String = "", memo: String = "",
                lines: [ExpenseInput.Line], paymentAccountID: UUID?, method: PaymentMethod = .card,
                frequency: RecurrenceFrequency = .monthly, startDate: Date, endDate: Date? = nil,
                autoCharge: Bool = false, isActive: Bool = true, billTermsDays: Int = 30) {
        self.name = name
        self.kind = kind
        self.vendor = vendor
        self.payee = payee
        self.memo = memo
        self.lines = lines
        self.paymentAccountID = paymentAccountID
        self.method = method
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.autoCharge = autoCharge
        self.isActive = isActive
        self.billTermsDays = billTermsDays
    }
}

/// Cambios a una cuenta del plan (`Bookkeeper.updateAccount`).
public struct AccountInput: Sendable {
    public var code: String
    public var name: String
    public var subtype: AccountSubtype
    public var details: String
    /// Cuenta principal (`nil` = de primer nivel).
    public var parentID: UUID?
    /// Últimos 4 dígitos (vacío o exactamente 4 dígitos).
    public var last4: String

    public init(code: String, name: String, subtype: AccountSubtype, details: String = "", parentID: UUID? = nil, last4: String = "") {
        self.code = code
        self.name = name
        self.subtype = subtype
        self.details = details
        self.parentID = parentID
        self.last4 = last4
    }
}
