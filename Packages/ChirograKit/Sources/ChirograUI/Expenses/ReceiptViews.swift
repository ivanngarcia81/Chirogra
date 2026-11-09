import ChirograData
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Un recibo elegido o arrastrado, todavía sin guardar: el archivo tal cual, su nombre y su tipo. También se recibe al
/// soltar una foto o un PDF sobre la zona del recibo (canvas `MacGastoNuevo`: «Arrastra una foto o un PDF»).
nonisolated struct ReceiptFile: Identifiable, Transferable {
    let id = UUID()
    let data: Data
    let name: String
    let type: UTType

    init(data: Data, name: String, type: UTType) {
        self.data = data
        self.name = name
        self.type = type
    }

    init(url: URL, fallback: UTType) throws {
        self.init(data: try Data(contentsOf: url), name: url.lastPathComponent,
                  type: UTType(filenameExtension: url.pathExtension) ?? fallback)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .pdf) { try ReceiptFile(url: $0.file, fallback: .pdf) }
        FileRepresentation(importedContentType: .image) { try ReceiptFile(url: $0.file, fallback: .image) }
    }
}

/// Botones para adjuntar un recibo: escanearlo con la cámara (iPhone y iPad, `DocumentScannerView`), foto de la
/// fototeca o archivo (imagen o PDF). En «Nuevo gasto», el recibo elegido se lee y rellena el formulario
/// (`Receipts/ReceiptReader.swift`).
struct ReceiptPickerButtons: View {
    /// Textos cortos para la zona del recibo de pantallas anchas (`MacGastoNuevo`).
    var short = false
    let onPick: (ReceiptFile) -> Void
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var scanning = false

    var body: some View {
        #if os(iOS)
        if DocumentScanner.isAvailable {
            Button(short ? String(localized: "Escanear") : String(localized: "Escanear recibo"), systemImage: "doc.viewfinder") { scanning = true }
                .fullScreenCover(isPresented: $scanning) {
                    DocumentScannerView { file in
                        scanning = false
                        if let file { onPick(file) }
                    }
                    .ignoresSafeArea()
                }
        }
        #endif
        PhotosPicker(selection: $photo, matching: .images) {
            Label(short ? String(localized: "Elegir foto") : String(localized: "Adjuntar foto del recibo"), systemImage: "photo.on.rectangle")
        }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self) {
                    onPick(ReceiptFile(data: data, name: "recibo.jpg", type: photo.supportedContentTypes.first ?? .jpeg))
                }
                self.photo = nil
            }
        }
        Button(short ? String(localized: "Elegir archivo…") : String(localized: "Adjuntar archivo (PDF o imagen)"), systemImage: "doc.badge.plus") { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let file = try? ReceiptFile(url: url, fallback: .data) else { return }
                onPick(file)
            }
    }
}

/// Zona del recibo de «Nuevo gasto» en iPad y Mac (canvas `MacGastoNuevo`): se arrastra una foto o un PDF, o se elige;
/// debajo, los archivos ya elegidos con «Quitar».
struct ReceiptDropPanel: View {
    @Binding var receipts: [ReceiptFile]
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recibo").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                Image(systemName: "doc.viewfinder").font(.largeTitle).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                Text("Arrastra una foto o un PDF").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("JPG, PNG, HEIC o PDF").font(.footnote).foregroundStyle(Palette.ink2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ReceiptPickerButtons(short: true) { receipts.append($0) } }
                    VStack(spacing: 8) { ReceiptPickerButtons(short: true) { receipts.append($0) } }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .background(isTargeted ? Palette.brandWash : Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
                .strokeBorder(isTargeted ? Palette.brand : Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))

