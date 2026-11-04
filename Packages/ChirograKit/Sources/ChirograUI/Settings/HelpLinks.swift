import SwiftUI

extension ChirograLinks {
    /// Guía de uso en chirogra.com (`sitio/guia`, `sitio/guide`): en español o en inglés según el idioma de la app.
    static var guide: URL {
        let spanish = Bundle.main.preferredLocalizations.first?.hasPrefix("es") ?? true
        return URL(string: spanish ? "https://chirogra.com/guia/" : "https://chirogra.com/guide/")!
    }
}

/// Fila «Guía de uso» de las listas de Ajustes (iPhone, «Más» y la lista estrecha): abre la guía en el navegador.
struct GuideLinkRow: View {
    var body: some View {
        Link(destination: ChirograLinks.guide) {
            HStack(spacing: 12) {
                IconTile(systemImage: "questionmark.circle", foreground: Palette.blue)
                Text("Guía de uso").foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(Text("Se abre en el navegador"))
    }
}

/// Menú «Ayuda» de la app (en el Mac, la barra de menús; en el iPad, el menú del teclado): la guía de uso en
/// chirogra.com, con ⌘? como las demás apps.
public struct ChirograHelpCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Guía de uso de Chirogra", destination: ChirograLinks.guide)
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
