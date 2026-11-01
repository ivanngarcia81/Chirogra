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
        NavigationLink { DataAndSecurityView() } label: { Label("iCloud, copias y seguridad", systemImage: "icloud") }
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
    var body: some View {
        Form {
            Section {
                // El nombre de la moneda lo da el sistema en el idioma y la región del teléfono.
                LabeledContent("Moneda", value: Locale.current.localizedString(forCurrencyCode: company.currencyCode)
                    .map { "\(company.currencyCode) · \($0)" } ?? company.currencyCode)
                LabeledContent("Ejemplo de importe", value: Int64(4_821_540).money)
                LabeledContent("Ejemplo de fecha", value: Date.now.formatted(date: .numeric, time: .omitted))
            } footer: {
                Text("Los formatos siguen la región de tu dispositivo (Ajustes › General › Idioma y región).")
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
        .navigationTitle("iCloud, copias y seguridad")
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