            ForEach(receipts) { receipt in
                HStack(spacing: 10) {
                    ReceiptThumbnail(data: receipt.data, contentType: receipt.type.identifier, side: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(receipt.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                        Text("\(Int64(receipt.data.count).formatted(.byteCount(style: .file))) · adjunto")
                            .font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 6)
                    Button("Quitar") { receipts.removeAll { $0.id == receipt.id } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("Quitar \(receipt.name)")
                }
            }
            Text("Chirogra lee el recibo en este aparato y rellena el formulario: revisa los datos antes de guardar. El archivo se guarda junto al gasto tal como lo subes.")
                .font(.footnote).foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dropDestination(for: ReceiptFile.self) { files, _ in
            receipts += files
            return !files.isEmpty
        } isTargeted: { isTargeted = $0 }
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
                Image(systemName: "doc.richtext").font(.title2).foregroundStyle(Palette.ink2)
            }
        }
        .frame(width: side, height: side)
        .background(Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

/// Detalle de un gasto (canvas `MacGastos`, inspector «Gasto»): icono de la categoría con el beneficiario y el importe,
/// «Detalles» en filas «etiqueta gris · valor», el recibo y el historial de asientos. El título es el beneficiario.
/// «Editar» abre el editor; en un gasto contabilizado, guardar revierte su asiento y registra uno nuevo. Un gasto «por
/// confirmar» (sin asiento) se registra desde aquí.
struct ExpenseDetailView: View {
    @Bindable var expense: Expense
    @Environment(\.modelContext) private var context
    @CompanyQuery private var accounts: [Account]
    @State private var errorMessage: String?
    @State private var removing: Attachment?
    @State private var isTargeted = false
    @State private var editing = false

    private func accountName(_ id: UUID?) -> String? { accounts.first { $0.id == id }?.name }
    private var category: String? { expense.sortedLines.first.flatMap { accountName($0.accountID) } }
    private var title: String { expense.payee.isEmpty ? String(localized: "Gasto") : expense.payee }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section { header }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            if expense.isPendingConfirmation { pendingSection }
            details
            receipts
            if expense.isPosted || expense.isVoid {
                ExpenseHistorySection(expense: expense)
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .recordTitle(title, section: String(localized: "Gasto"))
        .toolbar {
            if !expense.isVoid {
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { editing = true }.headerButton()
                }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { ExpenseEditorView(expense: expense) }.editorSheetSizing() }
        .dropDestination(for: ReceiptFile.self) { files, _ in
            files.forEach(attach)
            return !files.isEmpty
        } isTargeted: { isTargeted = $0 }
        .confirmationDialog("¿Quitar este recibo?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { attachment in
            Button("Quitar \(attachment.filename)", role: .destructive) { remove(attachment) }
        } message: { _ in
            Text("El gasto y su asiento no cambian; solo se borra el archivo adjunto.")
        }
    }

    /// Icono de la categoría, beneficiario y cifra (canvas: cuadrado de 36 pt, nombre semibold e importe de 24 bold).
    private var header: some View {
        HStack(spacing: 12) {
            LargeIconTile(systemImage: ExpenseCategoryStyle.symbol(for: category), color: ExpenseCategoryStyle.color(for: category))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(expense.total.money).font(.amount(28)).foregroundStyle(Palette.ink).strikethrough(expense.isVoid)
                if let status = ExpenseStatus(expense) { status.chip(compact: false) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        Section {
            LabeledContent("Fecha", value: expense.date.shortDate)
            if let vendor = expense.vendor { LabeledContent("Proveedor", value: vendor.name) }
            let lines = expense.sortedLines
            if lines.count == 1 {
                LabeledContent("Categoría", value: category ?? String(localized: "Sin categoría"))
            } else {
                ForEach(lines) { line in
                    LabeledContent(accountName(line.accountID) ?? String(localized: "Sin categoría"), value: line.amount.money)
                }
            }
            LabeledContent("Cuenta de pago", value: accounts.account(expense.paymentAccountID)?.paymentLabel ?? "—")
            LabeledContent("Método", value: PaymentMethodPicker.title(for: PaymentMethod(rawValue: expense.methodRaw) ?? .other,
                                                       paidFrom: accounts.account(expense.paymentAccountID)?.subtype))
            if expense.salesTaxIncluded > 0 {
                LabeledContent("Subtotal", value: expense.subtotalBeforeTax.money)
                LabeledContent("Impuesto incluido", value: expense.salesTaxIncluded.money)
            }
            if let customer = expense.customer { LabeledContent("Cliente o proyecto", value: customer.name) }
            if expense.recurringTemplateID != nil { LabeledContent("Origen", value: String(localized: "Recurrente")) }
            if !expense.memo.isEmpty { LabeledContent("Nota", value: expense.memo) }
        } header: {
            SectionLabel(text: String(localized: "Detalles"))
        }
    }

    @ViewBuilder
    private var receipts: some View {
        let attachments = (expense.attachments ?? []).sorted { $0.createdAt < $1.createdAt }
        Section {
            if attachments.isEmpty {
                HStack(spacing: 6) {
                    StatusDot(color: Palette.orange)
                    Text("Sin recibo").foregroundStyle(Palette.warning)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(attachments) { attachment in
                AdaptiveRow {
                    HStack(spacing: 12) {
                        ReceiptThumbnail(data: attachment.data, contentType: attachment.contentType, side: 48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.filename).lineLimit(2)
                            Text(attachment.createdAt.shortDate).font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    }
                } trailing: {
                    HStack(spacing: 16) { attachmentActions(attachment) }
                }
                .swipeActions {
                    Button("Quitar", systemImage: "trash", role: .destructive) { removing = attachment }
                }
                .contextMenu {
                    Button("Quitar recibo", systemImage: "trash", role: .destructive) { removing = attachment }
                }
            }
            ReceiptPickerButtons { attach($0) }
        } header: {
            SectionLabel(text: String(localized: "Recibo"))
        } footer: {
            if attachments.isEmpty {
                Text("Guarda el comprobante: el IRS pide conservarlo.")
            }
        }
        .listRowBackground(isTargeted ? Palette.brandWash : Palette.surface)
    }

    /// «Por confirmar»: lo generó una recurrente sin cargo automático y todavía no tiene asiento.
    private var pendingSection: some View {
        Section {
            Button("Registrar \(expense.total.money)", action: record).buttonStyle(.primary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } footer: {
            Text("Este gasto lo generó una recurrente sin cargo automático: revisa el importe (con «Editar» si cambió) y regístralo.")
        }
    }

    private func record() {
        do {
            try Bookkeeper(context: context).record(expense)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Compartir y quitar un recibo.
    @ViewBuilder
    private func attachmentActions(_ attachment: Attachment) -> some View {
        if let data = attachment.data {
            ShareLink(item: AttachmentFile(data: data, filename: attachment.filename, contentType: attachment.contentType),
                      preview: SharePreview(attachment.filename)) {
                Label("Compartir", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                    .frame(minWidth: Metrics.target, minHeight: Metrics.target)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Compartir \(attachment.filename)")
        }
        Button("Quitar", systemImage: "trash", role: .destructive) { removing = attachment }
            .labelStyle(.iconOnly)
            .frame(minWidth: Metrics.target, minHeight: Metrics.target)
            .buttonStyle(.borderless)
            .accessibilityLabel("Quitar \(attachment.filename)")
    }

    private func attach(_ file: ReceiptFile) {
        do {
            try Bookkeeper(context: context).attachReceipt(file.data, filename: file.name, contentType: file.type, to: expense)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "No se pudo adjuntar el archivo: usa una foto o un PDF.")
        }
    }

    private func remove(_ attachment: Attachment) {
        do {
            try Bookkeeper(context: context).removeAttachment(attachment)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "No se pudo quitar el recibo.")
        }
    }
}

/// Icono de cabecera de una ficha (canvas `MacGastos`, `MacCierre`: cuadrado de 36 pt, radio 9, símbolo blanco).
/// Como `IconTile`, pero más grande; candidato a subir al sistema.
struct LargeIconTile: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.5, weight: .medium))
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            .background(color, in: RoundedRectangle(cornerRadius: side * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}
