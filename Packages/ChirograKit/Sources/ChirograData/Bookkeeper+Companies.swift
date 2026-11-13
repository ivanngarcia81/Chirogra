import ChirograCore
import Foundation
import SwiftData

// MARK: - Varias empresas (esquema 4, docs/DATOS-V4.md §1)
//
// Cada registro lleva `companyID` (todos los modelos salvo `Company`). Un `Bookkeeper` trabaja con **una** empresa:
// la que se le da (`Bookkeeper(context:companyID:)`) o, si no, la **activa** del aparato (`ActiveCompany`, se guarda en
// `UserDefaults`), y si tampoco la hay, la primera del selector. Todo lo que crea lleva su `companyID` y todas sus
// búsquedas filtran por ella.
//
// **Huérfanos:** un registro con `companyID == nil` (llegó de un aparato con una versión anterior, o lo insertó una
// pantalla sin pasar por `Bookkeeper`) cuenta como de la **empresa principal**, la más antigua, que es la única que
// conocían las versiones anteriores. `adoptOrphanRecords()` les pone la empresa para siempre: la app debe llamarlo al
// abrirse y tras sincronizar. Así un usuario con una sola empresa nunca deja de ver nada.

/// Empresa activa en este aparato (no se sincroniza: cada aparato puede estar mirando una distinta).
@MainActor
public enum ActiveCompany {
    /// Clave de `UserDefaults`; guarda `Company.id.uuidString`. La UI puede leerla con `@AppStorage`.
    public static let defaultsKey = "activeCompanyID"
    /// Para pruebas.
    public static var defaults: UserDefaults = .standard

    /// La elegida, aunque ya no exista en los libros (`Bookkeeper.resolvedCompanyID()` lo comprueba).
    public static var id: UUID? {
        get { defaults.string(forKey: defaultsKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: defaultsKey) }
    }

    public static func select(_ company: Company) { id = company.id }
}

/// Límite de empresas según el plan. Cuentan **todas**, también las archivadas (decisión del usuario, 8-nov: archivar
/// no deja sitio; los libros archivados siguen en iCloud). Para hacer sitio hay que borrar una empresa.
public enum CompanyLimits {
    /// Plan normal: una empresa.
    public static let standard = 1
    /// Sin límite.
    public static let unlimited = Int.max
    /// Plan para contadores: **sin límite** (decisión del usuario, 8-nov: el contador lleva muchas empresas; antes 5).
    public static let accountant = unlimited
    /// El límite no limita (para los textos: «sin límite» en vez de un número).
    public static func isUnlimited(_ limit: Int) -> Bool { limit == unlimited }
}

/// Utilidades de la empresa dueña que no necesitan un `Bookkeeper` (también las usa la migración V3 → V4).
public enum CompanyOwnership {

