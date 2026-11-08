import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Copia de seguridad")
struct BackupTests {
    let now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    /// Libros de ejemplo con un recibo, un W-9 y un estimado convertido, para cubrir adjuntos y relaciones.
    func sampleContainer() throws -> ModelContainer {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try SampleData.populate(context)
        let books = Bookkeeper(context: context)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        try books.attachReceipt(Data("%PDF-1.7 recibo".utf8), filename: "recibo.pdf", contentType: .pdf, to: expense)
        let vendor = try #require(try context.fetch(FetchDescriptor<Vendor>()).first)
        try books.attachW9(Data("%PDF-1.7 w9".utf8), filename: "w9.pdf", contentType: .pdf, to: vendor)
        return container
    }

    func payloadJSON(_ data: Data) throws -> Data {
        let file = try BackupArchive.decode(data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file.payload)
    }

    @Test("La copia cubre todas las entidades y propiedades del esquema (si falla: scripts/gen-backup.py)")
    func coversSchema() {
        let entities = ChirograStore.schema.entities
        #expect(entities.count == BackupArchive.modelCount)
        for entity in entities {
            let names = Set(entity.attributes.map(\.name) + entity.relationships.map(\.name))
            #expect(BackupArchive.coveredProperties[entity.name] == names, "\(entity.name)")
        }
    }

    @Test("Restaurar en otros libros deja exactamente lo mismo: registros, relaciones, adjuntos y saldos")
    func roundTrip() throws {
        let original = try sampleContainer()
        let backup = try BackupArchive.make(from: original.mainContext, appVersion: "1.0", now: now)

        // El destino ya tiene otros libros: se reemplazan.
        let target = try ChirograStore.makeContainer(inMemory: true)
        try Bookkeeper(context: target.mainContext).setUpCompany(legalName: "Otra LLC", displayName: "Otra", entityType: .llc,
                                                                 state: "CA", sector: .retail)
        let info = try BackupArchive.restore(backup, into: target.mainContext, actor: "Prueba")
        #expect(info.companyName == "Ríos Diseño & Obra")
        #expect(info.createdAt == now)

        let again = try BackupArchive.make(from: target.mainContext, appVersion: "1.0", now: now)
        let before = try BackupArchive.decode(backup).payload.counts
        var after = try BackupArchive.decode(again).payload.counts
        after["AuditEvent", default: 0] -= 1   // el aviso de «copia restaurada»
        #expect(before == after)

        // Todo igual salvo el registro de auditoría de la restauración.
        let restoredContext = target.mainContext
        let audit = try #require(try restoredContext.fetch(FetchDescriptor<AuditEvent>()).first { $0.action == "restore" })
        restoredContext.delete(audit)
        try restoredContext.save()
        let third = try BackupArchive.make(from: restoredContext, appVersion: "1.0", now: now)
        #expect(try payloadJSON(third) == payloadJSON(backup))

        // Los libros restaurados cuadran y conservan relaciones y adjuntos.
        let books = Bookkeeper(context: restoredContext)
        let balance = ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: try books.ledgerLines(), asOf: .distantFuture)
        #expect(balance.isBalanced)
        #expect(try restoredContext.fetch(FetchDescriptor<Company>()).count == 1)
        let expense = try #require(try restoredContext.fetch(FetchDescriptor<Expense>()).first { !($0.attachments ?? []).isEmpty })
        #expect(expense.attachments?.first?.data == Data("%PDF-1.7 recibo".utf8))
        let group = try #require(try restoredContext.fetch(FetchDescriptor<TaxGroup>()).first { ($0.rates ?? []).count > 1 })
        #expect(group.rates?.allSatisfy { ($0.groups ?? []).contains { $0.id == group.id } } == true)
        let invoice = try #require(try restoredContext.fetch(FetchDescriptor<Invoice>()).first { !($0.paymentApplications ?? []).isEmpty })
        #expect(invoice.customer != nil && !(invoice.lines ?? []).isEmpty)
    }

    @Test("Una copia de un esquema anterior sin una propiedad la restaura con su valor por defecto")
    func missingPropertyGetsDefault() throws {
        let original = try sampleContainer()
        let backup = try BackupArchive.make(from: original.mainContext, appVersion: "1.0", now: now)
        let json = try (backup.dropFirst(BackupArchive.signature.count) as NSData).decompressed(using: .zlib) as Data
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var payload = try #require(object["payload"] as? [String: Any])
        var customers = try #require(payload["customer"] as? [[String: Any]])
        for index in customers.indices { customers[index]["notes"] = nil; customers[index]["paymentTermsDays"] = nil }
        payload["customer"] = customers
        object["payload"] = payload
        let edited = try JSONSerialization.data(withJSONObject: object)
        let file = BackupArchive.signature + (try (edited as NSData).compressed(using: .zlib) as Data)

        let target = try ChirograStore.makeContainer(inMemory: true)
        try BackupArchive.restore(file, into: target.mainContext)
        let restored = try target.mainContext.fetch(FetchDescriptor<Customer>())
        #expect(!restored.isEmpty && restored.allSatisfy { $0.notes.isEmpty && $0.paymentTermsDays == 30 })
    }

    @Test("Un archivo que no es una copia, una copia dañada o de una versión más nueva no tocan los libros")
    func rejectsBadFiles() throws {
        let container = try sampleContainer()
        let context = container.mainContext
        let invoices = try context.fetchCount(FetchDescriptor<Invoice>())
        let backup = try BackupArchive.make(from: context, appVersion: "1.0", now: now)

        #expect(throws: BackupError.notABackup) { try BackupArchive.restore(Data("hola".utf8), into: context) }
        #expect(throws: BackupError.damaged) { try BackupArchive.restore(BackupArchive.signature + Data([1, 2, 3]), into: context) }

        let json = try (backup.dropFirst(BackupArchive.signature.count) as NSData).decompressed(using: .zlib) as Data
        let newer = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":\"\(BackupArchive.schemaVersion)\"", with: "\"schemaVersion\":\"9.0.0\"")
        let newerFile = BackupArchive.signature + (try (Data(newer.utf8) as NSData).compressed(using: .zlib) as Data)
        #expect(throws: BackupError.newerVersion) { try BackupArchive.restore(newerFile, into: context) }

        // Una referencia rota (la cuenta de unas líneas de diario no está en la copia): deshace todo.
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first { !($0.lines ?? []).isEmpty })
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var payload = try #require(object["payload"] as? [String: Any])
        var accounts = try #require(payload["account"] as? [[String: Any]])
        let index = try #require(accounts.firstIndex { $0["id"] as? String == account.id.uuidString })
        accounts[index]["id"] = UUID().uuidString
        payload["account"] = accounts
        object["payload"] = payload
        let brokenJSON = try JSONSerialization.data(withJSONObject: object)
        let brokenFile = BackupArchive.signature + (try (brokenJSON as NSData).compressed(using: .zlib) as Data)
        #expect(throws: BackupError.brokenReference("JournalLine.account")) { try BackupArchive.restore(brokenFile, into: context) }
        #expect(try context.fetchCount(FetchDescriptor<Invoice>()) == invoices)
        #expect(try context.fetchCount(FetchDescriptor<Company>()) == 1)
    }

    @Test("Nombre de archivo sugerido")
    func filename() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        #expect(BackupArchive.suggestedFilename(companyName: "Ríos Diseño & Obra", date: date) == "Chirogra · Ríos Diseño & Obra · 2026-11-03.chirogra")
        #expect(BackupArchive.suggestedFilename(companyName: "A/B", date: date) == "Chirogra · A-B · 2026-11-03.chirogra")
    }
}
