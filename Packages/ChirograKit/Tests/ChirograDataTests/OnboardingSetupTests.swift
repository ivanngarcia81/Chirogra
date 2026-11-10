import ChirograCore
import Foundation
import SwiftData
import Testing
@testable import ChirograData

@MainActor
@Suite("Alta: tabla de tasas estatales")
struct StateSalesTaxTableTests {
    @Test("Están los 50 estados, DC y Puerto Rico, sin repetir y en mayúsculas")
    func coversEveryState() {
        let codes = StateSalesTax.all.map(\.code)
        #expect(codes.count == 52)
        #expect(Set(codes).count == codes.count)
        #expect(codes.contains("DC") && codes.contains("PR"))
        #expect(codes.allSatisfy { $0.count == 2 && $0 == $0.uppercased() })
        #expect(StateSalesTax.all.map(\.name) == StateSalesTax.all.map(\.name).sorted())
    }

    @Test("Sin sales tax estatal: Delaware, Montana, New Hampshire, Oregon y Alaska (solo local)")
    func statesWithoutStateTax() {
        let none = StateSalesTax.all.filter { $0.rateMillionths == nil }.map(\.code)
        #expect(Set(none) == ["AK", "DE", "MT", "NH", "OR"])
        #expect(StateSalesTax.forState("AK")?.hasLocalTaxOnly == true)
        #expect(StateSalesTax.forState("OR")?.hasLocalTaxOnly == false)
    }

    @Test("Cifras conocidas (Tax Foundation, midyear 2026) y todas entre 2.9 % y 10.5 %, con agencia")
    func knownRates() {
        let expected: [String: Int64] = [
            "TX": 62_500, "CA": 72_500, "CO": 29_000, "NY": 40_000, "FL": 60_000, "LA": 50_000, "MN": 68_750,
            "NJ": 66_250, "MO": 42_250, "NM": 48_750, "SD": 42_000, "UT": 61_000, "VA": 53_000, "DC": 60_000,
            "TN": 70_000, "WA": 65_000, "PR": 105_000,
        ]
        for (code, rate) in expected { #expect(StateSalesTax.forState(code)?.rateMillionths == rate, "\(code)") }
        for state in StateSalesTax.all {
            guard let rate = state.rateMillionths else { continue }
            #expect((29_000...105_000).contains(rate), "\(state.code)")
            #expect(!state.agency.isEmpty, "\(state.code)")
        }
        #expect(StateSalesTax.forState("TX")?.agency == "Texas Comptroller")
        #expect(StateSalesTax.forState(" tx ")?.code == "TX")
        #expect(StateSalesTax.forState("ZZ") == nil)
    }
}

@MainActor
@Suite("Alta: sales tax y saldos de apertura")
struct OnboardingSetupTests {
    private func newBooks(state: String) throws -> (ModelContext, Bookkeeper) {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        // El contenedor tiene que vivir mientras se usa el contexto.
        Self.containers.append(container)
        let books = Bookkeeper(context: context)
        try books.setUpCompany(legalName: "Taller Uno LLC", displayName: "Taller Uno", entityType: .llc, state: state,
                               sector: .construction, locale: Locale(identifier: "es"))
        return (context, books)
    }

    private static var containers: [ModelContainer] = []

    @Test("Texas: crea «Texas Comptroller» y la tasa «Texas» 6.25 % como impuesto predeterminado")
    func texasDefaultRate() throws {
        let (context, books) = try newBooks(state: "TX")
        let rate = try #require(try books.setUpStateSalesTax())
        #expect(rate.name == "Texas")
        #expect(rate.rateMillionths == 62_500)
        #expect(rate.agency?.name == "Texas Comptroller")
        #expect(rate.agency?.liabilityAccountID == (try books.systemAccount(.salesTaxPayable)).id)
        #expect(try books.company()?.defaultTaxGroupID == rate.id)

        // Una factura nueva toma ese impuesto y lo cobra.
        let defaults = try books.newInvoiceDefaults(for: nil)
        #expect(defaults.taxGroupID == rate.id)
        let components = try books.taxComponents(groupID: defaults.taxGroupID, on: .now)
        #expect(components.map(\.rateMillionths) == [62_500])

        // Repetirlo no duplica la agencia ni la tasa.
        let again = try #require(try books.setUpStateSalesTax())
        #expect(again.id == rate.id)
        #expect(try context.fetchCount(FetchDescriptor<TaxAgency>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaxRate>()) == 1)
    }

