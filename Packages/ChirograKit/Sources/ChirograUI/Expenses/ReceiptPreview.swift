import ChirograData
import Foundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Recibos abiertos en Vista Rápida (a pantalla completa en el iPhone, con zoom; ventana en el Mac): el que se ve y
/// todos los del gasto, para pasar de uno a otro. Cada archivo se copia a la carpeta temporal con su nombre (el título
/// de Vista Rápida) y se borra al cerrarla. Eric, Beta Family, build 55: en el iPhone no había forma de ver el recibo
/// sin descargarlo.
struct ReceiptPreview {
    var current: URL?
    var all: [URL] = []

    /// Recibos ya guardados (detalle del gasto, inspector del Mac, W-9 del proveedor), empezando por `index`.
    mutating func show(_ attachments: [Attachment], from index: Int = 0) {
        open(attachments.compactMap { Self.temporaryFile(for: $0) }, from: index)
    }

    /// Recibos elegidos o escaneados que aún no se han guardado («Nuevo gasto»).
    mutating func show(_ files: [ReceiptFile], from index: Int = 0) {
        open(files.compactMap { Self.temporaryFile(for: $0) }, from: index)
    }

    private mutating func open(_ urls: [URL], from index: Int) {
        guard !urls.isEmpty else { return }
        all = urls
        current = urls[min(max(0, index), urls.count - 1)]
    }

    static let folder = FileManager.default.temporaryDirectory.appending(path: "Recibos", directoryHint: .isDirectory)

    static func temporaryFile(for attachment: Attachment) -> URL? {
        guard let data = attachment.data else { return nil }
        return temporaryFile(data, named: attachment.filename, contentType: attachment.contentType, id: attachment.id)
    }

    static func temporaryFile(for file: ReceiptFile) -> URL? {
        temporaryFile(file.data, named: file.name, contentType: file.type.identifier, id: file.id)
    }

    /// `Recibos/<id>/<nombre>`: una carpeta por archivo, para que dos recibos con el mismo nombre no se pisen.
    private static func temporaryFile(_ data: Data, named filename: String, contentType: String, id: UUID) -> URL? {
        let directory = folder.appending(path: id.uuidString, directoryHint: .isDirectory)
        var name = filename.replacingOccurrences(of: "/", with: "-")
        if name.isEmpty { name = String(localized: "Recibo") }
        if (name as NSString).pathExtension.isEmpty, let ext = UTType(contentType)?.preferredFilenameExtension {
            name += ".\(ext)"
        }
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Borra las copias (con su carpeta) al cerrar Vista Rápida.
    fileprivate mutating func clear() {
        for url in all { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        all = []
    }
}

extension View {
    /// Vista Rápida de `preview` mientras tenga un recibo abierto; al cerrarla se borran las copias temporales.
    func receiptPreview(_ preview: Binding<ReceiptPreview>) -> some View {
        quickLookPreview(preview.current, in: preview.wrappedValue.all)
            .onChange(of: preview.wrappedValue.current == nil) { _, closed in
                if closed { preview.wrappedValue.clear() }
            }
    }
}
