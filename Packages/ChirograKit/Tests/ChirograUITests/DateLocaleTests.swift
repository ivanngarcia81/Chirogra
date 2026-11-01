import Foundation
import Testing
@testable import ChirograUI

@Suite("Orden de las fechas según idioma y región")
struct DateLocaleTests {
    /// 15 de enero de 2027, a mediodía en UTC para que no cambie de día con la zona horaria.
    let date = Date(timeIntervalSince1970: 1_800_014_400)

    func numeric(_ locale: Locale) -> String {
        var style = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    func text(_ locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    @Test("Español en EE. UU.: cifras mes/día (región) y mes en letra día-mes (canvas)")
    func spanishUS() {
        let locales = Locale.dateLocales(language: "es", region: "US")
        #expect(numeric(locales.numeric) == "1/15/2027")
        #expect(text(locales.text) == "15 ene 2027")
    }

    @Test("Español en México y España: día/mes en los dos casos", arguments: ["MX", "ES"])
    func spanishDayFirst(region: String) {
        let locales = Locale.dateLocales(language: "es", region: region)
        #expect(numeric(locales.numeric) == "15/1/2027")
        #expect(text(locales.text) == "15 ene 2027")
    }

    @Test("Inglés en EE. UU.: mes primero")
    func englishUS() {
        let locales = Locale.dateLocales(language: "en", region: "US")
        #expect(numeric(locales.numeric) == "1/15/2027")
        #expect(text(locales.text) == "Jan 15, 2027")
    }
}
