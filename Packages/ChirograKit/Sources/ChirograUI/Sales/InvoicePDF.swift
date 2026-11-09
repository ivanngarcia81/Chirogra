import ChirograCore
import ChirograData
import CoreGraphics
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Documento de venta

/// Factura o estimado del que sale un PDF (canvas `FacturaEnviar`, `Estimado`).
enum SalesDocumentSource {
    case invoice(Invoice)
    case estimate(Estimate)

    var customer: Customer? {
        switch self {
        case .invoice(let invoice): invoice.customer
        case .estimate(let estimate): estimate.customer
        }
    }

    var document: SalesDocument {
        switch self {
        case .invoice(let invoice): SalesDocument(invoice: invoice)
        case .estimate(let estimate): SalesDocument(estimate: estimate)
        }
    }
}

/// Lo que se imprime de una factura o un estimado, ya calculado: datos, líneas, filas de totales y marca de agua.
/// El PDF, la vista previa y la plantilla de Ajustes dibujan esto con `InvoiceDocumentView`.
struct SalesDocument {
    enum Kind { case invoice, estimate }

    struct Line: Identifiable {
        let id: UUID
        let details: String
        let quantity: Decimal
        let unitPrice: Int64
        let amount: Int64
        let isTaxable: Bool
    }

    /// Fila de totales. `subtle` va en gris (el impuesto incluido); `strong`, en negrita; `accent`, en la cápsula del
    /// color de la plantilla (el total).
    struct Total: Identifiable {
        enum Style { case normal, subtle, strong, accent }
        let id = UUID()
        let title: String
        let value: String
        var style: Style = .normal
    }

    var kind: Kind
    var number: String
    /// Concepto del estimado («Remodelación del lobby»).
    var title = ""
    var issueDate: Date
    var secondDate: Date
    var customerName: String
    var customerAddress: String
    var customerEmail: String
    var lines: [Line]
    var totals: [Total]
    var message: String
    var watermark: String?
    /// La marca de agua va en rojo (factura anulada, estimado rechazado).
    var watermarkIsNegative = false
    /// Importe de la barra de la vista previa: total, o saldo de una factura abierta.
    var amount: Int64
    var pricesIncludeTax = false
    /// Recuadro «Pagar ahora» con QR e instrucciones (`Sales/PayNow/`); `nil` sin enlace ni instrucciones.
    var payNow: PayNowInfo?

    var filename: String {
        switch kind {
        case .invoice: number.isEmpty ? String(localized: "Factura borrador.pdf") : String(localized: "Factura \(number).pdf")
        case .estimate: number.isEmpty ? String(localized: "Estimado.pdf") : String(localized: "Estimado \(number).pdf")
        }
    }

    var hasTaxableLines: Bool { lines.contains(where: \.isTaxable) }

    init(invoice: Invoice) {
        kind = .invoice
        number = invoice.number
        issueDate = invoice.issueDate
        secondDate = invoice.dueDate
        customerName = invoice.customer?.name ?? ""
        customerAddress = invoice.customer?.billingAddress ?? ""
        customerEmail = invoice.customer?.email ?? ""
        lines = invoice.sortedLines.map {
            Line(id: $0.id, details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice, amount: $0.amount, isTaxable: $0.isTaxable)
        }
        message = invoice.customerMessage
        pricesIncludeTax = invoice.pricesIncludeTax
        watermark = invoice.status == .draft ? String(localized: "BORRADOR") : invoice.status == .void ? String(localized: "ANULADA") : nil
        watermarkIsNegative = invoice.status == .void
        if invoice.status == .draft {
            // Borrador: los totales con las reglas de emisión (impuesto, descuento, impuesto incluido).
            if let computed = invoice.modelContext.flatMap({ try? Bookkeeper(context: $0).totals(for: invoice) }) {
                self.totals = Self.rows(subtotal: computed.subtotal, discount: computed.discount,
                                        taxes: computed.taxes.map { ($0.component.name, $0.component.rateMillionths, $0.amount) },
                                        total: computed.total, pricesIncludeTax: invoice.pricesIncludeTax)
                amount = computed.total
            } else {
                self.totals = Self.rows(subtotal: invoice.linesSubtotal, discount: invoice.discount, taxes: [],
                                        total: invoice.draftAmount, pricesIncludeTax: invoice.pricesIncludeTax)
                amount = invoice.draftAmount
            }
        } else {
            var rows = Self.rows(subtotal: invoice.subtotal, discount: invoice.discount,
                                 taxes: (invoice.taxLines ?? []).sorted { $0.name < $1.name }.map { ($0.name, $0.rateMillionths, $0.amount) },
                                 total: invoice.total, pricesIncludeTax: invoice.pricesIncludeTax)
            if invoice.amountPaid > 0 { rows.append(Total(title: String(localized: "Pagado"), value: "−\(invoice.amountPaid.money)")) }
            if invoice.creditsApplied > 0 {
                rows.append(Total(title: String(localized: "Notas de crédito"), value: "−\(invoice.creditsApplied.money)"))
            }
            if invoice.amountPaid > 0 || invoice.creditsApplied > 0 {
                rows.append(Total(title: String(localized: "Saldo pendiente"), value: invoice.balanceDue.money, style: .strong))
            }
            totals = rows
            amount = invoice.isOpen ? invoice.balanceDue : invoice.total
        }
        payNow = PayNowInfo.forInvoice(invoice, amount: amount)
    }

