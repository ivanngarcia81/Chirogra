import ChirograCore
import ChirograData
import SwiftUI

// Piezas de los formularios de Gastos (gasto, factura por pagar, recurrente, proveedor), recorrido «cliente nuevo»
// del 5-nov.

/// Fila «Monto» con su campo de importe a la derecha: tocar cualquier parte de la fila (también la etiqueta) da el
/// foco al campo. Antes solo respondía el «$0.00» de la derecha. VoiceOver sigue leyendo la etiqueta y el campo como
/// siempre: el gesto es solo para el dedo.
struct MoneyRow: View {
    let title: String
    @Binding var minorUnits: Int64
    var font: Font? = nil
    @FocusState private var focused: Bool

    init(_ title: String, minorUnits: Binding<Int64>, font: Font? = nil) {
        self.title = title
        self._minorUnits = minorUnits
        self.font = font
    }

    var body: some View {
        LabeledContent {
            // Sin su propia etiqueta: en el Mac salía «Importe total Importe total».
            MoneyField(title: title, minorUnits: $minorUnits)
                .font(font)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                .accessibilityLabel(title)
                .focused($focused)
        } label: {
            Text(title)
        }
        #if os(iOS)
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        #endif
    }
}

/// «Categoría» de un gasto: primero los gastos y costos y, aparte y al final, las compras de equipo, inventario y
/// pagos por adelantado. Nunca las por cobrar ni las contra-cuentas (`ExpenseCategories`). Se le pasan todas las
/// cuentas: el filtro es suyo, y conserva la elegida aunque ya no pase el filtro (un gasto antiguo).
struct ExpenseCategoryPicker: View {
    let title: String
    let accounts: [Account]
    @Binding var selection: UUID?

    var body: some View {
        let groups = ExpenseCategories.groups(from: accounts, keeping: selection)
        Picker(title, selection: $selection) {
            Text("Elegir…").tag(UUID?.none)
            Section {
                ForEach(groups.costs) { Text($0.displayName).tag(Optional($0.id)) }
            } header: {
                Text("Gastos y costos")
            }
            if !groups.assetPurchases.isEmpty {
                Section {
                    ForEach(groups.assetPurchases) { Text($0.displayName).tag(Optional($0.id)) }
                } header: {
                    Text(groups.includesInventory ? "Compras de equipo, inventario y pagos por adelantado"
                                                  : "Compras de equipo y pagos por adelantado")
                }
            }
        }
    }
}

/// «Proveedor» con «Nuevo proveedor…» en el mismo menú (como «Nuevo cliente» de la factura): abre el editor de
/// proveedor con `proposedName` (lo escrito en «Pagado a») y, al guardar, el proveedor queda elegido. Elegir
/// «Nuevo proveedor…» no cambia la selección: se queda la de antes hasta que se guarde el proveedor.
struct VendorPicker: View {
    /// Etiqueta interna de «Nuevo proveedor…» en el menú; nunca se guarda.
    static let newVendorTag = UUID(uuidString: "00000000-0000-0000-0000-00000000A0D0")!

    let vendors: [Vendor]
    @Binding var selection: UUID?
    /// «Ninguno» (gasto) o «Elegir…» (factura por pagar, donde el proveedor es obligatorio).
    var noneTitle: LocalizedStringKey = "Ninguno"
    var proposedName: String = ""
    /// Tras guardar el proveedor nuevo, antes de elegirlo (para rellenar lo que dependa de él).
    var onCreate: (Vendor) -> Void = { _ in }
    @State private var creating = false

    var body: some View {
        Picker("Proveedor", selection: $selection) {
            Text(noneTitle).tag(UUID?.none)
            Label("Nuevo proveedor…", systemImage: "plus").tag(Optional(Self.newVendorTag))
            Divider()
            ForEach(vendors.filter { !$0.isArchived || $0.id == selection }) { Text($0.name).tag(Optional($0.id)) }
        }
        .onChange(of: selection) { old, new in
            guard new == Self.newVendorTag else { return }
            selection = old == Self.newVendorTag ? nil : old
            creating = true
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                VendorEditorView(initialName: proposedName.trimmingCharacters(in: .whitespaces)) { vendor in
                    onCreate(vendor)
                    selection = vendor.id
                }
            }
            .editorSheetSizing()
        }
    }
}
