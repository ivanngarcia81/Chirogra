import ChirograData
import SwiftData
import SwiftUI

/// Ajustes (canvas `AjustesEmpresa`, `AjustesFormatos`, `AjustesDatos`, `MacAjustes`): formularios agrupados del sistema.
/// «Usuarios y permisos» es de fase 2 y «Plantilla de factura» no está en el MVP (DISEÑO §7.4): no salen.
struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacAjustes` en iPad y Mac (hasta AX3); la lista del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        if isWide {
            SettingsWideView()
        } else {
            List { SettingsLinks() }
                .listRowBackground(Palette.surface)
                .screenBackground()
                .navigationTitle("Ajustes")
                .headerTitle()
        }
    }
}

/// Páginas de Ajustes, con su icono de color como en Ajustes del sistema (canvas `MacAjustes`).
enum SettingsPage: String, CaseIterable, Identifiable {
    case profile, formats, data
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: String(localized: "Perfil de la empresa")
        case .formats: String(localized: "Moneda y formatos")
        case .data: String(localized: "iCloud, copias y seguridad")
        }
    }

    var symbol: String {
        switch self {
        case .profile: "building.2.fill"
        case .formats: "dollarsign"
        case .data: "icloud.fill"
        }
    }

    var color: Color {
        switch self {
        case .profile: Palette.blue
        case .formats: Palette.green
        case .data: Palette.teal
        }
    }
}

/// Ajustes en iPad y Mac (canvas `MacAjustes`): las páginas a la izquierda, con la elegida rellena de Tinta y texto
/// blanco, y su formulario a la derecha, de 640 pt como máximo.
struct SettingsWideView: View {
    @Environment(\.modelContext) private var context
    @Query private var companies: [Company]
    @State private var page: SettingsPage = .profile
    @State private var saved = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsPage.allCases) { option in pageRow(option) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: Self.navWidth)
            .scrollIndicators(.never)
            Divider()
            Group {
                if let company = companies.first {
                    switch page {
                    case .profile: CompanyProfileView(company: company, embedded: true)
                    case .formats: FormatsView(company: company, embedded: true)
                    case .data: DataAndSecurityView(embedded: true)
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        #if os(macOS)
        .navigationTitle(page.title)
        .navigationSubtitle(String(localized: "Ajustes"))
        #else
        .navigationTitle("Ajustes")
        #endif
        .headerTitle()
        .toolbar {
            if page == .profile {
                ToolbarItem(placement: .primaryAction) {
                    Button(saved ? String(localized: "Guardado ✓") : String(localized: "Guardar cambios")) {
                        try? context.save()
                        saved = true
                    }
                    .tint(saved ? Palette.positive : Palette.ink)
                }
            }
        }
        .onDisappear { try? context.save() }
    }

    private func pageRow(_ option: SettingsPage) -> some View {
        let selected = page == option
        return Button { page = option; saved = false } label: {
            HStack(spacing: 8) {
                IconTile(systemImage: option.symbol, foreground: option.color)
                Text(option.title)
                    .foregroundStyle(selected ? Palette.onBrandFill : Palette.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: Self.rowHeight)
            .background(selected ? Palette.brandFill : .clear, in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    #if os(macOS)
    private static let navWidth: CGFloat = 220
    private static let rowHeight: CGFloat = 30
    private static let rowRadius: CGFloat = 7
    #else
    private static let navWidth: CGFloat = 260
    private static let rowHeight: CGFloat = 44
    private static let rowRadius: CGFloat = 12
    #endif
}

/// Lista de Ajustes de pantallas estrechas: filas con el icono de color de cada página.
struct SettingsLinks: View {
    /// En «Más» del iPhone el perfil ya se abre desde la fila de la empresa.
    var showsCompanyProfile = true
    @Query private var companies: [Company]

    var body: some View {
        if let company = companies.first {
            if showsCompanyProfile {
                link(.profile) { CompanyProfileView(company: company) }
            }
            link(.formats) { FormatsView(company: company) }
        }
        link(.data) { DataAndSecurityView() }
    }

    private func link<Destination: View>(_ page: SettingsPage, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                IconTile(systemImage: page.symbol, foreground: page.color)
                Text(page.title).foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Campo de texto de un formulario de Ajustes con su nombre a la izquierda (canvas: «Nombre comercial · Ríos…»).
/// En iOS el `TextField` de un formulario no muestra su título, así que va en un `LabeledContent` con el estilo del
/// sistema (el de la app fija el ancho del valor y el campo quedaba del tamaño del texto de ayuda).
private struct SettingsField: View {
    enum Kind { case text, email, phone }

    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey = "Opcional"
    var kind: Kind = .text

    var body: some View {
        #if os(macOS)
        TextField(title, text: $text, prompt: Text(prompt))
        #else
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .keyboardType(kind == .email ? .emailAddress : kind == .phone ? .phonePad : .default)
                .textContentType(kind == .email ? .emailAddress : kind == .phone ? .telephoneNumber : nil)
                .textInputAutocapitalization(kind == .email ? .never : .words)
                .autocorrectionDisabled(kind != .text)
        }
        .labeledContentStyle(.automatic)
        #endif
    }
}

/// Perfil de la empresa (canvas `AjustesEmpresa`, `MacAjustes` · Perfil): identidad, contacto, dirección y año fiscal.
/// Se guarda al salir (y con «Guardar cambios» en iPad y Mac). El logotipo queda para después.
struct CompanyProfileView: View {
    @Bindable var company: Company
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                SettingsField(title: "Nombre comercial", text: $company.displayName, prompt: "Obligatorio")
                SettingsField(title: "Razón social", text: $company.legalName, prompt: "Obligatorio")
                Picker("Tipo de entidad", selection: $company.entityTypeRaw) {
                    ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                SettingsField(title: "ID fiscal (EIN)", text: $company.ein)
            } header: {
                SectionLabel(text: String(localized: "Identidad"))
            }
            Section {
                SettingsField(title: "Correo", text: $company.email, prompt: "Correo de facturación", kind: .email)
                SettingsField(title: "Teléfono", text: $company.phone, kind: .phone)
            } header: {
                SectionLabel(text: String(localized: "Contacto"))
            }
            Section {
                TextField("Dirección", text: $company.address, prompt: Text("Calle, ciudad y código postal"), axis: .vertical)
                    .lineLimit(1...4)
                Picker("Estado de EE. UU.", selection: $company.state) {
                    Text("—").tag("")
                    ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                SectionLabel(text: String(localized: "Dirección"))
            } footer: {
                Text("Estos datos aparecen en el encabezado de tus facturas.")
            }
            Section {
                Picker("Inicio del año fiscal", selection: $company.fiscalYearStartMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.standaloneMonthSymbols[month - 1].sentenceCased).tag(month)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .modifier(TitleUnlessEmbedded(title: "Perfil de la empresa", embedded: embedded))
        .onDisappear { try? context.save() }
    }
}

/// Moneda y formatos (canvas `AjustesFormatos`): una vista previa con la última factura y cómo se escriben importes,
/// fechas e idioma. Siguen la región y el idioma del dispositivo (decisión del usuario), así que se muestran, no se eligen.
struct FormatsView: View {
    let company: Company
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Query private var invoices: [Invoice]

    var body: some View {
        Form {
            Section {
                // La última factura emitida, con su importe y vencimiento reales; sin facturas, un ejemplo genérico.
                let sample = invoices.filter { !$0.number.isEmpty }.max { $0.issueDate < $1.issueDate }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vista previa · Factura \(sample?.number ?? "F-0000")")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                    Text((sample?.total ?? 255_805).money).font(.amount(34)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Vence el \((sample?.dueDate ?? Date.now.addingTimeInterval(15 * 86_400)).formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: .app)))")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            Section {
                // El nombre de la moneda lo da el sistema en el idioma y la región del teléfono.
                LabeledContent("Moneda base", value: Locale.current.localizedString(forCurrencyCode: company.currencyCode)
                    .map { "\(company.currencyCode) · \($0.sentenceCased)" } ?? company.currencyCode)
                LabeledContent("Separadores", value: Decimal(string: "1234.56")?.formatted(.number.precision(.fractionLength(2))) ?? "1,234.56")
            } header: {
                SectionLabel(text: String(localized: "Moneda"))
            }
            Section {
                LabeledContent("Formato de fecha", value: Date.now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: .app)))
                LabeledContent("Idioma", value: languageName)
                LabeledContent("Inicio del año fiscal", value: Calendar.current.standaloneMonthSymbols[max(0, min(11, company.fiscalYearStartMonth - 1))].sentenceCased)
                LabeledContent("Primer día de la semana", value: Calendar.current.standaloneWeekdaySymbols[Calendar.current.firstWeekday - 1].sentenceCased)
            } header: {
                SectionLabel(text: String(localized: "Fechas e idioma"))
            } footer: {
                Text("Los separadores, el formato de fecha y el idioma siguen la región y el idioma de tu dispositivo (Ajustes › General › Idioma y región).")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .modifier(TitleUnlessEmbedded(title: "Moneda y formatos", embedded: embedded))
    }

    /// Idioma de la app («Español», «English»), en ese mismo idioma.
    private var languageName: String {
        let code = Locale.appText.language.languageCode?.identifier ?? "es"
        return (Locale(identifier: code).localizedString(forLanguageCode: code) ?? code).sentenceCased
    }
}

/// Datos y seguridad (canvas `AjustesDatos`): iCloud, copias y bloqueo, como filas con icono de color. Las copias
/// exportables y la exportación de datos llegan más adelante; no se dibujan como si ya existieran.
struct DataAndSecurityView: View {
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var lockUnavailable = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "icloud.fill", foreground: Palette.blue)
                    Toggle(isOn: $iCloudSyncEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sincronizar con iCloud")
                            // `AjustesDatos`: estado con un punto de color.
                            HStack(spacing: 6) {
                                StatusDot(color: iCloudSyncEnabled ? Palette.green : Palette.gray)
                                Text(iCloudSyncEnabled ? String(localized: "Activado · iPhone, iPad y Mac") : String(localized: "Solo en este dispositivo"))
                            }
                            .font(Self.detailFont)
                            .foregroundStyle(iCloudSyncEnabled ? Palette.positive : Palette.ink2)
                        }
                    }
                }
            } header: {
                SectionLabel(text: "iCloud")
            } footer: {
                Text("Tus libros viajan cifrados en tu cuenta privada de iCloud entre tu iPhone, iPad y Mac. El cambio se aplica al volver a abrir la app.")
            }
            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "clock.arrow.circlepath", foreground: Palette.green)
                    LabeledContent("Copia de seguridad exportable", value: String(localized: "Próximamente"))
                }
            } header: {
                SectionLabel(text: String(localized: "Copias de seguridad"))
            } footer: {
                Text("Pronto podrás guardar una copia de tus libros en un archivo y restaurarla, sin depender de iCloud.")
            }
            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "faceid", foreground: Palette.green)
                    Toggle("Bloquear con Face ID o Touch ID", isOn: Binding(
                        get: { appLockEnabled },
                        set: { enabled in
                            lockUnavailable = enabled && !AppLock.isAvailable
                            appLockEnabled = enabled && !lockUnavailable
                        }
                    ))
                }
            } header: {
                SectionLabel(text: String(localized: "Seguridad"))
            } footer: {
                if lockUnavailable {
                    Text("Para bloquear Chirogra, primero configura un código, Face ID o Touch ID en los ajustes del dispositivo.")
                        .foregroundStyle(Palette.negative)
                } else {
                    Text("Chirogra se bloquea cada vez que pasa a segundo plano.")
                }
            }
        }
        .formStyle(.grouped)
        // Interruptores como los del canvas (en el Mac, el de casilla salía por defecto en los formularios).
        .toggleStyle(.switch)
        .screenBackground()
        .modifier(TitleUnlessEmbedded(title: "Datos y seguridad", embedded: embedded))
    }

    #if os(macOS)
    private static let detailFont = Font.subheadline
    #else
    private static let detailFont = Font.footnote
    #endif
}

extension EntityType {
    var title: String {
        switch self {
        case .soleProprietorship: String(localized: "Negocio propio (sole proprietorship)")
        case .llc: String(localized: "LLC")
        case .sCorp: String(localized: "S corporation")
        case .cCorp: String(localized: "C corporation")
        case .partnership: String(localized: "Sociedad (partnership)")
        }
    }
}

enum USState {
    static let all = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
        "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "PR",
        "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]
}

/// Título de una página de Ajustes abierta encima (pequeño y centrado, como en el canvas); dentro de
/// `SettingsWideView`, ninguno: manda el de la ventana.
private struct TitleUnlessEmbedded: ViewModifier {
    let title: LocalizedStringKey
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle(title).inlineTitle() }
    }
}
