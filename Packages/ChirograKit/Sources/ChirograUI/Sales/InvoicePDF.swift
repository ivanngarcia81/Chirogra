import ChirograCore
import ChirograData
import CoreGraphics
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Factura en PDF tamaño carta (DISEÑO §3.1, canvas `FacturaEnviar`). Se dibuja con `InvoiceDocumentView`,
/// siempre en modo claro, y se pagina si hay muchas líneas; la vista previa muestra ese mismo PDF.
enum InvoicePDF {
    static let pageSize = CGSize(width: 612, height: 792)   // US Letter, en puntos
    static let linesPerPage = 16

    static func pages(for invoice: Invoice) -> [[InvoiceLine]] {
        let lines = invoice.sortedLines
        guard !lines.isEmpty else { return [[]] }
        return stride(from: 0, to: lines.count, by: linesPerPage).map { Array(lines[$0..<min($0 + linesPerPage, lines.count)]) }
    }

    @MainActor
    static func render(_ invoice: Invoice, company: Company?) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let pages = pages(for: invoice)
        for (index, lines) in pages.enumerated() {
            let page = InvoiceDocumentView(invoice: invoice, company: company, lines: lines,
                                           pageNumber: index + 1, pageCount: pages.count)
                .frame(width: pageSize.width, height: pageSize.height)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }
}

/// PDF de la factura ya generado, para compartir o enviar desde la hoja del sistema.
struct InvoicePDFFile: Transferable {
    let data: Data
    let filename: String

    @MainActor
    init(invoice: Invoice, company: Company?) {
        data = InvoicePDF.render(invoice, company: company)
        filename = invoice.number.isEmpty ? String(localized: "Factura borrador.pdf") : String(localized: "Factura \(invoice.number).pdf")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

/// Una página de la factura. Sin `ScrollView` ni `List` para que `ImageRenderer` la dibuje completa.
struct InvoiceDocumentView: View {
    let invoice: Invoice
    let company: Company?
    let lines: [InvoiceLine]
    var pageNumber = 1
    var pageCount = 1

    private var isLastPage: Bool { pageNumber == pageCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if pageNumber == 1 { parties }
            table
            if isLastPage { totals }
            Spacer(minLength: 0)
            footer
        }
        .padding(40)
        .font(.system(size: 10))
        .foregroundStyle(Palette.ink)
        .background(Color.white)
        .overlay {
            if invoice.status == .draft {
                Text("BORRADOR").font(.system(size: 72, weight: .black)).foregroundStyle(Palette.ink3.opacity(0.12)).rotationEffect(.degrees(-30))
            } else if invoice.status == .void {
                Text("ANULADA").font(.system(size: 72, weight: .black)).foregroundStyle(Palette.negative.opacity(0.15)).rotationEffect(.degrees(-30))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                LogoMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company?.displayName ?? "").font(.system(size: 16, weight: .bold))
                    if let company, company.legalName != company.displayName { Text(company.legalName) }
                    if let address = company?.address, !address.isEmpty { Text(address) }
                    if let email = company?.email, !email.isEmpty { Text(email) }
                    if let ein = company?.ein, !ein.isEmpty { Text("EIN \(ein)") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("FACTURA").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.brand)
                Text(invoice.number.isEmpty ? String(localized: "Sin número") : invoice.number).font(.system(size: 12, weight: .semibold))
                Text("Fecha: \(invoice.issueDate.shortDate)")
                Text("Vence: \(invoice.dueDate.shortDate)")
            }
        }
    }

