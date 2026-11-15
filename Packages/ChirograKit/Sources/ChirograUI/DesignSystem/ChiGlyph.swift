import SwiftUI

// Generado desde `App/AppIcon.icon/Assets/chirogra-N-icono.svg` (icono χρ del 14-nov): si cambia el icono, volver a
// sacarlo de ese SVG en vez de retocarlo a mano. Lienzo de 1024 escalado al tamaño pedido. En el icono la χ va en
// blanco y la ρ en azafrán (`Palette.accent`), las dos rellenas y sin filo (`LogoMark`).

/// La χ del icono.
nonisolated struct ChiGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 1024, y: rect.minY + rect.height * y / 1024)
        }
        var path = Path()
        path.move(to: p(438.48, 750.94))
        path.addQuadCurve(to: p(405.62, 740.4), control: p(417.4, 750.94))
        path.addQuadCurve(to: p(389.5, 703.51), control: p(393.84, 729.86))
        path.addQuadCurve(to: p(384.54, 630.66), control: p(385.16, 677.16))
        path.addLine(to: p(383.92, 566.8))
        path.addLine(to: p(381.44, 566.8))
        path.addLine(to: p(241.32, 750.32))
        path.addLine(to: p(178.7, 750.32))
        path.addLine(to: p(178.7, 740.4))
        path.addLine(to: p(378.96, 515.34))
        path.addLine(to: p(378.34, 478.14))
        path.addQuadCurve(to: p(367.18, 397.85), control: p(377.72, 426.68))
        path.addQuadCurve(to: p(328.12, 369.02), control: p(356.64, 369.02))
        path.addQuadCurve(to: p(297.12, 377.39), control: p(308.28, 369.02))
        path.addQuadCurve(to: p(276.66, 396.3), control: p(285.96, 385.76))
        path.addLine(to: p(264.88, 387.62))
        path.addQuadCurve(to: p(287.2, 356), control: p(274.18, 370.26))
        path.addQuadCurve(to: p(315.72, 333.37), control: p(300.22, 341.74))
        path.addQuadCurve(to: p(347.34, 325), control: p(331.22, 325))
        path.addQuadCurve(to: p(382.06, 340.81), control: p(369.66, 325))
        path.addQuadCurve(to: p(399.73, 381.11), control: p(394.46, 356.62))
        path.addQuadCurve(to: p(406.24, 433.19), control: p(405, 405.6))
        path.addQuadCurve(to: p(407.48, 484.96), control: p(407.48, 460.78))
        path.addLine(to: p(409.34, 484.96))
        path.addLine(to: p(530.24, 330.58))
        path.addLine(to: p(593.48, 329.34))
        path.addLine(to: p(594.1, 337.4))
        path.addLine(to: p(411.2, 533.32))
        path.addLine(to: p(411.82, 554.4))
        path.addQuadCurve(to: p(418.95, 643.99), control: p(413.68, 611.44))
        path.addQuadCurve(to: p(434.14, 689.56), control: p(424.22, 676.54))
        path.addQuadCurve(to: p(458.94, 702.58), control: p(444.06, 702.58))
        path.addQuadCurve(to: p(484.05, 697.31), control: p(473.2, 702.58))
        path.addQuadCurve(to: p(504.82, 680.88), control: p(494.9, 692.04))
        path.addLine(to: p(515.36, 690.18))
        path.addQuadCurve(to: p(495.83, 721.49), control: p(507.3, 707.54))
        path.addQuadCurve(to: p(470.1, 743.19), control: p(484.36, 735.44))
        path.addQuadCurve(to: p(438.48, 750.94), control: p(455.84, 750.94))
        path.closeSubpath()
        return path
    }
}

/// La ρ del icono.
nonisolated struct RhoGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 1024, y: rect.minY + rect.height * y / 1024)
        }
        var path = Path()
        path.move(to: p(643.76, 745.4))
        path.addLine(to: p(595.4, 756.56))
        path.addLine(to: p(586.1, 754.7))
        path.addQuadCurve(to: p(587.34, 637.52), control: p(586.1, 692.7))
        path.addQuadCurve(to: p(589.2, 540.18), control: p(588.58, 582.34))
        path.addQuadCurve(to: p(608.11, 414.94), control: p(590.44, 462.68))
        path.addQuadCurve(to: p(658.02, 345.5), control: p(625.78, 367.2))
        path.addQuadCurve(to: p(734.28, 323.8), control: p(690.26, 323.8))
        path.addQuadCurve(to: p(788.84, 338.06), control: p(763.42, 323.8))
        path.addQuadCurve(to: p(829.76, 384.25), control: p(814.26, 352.32))
        path.addQuadCurve(to: p(845.26, 469.5), control: p(845.26, 416.18))
        path.addQuadCurve(to: p(830.38, 548.55), control: p(845.26, 512.28))
        path.addQuadCurve(to: p(786.67, 606.83), control: p(815.5, 584.82))
        path.addQuadCurve(to: p(715.68, 628.84), control: p(757.84, 628.84))
        path.addQuadCurve(to: p(675.69, 617.06), control: p(692.12, 628.84))
        path.addQuadCurve(to: p(648.72, 588.23), control: p(659.26, 605.28))
        path.addQuadCurve(to: p(630.74, 555.68), control: p(638.18, 571.18))
        path.addLine(to: p(626.4, 555.68))
        path.addQuadCurve(to: p(632.29, 631.01), control: p(629.5, 599.08))
        path.addQuadCurve(to: p(637.87, 689.6), control: p(635.08, 662.94))
        path.addQuadCurve(to: p(643.76, 745.4), control: p(640.66, 716.26))
        path.closeSubpath()
        path.move(to: p(715.06, 578))
        path.addQuadCurve(to: p(786.98, 550.72), control: p(757.84, 578))
        path.addQuadCurve(to: p(816.12, 470.74), control: p(816.12, 523.44))
        path.addQuadCurve(to: p(803.41, 413.08), control: p(816.12, 432.92))
        path.addQuadCurve(to: p(770.86, 385.8), control: p(790.7, 393.24))
        path.addQuadCurve(to: p(730.56, 378.36), control: p(751.02, 378.36))
        path.addQuadCurve(to: p(680.34, 388.9), control: p(703.28, 378.36))
        path.addQuadCurve(to: p(643.45, 421.76), control: p(657.4, 399.44))
        path.addQuadCurve(to: p(629.5, 480.04), control: p(629.5, 444.08))
        path.addQuadCurve(to: p(652.75, 549.79), control: p(629.5, 521.58))
        path.addQuadCurve(to: p(715.06, 578), control: p(676, 578))
        path.closeSubpath()
        return path
    }
}
