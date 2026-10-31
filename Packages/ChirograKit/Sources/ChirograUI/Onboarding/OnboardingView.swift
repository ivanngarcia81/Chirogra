import ChirograData
import SwiftData
import SwiftUI

/// Alta de empresa (canvas: `OnbEmpresa`, `OnbTipo`). El paso 3 "Traer movimientos" es de la fase 2.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var step = 1
    @State private var displayName = ""
    @State private var legalName = ""
    @State private var state = ""
    @State private var entityType: EntityType = .soleProprietorship
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                if step > 1 {
                    Button { step -= 1 } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
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
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)

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

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoMark(size: 56)
            Text("Crea tu empresa").font(.largeTitle.bold())
            Text("Con estos datos preparamos tu plan de cuentas y tus facturas.").foregroundStyle(Palette.ink2)
            VStack(spacing: 12) {
                field("Nombre del negocio", text: $displayName, prompt: "Ríos Diseño & Obra")
                field("Razón social (opcional)", text: $legalName, prompt: "Ríos Diseño & Obra LLC")
                Picker("Estado", selection: $state) {
                    Text("Elige tu estado").tag("")
                    ForEach(USState.all, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tipo de negocio").font(.largeTitle.bold())
            Text("Define cómo se llama el patrimonio en tus reportes. Puedes cambiarlo después.").foregroundStyle(Palette.ink2)
            VStack(spacing: 10) {
                ForEach(EntityType.allCases, id: \.self) { type in
                    Button { entityType = type } label: {
                        HStack {
                            Text(type.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: entityType == type ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(entityType == type ? Palette.brand : Palette.ink3)
                        }
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(entityType == type ? Palette.brand : Palette.separator, lineWidth: entityType == type ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(entityType == type ? .isSelected : [])
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextField(title, text: text, prompt: Text(prompt))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).stroke(Palette.separator))
        }
    }

    private func createCompany() {
        do {
            let name = displayName.trimmingCharacters(in: .whitespaces)
            try Bookkeeper(context: context).setUpCompany(
                legalName: legalName.isEmpty ? name : legalName, displayName: name, entityType: entityType, state: state
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
