import CoreGraphics
import Foundation
import Synchronization
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// El texto de un recibo (foto o PDF), leído en el aparato con Vision: renglones en orden de lectura, con lo que está a
/// la misma altura del papel unido («TOTAL     284.17»), que es como lo esperan las reglas (`ReceiptRules`). Un PDF con
/// texto (recibo digital) se lee tal cual; uno escaneado se pasa a imagen y se lee como una foto. Nada sale del aparato.
nonisolated enum ReceiptTextRecognizer {
    enum Failure: Error { case unreadable }

    /// Como mucho tantas páginas de un PDF (un recibo largo; más ya no es un recibo).
    static let maxPages = 3

    /// La primera lectura tras instalar la app tarda (el sistema prepara el modelo de texto para el aparato, casi un
    /// minuto en el Mac de pruebas); después, unos segundos. Al abrir «Nuevo gasto» se lee una imagen pequeña para
    /// adelantar ese trabajo mientras el usuario elige el recibo. Una vez por sesión.
    static func warmUp() {
        guard !warmedUp.withLock({ let was = $0; $0 = true; return was }) else { return }
        Task.detached(priority: .utility) {
            guard let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 8, y: 12, width: 48, height: 8))
            guard let image = context.makeImage() else { return }
            _ = try? await lines(of: image)
        }
    }
    private static let warmedUp = Mutex(false)

    static func lines(of data: Data, type: UTType) async throws -> [String] {
        if type.conforms(to: .pdf) { return try await pdfLines(data) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:))
        return try await lines(of: image, orientation: orientation)
    }

    static func lines(of image: CGImage, orientation: CGImagePropertyOrientation? = nil) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "es-ES")]
        let observations = try await request.perform(on: image, orientation: orientation)
        return rows(from: observations.compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox.cgRect) }
        })
    }

    /// Junta en un renglón los trozos que están a la misma altura (el artículo a la izquierda y su precio a la derecha)
    /// y ordena de arriba abajo. Las cajas de Vision van normalizadas con el origen abajo a la izquierda.
    static func rows(from pieces: [(text: String, box: CGRect)]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(text: String, box: CGRect)]] = []
        for piece in sorted {
            if let last = rows.last?.last, abs(last.box.midY - piece.box.midY) < max(last.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "   ") }
    }

    private static func pdfLines(_ data: Data) async throws -> [String] {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw Failure.unreadable }
        let count = min(document.pageCount, maxPages)
        // Recibo digital: el texto ya está en el PDF.
        let text = (0..<count).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        let embedded = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if embedded.count >= 3 { return embedded }
        // Escaneado: cada página como imagen.
        var lines: [String] = []
        for index in 0..<count {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            lines += try await self.lines(of: image)
        }
        return lines
    }

    /// Una página del PDF a unos 200 ppp (suficiente para Vision sin gastar memoria).
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(200.0 / 72.0, 2400 / max(bounds.width, bounds.height, 1))
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        if let pageRef = page.pageRef { context.drawPDFPage(pageRef) }
        return context.makeImage()
    }
}
