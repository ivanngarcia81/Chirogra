import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Varias empresas en pantalla: el filtro de `@CompanyQuery` y la empresa de lo que se guarda sin `Bookkeeper`.
@MainActor
@Suite("Empresa activa en pantalla", .serialized)
struct CompanyScopeTests {
    let container: ModelContainer
    let firstID: UUID
    let secondID: UUID

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        firstID = try books.setUpCompany(legalName: "Primera LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US")).id
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = CompanyLimits.accountant
        defer { Bookkeeper.companyLimit = saved }
        secondID = try books.forNewCompany().setUpCompany(legalName: "Segunda Inc", entityType: .sCorp, state: "CA",
                                                          locale: Locale(identifier: "es_US")).id
    }

    var context: ModelContext { container.mainContext }

    func customers(in scope: CompanyScope?) throws -> [String] {
        CompanySession.scope = scope
        defer { CompanySession.scope = nil }
        let active = #Predicate<Customer> { !$0.isArchived }
        return try context.fetch(FetchDescriptor(predicate: CompanySession.predicate(active), sortBy: [SortDescriptor(\.name)])).map(\.name)
    }

    @Test("El filtro de la empresa activa: cada una ve lo suyo y la principal, además, lo que no tiene empresa")
    func predicate() throws {
        let first = Bookkeeper(context: context, companyID: firstID)
        let second = Bookkeeper(context: context, companyID: secondID)
        first.insert(Customer(name: "Cliente de la primera"))
        second.insert(Customer(name: "Cliente de la segunda"))
        let archived = Customer(name: "Archivado de la segunda")
        archived.isArchived = true
        second.insert(archived)
        let orphan = Customer(name: "Sin empresa")
        context.insert(orphan)
        try context.save()
        // `context.save()` sin ámbito: el huérfano se queda sin empresa.
        #expect(orphan.companyID == nil)

        let firstScope = try #require(try first.companyScope())
        let secondScope = try #require(try second.companyScope())
        #expect(firstScope.includeOrphans && !secondScope.includeOrphans)
        #expect(try customers(in: firstScope) == ["Cliente de la primera", "Sin empresa"])
        #expect(try customers(in: secondScope) == ["Cliente de la segunda"])
        // Sin empresa activa (antes del alta) no se filtra por empresa.
        #expect(try customers(in: nil).count == 3)
        #expect(CompanySession.key(firstScope) != CompanySession.key(secondScope))
    }

    @Test("Lo que una pantalla inserta con context.insert y guarda con context.save() toma la empresa activa")
    func stampOnSave() throws {
        CompanyStamp.install()
        CompanySession.scope = CompanyScope(id: secondID, includeOrphans: false)
        defer { CompanySession.scope = nil }
        let customer = Customer(name: "Nuevo en la segunda")
        context.insert(customer)
        let alreadyOwned = Customer(name: "Ya era de la primera")
        alreadyOwned.companyID = firstID
        context.insert(alreadyOwned)
        try context.save()
        #expect(customer.companyID == secondID)
        #expect(alreadyOwned.companyID == firstID)
        #expect(try Bookkeeper(context: context, companyID: secondID).fetch(Customer.self).contains { $0.id == customer.id })
    }

    @Test("Límite por plan: sin productos no se limita; con el plan normal, 1, aunque el de contadores no esté a la venta")
    func planLimit() {
        #expect(SubscriptionStore.companyLimit(status: .notConfigured, plan: .standard) == CompanyLimits.accountant)
        #expect(SubscriptionStore.companyLimit(status: .subscribed(isTrial: false, expires: nil), plan: .standard) == CompanyLimits.standard)
        #expect(SubscriptionStore.companyLimit(status: .subscribed(isTrial: true, expires: nil), plan: .accountant) == CompanyLimits.accountant)
        #expect(SubscriptionStore.companyLimit(status: .lapsed, plan: .standard) == CompanyLimits.standard)
        #expect(SubscriptionStore.companyLimit(status: .unknown, plan: .standard) == CompanyLimits.standard)
        #expect(CompanyLimits.isUnlimited(CompanyLimits.accountant))
        // TestFlight (compras de prueba): sin límite, sin el plan para contadores.
        #expect(SubscriptionStore.companyLimit(status: .subscribed(isTrial: false, expires: nil), plan: .standard, isTestFlight: true) == CompanyLimits.accountant)
        #expect(SubscriptionStore.companyLimit(status: .lapsed, plan: .standard, isTestFlight: true) == CompanyLimits.accountant)
    }

    @Test("Cambiar de empresa con un editor sin guardar pregunta antes; si se cancela, no cambia")
    func unsavedChangesOnSwitch() {
        let hub = CompanyHub()
        let unsaved = UnsavedChanges()
        hub.unsavedChanges = unsaved
        CompanySession.scope = CompanyScope(id: firstID, includeOrphans: true)
        defer { CompanySession.scope = nil }
        let saved = ActiveCompany.id
        defer { ActiveCompany.id = saved }
        ActiveCompany.id = firstID

        let token = EditorToken()
        var discarded = false
        unsaved.report(token, hasChanges: true) { discarded = true }
        hub.select(secondID)
        #expect(hub.pendingCompanyID == secondID)
        #expect(ActiveCompany.id == firstID)
        // «Seguir editando»: no se cambia.
        hub.pendingCompanyID = nil
        #expect(ActiveCompany.id == firstID && !discarded)
        // «Descartar»: se pierden los cambios y se cambia.
        hub.select(secondID)
        hub.discardAndSwitch()
        #expect(discarded && ActiveCompany.id == secondID && hub.pendingCompanyID == nil)
        // Sin cambios, al momento.
        CompanySession.scope = CompanyScope(id: secondID, includeOrphans: false)
        hub.select(firstID)
        #expect(ActiveCompany.id == firstID && hub.pendingCompanyID == nil)
        withExtendedLifetime(token) {}
    }

    @Test("Las archivadas cuentan para el límite del plan")
    func archivedCount() throws {
        let books = Bookkeeper(context: context, companyID: firstID)
        let saved = Bookkeeper.companyLimit
        Bookkeeper.companyLimit = 2
        defer { Bookkeeper.companyLimit = saved }
        #expect(try !books.canAddCompany())
        try books.archiveCompany(try #require(try books.companies().first { $0.id == secondID }))
        #expect(try books.companies().count == 1)
        #expect(try !books.canAddCompany())
    }
}