    init(estimate: Estimate) {
        kind = .estimate
        number = estimate.number
        title = estimate.title
        issueDate = estimate.issueDate
        secondDate = estimate.expirationDate
        customerName = estimate.customer?.name ?? ""
        customerAddress = estimate.customer?.billingAddress ?? ""
        customerEmail = estimate.customer?.email ?? ""
        lines = estimate.sortedLines.map {
            Line(id: $0.id, details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice, amount: $0.amount, isTaxable: $0.isTaxable)
        }
        message = estimate.customerMessage
        pricesIncludeTax = estimate.pricesIncludeTax
        watermark = estimate.status == .declined ? String(localized: "RECHAZADO") : nil
        watermarkIsNegative = estimate.status == .declined
        if let computed = estimate.modelContext.flatMap({ try? Bookkeeper(context: $0).totals(for: estimate) }) {
            totals = Self.rows(subtotal: computed.subtotal, discount: computed.discount,
                               taxes: computed.taxes.map { ($0.component.name, $0.component.rateMillionths, $0.amount) },
                               total: computed.total, pricesIncludeTax: estimate.pricesIncludeTax)
            amount = computed.total
        } else {
            totals = Self.rows(subtotal: estimate.subtotal, discount: estimate.discount,
                               taxes: estimate.taxTotal == 0 ? [] : [(String(localized: "Sales tax"), Int64(0), estimate.taxTotal)],
                               total: estimate.total, pricesIncludeTax: estimate.pricesIncludeTax)
            amount = estimate.total
        }
    }

    /// Ejemplo para la vista previa de la plantilla cuando aún no hay facturas (canvas `AjustesPlantilla`).
    static func sample(customerMessage: String) -> SalesDocument {
        let lines = [
            Line(id: UUID(), details: String(localized: "Diseño de barra y mostrador"), quantity: 1, unitPrice: 180_000, amount: 180_000, isTaxable: false),
            Line(id: UUID(), details: String(localized: "Instalación de repisas (h)"), quantity: 6, unitPrice: 6_500, amount: 39_000, isTaxable: false),
            Line(id: UUID(), details: String(localized: "Madera de roble (m²)"), quantity: 4, unitPrice: 8_500, amount: 34_000, isTaxable: true),
        ]
        var document = SalesDocument(kind: .invoice, number: "F-1049", issueDate: .now,
                                     secondDate: Calendar.current.date(byAdding: .day, value: 15, to: .now) ?? .now,
                                     customerName: "Café Aurora", customerAddress: "", customerEmail: "pagos@cafeaurora.com",
                                     lines: lines, totals: [], message: customerMessage, watermark: nil, amount: 255_805)
        document.totals = rows(subtotal: 253_000, discount: 0, taxes: [("Texas", 82_500, 2_805)], total: 255_805, pricesIncludeTax: false)
        return document
    }

    private init(kind: Kind, number: String, issueDate: Date, secondDate: Date, customerName: String, customerAddress: String,
                 customerEmail: String, lines: [Line], totals: [Total], message: String, watermark: String?, amount: Int64) {
        self.kind = kind
        self.number = number
        self.issueDate = issueDate
        self.secondDate = secondDate
        self.customerName = customerName
        self.customerAddress = customerAddress
        self.customerEmail = customerEmail
        self.lines = lines
        self.totals = totals
        self.message = message
        self.watermark = watermark
        self.amount = amount
    }

