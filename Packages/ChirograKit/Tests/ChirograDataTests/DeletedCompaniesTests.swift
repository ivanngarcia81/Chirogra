import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Empresas borradas apuntadas en iCloud (`DeletedCompanies`, build 42): lo que un aparato atrasado vuelva a subir de
/// una empresa borrada se borra otra vez, sin tocar las demás ni los registros sin empresa.
@MainActor
@Suite("Empresas borradas", .serialized)
struct DeletedCompaniesTests {
    let container: ModelContainer
    let first: Bookkeeper
    let firstID: UUID
    let storage = MemoryDeletedCompanyStorage()

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        firstID = try books.setUpCompany(legalName: "Primera LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
        first = books.forCompany(firstID)
    }

    var context: ModelContext { container.mainContext }

    /// Con iCloud encendido y la lista en memoria; al terminar, como estaba (las demás pruebas no la usan).
    func withICloud<T>(_ body: () throws -> T) rethrows -> T {
        let (savedStorage, savedEnabled) = (DeletedCompanies.storage, DeletedCompanies.isEnabled)
        DeletedCompanies.storage = storage
        DeletedCompanies.isEnabled = true
        defer { DeletedCompanies.storage = savedStorage; DeletedCompanies.isEnabled = savedEnabled }
        return try body()
    }

    func addSecond(name: String = "Segunda Inc") throws -> Bookkeeper {
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        let books = try first.forNewCompany()
        try books.setUpCompany(legalName: name, entityType: .sCorp, state: "CA", locale: Locale(identifier: "es_US"))
        return books
    }

    /// Lo que subiría un aparato atrasado: la empresa con su mismo id y un cliente suyo.
    func resurrect(_ id: UUID, name: String) throws {
        let company = Company(legalName: name)
        company.id = id
        context.insert(company)
        let customer = Customer(name: "Cliente que volvió")
        customer.companyID = id
        context.insert(customer)
        try context.save()
    }

    @Test("Borrar una empresa la apunta, y lo que vuelva de ella se borra otra vez")
    func deleteThenSweep() throws {
        try withICloud {
            let second = try addSecond()
            let secondID = try #require(try second.resolvedCompanyID())
            let customersOfFirst = try first.fetch(Customer.self).count
            try first.deleteCompany(try #require(try second.company()))
            #expect(DeletedCompanies.ids == [secondID])
            #expect(try DeletedCompanies.sweep(in: context) == 0)

            try resurrect(secondID, name: "Segunda Inc")
            let orphan = Customer(name: "Sin empresa")
            context.insert(orphan)
            try context.save()
            ActiveCompany.id = secondID

            #expect(try DeletedCompanies.sweep(in: context) == 2)
            let companies = try context.fetch(FetchDescriptor<Company>())
            #expect(companies.map(\.id) == [firstID])
            #expect(try MigrationTests.ownedCount(context, companyID: secondID) == 0)
            // Los registros sin empresa no se tocan (son de la principal).
            #expect(try MigrationTests.orphanCount(context) == 1)
            #expect(try first.fetch(Customer.self).count == customersOfFirst + 1)
            #expect(ActiveCompany.id == firstID)
            #expect(try DeletedCompanies.sweep(in: context) == 0)
        }
    }

    @Test("Sin iCloud no se apunta ni se barre nada")
    func withoutICloud() throws {
        let (savedStorage, savedEnabled) = (DeletedCompanies.storage, DeletedCompanies.isEnabled)
        DeletedCompanies.storage = storage
        DeletedCompanies.isEnabled = false
        defer { DeletedCompanies.storage = savedStorage; DeletedCompanies.isEnabled = savedEnabled }
        let second = try addSecond()
        let secondID = try #require(try second.resolvedCompanyID())
        try first.deleteCompany(try #require(try second.company()))
        #expect(storage.entries.isEmpty)
        try resurrect(secondID, name: "Segunda Inc")
        #expect(try DeletedCompanies.sweep(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Company>()) == 2)
    }

    @Test("Borrar todo apunta todas las empresas")
    func eraseAllRecords() throws {
        try withICloud {
            let second = try addSecond()
            let secondID = try #require(try second.resolvedCompanyID())
            try BackupArchive.eraseAll(in: context)
            #expect(DeletedCompanies.ids == [firstID, secondID])
            #expect(ActiveCompany.id == nil)
            #expect(try context.fetchCount(FetchDescriptor<Company>()) == 0)

            // Una empresa nueva después no se toca.
            let fresh = Bookkeeper(context: context, actor: "Pruebas")
            let freshID = try fresh.setUpCompany(legalName: "Nueva LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
            try resurrect(firstID, name: "Primera LLC")
            #expect(try DeletedCompanies.sweep(in: context) == 2)
            #expect(try context.fetch(FetchDescriptor<Company>()).map(\.id) == [freshID])
        }
    }

    @Test("La copia de una empresa borrada se restaura con ids nuevos y el barrido no la toca")
    func restoreDeletedCompany() throws {
        try withICloud {
            let second = try addSecond()
            let secondID = try #require(try second.resolvedCompanyID())
            let copy = try BackupArchive.make(from: context, companyID: secondID, appVersion: "1.2")
            try first.deleteCompany(try #require(try second.company()))

            let saved = Bookkeeper.companyLimit
            Bookkeeper.companyLimit = CompanyLimits.accountant
            defer { Bookkeeper.companyLimit = saved }
            let result = try BackupArchive.restoreCompany(copy, into: context, mode: .newCompany, actor: "Pruebas")
            #expect(result.companyID != secondID)
            #expect(result.renumbered)
            #expect(try DeletedCompanies.sweep(in: context) == 0)
            #expect(try context.fetchCount(FetchDescriptor<Company>()) == 2)
            #expect(try MigrationTests.ownedCount(context, companyID: result.companyID) > 0)
        }
    }

    @Test("Sustituir una empresa por la copia de otra apunta la sustituida")
    func replaceRecordsReplaced() throws {
        try withICloud {
            let second = try addSecond()
            let secondID = try #require(try second.resolvedCompanyID())
            let copy = try BackupArchive.make(from: context, companyID: secondID, appVersion: "1.2")
            try first.deleteCompany(try #require(try second.company()))
            storage.removeObject(forKey: DeletedCompanies.keyPrefix + secondID.uuidString)

            // La copia vuelve con su id (nadie la tiene apuntada) en lugar de la primera, que queda apuntada.
            let result = try BackupArchive.restoreCompany(copy, into: context, mode: .replaceCompany(firstID), actor: "Pruebas")
            #expect(result.companyID == secondID)
            #expect(DeletedCompanies.ids == [firstID])
            // Restaurar la copia de la misma empresa en su lugar no apunta nada.
            let again = try BackupArchive.make(from: context, companyID: secondID, appVersion: "1.2")
            try BackupArchive.restoreCompany(again, into: context, mode: .replaceCompany(secondID), actor: "Pruebas")
            #expect(DeletedCompanies.ids == [firstID])
        }
    }
}
