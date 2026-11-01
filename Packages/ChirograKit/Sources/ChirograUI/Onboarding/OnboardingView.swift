import ChirograData
import SwiftData
import SwiftUI

/// Alta de empresa (canvas `OnbEmpresa`, `OnbTipo`). Paso 1: nombre, estado, año fiscal e ID fiscal. Paso 2: tipo de
/// negocio, que decide la plantilla del plan de cuentas. El paso 3 del canvas («Traer movimientos») no está en el MVP.
/// El logotipo de la empresa todavía no se guarda, así que no se pide.
struct OnboardingView: View {
    /// Tipos de negocio del canvas; cada uno usa una de las plantillas de plan de cuentas.
    enum Kind: String, CaseIterable, Identifiable {
        case professional, retail, construction, food, health, freelance
        var id: String { rawValue }

        var title: String {
            switch self {
            case .professional: String(localized: "Servicios profesionales")
            case .retail: String(localized: "Comercio o tienda")
            case .construction: String(localized: "Construcción y oficios")
            case .food: String(localized: "Restaurante y comida")
            case .health: String(localized: "Salud y bienestar")
            case .freelance: String(localized: "Independiente")
            }
        }

        var systemImage: String {
            switch self {
            case .professional: "briefcase"
            case .retail: "storefront"
            case .construction: "hammer"
            case .food: "fork.knife"
            case .health: "heart"
            case .freelance: "person"
            }
        }

        var sector: BusinessSector {
            switch self {
            case .retail, .food: .retail
            case .construction: .construction
            case .professional, .health, .freelance: .services
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step = 1
    @State private var displayName = ""
    @State private var legalName = ""
    @State private var state = ""
    @State private var fiscalStartMonth = 1
    @State private var ein = ""
    @State private var entityType: EntityType = .soleProprietorship
    @State private var kind: Kind = .construction
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepIndicator
                if step == 1 { companyStep } else { typeStep }
                if let errorMessage { ErrorBanner(message: errorMessage) }
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                Button(step == 1 ? "Continuar" : "Usar este plan") {
                    if step == 1 { step = 2 } else { createCompany() }
                }
                .buttonStyle(.primary)
                .disabled(!canContinue)
                if step == 1 {
                    Button("Probar con datos de ejemplo", action: loadSample)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(Palette.background)
        }
        .background(Palette.background)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            if step > 1 {
                Button { step -= 1 } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Atrás")
            }
            ForEach(1...2, id: \.self) { index in
                Capsule().fill(index <= step ? Palette.brand : Palette.separator).frame(height: 5)
            }
            Text("\(step) de 2").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).padding(.leading, 8)
        }
    }

    /// El estado es obligatorio: decide qué sales tax se cobra.
    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && !state.isEmpty
    }

    // MARK: Paso 1 (`OnbEmpresa`)

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            LogoMark(size: 52)
            VStack(alignment: .leading, spacing: 8) {
                Text("Creemos tu empresa").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Estos datos aparecen en tus facturas. Puedes cambiarlos cuando quieras en Ajustes.").foregroundStyle(Palette.ink2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Nombre de la empresa").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
                TextField("Nombre de la empresa", text: $displayName, prompt: Text("Ríos Diseño & Obra"))
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).stroke(Palette.brand, lineWidth: 1.5))
            }
            VStack(spacing: 0) {
                infoRow(String(localized: "País o región")) { Text("Estados Unidos").foregroundStyle(Palette.ink2) }
                Divider()
                infoRow(String(localized: "Moneda")) { Text("USD · Dólar").foregroundStyle(Palette.ink2) }
                Divider()
                infoRow(String(localized: "Estado")) {
                    Picker("Estado", selection: $state) {
                        Text("Elige tu estado").tag("")
                        ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                Divider()
                infoRow(String(localized: "Inicio del año fiscal")) {
                    Picker("Inicio del año fiscal", selection: $fiscalStartMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Calendar.current.standaloneMonthSymbols[month - 1].sentenceCased).tag(month)
                        }
                    }
                    .labelsHidden()
                }
                Divider()
                infoRow(String(localized: "Razón social")) {
                    TextField("Razón social", text: $legalName, prompt: Text("Opcional")).multilineTextAlignment(.trailing)
                }
                Divider()
                infoRow(String(localized: "ID fiscal (EIN)")) {
                    TextField("ID fiscal (EIN)", text: $ein, prompt: Text("Opcional")).multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.separator))

            Label("Tus libros se llevan en dólares (USD). El estado decide el sales tax que cobras; es obligatorio.",
                  systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.brand)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.brandWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func infoRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Palette.ink).fixedSize()
                Spacer(minLength: 8)
                content()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(Palette.ink)
                content()
            }
        }
        .frame(minHeight: 50)
    }

    // MARK: Paso 2 (`OnbTipo`)

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("¿A qué se dedica tu negocio?").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Te sugerimos un plan de cuentas listo para usar.").foregroundStyle(Palette.ink2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Kind.allCases) { option in kindCard(option) }
            }
            suggestedPlan
            infoRow(String(localized: "Tipo de entidad")) {
                Picker("Tipo de entidad", selection: $entityType) {
                    ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func kindCard(_ option: Kind) -> some View {
        let selected = kind == option
        return Button { kind = option } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Palette.onBrand : Palette.ink2)
                    .frame(width: 34, height: 34)
                    .background(selected ? Palette.brand : Palette.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(option.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Palette.brand : Palette.separator, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Cuentas propias del sector (ingresos, costos, inventario) como chips, y cuántas se crearán en total.
    private var suggestedPlan: some View {
        let entries = kind.sector.template.entries
        let featured = entries.filter { [.sales, .costOfGoodsSold, .inventory, .operatingExpense].contains($0.subtype) }
            .prefix(6).map { $0.name(for: .current) }   // el mismo idioma con que `setUpCompany` creará las cuentas
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: String(localized: "Plan de cuentas sugerido"))
                Spacer()
                Text("\(entries.count) cuentas").font(.footnote.weight(.semibold)).foregroundStyle(Palette.brand)
            }
            FlowLayout(spacing: 6) {
                ForEach(featured, id: \.self) { chip($0) }
                if entries.count > featured.count { chip(String(localized: "+ \(entries.count - featured.count) más")) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.separator))
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Acciones

    private func createCompany() {
        do {
            let name = displayName.trimmingCharacters(in: .whitespaces)
            let company = try Bookkeeper(context: context).setUpCompany(
                legalName: legalName.isEmpty ? name : legalName, displayName: name, entityType: entityType,
                state: state, sector: kind.sector
            )
            company.fiscalYearStartMonth = fiscalStartMonth
            company.ein = ein.trimmingCharacters(in: .whitespaces)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSample() {
        do { try SampleData.populate(context) } catch { errorMessage = error.localizedDescription }
    }
}

/// Coloca las vistas en filas y pasa a la siguiente cuando no caben (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    OnboardingView().modelContainer(try! ChirograStore.makeContainer(inMemory: true))
}
