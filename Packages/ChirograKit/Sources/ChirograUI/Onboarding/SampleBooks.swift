import ChirograData
import SwiftData
import SwiftUI

/// «Empezar con mi empresa»: salir de los datos de ejemplo («Probar con datos de ejemplo» del alta) para crear la
/// empresa propia. Los libros de ejemplo se reconocen por su alta en el registro de auditoría (`SampleData.isSample`,
/// sin cambiar el esquema y válido en todos los aparatos con iCloud).
///
/// - Inicio muestra el aviso «Estás viendo datos de ejemplo» (`SampleBooksBanner`), que se puede ocultar.
/// - Ajustes › iCloud, copias y seguridad tiene la misma acción (`SampleBooksSection`), para quien lo ocultó.
/// - Las dos piden la confirmación a la raíz (`SampleBooks.shared.confirm()`), que borra los libros
///   (`SampleData.discard`) y vuelve al alta «Creemos tu empresa» (`ChirograRootView`).
@MainActor
@Observable
final class SampleBooks {
    static let shared = SampleBooks()

    /// La confirmación «¿Borrar los datos de ejemplo?» a la vista (la presenta la raíz).
    var isConfirming = false
    /// Error al borrar (no debería pasar: el borrado no cambia nada si falla).
    var errorMessage: String?

    func confirm() { isConfirming = true }

    /// Aviso de Inicio oculto con su «×» (en este aparato). Se vuelve a mostrar con otros datos de ejemplo.
    static let bannerHiddenKey = "sampleBooksBannerHidden"
}

/// Muestra `content` solo mientras los libros son los de ejemplo; le pasa el nombre de la empresa de ejemplo.
struct IfSampleBooks<Content: View>: View {
    @Query private var companies: [Company]
    @Query(filter: SampleData.sampleCreationsPredicate) private var sampleCreations: [AuditEvent]
    @ViewBuilder var content: (String) -> Content

    var body: some View {
        if SampleData.isSample(companies: companies, sampleCreations: sampleCreations), let company = companies.first {
            content(company.displayName.isEmpty ? company.legalName : company.displayName)
        }
    }
}

/// Aviso de Inicio mientras los libros son de ejemplo: «Estás viendo datos de ejemplo» con «Empezar con mi empresa» y
/// una «×» para ocultarlo. En una fila si cabe (iPad, Mac); si no, el botón debajo del texto (iPhone); con letra de
/// accesibilidad, el texto y el botón a todo el ancho.
struct SampleBooksBanner: View {
    @AppStorage(SampleBooks.bannerHiddenKey) private var hidden = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Ancho del contenido de la tarjeta: con 560 pt o más, todo en una fila.
    @State private var width: CGFloat = 0
    private static let oneRowWidth: CGFloat = 560

    var body: some View {
        if !hidden {
            IfSampleBooks { company in card(company) }
        }
    }

    private func card(_ company: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Letra de accesibilidad: el texto a todo el ancho, debajo del icono y la «×», y el botón también.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        icon
                        Spacer(minLength: 0)
                        closeButton
                    }
                    texts(company).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Empezar con mi empresa") { SampleBooks.shared.confirm() }
                        .buttonStyle(.primary)
                        .padding(.trailing, Self.padding - Self.trailingPadding)
                }
            } else if width >= Self.oneRowWidth {
                // Una fila: el texto se parte en dos líneas si hace falta y el botón queda a la derecha.
                HStack(alignment: .center, spacing: 12) {
                    icon
                    texts(company).frame(maxWidth: .infinity, alignment: .leading)
                    startButton.fixedSize()
                    closeButton
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        icon
                        texts(company).frame(maxWidth: .infinity, alignment: .leading)
                        closeButton
                    }
                    startButton
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.leading, Self.padding)
        .padding(.trailing, Self.trailingPadding)
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        #if os(macOS)
        .overlay { RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5) }
        #endif
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        IconTile(systemImage: "sparkles", foreground: Palette.orange)
    }

    private func texts(_ company: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Estás viendo datos de ejemplo")
                .font(.headline).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("«\(company)» es una empresa inventada para probar Chirogra. Cuando quieras, bórrala y crea la tuya.")
                .font(.subheadline).foregroundStyle(Palette.ink2)
        }
    }

    private var startButton: some View {
        Button("Empezar con mi empresa") { SampleBooks.shared.confirm() }
            .buttonStyle(.primaryCompact)
            #if os(macOS)
            .controlSize(.regular)
            #endif
    }

    private var closeButton: some View {
        Button { hidden = true } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ocultar aviso")
        .accessibilityHint("Podrás empezar con tu empresa desde Ajustes › iCloud, copias y seguridad.")
        #if os(macOS)
        .help("Ocultar aviso")
        #endif
    }

    #if os(macOS)
    private static let padding: CGFloat = 14
    private static let trailingPadding: CGFloat = 8
    #else
    private static let padding: CGFloat = 16
    /// La «×» ya trae su área de 44 pt: el borde de la tarjeta queda a la vista a ~16 pt del símbolo.
    private static let trailingPadding: CGFloat = 4
    #endif
}