    @Test("Oregon y Alaska: no se crea ninguna tasa ni predeterminado")
    func noStateTax() throws {
        for state in ["OR", "AK"] {
            let (context, books) = try newBooks(state: state)
            #expect(try books.setUpStateSalesTax() == nil)
            #expect(try context.fetchCount(FetchDescriptor<TaxRate>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<TaxAgency>()) == 0)
            #expect(try books.company()?.defaultTaxGroupID == nil)
        }
    }

    @Test("No cambia un impuesto predeterminado que ya existe")
    func keepsExistingDefault() throws {
        let (context, books) = try newBooks(state: "CA")
        let agency = TaxAgency(name: "City", liabilityAccountID: try books.systemAccount(.salesTaxPayable).id)
        context.insert(agency)
        let local = TaxRate(name: "Los Angeles", rateMillionths: 22_500, agency: agency)
        context.insert(local)
        try books.setDefaultTax(local.id)
        let state = try #require(try books.setUpStateSalesTax())
        #expect(state.rateMillionths == 72_500)
        #expect(try books.company()?.defaultTaxGroupID == local.id)
    }

    @Test("Tasa local sumada a la estatal: grupo «Austin, TX» 8.25 % como predeterminado de las facturas nuevas")
    func localRateAddedToState() throws {
        let (context, books) = try newBooks(state: "TX")
        let texas = try #require(try books.setUpStateSalesTax())
        #expect(try books.defaultTaxCode()?.rateMillionths == 62_500)

        let (rate, group) = try books.addTaxRate(name: " Austin ", rateMillionths: 20_000, agency: texas.agency, use: .addToDefault)
        let combined = try #require(group)
        #expect(rate.name == "Austin")
        #expect(rate.agency?.id == texas.agency?.id)
        #expect(combined.name == "Austin, TX")
        #expect(combined.combinedRateMillionths == 82_500)
        #expect(Set((combined.rates ?? []).map(\.id)) == [texas.id, rate.id])
        #expect(try books.company()?.defaultTaxGroupID == combined.id)
        #expect(try context.fetchCount(FetchDescriptor<TaxAgency>()) == 1)

        // Una factura nueva cobra las dos tasas.
        let defaults = try books.newInvoiceDefaults(for: nil)
        #expect(defaults.taxGroupID == combined.id)
        let components = try books.taxComponents(groupID: defaults.taxGroupID, on: .now)
        #expect(components.map(\.rateMillionths).sorted() == [20_000, 62_500])

        // Otra tasa más se suma al grupo predeterminado en uno nuevo.
        let (_, next) = try books.addTaxRate(name: "Distrito", rateMillionths: 5_000, agency: texas.agency, use: .addToDefault)
        #expect(next?.name == "Austin, TX + Distrito")
        #expect(next?.combinedRateMillionths == 87_500)
        #expect(try books.company()?.defaultTaxGroupID == next?.id)
    }

    @Test("Alta con la tasa total: Texas 6.25 % + «Austin» 2 % en un grupo «Austin, TX» 8.25 % predeterminado")
    func onboardingTotalRate() throws {
        let (_, books) = try newBooks(state: "TX")
        let code = try #require(try books.setUpSalesTax(totalMillionths: 82_500, localName: " Austin "))
        #expect(code.name == "Austin, TX")
        #expect(code.rateMillionths == 82_500)
        #expect(Set(code.rates.map(\.name)) == ["Texas", "Austin"])
        #expect(code.rates.allSatisfy { $0.agency?.name == "Texas Comptroller" })
        #expect(try books.company()?.defaultTaxGroupID == code.id)

        // Igual a la estatal o sin total: solo la tasa del estado.
        let (_, same) = try newBooks(state: "TX")
        #expect(try same.setUpSalesTax(totalMillionths: 62_500)?.name == "Texas")
        let (_, none) = try newBooks(state: "TX")
        #expect(try none.setUpSalesTax(totalMillionths: nil)?.rateMillionths == 62_500)

        // Sin nombre, la parte local se llama «Local»; menor que la estatal, error.
        let (_, unnamed) = try newBooks(state: "TX")
        #expect(try unnamed.setUpSalesTax(totalMillionths: 72_500)?.rates.contains { $0.name == "Local" } == true)
        let (_, low) = try newBooks(state: "TX")
        #expect(throws: BookkeepingError.self) { try low.setUpSalesTax(totalMillionths: 50_000) }

        // Oregon (sin sales tax estatal): no crea nada aunque se escriba un total.
        let (_, oregon) = try newBooks(state: "OR")
        #expect(try oregon.setUpSalesTax(totalMillionths: 20_000) == nil)
    }

