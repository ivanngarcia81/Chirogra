import Foundation
import SwiftData

/// Copia de seguridad exportable (DISEÑO §6.5): un archivo `.chirogra` con los libros completos de **una empresa** —todos
/// sus modelos y los recibos, logos y W-9 adjuntos— independiente de iCloud. Sirve también para entregarle los libros a
/// un cliente (PLAN-FASE2 §1).
///
/// Formato 1: la firma `CHIROGRA-COPIA-1\n` seguida de JSON comprimido con zlib (`BackupFile`: `info` y `payload`).
/// Cada modelo es un registro con sus propiedades guardadas y sus relaciones a uno por `id`
/// (`Backup+Generated.swift`, que escribe `scripts/gen-backup.py`). Las propiedades que falten en una copia de un
/// esquema anterior toman su valor por defecto; una copia de un esquema más nuevo no se abre.
///
/// Esquema 4: la copia es de la empresa activa (o la que se pida) y sus registros con su `companyID`. Al restaurar, la
/// copia **sustituye a una empresa** (la activa, por defecto) o entra **como empresa nueva** (`RestoreMode`); las
/// demás empresas no se tocan. Las copias de antes (sin `companyID`) se restauran igual: todo es de la empresa de la
/// copia (si una copia vieja traía varias empresas, de libros mezclados, la más antigua; las demás no se restauran).
/// Si algún id de la copia ya existe en otra empresa (p. ej. al restaurar como nueva la copia de una empresa que sigue
/// aquí), se le dan ids nuevos a todo, conservando las referencias.
///
/// Restaurar primero prueba la copia en un almacén en memoria y después borra la empresa sustituida y crea los
/// registros de la copia en un solo guardado; si algo falla no cambia nada. Con iCloud, el cambio llega a los otros aparatos.
public enum BackupArchive {
    public static let fileExtension = "chirogra"
    public static let formatVersion = 1
    static let signature = Data("CHIROGRA-COPIA-1\n".utf8)

    /// Datos de la copia que se muestran antes de restaurarla.
    public struct Info: Codable, Sendable, Equatable {
        public var formatVersion: Int
        public var schemaVersion: String
        public var createdAt: Date
        public var appVersion: String
        public var companyName: String
        /// Registros por entidad («Invoice»: 12…).
        public var counts: [String: Int]
        /// Esquema 4: id de la empresa copiada (`nil` en las copias de antes).
        public var companyID: UUID?

        public var recordCount: Int { counts.values.reduce(0, +) }
        public func count(of entity: String) -> Int { counts[entity] ?? 0 }
    }

    /// Dónde va la copia al restaurarla.
    public enum RestoreMode: Equatable, Sendable {
        /// Sustituye a esa empresa (sus libros se borran); `nil` = la activa. Sin empresas, simplemente se crea.
        case replaceCompany(UUID?)
        /// Entra como una empresa más (dentro del límite del plan, `Bookkeeper.companyLimit`).
        case newCompany
    }

    /// Resultado de restaurar: los datos de la copia y la empresa restaurada (queda activa).
    public struct RestoreResult: Sendable, Equatable {
        public var info: Info
        public var companyID: UUID
        /// Se dieron ids nuevos a los registros (porque ya existían en otra empresa).
        public var renumbered: Bool
    }

    struct BackupFile: Codable {
        var info: Info
        var payload: BackupPayload
    }