    /// Subtotal, descuento, impuesto y total. Con precios con impuesto incluido el subtotal ya lleva el impuesto, así que
    /// Subtotal − Descuento = Total y el impuesto va debajo, en gris, como «Incluye Austin 8.25 %» (DATOS-V2 §4): antes
    /// se sumaba como una fila más y la cuenta no cuadraba.
    static func rows(subtotal: Int64, discount: Int64, taxes: [(name: String, rate: Int64, amount: Int64)], total: Int64,
                     pricesIncludeTax: Bool) -> [Total] {
        var rows = [Total(title: String(localized: "Subtotal"), value: subtotal.money)]
        if discount > 0 { rows.append(Total(title: String(localized: "Descuento"), value: "−\(discount.money)")) }
        if pricesIncludeTax {
            rows.append(Total(title: String(localized: "Total (impuesto incluido)"), value: total.money, style: .accent))
            for tax in taxes where tax.amount != 0 {
                rows.append(Total(title: String(localized: "Incluye \(tax.name) \(percentText(tax.rate))"), value: tax.amount.money, style: .subtle))
            }
        } else {
            for tax in taxes {
                rows.append(Total(title: "\(tax.name) \(percentText(tax.rate))", value: tax.amount.money))
            }
            rows.append(Total(title: String(localized: "Total"), value: total.money, style: .accent))
        }
        return rows
    }

    /// «8.25 %» a partir de millonésimas.
    static func percentText(_ millionths: Int64) -> String {
        (Decimal(millionths) / 1_000_000).formatted(.percent.precision(.fractionLength(0...4)))
    }
}

// MARK: - PDF

/// PDF tamaño carta de una factura o un estimado (DISEÑO §3.1, canvas `FacturaEnviar`). Se dibuja con
/// `InvoiceDocumentView`, siempre en modo claro, con la plantilla de la empresa, y se pagina si hay muchas líneas; la
/// vista previa muestra ese mismo PDF.
enum InvoicePDF {
    static let pageSize = CGSize(width: 612, height: 792)   // US Letter, en puntos
    /// Espacio de coordenadas de la página (para el enlace de «Pagar ahora», `PayNowLinkAreas`).
    static let pageSpace = "invoicePage"

    static func linesPerPage(for company: Company?) -> Int {
        company?.invoiceStyle == .compact ? 20 : 16
    }

    static func pages(for document: SalesDocument, company: Company?) -> [[SalesDocument.Line]] {
        let lines = document.lines
        guard !lines.isEmpty else { return [[]] }
        let size = linesPerPage(for: company)
        return stride(from: 0, to: lines.count, by: size).map { Array(lines[$0..<min($0 + size, lines.count)]) }
    }

    static func pages(for invoice: Invoice, company: Company? = nil) -> [[SalesDocument.Line]] {
        pages(for: SalesDocument(invoice: invoice), company: company)
    }

    @MainActor
    static func render(_ invoice: Invoice, company: Company?) -> Data {
        render(SalesDocument(invoice: invoice), company: company)
    }

    @MainActor
    static func render(_ document: SalesDocument, company: Company?) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let pages = pages(for: document, company: company)
        for (index, lines) in pages.enumerated() {
            let areas = PayNowLinkAreas()
            let page = InvoiceDocumentView(document: document, company: company, lines: lines,
                                           pageNumber: index + 1, pageCount: pages.count)
                .frame(width: pageSize.width, height: pageSize.height)
                .coordinateSpace(.named(pageSpace))
                .environment(\.colorScheme, .light)
                .environment(\.payNowLinkAreas, areas)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                // «Pagar ahora» y el QR se pueden pulsar en el PDF (el origen del PDF está abajo a la izquierda).
                if let url = document.payNow?.url {
                    for rect in areas.rects where rect.width > 0 && rect.height > 0 {
                        pdf.setURL(url as CFURL, for: CGRect(x: rect.minX, y: pageSize.height - rect.maxY,
                                                             width: rect.width, height: rect.height))
                    }
                }
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }
}

/// PDF ya generado, para compartir, imprimir o adjuntar al correo.
struct InvoicePDFFile: Transferable {
    let data: Data
    let filename: String

    @MainActor
    init(invoice: Invoice, company: Company?) {
        self.init(document: SalesDocument(invoice: invoice), company: company)
    }

