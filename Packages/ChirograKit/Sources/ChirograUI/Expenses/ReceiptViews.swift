import ChirograData
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Botones para adjuntar un recibo: foto de la fototeca o archivo (imagen o PDF).
/// La lectura automática del recibo (OCR) es de la fase 2.
struct ReceiptPickerButtons: View {
    let onPick: (Data, String, UTType) -> Void
    @State private var photo: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            Label("Adjuntar foto del recibo", systemImage: "photo.on.rectangle")
        }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self) {
                    onPick(data, "recibo.jpg", photo.supportedContentTypes.first ?? .jpeg)
                }
                self.photo = nil
            }
        }
        Button("Adjuntar archivo (PDF o imagen)", systemImage: "doc.badge.plus") { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                onPick(data, url.lastPathComponent, UTType(filenameExtension: url.pathExtension) ?? .data)
            }
    }
}

/// Miniatura de un recibo adjunto; los PDF se muestran con un icono.
struct ReceiptThumbnail: View {
    let data: Data?
    let contentType: String
    var side: CGFloat = 72

    var body: some View {
        Group {
            if let image = cgImage {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "doc.richtext").font(.title).foregroundStyle(Palette.ink3)
            }
        }
        .frame(width: side, height: side)
        .background(Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(contentType == UTType.pdf.identifier ? "Recibo en PDF" : "Foto del recibo")
    }

    private var cgImage: CGImage? {
        guard contentType != UTType.pdf.identifier, let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
        ] as CFDictionary)
    }
}

/// Archivo de un recibo para compartir o abrir en otra app.
struct AttachmentFile: Transferable {
    let data: Data
    let filename: String
    let contentType: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

/// Detalle de un gasto: datos, categoría, recibos adjuntos y asiento contable.
struct ExpenseDetailView: View {
    @Bindable var expense: Expense
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @State private var errorMessage: String?
    @State private var removing: Attachment?

    var body: some View {
        List {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.payee).font(.title3.weight(.semibold))
                    Text("−\(expense.total.money)").font(.amount(28)).foregroundStyle(Palette.outflow)
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Fecha", value: expense.date.shortDate)
                LabeledContent("Pagado con", value: accounts.first { $0.id == expense.paymentAccountID }?.name ?? "—")
                ForEach(expense.sortedLines) { line in
                    LabeledContent(accounts.first { $0.id == line.accountID }?.name ?? "Sin categoría", value: line.amount.money)
                }
                if !expense.memo.isEmpty { LabeledContent("Nota", value: expense.memo) }
            }
            Section {
                let attachments = (expense.attachments ?? []).sorted { $0.createdAt < $1.createdAt }
                if attachments.isEmpty {
                    Text("Sin recibo. Guarda el comprobante: el IRS pide conservarlo.").foregroundStyle(Palette.ink3)
                }
                ForEach(attachments) { attachment in
                    HStack(spacing: 12) {
                        ReceiptThumbnail(data: attachment.data, contentType: attachment.contentType)
                        VStack(alignment: .leading) {
                            Text(attachment.filename).lineLimit(1)
                            Text(attachment.createdAt.shortDate).font(.caption).foregroundStyle(Palette.ink3)
                        }
                        Spacer()
                        if let data = attachment.data {
                            ShareLink(item: AttachmentFile(data: data, filename: attachment.filename, contentType: attachment.contentType),
                                      preview: SharePreview(attachment.filename)) {
                                Label("Compartir", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("Compartir \(attachment.filename)")
                        }
                        Button("Quitar", systemImage: "trash", role: .destructive) { removing = attachment }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Quitar \(attachment.filename)")
                    }
                    .swipeActions {
                        Button("Quitar", systemImage: "trash", role: .destructive) { removing = attachment }
                    }
                    .contextMenu {
                        Button("Quitar recibo", systemImage: "trash", role: .destructive) { removing = attachment }
                    }
                }
                ReceiptPickerButtons { data, name, type in
                    do {
                        try Bookkeeper(context: context).attachReceipt(data, filename: name, contentType: type, to: expense)
                        errorMessage = nil
                    } catch {
                        errorMessage = "No se pudo adjuntar el archivo: usa una foto o un PDF."
                    }
                }
            } header: {
                Text("Recibos")
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Gasto")
        .inlineTitle()
        .confirmationDialog("¿Quitar este recibo?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { attachment in
            Button("Quitar \(attachment.filename)", role: .destructive) { remove(attachment) }
        } message: { _ in
            Text("El gasto y su asiento no cambian; solo se borra el archivo adjunto.")
        }
    }

    private func remove(_ attachment: Attachment) {
        do {
            try Bookkeeper(context: context).removeAttachment(attachment)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo quitar el recibo."
        }
    }
}
