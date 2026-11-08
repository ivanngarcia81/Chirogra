import ChirograData
import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import Testing
import Vision
@testable import ChirograUI

/// «Pagar ahora» en la factura: el recuadro sale solo cuando toca, el PDF lleva el enlace pulsable y el QR se lee.
@MainActor
@Suite("Pagar ahora en la factura", .serialized)
struct PayNowTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    var books: Bookkeeper { Bookkeeper(context: context) }

    init() throws {
        container = try ChirograStore.makeContainer(inMemory: true)
        _ = try Bookkeeper(context: container.mainContext, actor: "Pruebas")
            .setUpCompany(legalName: "Taller Uno LLC", entityType: .llc, state: "TX", locale: Locale(identifier: "es_US"))
    }

    func issuedInvoice(amount: Int64 = 125_050) throws -> Invoice {
        let customer = Customer(name: "Café Aurora")
        books.insert(customer)
        let income = try #require(try books.accounts().first { $0.code == "4000" })
        let invoice = try books.saveDraft(InvoiceDraftInput(customer: customer, issueDate: .now, dueDate: .now,
                                                            lines: [.init(details: "Servicio", unitPrice: amount, incomeAccountID: income.id)]))
        try books.issue(invoice)
        return invoice
    }

    @Test("Sin enlace ni instrucciones, o con «Pagar ahora» apagado, la factura no lleva el recuadro")
    func onlyWhenConfigured() throws {
        let invoice = try issuedInvoice()
        #expect(SalesDocument(invoice: invoice).payNow == nil)
        try books.setPaymentSettings(link: "https://buy.stripe.com/test_123", instructions: "", showPayNow: false)
        #expect(SalesDocument(invoice: invoice).payNow == nil)
        try books.setPaymentSettings(link: "", instructions: "Zelle a pagos@tallerluna.com", showPayNow: true)
        let info = try #require(SalesDocument(invoice: invoice).payNow)
        #expect(info.url == nil)
        #expect(info.emailText.contains("Zelle a pagos@tallerluna.com"))
    }

    @Test("El enlace con {amount} y {number} lleva el saldo; el PDF tiene el enlace pulsable y el QR dice lo mismo")
    func pdfLinkAndQR() async throws {
        let invoice = try issuedInvoice()
        try books.setPaymentSettings(link: "https://pay.example.com/taller?amount={amount}&ref={number}",
                                     instructions: "Transferencia: cuenta 1234", showPayNow: true)
        let document = SalesDocument(invoice: invoice)
        let url = try #require(document.payNow?.url)
        #expect(url.absoluteString == "https://pay.example.com/taller?amount=1250.50&ref=\(invoice.number)")
        #expect(document.payNow?.emailText.contains(url.absoluteString) == true)

        let company = try books.company()
        let data = InvoicePDF.render(document, company: company)
        let pdf = try #require(PDFDocument(data: data))
        let page = try #require(pdf.page(at: 0))
        let links = page.annotations.compactMap(\.url)
        #expect(links.count == 2, "«Pagar ahora» y el QR: \(page.annotations.map(\.bounds))")
        #expect(links.allSatisfy { $0 == url })

        // El QR de la página, leído con Vision.
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3
        let context = try #require(CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                             bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(try #require(page.pageRef))
        let image = try #require(context.makeImage())
        let codes = try await DetectBarcodesRequest().perform(on: image)
        #expect(codes.compactMap(\.payloadString).contains(url.absoluteString))
    }

    @Test("Una factura pagada no lleva «Pagar ahora»")
    func paidInvoice() throws {
        let invoice = try issuedInvoice(amount: 10_000)
        try books.setPaymentSettings(link: "https://paypal.me/tallerluna", instructions: "", showPayNow: true)
        #expect(SalesDocument(invoice: invoice).payNow?.url != nil)
        let bank = try #require(try books.accounts().first { $0.subtype == .bank })
        try books.recordPayment(for: invoice, amount: 10_000, depositAccount: bank)
        #expect(SalesDocument(invoice: invoice).payNow == nil)
    }
}
