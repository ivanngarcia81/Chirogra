import CoreGraphics
import Testing
@testable import ChirograUI

/// La tarjeta del recorrido se desliza como la bienvenida (Eric, Beta Family, build 55): a la izquierda, el paso
/// siguiente; a la derecha, el anterior.
@Suite("Deslizar el recorrido")
struct RecorridoDeslizarTests {
    @Test("Horizontal y largo: a la izquierda, siguiente; a la derecha, anterior")
    func direccion() {
        #expect(Recorrido.deslizamiento(CGSize(width: -80, height: 10), previsto: CGSize(width: -120, height: 10)) == .siguiente)
        #expect(Recorrido.deslizamiento(CGSize(width: 80, height: -10), previsto: CGSize(width: 120, height: -10)) == .anterior)
    }

    @Test("Corto, vertical o en diagonal no cuenta")
    func noCuenta() {
        #expect(Recorrido.deslizamiento(CGSize(width: -30, height: 0), previsto: CGSize(width: -40, height: 0)) == nil)
        #expect(Recorrido.deslizamiento(CGSize(width: 10, height: 120), previsto: CGSize(width: 10, height: 200)) == nil)
        #expect(Recorrido.deslizamiento(CGSize(width: -60, height: 55), previsto: CGSize(width: -60, height: 55)) == nil)
    }

    @Test("Un golpe rápido cuenta aunque el dedo se mueva poco, si va hacia el mismo lado")
    func golpe() {
        #expect(Recorrido.deslizamiento(CGSize(width: -30, height: 0), previsto: CGSize(width: -160, height: 5)) == .siguiente)
        #expect(Recorrido.deslizamiento(CGSize(width: 30, height: 0), previsto: CGSize(width: 160, height: 5)) == .anterior)
        #expect(Recorrido.deslizamiento(CGSize(width: 30, height: 0), previsto: CGSize(width: -160, height: 0)) == nil)
    }

    @Test("Sin salirse: ni antes del primero ni después del último")
    func limites() {
        #expect(Recorrido.pasoTras(.siguiente, actual: 0, total: 5) == 1)
        #expect(Recorrido.pasoTras(.anterior, actual: 3, total: 5) == 2)
        #expect(Recorrido.pasoTras(.anterior, actual: 0, total: 5) == nil)
        #expect(Recorrido.pasoTras(.siguiente, actual: 4, total: 5) == nil)
        #expect(Recorrido.pasoTras(.siguiente, actual: 10, total: 12) == 11)
        #expect(Recorrido.pasoTras(.siguiente, actual: 0, total: 1) == nil)
    }
}
