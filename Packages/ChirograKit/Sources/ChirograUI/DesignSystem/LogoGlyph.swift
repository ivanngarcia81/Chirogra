import SwiftUI

// Sacado de las capas de `App/AppIcon.icon/Assets` (icono «chirogra pencils» del 21-nov: un lapicero y un lápiz que se
// cruzan en χ y una ρ azafrán con brillo de lupa). Lienzo de 1024 escalado al tamaño pedido; cada pieza es una forma
// rellena (la ρ y el brillo son trazos del SVG convertidos en contorno) para que `LogoMark` la pinte y la bienvenida
// dibuje su contorno antes de rellenarla. Si cambia el icono, volver a sacarlo de esos SVG en vez de retocarlo a mano.
// Antes: la χρ de letra (14-nov) y la χ cursiva sola (12-nov), en `ChiGlyph`/`RhoGlyph`.

/// Una pieza del logotipo, de abajo arriba como las capas del icono.
nonisolated struct LogoGlyph: Shape {
    enum Part: CaseIterable {
        /// `3-lapicero.svg`: capuchón, cuerpo y punta blancos.
        case penBody
        /// El cono gris del lapicero.
        case penCone
        /// La bolita de la punta del lapicero.
        case penBall
        /// `5-lapiz.svg`: cuerpo blanco con la goma redonda arriba.
        case pencilBody
        /// La virola y la punta grises del lápiz.
        case pencilTip
        /// `7-rho.svg`: palo y círculo con trazo de 46.
        case rho
        /// `8-brillo.svg`: arco y punto dentro de la ρ.
        case shine
    }

    var part: Part

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 1024
        let toRect = CGAffineTransform(scaleX: scale, y: rect.height / 1024)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        switch part {
        case .penBody, .penCone, .penBall:
            return Self.pen(part).applying(Self.placed(degrees: -35)).applying(toRect)
        case .pencilBody, .pencilTip:
            return Self.pencil(part).applying(Self.placed(degrees: 35)).applying(toRect)
        case .rho:
            var line = Path()
            line.move(to: CGPoint(x: 587, y: 425))
            line.addLine(to: CGPoint(x: 587, y: 718))
            line.addEllipse(in: CGRect(x: 709 - 122, y: 425 - 122, width: 244, height: 244))
            return line.applying(toRect).strokedPath(StrokeStyle(lineWidth: 46 * scale, lineCap: .round))
        case .shine:
            // Arco de radio 64 con centro (708.55, 424.55), de −164.08° a −96.77° (el `A64 64 0 0 1` del SVG).
            var arc = Path()
            let center = CGPoint(x: 708.55, y: 424.55)
            let steps = 24
            for i in 0...steps {
                let angle = (-164.08 + (-96.77 + 164.08) * Double(i) / Double(steps)) * .pi / 180
                let point = CGPoint(x: center.x + 64 * cos(angle), y: center.y + 64 * sin(angle))
                if i == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
            }
            var shine = arc.applying(toRect).strokedPath(StrokeStyle(lineWidth: 15 * scale, lineCap: .round, lineJoin: .round))
            shine.addEllipse(in: CGRect(x: 755 - 9, y: 471 - 9, width: 18, height: 18).applying(toRect))
            return shine
        }
    }

    /// El `translate(352 520) rotate(…)` de los dos lápices.
    private static func placed(degrees: Double) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(CGAffineTransform(translationX: 352, y: 520))
    }

    private static func pen(_ part: Part) -> Path {
        var path = Path()
        switch part {
        case .penBody:
            path.move(to: CGPoint(x: -28, y: -205))
            path.addLine(to: CGPoint(x: -28, y: -248))
            path.addQuadCurve(to: CGPoint(x: -6, y: -270), control: CGPoint(x: -28, y: -270))
            path.addLine(to: CGPoint(x: 6, y: -270))
            path.addQuadCurve(to: CGPoint(x: 28, y: -248), control: CGPoint(x: 28, y: -270))
            path.addLine(to: CGPoint(x: 28, y: -205))
            path.closeSubpath()
            path.addRect(CGRect(x: -28, y: -185, width: 56, height: 381))
            path.move(to: CGPoint(x: -10, y: 236))
            path.addLine(to: CGPoint(x: 10, y: 236))
            path.addLine(to: CGPoint(x: 6, y: 256))
            path.addLine(to: CGPoint(x: 6, y: 264))
            path.addQuadCurve(to: CGPoint(x: 0, y: 270), control: CGPoint(x: 6, y: 270))
            path.addQuadCurve(to: CGPoint(x: -6, y: 264), control: CGPoint(x: -6, y: 270))
            path.addLine(to: CGPoint(x: -6, y: 256))
            path.closeSubpath()
        case .penCone:
            path.move(to: CGPoint(x: -28, y: 196))
            path.addLine(to: CGPoint(x: 28, y: 196))
            path.addLine(to: CGPoint(x: 15, y: 236))
            path.addLine(to: CGPoint(x: -15, y: 236))
            path.closeSubpath()
        default:
            path.addEllipse(in: CGRect(x: -8, y: 255, width: 16, height: 16))
        }
        return path
    }

    private static func pencil(_ part: Part) -> Path {
        if part == .pencilBody {
            return UnevenRoundedRectangle(topLeadingRadius: 29, topTrailingRadius: 29)
                .path(in: CGRect(x: -29, y: -270, width: 58, height: 423.5))
        }
        var path = Path()
        path.addRect(CGRect(x: -29, y: 162.5, width: 58, height: 21.5))
        path.move(to: CGPoint(x: -29, y: 184))
        path.addLine(to: CGPoint(x: 29, y: 184))
        path.addLine(to: CGPoint(x: 3, y: 266))
        path.addQuadCurve(to: CGPoint(x: -3, y: 266), control: CGPoint(x: 0, y: 271))
        path.closeSubpath()
        return path
    }
}

extension LogoGlyph.Part {
    /// Color de la pieza en el icono.
    var color: Color {
        switch self {
        case .penBody, .pencilBody: Palette.logoMark
        case .penCone, .pencilTip: Palette.logoTip
        case .penBall: Palette.logoBall
        case .rho, .shine: Palette.logoRho
        }
    }
}