    static var schemaVersion: String {
        let version = SchemaV5.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// Copia de la empresa activa de `context` (la que usa `Bookkeeper(context:)`).
    @MainActor
    public static func make(from context: ModelContext, appVersion: String, now: Date = Date()) throws -> Data {
        try make(from: context, companyID: Bookkeeper(context: context).resolvedCompanyID(), appVersion: appVersion, now: now)
    }

    /// Copia de una empresa (sus registros y, si es la principal, los que no tienen empresa). Con `companyID == nil`
    /// (libros sin empresa) copia todo.
    @MainActor
    public static func make(from context: ModelContext, companyID: UUID?, appVersion: String, now: Date = Date()) throws -> Data {
        let primary = try CompanyOwnership.primaryCompanyID(in: context)
        let scope = BackupScope(companyID: companyID, includeOrphans: companyID == nil || companyID == primary)
        let payload = try BackupPayload(context: context, scope: scope)
        let company = try context.fetch(scope.companies()).first
        let info = Info(formatVersion: formatVersion, schemaVersion: schemaVersion, createdAt: now, appVersion: appVersion,
                        companyName: company?.name ?? "", counts: payload.counts, companyID: company?.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(BackupFile(info: info, payload: payload))
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        return signature + compressed
    }

    /// Lee los datos de la copia sin tocar los libros.
    public static func info(of data: Data) throws -> Info {
        try decode(data).info
    }

    /// Sustituye la empresa activa por la de la copia (como antes del esquema 4, cuando había una sola empresa).
    @MainActor
    @discardableResult
    public static func restore(_ data: Data, into context: ModelContext, actor: String = "") throws -> Info {
        try restoreCompany(data, into: context, mode: .replaceCompany(nil), actor: actor).info
    }

    /// Restaura la copia sustituyendo una empresa o como empresa nueva, en un solo guardado, y la deja activa.
    @MainActor
    @discardableResult
    public static func restoreCompany(_ data: Data, into context: ModelContext, mode: RestoreMode, actor: String = "") throws -> RestoreResult {
        let json = try decompressed(data)
        _ = try decode(data)   // firma, versión y que se lea
        let books = Bookkeeper(context: context, actor: actor)
        let replaced: UUID?
        switch mode {
        case .replaceCompany(let id):
            replaced = try id ?? books.resolvedCompanyID()
        case .newCompany:
            replaced = nil
            if try !books.companies().isEmpty, try !books.canAddCompany() {
                throw BookkeepingError.companyLimitReached(Bookkeeper.companyLimit)
            }
        }
        let primary = try CompanyOwnership.primaryCompanyID(in: context)
        let replacedScope = replaced.map { BackupScope(companyID: $0, includeOrphans: $0 == primary) }
        let prepared = try prepare(json, keepingIDsUnlessIn: try existingIDs(in: context, excluding: replacedScope))
        let file: BackupFile
        do {
            file = try JSONDecoder().decode(BackupFile.self, from: prepared.json)
        } catch {
            throw BackupError.damaged
        }
        // Primero, de prueba en un almacén en memoria: si la copia tiene una referencia rota, falla ahí sin tocar los
        // libros (deshacer a medias un borrado con cascadas no es fiable en SwiftData).
        let trial = try ChirograStore.makeContainer(inMemory: true)
        try file.payload.insert(into: trial.mainContext)
        try trial.mainContext.save()
        do {
            if let replacedScope { try delete(replacedScope, in: context) }
            try file.payload.insert(into: context)
            let summary = String(localized: "Copia restaurada del \(file.info.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Bookkeeper(context: context, actor: actor, companyID: prepared.companyID)
                .insert(AuditEvent(actor: actor, entityName: "Backup", entityID: nil, action: "restore", summary: summary))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        ActiveCompany.id = prepared.companyID
        return RestoreResult(info: file.info, companyID: prepared.companyID, renumbered: prepared.renumbered)
    }

    /// Nombre de archivo sugerido: «Chirogra · Ríos Diseño & Obra · 2026-11-03.chirogra».
    public static func suggestedFilename(companyName: String, date: Date = Date()) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let company = companyName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return (company.isEmpty ? "Chirogra · \(day)" : "Chirogra · \(company) · \(day)") + ".\(fileExtension)"
    }

    static func decompressed(_ data: Data) throws -> Data {
        guard data.starts(with: signature) else { throw BackupError.notABackup }
        do {
            return try (data.dropFirst(signature.count) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw BackupError.damaged
        }
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let json = try decompressed(data)
        struct Header: Decodable { var info: Info }
        guard let header = try? JSONDecoder().decode(Header.self, from: json) else { throw BackupError.damaged }
        guard header.info.formatVersion <= formatVersion,
              header.info.schemaVersion.compare(schemaVersion, options: .numeric) != .orderedDescending
        else { throw BackupError.newerVersion }
        do {
            return try JSONDecoder().decode(BackupFile.self, from: json)
        } catch {
            throw BackupError.damaged
        }
    }

    // MARK: Preparar la copia para una empresa

    struct Prepared {
        var json: Data
        var companyID: UUID
        var renumbered: Bool
    }

    /// Deja la copia lista para entrar como una empresa: una sola empresa (la más antigua, en copias viejas con varias),
    /// `companyID` en todos los registros y, si algún id choca con `existing`, ids nuevos para todo.
    static func prepare(_ json: Data, keepingIDsUnlessIn existing: Set<String>) throws -> Prepared {
        guard var object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              var payload = object["payload"] as? [String: Any] else { throw BackupError.damaged }
        var companies = payload["company"] as? [[String: Any]] ?? []
        if companies.count > 1 {
            companies.sort { a, b in
                let (da, db) = ((a["createdAt"] as? Double) ?? 0, (b["createdAt"] as? Double) ?? 0)
                return da != db ? da < db : ((a["id"] as? String) ?? "") < ((b["id"] as? String) ?? "")
            }
            companies = [companies[0]]
            payload["company"] = companies
        }
        guard let company = companies.first, let sourceID = company["id"] as? String else { throw BackupError.damaged }

        var ids = Set<String>()
        for case let records as [[String: Any]] in payload.values {
            for record in records { if let id = record["id"] as? String { ids.insert(id) } }
        }
        let renumber = !ids.isDisjoint(with: existing)
        var mapping: [String: String] = [:]
        if renumber { for id in ids { mapping[id] = UUID().uuidString } }
        let companyID = mapping[sourceID] ?? sourceID

        func remap(_ value: Any) -> Any {
            switch value {
            case let text as String: mapping[text] ?? text
            case let list as [Any]: list.map(remap)
            case let dictionary as [String: Any]: dictionary.mapValues(remap)
            default: value
            }
        }
        for (key, value) in payload {
            guard var records = value as? [[String: Any]] else { continue }
            records = records.map { record in
                var record = renumber ? (remap(record) as? [String: Any] ?? record) : record
                if key != "company" { record["companyID"] = companyID }
                return record
            }
            payload[key] = records
        }
        object["payload"] = payload
        guard let uuid = UUID(uuidString: companyID) else { throw BackupError.damaged }
        return Prepared(json: try JSONSerialization.data(withJSONObject: object), companyID: uuid, renumbered: renumber)
    }

    /// Ids (en texto) de todos los registros de los libros, salvo los de la empresa que se va a sustituir.
    @MainActor
    static func existingIDs(in context: ModelContext, excluding scope: BackupScope?) throws -> Set<String> {
        var ids = Set(try context.fetch(FetchDescriptor<Company>()).filter { $0.id != scope?.companyID }.map(\.id.uuidString))
        for type in CompanyOwnership.ownedTypes { ids.formUnion(try idsOf(type, excluding: scope, in: context)) }
        return ids
    }

    @MainActor
    private static func idsOf<T: CompanyOwned>(_ type: T.Type, excluding scope: BackupScope?, in context: ModelContext) throws -> [String] {
        let all = try context.fetch(FetchDescriptor<T>())
        guard let scope, let companyID = scope.companyID else { return all.map(\.id.uuidString) }
        return all.filter { !($0.companyID == companyID || (scope.includeOrphans && $0.companyID == nil)) }.map(\.id.uuidString)
    }

    // MARK: Borrar

    /// Borra todos los registros de los libros (todas las empresas, todos los modelos) en un solo guardado; si algo
    /// falla no cambia nada. Lo usa «Empezar con mi empresa» para quitar los datos de ejemplo (`SampleData.discard`).
    @MainActor
    public static func eraseAll(in context: ModelContext) throws {
        do {
            for type in BackupPayload.modelTypes { try deleteAll(type, in: context) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Marca para borrar la empresa de `scope` y todos sus registros, sin guardar.
    @MainActor
    static func delete(_ scope: BackupScope, in context: ModelContext) throws {
        guard let companyID = scope.companyID else { return }
        for type in CompanyOwnership.ownedTypes {
            try Bookkeeper.deleteRecords(type, companyID: companyID, includeOrphans: scope.includeOrphans, in: context)
        }
        for company in try context.fetch(FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyID })) {
            context.delete(company)
        }
    }

    @MainActor
    private static func deleteAll<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws {
        // Uno a uno y no con `delete(model:)`: el borrado por lotes no pasa por la sincronización con iCloud.
        for model in try context.fetch(FetchDescriptor<M>()) { context.delete(model) }
    }
}

/// Qué entra en una copia: la empresa y sus registros (con los huérfanos si es la principal). Sin empresa, todo.
struct BackupScope {
    var companyID: UUID?
    var includeOrphans: Bool

    func companies() -> FetchDescriptor<Company> {
        guard let companyID else { return FetchDescriptor<Company>() }
        return FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyID })
    }

    func descriptor<T: CompanyOwned>(_ type: T.Type) -> FetchDescriptor<T> {
        guard let companyID else { return FetchDescriptor<T>() }
        return FetchDescriptor<T>(predicate: T.ownedBy(companyID, includeOrphans: includeOrphans))
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notABackup
    case damaged
    case newerVersion
    case brokenReference(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "El archivo no es una copia de Chirogra.")
        case .damaged: String(localized: "La copia está dañada y no se puede leer.")
        case .newerVersion: String(localized: "La copia es de una versión más nueva de Chirogra. Actualiza la app para restaurarla.")
        case .brokenReference: String(localized: "La copia está incompleta: le falta un registro relacionado.")
        }
    }
}

extension Decimal {
    /// Sin pasar por `Double`, para no perder decimales.
    var backupString: String { NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "en_US_POSIX")) }

    init?(backupString: String) {
        self.init(string: backupString, locale: Locale(identifier: "en_US_POSIX"))
    }
}
