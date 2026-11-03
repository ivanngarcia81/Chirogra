#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Proveedores como tabla + inspector (canvas `MacProveedores`). Arriba el segmentado Todos · Con saldo · 1099 con
/// su cuenta y, a la derecha, cuántos proveedores requieren 1099-NEC; la tabla Proveedor · Categoría · Por pagar ·
/// Gastado en el año · 1099 · Última compra, ordenada por lo gastado. El inspector muestra el proveedor elegido (Resumen,
/// Impuestos) con «Nuevo gasto» y «Abrir ficha». Doble clic abre la ficha completa (`VendorDetailView`,
/// canvas `MacProveedorFicha`).
struct VendorTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var filter: VendorFilter = .all
    @State private var query = ""
    @State private var creating = false
    @State private var addingExpense: Vendor?
    @State private var openedVendor: Vendor?

    private var year: Int { Calendar.current.component(.year, from: .now) }

    /// Proveedores activos (los archivados no salen, como en la columna maestro del iPad), con sus cifras ya calculadas.
    private var active: [VendorTableRow] {
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        return vendors.filter { !$0.isArchived }.map { vendor in
            let bills = (vendor.bills ?? []).filter { $0.status != .void }
            let expenses = vendor.expenses ?? []
            let spent = bills.filter { calendar.component(.year, from: $0.billDate) == year }.reduce(0) { $0 + $1.total }
                + expenses.filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.total }
            // Lo pagado en el año (pagos de facturas y gastos), que es lo que cuenta para el 1099.
            let payments: [BillPayment] = bills.flatMap { $0.payments ?? [] }
            let paidBills: Int64 = payments.filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.amount }
            let paidExpenses: Int64 = expenses.filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.total }
            let paid = paidBills + paidExpenses
            let last = (bills.map(\.billDate) + expenses.map(\.date)).max()
            let preferred = [vendor.preferredPaymentMethod?.title, accounts.account(vendor.preferredPaymentAccountID)?.paymentLabel]
                .compactMap { $0 }.joined(separator: " · ")
            return VendorTableRow(vendor: vendor, id: vendor.id, name: vendor.name,
                                  category: vendor.defaultExpenseAccountID.flatMap { names[$0] } ?? "",
                                  openBalance: vendor.openBalance, spentThisYear: spent, paidThisYear: paid,
                                  lastPurchase: last, is1099: vendor.is1099, email: vendor.email,
                                  w9Received: vendor.w9Received, w9Date: vendor.w9ReceivedDate,
                                  preferredPayment: preferred.isEmpty ? nil : preferred)
        }
    }

    private func matches(_ row: VendorTableRow, _ filter: VendorFilter) -> Bool {
        switch filter {
        case .all: true
        case .withBalance: row.openBalance > 0
        case .form1099: row.is1099
        }
    }

    private func filtered(_ rows: [VendorTableRow]) -> [VendorTableRow] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            matches(row, filter) && (text.isEmpty
                || row.name.localizedStandardContains(text)
                || row.category.localizedStandardContains(text)
                || row.email.localizedStandardContains(text))
        }
    }

    var body: some View {
        let rows = active
        let shown = filtered(rows)
        let owed = rows.reduce(0) { $0 + $1.openBalance }
        let with1099 = rows.filter(\.is1099).count
        MacTablePage(
            title: String(localized: "Proveedores"),
            subtitle: String(localized: "\(String(localized: "\(rows.count) proveedores")) · \(owed.money) por pagar"),
            rows: shown,
            footer: shown.count == rows.count ? String(localized: "\(rows.count) proveedores")
                : String(localized: "\(shown.count) de \(rows.count) proveedores"),
            query: $query, searchPrompt: Text("Nombre o categoría"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\VendorTableRow.spentThisYear, order: .reverse)],
            addTitle: String(localized: "Nuevo proveedor"), onAdd: { creating = true },
            onOpen: { openedVendor = $0.vendor },
            empty: rows.isEmpty
                ? MacTableEmpty(systemImage: "shippingbox", title: String(localized: "Sin proveedores"),
                                message: String(localized: "Añade a quienes te venden bienes o servicios."),
                                actionTitle: String(localized: "Nuevo proveedor"), action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ningún proveedor coincide con la búsqueda o el filtro."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { _ in String(localized: "Proveedor") },
            inspectorPlaceholder: String(localized: "Selecciona un proveedor para ver sus detalles.")
        ) {
            TableColumn("Proveedor", value: \.name) { row in
                HStack(spacing: 8) {
                    VendorMonogram(initials: Initials.from(row.name), side: 18)
                    Text(row.name).lineLimit(1)
                }
            }
            .width(min: 120, ideal: 170)
            TableColumn("Categoría", value: \.category) { row in
                MacCellText(text: row.category.isEmpty ? "—" : row.category).lineLimit(1)
            }
            .width(min: 70, ideal: 110, max: 200)
            TableColumn("Por pagar", value: \.openBalance) { row in
                MacCellText(text: row.openBalance > 0 ? row.openBalance.money : "—",
                            color: row.openBalance > 0 ? Palette.ink : Palette.ink2)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 84, max: 130)
            .alignment(.trailing)
            TableColumn(Text("Gastado \(Date.now.formatted(.appDateTime.year()))"), value: \.spentThisYear) { row in
                Text(row.spentThisYear.money).monospacedDigit()
            }
            .width(min: 80, ideal: 96, max: 140)
            .alignment(.trailing)
            TableColumn("1099", value: \.form1099Rank) { row in
                Form1099Cell(is1099: row.is1099)
            }
            .width(min: 36, ideal: 40, max: 60)
            .alignment(.center)
            TableColumn("Última compra", value: \.lastPurchaseRank) { row in
                MacCellText(text: row.lastPurchase?.dayMonth ?? "—")
            }
            .width(min: 70, ideal: 84, max: 120)
        } filter: {
            HStack(spacing: 12) {
                MacTableFilter(title: String(localized: "Filtrar proveedores"), options: VendorFilter.allCases,
                               selection: $filter, label: \.localizedTitle) { option in
                    rows.filter { matches($0, option) }.count
                }
                .layoutPriority(1)
                if with1099 > 0 {
                    Spacer(minLength: 8)
                    Label {
                        Text("\(with1099) proveedores requieren formulario 1099-NEC para \(Date.now.formatted(.appDateTime.year()))")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Palette.info)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            }
        } inspector: { row in
            VendorInspector(row: row)
        } actions: { row in
            HStack(spacing: 8) {
                Button("Nuevo gasto") { addingExpense = row.vendor }.buttonStyle(.secondary)
                Button("Abrir ficha") { openedVendor = row.vendor }.buttonStyle(.primary)
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { VendorEditorView() }.editorSheetSizing() }
        .sheet(item: $addingExpense) { vendor in
            NavigationStack { ExpenseEditorView(preselectedVendor: vendor) }.editorSheetSizing()
        }
        .navigationDestination(item: $openedVendor) { VendorDetailView(vendor: $0) }
        #if DEBUG
        // `-qa.abrir 1` abre la ficha del proveedor de la fila elegida con `-qa.fila`.
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nuevo") { creating = true; return }
            guard UserDefaults.standard.bool(forKey: "qa.abrir"), let id = selection,
                  let vendor = vendors.first(where: { $0.id == id }) else { return }
            openedVendor = vendor
        }
        #endif
    }
}

