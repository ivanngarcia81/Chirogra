import ChirograCore
import ChirograData
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes › Plantilla de factura (canvas `AjustesPlantilla`, `MacAjustes` · Plantilla): la vista previa de la factura
/// tal como sale en el PDF; Apariencia (color de acento y estilo Clásica · Compacta); Logo (mostrarlo, elegir una imagen
/// o quitarla); qué datos de la empresa salen (EIN, dirección, teléfono); los valores de las facturas nuevas (términos y
/// mensaje) y la nota al pie. Cambia la empresa al momento (la vista previa lo refleja) y se guarda al salir, como el
/// resto de Ajustes. El PDF de facturas y estimados lo lee de `Company` (`InvoiceTemplate`).
struct InvoiceTemplateView: View {
    @Bindable var company: Company
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @State private var photo: PhotosPickerItem?
    @State private var importingLogo = false
    @State private var errorMessage: String?
    @State private var width: CGFloat = 0

    private var books: Bookkeeper { Bookkeeper(context: context) }

    /// La última factura emitida (o un ejemplo si aún no hay), con la plantilla actual.
    private var sample: SalesDocument {
        if let invoice = invoices.first(where: { $0.status != .draft && $0.status != .void }) {
            return SalesDocument(invoice: invoice)
        }
        return .sample(customerMessage: company.defaultInvoiceMessage)
    }