    @MainActor
    init(document: SalesDocument, company: Company?) {
        data = InvoicePDF.render(document, company: company)
        filename = document.filename
    }

    /// Copia en la carpeta temporal con su nombre, para las hojas que adjuntan archivos (compartir, correo del Mac).
    func temporaryURL() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: filename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

// MARK: - Plantilla

/// Colores y opciones de la plantilla de factura de la empresa (canvas `AjustesPlantilla`, DATOS-V2 §10).
struct InvoiceTemplate {
    var accent: Color
    var soft: Color
    var style: InvoiceStyle
    var showLogo: Bool
    var showEIN: Bool
    var showAddress: Bool
    var showPhone: Bool
    var logo: Data?
    var footer: String

    init(company: Company?) {
        let hex = company?.invoiceAccentHex ?? InvoiceAccent.ink.hex
        accent = Color(invoiceHex: hex) ?? Color(invoiceHex: InvoiceAccent.ink.hex) ?? .indigo
        soft = InvoiceAccent(hex: hex).flatMap { Color(invoiceHex: $0.softHex) } ?? accent.opacity(0.12)
        style = company?.invoiceStyle ?? .classic
        showLogo = company?.invoiceShowLogo ?? true
        showEIN = company?.invoiceShowEIN ?? false
        showAddress = company?.invoiceShowAddress ?? true
        showPhone = company?.invoiceShowPhone ?? true
        logo = company?.logo?.data
        footer = company?.invoiceFooter ?? ""
    }
}

extension Color {
    /// Color de un hexadecimal «#3A3FD1» (el de la plantilla de factura).
    init?(invoiceHex hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// Imagen del logo guardado (PNG), para el PDF y Ajustes.
struct CompanyLogoImage: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
        #elseif canImport(AppKit)
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        #endif
    }
}

// MARK: - Página

/// Una página de la factura o del estimado, con la plantilla de la empresa: logo (o sus iniciales en el color de la
/// plantilla), datos según los interruptores, título «FACTURA» espaciado (clásica) o «Factura» (compacta), cabecera
/// de la tabla en el color suave, total en una cápsula del color y el pie de la plantilla junto al mensaje.
/// Sin `ScrollView` ni `List` para que `ImageRenderer` la dibuje completa. Siempre en claro (colores fijos).
struct InvoiceDocumentView: View {
    let document: SalesDocument
    let company: Company?
    let lines: [SalesDocument.Line]
    var pageNumber = 1
    var pageCount = 1

    private static let ink = Color(red: 0.07, green: 0.08, blue: 0.17)
    private static let ink2 = Color(red: 0.35, green: 0.37, blue: 0.47)
    private static let line = Color(red: 0.82, green: 0.82, blue: 0.84)

    private var template: InvoiceTemplate { InvoiceTemplate(company: company) }
    private var isLastPage: Bool { pageNumber == pageCount }
    private var isCompact: Bool { template.style == .compact }

    var body: some View {
        let template = template
        VStack(alignment: .leading, spacing: isCompact ? 12 : 18) {
            header(template)
            if pageNumber == 1 { parties }
            table(template)
            if isLastPage { totals(template) }
            if isLastPage, let payNow = document.payNow {
                PayNowBlock(info: payNow, accent: template.accent, soft: template.soft)
            }
            Spacer(minLength: 0)
            footer(template)
        }
        .padding(40)
        .font(.system(size: 10))
        .foregroundStyle(Self.ink)
        .background(Color.white)
        .overlay {
            if let watermark = document.watermark {
                Text(watermark).font(.system(size: 72, weight: .black))
                    .foregroundStyle((document.watermarkIsNegative ? Color.red : Self.ink).opacity(0.1))
                    .rotationEffect(.degrees(-30))
            }
        }
    }

    private var documentTitle: String {
        switch (document.kind, isCompact) {
        case (.invoice, false): String(localized: "FACTURA")
        case (.invoice, true): String(localized: "Factura")
        case (.estimate, false): String(localized: "ESTIMADO")
        case (.estimate, true): String(localized: "Estimado")
        }
    }

