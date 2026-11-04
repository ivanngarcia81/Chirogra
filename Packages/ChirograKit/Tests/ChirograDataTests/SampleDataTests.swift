import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// «Empezar con mi empresa»: reconocer los libros de ejemplo y borrarlos sin dejar nada.
@MainActor
@Suite("Datos de ejemplo")
struct SampleDataTests {
    func sampleContainer() throws -> ModelContainer {
        let container = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(container.mainContext)
        return container
    }

    func count<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<M>())
    }

    /// Registros que quedan, por entidad (solo las que tienen alguno).
    func leftovers(in context: ModelContext) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for type in BackupPayload.modelTypes {
            let found = try count(type, in: context)
            if found > 0 { result[String(describing: type)] = found }
        }
        return result
    }

    @Test("Los libros de ejemplo se reconocen como de ejemplo")
    func recognizesSample() throws {
        let container = try sampleContainer()
        #expect(try SampleData.isSample(container.mainContext))
    }

    @Test("Una empresa real no es de ejemplo, aunque se llame igual que la de ejemplo")
    func realCompanyIsNotSample() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(try !SampleData.isSample(context))   // sin empresa
        // Como en el alta (`OnboardingView`): `Bookkeeper` sin actor.
        try Bookkeeper(context: context).setUpCompany(legalName: "Ríos Diseño & Obra LLC", displayName: "Ríos Diseño & Obra",
                                                      entityType: .llc, state: "TX", sector: .construction)
        #expect(try !SampleData.isSample(context))
    }

    @Test("Si llega una empresa real junto a la de ejemplo (iCloud), los libros ya no son de ejemplo")
    func mixedBooksAreNotSample() throws {
        let container = try sampleContainer()
        let context = container.mainContext
        let real = Company(legalName: "Taller Mora LLC", displayName: "Taller Mora", entityType: .llc, state: "TX")
        context.insert(real)
        // Un registro de «Ejemplo» de otra entidad o de otra empresa no la convierte en ejemplo.
        context.insert(AuditEvent(actor: SampleData.actor, entityName: "Invoice", entityID: real.id, action: "create", summary: ""))
        try context.save()
        #expect(try !SampleData.isSample(context))
        #expect(throws: SampleDataError.notSample) { try SampleData.discard(from: context) }
        #expect(try count(Company.self, in: context) == 2)
    }

    @Test("Dos copias de la empresa de ejemplo (una por aparato) siguen siendo de ejemplo")
    func duplicatedSampleIsSample() throws {
        let container = try sampleContainer()
        let context = container.mainContext
        let copy = Company(legalName: "Ríos Diseño & Obra LLC", displayName: "Ríos Diseño & Obra", entityType: .llc, state: "TX")
        context.insert(copy)
        context.insert(AuditEvent(actor: SampleData.actor, entityName: "Company", entityID: copy.id, action: "create", summary: ""))
        try context.save()
        #expect(try SampleData.isSample(context))
    }

    @Test("La marca viaja con los libros: restaurar una copia de los de ejemplo sigue siendo de ejemplo")
    func markSurvivesBackup() throws {
        let original = try sampleContainer()
        let backup = try BackupArchive.make(from: original.mainContext, appVersion: "1.0")
        let target = try ChirograStore.makeContainer(inMemory: true)
        try BackupArchive.restore(backup, into: target.mainContext)
        #expect(try SampleData.isSample(target.mainContext))
    }

    @Test("Empezar con mi empresa borra todos los registros de todos los modelos")
    func discardErasesEverything() throws {
        let container = try sampleContainer()
        let context = container.mainContext
        // Con adjuntos también (recibo y W-9), que cuelgan de otros modelos.
        let books = Bookkeeper(context: context)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        try books.attachReceipt(Data("%PDF-1.7 recibo".utf8), filename: "recibo.pdf", contentType: .pdf, to: expense)
        let vendor = try #require(try context.fetch(FetchDescriptor<Vendor>()).first)
        try books.attachW9(Data("%PDF-1.7 w9".utf8), filename: "w9.pdf", contentType: .pdf, to: vendor)
        #expect(try leftovers(in: context).count > 15)

        try SampleData.discard(from: context)
        #expect(try leftovers(in: context).isEmpty)
        #expect(!context.hasChanges)

        // Y lo que se lee desde otro contexto (lo guardado de verdad) también está vacío.
        #expect(try leftovers(in: ModelContext(container)).isEmpty)

        // Después se puede dar de alta la empresa propia, y ya no es de ejemplo.
        try Bookkeeper(context: context).setUpCompany(legalName: "Taller Mora LLC", displayName: "Taller Mora", entityType: .llc,
                                                      state: "TX", sector: .construction)
        #expect(try !SampleData.isSample(context))
        #expect(try count(Company.self, in: context) == 1)
        #expect(try count(Invoice.self, in: context) == 0)
    }

    @Test("Con libros reales no se borra nada")
    func discardRefusesRealBooks() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try Bookkeeper(context: context).setUpCompany(legalName: "Taller Mora LLC", entityType: .llc, state: "TX")
        let before = try leftovers(in: context)
        #expect(throws: SampleDataError.notSample) { try SampleData.discard(from: context) }
        #expect(try leftovers(in: context) == before)
    }

    @Test("Se puede empezar aunque los libros estén en solo lectura (son de ejemplo, no del usuario)")
    func discardWorksWhileReadOnly() throws {
        let container = try sampleContainer()
        Bookkeeper.isReadOnly = true
        defer { Bookkeeper.isReadOnly = false }
        try SampleData.discard(from: container.mainContext)
        #expect(try leftovers(in: container.mainContext).isEmpty)
    }

    @Test("En un almacén en disco, lo borrado no vuelve al abrirlo otra vez")
    func discardPersists() throws {
        let folder = URL.temporaryDirectory.appending(path: "SampleDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Libros.store")
        do {
            let container = try ChirograStore.makeContainer(url: url)
            try SampleData.populate(container.mainContext)
            try SampleData.discard(from: container.mainContext)
        }
        let reopened = try ChirograStore.makeContainer(url: url)
        #expect(try leftovers(in: reopened.mainContext).isEmpty)
    }
}
