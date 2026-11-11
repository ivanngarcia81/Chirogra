import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Un almacén escrito con un esquema anterior (en disco, con los modelos congelados de `SchemaV1`, `SchemaV2` o
/// `SchemaV3`) se abre con el contenedor de la app, se migra hasta `SchemaV4` y conserva todo; los campos nuevos toman
/// su valor por defecto y todo queda con la empresa que había (`companyID`).
@MainActor
@Suite("Migración de los esquemas 1, 2 y 3 al 4")
struct MigrationTests {

    /// Registros sin empresa, de todos los modelos.
    static func orphanCount(_ context: ModelContext) throws -> Int {
        try CompanyOwnership.ownedTypes.reduce(0) { $0 + (try count($1, in: context)) }
    }

    private static func count<T: CompanyOwned>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>(predicate: T.orphans))
    }

    /// Registros con esa empresa, de todos los modelos.
    static func ownedCount(_ context: ModelContext, companyID: UUID) throws -> Int {
        try CompanyOwnership.ownedTypes.reduce(0) { $0 + (try owned($1, companyID, in: context)) }
    }

    private static func owned<T: CompanyOwned>(_ type: T.Type, _ id: UUID, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>(predicate: T.ownedBy(id, includeOrphans: false)))
    }

    static func temporaryStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "chirogra-migracion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Chirogra.store")
    }

    /// Escribe libros pequeños pero completos con los modelos del esquema 1.
    static func writeV1Store(at url: URL, today: Date) throws -> (companyID: UUID, invoiceID: UUID, expenseID: UUID, checkingID: UUID) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Chirogra", schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        let company = SchemaV1.Company()
        company.legalName = "Vieja Escuela LLC"
        company.displayName = "Vieja Escuela"
        company.state = "TX"
        company.lockDate = Calendar.current.date(byAdding: .day, value: -200, to: today)
        context.insert(company)

        func account(_ code: String, _ name: String, _ subtype: AccountSubtype, system: Bool = false) -> SchemaV1.Account {
            let account = SchemaV1.Account()
            account.code = code
            account.name = name
            account.subtypeRaw = subtype.rawValue
            account.isSystem = system
            context.insert(account)
            return account
        }
        let checking = account("1010", "Cuenta corriente", .bank)
        let receivable = account("1100", "Cuentas por cobrar", .accountsReceivable, system: true)
        let payable = account("2000", "Cuentas por pagar", .accountsPayable, system: true)
        _ = account("2200", "Sales tax por pagar", .salesTaxPayable, system: true)
        let capital = account("3000", "Capital del dueño", .ownersEquity, system: true)
        let services = account("4000", "Ingresos por servicios", .sales)
        let supplies = account("6500", "Suministros", .operatingExpense)

        for (kind, prefix, next, digits) in [(DocumentKind.journalEntry, "", 4, 1), (.invoice, "F-", 1002, 4), (.creditNote, "NC-", 1, 4)] {
            let sequence = SchemaV1.NumberSequence()
            sequence.kindRaw = kind.rawValue
            sequence.prefix = prefix
            sequence.nextNumber = next
            sequence.minimumDigits = digits
            context.insert(sequence)
        }

        func entry(_ number: Int, _ memo: String, _ source: EntrySource, _ lines: [(SchemaV1.Account, Int64, Int64)]) -> SchemaV1.JournalEntry {
            let entry = SchemaV1.JournalEntry()
            entry.number = number
            entry.date = today
            entry.memo = memo
            entry.sourceRaw = source.rawValue
            context.insert(entry)
            for (order, (account, debit, credit)) in lines.enumerated() {
                let line = SchemaV1.JournalLine()
                line.account = account
                line.debit = debit
                line.credit = credit
                line.order = order
                line.entry = entry
                context.insert(line)
            }
            return entry
        }
        _ = entry(1, "Saldos iniciales", .opening, [(checking, 500_000, 0), (capital, 0, 500_000)])

        let customer = SchemaV1.Customer()
        customer.name = "Café Aurora"
        customer.email = "hola@cafeaurora.com"
        customer.notes = "Pagan los viernes"
        context.insert(customer)
        let invoice = SchemaV1.Invoice()
        invoice.number = "F-1001"
        invoice.statusRaw = InvoiceStatus.sent.rawValue
        invoice.customer = customer
        invoice.subtotal = 120_000
        invoice.total = 120_000
        invoice.issueDate = today
        invoice.dueDate = today
        context.insert(invoice)
        let invoiceLine = SchemaV1.InvoiceLine()
        invoiceLine.details = "Diseño"
        invoiceLine.unitPrice = 120_000
        invoiceLine.isTaxable = false
        invoiceLine.incomeAccountID = services.id
        invoiceLine.invoice = invoice
        context.insert(invoiceLine)
        invoice.journalEntryID = entry(2, "Factura F-1001", .invoice, [(receivable, 120_000, 0), (services, 0, 120_000)]).id

        let vendor = SchemaV1.Vendor()
        vendor.name = "Maderas del Norte"
        vendor.is1099 = true
        vendor.tinLast4 = "1234"
        context.insert(vendor)
        let bill = SchemaV1.Bill()
        bill.vendorNumber = "B-221"
        bill.vendor = vendor
        bill.total = 30_000
        bill.billDate = today
        bill.dueDate = today
        bill.payableAccountID = payable.id
        context.insert(bill)
        bill.journalEntryID = entry(3, "Factura B-221", .bill, [(supplies, 30_000, 0), (payable, 0, 30_000)]).id

        let expense = SchemaV1.Expense()
        expense.payee = "Home Depot"
        expense.date = today
        expense.vendor = vendor
        expense.paymentAccountID = checking.id
        expense.total = 4_500
        context.insert(expense)
        let expenseLine = SchemaV1.ExpenseLine()
        expenseLine.details = "Tornillos"
        expenseLine.amount = 4_500
        expenseLine.accountID = supplies.id
        expenseLine.expense = expense
        context.insert(expenseLine)
        let receipt = SchemaV1.Attachment()
        receipt.filename = "recibo.jpg"
        receipt.contentType = "public.jpeg"
        receipt.data = Data(repeating: 7, count: 300_000)   // grande: va a almacenamiento externo
        receipt.expense = expense
        context.insert(receipt)
        expense.journalEntryID = entry(4, "Gasto · Home Depot", .expense, [(supplies, 4_500, 0), (checking, 0, 4_500)]).id

        let agency = SchemaV1.TaxAgency()
        agency.name = "Texas Comptroller"
        context.insert(agency)
        let rate = SchemaV1.TaxRate()
        rate.name = "Texas"
        rate.rateMillionths = 62_500
        rate.agency = agency
        context.insert(rate)
        let group = SchemaV1.TaxGroup()
        group.name = "Texas"
        group.rates = [rate]
        context.insert(group)

        let audit = SchemaV1.AuditEvent()
        audit.action = "create"
        audit.summary = "Alta"
        context.insert(audit)
        try context.save()
        return (company.id, invoice.id, expense.id, checking.id)
    }

    @Test("Los datos de un almacén V1 sobreviven y los campos nuevos nacen con su valor por defecto")
    func migratesV1Store() throws {
        let url = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let today = Calendar.current.startOfDay(for: Date())
        let ids = try Self.writeV1Store(at: url, today: today)

        let container = try ChirograStore.makeContainer(url: url)
        let context = container.mainContext
        let books = Bookkeeper(context: context, actor: "Pruebas")

        // Lo de antes, intacto.
        let company = try #require(try books.company())
        #expect(company.id == ids.companyID)
        #expect(company.legalName == "Vieja Escuela LLC")
        #expect(company.lockDate != nil)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 7)
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<JournalLine>()) == 8)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).allSatisfy { $0.totalDebits == $0.totalCredits })
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        #expect(invoice.id == ids.invoiceID)
        #expect(invoice.number == "F-1001" && invoice.balanceDue == 120_000 && invoice.customer?.name == "Café Aurora")
        #expect(invoice.sortedLines.first?.details == "Diseño")
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.id == ids.expenseID)
        #expect(expense.attachments?.first?.data?.count == 300_000)
        #expect(expense.vendor?.tinLast4 == "1234")
        #expect(try context.fetch(FetchDescriptor<TaxGroup>()).first?.combinedRateMillionths == 62_500)
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture).isBalanced)

        // Lo nuevo, con su valor por defecto.
        #expect(company.pricesIncludeTax == false)
        #expect(company.salesTaxSourcing == .origin)
        #expect(company.invoiceAccentHex == InvoiceAccent.ink.hex)
        #expect(company.invoiceShowLogo && company.invoiceShowAddress && !company.invoiceShowEIN)
        #expect(company.defaultPaymentTermsDays == 30 && company.defaultTaxGroupID == nil && company.logo == nil)
        #expect(!company.hasClosingPassword)
        #expect(try books.accounts().allSatisfy { $0.last4.isEmpty })
        #expect(invoice.pricesIncludeTax == false && invoice.estimateID == nil && (invoice.events ?? []).isEmpty)
        #expect(expense.salesTaxIncluded == 0 && expense.customer == nil && expense.revision == 0 && !expense.isVoid)
        let bill = try #require(try context.fetch(FetchDescriptor<Bill>()).first)
        #expect(bill.scheduledPaymentDate == nil && !bill.autoPay && bill.recurringTemplateID == nil)
        #expect(bill.vendor?.w9Received == false && bill.vendor?.preferredPaymentMethod == nil)
        #expect(invoice.customer?.contactName == "" && (invoice.customer?.datedNotes ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).allSatisfy { $0.replacesEntryID == nil })

        // Esquema 4: todo es de la empresa que había; los campos nuevos, con su valor por defecto.
        #expect(try Self.orphanCount(context) == 0)
        #expect(try Self.ownedCount(context, companyID: company.id) == 7 + 4 + 8 + 3 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)
        #expect(company.sortOrder == 0 && !company.isArchived && company.postalCode.isEmpty && company.paymentLinkURL.isEmpty)
        #expect(company.showPayNowOnInvoice && company.paymentInstructions.isEmpty)
        #expect(try books.accounts().allSatisfy { $0.taxFormLineRaw.isEmpty })
        #expect(try context.fetch(FetchDescriptor<JournalLine>()).allSatisfy { $0.reconciliationID == nil && $0.clearedAt == nil })
        #expect(invoice.customer?.postalCode == "")
        #expect(try context.fetchCount(FetchDescriptor<BankTransaction>()) == 0)

        // Y se puede seguir trabajando con las funciones nuevas sobre los datos migrados.
        let checking = try #require(try books.account(id: ids.checkingID))
        try books.updateAccount(checking, with: AccountInput(code: "1010", name: "Corriente", subtype: .bank, last4: "4821"))
        #expect(checking.maskedName == "Corriente ••4821")
        try books.schedulePayment(for: bill, on: today, from: checking)
        let estimate = try books.saveEstimate(EstimateInput(customer: invoice.customer, issueDate: today, expirationDate: today,
                                                            lines: [.init(details: "Obra", unitPrice: 10_000, incomeAccountID: nil)]))
        #expect(estimate.number == "E-0001")   // la serie de estimados no existía en V1: se crea con su prefijo
        try books.addNote(to: try #require(invoice.customer), text: "Migrado")
        try books.recordReminder(invoice, to: "hola@cafeaurora.com", subject: "Recordatorio")
        let entry = try #require(try books.updateExpense(expense, with: {
            var input = ExpenseInput(expense)
            input.lines[0].amount = 5_000
            return input
        }()))
        #expect(entry.number == 5)   // la serie de asientos sigue donde iba
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture).isBalanced)

        // Reabrir el almacén ya migrado no vuelve a migrar ni pierde nada.
        let reopened = try ChirograStore.makeContainer(url: url)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<CustomerNote>()) == 1)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Estimate>()) == 1)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Account>()).first { $0.code == "1010" }?.last4 == "4821")
    }

    /// Comprobación manual contra un almacén escrito por una versión publicada (esquema 1, 2 o 3; p. ej. `SampleData`
    /// en `4f4e68e` o en `c214680`). Se activa con `CHIROGRA_STORE=/ruta/Chirogra.store swift test --filter
    /// MigrationTests` (también vale el nombre de antes, `CHIROGRA_V1_STORE`); el almacén se copia antes de abrirlo, así
    /// que el original no se toca. Ver docs/DATOS-V2.md y docs/DATOS-V4.md.
    nonisolated static var publishedStore: String? {
        ProcessInfo.processInfo.environment["CHIROGRA_STORE"] ?? ProcessInfo.processInfo.environment["CHIROGRA_V1_STORE"]
    }

    @Test("Un almacén escrito por una versión publicada se migra al esquema 4 y cuadra", .enabled(if: publishedStore != nil))
    func migratesStoreFromPublishedApp() throws {
        let source = URL(filePath: try #require(Self.publishedStore))
        let url = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(filePath: source.path() + suffix)
            if FileManager.default.fileExists(atPath: from.path()) { try FileManager.default.copyItem(at: from, to: URL(filePath: url.path() + suffix)) }
        }
        let folder = source.deletingLastPathComponent().appending(path: ".Chirogra_SUPPORT")
        if FileManager.default.fileExists(atPath: folder.path()) {
            try FileManager.default.copyItem(at: folder, to: url.deletingLastPathComponent().appending(path: ".Chirogra_SUPPORT"))
        }
        let container = try ChirograStore.makeContainer(url: url)
        let books = Bookkeeper(context: container.mainContext)
        #expect(try books.company() != nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Invoice>()) > 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<JournalEntry>()) > 0)
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture).isBalanced)
        #expect(try books.company()?.invoiceAccentHex == InvoiceAccent.ink.hex)
        _ = try books.notices()
        #expect(try Self.orphanCount(container.mainContext) == 0)
        let companies = try container.mainContext.fetch(FetchDescriptor<Company>())
        #expect(companies.filter { !$0.isArchived }.count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<AuditEvent>()).contains { !$0.subjectEntity.isEmpty })
    }

    @Test("El plan de migración va de la versión 1 a la 5 y la app usa la 5")
    func plan() {
        #expect(ChirograMigrationPlan.schemas.map { $0.versionIdentifier }
                == [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0), Schema.Version(3, 0, 0), Schema.Version(4, 0, 0), Schema.Version(5, 0, 0)])
        #expect(ChirograMigrationPlan.stages.count == 4)
        #expect(SchemaV2.models.count == SchemaV1.models.count + 8)
        #expect(SchemaV3.models.count == SchemaV2.models.count)
        #expect(SchemaV4.models.count == SchemaV3.models.count + 6)
        #expect(SchemaV5.models.count == SchemaV4.models.count)
        #expect(ChirograStore.schema.entities.count == SchemaV5.models.count)
        #expect(CompanyOwnership.ownedTypes.count == SchemaV5.models.count - 1)
        #expect(ChirograStore.schema.entities.first { $0.name == "AuditEvent" }?.storedProperties.contains { $0.name == "device" } == true)
    }

    /// Esquema 2 → 3 → 4: `AuditEvent.entityName` pasa a `subjectEntity` y conserva el valor (lo usan la detección de
    /// los datos de ejemplo y la actividad de las facturas), y todo queda con la empresa.
    @MainActor
    @Test("Un almacén del esquema 2 se migra al 4: el historial conserva su entidad y todo tiene empresa")
    func migratesV2Store() throws {
        let url = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let companyID: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Chirogra", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let company = SchemaV2.Company()
            company.legalName = "Dos LLC"
            context.insert(company)
            companyID = company.id
            for (actor, entity, id, action) in [("Ejemplo", "Company", companyID, "create"), ("Ana", "Invoice", UUID(), "sent")] {
                let event = SchemaV2.AuditEvent()
                event.actor = actor
                event.entityName = entity
                event.entityID = id
                event.action = action
                context.insert(event)
            }
            let template = SchemaV2.RecurringTemplate()
            template.name = "Renta"
            context.insert(template)
            let line = SchemaV2.RecurringTemplateLine()
            line.amount = 100_000
            line.template = template
            context.insert(line)
            try context.save()
        }
        let container = try ChirograStore.makeContainer(url: url)
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<AuditEvent>(sortBy: [SortDescriptor(\.actor)]))
        #expect(events.map(\.subjectEntity) == ["Invoice", "Company"])
        #expect(events.last?.entityID == companyID)
        #expect(events.map(\.action) == ["sent", "create"])
        #expect(try Self.orphanCount(context) == 0)
        #expect(try Self.ownedCount(context, companyID: companyID) == 4)
        #expect(try context.fetch(FetchDescriptor<RecurringTemplate>()).first?.total == 100_000)
    }

    /// Esquema 3 → 4 con los libros mezclados de dos altas (dos aparatos que hicieron el alta y se juntaron por iCloud):
    /// todo pasa a la empresa más antigua y la otra, vacía, queda archivada.
    @MainActor
    @Test("Un almacén del esquema 3 se migra al 4: todo a la empresa más antigua y las demás archivadas")
    func migratesV3Store() throws {
        let url = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let oldest: UUID, newer: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Chirogra", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let first = SchemaV2.Company()
            first.legalName = "Primera LLC"
            first.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let second = SchemaV2.Company()
            second.legalName = "Segunda LLC"
            second.createdAt = Date(timeIntervalSinceReferenceDate: 810_000_000)
            context.insert(second)
            context.insert(first)
            oldest = first.id
            newer = second.id
            let account = SchemaV2.Account()
            account.code = "1010"
            account.subtypeRaw = AccountSubtype.bank.rawValue
            context.insert(account)
            let entry = SchemaV2.JournalEntry()
            entry.number = 1
            context.insert(entry)
            let line = SchemaV2.JournalLine()
            line.debit = 500
            line.entry = entry
            line.account = account
            context.insert(line)
            let event = SchemaV3.AuditEvent()
            event.subjectEntity = "Company"
            event.entityID = first.id
            context.insert(event)
            try context.save()
        }
        let container = try ChirograStore.makeContainer(url: url)
        let context = container.mainContext
        #expect(try Self.orphanCount(context) == 0)
        #expect(try Self.ownedCount(context, companyID: oldest) == 4)
        let companies = try context.fetch(FetchDescriptor<Company>()).sorted { $0.sortOrder < $1.sortOrder }
        #expect(companies.map(\.id) == [oldest, newer])
        #expect(companies.map(\.isArchived) == [false, true])
        #expect(try context.fetch(FetchDescriptor<AuditEvent>()).first?.subjectEntity == "Company")
        let books = Bookkeeper(context: context)
        #expect(try books.company()?.id == oldest)
        #expect(try books.accounts().count == 1)
        #expect(ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture).rows.count == 1)

        // Reabrir no vuelve a migrar ni cambia nada.
        let reopened = try ChirograStore.makeContainer(url: url)
        #expect(try Self.orphanCount(reopened.mainContext) == 0)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Company>()).filter(\.isArchived).map(\.id) == [newer])
    }

    /// Esquema 4 → 5 (1.1 → 1.2): ligera. Lo de antes se conserva y las propiedades nuevas nacen vacías.
    @MainActor
    @Test("Un almacén del esquema 4 se migra al 5: la bitácora y los movimientos conservan todo y lo nuevo nace vacío")
    func migratesV4Store() throws {
        let url = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let companyID: UUID, transactionID: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV4.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Chirogra", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let company = SchemaV4.Company(legalName: "Cuatro LLC")
            context.insert(company)
            companyID = company.id
            let event = SchemaV4.AuditEvent()
            event.companyID = companyID
            event.subjectEntity = "Company"
            event.entityID = companyID
            event.action = "create"
            event.summary = "Alta de Cuatro LLC"
            context.insert(event)
            let transaction = SchemaV4.BankTransaction()
            transaction.companyID = companyID
            transaction.amount = -4_250
            transaction.details = "UBER *TRIP"
            transaction.statusRaw = BankTransactionStatus.ignored.rawValue
            context.insert(transaction)
            transactionID = transaction.id
            try context.save()
        }
        let container = try ChirograStore.makeContainer(url: url)
        let context = container.mainContext
        let event = try #require(try context.fetch(FetchDescriptor<AuditEvent>()).first)
        #expect(event.summary == "Alta de Cuatro LLC")
        #expect(event.subjectEntity == "Company")
        #expect(event.device.isEmpty && event.changeDetails.isEmpty)
        let transaction = try #require(try context.fetch(FetchDescriptor<BankTransaction>()).first)
        #expect(transaction.id == transactionID)
        #expect(transaction.amount == -4_250 && transaction.status == .ignored)
        #expect(transaction.ignoreReason.isEmpty)
        #expect(try Self.ownedCount(context, companyID: companyID) == 2)
    }
}