/// «Datos de ejemplo» de Ajustes › iCloud, copias y seguridad: la misma acción que el aviso de Inicio. Va ahí, con las
/// copias de seguridad, porque es lo que reemplaza los libros enteros (como «Restaurar desde una copia…»), y es la misma
/// página en iPhone («Más › iCloud y copias»), iPad y Mac.
struct SampleBooksSection: View {
    var body: some View {
        IfSampleBooks { company in
            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "sparkles", foreground: Palette.orange)
                    Button("Empezar con mi empresa…") { SampleBooks.shared.confirm() }
                        .foregroundStyle(Palette.brand)
                    Spacer(minLength: 0)
                }
                .buttonStyle(.borderless)
            } header: {
                SectionLabel(text: String(localized: "Datos de ejemplo"))
            } footer: {
                Text("Estás usando los datos de ejemplo de «\(company)». Bórralos y crea tu empresa desde cero.")
            }
        }
    }
}

extension View {
    /// En la raíz: la confirmación de «Empezar con mi empresa» y el borrado. `onDiscard` se llama después de borrar.
    func sampleBooksConfirmation(onDiscard: @escaping () -> Void) -> some View {
        modifier(SampleBooksConfirmation(onDiscard: onDiscard))
    }
}

private struct SampleBooksConfirmation: ViewModifier {
    let onDiscard: () -> Void
    @Environment(\.modelContext) private var context
    @State private var sampleBooks = SampleBooks.shared
    @AppStorage(ChirograStore.syncEnabledKey) private var iCloudSyncEnabled = true
    @AppStorage(SampleBooks.bannerHiddenKey) private var bannerHidden = false
    @Query private var companies: [Company]
    @Query(filter: SampleData.sampleCreationsPredicate) private var sampleCreations: [AuditEvent]
    #if DEBUG
    /// `-qa.empezar` ya se aplicó en esta sesión.
    @State private var qaApplied = false
    #endif

    private var isSample: Bool { SampleData.isSample(companies: companies, sampleCreations: sampleCreations) }

    private var companyName: String {
        companies.first.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? ""
    }

    func body(content: Content) -> some View {
        content
            .alert("¿Borrar los datos de ejemplo?", isPresented: $sampleBooks.isConfirming) {
                Button("Borrar y empezar", role: .destructive, action: discard)
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(message)
            }
            .alert("No se pudieron borrar los datos de ejemplo",
                   isPresented: Binding(get: { sampleBooks.errorMessage != nil }, set: { if !$0 { sampleBooks.errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(sampleBooks.errorMessage ?? "")
            }
            // Si los libros dejan de ser de ejemplo con la confirmación abierta (llega otra empresa por iCloud), se cierra.
            .onChange(of: isSample) { _, sample in if !sample { sampleBooks.isConfirming = false } }
            #if DEBUG
            // `-qa.empezar 1` (solo Debug): abre la confirmación en cuanto hay datos de ejemplo; `-qa.empezar confirmar`
            // además borra, como al tocar «Borrar y empezar».
            .onChange(of: isSample, initial: true) { _, sample in
                guard sample, !qaApplied, let mode = UserDefaults.standard.string(forKey: "qa.empezar") else { return }
                qaApplied = true
                Task { @MainActor in
                    // Que Inicio termine de dibujarse antes de la alerta.
                    try? await Task.sleep(for: .milliseconds(600))
                    if mode == "confirmar" { discard() } else { sampleBooks.confirm() }
                }
            }
            #endif
    }

    private var message: String {
        let what = String(localized: "Se borran todos los datos de ejemplo de «\(companyName)»: clientes, facturas, gastos, asientos y ajustes. Después creas tu empresa desde cero.")
        let scope = iCloudSyncEnabled ? " " + String(localized: "También se borran en tus otros aparatos con iCloud.") : ""
        return what + scope
    }

    private func discard() {
        do {
            try SampleData.discard(from: context)
            bannerHidden = false
            onDiscard()
        } catch {
            sampleBooks.errorMessage = error.localizedDescription
        }
    }
}
