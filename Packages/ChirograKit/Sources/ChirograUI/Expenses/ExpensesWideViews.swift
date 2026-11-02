import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

extension Bill {
    /// Abierta y con el vencimiento ya pasado.
    var isOverdue: Bool { isOpen && dueDate < Calendar.current.startOfDay(for: .now) }

    /// Días de atraso de una factura abierta y vencida.
    var daysOverdue: Int? {
        guard isOverdue else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: .now)).day
    }

    /// Concepto de la factura: la nota o, si no tiene, la descripción de la primera línea.
    var concept: String { memo.isEmpty ? (sortedLines.first?.details ?? "") : memo }
}

extension StatusChip {
    /// Estado de una factura por pagar con el atraso, como el de las facturas de venta (canvas `MacPorPagar`:
    /// «● Vencida · 4 días» en rojo); el resto, el de `init(bill:)`.
    init(billWithAge bill: Bill, compact: Bool = true) {
        if let days = bill.daysOverdue {
            self.init(text: String(localized: "Vencida · \(days) días"), foreground: Palette.negative, background: Palette.negativeWash,
                      compact: compact, dot: Palette.red)
        } else {
            self.init(bill: bill, compact: compact)
        }
    }
}

/// Símbolo y color de una categoría de gasto (canvas `Gastos`, `MacGastos`: Materiales en índigo, Subcontratistas en
/// verde azulado, Transporte en naranja, Renta en azul…), por palabras del nombre en español o en inglés.
enum ExpenseCategoryStyle {
    private static let table: [(keys: [String], symbol: String, color: Color)] = [
        (["material", "suministro", "suppl", "job"], "shippingbox", Palette.indigo),
        (["subcontrat", "contratista", "contract labor", "professional", "profesional", "mano de obra"], "person", Palette.teal),
        (["vehí", "vehic", "transport", "car ", "truck", "combustible", "gasolin", "fuel"], "car", Palette.orange),
        (["software", "suscrip", "subscri"], "desktopcomputer", Palette.gray),
        (["renta", "alquiler", "rent", "lease"], "house", Palette.blue),
        (["seguro", "insurance"], "shield", Palette.green),
        (["publicidad", "advertis", "marketing"], "megaphone", Palette.pink),
        (["comida", "meal", "restaur"], "fork.knife", Palette.red),
        (["teléfono", "phone", "internet", "utilit", "servicios públicos"], "bolt", Palette.purple),
        (["banco", "bank", "comisi", "fee"], "building.columns", Palette.gray),
        (["reparac", "repair", "manten"], "wrench.and.screwdriver", Palette.orange),
        (["viaje", "travel"], "airplane", Palette.teal),
        (["oficina", "office"], "tray.full", Palette.blue),
    ]

    private static func entry(_ name: String) -> (keys: [String], symbol: String, color: Color)? {
        let name = name.lowercased()
        return table.first { entry in entry.keys.contains { name.contains($0) } }
    }

    static func symbol(for name: String?) -> String { name.flatMap(entry)?.symbol ?? "receipt" }
    static func color(for name: String?) -> Color { name.flatMap(entry)?.color ?? Palette.gray }

    /// Colores de la barra del mes: el de cada categoría; si dos categorías comparten color, la segunda toma uno libre
    /// para que la barra se siga leyendo.
    static func barColors(for names: [String]) -> [Color] {
        let spare: [Color] = [Palette.indigo, Palette.teal, Palette.blue, Palette.orange, Palette.purple, Palette.pink, Palette.green]
        var used: [Color] = []
        return names.map { name in
            let own = color(for: name)
            let pick = used.contains(own) ? (spare.first { !used.contains($0) } ?? own) : own
            used.append(pick)
            return pick
        }
    }
}

/// Fila «etiqueta gris · valor» de una ficha (canvas: inspectores del Mac, `.irow`), para pantallas sin `List`.
struct DetailRow<Value: View>: View {
    let title: String
    @ViewBuilder var value: Value

    var body: some View {
        AdaptiveRow(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Palette.ink2)
        } trailing: {
            value.foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: Self.minHeight)
        .accessibilityElement(children: .combine)
    }

    #if os(macOS)
    static var minHeight: CGFloat { 26 }
    #else
    static var minHeight: CGFloat { Metrics.target }
    #endif
}

extension DetailRow where Value == Text {
    init(_ title: String, value: String) {
        self.init(title: title) { Text(value) }
    }
}
