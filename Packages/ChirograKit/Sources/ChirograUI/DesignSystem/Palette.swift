import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colores de la app según el tablero «Sistema nativo» del canvas (`Main.dc.html`, docs/REDISEÑO-NATIVO.md §1):
/// un solo color de acento, Tinta (`AccentColor`, el `tint` de toda la app), y todo lo demás con los colores
/// semánticos del sistema (label, secondaryLabel, systemGroupedBackground, separator, rellenos y colores de sistema),
/// así el modo oscuro y «Aumentar contraste» salen del sistema. Las vistas usan solo estos tokens, nunca valores sueltos.
///
/// Los nombres antiguos (`brandWash`, `ink3`, `outflow`, `…Wash`) se conservan para que las pantallas sigan compilando
/// mientras se rehacen; apuntan al color del canvas más cercano.
public enum Palette {
    // MARK: Acento (Tinta)

    /// Tinta para texto, iconos, enlaces, gráficas de ingresos y `tint` (canvas `--tint`: #3A3FD1 · #9A9EFF).
    public static let brand = Color(light: 0x3A3FD1, dark: 0x9A9EFF)
    /// Relleno de Tinta bajo texto blanco: botón primario, fila elegida del Mac y del iPad, acción destacada
    /// (canvas `--tintFill`: #3A3FD1 · #5458E6; con #9A9EFF el blanco no llegaría a AA en oscuro).
    public static let brandFill = Color(light: 0x3A3FD1, dark: 0x5458E6)
    /// Texto sobre `brandFill`.
    public static let onBrandFill = Color.white
    /// Tinta tenue (canvas `--tintw`): selección suave, fondos de iconos.
    public static let brandWash = Color(light: 0x3A3FD1, lightAlpha: 0.12, dark: 0x9A9EFF, darkAlpha: 0.18)
    /// Texto sobre `brand` (solo tarjetas antiguas rellenas de marca: el canvas actual ya no las usa).
    public static let onBrand = Color(light: 0xFFFFFF, dark: 0x0D0E18)

    /// Azafrán: solo el punto del logotipo.
    public static let accent = Color(light: 0xF2B33D, dark: 0xF2B33D)
    public static let onAccent = Color(light: 0x2A1C00, dark: 0x2A1C00)

    // MARK: Significados (Main · «Color de acento y colores del sistema»)

    /// Ingresos en gráficas: el acento.
    public static let income = brand
    /// Gastos en gráficas y categorías: systemOrange.
    public static let expense = orange
    /// Barras de gastos de las gráficas.
    public static let expenseBar = orange
    /// Icono de cuenta bancaria: systemBlue.
    public static let bankAccount = blue
    /// Icono de tarjeta de crédito: systemIndigo.
    public static let creditCard = indigo
    /// Salidas de dinero: el canvas las escribe en `label` (solo las entradas van en verde).
    public static let outflow = ink
    public static let outflowWash = surface2

    // MARK: Fondos y superficies

    #if canImport(UIKit)
    /// Fondo de pantalla: `systemGroupedBackground` (#F2F2F7 · #000000).
    public static let background = Color(uiColor: .systemGroupedBackground)
    /// Celdas y tarjetas sobre el fondo: `secondarySystemGroupedBackground` (#FFFFFF · #1C1C1E).
    public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Relleno de controles: buscador, segmentado, botón secundario (canvas `--fill`).
    public static let surface2 = Color(uiColor: .tertiarySystemFill)
    /// Relleno más marcado (canvas `--fill2`): interruptor apagado, resto de una barra.
    public static let fill2 = Color(uiColor: .systemFill)
    public static let separator = Color(uiColor: .separator)
    /// Barra lateral del iPad: panel blanco del canvas (`Sidebar`, device=ipad).
    public static let sidebar = Color(uiColor: .secondarySystemGroupedBackground)
    public static let ink = Color(uiColor: .label)
    #else
    /// Fondo de la ventana del Mac (canvas `--win`: #FFFFFF · #1E1E1E).
    public static let background = Color(nsColor: .controlBackgroundColor)
    /// Cajas del Mac (canvas `--row2`, con borde de `separator`): tarjetas de cifras, gráficas, fila alterna.
    public static let surface = Color(light: 0xF5F5F7, dark: 0x262628)
    public static let surface2 = Color(nsColor: .tertiarySystemFill)
    public static let fill2 = Color(nsColor: .systemFill)
    public static let separator = Color(nsColor: .separatorColor)
    /// En el Mac la barra lateral es el material del sistema: sin fondo propio.
    public static let sidebar = Color.clear
    public static let ink = Color(nsColor: .labelColor)
    #endif

    // MARK: Texto

    /// Texto secundario (canvas `--ink2`: #6C6C70 · #98989F). Es `secondaryLabel` opaco: cumple AA (≥ 4.5:1) sobre el
    /// fondo y las celdas en claro y en oscuro; el `secondaryLabel` translúcido del sistema no llega en texto pequeño.
    public static let ink2 = Color(light: 0x6C6C70, dark: 0x98989F)
    /// Igual que `ink2`: el canvas solo tiene dos niveles de texto.
    public static let ink3 = ink2
    /// Chevron y anillos decorativos (canvas `--chev`), nunca texto.
    public static let chevron = Color(light: 0xBABABF, dark: 0x5C5C61)

