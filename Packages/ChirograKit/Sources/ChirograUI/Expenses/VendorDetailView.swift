import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ficha de proveedor de solo lectura (canvas `ProveedorFicha`): cabecera, tres cifras, la próxima factura por pagar
/// e historial de gastos y facturas. Se edita desde «Editar».
struct VendorDetailView: View {
    let vendor: Vendor
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var editing = false
    @State private var paying: Bill?

    private var year: Int { Calendar.current.component(.year, from: .now) }
    private var bills: [Bill] { (vendor.bills ?? []).filter { $0.status != .void } }
    private var expenses: [Expense] { vendor.expenses ?? [] }
    private var category: String? { accounts.first { $0.id == vendor.defaultExpenseAccountID }?.name }
    private var nextBill: Bill? { bills.filter(\.isOpen).min { $0.dueDate < $1.dueDate } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                ProfileHeader(systemImage: "shippingbox", name: vendor.name, detail: headerDetail,
                              foreground: Palette.outflow, background: Palette.outflowWash)
                HStack(spacing: 8) {
                    MiniStat(title: String(localized: "Por pagar"), value: vendor.openBalance.money)
                    MiniStat(title: String(localized: "Gastado \(Date.now.formatted(.dateTime.year()))"), value: spentThisYear.money)
                    MiniStat(title: String(localized: "Compras"), value: (bills.count + expenses.count).formatted())
                }
                if let nextBill { billCard(nextBill) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Historial").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    if let category { Text("Categoría predeterminada: \(category)").font(.footnote).foregroundStyle(Palette.ink3) }
                }
                .padding(.top, 4)
                history
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .inlineTitle()
        .toolbar { Button("Editar") { editing = true } }
        .sheet(isPresented: $editing) { NavigationStack { VendorEditorView(vendor: vendor) } }
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) } }
    }

    /// «Materiales · Neto 30 · desde 2024».
    private var headerDetail: String {
        let since = ([vendor.createdAt] + bills.map(\.billDate) + expenses.map(\.date)).min() ?? vendor.createdAt
        let terms = vendor.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(vendor.paymentTermsDays)")
        return ([category, terms, String(localized: "desde \(since.formatted(.dateTime.year()))")].compactMap { $0 }).joined(separator: " · ")
    }

    private var spentThisYear: Int64 {
        let calendar = Calendar.current
        return bills.filter { calendar.component(.year, from: $0.billDate) == year }.reduce(0) { $0 + $1.total }
            + expenses.filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.total }
    }

    private func billCard(_ bill: Bill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow {
                Text("Factura por pagar \(bill.vendorNumber)").font(.headline).foregroundStyle(Palette.ink)
            } trailing: {
                StatusChip(bill: bill)
            }
            AdaptiveRow(alignment: .firstTextBaseline) {
                Text(bill.memo.isEmpty ? bill.dueDate.dueLabel : "\(bill.memo) · \(bill.dueDate.dueLabel)")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
            } trailing: {
                Text(bill.balanceDue.money).font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Palette.ink)
            }
            Button("Registrar pago") { paying = bill }.buttonStyle(.primary)
            Text("El pago se registra en tus libros; el dinero se mueve desde tu banco.")
                .font(.caption).foregroundStyle(Palette.ink3)
        }
        .card()
    }

    private enum Item: Identifiable {
        case bill(Bill), expense(Expense)
        var id: UUID { switch self { case .bill(let bill): bill.id; case .expense(let expense): expense.id } }
        var date: Date { switch self { case .bill(let bill): bill.billDate; case .expense(let expense): expense.date } }
    }

    private var history: some View {
        let items = (bills.map(Item.bill) + expenses.map(Item.expense)).sorted { $0.date > $1.date }
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text("Sin compras todavía").foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                switch item {
                case .bill(let bill):
                    row(title: String(localized: "Factura \(bill.vendorNumber) · \(bill.status == .paid ? String(localized: "pagada") : String(localized: "por pagar"))"),
                        subtitle: bill.billDate.dayMonth, hasReceipt: !(bill.attachments ?? []).isEmpty, amount: bill.total)
                case .expense(let expense):
                    NavigationLink { ExpenseDetailView(expense: expense) } label: {
                        row(title: expense.memo.isEmpty ? String(localized: "Gasto") : String(localized: "Gasto · \(expense.memo)"),
                            subtitle: "\(expense.date.dayMonth) · \(accounts.first { $0.id == expense.paymentAccountID }?.name ?? "")",
                            hasReceipt: !(expense.attachments ?? []).isEmpty, amount: expense.total)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: 12)
    }

    private func row(title: String, subtitle: String, hasReceipt: Bool, amount: Int64) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if hasReceipt {
                Image(systemName: "paperclip").foregroundStyle(Palette.ink3).accessibilityLabel("Recibo adjunto")
            }
            Text(amount.money).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
