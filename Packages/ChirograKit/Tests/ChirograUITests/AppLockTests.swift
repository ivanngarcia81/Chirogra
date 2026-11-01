import LocalAuthentication
import Testing
@testable import ChirograUI

/// El mensaje rojo «No se pudo verificar tu identidad» solo aparece ante un fallo real de Face ID.
@Suite("Bloqueo con Face ID")
struct AppLockTests {
    @Test("Cancelar o una interrupción del sistema no es un fallo", arguments: [
        LAError.Code.userCancel, .appCancel, .systemCancel, .notInteractive,
    ])
    func cancellationIsNotFailure(code: LAError.Code) {
        #expect(!LockView.isFailure(LAError(code)))
    }

    @Test("Una identidad no reconocida o bloqueada sí es un fallo", arguments: [
        LAError.Code.authenticationFailed, .biometryLockout,
    ])
    func realFailures(code: LAError.Code) {
        #expect(LockView.isFailure(LAError(code)))
    }
}
