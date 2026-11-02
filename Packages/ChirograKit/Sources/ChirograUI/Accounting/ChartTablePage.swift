#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: tabla + inspector de Plan de cuentas (canvas `MacPlanCuentas`). POR HACER con `MacTablePage` (ver docs/REDISEÑO-NATIVO.md,
/// «Mac: tabla + inspector»; el ejemplo hecho es `Sales/InvoiceTablePage.swift`). Mientras `isReady` sea `false`,
/// el Mac sigue mostrando esta página con la columna maestro de antes (`MasterColumn` + `MasterDetailColumn`).
struct ChartTablePage: View {
    static let isReady = false
    @Binding var selection: UUID?

    var body: some View { EmptyView() }
}
#endif
