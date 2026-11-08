#if DEBUG
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Argumentos de QA del escaneo (solo Debug): `-qa.escanear prueba` abre «Nuevo gasto» con un recibo de prueba hecho
/// aquí (el del canvas `ReciboCamara`, The Home Depot, $284.17); `-qa.escanear <ruta>` con una foto o un PDF (ruta
/// dentro del contenedor de la app o, en el simulador, del Mac). `-qa.reciboIA no` lee solo con las reglas.
enum ReceiptQA {
    static var argument: String? { UserDefaults.standard.string(forKey: "qa.escanear") }

    /// Deja constancia de la lectura en los ajustes de la app (`qa.recibo.resultado`), para leerla desde fuera con
    /// `defaults read` en la copia de prueba.
    static func note(_ text: String) {
        let defaults = UserDefaults.standard
        let previous = defaults.stringArray(forKey: "qa.recibo.resultado") ?? []
        defaults.set(Array((previous + [text]).suffix(10)), forKey: "qa.recibo.resultado")
    }

    /// Solo la primera vez (el editor se vuelve a crear con «Guardar y nuevo»).
    @MainActor private static var used = false

    @MainActor
    static func launchReceipt() -> ReceiptFile? {
        guard let argument, !used else { return nil }
        used = true
        if argument == "prueba" || argument == "1" {
            return samplePNG().map { ReceiptFile(data: $0, name: "recibo-prueba.png", type: .png) }
        }
        let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
        return try? ReceiptFile(url: url, fallback: .image)
    }

    /// Un recibo de ferretería como el del canvas, a 3×, para que Vision lo lea como una foto.
    @MainActor
    static func samplePNG() -> Data? {
        let rows: [(String, String)] = [("TORNILLO 2\" X100", "12.98"), ("BISAGRA OCULTA X6", "38.40"),
                                        ("TABLERO MDF 18MM", "146.00"), ("BARNIZ MATE 1GAL", "65.13")]
        let content = VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: "THE HOME DEPOT").font(.system(size: 22, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity)
            Text(verbatim: "#4410 AUSTIN, TX").frame(maxWidth: .infinity)
            Text(verbatim: "10/29/2026 14:32").frame(maxWidth: .infinity)
            Divider().overlay(Color.gray)
            ForEach(rows, id: \.0) { row in
                HStack { Text(verbatim: row.0); Spacer(); Text(verbatim: row.1) }
            }
            Divider().overlay(Color.gray)
            HStack { Text(verbatim: "SUBTOTAL"); Spacer(); Text(verbatim: "262.51") }
            HStack { Text(verbatim: "TAX 8.25%"); Spacer(); Text(verbatim: "21.66") }
            HStack { Text(verbatim: "TOTAL"); Spacer(); Text(verbatim: "284.17") }.font(.system(size: 18, weight: .bold, design: .monospaced))
            Text(verbatim: "VISA ****1177")
        }
        .font(.system(size: 15, design: .monospaced))
        .padding(28)
        .frame(width: 380)
        .foregroundStyle(Color.black)
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: image).pngData()
        #else
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #endif
    }
}
#endif
