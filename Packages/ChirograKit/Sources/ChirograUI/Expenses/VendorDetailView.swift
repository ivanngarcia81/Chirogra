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
    @State private var addingExpense = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacProveedorFicha` en iPad y Mac (hasta AX3); la ficha del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    private var year: Int { Calendar.current.component(.year, from: .now) }
    private var bills: [Bill] { (vendor.bills ?? []).filter { $0.status != .void } }
    private var expenses: [Expense] { vendor.expenses ?? [] }
    private var category: String? { accounts.first { $0.id == vendor.defaultExpenseAccountID }?.name }
    private var nextBill: Bill? { bills.filter(\.isOpen).min { $0.dueDate < $1.dueDate } }

    var body: some View {
        Group {
            if isWide { wideBody } else { compactBody }
        }
        .background(Palette.background)
        .recordTitle(vendor.name, section: String(localized: "Proveedores"))
        .toolbar {
            Button("Editar") { editing = true }.headerButton()
            if isWide {
                Button { addingExpense = true } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Gasto") }
                }
                .accessibilityLabel("Nuevo gasto")
                .headerButton()
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { VendorEditorView(vendor: vendor) } }
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) } }
        .navigationDestination(isPresented: $addingExpense) { ExpenseEditorView(preselectedVendor: vendor) }
    }

    private var compactBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                ProfileHeader(systemImage: "shippingbox", name: vendor.name, detail: headerDetail,
                              foreground: Palette.outflow, background: Palette.outflowWash)
                HStack(spacing: 8) {
                    MiniStat(title: String(localized: "Por pagar"), value: vendor.openBalance.money)
                    MiniStat(title: String(localized: "Gastado \(Date.now.formatted(.appDateTime.year()))"), value: spentThisYear.money)
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
    }

    // MARK: iPad y Mac (`MacProveedorFicha`)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                wideHeader
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Por pagar"), value: vendor.openBalance.money),
                    KPIItem(title: String(localized: "Gastado en \(Date.now.formatted(.appDateTime.year()))"), value: spentThisYear.money),
                    KPIItem(title: String(localized: "Compras"), value: (bills.count + expenses.count).formatted()),
                ])
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { openBillsTable; historyTable }.frame(maxWidth: .infinity)
                        VStack(spacing: 16) { form1099Card; contactCard }.frame(width: 300)
                    }
                    VStack(spacing: 16) { openBillsTable; historyTable; form1099Card; contactCard }
                }
            }
            .padding(20)
        }
    }

    private var wideHeader: some View {
        HStack(spacing: 14) {
            Text(Initials.from(vendor.name))
                .font(.title3.weight(.bold))
                .frame(width: 52, height: 52)
                .foregroundStyle(Palette.outflow)
                .background(Palette.outflowWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(vendor.name).font(.title2.weight(.bold)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    if vendor.is1099 { StatusChip(text: "1099", foreground: Palette.info, background: Palette.infoWash) }
                }
                Text([category, headerDetail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
    }

    private var openBillsTable: some View {
        let open = bills.filter(\.isOpen).sorted { $0.dueDate < $1.dueDate }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Facturas por pagar").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TableCard {
                Text("Nº").frame(width: 90, alignment: .leading)
                Text("Concepto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Vence").frame(width: 80, alignment: .leading)
                Text("Importe").frame(width: 100, alignment: .trailing)
                Text("Acción").frame(width: 80, alignment: .trailing)
            } rows: {
                ForEach(open) { bill in
                    TableRow {
                        Text(bill.vendorNumber).fontWeight(.semibold).frame(width: 90, alignment: .leading)
                        Text(bill.memo.isEmpty ? (bill.sortedLines.first?.details ?? "—") : bill.memo).foregroundStyle(Palette.ink2)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(bill.dueDate.dayMonth).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                            .frame(width: 80, alignment: .leading)
                        Text(bill.balanceDue.money).fontWeight(.semibold).frame(width: 100, alignment: .trailing)
                        Button("Pagar") { paying = bill }
                            .glassActionButton().controlSize(.small)
                            .accessibilityLabel("Registrar pago de \(bill.vendorNumber)")
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                if open.isEmpty {
                    Text("Nada por pagar").font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    private var historyTable: some View {
        let items = (bills.map(Item.bill) + expenses.map(Item.expense)).sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Historial").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TableCard {
                Text("Fecha").frame(width: 70, alignment: .leading)
                Text("Concepto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cuenta").frame(width: 160, alignment: .leading)
                Text("Importe").frame(width: 100, alignment: .trailing)
            } rows: {
                ForEach(items) { item in
                    switch item {
                    case .bill(let bill):
                        historyRow(date: bill.billDate,
                                   concept: String(localized: "Factura \(bill.vendorNumber) · \(bill.status == .paid ? String(localized: "pagada") : String(localized: "por pagar"))"),
                                   account: String(localized: "Cuentas por pagar"), amount: bill.total)
                    case .expense(let expense):
                        NavigationLink { ExpenseDetailView(expense: expense) } label: {
                            historyRow(date: expense.date,
                                       concept: expense.memo.isEmpty ? String(localized: "Gasto") : String(localized: "Gasto · \(expense.memo)"),
                                       account: accounts.first { $0.id == expense.paymentAccountID }?.name ?? "—", amount: expense.total)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if items.isEmpty {
                    Text("Sin compras todavía").font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    private func historyRow(date: Date, concept: String, account: String, amount: Int64) -> some View {
        TableRow {
            Text(date.dayMonth).foregroundStyle(Palette.ink2).frame(width: 70, alignment: .leading)
            Text(concept).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(account).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 160, alignment: .leading)
            Text(amount.money).fontWeight(.semibold).frame(width: 100, alignment: .trailing)
        }
    }

    /// Solo lectura: se cambia desde «Editar». El W-9 no se guarda todavía.
    private var form1099Card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Formulario 1099").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Label(vendor.is1099 ? String(localized: "Requiere 1099") : String(localized: "No requiere 1099"),
                  systemImage: vendor.is1099 ? "checkmark.square.fill" : "square")
                .font(.subheadline).foregroundStyle(vendor.is1099 ? Palette.brand : Palette.ink2)
            LabeledContent("TIN", value: vendor.tinLast4.isEmpty ? "—" : "•••–••–\(vendor.tinLast4)").font(.subheadline)
            if vendor.is1099 {
                Text("Si le pagas $600 o más en el año, envíale el 1099-NEC antes del 31 de enero.")
                    .font(.caption).foregroundStyle(Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contacto").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            LabeledContent("Correo", value: vendor.email.isEmpty ? "—" : vendor.email.replacingOccurrences(of: "@", with: "@\u{200B}"))
            LabeledContent("Teléfono", value: vendor.phone.isEmpty ? "—" : vendor.phone)
            LabeledContent("Categoría", value: category ?? "—")
            LabeledContent("Plazo de pago", value: vendor.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(vendor.paymentTermsDays)"))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// «Neto 30 · desde 2024». La categoría va debajo de «Historial»: aquí, con nombres largos, partía el subtítulo.
    private var headerDetail: String {
        let since = ([vendor.createdAt] + bills.map(\.billDate) + expenses.map(\.date)).min() ?? vendor.createdAt
        let terms = vendor.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(vendor.paymentTermsDays)")
        return [terms, String(localized: "desde \(since.formatted(.appDateTime.year()))")].joined(separator: " · ")
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
