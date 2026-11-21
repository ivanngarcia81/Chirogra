import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Copia con contraseña (revisión externa del 21-nov): el archivo entero va cifrado con AES-GCM y una clave de PBKDF2.
@MainActor
@Suite("Copia con contraseña")
struct BackupEncryptionTests {
    /// Pocas iteraciones: las pruebas no miden la fuerza, solo el formato.
    let iterations: UInt32 = 1_000

    func backup() throws -> (data: Data, container: ModelContainer) {
        let container = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(container.mainContext, locale: Locale(identifier: "es_US"))
        let vendor = try #require(try container.mainContext.fetch(FetchDescriptor<Vendor>()).first)
        try Bookkeeper(context: container.mainContext).attachW9(Data("%PDF-1.7 W-9 TIN 123-45-6789".utf8), filename: "w9.pdf",
                                                                 contentType: .pdf, to: vendor)
        return (try BackupArchive.make(from: container.mainContext, appVersion: "1.3.0"), container)
    }

    @Test("Con la contraseña sale la copia de siempre; sin ella no se lee nada")
    func roundTrip() throws {
        let plain = try backup().data
        let locked = try BackupArchive.encrypt(plain, password: "Río seguro 2026", iterations: iterations)
        #expect(BackupArchive.isEncrypted(locked) && !BackupArchive.isEncrypted(plain))
        #expect(throws: BackupError.needsPassword) { try BackupArchive.info(of: locked) }
        // Ni el JSON comprimido ni el W-9 aparecen en claro.
        #expect(locked.range(of: Data("123-45-6789".utf8)) == nil)
        #expect(locked.range(of: plain.dropFirst(BackupArchive.signature.count).prefix(64)) == nil)

        let opened = try BackupArchive.decrypt(locked, password: "Río seguro 2026")
        #expect(opened == plain)
        #expect(try BackupArchive.info(of: opened).companyName == BackupArchive.info(of: plain).companyName)
        // La misma contraseña escrita con otra forma Unicode («í» compuesta o con tilde aparte) también abre.
        #expect(try BackupArchive.decrypt(locked, password: "Ri\u{301}o seguro 2026") == plain)
        // Dos copias con la misma contraseña no se parecen (sal y nonce nuevos).
        #expect(try BackupArchive.encrypt(plain, password: "Río seguro 2026", iterations: iterations) != locked)
    }

    @Test("Contraseña equivocada o archivo tocado: «La contraseña no es correcta»")
    func wrongPasswordOrTampered() throws {
        let locked = try BackupArchive.encrypt(try backup().data, password: "correcta", iterations: iterations)
        #expect(throws: BackupError.wrongPassword) { try BackupArchive.decrypt(locked, password: "otra") }
        var tampered = locked
        tampered[tampered.count - 40] ^= 0x01
        #expect(throws: BackupError.wrongPassword) { try BackupArchive.decrypt(tampered, password: "correcta") }
        // Cambiar las iteraciones de la cabecera (dato asociado) tampoco abre.
        var header = locked
        header[BackupArchive.encryptedSignature.count + BackupArchive.saltLength + 3] ^= 0x01
        #expect(throws: BackupError.wrongPassword) { try BackupArchive.decrypt(header, password: "correcta") }
        #expect(throws: BackupError.damaged) { try BackupArchive.decrypt(locked.prefix(30), password: "correcta") }
    }

    @Test("Una copia sin contraseña se abre igual que antes y se restaura tras descifrar")
    func restoresAfterDecrypting() throws {
        let (plain, _) = try backup()
        #expect(try BackupArchive.decrypt(plain, password: "") == plain)
        let locked = try BackupArchive.encrypt(plain, password: "clave", iterations: iterations)
        let target = try ChirograStore.makeContainer(inMemory: true)
        let result = try BackupArchive.restoreCompany(try BackupArchive.decrypt(locked, password: "clave"),
                                                      into: target.mainContext, mode: .newCompany)
        #expect(result.info.recordCount > 0)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<ChirograData.Attachment>()) == 1)
    }
}
