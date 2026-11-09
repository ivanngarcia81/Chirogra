import SwiftUI

// Filas de la columna maestro del iPad y del Mac (canvas `iPadVentas`), comunes a todas las listas maestro
// (`Shell/MasterDetail.swift`) y a la de Estimados (`Sales/EstimateMasterList.swift`).

extension EnvironmentValues {
    /// La fila de la columna maestro es la elegida: va sobre el relleno de Tinta y todo su texto pasa a blanco.
    @Entry var isMasterRowSelected = false
}

/// Colores de una fila de la columna maestro, en blanco si es la elegida (decisión del usuario del 2-nov: relleno de
/// Tinta con texto blanco, como `iPadVentas`). El blanco sobre `brandFill` da 7,5:1 en claro y 5,4:1 en oscuro; el
/// secundario al 92 %, 4,7:1 en oscuro (AA). El del canvas (80 %) quedaba en ~4:1 en oscuro.
struct MasterRowColors {
    let isSelected: Bool
    var primary: Color { isSelected ? Palette.onBrandFill : Palette.ink }
    var secondary: Color { isSelected ? Palette.onBrandFill.opacity(0.92) : Palette.ink2 }
    func amount(_ color: Color) -> Color { isSelected ? Palette.onBrandFill : color }

    /// Detalle de la fila: 13 pt en iPhone e iPad, 11 en el Mac (`.footnote` del Mac son 10).
    static var detailFont: Font {
        #if os(macOS)
        .subheadline
        #else
        .footnote
        #endif
    }
}

/// Estado de una fila maestro: el de su chip, o en blanco (punto y texto) sobre la fila elegida.
struct MasterStatus: View {
    let chip: StatusChip
    @Environment(\.isMasterRowSelected) private var isSelected

    var body: some View {
        if isSelected {
            StatusChip(text: chip.text, foreground: Palette.onBrandFill, background: .clear, compact: true, dot: Palette.onBrandFill)
        } else {
            chip
        }
    }
}

/// Símbolo pequeño de una fila maestro (clip del recibo, tipo de cuenta), gris o blanco en la elegida.
struct MasterSymbol: View {
    let systemImage: String
    let label: LocalizedStringKey?
    @Environment(\.isMasterRowSelected) private var isSelected

    var body: some View {
        let image = Image(systemName: systemImage)
            .font(MasterRowColors.detailFont)
            .foregroundStyle(MasterRowColors(isSelected: isSelected).secondary)
        if let label { image.accessibilityLabel(Text(label)) } else { image.accessibilityHidden(true) }
    }
}

/// Dato corto de una fila maestro sin estado («1099»), en el gris del detalle o en blanco.
struct MasterDetailText: View {
    let text: String
    @Environment(\.isMasterRowSelected) private var isSelected

    var body: some View {
        Text(text).font(MasterRowColors.detailFont).foregroundStyle(MasterRowColors(isSelected: isSelected).secondary)
    }
}

/// Fila de la columna maestro (canvas `iPadVentas`): nombre e importe en `.body` arriba; detalle y estado en `.footnote`
/// abajo. El nombre pasa a una segunda línea antes que recortarse; con tamaños de accesibilidad, todo en columna.
struct MasterRow<Badge: View>: View {
    let title: String
    let amount: String
    let subtitle: String
    var amountColor = Palette.ink
    @ViewBuilder var badge: Badge
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isMasterRowSelected) private var isSelected

    var body: some View {
        let colors = MasterRowColors(isSelected: isSelected)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(amount).monospacedDigit().foregroundStyle(colors.amount(amountColor))
                    Text(subtitle).font(MasterRowColors.detailFont).foregroundStyle(colors.secondary)
                    badge
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title).lineLimit(2)
                        Spacer(minLength: 8)
                        Text(amount).monospacedDigit().foregroundStyle(colors.amount(amountColor)).fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subtitle).font(MasterRowColors.detailFont).foregroundStyle(colors.secondary).lineLimit(1)
                        Spacer(minLength: 8)
                        badge
                    }
                }
            }
        }
        .font(.body)
        .foregroundStyle(colors.primary)
        #if os(macOS)
        .padding(.vertical, 3)
        #else
        .padding(.vertical, 6)
        #endif
        .accessibilityElement(children: .combine)
    }
}

/// Fondo de una fila maestro: la superficie de la columna o, en la elegida, una cápsula redondeada de Tinta con margen,
/// como la del canvas (radio 12 en el iPad; 6 en el Mac, como las listas de origen del sistema).
struct MasterRowBackground: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Palette.masterColumn
            if isSelected {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(Palette.brandFill)
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 1)
            }
        }
    }

    #if os(macOS)
    private static let radius: CGFloat = 6
    private static let inset: CGFloat = 6
    #else
    private static let radius: CGFloat = 12
    private static let inset: CGFloat = 8
    #endif
}

extension View {
    /// Fila de la columna maestro con su selección: la elegida, rellena de Tinta con todo el texto en blanco (decisión
    /// del usuario del 2-nov, como el canvas). Las filas leen `isMasterRowSelected` para cambiar sus colores.
    func masterRow(_ id: UUID, selection: UUID?) -> some View {
        let isSelected = id == selection
        return tag(id)
            .environment(\.isMasterRowSelected, isSelected)
            .listRowBackground(MasterRowBackground(isSelected: isSelected))
            .listRowSeparator(isSelected ? .hidden : .automatic)
            // Con teclado o trackpad, el sistema dibujaba encima su anillo de foco: cuadrado, sin las esquinas de la
            // fila rellena de Tinta y cortado por la derecha (iPad, 2-nov). La fila elegida ya se ve; las flechas del
            // teclado siguen moviendo la selección.
            .focusEffectDisabled()
    }
}
