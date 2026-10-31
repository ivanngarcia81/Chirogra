import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import ChirograData

@MainActor
@Suite("Recibos adjuntos")
struct AttachmentTests {
    func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.25, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Una foto grande se reduce a 2048 px y se guarda como JPEG")
    func photoIsDownscaled() throws {
        let prepared = try AttachmentProcessing.prepare(try png(width: 4000, height: 3000), filename: "IMG_0001.png", contentType: .png)
        #expect(prepared.contentType == UTType.jpeg.identifier)
        #expect(prepared.filename == "IMG_0001.jpg")
        let source = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2048)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1536)
    }

    @Test("Los PDF se guardan tal cual y otros tipos se rechazan")
    func pdfAndUnsupported() throws {
        let pdf = Data("%PDF-1.7 recibo".utf8)
        #expect(try AttachmentProcessing.prepare(pdf, filename: "recibo.pdf", contentType: .pdf).data == pdf)
        #expect(throws: AttachmentProcessing.Failure.unsupportedType) {
            try AttachmentProcessing.prepare(Data("hola".utf8), filename: "nota.txt", contentType: .plainText)
        }
    }

    @Test("Adjuntar un recibo a un gasto registrado no cambia la contabilidad")
    func attachToExpense() throws {
        let container = try ChirograStore.makeContainer(inMemory: true)
        let books = Bookkeeper(context: container.mainContext)
        try books.setUpCompany(legalName: "Prueba", locale: Locale(identifier: "es_US"))
        let accounts = try books.accounts()
        let expense = Expense(payee: "Home Depot", paymentAccountID: accounts.first { $0.code == "1010" }?.id)
        container.mainContext.insert(expense)
        let line = ExpenseLine(details: "Suministros", amount: 21_475, accountID: accounts.first { $0.code == "6500" }?.id)
        line.expense = expense
        container.mainContext.insert(line)
        try books.record(expense)
        let entries = try container.mainContext.fetchCount(FetchDescriptor<JournalEntry>())

        try books.attachReceipt(try png(width: 800, height: 600), filename: "ticket.png", contentType: .png, to: expense)
        #expect(expense.attachments?.count == 1)
        #expect(expense.attachments?.first?.contentType == UTType.jpeg.identifier)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<JournalEntry>()) == entries)
    }
}
