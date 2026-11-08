import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Campo «Código postal» (ZIP de 5 dígitos; admite ZIP+4).
struct PostalCodeField: View {
    @Binding var text: String
    var title: LocalizedStringKey = "Código postal"

    var body: some View {
        #if os(macOS)
        TextField(title, text: $text, prompt: Text(verbatim: "78702"))
            .task { await PostalTaxTableLoader.loadIfNeeded() }
        #else
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(verbatim: "78702"))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .textContentType(.postalCode)
                .autocorrectionDisabled()
        }
        .labeledContentStyle(.automatic)
        // Aquí y no en la sugerencia: el campo siempre está, la sugerencia puede no dibujar nada.
        .task { await PostalTaxTableLoader.loadIfNeeded() }
        #endif
    }
}

extension SalesTaxSuggestion {
    /// «Austin, TX».
    var displayName: String { rate.region.isEmpty ? rate.state : "\(rate.region), \(rate.state)" }
    /// «Estado 6.25 % + local 2 %».
    var breakdown: String {
        rate.localRateMillionths > 0
            ? String(localized: "Estado \(StateTaxNote.percent(rate.stateRateMillionths)) + local \(StateTaxNote.percent(rate.localRateMillionths))")
            : String(localized: "Solo la tasa del estado")
    }
}

/// Sugerencia de sales tax por código postal (paso 1): la tasa total aproximada (estado + local) de la tabla publicada
/// y «Crear la tasa…» con confirmación (`Bookkeeper.createTaxCode`). Sin tabla cargada no muestra nada. Con `customer`,
/// la de una venta a ese cliente (origen o destino según el estado); sin él, la del código postal del negocio.
struct PostalTaxSuggestionView: View {
    /// Código postal que se está escribiendo (para refrescar).
    let postalCode: String
    var customer: Customer? = nil
    /// Tras crear o elegir el impuesto (el cliente lo pone como su impuesto por defecto).
    var onUse: ((UUID) -> Void)? = nil
    var useTitle: LocalizedStringKey = "Usar para este cliente"

    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \TaxGroup.name) private var groups: [TaxGroup]
    @CompanyQuery(sort: \TaxRate.name) private var rates: [TaxRate]
    @State private var confirming = false
    @State private var created: String?
    @State private var errorMessage: String?
    private var tableLoaded: Bool { PostalTaxTableLoader.status.hasTable }

    private var suggestion: SalesTaxSuggestion? {
        guard tableLoaded else { return nil }
        return try? Bookkeeper(context: context).suggestedSalesTax(for: customer)
    }

    private func codeName(_ id: UUID) -> String? {
        groups.first { $0.id == id }?.name ?? rates.first { $0.id == id }?.name
    }

    var body: some View {
        Group {
            if let suggestion {
                content(suggestion)
            } else if tableLoaded, let zip = PostalTaxTable.normalized(postalCode), PostalTaxTables.current?.rate(for: zip) == nil {
                Text("No hay una tasa para \(zip) en la tabla de Chirogra. Escribe la de tu estado a mano.")
                    .font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        #if DEBUG
        // `-qa.crearTasa 1` abre la confirmación de «Crear la tasa…»; `-qa.crearTasa confirmar` la crea.
        .task(id: suggestion?.rate.postalCode) {
            guard let suggestion, suggestion.existingTaxCodeID == nil, created == nil else { return }
            switch UserDefaults.standard.string(forKey: "qa.crearTasa") {
            case "1": confirming = true
            case "confirmar": create(suggestion)
            default: break
            }
        }
        #endif
    }

    @ViewBuilder
    private func content(_ suggestion: SalesTaxSuggestion) -> some View {
        let percent = StateTaxNote.percent(suggestion.rate.combinedRateMillionths)
        LabeledContent {
            Text(verbatim: "\(suggestion.displayName) · \(percent)").fontWeight(.semibold).foregroundStyle(Palette.ink)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.basis == .origin ? "Tasa sugerida para tu negocio (\(suggestion.rate.postalCode))"
                                                 : "Tasa sugerida para \(suggestion.rate.postalCode)")
                Text("\(suggestion.breakdown) · aproximada").font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .accessibilityElement(children: .combine)
        if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(Palette.negative)
        }
        if created != nil {
            // Recién creado: basta con el aviso de abajo.
        } else if let id = suggestion.existingTaxCodeID {
            HStack {
                Label { Text("Ya tienes este impuesto: \(codeName(id) ?? suggestion.displayName)") } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
                }
                .font(.subheadline)
                Spacer(minLength: 8)
                if let onUse, groups.contains(where: { $0.id == id }) {
                    Button(useTitle) { onUse(id) }.buttonStyle(.borderless)
                }
            }
            .frame(minHeight: Metrics.target)
        } else {
            Button {
                confirming = true
            } label: {
                Label("Crear la tasa «\(suggestion.displayName)» de \(percent)…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .confirmationDialog(Text("¿Crear la tasa «\(suggestion.displayName)» de \(percent)?"), isPresented: $confirming,
                                titleVisibility: .visible) {
                Button("Crear tasa") { create(suggestion) }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(message(for: suggestion))
            }
        }
        if let created {
            Label { Text("Impuesto creado: \(created). Elígelo en tus facturas o como predeterminado en Impuestos.") } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
            }
            .font(.footnote)
        }
    }

    private func message(for suggestion: SalesTaxSuggestion) -> String {
        let table = PostalTaxTables.current
        var text = String(localized: "Es una tasa aproximada para el código postal \(suggestion.rate.postalCode): \(suggestion.breakdown). Un código postal puede tener varias tasas; compruébala con tu estado antes de cobrarla.")
        if let source = table?.source, !source.isEmpty {
            text += "\n\n" + String(localized: "Fuente: \(source)") + (table?.effectiveDate.isEmpty == false ? " · \(table!.effectiveDate)" : "")
        }
        return text
    }

    private func create(_ suggestion: SalesTaxSuggestion) {
        do {
            let summary = try Bookkeeper(context: context).createTaxCode(for: suggestion)
            created = summary.name
            errorMessage = nil
            onUse?(summary.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