    @Test("Tasa nueva sin sumar, como predeterminado sin haberlo, agencia nueva y datos malos")
    func addTaxRateVariants() throws {
        let (context, books) = try newBooks(state: "TX")
        let texas = try #require(try books.setUpStateSalesTax())
        let (kept, none) = try books.addTaxRate(name: "Dallas", rateMillionths: 20_000, agency: texas.agency, use: .keep)
        #expect(none == nil)
        #expect(try books.company()?.defaultTaxGroupID == texas.id)
        #expect(kept.agency?.id == texas.agency?.id)

        // Oregon: sin predeterminado, «sumar» deja la tasa sola como predeterminado; con agencia nueva.
        let (_, oregon) = try newBooks(state: "OR")
        let (local, group) = try oregon.addTaxRate(name: "Portland", rateMillionths: 10_000, agency: nil,
                                                   newAgencyName: "City of Portland", use: .addToDefault)
        #expect(group == nil)
        #expect(local.agency?.name == "City of Portland")
        #expect(local.agency?.liabilityAccountID == (try oregon.systemAccount(.salesTaxPayable)).id)
        #expect(try oregon.company()?.defaultTaxGroupID == local.id)

        #expect(throws: BookkeepingError.self) { try books.addTaxRate(name: " ", rateMillionths: 10_000, agency: texas.agency) }
        #expect(throws: BookkeepingError.self) { try books.addTaxRate(name: "Cero", rateMillionths: 0, agency: texas.agency) }
        #expect(throws: BookkeepingError.self) { try books.addTaxRate(name: "Sin agencia", rateMillionths: 10_000, agency: nil) }
        #expect(try context.fetchCount(FetchDescriptor<TaxRate>()) == 2)
    }

    @Test("Tipo de empresa sugerido por el nombre")
    func entityTypeFromName() {
        #expect(EntityType.suggested(forName: "Pintura Martínez LLC") == .llc)
        #expect(EntityType.suggested(forName: "Pintura Martínez, L.L.C.") == .llc)
        #expect(EntityType.suggested(forName: "acme llc.") == .llc)
        #expect(EntityType.suggested(forName: "Ríos Diseño Inc.") == .cCorp)
        #expect(EntityType.suggested(forName: "Taller Corp") == .cCorp)
        #expect(EntityType.suggested(forName: "Gómez & Ruiz LLP") == .partnership)
        #expect(EntityType.suggested(forName: "Pintura Martínez") == nil)
        #expect(EntityType.suggested(forName: "Llcanto") == nil)
        #expect(EntityType.suggested(forName: "") == nil)
    }

    @Test("Saldo del banco: el asiento cuadra contra 3900 y el banco queda con ese saldo")
    func bankOpeningBalance() throws {
        let (_, books) = try newBooks(state: "TX")
        #expect(try !books.hasOpeningBalances())
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let entry = try #require(try books.recordOpeningBalances(bank: 1_250_000, on: date))
        #expect(entry.source == .opening)
        #expect(entry.status == .posted)
        #expect(entry.date == date)
        #expect(entry.draft.isBalanced)
        #expect(entry.draft.totalDebits == 1_250_000)

        let accounts = try books.accounts()
        let checking = try #require(accounts.first { $0.code == "1010" })
        let equity = try #require(accounts.first { $0.code == "3900" })
        #expect(equity.subtype == .openingBalanceEquity)
        let lines = try books.ledgerLines()
        #expect(ReportBuilder.balance(of: checking.ledgerAccount, lines: lines) == 1_250_000)
        #expect(ReportBuilder.balance(of: equity.ledgerAccount, lines: lines) == 1_250_000)
        #expect(try books.hasOpeningBalances())

        // La balanza de comprobación sigue cuadrada.
        let trial = ReportBuilder.trialBalance(accounts: try books.ledgerAccounts(), lines: lines, asOf: date)
        #expect(trial.isBalanced && trial.totalDebit == 1_250_000)
    }

