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

    /// Todo sale en el idioma de la app (`locale`): el plan de cuentas (categorías) y también la empresa, los
    /// clientes, los proveedores y las descripciones (`SampleTexts`). Lo que crea el usuario después no se traduce
    /// nunca; esto sí, porque es lo primero que se ve al probar la app (y lo que ve el revisor de Apple).
    public static func populate(_ context: ModelContext, today: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = .current) throws {
        let t = SampleTexts(locale: locale)
        let books = Bookkeeper(context: context, actor: actor)
        try books.setUpCompany(legalName: t.legalName, displayName: t.displayName,
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

        try books.post(JournalEntryDraft(date: day(-120), memo: t.openingBalances, source: .opening, lines: [
            .debit(checking.id, 3_800_000), .debit(savings.id, 950_000), .credit(capital.id, 4_750_000),
        ]))

        // Sales tax de Austin, TX: 6.25 % estatal + 1 % ciudad + 1 % transporte.
        let taxPayable = try books.systemAccount(.salesTaxPayable)
        let comptroller = TaxAgency(name: "Texas Comptroller", filingFrequency: .quarterly, liabilityAccountID: taxPayable.id)
        books.insert(comptroller)
        let rates = [("Texas", 62_500), ("Austin", 10_000), ("Austin MTA", 10_000)].map { name, rate in
            let taxRate = TaxRate(name: name, rateMillionths: Int64(rate), agency: comptroller)
            books.insert(taxRate)
            return taxRate
        }
        let austin = TaxGroup(name: "Austin, TX", rates: rates)
        books.insert(austin)

        if let company = try books.company() {
            company.defaultTaxGroupID = austin.id
            company.defaultPaymentTermsDays = 15
            company.phone = "(512) 555-0142"
            company.email = t.companyEmail
            company.website = t.website
            company.address = "1400 E 6th St, Austin, TX 78702"
            company.defaultInvoiceMessage = t.invoiceMessage
            company.invoiceFooter = t.invoiceFooter
        }

        let customers = t.customers.map { name, email in
            let customer = Customer(name: name, email: email, paymentTermsDays: 15)
            customer.defaultTaxGroupID = austin.id
            books.insert(customer)
            return customer
        }
        let mirador = customers[1]
        mirador.contactName = t.miradorContact
        mirador.contactTitle = t.miradorTitle
        mirador.notes = t.miradorNotes
        customers[0].contactName = t.auroraContact
        customers[0].contactTitle = t.auroraTitle
        books.insert(CustomerNote(customer: mirador, date: day(-11), text: t.noteLobby, author: "Ana R."))
        books.insert(CustomerNote(customer: mirador, date: day(-60), text: t.notePurchaseOrder, author: "Ana R."))

        func invoice(_ customer: Customer, issued: Int, lines: [(String, Decimal, Int64, Account, Bool)]) throws -> Invoice {
            let invoice = Invoice(customer: customer, issueDate: day(issued))
            invoice.taxGroupID = customer.defaultTaxGroupID
            books.insert(invoice)
            for (index, line) in lines.enumerated() {
                let model = InvoiceLine(details: line.0, quantity: line.1, unitPrice: line.2, isTaxable: line.4,
                                        incomeAccountID: line.3.id, order: index)
                model.invoice = invoice
                books.insert(model)
            }
            try books.issue(invoice)
            try books.recordInvoiceSent(invoice, to: customer.email, subject: t.invoiceSubject(invoice.number), date: day(issued))
            return invoice
        }

        let paid = try invoice(customers[0], issued: -40, lines: [(t.interiorDesign, 1, 180_000, services, false)])
        try books.recordPayment(for: paid, amount: paid.balanceDue, date: day(-30), depositAccount: checking)
        let overdue = try invoice(customers[1], issued: -23, lines: [(t.lobbyRemodel, 1, 150_000, services, false),
                                                                     (t.materials, 1, 55_427, materials, true)])
        try books.recordReminder(overdue, to: mirador.email, subject: t.reminderSubject(overdue.number), date: today)
        _ = try invoice(customers[2], issued: -18, lines: [(t.signage, 1, 100_000, services, false),
                                                           (t.vinyl, 4, 2_310, materials, true)])
        let partial = try invoice(customers[1], issued: -10, lines: [(t.roomDesign, 2, 128_500, services, false)])
        try books.recordPayment(for: partial, amount: 100_000, date: day(-3), depositAccount: checking)
        _ = try invoice(customers[0], issued: -3, lines: [(t.patioRedesign, 1, 240_000, services, false)])

        let lumber = Vendor(name: t.lumberName, email: t.lumberEmail)
        lumber.defaultExpenseAccountID = try account("5000").id
        lumber.preferredPaymentMethod = .bankTransfer
        lumber.preferredPaymentAccountID = checking.id
        books.insert(lumber)
        let bill = Bill(vendor: lumber, vendorNumber: "B-221", billDate: day(-12), dueDate: day(9))
        books.insert(bill)
        let billLine = BillLine(details: t.plywood, amount: 84_230, accountID: try account("5000").id)
        billLine.bill = bill
        books.insert(billLine)
        try books.record(bill)
        try books.schedulePayment(for: bill, on: day(7), from: checking, method: .bankTransfer)

        let contractor = Vendor(name: "Luis Mora", email: t.contractorEmail)
        contractor.is1099 = true
        contractor.tinLast4 = "7310"
        contractor.w9Received = true
        contractor.w9ReceivedDate = day(-90)
        contractor.preferredPaymentMethod = .bankTransfer
        contractor.preferredPaymentAccountID = checking.id
        books.insert(contractor)

        let adobe = Vendor(name: "Adobe", email: "")
        adobe.defaultExpenseAccountID = try account("6750").id
        books.insert(adobe)
        // Suscripción mensual con cargo automático a la tarjeta: la primera repetición se genera aquí mismo.
        try books.saveRecurringTemplate(RecurringTemplateInput(
            name: "Adobe Creative Cloud", kind: .expense, vendor: adobe, payee: "Adobe Creative Cloud",
            lines: [ExpenseInput.Line(details: "Adobe Creative Cloud", amount: 5_999, accountID: try account("6750").id)],
            paymentAccountID: card.id, method: .card, frequency: .monthly, startDate: day(-25), autoCharge: true
        ))
        try books.generateRecurring(through: today, calendar: calendar)

        let expenses: [(String, Int, Int64, String, Account)] = [
            (t.workshopRent, -28, 120_000, "6400", checking),
            ("UBER *TRIP", -2, 1_840, "6050", card),
            ("Home Depot", -6, 21_475, "6500", card),
            (t.vehicleInsurance, -14, 31_000, "6200", checking),
        ]
        for (payee, offset, amount, code, paymentAccount) in expenses {
            let expense = Expense(date: day(offset), payee: payee, paymentAccountID: paymentAccount.id)
            books.insert(expense)
            let line = ExpenseLine(details: payee, amount: amount, accountID: try account(code).id)
            line.expense = expense
            books.insert(line)
            if payee == "Home Depot" {
                // Materiales para la terraza de Café Aurora: gasto facturable, con el sales tax del ticket.
                expense.customer = customers[0]
                expense.salesTaxIncluded = 1_637
            }
            try books.record(expense)
        }

        // Estimado aceptado, aún sin facturar (canvas `Estimado`).
        let estimate = try books.saveEstimate(EstimateInput(
            customer: mirador, title: t.estimateTitle, issueDate: day(-5), expirationDate: day(25),
            taxGroupID: austin.id, customerMessage: t.estimateMessage,
            lines: [
                .init(details: t.lobbyDesign, unitPrice: 240_000, isTaxable: false, incomeAccountID: services.id),
                .init(details: t.labor, quantity: 40, unitPrice: 5_800, isTaxable: false, incomeAccountID: services.id),
                .init(details: t.oak, quantity: 12, unitPrice: 8_500, isTaxable: true, incomeAccountID: materials.id),
            ]
        ))
        try books.setStatus(.sent, of: estimate, date: day(-5))
        try books.setStatus(.accepted, of: estimate, acceptedBy: t.miradorContact, date: day(-2))

        // Esquema 4: banco (canvas de conciliación) y presupuesto. Movimientos del banco y de la tarjeta: el cobro de
        // Café Aurora y la renta emparejados con lo registrado; Uber y Shell por revisar (Shell con una regla).
        try books.saveBankRule(BankRuleInput(name: t.fuelRule, matchText: "shell", amountSign: .outflow, targetAccountID: try account("6050").id))
        let bankLines = [
            BankStatementLine(date: day(-30), amount: 180_000, details: t.depositDetails, externalID: "fitid:S-1"),
            BankStatementLine(date: day(-28), amount: -120_000, details: t.checkDetails, checkNumber: "1043", externalID: "fitid:S-2"),
        ]
        try books.importStatementLines(bankLines, source: .ofx, into: checking)
        try books.importStatementLines([
            BankStatementLine(date: day(-2), amount: -1_840, details: "UBER *TRIP HELP.UBER.COM", externalID: "fitid:T-1"),
            BankStatementLine(date: day(-1), amount: -4_310, details: "SHELL OIL 57444", externalID: "fitid:T-2"),
        ], source: .ofx, into: card)
        for transaction in try books.bankInbox(account: checking) {
            if let candidate = try books.matchCandidates(for: transaction).first { try books.match(transaction, to: candidate.line) }
        }
        let fiscalYear = calendar.component(.year, from: try books.fiscalYearStart(containing: today, calendar: calendar))
        let budget = try books.createBudget(name: t.budgetName(fiscalYear), fiscalYear: fiscalYear)
        try books.setAnnualBudget(9_000_000, account: services, in: budget, calendar: calendar)
        try books.setAnnualBudget(1_440_000, account: try account("6400"), in: budget, calendar: calendar)
        try books.setAnnualBudget(240_000, account: try account("6050"), in: budget, calendar: calendar)
    }

    // MARK: - Datos de ejemplo o libros propios

    /// Altas de empresa hechas por los datos de ejemplo, para una `@Query` (`isSample(companies:sampleCreations:)`).
    public static var sampleCreationsPredicate: Predicate<AuditEvent> {
        let actor = actor
        return #Predicate<AuditEvent> { $0.actor == actor && $0.subjectEntity == "Company" && $0.action == "create" }
    }

    /// `true` si hay empresa y todas son de ejemplo (con iCloud podrían llegar dos copias de la de ejemplo, una por
    /// aparato). Con una sola empresa real, `false`.
    public static func isSample(companies: [Company], sampleCreations: [AuditEvent]) -> Bool {
        guard !companies.isEmpty else { return false }
        let sampleIDs = Set(sampleCreations.compactMap { event -> UUID? in
            event.actor == actor && event.subjectEntity == "Company" && event.action == "create" ? event.entityID : nil
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

/// Los textos de los datos de ejemplo, en español o en inglés según el idioma de la app. Las cifras, las fechas y los
/// importes son los mismos en los dos (las pruebas y las capturas cuentan con ellos); solo cambian los nombres.
struct SampleTexts {
    let spanish: Bool

    init(locale: Locale) { spanish = locale.language.languageCode?.identifier == "es" }

    private func pick(_ es: String, _ en: String) -> String { spanish ? es : en }

    var legalName: String { pick("Ríos Diseño & Obra LLC", "Rios Design & Build LLC") }
    var displayName: String { pick("Ríos Diseño & Obra", "Rios Design & Build") }
    var openingBalances: String { pick("Saldos iniciales", "Opening balances") }
    var companyEmail: String { pick("hola@riosdiseno.com", "hello@riosdesignbuild.com") }
    var website: String { pick("riosdiseno.com", "riosdesignbuild.com") }
    var invoiceMessage: String { pick("Gracias por su preferencia.", "Thank you for your business.") }
    var invoiceFooter: String {
        pick("Pago a 15 días por transferencia a la cuenta indicada.", "Payment due in 15 days by bank transfer to the account shown.")
    }

    var customers: [(String, String)] {
        spanish
            ? [("Café Aurora", "hola@cafeaurora.com"), ("Hotel Mirador", "compras@hotelmirador.com"),
               ("Clínica Del Valle", "admin@clinicadelvalle.com")]
            : [("Aurora Café", "hello@auroracafe.com"), ("Mirador Hotel", "purchasing@miradorhotel.com"),
               ("Del Valle Clinic", "admin@delvalleclinic.com")]
    }
    var miradorContact: String { pick("Laura Méndez", "Laura Mendez") }
    var miradorTitle: String { pick("Gerente", "General Manager") }
    var miradorNotes: String {
        pick("Pagan los viernes. Enviar facturas a Laura con copia a contabilidad.",
             "They pay on Fridays. Send invoices to Laura and copy accounting.")
    }
    var auroraContact: String { pick("Sofía Ríos", "Sofia Rios") }
    var auroraTitle: String { pick("Dueña", "Owner") }
    var noteLobby: String { pick("Interesados en remodelar el lobby en enero.", "Interested in remodeling the lobby in January.") }
    var notePurchaseOrder: String {
        pick("Piden factura con orden de compra a partir de octubre.", "Invoices need a purchase order starting in October.")
    }

    func invoiceSubject(_ number: String) -> String {
        spanish ? "Factura \(number) · \(displayName)" : "Invoice \(number) · \(displayName)"
    }
    func reminderSubject(_ number: String) -> String {
        spanish ? "Recordatorio: factura \(number) vencida" : "Reminder: invoice \(number) is past due"
    }

    var interiorDesign: String { pick("Diseño de interiores · fase 1", "Interior design · phase 1") }
    var lobbyRemodel: String { pick("Remodelación de lobby", "Lobby remodel") }
    var materials: String { pick("Materiales", "Materials") }
    var signage: String { pick("Señalética y mobiliario", "Signage and furniture") }
    var vinyl: String { pick("Vinil impreso", "Printed vinyl") }
    var roomDesign: String { pick("Diseño de habitaciones", "Guest room design") }
    var patioRedesign: String { pick("Rediseño de terraza", "Patio redesign") }

    var lumberName: String { pick("Maderas del Norte", "Northside Lumber") }
    var lumberEmail: String { pick("ventas@maderasnorte.com", "sales@northsidelumber.com") }
    var plywood: String { pick("Triplay y herrajes", "Plywood and hardware") }
    var contractorEmail: String { pick("luis.mora@correo.com", "luis.mora@mail.com") }

    var workshopRent: String { pick("Renta del taller", "Workshop rent") }
    var vehicleInsurance: String { pick("Seguro del vehículo", "Vehicle insurance") }

    var estimateTitle: String { pick("Remodelación del lobby", "Lobby remodel") }
    var estimateMessage: String { pick("Precios válidos por 30 días.", "Prices valid for 30 days.") }
    var lobbyDesign: String { pick("Diseño de lobby", "Lobby design") }
    var labor: String { pick("Mano de obra", "Labor") }
    var oak: String { pick("Madera de roble", "Oak lumber") }

    var fuelRule: String { pick("Gasolina", "Fuel") }
    var depositDetails: String { pick("DEPOSIT CAFE AURORA", "DEPOSIT AURORA CAFE") }
    var checkDetails: String { pick("CHECK 1043 RENTA TALLER", "CHECK 1043 WORKSHOP RENT") }
    func budgetName(_ year: Int) -> String { spanish ? "Presupuesto \(year)" : "Budget \(year)" }
}
