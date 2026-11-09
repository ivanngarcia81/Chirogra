import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import VisionKit
#endif

/// Cámara de documentos del sistema (VisionKit, canvas `ReciboCamara`): encuadra el recibo sola, endereza y recorta.
/// Solo en iPhone y iPad con cámara (`isAvailable`); en el Mac y en el simulador se elige una foto o un PDF.
/// Una página sale como JPEG; varias, como un PDF.
enum DocumentScanner {
    static var isAvailable: Bool {
        #if os(iOS)
        VNDocumentCameraViewController.isSupported
        #else
        false
        #endif
    }
}

#if os(iOS)
struct DocumentScannerView: UIViewControllerRepresentable {
    /// `nil` si se canceló o falló.
    let onFinish: (ReceiptFile?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (ReceiptFile?) -> Void
        init(onFinish: @escaping (ReceiptFile?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(Self.file(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }

        static func file(from pages: [UIImage]) -> ReceiptFile? {
            guard let first = pages.first else { return nil }
            if pages.count == 1 {
                return first.jpegData(compressionQuality: 0.8).map { ReceiptFile(data: $0, name: String(localized: "Recibo escaneado.jpg"), type: .jpeg) }
            }
            // Varias páginas: un PDF, cada una a su tamaño (a 72 ppp del ancho de una carta).
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            let data = renderer.pdfData { context in
                for page in pages {
                    let scale = 612 / max(page.size.width, 1)
                    let bounds = CGRect(x: 0, y: 0, width: 612, height: page.size.height * scale)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    page.draw(in: bounds)
                }
            }
            return ReceiptFile(data: data, name: String(localized: "Recibo escaneado.pdf"), type: .pdf)
        }
    }
}
#endif
