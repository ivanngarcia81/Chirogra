import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

extension Customer {
    /// Saldo de las facturas abiertas ya vencidas.
    var overdueBalance: Int64 {
        (invoices ?? []).filter { $0.isOpen && $0.daysOverdue() != nil }.reduce(0) { $0 + $1.balanceDue }
    }
}

/// Tabla (canvas `MacVentas`, `MacInicio`): cabecera en tipo oración, pequeña y gris, y filas separadas por líneas.
/// En el Mac, la tabla del sistema: borde fino, radio 8, cabecera de 26 pt sobre el fondo de la ventana; en iPhone e
/// iPad, una celda agrupada (radio 24).
struct TableCard<Header: View, Rows: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var rows: Rows

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tableRadius, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: Self.columnSpacing) { header }
                .font(.label).foregroundStyle(Palette.ink2)
                // Una línea y recortado: con columnas estrechas la cabecera se partía en sílabas («Des-crip-ción»).
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, Self.inset)
                .frame(minHeight: Self.headerHeight)
                .accessibilityHidden(true)
            rows
        }
        #if os(macOS)
        .background(Palette.background, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
        #else
        .background(Palette.surface, in: shape)
        #endif
    }

    #if os(macOS)
    static var inset: CGFloat { 10 }
    static var headerHeight: CGFloat { 26 }
    static var columnSpacing: CGFloat { 10 }
    #else
    static var inset: CGFloat { 16 }
    static var headerHeight: CGFloat { 36 }
    static var columnSpacing: CGFloat { 12 }
    #endif
}

/// Fila de `TableCard`: línea arriba, del alto mínimo de la plataforma (44 pt táctiles; 28 en el Mac, con el cuerpo
/// de 13 pt del Mac).
struct TableRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: TableCard<EmptyView, EmptyView>.columnSpacing) { content }
                #if os(macOS)
                .font(.body)
                #else
                .font(.subheadline)
                #endif
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, TableCard<EmptyView, EmptyView>.inset)
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}
