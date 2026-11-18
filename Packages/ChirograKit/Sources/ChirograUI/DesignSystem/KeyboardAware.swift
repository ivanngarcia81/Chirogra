import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    /// Barra de vidrio inferior (`safeAreaBar`) que se esconde mientras el teclado está a la vista (iOS): si no, sube
    /// con el teclado y tapa los campos (el alta, recorrido «cliente nuevo», 5-nov). Mismo patrón que `HiddenWhile` del
    /// editor de facturas, pero sigue el teclado por su cuenta. En el Mac pone la barra siempre.
    func bottomBarHiddenWithKeyboard<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(KeyboardHidingBottomBar(bar: bar()))
    }
}

extension View {
    /// Sin el aviso de que el teclado se abrió, no deja sitio para él. Un tester (Beta Family, 18-nov, iPhone 16e con
    /// iOS 26.7.1) vio la lista de Ventas cortada a media pantalla y la barra de la factura flotando a la altura del
    /// teclado, sin teclado a la vista; no se reprodujo en el simulador. Con el teclado de verdad no cambia nada.
    func ignoringStaleKeyboardSpace() -> some View { modifier(StaleKeyboardSpace()) }
}

private struct StaleKeyboardSpace: ViewModifier {
    @State private var keyboardShown = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .ignoresSafeArea(keyboardShown ? [] : .keyboard, edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        #else
        content
        #endif
    }
}

private struct KeyboardHidingBottomBar<Bar: View>: ViewModifier {
    let bar: Bar
    @State private var keyboardShown = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if !keyboardShown { bar }
            }
            .ignoresSafeArea(keyboardShown ? [] : .keyboard, edges: .bottom)   // como `ignoringStaleKeyboardSpace`
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        #else
        content.safeAreaBar(edge: .bottom, spacing: 0) { bar }
        #endif
    }
}