    private var parties: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FACTURAR A").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.ink3)
            Text(invoice.customer?.name ?? "").font(.system(size: 12, weight: .semibold))
            if let address = invoice.customer?.billingAddress, !address.isEmpty { Text(address) }
            if let email = invoice.customer?.email, !email.isEmpty { Text(email) }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            row(String(localized: "DESCRIPCIÓN"), String(localized: "CANT."), String(localized: "PRECIO"), String(localized: "IMPORTE"), header: true)
            ForEach(lines) { line in
                row(line.details.isEmpty ? "—" : line.details + (line.isTaxable ? " *" : ""),
                    line.quantity.formatted(), line.unitPrice.money, line.amount.money)
            }
        }
    }

    private func row(_ description: String, _ quantity: String, _ price: String, _ amount: String, header: Bool = false) -> some View {
        HStack {
            Text(description).frame(maxWidth: .infinity, alignment: .leading)
            Text(quantity).frame(width: 50, alignment: .trailing)
            Text(price).frame(width: 90, alignment: .trailing)
            Text(amount).frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: header ? 8 : 10, weight: header ? .semibold : .regular).monospacedDigit())
        .foregroundStyle(header ? Palette.ink3 : Palette.ink)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 0.5) }
    }

    private var totals: some View {
        let issued = invoice.status != .draft
        let subtotal = issued ? invoice.subtotal : invoice.linesSubtotal
        return HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                total(String(localized: "Subtotal"), subtotal.money)
                if invoice.discount > 0 { total(String(localized: "Descuento"), "−\(invoice.discount.money)") }
                ForEach(invoice.taxLines ?? []) { tax in
                    total(String(localized: "\(tax.name) \((Decimal(tax.rateMillionths) / 10_000).formatted())%"), tax.amount.money)
                }
                if !issued { total(String(localized: "Sales tax"), String(localized: "se calcula al emitir")) }
                total(String(localized: "Total"), (issued ? invoice.total : invoice.draftAmount).money, bold: true)
                if invoice.amountPaid > 0 { total(String(localized: "Pagado"), "−\(invoice.amountPaid.money)") }
                if invoice.creditsApplied > 0 { total(String(localized: "Notas de crédito"), "−\(invoice.creditsApplied.money)") }
                if issued { total(String(localized: "Saldo pendiente"), invoice.balanceDue.money, bold: true) }
            }
            .frame(width: 240)
        }
    }

    private func total(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: bold ? 12 : 10, weight: bold ? .bold : .regular))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLastPage, !invoice.customerMessage.isEmpty { Text(invoice.customerMessage) }
            if lines.contains(where: \.isTaxable) { Text("* Gravable con sales tax").foregroundStyle(Palette.ink3) }
            HStack {
                Text("Hecho con Chirogra").foregroundStyle(Palette.ink3)
                Spacer()
                if pageCount > 1 { Text("Página \(pageNumber) de \(pageCount)").foregroundStyle(Palette.ink3) }
            }
        }
        .font(.system(size: 8))
    }
}

/// Vista previa de la factura tal como saldrá en el PDF, con botón para compartirla.
struct InvoicePreviewView: View {
    let invoice: Invoice
    let company: Company?
    @Environment(\.dismiss) private var dismiss
    @State private var pdf: InvoicePDFFile?

    var body: some View {
        Group {
            if let pdf {
                // El mismo PDF que se comparte, ajustado al ancho de la pantalla; se amplía con dos dedos.
                PDFPreview(data: pdf.data)
                    .accessibilityLabel("Vista previa de la factura \(invoice.number)")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.surface2)
        // `FacturaEnviar`: «Compartir PDF» como acción principal, fija abajo. Enviar por correo desde la app
        // (hoja «Enviar por correo» del canvas) llega más adelante: de momento se comparte por Mail o Mensajes.
        .bottomActionBar {
            if let pdf {
                ShareLink(item: pdf, subject: Text(pdf.filename), preview: SharePreview(pdf.filename)) {
                    Label("Compartir PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            }
        }
        .navigationTitle(invoice.number.isEmpty ? String(localized: "Vista previa") : invoice.number)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.headerButton() }
        }
        .task { pdf = InvoicePDFFile(invoice: invoice, company: company) }
    }
}

/// PDF con PDFKit: páginas ajustadas al ancho disponible y zoom con gesto.
#if canImport(UIKit)
private struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
#elseif canImport(AppKit)
private struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif
