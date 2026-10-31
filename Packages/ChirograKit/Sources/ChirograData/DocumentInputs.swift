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
    }

    public var customer: Customer?
    public var issueDate: Date
    public var dueDate: Date
    public var taxGroupID: UUID?
    public var discount: Int64
    public var customerMessage: String
    public var lines: [Line]

    public init(customer: Customer?, issueDate: Date, dueDate: Date, taxGroupID: UUID? = nil, discount: Int64 = 0,
                customerMessage: String = "", lines: [Line]) {
        self.discount = discount
        self.customer = customer
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.taxGroupID = taxGroupID
        self.customerMessage = customerMessage
        self.lines = lines
    }
}
