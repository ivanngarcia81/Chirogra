import SwiftUI

// Sacado de las capas de `App/AppIcon.icon/Assets` (icono «Ecuación» del 27-nov): la ecuación contable en tres bloques
// redondeados sobre azul marino. A la izquierda, alto, el de los activos (azafrán); a la derecha, arriba, el de los
// pasivos (blanco) y abajo el del capital (gris pizarra): activos = pasivos + capital. Lienzo de 1024 escalado al tamaño
// pedido, `rect` con radio 56 como en los SVG. Si cambia el icono, volver a sacarlo de esos SVG en vez de retocarlo a mano.
// Antes: los lápices en χ con la ρ (21-nov, ahora solo el asistente, `AssistantGlyph`), la χρ de letra (14-nov) y la
// χ cursiva (12-nov).

/// Un bloque del logotipo, de izquierda a derecha y de arriba abajo.
nonisolated struct LogoGlyph: Shape {
    enum Part: CaseIterable {
        /// `03-bloque-izquierdo.svg`: activos.
        case assets
        /// `04-bloque-derecho-superior.svg`: pasivos.
        case liabilities
        /// `05-bloque-derecho-inferior.svg`: capital.
        case equity
    }

    var part: Part

    /// Radio de las esquinas en el lienzo de 1024.
    static let cornerRadius: CGFloat = 56

    func path(in rect: CGRect) -> Path {
        let scale = CGSize(width: rect.width / 1024, height: rect.height / 1024)
        let box = Self.box(part)
        let placed = CGRect(x: rect.minX + box.minX * scale.width, y: rect.minY + box.minY * scale.height,
                            width: box.width * scale.width, height: box.height * scale.height)
        return RoundedRectangle(cornerRadius: Self.cornerRadius * scale.width, style: .circular).path(in: placed)
    }

    private static func box(_ part: Part) -> CGRect {
        switch part {
        case .assets: CGRect(x: 224, y: 232, width: 260, height: 560)
        case .liabilities: CGRect(x: 540, y: 232, width: 260, height: 220)
        case .equity: CGRect(x: 540, y: 480, width: 260, height: 312)
        }
    }
}

extension LogoGlyph.Part {
    /// Color del bloque en el icono.
    var color: Color {
        switch self {
        case .assets: Palette.logoAssets
        case .liabilities: Palette.logoLiabilities
        case .equity: Palette.logoEquity
        }
    }
}
