import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Varias empresas en los mismos libros (esquema 4): cada `Bookkeeper` ve y crea solo lo de la suya.
@MainActor
@Suite("Varias empresas")
struct CompaniesTests {
    let container: ModelContainer
    let first: Bookkeeper
    let firstID: UUID

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        firstID = try books.setUpCompany(legalName: "Primera LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
        first = books.forCompany(firstID)
    }

    var context: ModelContext { container.mainContext }

    /// Da de alta otra empresa con el límite del plan para contadores.
    func addSecond(name: String = "Segunda Inc", sector: BusinessSector = .retail) throws -> Bookkeeper {
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        let books = try first.forNewCompany()
        try books.setUpCompany(legalName: name, entityType: .sCorp, state: "CA", sector: sector, locale: Locale(identifier: "es_US"))
        return books
    }

    func account(_ books: Bookkeeper, _ code: String) throws -> Account {
        try #require(try books.accounts().first { $0.code == code })
    }

    @discardableResult
    func issueInvoice(_ books: Bookkeeper, amount: Int64) throws -> Invoice {
        let customer = Customer(name: "Cliente de \(try books.company()?.name ?? "")")
        books.insert(customer)
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: Date(), dueDate: Date(),
                                                            lines: [.init(details: "Servicio", unitPrice: amount, incomeAccountID: try account(books, "4000").id)]))
        try books.issue(invoice)
        return invoice
    }

    @Test("El límite del plan: una empresa en el normal, cinco en el de contadores")
    func companyLimit() throws {
        #expect(Bookkeeper.companyLimit == CompanyLimits.standard)
        #expect(try !first.canAddCompany())
        #expect(throws: BookkeepingError.companyLimitReached(1)) { try first.forNewCompany() }
        // Con un id nuevo a mano tampoco se salta el límite.
        #expect(throws: BookkeepingError.companyLimitReached(1)) {
            try Bookkeeper(context: context, companyID: UUID()).setUpCompany(legalName: "Tercera")
        }
        // Sin companyID, el alta de siempre sigue diciendo que ya hay empresa.
        #expect(throws: BookkeepingError.companyAlreadyExists) { try Bookkeeper(context: context).setUpCompany(legalName: "Otra") }

        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        for index in 2...5 {
            try first.forNewCompany().setUpCompany(legalName: "Empresa \(index)")
        }
        #expect(try first.companies().count == 5)
        #expect(throws: BookkeepingError.companyLimitReached(5)) { try first.forNewCompany() }
        // Archivar deja sitio; restaurar no puede pasar el límite.
        let archived = try #require(try first.companies().last)
        try first.archiveCompany(archived)
        #expect(try first.canAddCompany())
        try first.forNewCompany().setUpCompany(legalName: "Empresa 6")
        #expect(throws: BookkeepingError.companyLimitReached(5)) { try first.unarchiveCompany(archived) }
        #expect(try first.companies(includeArchived: true).count == 6)
        #expect(try first.companies().map(\.sortOrder) == [0, 1, 2, 3, 5])
    }

    @Test("Cada empresa ve solo lo suyo: cuentas, numeración, facturas, reportes y avisos")
    func scoping() throws {
        let second = try addSecond()
        let secondID = try #require(try second.resolvedCompanyID())
        #expect(secondID != firstID)
        #expect(try second.company()?.legalName == "Segunda Inc")
        #expect(try first.company()?.legalName == "Primera LLC")

        // Cada una con su plan de cuentas (comercio tiene inventario, servicios no).
        #expect(try first.accounts().contains { $0.code == "1200" } == false)
        #expect(try second.accounts().contains { $0.code == "1200" })
        #expect(try first.accounts().allSatisfy { $0.companyID == firstID })
        #expect(try second.accounts().allSatisfy { $0.companyID == secondID })

        // Numeración propia.
        let a = try issueInvoice(first, amount: 100_000)
        let b = try issueInvoice(second, amount: 50_000)
        #expect(a.number == "F-1001" && b.number == "F-1001")
        #expect(try first.entry(id: a.journalEntryID)?.number == 1 && second.entry(id: b.journalEntryID)?.number == 1)
        #expect(a.companyID == firstID && (a.lines ?? []).allSatisfy { $0.companyID == firstID })
        #expect(try first.entry(id: b.journalEntryID) == nil)

        // Reportes separados.
        #expect(try first.receivablesAging(asOf: Date()).total == 100_000)
        #expect(try second.receivablesAging(asOf: Date()).total == 50_000)
        #expect(try first.trialBalance(asOf: .distantFuture).totalDebit == 100_000)
        #expect(try second.trialBalance(asOf: .distantFuture).isBalanced)

        // Una cuenta de la otra empresa no se puede usar.
        let foreign = try account(second, "1010")
        #expect(throws: BookkeepingError.self) {
            try first.post(JournalEntryDraft(date: Date(), lines: [.debit(foreign.id, 100), .credit(try account(first, "3000").id, 100)]))
        }

        // Lista con lo pendiente de cada una.
        let overviews = try first.companyOverviews()
        #expect(overviews.map(\.name) == ["Primera LLC", "Segunda Inc"])
        #expect(overviews.map(\.receivables) == [100_000, 50_000])
    }

    @Test("La empresa activa decide con qué trabaja Bookkeeper(context:)")
    func activeCompany() throws {
        let second = try addSecond()
        let secondID = try #require(try second.resolvedCompanyID())
        // El alta deja activa la nueva.
        #expect(ActiveCompany.id == secondID)
        #expect(try Bookkeeper(context: context).company()?.id == secondID)
        ActiveCompany.id = firstID
        #expect(try Bookkeeper(context: context).company()?.id == firstID)
        // Una activa que no existe en estos libros: la primera del selector.
        ActiveCompany.id = UUID()
        #expect(try Bookkeeper(context: context).resolvedCompanyID() == firstID)
        // Reordenar el selector cambia cuál es la primera.
        try first.reorderCompanies([try #require(try second.company())])
        #expect(try Bookkeeper(context: context).resolvedCompanyID() == secondID)
        // Archivar la activa pasa a la siguiente.
        ActiveCompany.id = secondID
        try first.archiveCompany(try #require(try second.company()))
        #expect(ActiveCompany.id == firstID)
    }

    @Test("Los registros sin empresa cuentan como de la principal hasta que se adoptan")
    func orphans() throws {
        let second = try addSecond()
        let customer = Customer(name: "Llegó de un aparato viejo")
        context.insert(customer)
        try context.save()
        #expect(customer.companyID == nil)
        #expect(try first.fetch(Customer.self).contains { $0.id == customer.id })
        #expect(try !second.fetch(Customer.self).contains { $0.id == customer.id })
        #expect(try first.adoptOrphanRecords() == 1)
        #expect(customer.companyID == firstID)
        #expect(try first.adoptOrphanRecords() == 0)

        // Lo que una pantalla inserte con `context.insert` toma la empresa al guardar con Bookkeeper.
        let vendor = Vendor(name: "Proveedor")
        context.insert(vendor)
        try second.setW9(for: vendor, received: true)
        #expect(vendor.companyID == (try second.resolvedCompanyID()))
    }

    @Test("Borrar una empresa se lleva todo lo suyo y nada de las demás")
    func deleteCompany() throws {
        let second = try addSecond()
        try issueInvoice(first, amount: 10_000)
        try issueInvoice(second, amount: 20_000)
        let before = try MigrationTests.ownedCount(context, companyID: firstID)
        let company = try #require(try second.company())
        ActiveCompany.id = company.id
        try first.deleteCompany(company)
        #expect(try context.fetchCount(FetchDescriptor<Company>()) == 1)
        #expect(try MigrationTests.ownedCount(context, companyID: firstID) == before)
        #expect(try MigrationTests.orphanCount(context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Invoice>()) == 1)
        #expect(ActiveCompany.id == firstID)
        #expect(try first.trialBalance(asOf: .distantFuture).totalDebit == 10_000)
    }

    @Test("La copia es de una empresa y se restaura como nueva o sustituyendo a otra")
    func backupPerCompany() throws {
        let second = try addSecond()
        try issueInvoice(first, amount: 10_000)
        try issueInvoice(second, amount: 20_000)
        let secondID = try #require(try second.resolvedCompanyID())

        let copy = try BackupArchive.make(from: context, companyID: secondID, appVersion: "1.1")
        let info = try BackupArchive.info(of: copy)
        #expect(info.companyName == "Segunda Inc" && info.companyID == secondID)
        #expect(info.count(of: "Company") == 1 && info.count(of: "Invoice") == 1)
        #expect(info.count(of: "Account") == (try second.accounts(includeArchived: true).count))

        // Como empresa nueva mientras la original sigue aquí: ids nuevos para todo.
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        let restored = try BackupArchive.restoreCompany(copy, into: context, mode: .newCompany, actor: "Pruebas")
        #expect(restored.renumbered && restored.companyID != secondID)
        #expect(ActiveCompany.id == restored.companyID)
        let third = first.forCompany(restored.companyID)
        #expect(try third.company()?.legalName == "Segunda Inc")
        #expect(try third.receivablesAging(asOf: Date()).total == 20_000)
        #expect(try third.trialBalance(asOf: .distantFuture).isBalanced)
        #expect(try second.receivablesAging(asOf: Date()).total == 20_000)
        #expect(try first.receivablesAging(asOf: Date()).total == 10_000)
        #expect(try MigrationTests.orphanCount(context) == 0)
        let invoice = try #require(try third.fetch(Invoice.self).first)
        #expect(try third.entry(id: invoice.journalEntryID) != nil)

        // Sustituyendo a la primera: la primera desaparece, las demás no cambian.
        try BackupArchive.restoreCompany(copy, into: context, mode: .replaceCompany(firstID))
        #expect(try context.fetchCount(FetchDescriptor<Company>()) == 3 - 1 + 1 - 0)
        #expect(try first.company() == nil)
        let names = try Bookkeeper(context: context).companies().map(\.legalName)
        #expect(names.filter { $0 == "Segunda Inc" }.count == 3)
    }

    @Test("Una copia de antes del esquema 4 (sin companyID) se restaura entera en una empresa")
    func restoresOldCopy() throws {
        try issueInvoice(first, amount: 10_000)
        let copy = try BackupArchive.make(from: context, appVersion: "1.0")
        // Quita `companyID` de todos los registros y la versión de esquema, como en una copia de la 1.0.1.
        let json = try BackupArchive.decompressed(copy)
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var payload = try #require(object["payload"] as? [String: Any])
        for (key, value) in payload {
            guard var records = value as? [[String: Any]] else { continue }
            for index in records.indices { records[index]["companyID"] = nil }
            payload[key] = records
        }
        object["payload"] = payload
        var info = try #require(object["info"] as? [String: Any])
        info["schemaVersion"] = "3.0.0"
        info["companyID"] = nil
        object["info"] = info
        let old = BackupArchive.signature + (try (JSONSerialization.data(withJSONObject: object) as NSData).compressed(using: .zlib) as Data)

        let target = try ChirograStore.makeContainer(inMemory: true)
        let result = try BackupArchive.restoreCompany(old, into: target.mainContext, mode: .replaceCompany(nil))
        #expect(result.companyID == firstID && !result.renumbered)
        #expect(try MigrationTests.orphanCount(target.mainContext) == 0)
        let books = Bookkeeper(context: target.mainContext, companyID: result.companyID)
        #expect(try books.receivablesAging(asOf: Date()).total == 10_000)
        #expect(try books.trialBalance(asOf: .distantFuture).isBalanced)
    }
}
