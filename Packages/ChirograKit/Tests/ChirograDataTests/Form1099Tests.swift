import Testing
@testable import ChirograData

@Suite("Mínimo del 1099-NEC")
struct Form1099Tests {
    @Test("2025 y antes: $600", arguments: [2019, 2024, 2025])
    func through2025(year: Int) {
        #expect(Form1099.threshold(forTaxYear: year) == 60_000)
    }

    @Test("Desde 2026: $2,000 (también 2027 y siguientes mientras el IRS no publique el ajuste)", arguments: [2026, 2027, 2030])
    func from2026(year: Int) {
        #expect(Form1099.threshold(forTaxYear: year) == 200_000)
    }

    @Test("Llegar al mínimo cuenta; quedarse un centavo por debajo, no")
    func boundary() {
        #expect(Form1099.reachesThreshold(paid: 60_000, taxYear: 2025))
        #expect(!Form1099.reachesThreshold(paid: 59_999, taxYear: 2025))
        #expect(Form1099.reachesThreshold(paid: 200_000, taxYear: 2026))
        #expect(!Form1099.reachesThreshold(paid: 199_999, taxYear: 2026))
        // $1,500 pagados: en 2025 obligaba a enviar el 1099-NEC; en 2026, ya no.
        #expect(Form1099.reachesThreshold(paid: 150_000, taxYear: 2025))
        #expect(!Form1099.reachesThreshold(paid: 150_000, taxYear: 2026))
    }

    @Test("La nota depende de la marca 1099, de lo pagado y del año")
    func notice() {
        #expect(Form1099.notice(is1099: false, paid: 500_000, taxYear: 2026) == .notReportable)
        #expect(Form1099.notice(is1099: true, paid: 150_000, taxYear: 2026) == .belowThreshold(threshold: 200_000))
        #expect(Form1099.notice(is1099: true, paid: 150_000, taxYear: 2025) == .reached(paid: 150_000, threshold: 60_000))
        #expect(Form1099.notice(is1099: true, paid: 250_000, taxYear: 2027) == .reached(paid: 250_000, threshold: 200_000))
        #expect(Form1099.notice(is1099: true, paid: 0, taxYear: 2024) == .belowThreshold(threshold: 60_000))
    }
}
