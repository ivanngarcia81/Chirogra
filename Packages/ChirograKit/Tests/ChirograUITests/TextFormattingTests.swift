import Foundation
import Testing
@testable import ChirograUI

@Suite("Formato de textos")
struct TextFormattingTests {
    @Test("Solo la primera letra va en mayúscula")
    func sentenceCased() {
        #expect("octubre de 2026".sentenceCased == "Octubre de 2026")
        #expect("".sentenceCased == "")
        #expect("éxito".sentenceCased == "Éxito")
    }
}
