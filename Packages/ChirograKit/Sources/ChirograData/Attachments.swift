import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Preparación de recibos adjuntos (DISEÑO §4.5): las fotos se reducen y se guardan en JPEG;
/// los PDF se guardan tal cual.
public enum AttachmentProcessing {
    public static let maxPixelSize = 2048
    public static let jpegQuality = 0.75

    public struct Prepared: Sendable {
        public var data: Data
        public var contentType: String
        public var filename: String
    }

    public enum Failure: Error, Equatable {
        case unsupportedType
        case unreadableImage
    }

    public static func prepare(_ data: Data, filename: String, contentType: UTType) throws -> Prepared {
        if contentType.conforms(to: .pdf) {
            return Prepared(data: data, contentType: UTType.pdf.identifier, filename: filename)
        }
        return try reencoded(data, filename: filename, contentType: contentType, maxPixelSize: maxPixelSize, as: .jpeg,
                             properties: [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary,
                             fallbackName: "recibo", fileExtension: "jpg")
    }

    /// Logo de la empresa: imagen reducida a `logoMaxPixelSize` y guardada en PNG (conserva la transparencia).
    public static let logoMaxPixelSize = 512

    public static func prepareLogo(_ data: Data, filename: String, contentType: UTType) throws -> Prepared {
        try reencoded(data, filename: filename, contentType: contentType, maxPixelSize: logoMaxPixelSize, as: .png,
                      properties: nil, fallbackName: "logo", fileExtension: "png")
    }

    /// Reduce una imagen a `maxPixelSize` (respetando su orientación) y la guarda en el formato `type`.
    private static func reencoded(_ data: Data, filename: String, contentType: UTType, maxPixelSize: Int, as type: UTType,
                                  properties: CFDictionary?, fallbackName: String, fileExtension: String) throws -> Prepared {
        guard contentType.conforms(to: .image) else { throw Failure.unsupportedType }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { throw Failure.unreadableImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw Failure.unreadableImage
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadableImage }
        let base = (filename as NSString).deletingPathExtension
        return Prepared(data: output as Data, contentType: type.identifier, filename: "\(base.isEmpty ? fallbackName : base).\(fileExtension)")
    }
}

extension Bookkeeper {
    /// Adjunta un recibo a un gasto. No cambia la contabilidad: se puede hacer antes o después de registrarlo.
    @discardableResult
    public func attachReceipt(_ data: Data, filename: String, contentType: UTType, to expense: Expense) throws -> Attachment {
        let prepared = try AttachmentProcessing.prepare(data, filename: filename, contentType: contentType)
        let attachment = Attachment(filename: prepared.filename, contentType: prepared.contentType, data: prepared.data)
        attachment.expense = expense
        insert(attachment)
        try commit()
        return attachment
    }

    /// Quita un recibo adjunto. Tampoco cambia la contabilidad; queda constancia en la auditoría.
    public func removeAttachment(_ attachment: Attachment) throws {
        let owner = attachment.expense?.payee ?? attachment.bill?.vendorNumber ?? ""
        audit("Attachment", attachment.id, "delete", String(localized: "Recibo quitado: \(attachment.filename)\(owner.isEmpty ? "" : " · \(owner)")"))
        context.delete(attachment)
        try commit()
    }
}