    /// Empresas en el orden del selector: `sortOrder` y, a igualdad, la más antigua primero.
    static func companies(in context: ModelContext) throws -> [Company] {
        try context.fetch(FetchDescriptor<Company>()).sorted {
            ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString)
        }
    }

    /// La empresa principal: la más antigua (fecha de alta y, a igualdad, id). Es la dueña de los huérfanos.
    static func primaryCompany(among companies: [Company]) -> Company? {
        companies.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// Sin leer todas las empresas: la más antigua y, si hay empate de fecha, las empatadas (lo llama cada búsqueda de
    /// `Bookkeeper`; con muchas empresas, leerlas todas cada vez hacía lentas la lista de empresas y el registro).
    public static func primaryCompanyID(in context: ModelContext) throws -> UUID? {
        var oldestFirst = FetchDescriptor<Company>(sortBy: [SortDescriptor(\.createdAt)])
        oldestFirst.fetchLimit = 1
        guard let oldest = try context.fetch(oldestFirst).first else { return nil }
        let created = oldest.createdAt
        let tied = try context.fetch(FetchDescriptor<Company>(predicate: #Predicate { $0.createdAt == created }))
        return primaryCompany(among: tied.isEmpty ? [oldest] : tied)?.id
    }

    /// Da la empresa principal a todo lo que no tiene empresa. Sin empresa no hace nada. No guarda.
    /// - Parameter archivingExtraCompanies: solo en la migración: archiva las demás empresas (libros mezclados de
    ///   antes del esquema 4, sin nada propio) y numera `sortOrder` por antigüedad.
    /// - Returns: cuántos registros cambió.
    @discardableResult
    /// `types`: las clases de los modelos; la migración 3 → 4 pasa las del esquema 4 (`ownedTypesV4`), que es el del
    /// almacén en ese momento (con las del 5, Core Data no encuentra sus propiedades nuevas y la app se cierra).
    public static func adoptOrphans(in context: ModelContext, archivingExtraCompanies: Bool = false,
                                    types: [any CompanyOwned.Type] = ownedTypes) throws -> Int {
        let companies = try context.fetch(FetchDescriptor<Company>())
        guard let primary = primaryCompany(among: companies) else { return 0 }
        if archivingExtraCompanies {
            let byAge = companies.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for (index, company) in byAge.enumerated() {
                company.sortOrder = index
                if company.id != primary.id, !company.isArchived {
                    company.isArchived = true
                    company.archivedAt = company.archivedAt ?? Date()
                }
            }
        }
        var changed = 0
        for type in types {
            changed += try adopt(type, companyID: primary.id, in: context)
        }
        return changed
    }

    private static func adopt<T: CompanyOwned>(_ type: T.Type, companyID: UUID, in context: ModelContext) throws -> Int {
        let orphans = try context.fetch(FetchDescriptor<T>(predicate: T.orphans))
        for model in orphans { model.companyID = companyID }
        return orphans.count
    }

    /// Registros de una empresa (con los huérfanos si es la principal), de un tipo.
    static func records<T: CompanyOwned>(_ type: T.Type, companyID: UUID, includeOrphans: Bool, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(predicate: T.ownedBy(companyID, includeOrphans: includeOrphans)))
    }
}

extension CompanyOwned {
    /// Los que no tienen empresa.
    static var orphans: Predicate<Self> { ownedBy(UUID(), includeOrphans: true) }
}

// MARK: - Ámbito de un Bookkeeper

/// Empresa con la que trabaja un `Bookkeeper` (`Bookkeeper.companyScope()`), y con ella el filtro para las `@Query`.
public struct CompanyScope: Sendable, Equatable {
    public let id: UUID
    /// Es la principal: también ve los registros sin empresa.
    public let includeOrphans: Bool

    public init(id: UUID, includeOrphans: Bool) {
        self.id = id
        self.includeOrphans = includeOrphans
    }

    /// Los registros de esta empresa: `@Query(filter: scope.predicate(Invoice.self))`.
    public func predicate<T: CompanyOwned>(_ type: T.Type) -> Predicate<T> {
        T.ownedBy(id, includeOrphans: includeOrphans)
    }
}

extension Bookkeeper {

    /// Empresa con la que trabaja: la dada al crearlo; si no, la activa del aparato si existe en estos libros; si no,
    /// la primera del selector que no esté archivada (o la primera). `nil` si no hay ninguna empresa.
    public func resolvedCompanyID() throws -> UUID? {
        try scope()?.id
    }

    /// La empresa de este `Bookkeeper` y si es la principal (ve los huérfanos), para filtrar las `@Query` de la UI.
    /// `nil` si no hay ninguna empresa.
    public func companyScope() throws -> CompanyScope? {
        try scope()
    }

    /// Se llama en cada búsqueda: no lee todas las empresas salvo si no hay activa (con muchas empresas, hacerlo cada
    /// vez lo volvía lento todo).
    func scope() throws -> CompanyScope? {
        let id: UUID
        if let companyID {
            id = companyID
        } else if let active = ActiveCompany.id,
                  try context.fetchCount(FetchDescriptor<Company>(predicate: #Predicate { $0.id == active })) > 0 {
            id = active
        } else {
            let companies = try CompanyOwnership.companies(in: context)
            guard let first = companies.first(where: { !$0.isArchived }) ?? companies.first else { return nil }
            id = first.id
        }
        let primary = try CompanyOwnership.primaryCompanyID(in: context)
        return CompanyScope(id: id, includeOrphans: primary == nil || primary == id)
    }

    /// `predicate` limitado a la empresa de este `Bookkeeper` (`&&`). Sin empresa, `predicate` tal cual. Sirve también
    /// para un `FetchDescriptor` de la UI: `FetchDescriptor(predicate: try books.scoped(#Predicate<Bill> { $0.autoPay }))`.
    public func scoped<T: CompanyOwned>(_ predicate: Predicate<T>?) throws -> Predicate<T>? {
        guard let scope = try scope() else { return predicate }
        let owned = T.ownedBy(scope.id, includeOrphans: scope.includeOrphans)
        guard let predicate else { return owned }
        return #Predicate<T> { owned.evaluate($0) && predicate.evaluate($0) }
    }

    /// Búsqueda limitada a la empresa de este `Bookkeeper`.
    public func fetch<T: CompanyOwned>(_ type: T.Type, _ predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = [],
                                limit: Int? = nil) throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: try scoped(predicate), sortBy: sortBy)
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func count<T: CompanyOwned>(_ type: T.Type, _ predicate: Predicate<T>? = nil) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>(predicate: try scoped(predicate)))
    }

    /// Inserta un modelo con la empresa de este `Bookkeeper`. Úsalo en vez de `context.insert` en todo lo que crea
    /// `Bookkeeper` (y en lo que creen las pantallas, si no pasa por un servicio).
    public func insert<T: CompanyOwned>(_ model: T) {
        if model.companyID == nil { model.companyID = (try? resolvedCompanyID()) ?? nil }
        context.insert(model)
    }

    /// Red de seguridad antes de guardar: lo insertado sin empresa (p. ej. con `context.insert`) toma la de este
    /// `Bookkeeper`.
    func stampInsertedModels() {
        let pending = context.insertedModelsArray.compactMap { $0 as? any CompanyOwned }.filter { $0.companyID == nil }
        guard !pending.isEmpty, let id = try? resolvedCompanyID() else { return }
        for model in pending { stamp(model, id) }
    }

    private func stamp<T: CompanyOwned>(_ model: T, _ id: UUID) { model.companyID = id }
}

