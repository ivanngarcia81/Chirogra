import ChirograData
import Foundation
import SwiftData
import Testing
@testable import ChirograUI

/// Sales tax por código postal en pantalla: la tabla de muestra (inventada) se lee y lleva al impuesto sugerido.
@MainActor
@Suite("Sales tax por código postal (muestra)", .serialized)
struct PostalTaxSampleTests {
    @Test("La tabla de muestra se lee, dice que es inventada y normaliza el ZIP+4")
    func sampleTable() throws {
        let table = try #require(PostalTaxSample.table)
        #expect(table.count == 8)
        #expect(table.source.contains("inventada"))
        #expect(table.rate(for: "78702-1234")?.combinedRateMillionths == 82_500)
        #expect(table.rate(for: "1234") == nil)
    }

    @Test("Con el ZIP del negocio se sugiere «Austin, TX» 8.25 % y se crea con un toque; la segunda vez ya existe")
    func suggestAndCreate() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let company = try books.setUpCompany(legalName: "Taller Uno LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        company.postalCode = "78702"
        let table = try #require(PostalTaxSample.table)
        let suggestion = try #require(try books.suggestedSalesTax(for: nil, table: table))
        #expect(suggestion.displayName == "Austin, TX")
        #expect(suggestion.basis == .origin)
        #expect(suggestion.breakdown.contains("2"))
        let created = try books.createTaxCode(for: suggestion)
        #expect(created.rateMillionths == 82_500)
        #expect(try books.suggestedSalesTax(for: nil, table: table)?.existingTaxCodeID == created.id)
        // Cliente de otro estado: la del cliente (destino).
        let customer = Customer(name: "Cliente de California")
        customer.postalCode = "94103"
        #expect(try books.suggestedSalesTax(for: customer, table: table)?.displayName == "San Francisco, CA")
    }
}
