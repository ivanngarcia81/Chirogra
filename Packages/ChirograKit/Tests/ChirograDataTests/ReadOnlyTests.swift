import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Libros en solo lectura")
struct ReadOnlyTests {
    /// Síncrona a propósito: en el actor principal corre entera, así que `isReadOnly` no se cruza con otras pruebas.
    @Test("Con la suscripción vencida no se registra nada y los libros quedan como estaban")
    func blocksWrites() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try SampleData.populate(context)
        let books = Bookkeeper(context: context)
        let entries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first { $0.isOpen && $0.balanceDue > 0 })
        let balance = invoice.balanceDue
        let checking = try #require(try books.accounts().first { $0.code == "1010" })
        let capital = try #require(try books.accounts().first { $0.code == "3000" })

        Bookkeeper.isReadOnly = true
        defer { Bookkeeper.isReadOnly = false }
        #expect(throws: BookkeepingError.readOnly) {
            try books.post(JournalEntryDraft(date: .now, memo: "Aporte", lines: [.debit(checking.id, 100), .credit(capital.id, 100)]))
        }
        #expect(throws: BookkeepingError.readOnly) {
            try books.recordPayment(for: invoice, amount: balance, date: .now, depositAccount: checking)
        }
        #expect(throws: BookkeepingError.readOnly) {
            try books.attachReceipt(Data("%PDF".utf8), filename: "r.pdf", contentType: .pdf,
                                    to: try #require(try context.fetch(FetchDescriptor<Expense>()).first))
        }
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == entries)
        #expect(invoice.balanceDue == balance)

        // La copia de seguridad se puede sacar igual.
        #expect(!(try BackupArchive.make(from: context, appVersion: "1.0")).isEmpty)
    }
}