// MARK: - Lista, alta, orden, archivo y borrado de empresas

/// Lo pendiente de una empresa, para la lista de empresas (PLAN-FASE2 §1: «lista con lo pendiente de cada una»).
public struct CompanyOverview: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var isArchived: Bool
    public var isActive: Bool
    /// Por cobrar: saldo de las facturas emitidas pendientes, y cuántas están vencidas.
    public var receivables: Int64
    public var overdueInvoices: Int
    /// Por pagar: saldo de las facturas de proveedor registradas pendientes.
    public var payables: Int64
    /// Avisos sin leer de la campana.
    public var unreadNotices: Int
    /// Movimientos bancarios «por revisar».
    public var bankTransactionsToReview: Int
}

extension Bookkeeper {

    /// Límite de empresas, archivadas incluidas. La app lo pone según la suscripción (`CompanyLimits.standard` o
    /// `.accountant`). Crear la primera empresa siempre se puede.
    public static var companyLimit = CompanyLimits.standard

    /// Empresas en el orden del selector. Por defecto, sin las archivadas.
    public func companies(includeArchived: Bool = false) throws -> [Company] {
        try CompanyOwnership.companies(in: context).filter { includeArchived || !$0.isArchived }
    }

    /// Se puede añadir otra empresa sin pasar el límite del plan. Las archivadas también cuentan.
    public func canAddCompany() throws -> Bool {
        try companies(includeArchived: true).count < Self.companyLimit
    }

    /// Un `Bookkeeper` para dar de alta **otra** empresa: con un id nuevo, todavía sin empresa. Con él se hace el alta
    /// de siempre (`setUpCompany`, que además la deja activa, y después `setUpSalesTax`, `recordOpeningBalances`…).
    /// Falla con `companyLimitReached` si ya se llegó al límite del plan.
    public func forNewCompany() throws -> Bookkeeper {
        guard try canAddCompany() else { throw BookkeepingError.companyLimitReached(Self.companyLimit) }
        return Bookkeeper(context: context, actor: actor, companyID: UUID())
    }

    /// El mismo `Bookkeeper` para otra empresa (p. ej. para la lista de empresas).
    public func forCompany(_ id: UUID) -> Bookkeeper {
        var copy = self
        copy.companyID = id
        return copy
    }

    /// La deja como activa en este aparato.
    public func select(_ company: Company) {
        ActiveCompany.select(company)
    }

