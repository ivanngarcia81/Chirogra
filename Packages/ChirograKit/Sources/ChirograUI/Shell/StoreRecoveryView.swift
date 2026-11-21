import ChirograData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pantalla de recuperación cuando la base de datos no se abre ni con iCloud ni en local (revisión externa del
/// 21-nov: antes la app se cerraba con `fatalError` cada vez que se abría). No borra nada: deja intentarlo otra vez,
/// mandar el detalle a soporte y, como último recurso, apartar la base a una carpeta (`ChirograStore.setAsideStore`) y
/// abrir una nueva; con iCloud los libros vuelven a bajar, sin iCloud se restaura una copia `.chirogra`.
public struct StoreRecoveryView: View {
    let errorText: String
    let retry: () -> Void
    let setAside: () throws -> URL

    @State private var confirmingSetAside = false
    @State private var setAsideError: String?
    @State private var copied = false

    public init(errorText: String, retry: @escaping () -> Void, setAside: @escaping () throws -> URL) {
        self.errorText = errorText
        self.retry = retry
        self.setAside = setAside
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    LogoMark(size: 34)
                    Text("Chirogra").font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("No se pudieron abrir tus libros")
                        .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Tus datos no se han borrado. Cierra otras apps y prueba otra vez; si sigue fallando, escríbenos con el detalle de abajo y te ayudamos a recuperarlos.")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Intentar otra vez", action: retry)
                        .buttonStyle(.primaryCompact)
                    if let mail = supportMail {
                        Link(destination: mail) {
                            Label("Escribir a soporte", systemImage: "envelope")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Detalle para soporte").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
                    Text(errorText)
                        .font(.footnote.monospaced()).foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(copied ? String(localized: "Copiado") : String(localized: "Copiar el detalle"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                        copy(errorText)
                        copied = true
                    }
                    .font(.footnote)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Empezar sin esta base").font(.headline).foregroundStyle(Palette.ink)
                    Text("Si no se abre después de intentarlo, puedes apartarla y abrir una nueva. No se borra: queda guardada en una carpeta de este aparato por si soporte la necesita. Con iCloud, tus libros vuelven a bajar solos; sin iCloud, restaura tu última copia .chirogra en Ajustes › iCloud y copias.")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Apartar la base y abrir una nueva…") { confirmingSetAside = true }
                        .buttonStyle(.secondary)
                    if let setAsideError {
                        Text(setAsideError).font(.footnote).foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .confirmationDialog("¿Apartar la base que no se abre?", isPresented: $confirmingSetAside, titleVisibility: .visible) {
            Button("Apartar y abrir una nueva") {
                do {
                    _ = try setAside()
                    setAsideError = nil
                } catch {
                    setAsideError = String(localized: "No se pudo apartar: \(error.localizedDescription)")
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La base se mueve a una carpeta de este aparato, sin borrarse, y Chirogra abre una vacía. Con iCloud, tus libros vuelven a bajar.")
        }
    }

    /// Correo a soporte con el detalle ya escrito.
    private var supportMail: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "soporte@chirogra.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Chirogra no abre mis libros")),
            URLQueryItem(name: "body", value: "\n\n---\n\(errorText)"),
        ]
        return components.url
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    StoreRecoveryView(errorText: "SwiftDataError(_error: SwiftData.SwiftDataError._Error.loadIssueModelContainer)",
                      retry: {}, setAside: { URL(filePath: "/tmp") })
}
