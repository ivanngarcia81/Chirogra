import ChirograData
import Foundation
import Testing
@testable import ChirograUI

/// Periodo que muestra Impuestos según la frecuencia de la agencia (Eric, Beta Family, build 55).
@MainActor
@Suite("Periodo de Impuestos")
struct SalesTaxShownPeriodTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { day(2026, 11, 20) }

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Mensual: el mes con su intervalo y la fecha límite; −3 es agosto")
    func monthly() {
        let current = SalesTaxShownPeriod(.monthly, now: now, calendar: calendar)
        #expect(current.interval == DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1)))
        #expect(current.deadline == day(2026, 12, 20))
        #expect(current.subtitle.hasSuffix(" · declaración mensual"))
        #expect(current.pickerLabel == "Mes")
        #expect(current.paymentsFoot(hasPayments: true) == "Pagos del mes")
        let earlier = SalesTaxShownPeriod(.monthly, offset: -3, now: now, calendar: calendar)
        #expect(earlier.interval.start == day(2026, 8, 1))
        #expect(earlier.title.contains("2026"))
    }

    @Test("Trimestral: «T3 2026», su columna «T3» y el intervalo de julio a septiembre")
    func quarterly() {
        let previous = SalesTaxShownPeriod(.quarterly, offset: -1, now: now, calendar: calendar)
        #expect(previous.interval == DateInterval(start: day(2026, 7, 1), end: day(2026, 10, 1)))
        #expect(previous.deadline == day(2026, 10, 20))
        #expect(previous.name == "T3 2026")
        #expect(previous.columnName == "T3")
        #expect(previous.title.hasPrefix("T3 2026 · "))
        #expect(previous.subtitle.hasSuffix(" · declaración trimestral"))
        #expect(previous.paymentsFoot(hasPayments: false) == "Sin pagos en el trimestre")
    }

    @Test("Anual: el año entero; −3 es 2023")
    func annual() {
        let current = SalesTaxShownPeriod(.annual, now: now, calendar: calendar)
        #expect(current.interval == DateInterval(start: day(2026, 1, 1), end: day(2027, 1, 1)))
        #expect(current.deadline == day(2027, 1, 20))
        #expect(current.title == "2026" && current.name == "2026" && current.columnName == "2026")
        #expect(current.subtitle == "2026 · declaración anual")
        #expect(SalesTaxShownPeriod(.annual, offset: -3, now: now, calendar: calendar).title == "2023")
    }
}