/// Fila de la tabla de proveedores: el proveedor con lo que se muestra y se ordena ya calculado (la categoría sale del
/// plan de cuentas, que el modelo no conoce). `nonisolated` para que sus key paths sirvan a `KeyPathComparator`.
nonisolated struct VendorTableRow: Identifiable {
    let vendor: Vendor
    let id: UUID
    let name: String
    let category: String
    let openBalance: Int64
    let spentThisYear: Int64
    let paidThisYear: Int64
    let lastPurchase: Date?
    let is1099: Bool
    let email: String
    let w9Received: Bool
    let w9Date: Date?
    /// «Transferencia · Corriente ••4821», o `nil` sin preferencia.
    let preferredPayment: String?

    /// Claves de orden: los que requieren 1099 primero al ordenar de mayor a menor; sin compras, al final.
    var form1099Rank: Int { is1099 ? 1 : 0 }
    var lastPurchaseRank: Date { lastPurchase ?? .distantPast }
}

/// Monograma gris del proveedor (canvas: 18 pt en la fila, 40 en el inspector).
private struct VendorMonogram: View {
    let initials: String
    @ScaledMetric private var side: CGFloat

    init(initials: String, side: CGFloat) {
        self.initials = initials
        _side = ScaledMetric(wrappedValue: side, relativeTo: .body)
    }

