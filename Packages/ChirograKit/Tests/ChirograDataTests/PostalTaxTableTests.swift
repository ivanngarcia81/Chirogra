import Foundation
import Testing
@testable import ChirograData

/// La tabla de sales tax por ZIP que trae la app (`scripts/tasas/generar.py`, docs/DATOS-V5.md).
@Suite("Tabla de sales tax por ZIP de la app")
struct PostalTaxTableTests {
    @Test("Se lee y trae los estados de la 1.2")
    func bundled() throws {
        let table = try #require(PostalTaxTable.bundled())
        #expect(table.count > 20_000)
        #expect(!table.effectiveDate.isEmpty)
        let data = try Data(contentsOf: try #require(Bundle.module.url(forResource: "sales-tax-zip", withExtension: "json")))
        struct File: Decodable { var rates: [PostalTaxRate] }
        let present = Set(try JSONDecoder().decode(File.self, from: data).rates.map(\.state))
        for state in ["TX", "CA", "FL", "NY", "IL", "NJ", "GA", "OH", "WA", "NC", "MD", "MA"] {
            #expect(present.contains(state), "\(state)")
        }
    }

    @Test("Ciudades conocidas: total, nombre y la tasa estatal igual a la de la app")
    func knownCities() throws {
        let table = try #require(PostalTaxTable.bundled())
        // (ZIP, estado, nombre, total en millonésimas)
        let cases: [(String, String, String, Int64)] = [
            ("78702", "TX", "Austin", 82_500),
            ("90012", "CA", "Los Angeles", 102_500),
            ("33130", "FL", "Miami-Dade County", 70_000),
            ("10001", "NY", "New York City", 88_750),
            ("60601", "IL", "Chicago", 105_000),
            ("07644", "NJ", "Bergen County", 66_250),
        ]
        for (zip, state, region, total) in cases {
            let rate = try #require(table.rate(for: zip), "\(zip)")
            #expect(rate.state == state)
            #expect(rate.region == region)
            #expect(rate.combinedRateMillionths == total, "\(zip): \(rate.combinedRateMillionths)")
            #expect(rate.stateRateMillionths == StateSalesTax.forState(state)?.rateMillionths)
        }
    }

    @Test("Ningún ZIP con tasa local se queda sin nombre ni pasa del tope razonable")
    func sane() throws {
        let data = try Data(contentsOf: try #require(Bundle.module.url(forResource: "sales-tax-zip", withExtension: "json")))
        struct File: Decodable { var rates: [PostalTaxRate] }
        let rates = try JSONDecoder().decode(File.self, from: data).rates
        #expect(Set(rates.map(\.postalCode)).count == rates.count)
        #expect(!rates.contains { $0.localRateMillionths > 0 && $0.region.isEmpty })
        #expect(!rates.contains { $0.combinedRateMillionths > 200_000 || $0.localRateMillionths < 0 })
    }
}
