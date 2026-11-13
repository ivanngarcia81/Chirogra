import Foundation
import SwiftData

// MARK: - Empresas borradas (1.2, build 42)
//
// Borrar una empresa ya borra sus registros uno a uno para que el borrado viaje por iCloud (`Bookkeeper.deleteCompany`).
// Pero un aparato que todavía tiene esos libros puede volver a subirlos: uno que estuvo cerrado y escribe en ellos al
// abrir (recurrentes, cargos automáticos) antes de recibir el borrado, uno en el que se enciende iCloud con libros
// propios, o todos después de borrar los datos de iCloud desde los Ajustes del sistema. CloudKit los toma por registros
// nuevos y la empresa «vuelve» en todos los aparatos (lo vio el usuario el 13-nov).
//
// Por eso cada empresa borrada se apunta, por su id, en el almacén de clave-valor de iCloud
// (`NSUbiquitousKeyValueStore`, aparte de CloudKit: no cambia el esquema ni hay que desplegar nada) y cada aparato, al
// abrir, tras cada importación de iCloud y cuando cambia esa lista, borra lo que encuentre de esas empresas
// (`sweep(in:)`). Si un aparato atrasado sube algo, se vuelve a borrar solo en todos.
//
// - Solo con iCloud encendido en el aparato (`isEnabled`, lo fija la app al abrir): sin iCloud los libros son solo
//   de este aparato y no se apunta ni se barre nada.
// - Nunca se borran los registros sin empresa (`companyID == nil`): son de la principal (`adoptOrphanRecords`).
// - Restaurar la copia de una empresa borrada no la resucita con su id: `BackupArchive.restoreCompany` le da ids nuevos
//   (si no, un aparato que aún no supiera que se restauró la volvería a borrar).
// - Una clave por empresa (`deletedCompany.<id>` → fecha), no una lista en una sola clave: el almacén de clave-valor
//   resuelve los choques por clave y el último que escribe gana, así dos aparatos que borran a la vez no se pisan.

/// Dónde se apuntan las empresas borradas: `NSUbiquitousKeyValueStore.default` en la app; en las pruebas, en memoria.
public protocol DeletedCompanyStorage: AnyObject {
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    var entries: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: DeletedCompanyStorage {
    public var entries: [String: Any] { dictionaryRepresentation }
}

/// Para las pruebas.
public final class MemoryDeletedCompanyStorage: DeletedCompanyStorage {
    public private(set) var entries: [String: Any] = [:]
    public init() {}
    public func set(_ value: Any?, forKey key: String) { entries[key] = value }
    public func removeObject(forKey key: String) { entries[key] = nil }
    public func synchronize() -> Bool { true }
}

@MainActor
public enum DeletedCompanies {
    /// El almacén de clave-valor de iCloud. Necesita el permiso `com.apple.developer.ubiquity-kvstore-identifier`.
    public static var storage: any DeletedCompanyStorage = NSUbiquitousKeyValueStore.default
    /// iCloud está encendido en este aparato (lo fija la app al abrir los libros con CloudKit). Apagado, ni se apunta
    /// ni se barre.
    public static var isEnabled = false

    static let keyPrefix = "deletedCompany."

    /// Apunta empresas borradas (con la fecha, para poder mirarlo). Lo llaman `deleteCompany`, `eraseAll` y restaurar
    /// en lugar de otra empresa, después de guardar el borrado.
    public static func record(_ ids: some Sequence<UUID>, at date: Date = Date()) {
        guard isEnabled else { return }
        var any = false
        for id in ids {
            storage.set(date.timeIntervalSince1970, forKey: keyPrefix + id.uuidString)
            any = true
        }
        if any { storage.synchronize() }
    }

    /// Las empresas borradas que se conocen (vacío sin iCloud).
    public static var ids: Set<UUID> { isEnabled ? recordedIDs : [] }

    /// Las apuntadas, aunque iCloud esté apagado en este aparato: restaurar una copia les da ids nuevos, para que otro
    /// aparato no la borre.
    static var recordedIDs: Set<UUID> {
        Set(storage.entries.keys.compactMap { key in
            key.hasPrefix(keyPrefix) ? UUID(uuidString: String(key.dropFirst(keyPrefix.count))) : nil
        })
    }

    /// Borra todo lo que quede de las empresas apuntadas (la empresa y sus registros con su `companyID`, uno a uno para
    /// que el borrado viaje por iCloud), en un solo guardado; si algo falla no cambia nada. Si la empresa activa era una
    /// de ellas, pasa a la primera que quede. Sin nada que borrar no guarda.
    /// - Returns: cuántos registros borró (las empresas incluidas).
    @discardableResult
    public static func sweep(in context: ModelContext) throws -> Int {
        let ids = self.ids
        guard !ids.isEmpty else { return 0 }
        var deleted = 0
        do {
            for id in ids {
                for type in CompanyOwnership.ownedTypes {
                    deleted += try deleteRecords(type, companyID: id, in: context)
                }
                for company in try context.fetch(FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })) {
                    context.delete(company)
                    deleted += 1
                }
            }
            if deleted > 0 { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
        if deleted > 0, let active = ActiveCompany.id, ids.contains(active) {
            ActiveCompany.id = try? CompanyOwnership.companies(in: context).first?.id
        }
        return deleted
    }

    private static func deleteRecords<T: CompanyOwned>(_ type: T.Type, companyID: UUID, in context: ModelContext) throws -> Int {
        let records = try CompanyOwnership.records(type, companyID: companyID, includeOrphans: false, in: context)
        for model in records { context.delete(model) }
        return records.count
    }
}
