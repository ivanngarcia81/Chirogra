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

extension View {
    /// Elegir un PDF o una imagen del disco (recibo o copia del W-9) y entregarlo como `ReceiptFile`.
    func receiptFileImporter(isPresented: Binding<Bool>, onPick: @escaping (ReceiptFile) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let file = try? ReceiptFile(url: url, fallback: .data) else { return }
            onPick(file)
        }
    }

    /// «¿Quitar este recibo?» mientras `attachment` tenga uno (detalle del gasto e inspector del Mac).
    func receiptRemovalDialog(_ attachment: Binding<Attachment?>, remove: @escaping (Attachment) -> Void) -> some View {
        confirmationDialog("¿Quitar este recibo?", isPresented: Binding(get: { attachment.wrappedValue != nil }, set: { if !$0 { attachment.wrappedValue = nil } }),
                            titleVisibility: .visible, presenting: attachment.wrappedValue) { target in
            Button("Quitar \(target.filename)", role: .destructive) { remove(target) }
        } message: { _ in
            Text("El gasto y su asiento no cambian; solo se borra el archivo adjunto.")
        }
    }
}

/// Botones para adjuntar un recibo: escanearlo con la cámara (iPhone y iPad, `DocumentScannerView`), foto de la
/// fototeca o archivo (imagen o PDF). En «Nuevo gasto», el recibo elegido se lee y rellena el formulario
/// (`Receipts/ReceiptReader.swift`).
struct ReceiptPickerButtons: View {
    /// Textos cortos para la zona del recibo de pantallas anchas (`MacGastoNuevo`).
    var short = false
    /// Objetivo del recorrido: va en el primer botón y no en el grupo. Con `.id` sobre los tres, el formulario los
    /// juntaba en una sola fila, amontonados y centrados (iPhone del usuario, build 56; venía del 54).
    var objetivo: String? = nil
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
                .modifier(ObjetivoDelRecorrido(id: objetivo))
        }
        #endif
        PhotosPicker(selection: $photo, matching: .images) {
            Label(short ? String(localized: "Elegir foto") : String(localized: "Adjuntar foto del recibo"), systemImage: "photo.on.rectangle")
        }
        .modifier(ObjetivoDelRecorrido(id: scannerShown ? nil : objetivo))
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
            .receiptFileImporter(isPresented: $importing, onPick: onPick)
    }

    private var scannerShown: Bool {
        #if os(iOS)
        DocumentScanner.isAvailable
        #else
        false
        #endif
    }
}

/// `.recorridoObjetivo` + `.id` solo si hay objetivo.
private struct ObjetivoDelRecorrido: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id { content.recorridoObjetivo(id).id(id) } else { content }
    }
}

/// Zona del recibo de «Nuevo gasto» en iPad y Mac (canvas `MacGastoNuevo`): se arrastra una foto o un PDF, o se elige;
/// debajo, los archivos ya elegidos con «Quitar».
struct ReceiptDropPanel: View {
    @Binding var receipts: [ReceiptFile]
    @State private var isTargeted = false
    @State private var previewing = ReceiptPreview()

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

            ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                HStack(spacing: 10) {
                    // Como en el detalle del gasto (Eric, Beta Family, build 55): clic para verlo en Vista Rápida.
                    Button { previewing.show(receipts, from: index) } label: {
                        HStack(spacing: 10) {
                            ReceiptThumbnail(data: receipt.data, contentType: receipt.type.identifier, side: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(receipt.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                                Text("\(Int64(receipt.data.count).formatted(.byteCount(style: .file))) · adjunto")
                                    .font(.footnote).foregroundStyle(Palette.ink2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver recibo \(receipt.name)")
                    .accessibilityHint("Abre el archivo a pantalla completa.")
                    .help("Ver recibo")
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
        .receiptPreview($previewing)
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
    @State private var previewing = ReceiptPreview()

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
        .receiptRemovalDialog($removing, remove: remove)
        .receiptPreview($previewing)
    }

    /// Beneficiario, cifra y «Categoría · fecha», como la cabecera de la factura (repaso visual, build 56). Sin el
    /// icono de la categoría: la categoría ya va en la línea de abajo y, centrado encima, alargaba la cabecera.
    private var header: some View {
        let lines = expense.sortedLines
        let categoryText = lines.count > 1 ? String(localized: "Varias categorías") : (category ?? String(localized: "Sin categoría"))
        return DetailSummary(name: title, amount: expense.total.money, struck: expense.isVoid) {
            if let status = ExpenseStatus(expense) { status.chip(compact: false) }
            DetailSummaryLine(text: "\(categoryText) · \(expense.date.shortDate)")
        }
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
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                AdaptiveRow {
                    // Eric, Beta Family, build 55: tocar la miniatura o la fila abre el recibo en Vista Rápida (zoom,
                    // deslizar entre los recibos del gasto). Botón propio y sin estilo de fila, para que Compartir y
                    // Quitar sigan siendo botones aparte.
                    Button { previewing.show(attachments, from: index) } label: {
                        HStack(spacing: 12) {
                            ReceiptThumbnail(data: attachment.data, contentType: attachment.contentType, side: 48)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.filename).lineLimit(2)
                                Text(attachment.createdAt.shortDate).font(.footnote).foregroundStyle(Palette.ink2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver recibo \(attachment.filename)")
                    .accessibilityHint("Abre el archivo a pantalla completa.")
                    .help("Ver recibo")
                } trailing: {
                    HStack(spacing: 16) { attachmentActions(attachment) }
                }
                .swipeActions {
                    Button("Quitar", systemImage: "trash", role: .destructive) { removing = attachment }
                }
                .contextMenu {
                    if attachment.data != nil {
                        Button("Ver recibo", systemImage: "eye") { previewing.show(attachments, from: index) }
                    }
                    Button("Quitar recibo", systemImage: "trash", role: .destructive) { removing = attachment }
                }
            }
            ReceiptPickerButtons { attach($0) }
        } header: {
            SectionLabel(text: String(localized: "Recibo"))
        } footer: {
            if attachments.isEmpty {
                Text("Guarda el recibo: el IRS pide conservarlo.")
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
