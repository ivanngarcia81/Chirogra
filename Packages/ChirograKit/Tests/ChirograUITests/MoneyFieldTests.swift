import Foundation
import Testing
@testable import ChirograUI

/// El campo de dinero se edita sin la moneda y lee coma o punto decimal (Yurii S., Beta Family, build 54:
/// «10,99 US$80» con el formato de Ucrania).
@Suite("Campo de dinero")
struct MoneyFieldTests {
    let us = Locale(identifier: "en_US")
    let ua = Locale(identifier: "uk_UA")
    let es = Locale(identifier: "es_ES")

    @Test("Al editar, solo el número; cero es vacío")
    func editingText() {
        #expect(MoneyField.text(1099, editing: true, locale: us) == "10.99")
        #expect(MoneyField.text(1099, editing: true, locale: ua) == "10,99")
        #expect(MoneyField.text(5000, editing: true, locale: us) == "50")
        #expect(MoneyField.text(123_456_78, editing: true, locale: us) == "123456.78")
        #expect(MoneyField.text(-1250, editing: true, locale: us) == "-12.50")
        #expect(MoneyField.text(0, editing: true, locale: us) == "")
        #expect(MoneyField.text(0, editing: false, locale: us) == "")
    }

    @Test("Sin editar, con la moneda")
    func shownText() {
        #expect(MoneyField.text(1099, editing: false, locale: us) == "$10.99")
        #expect(MoneyField.text(1099, editing: false, locale: ua).contains("10,99"))
    }

    @Test("Lee lo escrito en cada formato", arguments: [
        ("10.99", "en_US", Int64(1099)), ("10,99", "uk_UA", 1099), ("80", "uk_UA", 8000),
        ("10,5", "en_US", 1050), ("1,000", "en_US", 100_000), ("1,000.5", "en_US", 100_050),
        ("1.000", "es_ES", 100_000), ("1.000,25", "es_ES", 100_025), ("$12.30", "en_US", 1230),
        ("12,30 US$", "uk_UA", 1230), ("-45.10", "en_US", -4510), ("\u{2212}$45.10", "en_US", -4510),
        ("0.005", "en_US", 1), (".5", "en_US", 50), ("7.", "en_US", 700), ("", "en_US", 0), ("  ", "uk_UA", 0),
    ])
    func parses(text: String, locale: String, expected: Int64) {
        #expect(MoneyField.minorUnits(from: text, locale: Locale(identifier: locale)) == expected)
    }

    @Test("Sin cifras no cambia el importe")
    func garbage() {
        #expect(MoneyField.minorUnits(from: "US$", locale: ua) == nil)
        #expect(MoneyField.minorUnits(from: "-", locale: us) == nil)
        #expect(MoneyField.minorUnits(from: ",", locale: ua) == nil)
    }

    @Test("Ida y vuelta: lo que enseña al editar se lee igual", arguments: [Int64(1), 99, 1099, 5000, 123_456_78, -1250])
    func roundTrip(minorUnits: Int64) {
        for locale in [us, ua, es] {
            let text = MoneyField.text(minorUnits, editing: true, locale: locale)
            #expect(MoneyField.minorUnits(from: text, locale: locale) == minorUnits)
        }
    }
}
