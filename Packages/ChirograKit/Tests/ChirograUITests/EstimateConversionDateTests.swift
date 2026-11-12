import ChirograCore
import ChirograData
import Foundation
import Testing
@testable import ChirograUI

/// QA Hudson (12-nov), H01: «Convertir en factura» creaba la factura con la fecha de hoy sin decirlo. Ahora propone la
/// fecha de aceptación del estimado si cae en un periodo abierto.
@MainActor
@Suite("Fecha de la factura al convertir un estimado")
struct EstimateConversionDateTests {
    let calendar = Calendar.current
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10))!
    func day(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day))! }

    @Test("Aceptado en octubre, sin cierre: la factura propone el día de aceptación")
    func acceptedDate() {
        let estimate = Estimate(customer: nil, issueDate: day(10, 2))
        estimate.acceptedDate = day(10, 5)
        #expect(EstimateConversionChoice.proposedDate(for: estimate, lockDate: nil, now: now, calendar: calendar) == day(10, 5))
    }

    @Test("Sin aceptar, aceptado en un mes cerrado o en el futuro: hoy")
    func fallsBackToToday() {
        let estimate = Estimate(customer: nil, issueDate: day(10, 2))
        #expect(EstimateConversionChoice.proposedDate(for: estimate, lockDate: nil, now: now, calendar: calendar) == now)
        estimate.acceptedDate = day(10, 5)
        #expect(EstimateConversionChoice.proposedDate(for: estimate, lockDate: day(10, 31), now: now, calendar: calendar) == now)
        estimate.acceptedDate = day(11, 20)
        #expect(EstimateConversionChoice.proposedDate(for: estimate, lockDate: nil, now: now, calendar: calendar) == now)
    }
}

extension EstimateConversionDateTests {
    @Test("Se acepta con la pantalla abierta: la propuesta pasa a la fecha de aceptación, salvo que se eligiera otra")
    func followsAcceptance() {
        let estimate = Estimate(customer: nil, issueDate: day(10, 2))
        var choice = EstimateConversionChoice()
        choice.prepareDate(for: estimate, lockDate: nil)
        estimate.acceptedDate = day(10, 6)
        choice.prepareDate(for: estimate, lockDate: nil)
        #expect(choice.issueDate == day(10, 6))
        choice.issueDate = day(10, 9)
        estimate.acceptedDate = day(10, 7)
        choice.prepareDate(for: estimate, lockDate: nil)
        #expect(choice.issueDate == day(10, 9))
    }
}