    private func header(_ template: InvoiceTemplate) -> some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 10) {
                if template.showLogo { logo(template) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(company?.displayName ?? "").font(.system(size: 16, weight: .bold))
                    if let company, company.legalName != company.displayName, !company.legalName.isEmpty { Text(company.legalName) }
                    if template.showAddress, let address = company?.address, !address.isEmpty { Text(address) }
                    if let email = company?.email, !email.isEmpty { Text(email) }
                    if template.showPhone, let phone = company?.phone, !phone.isEmpty { Text(phone) }
                    if let website = company?.website, !website.isEmpty { Text(website) }
                    if template.showEIN, let ein = company?.ein, !ein.isEmpty { Text("EIN \(ein)") }
                }
                .foregroundStyle(Self.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(documentTitle)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(isCompact ? 0 : 2)
                    .foregroundStyle(template.accent)
                Text(document.number.isEmpty ? String(localized: "Sin número") : document.number).font(.system(size: 12, weight: .semibold))
                Text("Fecha: \(document.issueDate.shortDate)")
                switch document.kind {
                case .invoice: Text("Vence: \(document.secondDate.shortDate)")
                case .estimate: Text("Válido hasta: \(document.secondDate.shortDate)")
                }
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(template.accent).frame(height: 2) }
    }

    /// Logo de la empresa; sin logo, sus iniciales en un cuadrado del color de la plantilla (canvas `AjustesPlantilla`).
    @ViewBuilder
    private func logo(_ template: InvoiceTemplate) -> some View {
        if let data = template.logo {
            CompanyLogoImage(data: data).frame(maxWidth: 96, maxHeight: 44, alignment: .topLeading)
        } else {
            Text(Initials.from(company?.displayName ?? ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(template.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var parties: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.kind == .invoice ? String(localized: "FACTURAR A") : String(localized: "PARA"))
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(Self.ink2)
            Text(document.customerName).font(.system(size: 12, weight: .semibold))
            if !document.customerAddress.isEmpty { Text(document.customerAddress) }
            if !document.customerEmail.isEmpty { Text(document.customerEmail) }
            if !document.title.isEmpty {
                Text(document.title).font(.system(size: 11, weight: .semibold)).padding(.top, 6)
            }
        }
    }

    private func table(_ template: InvoiceTemplate) -> some View {
        VStack(spacing: 0) {
            row(String(localized: "DESCRIPCIÓN"), String(localized: "CANT."), String(localized: "PRECIO"), String(localized: "IMPORTE"), header: true)
                .background(template.soft, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            ForEach(lines) { line in
                row(line.details.isEmpty ? "—" : line.details + (line.isTaxable ? " *" : ""),
                    line.quantity.formatted(), line.unitPrice.money, line.amount.money)
                    .overlay(alignment: .bottom) { Rectangle().fill(Self.line).frame(height: 0.5) }
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
        .font(.system(size: header ? 8 : 10, weight: header ? .bold : .regular).monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, isCompact ? 3 : 6)
    }

    private func totals(_ template: InvoiceTemplate) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(document.totals) { total in
                    switch total.style {
                    case .accent:
                        totalRow(total.title, total.value, size: 12, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(template.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    case .strong: totalRow(total.title, total.value, size: 11, weight: .bold)
                    case .subtle: totalRow(total.title, total.value, size: 9, weight: .regular).foregroundStyle(Self.ink2)
                    case .normal: totalRow(total.title, total.value, size: 10, weight: .regular)
                    }
                }
            }
            .frame(width: 250)
        }
    }

    private func totalRow(_ title: String, _ value: String, size: CGFloat, weight: Font.Weight) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: size, weight: weight))
    }

    private func footer(_ template: InvoiceTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLastPage, !document.message.isEmpty { Text(document.message).font(.system(size: 9)) }
            if isLastPage, !template.footer.isEmpty { Text(template.footer).font(.system(size: 9)).foregroundStyle(Self.ink2) }
            if lines.contains(where: \.isTaxable) {
                Text(document.pricesIncludeTax ? String(localized: "* Gravable · precio con sales tax incluido") : String(localized: "* Gravable con sales tax"))
                    .foregroundStyle(Self.ink2)
            }
            HStack {
                Text("Hecho con Chirogra").foregroundStyle(Self.ink2)
                Spacer()
                if pageCount > 1 { Text("Página \(pageNumber) de \(pageCount)").foregroundStyle(Self.ink2) }
            }
        }
        .font(.system(size: 8))
    }
}

/// Una página del documento a escala de `width` (como mucho `maxWidth`), con sombra de papel sobre el fondo.
struct DocumentPageThumbnail: View {
    let document: SalesDocument
    let company: Company?
    let lines: [SalesDocument.Line]
    var pageNumber = 1
    var pageCount = 1
    let width: CGFloat

