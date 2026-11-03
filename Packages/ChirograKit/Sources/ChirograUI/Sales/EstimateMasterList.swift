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
///
/// Las piezas de las filas (`MasterRow`, `masterRow`…) son privadas de `Shell/MasterDetail.swift`; aquí van copias
/// mínimas (`EstimateMasterRow`) para no tocar ese archivo. Anotado para subirlas a `DesignSystem` después.
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
                let isSelected = estimate.id == selection
                EstimateMasterRow(estimate: estimate, isSelected: isSelected)
                    .tag(estimate.id)
                    .listRowBackground(EstimateMasterRowBackground(isSelected: isSelected))
                    .listRowSeparator(isSelected ? .hidden : .automatic)
                    .focusEffectDisabled()
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

/// Fila de la columna maestro: cliente e importe arriba; «E-0001 · válido hasta 30 nov» y el estado abajo; en blanco
/// sobre la elegida (relleno de Tinta, 7,5:1 en claro y 5,4:1 en oscuro).
private struct EstimateMasterRow: View {
    let estimate: Estimate
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var primary: Color { isSelected ? Palette.onBrandFill : Palette.ink }
    private var secondary: Color { isSelected ? Palette.onBrandFill.opacity(0.92) : Palette.ink2 }

    private var subtitle: String {
        let number = estimate.number.isEmpty ? String(localized: "Sin número") : estimate.number
        return "\(number) · " + String(localized: "válido hasta \(estimate.expirationDate.dayMonth)")
    }

    private var status: StatusChip {
        let chip = estimate.statusChip()
        return isSelected ? StatusChip(text: chip.text, foreground: Palette.onBrandFill, background: .clear, compact: true, dot: Palette.onBrandFill)
            : chip
    }

    var body: some View {
        let name = estimate.customer?.name ?? String(localized: "Sin cliente")
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                    Text(estimate.total.money).monospacedDigit()
                    Text(subtitle).font(.footnote).foregroundStyle(secondary)
                    status
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(name).lineLimit(2)
                        Spacer(minLength: 8)
                        Text(estimate.total.money).monospacedDigit().fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subtitle).font(.footnote).foregroundStyle(secondary).lineLimit(1)
                        Spacer(minLength: 8)
                        status
                    }
                }
            }
        }
        .font(.body)
        .foregroundStyle(primary)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Fondo de la fila: la superficie de la columna o, en la elegida, una cápsula de Tinta con margen (radio 12).
private struct EstimateMasterRowBackground: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Palette.surface
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.brandFill)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
            }
        }
    }
}
#endif
