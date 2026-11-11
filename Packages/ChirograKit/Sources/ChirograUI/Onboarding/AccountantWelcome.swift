import ChirograData
import SwiftData
import SwiftUI

// MARK: - Para quién lleva los libros (1.2, canvas «Chirogra — Contadores», opción A)
//
// La última página de la bienvenida pregunta si se llevan los libros del propio negocio o los de clientes. «Mi
// negocio» sigue como siempre (alta de la empresa). «Los de mis clientes» abre «Chirogra para contadores»: qué gana,
// «Dar de alta mi primer cliente» (el alta con textos de cliente) o «Importar copia de un cliente». Después del alta,
// la pantalla de planes sale con el de contadores (`RootView`). La elección se guarda en este aparato
// (`WelcomeAudience.key`) solo para ese camino.

enum WelcomeAudience: String, CaseIterable, Identifiable {
    case own
    case accountant

    var id: String { rawValue }
    /// Ajuste de este aparato con la elección de la bienvenida.
    static let key = "welcome.audience"

    static var current: WelcomeAudience {
        UserDefaults.standard.string(forKey: key).flatMap(WelcomeAudience.init(rawValue:)) ?? .own
    }

    var title: String {
        switch self {
        case .own: String(localized: "Mi negocio")
        case .accountant: String(localized: "Los de mis clientes")
        }
    }

    var detail: String {
        switch self {
        case .own: String(localized: "Llevo los libros de mi empresa: facturas, gastos y sales tax.")
        case .accountant: String(localized: "Soy contador o bookkeeper y llevo varias empresas.")
        }
    }

    var systemImage: String {
        switch self {
        case .own: "storefront"
        case .accountant: "building.2"
        }
    }

    var color: Color {
        switch self {
        case .own: Palette.orange
        case .accountant: Palette.brand
        }
    }
}

/// Última página de la bienvenida: «¿Para quién llevas los libros?» con las dos tarjetas.
struct AudiencePage: View {
    @Binding var selection: WelcomeAudience
    let otherDevice: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Circle()
                    .fill(Palette.brandWash)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "building.2").font(.system(size: 50, weight: .regular)).foregroundStyle(Palette.brand)
                    }
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("¿Para quién llevas los libros?")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Así te enseñamos lo que necesitas desde el principio.")
                        .font(.body)
                        .foregroundStyle(Palette.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
                VStack(spacing: 12) {
                    ForEach(WelcomeAudience.allCases) { option in card(option) }
                }
                .padding(.top, 24)
                if let otherDevice {
                    Button(action: otherDevice) {
                        Label("¿Ya usas Chirogra en otro aparato?", systemImage: "icloud")
                            .font(.subheadline)
                            .frame(minHeight: Metrics.target)
                    }
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: Self.width)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .padding(.top, Self.topPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    private func card(_ option: WelcomeAudience) -> some View {
        let isOn = selection == option
        return Button {
            if reduceMotion { selection = option } else { withAnimation(.snappy) { selection = option } }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(option.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.headline).foregroundStyle(Palette.ink)
                    Text(option.detail).font(.subheadline).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(isOn ? Palette.brand : .clear)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isOn ? Palette.brand : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    #if os(macOS)
    private static let topPadding: CGFloat = 32
    private static let width: CGFloat = 480
    #else
    private static let topPadding: CGFloat = 96
    private static let width: CGFloat = 520
    #endif
}

/// «Chirogra para contadores»: qué gana el contador y cómo empieza (alta del primer cliente o su copia).
struct AccountantIntroView: View {
    /// «Dar de alta mi primer cliente».
    let onCreate: () -> Void
    /// Se importó la copia de un cliente.
    let onImported: () -> Void
    let onBack: () -> Void

    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @State private var importing = false
    @State private var errorMessage: String?

    private struct Feature: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let color: Color
    }

    private var features: [Feature] {
        [
            Feature(id: "empresas", title: String(localized: "Empresas sin límite"),
                    detail: String(localized: "Cada cliente con sus libros, su sales tax y su cierre."), systemImage: "building.2", color: Palette.brand),
            Feature(id: "panel", title: String(localized: "Panel de clientes"),
                    detail: String(localized: "Lo urgente de cada uno: sales tax, banco sin conciliar, facturas vencidas."), systemImage: "rectangle.grid.1x2", color: Palette.red),
            Feature(id: "ajustes", title: String(localized: "Ajustes del contador"),
                    detail: String(localized: "Tus asientos quedan marcados y se pueden filtrar."), systemImage: "doc.plaintext", color: Palette.indigo),
            Feature(id: "bitacora", title: String(localized: "Bitácora de cambios"),
                    detail: String(localized: "Quién cambió qué y cuándo, también lo borrado."), systemImage: "clock.arrow.circlepath", color: Palette.orange),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Palette.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("Chirogra para contadores")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Lleva los libros de todos tus clientes en un solo lugar, cada uno en su empresa.")
                        .font(.body)
                        .foregroundStyle(Palette.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        if index > 0 { Divider().padding(.leading, 58) }
                        HStack(spacing: 12) {
                            IconTile(systemImage: feature.systemImage, foreground: feature.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feature.title).font(.headline).foregroundStyle(Palette.ink)
                                Text(feature.detail).font(.subheadline).foregroundStyle(Palette.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 22)
                if let errorMessage { ErrorBanner(message: errorMessage).padding(.top, 12) }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .padding(.top, Self.topPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(Palette.background)
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Palette.ink)
            .accessibilityLabel("Atrás")
            .padding(.horizontal, sizeClass == .regular ? 24 : 16)
            .padding(.top, sizeClass == .regular ? 16 : 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) { macFooter }
        #endif
        .fileImporter(isPresented: $importing, allowedContentTypes: [.chirograBackup]) { result in
            if case .success(let url) = result { importCopy(url) }
        }
    }

    #if os(macOS)
    private static let topPadding: CGFloat = 32
    #else
    private static let topPadding: CGFloat = 64
    #endif

    #if os(iOS)
    private var bottomBar: some View {
        let content = VStack(spacing: 12) {
            Button("Dar de alta mi primer cliente", action: onCreate)
                .buttonStyle(.primary)
            Button("Importar copia de un cliente (.chirogra)") { importing = true }
                .font(.body.weight(.semibold))
                .frame(minHeight: Metrics.target)
        }
        return Group {
            if sizeClass == .regular {
                // Con fondo y más ancho con letra grande: los botones se montaban sobre la lista (QA del 11-nov).
                content.frame(width: dynamicTypeSize.isAccessibilitySize ? 520 : 360).frame(maxWidth: .infinity)
                    .padding(.top, 8).padding(.bottom, 20).background(Palette.background)
            } else {
                content
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }
    #else
    private var macFooter: some View {
        HStack(spacing: 12) {
            Button("Importar copia de un cliente…") { importing = true }
            Spacer(minLength: 12)
            Button("Atrás", action: onBack)
            Button("Dar de alta mi primer cliente", action: onCreate)
                .buttonStyle(.primaryCompact)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }
    #endif

    /// La copia `.chirogra` que el cliente mandó desde su Chirogra entra como su empresa.
    private func importCopy(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = try BackupArchive.restoreCompany(data, into: context, mode: .newCompany)
            BooksReplacement.shared.didRestore(result.info)
            errorMessage = nil
            onImported()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