    // MARK: Estados (texto AA, canvas `--ok`, `--bad`, `--warn`, `--info`)

    /// «Pagada», al día, variaciones favorables, entradas de dinero.
    public static let positive = Color(light: 0x1F7A35, dark: 0x30D158)
    /// «Vencida», excluir, acciones destructivas.
    public static let negative = Color(light: 0xD70015, dark: 0xFF6961)
    /// «Pago parcial», «por revisar».
    public static let warning = Color(light: 0xB54700, dark: 0xFF9F0A)
    /// «Vista», información.
    public static let info = Color(light: 0x0064A0, dark: 0x64D2FF)
    /// Fondos tenues de estado (avisos de error, celdas marcadas). El canvas ya no pone los estados en cápsulas.
    public static let positiveWash = green.opacity(0.14)
    public static let negativeWash = red.opacity(0.12)
    public static let warningWash = orange.opacity(0.14)
    public static let infoWash = teal.opacity(0.14)

    // MARK: Colores del sistema (puntos de estado, iconos de fila tipo Ajustes, categorías)

    public static let green = Color.green
    public static let red = Color.red
    public static let orange = Color.orange
    public static let yellow = Color.yellow
    public static let blue = Color.blue
    public static let teal = Color.teal
    public static let indigo = Color.indigo
    public static let purple = Color.purple
    public static let pink = Color.pink
    public static let gray = Color.gray

    /// Monograma de contacto (Contactos): degradado gris con iniciales blancas.
    public static let monogram = LinearGradient(colors: [Color(light: 0xA3A3A8, dark: 0xA3A3A8), Color(light: 0x86868B, dark: 0x86868B)],
                                                startPoint: .top, endPoint: .bottom)

    /// Logotipo: siempre Tinta clara, «C» blanca y punto azafrán (canvas `Main`, icono de la cabecera).
    public static let logoFill = Color(light: 0x3A3FD1, dark: 0x3A3FD1)
    public static let logoMark = Color.white
}

/// Medidas del canvas: márgenes, separaciones y radios.
public enum Metrics {
    #if os(macOS)
    /// Margen del contenido del Mac (canvas: 20 pt).
    public static let gutter: CGFloat = 20
    #else
    /// Margen lateral de iPhone e iPad: 16 pt; los títulos de sección van a 16 pt más (32 desde el borde).
    public static let gutter: CGFloat = 16
    #endif
    public static let cardSpacing: CGFloat = 12
    public static let cardPadding: CGFloat = 16
    #if os(macOS)
    /// Cajas del Mac: radio 12 (tablas: 8).
    public static let cardRadius: CGFloat = 12
    public static let tableRadius: CGFloat = 8
    #else
    /// Grupos y tarjetas de iPhone e iPad: radio 24, como las listas agrupadas de iOS 26.
    public static let cardRadius: CGFloat = 24
    public static let tableRadius: CGFloat = 24
    #endif
    public static let heroRadius: CGFloat = cardRadius
    #if os(macOS)
    /// En el Mac, botones, filas y chips con la densidad de sus controles (canvas: botones de 28, filas de 28,
    /// cabeceras de 26): con 44 pt el Plan de cuentas mostraba la mitad de filas y la app parecía de iPhone.
    public static let buttonHeight: CGFloat = 28
    public static let target: CGFloat = 28
    /// Icono de fila del Mac (canvas `MacInicio`, Cuentas): 22 pt, radio 6.
    public static let iconTile: CGFloat = 22
    /// Monograma de fila del Mac.
    public static let avatar: CGFloat = 28
    public static let fieldRadius: CGFloat = 7
    #else
    /// Botón de acción: cápsula de 50 pt (canvas «Enviar factura»).
    public static let buttonHeight: CGFloat = 50
    /// Área táctil mínima de iPhone e iPad: 44 pt.
    public static let target: CGFloat = 44
    /// Icono de fila tipo Ajustes: 30 pt, radio 8.
    public static let iconTile: CGFloat = 30
    /// Monograma de cliente o proveedor en una fila: 40 pt.
    public static let avatar: CGFloat = 40
    /// Buscador y campos con fondo: radio 12.
    public static let fieldRadius: CGFloat = 12
    #endif
    /// Los botones son cápsulas: el radio es la mitad del alto.
    public static let buttonRadius: CGFloat = buttonHeight / 2
    /// Alto mínimo de una fila de dos líneas (canvas: 60 pt en iPhone e iPad).
    #if os(macOS)
    public static let rowHeight: CGFloat = 28
    #else
    public static let rowHeight: CGFloat = 60
    #endif
}

extension Color {
    /// `nonisolated` y cierre `@Sendable`: SwiftUI y UIKit/AppKit resuelven el color en hilos de fondo.
    /// Si el cierre heredara el MainActor (aislamiento por defecto del módulo), Swift 6 abortaría la app.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    /// Igual, con transparencia (canvas `--tintw`).
    nonisolated init(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(rgb: dark, alpha: darkAlpha) : NSColor(rgb: light, alpha: lightAlpha)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#endif
