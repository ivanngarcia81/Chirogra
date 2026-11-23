import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Suma SHA-256 de las copias `.chirogra` (auditoría del 23-nov, `Backup+Integrity.swift`).
@MainActor
@Suite("Copias: suma de comprobación, archivos dañados y compatibilidad")
struct BackupIntegrityTests {
    func sample() throws -> ModelContainer {
        let container = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(container.mainContext, locale: Locale(identifier: "es_US"))
        return container
    }

    func json(of backup: Data) throws -> Data {
        try (backup.dropFirst(BackupArchive.signature.count) as NSData).decompressed(using: .zlib) as Data
    }

    func compressed(_ json: Data) throws -> Data {
        BackupArchive.signature + (try (json as NSData).compressed(using: .zlib) as Data)
    }

    /// Lo que cuenta de los libros para ver que no cambiaron.
    func fingerprint(_ context: ModelContext) throws -> [Int] {
        [try context.fetchCount(FetchDescriptor<Company>()), try context.fetchCount(FetchDescriptor<Invoice>()),
         try context.fetchCount(FetchDescriptor<JournalEntry>()), try context.fetchCount(FetchDescriptor<JournalLine>())]
    }

    @Test("La copia lleva la suma y una versión anterior de Chirogra la sigue leyendo (ignora la clave nueva)")
    func compatibleWithOlderReaders() throws {
        let source = try sample()           // el contenedor tiene que vivir mientras se usa su contexto
        let backup = try BackupArchive.make(from: source.mainContext, appVersion: "1.3.0")
        let json = try json(of: backup)
        #expect(json.starts(with: BackupArchive.integrityPrefix))
        #expect(BackupArchive.hasChecksum(backup))
        // Lo que hacía la versión anterior: decodificar `BackupFile` del JSON y prepararlo con JSONSerialization.
        let file = try JSONDecoder().decode(BackupArchive.BackupFile.self, from: json)
        #expect(file.info.recordCount > 0)
        #expect(try BackupArchive.prepare(json, keepingIDsUnlessIn: []).companyID == file.info.companyID)
    }

    @Test("Una copia de antes de la suma (claves ordenadas, sin `integrity`) se restaura como siempre")
    func legacyCopiesStillRestore() throws {
        let source = try sample()
        var object = try #require(try JSONSerialization.jsonObject(with: try json(of: try BackupArchive.make(from: source.mainContext, appVersion: "1.2.0"))) as? [String: Any])
        object["integrity"] = nil
        let legacy = try compressed(try JSONSerialization.data(withJSONObject: object, options: .sortedKeys))
        #expect(!BackupArchive.hasChecksum(legacy))
        let target = try ChirograStore.makeContainer(inMemory: true)
        try BackupArchive.restore(legacy, into: target.mainContext)
        #expect(try fingerprint(target.mainContext) == fingerprint(source.mainContext))
    }

    @Test("Un importe cambiado dentro de la copia: «dañada», y los libros no se tocan")
    func editedAmountIsRejected() throws {
        let source = try sample()
        let backup = try BackupArchive.make(from: source.mainContext, appVersion: "1.3.0")
        let text = String(decoding: try json(of: backup), as: UTF8.self)
        let range = try #require(text.range(of: #""debit":[1-9][0-9]*"#, options: .regularExpression))
        let edited = text.replacingCharacters(in: range, with: #""debit":1"#)
        let file = try compressed(Data(edited.utf8))
        #expect(throws: BackupError.damaged) { try BackupArchive.info(of: file) }
        let books = try sample()
        let before = try fingerprint(books.mainContext)
        #expect(throws: BackupError.damaged) { try BackupArchive.restore(file, into: books.mainContext) }
        #expect(try fingerprint(books.mainContext) == before)
    }

    @Test("Con un bit cambiado en cualquier sitio del archivo, la copia o se rechaza o sale idéntica: nunca otros datos")
    func bitFlipsNeverRestoreDifferentData() throws {
        let source = try sample()           // el contenedor tiene que vivir mientras se usa su contexto
        let backup = try BackupArchive.make(from: source.mainContext, appVersion: "1.3.0")
        let original = try BackupArchive.decompressed(backup)
        var random = CashBasisCreditTests.SeededGenerator(state: 23)
        var rejected = 0
        for _ in 0..<300 {
            var data = backup
            let index = Int.random(in: BackupArchive.signature.count..<data.count, using: &random)
            data[index] ^= UInt8(1 << Int.random(in: 0..<8, using: &random))
            do {
                let opened = try BackupArchive.decompressed(data)
                #expect(opened == original, "byte \(index)")
            } catch {
                rejected += 1
            }
        }
        #expect(rejected > 250)
    }

    @Test("La copia cifrada lleva la suma por dentro y se restaura entera")
    func encryptedCopyKeepsChecksum() throws {
        let source = try sample()
        let backup = try BackupArchive.make(from: source.mainContext, appVersion: "1.3.0")
        let locked = try BackupArchive.encrypt(backup, password: "contraseña larga", iterations: 1_000)
        let opened = try BackupArchive.decrypt(locked, password: "contraseña larga")
        #expect(BackupArchive.hasChecksum(opened))
        let target = try ChirograStore.makeContainer(inMemory: true)
        try BackupArchive.restore(opened, into: target.mainContext)
        #expect(try fingerprint(target.mainContext) == fingerprint(source.mainContext))
    }
}
