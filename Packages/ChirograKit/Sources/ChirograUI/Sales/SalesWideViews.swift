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

/// Tabla en tarjeta: cabecera en mayúsculas y filas separadas por líneas.
struct TableCard<Header: View, Rows: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { header }
                .font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(Palette.ink3)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .accessibilityHidden(true)
            rows
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Fila de `TableCard`: línea arriba, 44 pt de alto como mínimo.
struct TableRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) { content }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}