    var body: some View {
        Text(initials)
            .font(.system(size: side * 0.42, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            .background(Palette.monogram, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Celda «1099»: una marca en azul (blanca sobre la fila elegida) o una raya.
private struct Form1099Cell: View {
    let is1099: Bool
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if is1099 {
            Image(systemName: "checkmark")
                .fontWeight(.bold)
                .foregroundStyle(prominence == .increased ? Color.white : Palette.brand)
                .accessibilityLabel("Requiere 1099")
        } else {
            MacCellText(text: "—").accessibilityLabel("No requiere 1099")
        }
    }
}

/// Inspector del proveedor (canvas `MacProveedores`, `MacProveedorFicha`): monograma, nombre y categoría; Resumen (Por
/// pagar, Gastado en el año, Última compra, Pago preferido) e Impuestos (Formulario 1099 y W-9, con su nota).
private struct VendorInspector: View {
    let row: VendorTableRow

    private var yearText: String { Date.now.formatted(.appDateTime.year()) }

    /// Nota del 1099 con lo que hay en los libros: el umbral de $600 se compara con lo pagado en el año.
    private var note1099: String {
        guard row.is1099 else { return String(localized: "Este proveedor no se reporta en el formulario 1099-NEC.") }
        if row.paidThisYear >= 60_000 {
            return String(localized: "Pagos en \(yearText): \(row.paidThisYear.money), por encima del mínimo de $600. Envíale el 1099-NEC antes del 31 de enero.")
        }
        return String(localized: "Si le pagas $600 o más en el año, envíale el 1099-NEC antes del 31 de enero.")
    }

    var body: some View {
        HStack(spacing: 10) {
            VendorMonogram(initials: Initials.from(row.name), side: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.body.weight(.bold)).foregroundStyle(Palette.ink).lineLimit(2)
                if !row.category.isEmpty {
                    Text(row.category).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        MacInspectorSection(title: String(localized: "Resumen")) {
            MacInspectorRow(String(localized: "Por pagar"), value: row.openBalance.money)
            MacInspectorRow(String(localized: "Gastado en \(yearText)"), value: row.spentThisYear.money)
            MacInspectorRow(String(localized: "Última compra"), value: row.lastPurchase?.dayMonth ?? "—")
            MacInspectorRow(String(localized: "Pago preferido"), value: row.preferredPayment ?? String(localized: "Sin preferencia"),
                            color: row.preferredPayment == nil ? Palette.ink2 : Palette.ink)
        }
        VStack(alignment: .leading, spacing: 6) {
            MacInspectorSection(title: String(localized: "Impuestos")) {
                MacInspectorRow(label: String(localized: "Formulario 1099")) {
                    HStack(spacing: 5) {
                        StatusDot(color: row.is1099 ? Palette.teal : Palette.gray)
                        Text(row.is1099 ? String(localized: "Requiere 1099-NEC") : String(localized: "No aplica"))
                            .foregroundStyle(row.is1099 ? Palette.info : Palette.ink2)
                    }
                }
                if row.is1099 || row.w9Received {
                    MacInspectorRow(label: String(localized: "Formulario W-9")) {
                        HStack(spacing: 5) {
                            StatusDot(color: row.w9Received ? Palette.green : Palette.orange)
                            Text(row.w9Received ? (row.w9Date.map { String(localized: "Recibido el \($0.dayMonth)") } ?? String(localized: "Recibido"))
                                                : String(localized: "Pendiente"))
                                .foregroundStyle(row.w9Received ? Palette.positive : Palette.warning)
                        }
                    }
                }
            }
            Text(note1099)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
