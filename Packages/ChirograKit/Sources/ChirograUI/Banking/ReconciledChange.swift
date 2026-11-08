import ChirograData
import SwiftData
import SwiftUI

// Aviso al cambiar algo conciliado (DISEÑO §4.6: «las líneas conciliadas quedan marcadas y no deben editarse sin
// advertencia»). `Bookkeeper.reverse` —y con él anular o corregir facturas, gastos y asientos— falla con
// `BookkeepingError.reconciledLines` si el asiento tiene líneas de una conciliación terminada. Los editores donde ocurre
// muestran este aviso y, si el usuario confirma, repiten la acción con `allowingReconciledChanges()` (queda en la
// auditoría). Mismo patrón que `ClosedPeriodRetry` (periodo cerrado).

/// Lo que hay que repetir si el usuario acepta cambiar algo conciliado.
struct ReconciledChangeRetry: Identifiable {
    let id = UUID()
    /// La acción, con un `Bookkeeper` que ya admite cambiar lo conciliado.
    let perform: (Bookkeeper) throws -> Void
}

enum ReconciledChange {
    /// El error es «tiene líneas conciliadas».
    static func matches(_ error: Error) -> Bool {
        if case BookkeepingError.reconciledLines = error { return true }
        return false
    }

    /// Si `error` es de algo conciliado, la petición para repetir `perform` tras confirmar; si no, `nil`.
    static func retry(for error: Error, _ perform: @escaping (Bookkeeper) throws -> Void) -> ReconciledChangeRetry? {
        matches(error) ? ReconciledChangeRetry(perform: perform) : nil
    }
}

private struct ReconciledChangeConfirmation: ViewModifier {
    @Binding var retry: ReconciledChangeRetry?
    let onError: (String) -> Void
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .alert("¿Cambiar algo conciliado?", isPresented: Binding(get: { retry != nil }, set: { if !$0 { retry = nil } }),
                   presenting: retry) { request in
                Button("Cambiar de todos modos", role: .destructive) {
                    do { try request.perform(Bookkeeper(context: context).allowingReconciledChanges()) } catch { onError(error.localizedDescription) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { _ in
                Text("Este movimiento ya está conciliado con el extracto del banco. Si lo cambias, esa conciliación dejará de cuadrar: tendrás que reabrirla y revisarla. Quedará anotado.")
            }
    }
}

extension View {
    /// Cuando `retry` tiene algo, pregunta si cambiar lo conciliado y lo repite (ver `ReconciledChangeConfirmation`).
    func reconciledChangeConfirmation(_ retry: Binding<ReconciledChangeRetry?>, onError: @escaping (String) -> Void) -> some View {
        modifier(ReconciledChangeConfirmation(retry: retry, onError: onError))
    }
}
