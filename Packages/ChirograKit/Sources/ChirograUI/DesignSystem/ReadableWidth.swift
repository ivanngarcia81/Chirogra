import SwiftUI

/// Detalle de una sola columna en el iPad (y el Mac) a lo ancho de lectura (720 pt, como `InvoiceDetailView`) y centrado,
/// con el mismo margen a cada lado, como los reportes (decisión del usuario del 21-nov). Para los detalles hechos con
/// `Form` o `List` (gasto, factura por pagar, asiento, movimiento por revisar, conciliación y regla), que ocupaban todo el
/// ancho del detalle. Con margen y no con un marco: así se desplaza también desde los lados. En columnas estrechas
/// (iPhone, iPad en vertical con la lista) no cambia nada.
private struct ReadableDetailWidth: ViewModifier {
    var column: CGFloat = 720
    /// Margen de un `Form` agrupado del sistema a cada lado.
    static let systemMargin: CGFloat = 20
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            if width > column + 2 * Self.systemMargin {
                content.contentMargins(.horizontal, (width - column) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableDetailWidth() -> some View { modifier(ReadableDetailWidth()) }

    /// iPad: las páginas anchas de una columna (Libro mayor, Cierre de periodo, Bitácora e Impuestos) a 820 pt de
    /// contenido y centradas, como los reportes (`ReportsView.readableWidth`; pedido del usuario, 21-nov: «está muy
    /// ancho, debe centrarse como las páginas anteriores»). Para el contenido de un `ScrollView`; en un `List`,
    /// `padReadingList()`. En el iPhone y el Mac no cambia nada.
    @ViewBuilder func padReadingColumn() -> some View {
        #if os(iOS)
        frame(maxWidth: PadReading.content + 2 * Metrics.gutter).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// `padReadingColumn()` para un `List` agrupado (su margen del sistema hace de margen de la página). Con un marco y
    /// no con `contentMargins`: así, en la Bitácora, las filas salían corridas a la izquierda y el filtro pegado al borde.
    /// `content`: 820 en las páginas, 720 en un detalle abierto desde ellas (como `readableDetailWidth`).
    @ViewBuilder func padReadingList(_ content: CGFloat = PadReading.content) -> some View {
        #if os(iOS)
        frame(maxWidth: content + 2 * ReadableDetailWidth.systemMargin).frame(maxWidth: .infinity)
            .background(Palette.background)
        #else
        self
        #endif
    }
}

/// Ancho de lectura de las páginas anchas del iPad: el de los reportes.
enum PadReading {
    static let content: CGFloat = 820
    /// Un detalle (`Form`) abierto desde una de esas páginas: el ancho de `readableDetailWidth`.
    static let detail: CGFloat = 720
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

/// Título con su detalle gris («Patio redesign · 1 × $2,400.00 · taxable», «Entry #2 · Nov 21, 2026 · Current»): en el
/// iPad, en la misma línea si cabe; si no, o en el iPhone y el Mac, el detalle debajo (pedido del usuario, 21-nov: en
/// los detalles del iPad sobraba sitio y quedaban dos líneas). Para las líneas de los documentos y los historiales.
struct TituloConDetalle: View {
    let title: String
    let detail: String
    var titleWeight: Font.Weight = .regular
    var detailFont: Font = .footnote
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    private var enLinea: Bool {
        #if os(iOS)
        sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize && !detail.isEmpty
        #else
        false
        #endif
    }

    var body: some View {
        if enLinea {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    titulo.lineLimit(1)
                    detalle.lineLimit(1)
                }
                apilado
            }
        } else {
            apilado
        }
    }

    private var titulo: some View { Text(title).fontWeight(titleWeight).foregroundStyle(Palette.ink) }
    private var detalle: some View { Text(detail).font(detailFont).foregroundStyle(Palette.ink2) }

    private var apilado: some View {
        VStack(alignment: .leading, spacing: 2) {
            titulo
            if !detail.isEmpty { detalle }
        }
    }
}
