import ChirograCore
import Foundation
import SwiftData

/// Datos de ejemplo para vistas previas, capturas y el botón "Probar con datos de ejemplo".
/// Todo pasa por `Bookkeeper`, así que los asientos de ejemplo cumplen las mismas reglas que los reales.
///
/// **Saber si los libros son de ejemplo** (`isSample`) sin tocar el esquema: `populate` da de alta la empresa con
/// `Bookkeeper(actor: SampleData.actor)`, así que su alta queda en el registro de auditoría como
/// `AuditEvent(actor: "Ejemplo", entityName: "Company", action: "create", entityID: <id de la empresa>)`. Ese registro
/// es parte de los libros: se sincroniza con iCloud y viaja en las copias `.chirogra`, así que la marca vale en
/// cualquier aparato (no como `UserDefaults`, que es de un solo aparato y se queda vieja al restaurar una copia).
/// Una empresa real nunca lo tiene: el alta (`OnboardingView`) usa `Bookkeeper` sin actor, y nada más en la app
/// escribe el actor «Ejemplo»; el nombre de la empresa no cuenta (alguien puede llamarse igual).
@MainActor
public enum SampleData {
    /// Actor del registro de auditoría de todo lo que crean los datos de ejemplo. No cambiarlo: los datos de ejemplo
    /// ya cargados en los aparatos se reconocen por él.
    public static let actor = "Ejemplo"

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
        let books = Bookkeeper(context: context, actor: actor)
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
        checking.last4 = "4821"
        savings.last4 = "9032"
        card.last4 = "1177"
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

        if let company = try books.company() {
            company.defaultTaxGroupID = austin.id
            company.defaultPaymentTermsDays = 15
            company.phone = "(512) 555-0142"
            company.email = "hola@riosdiseno.com"
            company.website = "riosdiseno.com"
            company.address = "1400 E 6th St, Austin, TX 78702"
            company.defaultInvoiceMessage = "Gracias por su preferencia."
            company.invoiceFooter = "Pago a 15 días por transferencia a la cuenta indicada."
        }

