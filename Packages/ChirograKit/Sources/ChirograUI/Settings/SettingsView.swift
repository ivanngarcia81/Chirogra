import ChirograData
import SwiftData
import SwiftUI

/// Ajustes (canvas: `AjustesEmpresa`, `AjustesFormatos`, `AjustesDatos`).
/// "Usuarios y permisos" y "Plantilla de factura" no están en el MVP (DISEÑO §7.4).
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

/// Ajustes en iPad y Mac (canvas `MacAjustes`): secciones a la izquierda y su contenido a la derecha.
/// «Plantilla de factura» y el logotipo quedan para más adelante (DISEÑO §7.4).
struct SettingsWideView: View {
    enum Page: String, CaseIterable, Identifiable {
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
            case .profile: "building.2"
            case .formats: "dollarsign.circle"
            case .data: "icloud"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query private var companies: [Company]
    @State private var page: Page = .profile
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacPageTitle(String(localized: "Ajustes"))
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 2) {
                    ForEach(Page.allCases) { option in
                        Button { page = option; saved = false } label: {
                            Label(option.title, systemImage: option.symbol)
                                .font(.subheadline.weight(page == option ? .semibold : .medium))
                                .foregroundStyle(page == option ? Palette.brand : Palette.ink2)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(page == option ? Palette.brandWash : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == option ? .isSelected : [])
                    }
                }
                .padding(8)
                .frame(width: 260)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text(page.title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)
                    if let company = companies.first {
                        switch page {
                        case .profile: CompanyProfileGrid(company: company)
                        case .formats: FormatsView(company: company, embedded: true).scrollContentBackground(.hidden)
                        case .data: DataAndSecurityView(embedded: true).scrollContentBackground(.hidden)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .background(Palette.background)
        .navigationTitle("Ajustes")
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
}

/// Perfil de la empresa en dos columnas (`MacAjustes`), sin logotipo.
struct CompanyProfileGrid: View {
    @Bindable var company: Company

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menu<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 4)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
    }

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 14, alignment: .topLeading), GridItem(.flexible(), spacing: 14, alignment: .topLeading)]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    field(String(localized: "Nombre comercial")) { TextField("Nombre comercial", text: $company.displayName).fieldBox() }
                    field(String(localized: "Razón social")) { TextField("Razón social", text: $company.legalName).fieldBox() }
                    field(String(localized: "Tipo de entidad")) {
                        menu {
                            Picker("Tipo de entidad", selection: $company.entityTypeRaw) {
                                ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                            }
                        }
                    }
                    field(String(localized: "ID fiscal (EIN)")) { TextField("EIN (opcional)", text: $company.ein).fieldBox() }
                    field(String(localized: "Correo de facturación")) { TextField("Correo", text: $company.email).fieldBox() }
                    field(String(localized: "Teléfono")) { TextField("Teléfono", text: $company.phone).fieldBox() }
                }
                field(String(localized: "Dirección")) { TextField("Dirección", text: $company.address, axis: .vertical).lineLimit(1...3).fieldBox() }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    field(String(localized: "Estado")) {
                        menu {
                            Picker("Estado", selection: $company.state) {
                                Text("—").tag("")
                                ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    field(String(localized: "Inicio del año fiscal")) {
                        menu {
                            Picker("Inicio del año fiscal", selection: $company.fiscalYearStartMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(Calendar.current.standaloneMonthSymbols[month - 1].sentenceCased).tag(month)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct SettingsLinks: View {
    /// En «Más» del iPhone el perfil ya se abre desde la tarjeta de la empresa.
    var showsCompanyProfile = true
    @Query private var companies: [Company]

    var body: some View {
        if let company = companies.first {
            if showsCompanyProfile {
                NavigationLink { CompanyProfileView(company: company) } label: { Label("Perfil de la empresa", systemImage: "building.2") }
            }
            NavigationLink { FormatsView(company: company) } label: { Label("Moneda y formatos", systemImage: "dollarsign.circle") }
        }
        NavigationLink { DataAndSecurityView() } label: { Label("Datos y seguridad", systemImage: "icloud") }
    }
}

struct CompanyProfileView: View {
    @Bindable var company: Company
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                TextField("Nombre comercial", text: $company.displayName)
                TextField("Razón social", text: $company.legalName)
                Picker("Tipo de entidad", selection: $company.entityTypeRaw) {
                    ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                TextField("EIN (opcional)", text: $company.ein)
                Picker("Estado", selection: $company.state) {
                    Text("—").tag("")
                    ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                }
            }
            Section(title: "Contacto") {
                TextField("Correo", text: $company.email)
                TextField("Teléfono", text: $company.phone)
                TextField("Dirección", text: $company.address, axis: .vertical)
            }
            Section {
                Picker("Inicio del año fiscal", selection: $company.fiscalYearStartMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.standaloneMonthSymbols[month - 1].sentenceCased).tag(month)
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Perfil de la empresa")
        .headerTitle()
        .onDisappear { try? context.save() }
    }
}

struct FormatsView: View {
    let company: Company
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @Query private var invoices: [Invoice]

    var body: some View {
        Form {
            // `AjustesFormatos`: vista previa en color de marca de cómo se ven importes y fechas.
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    // La última factura emitida, con su importe y vencimiento reales; sin facturas, un ejemplo genérico.
                    let sample = invoices.filter { !$0.number.isEmpty }.max { $0.issueDate < $1.issueDate }
                    Text("Vista previa · Factura \(sample?.number ?? "F-0000")")
                        .font(.caption.weight(.semibold)).textCase(.uppercase).opacity(0.85)
                    Text((sample?.total ?? 255_805).money).font(.amount(30))
                    Text("Vence el \((sample?.dueDate ?? Date.now.addingTimeInterval(15 * 86_400)).formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: .app)))")
                        .font(.subheadline).opacity(0.9)
                }
                .foregroundStyle(Palette.onBrand)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .listRowInsets(EdgeInsets())
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            Section(title: "Moneda") {
                // El nombre de la moneda lo da el sistema en el idioma y la región del teléfono.
                LabeledContent("Moneda", value: Locale.current.localizedString(forCurrencyCode: company.currencyCode)
                    .map { "\(company.currencyCode) · \($0)" } ?? company.currencyCode)
            }
            Section {
                LabeledContent("Inicio del año fiscal", value: Calendar.current.standaloneMonthSymbols[max(0, min(11, company.fiscalYearStartMonth - 1))].sentenceCased)
                LabeledContent("Primer día de la semana", value: Calendar.current.standaloneWeekdaySymbols[Calendar.current.firstWeekday - 1].sentenceCased)
            } header: {
                SectionLabel(text: String(localized: "Fechas e idioma"))
            } footer: {
                Text("Los separadores, el formato de fecha y el idioma siguen la región y el idioma de tu dispositivo (Ajustes › General › Idioma y región).")
            }
        }
        .screenBackground()
        .modifier(TitleUnlessEmbedded(title: "Moneda y formatos", embedded: embedded))
    }
}

struct DataAndSecurityView: View {
    /// Dentro de `SettingsWideView`: el título de la ventana sigue siendo «Ajustes».
    var embedded = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var lockUnavailable = false

    var body: some View {
        Form {
            Section {
                Toggle("Sincronizar con iCloud", isOn: $iCloudSyncEnabled)
                // `AjustesDatos`: estado con un punto de color.
                Label {
                    Text(iCloudSyncEnabled ? String(localized: "Activado · iPhone, iPad y Mac") : String(localized: "Solo en este dispositivo"))
                } icon: {
                    Circle().fill(iCloudSyncEnabled ? Palette.positive : Palette.ink3).frame(width: 8, height: 8)
                }
                .font(.subheadline)
                .foregroundStyle(iCloudSyncEnabled ? Palette.positive : Palette.ink3)
            } header: {
                SectionLabel(text: "iCloud")
            } footer: {
                Text("Tus libros viajan cifrados en tu cuenta privada de iCloud entre tu iPhone, iPad y Mac. El cambio se aplica al volver a abrir la app.")
            }
            Section {
                Toggle("Bloquear con Face ID o Touch ID", isOn: Binding(
                    get: { appLockEnabled },
                    set: { enabled in
                        lockUnavailable = enabled && !AppLock.isAvailable
                        appLockEnabled = enabled && !lockUnavailable
                    }
                ))
            } footer: {
                if lockUnavailable {
                    Text("Para bloquear Chirogra, primero configura un código, Face ID o Touch ID en los ajustes del dispositivo.")
                        .foregroundStyle(Palette.negative)
                } else {
                    Text("Chirogra se bloquea cada vez que pasa a segundo plano.")
                }
            }
            Section {
                LabeledContent("Copia de seguridad exportable", value: String(localized: "Próximamente"))
            } footer: {
                Text("Pronto podrás guardar una copia de tus libros en un archivo y restaurarla, sin depender de iCloud.")
            }
        }
        .screenBackground()
        .modifier(TitleUnlessEmbedded(title: "Datos y seguridad", embedded: embedded))
    }
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

private struct TitleUnlessEmbedded: ViewModifier {
    let title: LocalizedStringKey
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded { content } else { content.navigationTitle(title).headerTitle() }
    }
}
