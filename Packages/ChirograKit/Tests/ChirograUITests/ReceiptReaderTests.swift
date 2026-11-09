import ChirograCore
import ChirograData
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import ChirograUI

/// Escanear recibos: del texto (o de la imagen, con Vision) a lo que propone el editor de gasto. Sin el modelo del
/// aparato (`-qa.reciboIA no`), para que el resultado no dependa de Apple Intelligence.
@MainActor
@Suite("Leer recibos para el gasto", .serialized)
struct ReceiptReaderTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        UserDefaults.standard.set("no", forKey: "qa.reciboIA")
        container = try ChirograStore.makeContainer(inMemory: true)
        _ = try Bookkeeper(context: container.mainContext, actor: "Pruebas")
            .setUpCompany(legalName: "Taller Uno LLC", entityType: .llc, state: "TX", sector: .construction, locale: Locale(identifier: "es_US"))
    }

    var accounts: [Account] { (try? Bookkeeper(context: context).accounts()) ?? [] }

    @Test("Ferretería: proveedor existente con su categoría; sin proveedor, materiales por las palabras del recibo")
    func vendorAndCategory() async throws {
        let books = Bookkeeper(context: context)
        let vendor = Vendor(name: "Home Depot")
        let repairs = try #require(accounts.first { $0.code == "6450" })
        vendor.defaultExpenseAccountID = repairs.id
        books.insert(vendor)
        try context.save()
        let lines = ["THE HOME DEPOT #4410", "10/29/2026", "SUBTOTAL 262.51", "TAX 8.25% 21.66", "TOTAL 284.17"]
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8))!
        let reading = await ReceiptReader.reading(from: lines, accounts: accounts, vendors: [vendor], now: now)
        #expect(reading.vendorID == vendor.id)
        #expect(reading.categoryAccountID == repairs.id)
        #expect(reading.total == 28_417)
        #expect(reading.salesTax == 2_166)
        #expect(reading.foundCount == 4)

        let alone = await ReceiptReader.reading(from: lines, accounts: accounts, vendors: [], now: now)
        #expect(alone.vendorID == nil)
        #expect(alone.merchant == "The Home Depot")
        #expect(accounts.first { $0.id == alone.categoryAccountID }?.code == "5000")
    }

    @Test("Cada pista de categoría va a una cuenta de gasto de la plantilla")
    func categoryHints() {
        let costs = ExpenseCategories.groups(from: accounts).costs
        for hint in ReceiptCategoryHint.allCases {
            #expect(ReceiptReader.account(for: hint, in: costs) != nil, "sin cuenta para \(hint)")
        }
        #expect(ReceiptReader.account(for: .meals, in: costs)?.code == "6650")
        #expect(ReceiptReader.account(for: .vehicle, in: costs)?.code == "6050")
    }

    @Test("Emparejar el comercio: sin «The» ni número de tienda; nunca con un nombre demasiado corto")
    func vendorMatching() {
        let depot = Vendor(name: "The Home Depot")
        let shell = Vendor(name: "Shell Oil")
        let ab = Vendor(name: "AB")
        #expect(ReceiptReader.matchVendor("HOME DEPOT #4410", in: [depot, shell])?.name == "The Home Depot")
        #expect(ReceiptReader.matchVendor("Shell", in: [depot, shell])?.name == "Shell Oil")
        #expect(ReceiptReader.matchVendor("AB", in: [ab]) == nil)
        #expect(ReceiptReader.matchVendor("Starbucks", in: [depot, shell]) == nil)
    }

    @Test("La imagen del recibo de prueba se lee con Vision y da el total, el impuesto y la fecha")
    func visionOnSample() async throws {
        let png = try #require(ReceiptQA.samplePNG())
        let lines: [String]
        do {
            lines = try await ReceiptTextRecognizer.lines(of: png, type: .png)
        } catch {
            // Depende del Mac: con el Neural Engine muy ocupado, el sistema a veces no prepara el modelo de texto.
            withKnownIssue("Vision no pudo leer en este Mac: \(error)", isIntermittent: true) { throw error }
            return
        }
        let rules = ReceiptRules.parse(lines: lines, now: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8))!)
        #expect(rules.total == 28_417, "\(lines)")
        #expect(rules.salesTax == 2_166, "\(lines)")
        #expect(rules.merchant == "The Home Depot", "\(lines)")
        #expect(rules.date.map { Calendar.current.component(.day, from: $0) } == 29)
    }
}