        let customers = [("Café Aurora", "hola@cafeaurora.com"), ("Hotel Mirador", "compras@hotelmirador.com"),
                         ("Clínica Del Valle", "admin@clinicadelvalle.com")].map { name, email in
            let customer = Customer(name: name, email: email, paymentTermsDays: 15)
            customer.defaultTaxGroupID = austin.id
            context.insert(customer)
            return customer
        }
        let mirador = customers[1]
        mirador.contactName = "Laura Méndez"
        mirador.contactTitle = "Gerente"
        mirador.notes = "Pagan los viernes. Enviar facturas a Laura con copia a contabilidad."
        customers[0].contactName = "Sofía Ríos"
        customers[0].contactTitle = "Dueña"
        context.insert(CustomerNote(customer: mirador, date: day(-11), text: "Interesados en remodelar el lobby en enero.", author: "Ana R."))
        context.insert(CustomerNote(customer: mirador, date: day(-60), text: "Piden factura con orden de compra a partir de octubre.", author: "Ana R."))

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
            try books.recordInvoiceSent(invoice, to: customer.email, subject: "Factura \(invoice.number) · Ríos Diseño & Obra", date: day(issued))
            return invoice
        }

        let paid = try invoice(customers[0], issued: -40, lines: [("Diseño de interiores · fase 1", 1, 180_000, services, false)])
        try books.recordPayment(for: paid, amount: paid.balanceDue, date: day(-30), depositAccount: checking)
        let overdue = try invoice(customers[1], issued: -23, lines: [("Remodelación de lobby", 1, 150_000, services, false),
                                                                     ("Materiales", 1, 55_427, materials, true)])
        try books.recordReminder(overdue, to: mirador.email, subject: "Recordatorio: factura \(overdue.number) vencida", date: today)
        _ = try invoice(customers[2], issued: -18, lines: [("Señalética y mobiliario", 1, 100_000, services, false),
                                                           ("Vinil impreso", 4, 2_310, materials, true)])
        let partial = try invoice(customers[1], issued: -10, lines: [("Diseño de habitaciones", 2, 128_500, services, false)])
        try books.recordPayment(for: partial, amount: 100_000, date: day(-3), depositAccount: checking)
        _ = try invoice(customers[0], issued: -3, lines: [("Rediseño de terraza", 1, 240_000, services, false)])

        let lumber = Vendor(name: "Maderas del Norte", email: "ventas@maderasnorte.com")
        lumber.defaultExpenseAccountID = try account("5000").id
        lumber.preferredPaymentMethod = .bankTransfer
        lumber.preferredPaymentAccountID = checking.id
        context.insert(lumber)
        let bill = Bill(vendor: lumber, vendorNumber: "B-221", billDate: day(-12), dueDate: day(9))
        context.insert(bill)
        let billLine = BillLine(details: "Triplay y herrajes", amount: 84_230, accountID: try account("5000").id)
        billLine.bill = bill
        context.insert(billLine)
        try books.record(bill)
        try books.schedulePayment(for: bill, on: day(7), from: checking, method: .bankTransfer)

        let contractor = Vendor(name: "Luis Mora", email: "luis.mora@correo.com")
        contractor.is1099 = true
        contractor.tinLast4 = "7310"
        contractor.w9Received = true
        contractor.w9ReceivedDate = day(-90)
        contractor.preferredPaymentMethod = .bankTransfer
        contractor.preferredPaymentAccountID = checking.id
        context.insert(contractor)

        let adobe = Vendor(name: "Adobe", email: "")
        adobe.defaultExpenseAccountID = try account("6750").id
        context.insert(adobe)
        // Suscripción mensual con cargo automático a la tarjeta: la primera repetición se genera aquí mismo.
        try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Adobe Creative Cloud", kind: .expense, vendor: adobe, payee: "Adobe Creative Cloud",
            lines: [ExpenseInput.Line(details: "Adobe Creative Cloud", amount: 5_999, accountID: try account("6750").id)],
            paymentAccountID: card.id, method: .card, frequency: .monthly, startDate: day(-25), autoCharge: true
        ))
        try books.generateRecurring(through: today, calendar: calendar)

        let expenses: [(String, Int, Int64, String, Account)] = [
            ("Renta del taller", -28, 120_000, "6400", checking),
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
            if payee == "Home Depot" {
                // Materiales para la terraza de Café Aurora: gasto facturable, con el sales tax del ticket.
                expense.customer = customers[0]
                expense.salesTaxIncluded = 1_637
            }
            try books.record(expense)
        }

        // Estimado aceptado, aún sin facturar (canvas `Estimado`).
        let estimate = try books.saveEstimate(EstimateInput(
            customer: mirador, title: "Remodelación del lobby", issueDate: day(-5), expirationDate: day(25),
            taxGroupID: austin.id, customerMessage: "Precios válidos por 30 días.",
            lines: [
                .init(details: "Diseño de lobby", unitPrice: 240_000, isTaxable: false, incomeAccountID: services.id),
                .init(details: "Mano de obra", quantity: 40, unitPrice: 5_800, isTaxable: false, incomeAccountID: services.id),
                .init(details: "Madera de roble", quantity: 12, unitPrice: 8_500, isTaxable: true, incomeAccountID: materials.id),
            ]
        ))
        try books.setStatus(.sent, of: estimate, date: day(-5))
        try books.setStatus(.accepted, of: estimate, acceptedBy: "Laura Méndez", date: day(-2))
    }

    // MARK: - Datos de ejemplo o libros propios

    /// Altas de empresa hechas por los datos de ejemplo, para una `@Query` (`isSample(companies:sampleCreations:)`).
    public static var sampleCreationsPredicate: Predicate<AuditEvent> {
        let actor = actor
        return #Predicate<AuditEvent> { $0.actor == actor && $0.entityName == "Company" && $0.action == "create" }
    }

    /// `true` si hay empresa y todas son de ejemplo (con iCloud podrían llegar dos copias de la de ejemplo, una por
    /// aparato). Con una sola empresa real, `false`.
    public static func isSample(companies: [Company], sampleCreations: [AuditEvent]) -> Bool {
        guard !companies.isEmpty else { return false }
        let sampleIDs = Set(sampleCreations.compactMap { event -> UUID? in
            event.actor == actor && event.entityName == "Company" && event.action == "create" ? event.entityID : nil
        })
        return companies.allSatisfy { sampleIDs.contains($0.id) }
    }

    /// Los libros de `context` son los de ejemplo (ver la explicación del tipo).
    public static func isSample(_ context: ModelContext) throws -> Bool {
        isSample(companies: try context.fetch(FetchDescriptor<Company>()),
                 sampleCreations: try context.fetch(FetchDescriptor(predicate: sampleCreationsPredicate)))
    }

    /// «Empezar con mi empresa»: borra **todo** lo de los libros de ejemplo (todos los modelos, uno a uno para que el
    /// borrado llegue por iCloud a los otros aparatos) en un solo guardado. Después no queda empresa y la app vuelve al
    /// alta. Si los libros no son de ejemplo no borra nada y lanza `SampleDataError.notSample`: así nunca se borran
    /// unos libros reales por error.
    public static func discard(from context: ModelContext) throws {
        guard try isSample(context) else { throw SampleDataError.notSample }
        try BackupArchive.eraseAll(in: context)
    }
}

public enum SampleDataError: Error, Equatable, LocalizedError {
    /// Los libros no son los de ejemplo: no se borran.
    case notSample

    public var errorDescription: String? {
        switch self {
        case .notSample: String(localized: "Estos libros no son los de ejemplo, así que no se borraron.")
        }
    }
}
