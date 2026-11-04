import Foundation
import SwiftData

/// Copia de seguridad exportable (DISEÑO §6.5): un archivo `.chirogra` con los libros completos —todos los modelos y
/// los recibos, logos y W-9 adjuntos— independiente de iCloud.
///
/// Formato 1: la firma `CHIROGRA-COPIA-1\n` seguida de JSON comprimido con zlib (`BackupFile`: `info` y `payload`).
/// Cada modelo es un registro con sus propiedades guardadas y sus relaciones a uno por `id`
/// (`Backup+Generated.swift`, que escribe `scripts/gen-backup.py`). Las propiedades que falten en una copia de un
/// esquema anterior toman su valor por defecto; una copia de un esquema más nuevo no se abre.
///
/// Restaurar **reemplaza** los libros: primero se prueba en un almacén en memoria y después se borran todos los
/// modelos y se crean los de la copia en un solo guardado; si algo falla no cambia nada. Con iCloud, el cambio llega
/// también a los otros aparatos.
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

        public var recordCount: Int { counts.values.reduce(0, +) }
        public func count(of entity: String) -> Int { counts[entity] ?? 0 }
    }

    struct BackupFile: Codable {
        var info: Info
        var payload: BackupPayload
    }

    static var schemaVersion: String {
        let version = SchemaV2.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// Copia de todo lo que hay en `context`.
    @MainActor
    public static func make(from context: ModelContext, appVersion: String, now: Date = Date()) throws -> Data {
        let payload = try BackupPayload(context: context)
        let company = try context.fetch(FetchDescriptor<Company>()).first
        let info = Info(formatVersion: formatVersion, schemaVersion: schemaVersion, createdAt: now, appVersion: appVersion,
                        companyName: company.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? "",
                        counts: payload.counts)
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

    /// Reemplaza los libros de `context` por los de la copia, en un solo guardado.
    @MainActor
    @discardableResult
    public static func restore(_ data: Data, into context: ModelContext, actor: String = "") throws -> Info {
        let file = try decode(data)
        // Primero, de prueba en un almacén en memoria: si la copia tiene una referencia rota, falla ahí sin tocar los
        // libros (deshacer a medias un borrado con cascadas no es fiable en SwiftData).
        let trial = try ChirograStore.makeContainer(inMemory: true)
        try file.payload.insert(into: trial.mainContext)
        try trial.mainContext.save()
        do {
            try deleteEverything(in: context)
            try file.payload.insert(into: context)
            let summary = String(localized: "Copia restaurada del \(file.info.createdAt.formatted(date: .abbreviated, time: .shortened))")
            context.insert(AuditEvent(actor: actor, entityName: "Backup", entityID: nil, action: "restore", summary: summary))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return file.info
    }

    /// Nombre de archivo sugerido: «Chirogra · Ríos Diseño & Obra · 2026-11-03.chirogra».
    public static func suggestedFilename(companyName: String, date: Date = Date()) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let company = companyName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return (company.isEmpty ? "Chirogra · \(day)" : "Chirogra · \(company) · \(day)") + ".\(fileExtension)"
    }

    static func decode(_ data: Data) throws -> BackupFile {
        guard data.starts(with: signature) else { throw BackupError.notABackup }
        let json: Data
        do {
            json = try (data.dropFirst(signature.count) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw BackupError.damaged
        }
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

    /// Borra todos los registros de los libros (todos los modelos del esquema) en un solo guardado; si algo falla no
    /// cambia nada. Lo usa «Empezar con mi empresa» para quitar los datos de ejemplo (`SampleData.discard`).
    @MainActor
    public static func eraseAll(in context: ModelContext) throws {
        do {
            try deleteEverything(in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Marca para borrar todos los registros, sin guardar.
    @MainActor
    private static func deleteEverything(in context: ModelContext) throws {
        for type in BackupPayload.modelTypes {
            try deleteAll(type, in: context)
        }
    }

    @MainActor
    private static func deleteAll<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws {
        // Uno a uno y no con `delete(model:)`: el borrado por lotes no pasa por la sincronización con iCloud.
        for model in try context.fetch(FetchDescriptor<M>()) { context.delete(model) }
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
