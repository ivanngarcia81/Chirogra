import SwiftUI

/// Detalle de una sola columna en el iPad (y el Mac) a lo ancho de lectura (720 pt, como `InvoiceDetailView`) y centrado,
/// con el mismo margen a cada lado, como los reportes (decisión del usuario del 21-nov). Para los detalles hechos con
/// `Form` o `List` (gasto, factura por pagar, asiento, movimiento por revisar, conciliación y regla), que ocupaban todo el
/// ancho del detalle. Con margen y no con un marco: así se desplaza también desde los lados. En columnas estrechas
/// (iPhone, iPad en vertical con la lista) no cambia nada.
private struct ReadableDetailWidth: ViewModifier {
    static let column: CGFloat = 720
    /// Margen de un `Form` agrupado del sistema a cada lado.
    static let systemMargin: CGFloat = 20
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            if width > Self.column + 2 * Self.systemMargin {
                content.contentMargins(.horizontal, (width - Self.column) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableDetailWidth() -> some View { modifier(ReadableDetailWidth()) }
}

/// «Editar» de la barra de un detalle: en el iPad, el lápiz, como la factura y el cliente; en el iPhone y el Mac, la
/// palabra, como en el resto de la app (repaso visual del 21-nov: el estimado, el gasto y el proveedor decían «Edit»
/// junto a detalles que usaban el lápiz).
struct EditToolbarButton: View {
    let action: () -> Void
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if sizeClass == .regular {
            Button("Editar", systemImage: "pencil", action: action).headerButton()
        } else {
            Button("Editar", action: action).headerButton()
        }
        #else
        Button("Editar", action: action).headerButton()
        #endif
    }
}
