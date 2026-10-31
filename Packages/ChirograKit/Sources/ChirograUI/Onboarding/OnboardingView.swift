import ChirograData
import SwiftData
import SwiftUI

/// Alta de empresa (canvas: `OnbEmpresa`, `OnbTipo`). El paso 2 elige el sector, que decide la plantilla
/// del plan de cuentas. El paso 3 "Traer movimientos" es de la fase 2.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var step = 1
    @State private var displayName = ""
    @State private var legalName = ""
    @State private var state = ""
    @State private var entityType: EntityType = .soleProprietorship
    @State private var sector: BusinessSector = .services
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    Capsule().fill(index <= step ? Palette.brand : Palette.surface2).frame(height: 5)
                }
                Text("\(step) de 2").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).padding(.leading, 8)
            }

            if step == 1 { companyStep } else { typeStep }

            if let errorMessage { ErrorBanner(message: errorMessage) }
            Spacer()

            VStack(spacing: 6) {
                Button(step == 1 ? "Continuar" : "Ir a mi panel") {
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
        }
        .padding(20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    /// El estado es obligatorio: decide qué sales tax se cobra.
    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && !state.isEmpty
    }

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoMark(size: 56)
            Text("Crea tu empresa").font(.largeTitle.bold())
            Text("Con estos datos preparamos tu plan de cuentas y tus facturas.").foregroundStyle(Palette.ink2)
            VStack(spacing: 12) {
                field("Nombre del negocio", text: $displayName, prompt: "Ríos Diseño & Obra")
                field("Razón social (opcional)", text: $legalName, prompt: "Ríos Diseño & Obra LLC")
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Estado donde operas", selection: $state) {
                        Text("Elige tu estado").tag("")
                        ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("Obligatorio: define el sales tax que cobras.")
                        .font(.footnote).foregroundStyle(state.isEmpty ? Palette.warning : Palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tipo de negocio").font(.largeTitle.bold())
            Text("Preparamos un plan de cuentas pensado para tu sector. Podrás añadir o archivar cuentas después.")
                .foregroundStyle(Palette.ink2)
            VStack(spacing: 10) {
                ForEach(BusinessSector.allCases, id: \.self) { option in
                    Button { sector = option } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text(option.summary).font(.subheadline).foregroundStyle(Palette.ink3)
                            }
                            Spacer()
                            Image(systemName: sector == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(sector == option ? Palette.brand : Palette.ink3)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(sector == option ? Palette.brand : Palette.separator, lineWidth: sector == option ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sector == option ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Algunas cuentas que crearemos")
                Text(previewAccounts.joined(separator: " · ")).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Picker("Tipo de entidad", selection: $entityType) {
                ForEach(EntityType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    /// Ingresos y costos propios del sector elegido, como vista previa del plan de cuentas.
    private var previewAccounts: [String] {
        sector.template.entries
            .filter { [.sales, .costOfGoodsSold, .inventory].contains($0.subtype) }
            .map { $0.name(for: Locale(identifier: "es_US")) }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextField(title, text: text, prompt: Text(prompt))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).stroke(Palette.separator))
        }
    }

    private func createCompany() {
        do {
            let name = displayName.trimmingCharacters(in: .whitespaces)
            try Bookkeeper(context: context).setUpCompany(
                legalName: legalName.isEmpty ? name : legalName, displayName: name, entityType: entityType,
                state: state, sector: sector
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSample() {
        do { try SampleData.populate(context) } catch { errorMessage = error.localizedDescription }
    }
}

#Preview {
    OnboardingView().modelContainer(try! ChirograStore.makeContainer(inMemory: true))
}
