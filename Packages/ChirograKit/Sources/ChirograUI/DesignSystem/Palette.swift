import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tokens de color del canvas de Claude Design (DISEÑO §7.3), con variante clara y oscura.
/// Las vistas usan solo estos tokens, nunca valores sueltos.
public enum Palette {
    /// Tinta: color principal.
    public static let brand = Color(light: 0x3A3FD1, dark: 0x8F93FF)
    public static let brandWash = Color(light: 0xE7E8FB, dark: 0x252960)
    public static let onBrand = Color(light: 0xFFFFFF, dark: 0x0D0E18)
    /// Azafrán: avisos, insignias, detalle del logotipo.
    public static let accent = Color(light: 0xF2B33D, dark: 0xF2B33D)
    public static let onAccent = Color(light: 0x2A1C00, dark: 0x2A1C00)
    /// Cobre: salidas de dinero.
    public static let outflow = Color(light: 0xB4500F, dark: 0xFF9F66)
    public static let outflowWash = Color(light: 0xFCEBDD, dark: 0x3A2416)
    public static let expenseBar = Color(light: 0xE58A4E, dark: 0xE58A4E)

    public static let background = Color(light: 0xF4F5F9, dark: 0x0D0E18)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x171928)
    public static let surface2 = Color(light: 0xECEEF5, dark: 0x212438)
    public static let sidebar = Color(light: 0xE9EBF3, dark: 0x12131F)
    public static let separator = Color(light: 0xE1E4EE, dark: 0x2B2F47)

    public static let ink = Color(light: 0x12142B, dark: 0xF1F2F8)
    public static let ink2 = Color(light: 0x4F546E, dark: 0xB6BAD0)
    public static let ink3 = Color(light: 0x666B88, dark: 0x959BB8)

    public static let positive = Color(light: 0x17704A, dark: 0x52C893)
    public static let positiveWash = Color(light: 0xDDF3E8, dark: 0x14301F)
    public static let warning = Color(light: 0x8A5A00, dark: 0xF2C065)
    public static let warningWash = Color(light: 0xFBF0D6, dark: 0x33280F)
    public static let negative = Color(light: 0xB42833, dark: 0xFF8088)
    public static let negativeWash = Color(light: 0xFBE3E5, dark: 0x3A1A1E)
    public static let info = Color(light: 0x0E6A86, dark: 0x6FD0EE)
    public static let infoWash = Color(light: 0xDCEFF5, dark: 0x123039)
}

/// Medidas del canvas: márgenes, separaciones y radios.
public enum Metrics {
    public static let gutter: CGFloat = 16
    public static let cardSpacing: CGFloat = 12
    public static let cardPadding: CGFloat = 16
    public static let cardRadius: CGFloat = 20
    public static let heroRadius: CGFloat = 22
    public static let buttonRadius: CGFloat = 14
    public static let buttonHeight: CGFloat = 48
    public static let fieldRadius: CGFloat = 12
    public static let iconTile: CGFloat = 40
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif
