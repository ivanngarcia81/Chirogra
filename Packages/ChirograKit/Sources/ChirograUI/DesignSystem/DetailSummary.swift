import SwiftUI

/// Cabecera de una ficha, la de la factura (`FacturaDetalle`): el nombre pequeño arriba, la cifra grande y debajo el
/// estado y una línea gris. Centrada en el iPhone; a la izquierda en el iPad ancho y el Mac. Repaso visual, build 56:
/// estimado, gasto, cliente, proveedor y factura por pagar tenían cada uno la suya (tarjeta, icono a la izquierda,
/// 28 o 40 pt).
struct DetailSummary<Status: View>: View {
    let name: String
    let amount: String
    /// Tachada (gasto anulado).
    var struck = false
    /// `nil`: a la izquierda en el iPad ancho y el Mac, como la factura; las fichas con diseño ancho propio (cliente,
    /// proveedor) la piden centrada.
    var alignment: HorizontalAlignment? = nil
    /// Iniciales en círculo encima del nombre: las fichas de cliente y proveedor son de alguien, no un documento
    /// (Iván, 21-nov: se queda el círculo).
    var initials: String? = nil
    @ViewBuilder var status: Status

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// El tamaño de la cifra de la factura.
    static var amountFont: Font { .system(.largeTitle, weight: .bold) }

    private var isLeading: Bool {
        if let alignment { return alignment == .leading }
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: isLeading ? .leading : .center, spacing: 2) {
            if let initials {
                Monogram(initials: initials, side: 64, fontScale: 0.4, relativeTo: .title, maxScale: 1.4)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
            }
            Text(name).font(.subheadline).foregroundStyle(Palette.ink2)
            Text(amount)
                .font(Self.amountFont).monospacedDigit()
                .foregroundStyle(Palette.ink)
                .strikethrough(struck)
                .minimumScaleFactor(0.6).lineLimit(1)
            status
        }
        .multilineTextAlignment(isLeading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .center)
        .padding(.horizontal, isLeading ? 8 : 16)
        .padding(.vertical, isLeading ? 6 : 10)
        .accessibilityElement(children: .combine)
    }
}

/// Línea gris bajo el estado de `DetailSummary` («Categoría · fecha», «Cliente desde…»).
struct DetailSummaryLine: View {
    let text: String

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2).padding(.top, 2)
    }
}
