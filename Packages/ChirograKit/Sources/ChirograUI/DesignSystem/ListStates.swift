import SwiftUI

// Piezas comunes de las listas del iPhone y el iPad (repaso visual, build 56): la cabecera de resumen y el estado
// «Sin resultados», iguales en Ventas, Estimados, Clientes, Gastos y Proveedores.

/// Cabecera de resumen sobre el grupo de una lista (canvas `Ventas`): a la izquierda lo que se ve («5 facturas ·
/// Vencida»), a la derecha la etiqueta en gris y la cifra en `.headline` y `ink` («Por cobrar $7,170.02»). Si no cabe
/// en una línea, una debajo de la otra.
struct ListSummaryHeader: View {
    let title: Text
    /// Etiqueta gris de la derecha («Por cobrar», «12 clientes»).
    var label: Text? = nil
    /// Cifra destacada de la derecha, ya con formato.
    var amount: String? = nil
    /// Objetivo del recorrido sobre la cifra («sales.receivable»).
    var objetivo: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title.fixedSize()
                Spacer(minLength: 8)
                trailing.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                trailing
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .monospacedDigit()
        .textCase(nil)
    }

    @ViewBuilder
    private var trailing: some View {
        let stack = HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let label { label }
            if let amount { Text(verbatim: amount).font(.headline).foregroundStyle(Palette.ink) }
        }
        .accessibilityElement(children: .combine)
        if let objetivo { stack.recorridoObjetivo(objetivo) } else { stack }
    }
}

/// «Sin resultados» de una lista con búsqueda o filtro (canvas `Ventas`): la lupa, el porqué en una frase con punto y
/// «Quitar filtros» en la cápsula gris. Sin `clear`, sin botón.
struct NoResultsView: View {
    let message: String
    var clear: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label("Sin resultados", systemImage: "magnifyingglass")
        } description: {
            Text(message)
        } actions: {
            if let clear {
                Button("Quitar filtros", action: clear).buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: 560)
    }
}
