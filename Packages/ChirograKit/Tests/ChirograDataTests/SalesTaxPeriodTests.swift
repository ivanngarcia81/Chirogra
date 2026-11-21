import Foundation
import SwiftData
import Testing
@testable import ChirograData

/// Periodos de declaración de sales tax por frecuencia (Impuestos e Inicio; Eric, Beta Family, build 55: la pantalla
/// era siempre trimestral aunque la agencia declarara cada mes).
@MainActor
@Suite("Periodos de declaración del sales tax")
struct SalesTaxPeriodTests {
    let calendar = Calendar(identifier: .gregorian)

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Mes, trimestre y año que contienen el 20 de noviembre, con su fecha límite")
    func periodContaining() {
        let now = day(2026, 11, 20)
        let month = Bookkeeper.salesTaxFilingPeriod(.monthly, containing: now, calendar: calendar)
        #expect(month == SalesTaxFilingPeriod(start: day(2026, 11, 1), end: day(2026, 11, 30), deadline: day(2026, 12, 20)))
        let quarter = Bookkeeper.salesTaxFilingPeriod(.quarterly, containing: now, calendar: calendar)
        #expect(quarter == SalesTaxFilingPeriod(start: day(2026, 10, 1), end: day(2026, 12, 31), deadline: day(2027, 1, 20)))
        let year = Bookkeeper.salesTaxFilingPeriod(.annual, containing: now, calendar: calendar)
        #expect(year == SalesTaxFilingPeriod(start: day(2026, 1, 1), end: day(2026, 12, 31), deadline: day(2027, 1, 20)))
    }

    @Test("El actual y los tres anteriores, del más reciente al más antiguo y cruzando el año")
    func previousPeriods() {
        let months = Bookkeeper.salesTaxFilingPeriods(.monthly, containing: day(2026, 2, 10), count: 4, calendar: calendar)
        #expect(months.map(\.start) == [day(2026, 2, 1), day(2026, 1, 1), day(2025, 12, 1), day(2025, 11, 1)])
        #expect(months[2].end == day(2025, 12, 31) && months[2].deadline == day(2026, 1, 20))
        let quarters = Bookkeeper.salesTaxFilingPeriods(.quarterly, containing: day(2026, 11, 20), count: 4, calendar: calendar)
        #expect(quarters.map(\.start) == [day(2026, 10, 1), day(2026, 7, 1), day(2026, 4, 1), day(2026, 1, 1)])
        let years = Bookkeeper.salesTaxFilingPeriods(.annual, containing: day(2026, 11, 20), count: 4, calendar: calendar)
        #expect(years.map(\.start) == [day(2026, 1, 1), day(2025, 1, 1), day(2024, 1, 1), day(2023, 1, 1)])
        #expect(Bookkeeper.salesTaxFilingPeriods(.monthly, containing: day(2026, 2, 10), count: 0, calendar: calendar).isEmpty)
    }

    @Test("La de la agencia coincide con la de su frecuencia")
    func agencyPeriodMatchesFrequency() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let agency = TaxAgency(name: "Texas Comptroller", filingFrequency: .monthly, liabilityAccountID: nil)
        container.mainContext.insert(agency)
        let now = day(2026, 11, 20)
        #expect(books.salesTaxFilingPeriod(for: agency, containing: now, calendar: calendar)
            == Bookkeeper.salesTaxFilingPeriod(.monthly, containing: now, calendar: calendar))
        agency.filingFrequencyRaw = "desconocida"
        #expect(agency.filingFrequency == .quarterly)
    }

    @Test("Frecuencia de la pantalla: la primera agencia sin archivar; sin ninguna, trimestral")
    func shownFrequency() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let archived = TaxAgency(name: "Antigua", filingFrequency: .annual, liabilityAccountID: nil)
        archived.isArchived = true
        let monthly = TaxAgency(name: "Mensual", filingFrequency: .monthly, liabilityAccountID: nil)
        let quarterly = TaxAgency(name: "Trimestral", filingFrequency: .quarterly, liabilityAccountID: nil)
        [archived, monthly, quarterly].forEach { container.mainContext.insert($0) }
        #expect(FilingFrequency.shownForSalesTax([]) == .quarterly)
        #expect(FilingFrequency.shownForSalesTax([archived]) == .quarterly)
        #expect(FilingFrequency.shownForSalesTax([archived, monthly, quarterly]) == .monthly)
        #expect(FilingFrequency.shownForSalesTax([quarterly, monthly]) == .quarterly)
    }
}
