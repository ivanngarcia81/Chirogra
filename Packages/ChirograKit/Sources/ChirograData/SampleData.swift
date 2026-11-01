import ChirograCore
import Foundation
import SwiftData

/// Datos de ejemplo para vistas previas, capturas y el botón "Probar con datos de ejemplo".
/// Todo pasa por `Bookkeeper`, así que los asientos de ejemplo cumplen las mismas reglas que los reales.
@MainActor
public enum SampleData {

    public static func makeContainer(locale: Locale = .current) -> ModelContainer {
        do {
            let container = try ChirograStore.makeContainer(inMemory: true)
            try populate(container.mainContext, locale: locale)
            return container
        } catch {
            fatalError("No se pudieron crear los datos de ejemplo: \(error)")
        }
    }

    /// El plan de cuentas (categorías) y el asiento de apertura salen en el idioma de la app (`locale`);
    /// clientes, proveedores y descripciones son contenido de ejemplo «escrito por el usuario» y no se traducen.
    public static func populate(_ context: ModelContext, today: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = .current) throws {
        let books = Bookkeeper(context: context, actor: "Ejemplo")
        try books.setUpCompany(legalName: "Ríos Diseño & Obra LLC", displayName: "Ríos Diseño & Obra",
                               entityType: .llc, state: "TX", locale: locale)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func account(_ code: String) throws -> Account {
            guard let found = try books.accounts().first(where: { $0.code == code }) else { throw BookkeepingError.unknownAccount }
            return found
        }

        let checking = try account("1010")
        let savings = try account("1020")
        let card = try account("2100")
        let capital = try account("3000")
        let services = try account("4000")
        let materials = try account("4100")

        try books.post(JournalEntryDraft(date: day(-120), memo: String(localized: "Saldos iniciales"), source: .opening, lines: [
            .debit(checking.id, 3_800_000), .debit(savings.id, 950_000), .credit(capital.id, 4_750_000),
        ]))

        // Sales tax de Austin, TX: 6.25 % estatal + 1 % ciudad + 1 % transporte.
        let taxPayable = try books.systemAccount(.salesTaxPayable)
        let comptroller = TaxAgency(name: "Texas Comptroller", filingFrequency: .quarterly, liabilityAccountID: taxPayable.id)
        context.insert(comptroller)
        let rates = [("Texas", 62_500), ("Austin", 10_000), ("Austin MTA", 10_000)].map { name, rate in
            let taxRate = TaxRate(name: name, rateMillionths: Int64(rate), agency: comptroller)
            context.insert(taxRate)
            return taxRate
        }
        let austin = TaxGroup(name: "Austin, TX", rates: rates)
        context.insert(austin)

        let customers = [("Café Aurora", "hola@cafeaurora.com"), ("Hotel Mirador", "compras@hotelmirador.com"),
                         ("Clínica Del Valle", "admin@clinicadelvalle.com")].map { name, email in
            let customer = Customer(name: name, email: email, paymentTermsDays: 15)
            customer.defaultTaxGroupID = austin.id
            context.insert(customer)
            return customer
        }

        func invoice(_ customer: Customer, issued: Int, lines: [(String, Decimal, Int64, Account, Bool)]) throws -> Invoice {
            let invoice = Invoice(customer: customer, issueDate: day(issued))
            invoice.taxGroupID = customer.defaultTaxGroupID
            context.insert(invoice)
            for (index, line) in lines.enumerated() {
                let model = InvoiceLine(details: line.0, quantity: line.1, unitPrice: line.2, isTaxable: line.4,
                                        incomeAccountID: line.3.id, order: index)
                model.invoice = invoice
                context.insert(model)
            }
            try books.issue(invoice)
            return invoice
        }

        let paid = try invoice(customers[0], issued: -40, lines: [("Diseño de interiores · fase 1", 1, 180_000, services, false)])
        try books.recordPayment(for: paid, amount: paid.balanceDue, date: day(-30), depositAccount: checking)
        _ = try invoice(customers[1], issued: -23, lines: [("Remodelación de lobby", 1, 150_000, services, false),
                                                           ("Materiales", 1, 55_427, materials, true)])
        _ = try invoice(customers[2], issued: -18, lines: [("Señalética y mobiliario", 1, 100_000, services, false),
                                                           ("Vinil impreso", 4, 2_310, materials, true)])
        let partial = try invoice(customers[1], issued: -10, lines: [("Diseño de habitaciones", 2, 128_500, services, false)])
        try books.recordPayment(for: partial, amount: 100_000, date: day(-3), depositAccount: checking)
        _ = try invoice(customers[0], issued: -3, lines: [("Rediseño de terraza", 1, 240_000, services, false)])

        let lumber = Vendor(name: "Maderas del Norte", email: "ventas@maderasnorte.com")
        lumber.defaultExpenseAccountID = try account("5000").id
        context.insert(lumber)
        let bill = Bill(vendor: lumber, vendorNumber: "B-221", billDate: day(-12), dueDate: day(9))
        context.insert(bill)
        let billLine = BillLine(details: "Triplay y herrajes", amount: 84_230, accountID: try account("5000").id)
        billLine.bill = bill
        context.insert(billLine)
        try books.record(bill)

        let expenses: [(String, Int, Int64, String, Account)] = [
            ("Renta del taller", -28, 120_000, "6400", checking),
            ("Adobe Creative Cloud", -25, 5_999, "6750", card),
            ("UBER *TRIP", -2, 1_840, "6050", card),
            ("Home Depot", -6, 21_475, "6500", card),
            ("Seguro del vehículo", -14, 31_000, "6200", checking),
        ]
        for (payee, offset, amount, code, paymentAccount) in expenses {
            let expense = Expense(date: day(offset), payee: payee, paymentAccountID: paymentAccount.id)
            context.insert(expense)
            let line = ExpenseLine(details: payee, amount: amount, accountID: try account(code).id)
            line.expense = expense
            context.insert(line)
            try books.record(expense)
        }
    }
}