    var body: some View {
        SettingsForm {
            if let errorMessage {
                SettingsSection(plain: true) { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            SettingsSection(plain: true) {
                preview
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            SettingsSection {
                swatches
                LabeledContent("Estilo") {
                    Picker("Estilo", selection: $company.invoiceStyleRaw) {
                        Text("Clásica").tag(InvoiceStyle.classic.rawValue)
                        Text("Compacta").tag(InvoiceStyle.compact.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                #if os(iOS)
                .labeledContentStyle(.automatic)
                #endif
            } header: {
                SectionLabel(text: String(localized: "Apariencia"))
            }
            SettingsSection {
                Toggle("Mostrar logo", isOn: $company.invoiceShowLogo)
                logoRow
                #if os(iOS)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(company.logo == nil ? "Elegir de Fotos…" : "Cambiar desde Fotos…", systemImage: "photo")
                }
                #endif
                Button(company.logo == nil ? "Elegir imagen…" : "Cambiar imagen…", systemImage: "folder") { importingLogo = true }
                if company.logo != nil {
                    Button("Quitar logo", systemImage: "trash", role: .destructive, action: removeLogo)
                }
            } header: {
                SectionLabel(text: String(localized: "Logo"))
            } footer: {
                Text("Sin logo, la factura lleva tus iniciales en el color de la plantilla. La imagen se reduce a 512 px.")
            }
            SettingsSection {
                Toggle("Mostrar ID fiscal (EIN)", isOn: $company.invoiceShowEIN)
                Toggle("Mostrar dirección", isOn: $company.invoiceShowAddress)
                Toggle("Mostrar teléfono", isOn: $company.invoiceShowPhone)
            } header: {
                SectionLabel(text: String(localized: "Datos de la empresa"))
            } footer: {
                Text("Salen en el encabezado de tus facturas y estimados. Se editan en Perfil de la empresa.")
            }
            SettingsSection {
                SettingsPicker("Términos predeterminados", selection: $company.defaultPaymentTermsDays) {
                    Text("Al recibir").tag(0)
                    Text("Neto 15").tag(15)
                    Text("Neto 30").tag(30)
                    Text("Neto 60").tag(60)
                }
                SettingsTextArea(title: "Mensaje por defecto", text: $company.defaultInvoiceMessage,
                                 prompt: Text("Gracias por su preferencia."))
            } header: {
                SectionLabel(text: String(localized: "Facturas nuevas"))
            } footer: {
                Text("Con estos términos y este mensaje nacen las facturas y los estimados nuevos (los del cliente mandan si los tiene).")
            }
            SettingsSection {
                SettingsTextArea(title: "Nota al pie", text: $company.invoiceFooter, prompt: Text("Pago por transferencia a la cuenta…"))
            } header: {
                SectionLabel(text: String(localized: "Nota al pie"))
            } footer: {
                Text("Aparece al final de cada factura, junto a los términos.")
            }
        }
        .toggleStyle(.switch)
        .screenBackground()
        .modifier(TemplateTitle(embedded: embedded))
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $importingLogo, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): importLogo(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onDisappear { try? context.save() }
        #if DEBUG
        // `-qa.logo <ruta>`: pone el logo de un archivo (dentro del contenedor de la app) sin el selector.
        .task {
            guard let path = UserDefaults.standard.string(forKey: "qa.logo") else { return }
            importLogo(from: URL(filePath: path))
        }
        #endif
    }

    // MARK: Vista previa

    /// Canvas: la hoja sobre una tarjeta, con la cabecera, la tabla y el total en el color elegido.
    private var preview: some View {
        let document = sample
        let pages = InvoicePDF.pages(for: document, company: company)
        return VStack(spacing: 8) {
            Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            DocumentPageThumbnail(document: document, company: company, lines: pages.first ?? [], pageCount: pages.count,
                                  width: min(max(width - 64, 120), 360))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Vista previa de la plantilla")
            Text("Vista previa con \(document.number)").font(.footnote).foregroundStyle(Palette.ink2)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .card(padding: 0)
    }

    /// Los cinco colores del canvas (Tinta, Grafito, Cobre, Petróleo, Bosque) como botones de opción de 44 pt.
    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(InvoiceAccent.allCases, id: \.self) { accent in
                let selected = company.invoiceAccent == accent
                Button { company.invoiceAccentHex = accent.hex } label: {
                    Circle()
                        .fill(Color(invoiceHex: accent.hex) ?? .gray)
                        .padding(4)
                        .overlay(Circle().strokeBorder(selected ? (Color(invoiceHex: accent.hex) ?? .gray) : .clear, lineWidth: 2.5))
                        .frame(width: Self.swatch, height: Self.swatch)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accent.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(minHeight: Metrics.target)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color de la plantilla")
    }

    #if os(macOS)
    private static let swatch: CGFloat = 30
    #else
    private static let swatch: CGFloat = 44
    #endif

    @ViewBuilder
    private var logoRow: some View {
        HStack(spacing: 12) {
            if let data = company.logo?.data {
                CompanyLogoImage(data: data)
                    .frame(width: 56, height: 40)
                    .accessibilityLabel("Logo actual")
                Text(company.logo?.filename ?? "").foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
            } else {
                Text(Initials.from(company.displayName))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(invoiceHex: company.invoiceAccentHex) ?? Palette.brandFill,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text("Sin logo · se usan tus iniciales").foregroundStyle(Palette.ink2)
            }
        }
        .frame(minHeight: Metrics.target)
    }

    // MARK: Logo

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first ?? .png
            try books.setCompanyLogo(data, filename: "logo.\(type.preferredFilenameExtension ?? "png")", contentType: type)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        photo = nil
    }

    private func importLogo(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension) ?? .image
            try books.setCompanyLogo(data, filename: url.lastPathComponent, contentType: type)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeLogo() {
        do { try books.removeCompanyLogo(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}

extension InvoiceAccent {
    /// Nombre del color (canvas `AjustesPlantilla`).
    var title: String {
        switch self {
        case .ink: String(localized: "Tinta")
        case .graphite: String(localized: "Grafito")
        case .copper: String(localized: "Cobre")
        case .petroleum: String(localized: "Petróleo")
        case .forest: String(localized: "Bosque")
        }
    }
}

/// Título de la página abierta encima (pequeño y centrado); dentro de `SettingsWideView`, el de la ventana.
private struct TemplateTitle: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle("Plantilla de factura").inlineTitle() }
    }
}