    /// Cambia el orden del selector: `ordered` en el orden nuevo (las que falten conservan el suyo, detrás).
    public func reorderCompanies(_ ordered: [Company]) throws {
        let rest = try companies(includeArchived: true).filter { company in !ordered.contains { $0.id == company.id } }
        for (index, company) in (ordered + rest).enumerated() { company.sortOrder = index }
        try saveOrRollback()
    }

    /// Archiva una empresa: sale del selector; sus libros se quedan y sigue contando para el límite del plan. Si era la
    /// activa, la activa pasa a ser la primera que quede.
    public func archiveCompany(_ company: Company) throws {
        guard !company.isArchived else { return }
        company.isArchived = true
        company.archivedAt = Date()
        forCompany(company.id).audit("Company", company.id, "archive", String(localized: "Empresa archivada: \(company.name)"))
        try saveOrRollback()
        if ActiveCompany.id == company.id { ActiveCompany.id = try companies().first?.id }
    }

    /// Vuelve a mostrar una empresa archivada. Siempre se puede: las archivadas ya cuentan para el límite del plan.
    public func unarchiveCompany(_ company: Company) throws {
        guard company.isArchived else { return }
        company.isArchived = false
        company.archivedAt = nil
        forCompany(company.id).audit("Company", company.id, "unarchive", String(localized: "Empresa restaurada: \(company.name)"))
        try saveOrRollback()
    }

    /// Borra una empresa **con todos sus libros** (todos los registros con su `companyID` y, si es la principal, los
    /// huérfanos), uno a uno para que el borrado llegue por iCloud a los otros aparatos, en un solo guardado. No se
    /// puede deshacer: la UI debe pedir confirmación (y ofrecer antes una copia, `BackupArchive.make`).
    public func deleteCompany(_ company: Company) throws {
        let id = company.id
        let isPrimary = try CompanyOwnership.primaryCompanyID(in: context) == id
        do {
            try ensureWritable()
            for type in CompanyOwnership.ownedTypes {
                try Self.deleteRecords(type, companyID: id, includeOrphans: isPrimary, in: context)
            }
            context.delete(company)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        // Que ningún aparato atrasado la vuelva a subir (`DeletedCompanies`).
        DeletedCompanies.record([id])
        if ActiveCompany.id == id { ActiveCompany.id = try companies().first?.id }
    }

    static func deleteRecords<T: CompanyOwned>(_ type: T.Type, companyID: UUID, includeOrphans: Bool, in context: ModelContext) throws {
        for model in try CompanyOwnership.records(type, companyID: companyID, includeOrphans: includeOrphans, in: context) {
            context.delete(model)
        }
    }

    /// Da la empresa principal a los registros sin empresa (ver arriba) y guarda si cambió algo. Llamarlo al abrir la
    /// app y tras cada sincronización de iCloud. Devuelve cuántos cambió.
    @discardableResult
    public func adoptOrphanRecords() throws -> Int {
        let changed = try CompanyOwnership.adoptOrphans(in: context)
        if changed > 0 { try saveOrRollback() }
        return changed
    }

    /// Resumen de lo pendiente de cada empresa (incluidas las archivadas si se pide), en el orden del selector.
    public func companyOverviews(includeArchived: Bool = false, asOf date: Date = Date()) throws -> [CompanyOverview] {
        let active = try resolvedCompanyID()
        return try companies(includeArchived: includeArchived).map { company in
            let books = forCompany(company.id)
            let invoices = try books.fetch(Invoice.self).filter { $0.isOpen && $0.balanceDue != 0 }
            let bills = try books.fetch(Bill.self).filter { $0.isOpen && $0.journalEntryID != nil }
            let toReview = BankTransactionStatus.toReview.rawValue
            return CompanyOverview(
                id: company.id, name: company.name, isArchived: company.isArchived, isActive: company.id == active,
                receivables: invoices.reduce(0) { $0 + $1.balanceDue },
                overdueInvoices: invoices.filter { $0.daysOverdue(asOf: date) != nil }.count,
                payables: bills.reduce(0) { $0 + $1.balanceDue },
                unreadNotices: try books.unreadNoticeCount(asOf: date),
                bankTransactionsToReview: try books.count(BankTransaction.self, #Predicate { $0.statusRaw == toReview })
            )
        }
    }
}
