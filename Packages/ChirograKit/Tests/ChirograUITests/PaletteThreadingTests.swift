import AppKit
import CoreTransferable
import SwiftUI
import Testing
@testable import ChirograUI

/// SwiftUI resuelve los colores dinámicos en hilos de fondo (p. ej. al dibujar Reportes › Por pagar).
/// Si el cierre que elige claro/oscuro quedara aislado al MainActor, Swift 6 abortaría la app.
@Suite("Colores fuera del hilo principal")
struct PaletteThreadingTests {
    @Test func resolvesOffMainActor() async {
        let color = await MainActor.run { NSColor(Palette.brand) }
        let components = await Task.detached {
            var rgb: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                let resolved = color.usingColorSpace(.sRGB)!
                rgb = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
            }
            return rgb
        }.value
        #expect(Int((components.0 * 255).rounded()) == 0x8F)
        #expect(Int((components.2 * 255).rounded()) == 0xFF)
    }
}

/// La hoja de compartir pide los datos de los archivos (`Transferable`) desde un hilo de fondo.
@Suite("Archivos compartidos fuera del hilo principal")
struct TransferableThreadingTests {
    @Test func csvExportsOffMainActor() async throws {
        let file = CSVFile(name: "Antigüedad", text: "a,b\n")
        let data = try await Task.detached { try await file.exported(as: .commaSeparatedText) }.value
        #expect(String(decoding: data, as: UTF8.self) == "a,b\n")
    }

    @Test func attachmentExportsOffMainActor() async throws {
        let file = AttachmentFile(data: Data([1, 2, 3]), filename: "recibo.jpg", contentType: "image/jpeg")
        let data = try await Task.detached { try await file.exported(as: .data) }.value
        #expect(data == Data([1, 2, 3]))
    }
}