    @Test("Banco y tarjeta: un solo asiento, la tarjeta debe ese saldo y 3900 queda por la diferencia")
    func bankAndCard() throws {
        let (_, books) = try newBooks(state: "TX")
        let entry = try #require(try books.recordOpeningBalances(bank: 500_000, creditCard: 120_000))
        #expect(entry.draft.isBalanced)
        let accounts = try books.accounts()
        let lines = try books.ledgerLines()
        func balance(_ code: String) throws -> Int64 {
            ReportBuilder.balance(of: try #require(accounts.first { $0.code == code }).ledgerAccount, lines: lines)
        }
        #expect(try balance("1010") == 500_000)
        #expect(try balance("2100") == 120_000)
        #expect(try balance("3900") == 380_000)

        // Debes más en la tarjeta de lo que hay en el banco: 3900 queda en negativo (saldo deudor).
        let (_, other) = try newBooks(state: "TX")
        let negative = try #require(try other.recordOpeningBalances(bank: 10_000, creditCard: 30_000))
        #expect(negative.draft.isBalanced)
        let equity = try #require(try other.accounts().first { $0.code == "3900" })
        #expect(ReportBuilder.balance(of: equity.ledgerAccount, lines: try other.ledgerLines()) == -20_000)
    }

    @Test("Sin importes no registra nada; negativos, error y nada escrito")
    func skipAndInvalid() throws {
        let (context, books) = try newBooks(state: "TX")
        #expect(try books.recordOpeningBalances(bank: 0) == nil)
        #expect(throws: BookkeepingError.self) { try books.recordOpeningBalances(bank: -5) }
        #expect(try context.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
        #expect(try !books.hasOpeningBalances())
    }

    @Test("Los datos de ejemplo ya cuentan con saldos de apertura y con impuesto predeterminado")
    func sampleBooks() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        try SampleData.populate(container.mainContext)
        let books = Bookkeeper(context: container.mainContext)
        #expect(try books.hasOpeningBalances())
        #expect(try books.company()?.defaultTaxGroupID != nil)
    }
}

@MainActor
@Suite("Ajustes: cambiar el estado de la empresa")
struct StateChangeTests {
    @Test("Crea la tasa del nuevo estado y la deja predeterminada si antes era la estatal sola")
    func replacesPlainStateRate() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let company = try books.setUpCompany(legalName: "Taller", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        try books.setUpSalesTax(totalMillionths: nil)
        let texas = try #require(try books.defaultTaxCode())
        #expect(texas.name == "Texas")

        company.state = "FL"
        let florida = try #require(try books.stateChanged(from: "TX", to: "FL"))
        #expect(florida.name == "Florida" && florida.rateMillionths == 60_000)
        #expect(company.defaultTaxGroupID == florida.id)
        #expect(florida.agency?.name == StateSalesTax.forState("FL")?.agency)
        // La de Texas sigue ahí (las facturas emitidas la usan).
        #expect(try books.taxRate(id: texas.id) != nil)

        // A un estado sin sales tax estatal: no se crea nada y el predeterminado se queda.
        company.state = "OR"
        #expect(try books.stateChanged(from: "FL", to: "OR") == nil)
        #expect(company.defaultTaxGroupID == florida.id)
    }

    @Test("Con un grupo estatal + local como predeterminado, solo crea la tasa nueva")
    func keepsCombinedGroup() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext, actor: "Pruebas")
        let company = try books.setUpCompany(legalName: "Taller", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
        try books.setUpSalesTax(totalMillionths: 82_500, localName: "Austin")
        let group = try #require(company.defaultTaxGroupID)
        company.state = "CA"
        let california = try #require(try books.stateChanged(from: "TX", to: "CA"))
        #expect(california.rateMillionths == 72_500)
        #expect(company.defaultTaxGroupID == group)
    }
}
