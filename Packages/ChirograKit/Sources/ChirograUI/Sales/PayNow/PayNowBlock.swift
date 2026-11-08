import ChirograCore
import ChirograData
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - «Pagar ahora» en la factura (cobro en línea, paso 1, CONTEXTO «Cobro en línea»)
//
// Sin servidor: la empresa pega su propio enlace de pago (Stripe Payment Link, Square, PayPal.me…) y/o instrucciones
// (Zelle, transferencia) en Ajustes › Cobro en línea. La factura en PDF lleva un recuadro con «Pagar ahora» (enlace
// que se puede pulsar en el PDF), un código QR con el mismo enlace y las instrucciones; el correo, el enlace y las
// instrucciones en el texto. **El cobro se sigue registrando a mano** («Registrar pago»).

/// Qué se imprime en el recuadro de pago de una factura.
struct PayNowInfo: Equatable {
    /// El enlace ya con el saldo, el número y el cliente (`PaymentLinkTemplate`); `nil` si solo hay instrucciones.
    var url: URL?
    var instructions: String

    var isEmpty: Bool { url == nil && instructions.isEmpty }

    /// El recuadro de una factura: solo con «Mostrar “Pagar ahora”» y saldo pendiente. Un borrador lo lleva con su
    /// total (así se ve en la vista previa antes de emitirla).
    @MainActor
    static func forInvoice(_ invoice: Invoice, amount: Int64) -> PayNowInfo? {
        guard let context = invoice.modelContext, invoice.status != .void else { return nil }
        let books = Bookkeeper(context: context, companyID: invoice.companyID)
        guard let company = try? books.company(), company.showPayNowOnInvoice else { return nil }
        let url: URL?
        if invoice.status == .draft {
            url = company.paymentLinkURL.isEmpty || amount <= 0 ? nil
                : PaymentLinkTemplate.url(company.paymentLinkURL, amount: amount, number: invoice.number,
                                          customer: invoice.customer?.name ?? "")
        } else {
            guard invoice.isOpen, invoice.balanceDue > 0 else { return nil }
            url = try? books.paymentLink(for: invoice)
        }
        let info = PayNowInfo(url: url, instructions: company.paymentInstructions.trimmingCharacters(in: .whitespacesAndNewlines))
        return info.isEmpty ? nil : info
    }

    /// Para la vista previa de Ajustes (factura de ejemplo).
    static func preview(link: String, instructions: String, amount: Int64, number: String, customer: String) -> PayNowInfo? {
        let url = link.trimmingCharacters(in: .whitespaces).isEmpty ? nil
            : PaymentLinkTemplate.url(link, amount: amount, number: number, customer: customer)
        let info = PayNowInfo(url: url, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        return info.isEmpty ? nil : info
    }

    /// Lo que se añade al correo de la factura (o del recordatorio).
    var emailText: String {
        var parts: [String] = []
        if let url { parts.append(String(localized: "Puedes pagar en línea aquí: \(url.absoluteString)")) }
        if !instructions.isEmpty { parts.append(String(localized: "Cómo pagar: \(instructions)")) }
        return parts.joined(separator: "\n\n")
    }
}

/// Código QR de un enlace (Core Image), con módulos nítidos al escalarlo.
enum PayNowQR {
    static func image(for url: URL, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent)
    }
}

/// Dónde quedó «Pagar ahora» (y el QR) en la página, para poner el enlace del PDF encima (`InvoicePDF.render`). El
/// `GeometryReader` lo anota al dibujar la página con `ImageRenderer`.
final class PayNowLinkAreas {
    var rects: [CGRect] = []
}

extension EnvironmentValues {
    @Entry var payNowLinkAreas: PayNowLinkAreas? = nil
}

/// Recuadro de pago de la factura (siempre en claro, como el resto del PDF): QR a la izquierda; «Pagar ahora» en una
/// cápsula del color de la plantilla, el enlace y «Escanea el código…»; debajo, las instrucciones.
struct PayNowBlock: View {
    let info: PayNowInfo
    let accent: Color
    let soft: Color
    @Environment(\.payNowLinkAreas) private var linkAreas

    private static let ink2 = Color(red: 0.35, green: 0.37, blue: 0.47)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = info.url {
                HStack(alignment: .center, spacing: 14) {
                    if let qr = PayNowQR.image(for: url) {
                        Image(decorative: qr, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 76, height: 76)
                            .padding(4)
                            .background(Color.white)
                            .background(linkArea)
                            .accessibilityLabel(Text("Código QR para pagar"))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pagar ahora")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(accent, in: Capsule())
                            .background(linkArea)
                        Text(verbatim: url.absoluteString)
                            .font(.system(size: 8))
                            .foregroundStyle(accent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("Escanea el código con la cámara del teléfono o pulsa «Pagar ahora».")
                            .font(.system(size: 8))
                            .foregroundStyle(Self.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !info.instructions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.url == nil ? "CÓMO PAGAR" : "OTRAS FORMAS DE PAGO")
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(Self.ink2)
                    Text(verbatim: info.instructions).font(.system(size: 9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 330, alignment: .leading)
        .background(soft.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Anota el sitio (en el espacio de la página) para el enlace del PDF. Al evaluar el `GeometryReader`: con
    /// `ImageRenderer` no corren `onAppear` ni `task` (y un `ViewModifier` tampoco servía).
    private var linkArea: some View {
        GeometryReader { proxy in
            let _ = record(proxy.frame(in: .named(InvoicePDF.pageSpace)))
            Color.clear
        }
    }

    private func record(_ frame: CGRect) {
        guard let linkAreas, !linkAreas.rects.contains(frame) else { return }
        linkAreas.rects.append(frame)
    }
}