    var body: some View {
        let size = InvoicePDF.pageSize
        let scale = max(1, width) / size.width
        InvoiceDocumentView(document: document, company: company, lines: lines, pageNumber: pageNumber, pageCount: pageCount)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.14), radius: 15, y: 10)
    }
}

// MARK: - Vista previa

/// Vista previa de una factura (también un borrador desde el editor).
struct InvoicePreviewView: View {
    let invoice: Invoice
    let company: Company?

    var body: some View { DocumentPreviewView(source: .invoice(invoice), company: company) }
}

/// Vista previa (canvas `FacturaEnviar`): las páginas tal como salen en el PDF, con sombra sobre el fondo; un grupo con
/// «Compartir PDF…» e «Imprimir»; y la barra de vidrio con el cliente, el importe y «Compartir». Para enviar por correo
/// con Para y Asunto (y dejarlo anotado) está `SendDocumentView`.
struct DocumentPreviewView: View {
    let source: SalesDocumentSource
    let company: Company?
    @Environment(\.dismiss) private var dismiss
    @State private var pdf: InvoicePDFFile?
    @State private var width: CGFloat = 0

    private var document: SalesDocument { source.document }
    private var title: String { document.number.isEmpty ? String(localized: "Vista previa") : document.number }

    var body: some View {
        let document = document
        let pages = InvoicePDF.pages(for: document, company: company)
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                VStack(spacing: 16) {
                    ForEach(pages.indices, id: \.self) { index in
                        DocumentPageThumbnail(document: document, company: company, lines: pages[index],
                                              pageNumber: index + 1, pageCount: pages.count, width: min(width - 24, 560))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(pages.count == 1 ? String(localized: "Vista previa de \(title)")
                                                : String(localized: "Página \(index + 1) de \(pages.count)"))
                    }
                }
                .padding(.top, 4)
                Text(pages.count == 1 ? String(localized: "Página 1 de 1 · PDF") : String(localized: "\(pages.count) páginas · PDF"))
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.top, 8)
                ShareAndPrintGroup(pdf: pdf).padding(.top, 20).frame(maxWidth: 560)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
        .bottomActionBar {
            VStack(alignment: .leading, spacing: 0) {
                Text("Para \(document.customerName.isEmpty ? String(localized: "Sin cliente") : document.customerName)")
                    .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                Text(document.amount.money).font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .accessibilityElement(children: .combine)
            if let pdf {
                ShareLink(item: pdf, subject: Text(pdf.filename), preview: SharePreview(pdf.filename)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primaryCompact)
            } else {
                ProgressView().frame(minWidth: 88, minHeight: Metrics.buttonHeight)
            }
        }
        .navigationTitle(title)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    #if os(macOS)
                    Text("Cerrar")
                    #else
                    Label("Cerrar", systemImage: "xmark").labelStyle(.iconOnly)
                    #endif
                }
                .headerButton()
            }
        }
        .task { pdf = InvoicePDFFile(document: document, company: company) }
    }
}

/// «Compartir PDF…» e «Imprimir» como filas con icono tipo Ajustes (canvas `FacturaEnviar`).
struct ShareAndPrintGroup: View {
    let pdf: InvoicePDFFile?

    var body: some View {
        VStack(spacing: 0) {
            if let pdf {
                ShareLink(item: pdf, subject: Text(pdf.filename), preview: SharePreview(pdf.filename)) {
                    row(String(localized: "Compartir PDF…"), systemImage: "square.and.arrow.up", color: Palette.blue)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, Metrics.cardPadding + Metrics.iconTile + 12)
                Button { InvoicePrinter.print(pdf) } label: {
                    row(String(localized: "Imprimir"), systemImage: "printer", color: Palette.gray)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: Metrics.target)
            }
        }
        .card(padding: 0)
    }

    private func row(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, foreground: color)
            Text(title).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .frame(minHeight: Metrics.target + 4)
        .contentShape(Rectangle())
    }
}

/// Imprime el PDF con el diálogo del sistema.
@MainActor
enum InvoicePrinter {
    static func print(_ file: InvoicePDFFile) {
        #if canImport(UIKit)
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = file.filename
        controller.printInfo = info
        controller.printingItem = file.data
        controller.present(animated: true)
        #elseif canImport(AppKit)
        guard let document = PDFDocument(data: file.data),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        operation.jobTitle = file.filename
        operation.runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        #endif
    }
}
