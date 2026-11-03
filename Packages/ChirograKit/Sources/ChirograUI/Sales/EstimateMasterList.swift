#if os(iOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Filtro de la columna maestro de estimados (los `rawValue` son las etiquetas en español del catálogo).
enum EstimateScope: String, CaseIterable, Identifiable {
    case open = "Abiertos", accepted = "Aceptados", all = "Todos"
    var id: String { rawValue }

    func matches(_ estimate: Estimate) -> Bool {
        switch self {
        case .open: [.draft, .sent, .accepted].contains(estimate.effectiveStatus()) && !estimate.isFullyInvoiced
        case .accepted: estimate.effectiveStatus() == .accepted
        case .all: true
        }
    }
}

/// Columna maestro de Estimados en el iPad (canvas `iPadVentas`, como la de facturas): «Estimados» con su buscador, el
/// segmentado Abiertos · Aceptados · Todos y filas de dos líneas (cliente e importe; número · validez y estado), la
/// elegida rellena de Tinta con el texto en blanco. «+ Estimado» en la barra.
/// Las filas son las de las demás listas maestro (`DesignSystem/MasterRows.swift`).
struct EstimateMasterList: View {
    @Binding var selection: UUID?
    @Query(sort: \Estimate.issueDate, order: .reverse) private var estimates: [Estimate]
    @State private var scope: EstimateScope = .open
    @State private var query = ""
    @State private var creating = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filtered: [Estimate] { estimates.filter { scope.matches($0) && EstimateFilter.search($0, query) } }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { estimate in
                MasterRow(title: estimate.customer?.name ?? String(localized: "Sin cliente"), amount: estimate.total.money,
                          subtitle: Self.subtitle(of: estimate)) {
                    MasterStatus(chip: estimate.statusChip())
                }
                .masterRow(estimate.id, selection: selection)
            }
            if filtered.isEmpty {
                Text(estimates.isEmpty ? String(localized: "Todavía no hay estimados") : String(localized: "Ningún estimado coincide"))
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.surface)
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        // Sin el anillo de foco del sistema con trackpad o teclado (como `MasterListStyle`).
        .tint(Color.clear)
        .focusEffectDisabled()
        #endif
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .tint(Palette.brandFill)
        .navigationTitle(String(localized: "Estimados"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Cliente, número o monto"))
        .safeAreaInset(edge: .top, spacing: 0) {
            filterBar.background(Palette.surface)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Estimado")
                    }
                }
                .accessibilityLabel("Nuevo estimado")
                .headerButton()
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { InvoiceEditorView(mode: .estimate(nil)) }.editorSheetSizing() }
    }

    @ViewBuilder
    private var filterBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("Mostrar").foregroundStyle(Palette.ink2)
                    Spacer(minLength: 8)
                    picker.pickerStyle(.menu)
                }
                .frame(minHeight: Metrics.target)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var picker: some View {
        Picker("Filtrar", selection: $scope) {
            ForEach(EstimateScope.allCases) { Text($0.localizedTitle).tag($0) }
        }
        .labelsHidden()
    }
}

extension EstimateMasterList {
    /// «E-0001 · válido hasta 30 nov».
    static func subtitle(of estimate: Estimate) -> String {
        let number = estimate.number.isEmpty ? String(localized: "Sin número") : estimate.number
        return "\(number) · " + String(localized: "válido hasta \(estimate.expirationDate.dayMonth)")
    }
}
#endif
