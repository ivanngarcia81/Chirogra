import ChirograData
import SwiftData
import SwiftUI

/// Ajustes (canvas: `AjustesEmpresa`, `AjustesFormatos`, `AjustesDatos`).
/// "Usuarios y permisos" y "Plantilla de factura" no están en el MVP (DISEÑO §7.4).
struct SettingsView: View {
    var body: some View {
        List { SettingsLinks() }
            .listRowBackground(Palette.surface)
            .screenBackground()
            .navigationTitle("Ajustes")
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
        .onDisappear { try? context.save() }
    }
}

struct FormatsView: View {
    let company: Company
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
        .navigationTitle("Moneda y formatos")
    }
}

struct DataAndSecurityView: View {
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
        .navigationTitle("Datos y seguridad")
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
