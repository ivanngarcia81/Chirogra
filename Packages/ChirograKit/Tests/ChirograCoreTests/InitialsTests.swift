import Testing
@testable import ChirograCore

@Suite("Iniciales de avatar")
struct InitialsTests {
    @Test("Primera letra de las dos primeras palabras, mayúscula y sin acentos", arguments: [
        ("Ríos Diseño & Obra", "RD"),
        ("café aurora", "CA"),
        ("Ángel Ñúñez", "AN"),
        ("Clínica Del Valle", "CD"),
        ("Maderas del Norte", "MD"),
        ("Adobe", "A"),
        ("& Co. Estudio", "CE"),
        ("  Hotel   Mirador  ", "HM"),
        ("Jean-Luc Picard", "JL"),
        ("3M Company", "3C"),
        ("", "?"),
        ("&", "?"),
    ])
    func initials(name: String, expected: String) {
        #expect(Initials.from(name) == expected)
    }
}
