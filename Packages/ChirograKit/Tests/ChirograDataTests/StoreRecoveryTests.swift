import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Base que no abre (auditoría del 23-nov): la app no se cierra (`BooksStore` en `ChirograApp.swift` enseña
/// `StoreRecoveryView`), «Apartar la base» la mueve sin borrar nada y abre una nueva, y lo apartado conserva los libros.
@MainActor
@Suite("Recuperación de una base que no abre")
struct StoreRecoveryTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "chirogra-recuperacion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Una base dañada da un error (no un cierre) y se aparta entera; la nueva abre vacía")
    func damagedStoreIsSetAside() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Chirogra.store")
        try Data(repeating: 0x5A, count: 64 * 1024).write(to: url)          // no es SQLite
        #expect(throws: (any Error).self) { _ = try ChirograStore.makeContainer(url: url) }

        let aside = try ChirograStore.setAsideStore(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let moved = try Data(contentsOf: aside.appending(path: "Chirogra.store"))
        #expect(moved == Data(repeating: 0x5A, count: 64 * 1024))           // movida tal cual, no borrada

        let fresh = try ChirograStore.makeContainer(url: url)
        #expect(try fresh.mainContext.fetchCount(FetchDescriptor<Company>()) == 0)
    }

    @Test("Apartar una base con libros: la carpeta apartada se abre y tiene los mismos libros")
    func setAsideKeepsBooks() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Chirogra.store")
        // Cerrada antes de apartarla, como en la app (la pantalla de recuperación sale cuando no se pudo abrir).
        let (invoices, lines): (Int, Int) = try {
            let container = try ChirograStore.makeContainer(url: url)
            try SampleData.populate(container.mainContext)
            return (try container.mainContext.fetchCount(FetchDescriptor<Invoice>()),
                    try container.mainContext.fetchCount(FetchDescriptor<JournalLine>()))
        }()
        #expect(invoices > 0)

        let aside = try ChirograStore.setAsideStore(at: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: aside.path(percentEncoded: false))
        #expect(names.contains("Chirogra.store"))
        let reopened = try ChirograStore.makeContainer(url: aside.appending(path: "Chirogra.store"))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Invoice>()) == invoices)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<JournalLine>()) == lines)
        #expect(try Bookkeeper(context: reopened.mainContext).trialBalance(asOf: .distantFuture).isBalanced)
    }
}
