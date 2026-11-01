import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

extension Bill {
    /// Abierta y con el vencimiento ya pasado.
    var isOverdue: Bool { isOpen && dueDate < Calendar.current.startOfDay(for: .now) }
}

extension Vendor {
    /// Fecha de la última factura o gasto.
    var lastPurchase: Date? {
        ((bills ?? []).filter { $0.status != .void }.map(\.billDate) + (expenses ?? []).map(\.date)).max()
    }

    func spent(inYearOf date: Date) -> Int64 {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return (bills ?? []).filter { $0.status != .void && calendar.component(.year, from: $0.billDate) == year }.reduce(0) { $0 + $1.total }
            + (expenses ?? []).filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.total }
    }
}

// MARK: - Gastos (`MacGastos`)

/// Tarjeta del mes con barra por categoría, búsqueda, «Solo sin recibo» y tabla FECHA · PROVEEDOR · CATEGORÍA ·
/// CUENTA DE PAGO · RECIBO · IMPORTE.
struct ExpenseTableView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var query = ""
    @State private var withoutReceipt = false
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    private func category(_ expense: Expense) -> Account? {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }
    }

    private var filtered: [Expense] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return expenses.filter { expense in
            (!withoutReceipt || (expense.attachments ?? []).isEmpty)
                && (text.isEmpty || expense.payee.localizedStandardContains(text)
                    || (category(expense)?.name.localizedStandardContains(text) ?? false) || expense.total.money.contains(text))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MacPageTitle(String(localized: "Gastos"))
                monthCard
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { search.frame(maxWidth: 320); receiptToggle; Spacer(minLength: 8); count }
                    VStack(alignment: .leading, spacing: 10) { search; HStack { receiptToggle; Spacer(minLength: 8); count } }
                }
                TableCard {
                    Text("Fecha").frame(width: 64, alignment: .leading)
                    Text("Proveedor").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Categoría").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cuenta de pago").frame(width: 170, alignment: .leading)
                    Text("Recibo").frame(width: 70, alignment: .center)
                    Text("Importe").frame(width: amountWidth, alignment: .trailing)
                } rows: {
                    ForEach(filtered) { expense in
                        NavigationLink { ExpenseDetailView(expense: expense) } label: { row(expense) }.buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text(expenses.isEmpty ? String(localized: "Sin gastos todavía") : String(localized: "Ningún gasto coincide"))
                            .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
    }

    private var search: some View { WideSearchField(prompt: "Proveedor, categoría o importe", text: $query) }

    private var receiptToggle: some View {
        Toggle("Solo sin recibo", isOn: $withoutReceipt).toggleStyle(.switch).fixedSize().font(.subheadline)
    }

    private var count: some View {
        Text("\(filtered.count) de \(expenses.count) gastos").font(.footnote).foregroundStyle(Palette.ink3)
    }

    private func row(_ expense: Expense) -> some View {
        let category = category(expense)
        return TableRow {
            Text(expense.date.dayMonth).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
            Text(expense.payee).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: ExpenseListView.symbol(for: category)).font(.caption)
                    .foregroundStyle(Palette.outflow)
                    .frame(width: 26, height: 26)
                    .background(Palette.outflowWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                // Dos líneas: las categorías largas («Materiales y suministros del trabajo») se cortaban.
                Text(category?.name ?? String(localized: "Sin categoría")).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(accounts.first { $0.id == expense.paymentAccountID }?.name ?? "—").foregroundStyle(Palette.ink2).lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Group {
                if (expense.attachments ?? []).isEmpty {
                    Text("—").foregroundStyle(Palette.ink3).accessibilityLabel("Sin recibo")
                } else {
                    Image(systemName: "paperclip").foregroundStyle(Palette.positive).accessibilityLabel("Recibo adjunto")
                }
            }
            .frame(width: 70)
            Text(expense.total.money).fontWeight(.semibold).frame(width: amountWidth, alignment: .trailing)
        }
    }

    /// Gastos del mes (mismas cifras que el estado de resultados), variación y barra por categoría.
    private var monthCard: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let month = DateInterval.month(containing: .now)
        let statement = ledger.incomeStatement(month)
        let previous = ledger.incomeStatement(.month(containing: .now, offset: -1))
        let rows = (statement.costOfGoodsSold + statement.expenses).filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
        let total = rows.reduce(0) { $0 + $1.amount }
        let previousTotal = previous.totalExpenses + previous.totalCostOfGoodsSold
        var slices = rows.prefix(4).map { (name: $0.account.name, amount: $0.amount) }
        let rest = rows.dropFirst(4).reduce(0) { $0 + $1.amount }
        if rest > 0 { slices.append((String(localized: "Otros"), rest)) }
        let colors = ExpenseListView.barColors
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) { monthTotal(total, previousTotal).frame(minWidth: 180, alignment: .leading); breakdown(slices, total, colors) }
            VStack(alignment: .leading, spacing: 14) { monthTotal(total, previousTotal); breakdown(slices, total, colors) }
        }
        .card()
    }

    private func monthTotal(_ total: Int64, _ previous: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Gastos de \(Date.now.formatted(.appDateTime.month(.wide)))").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            Text(total.money).font(.amount(28)).foregroundStyle(Palette.ink)
            if previous != 0 {
                let percent = (total - previous) * 100 / abs(previous)
                let month = Calendar.current.date(byAdding: .month, value: -1, to: .now)?.formatted(.appDateTime.month(.wide)) ?? ""
                Text("\(percent >= 0 ? "↑" : "↓") \(abs(percent))% vs. \(month)").font(.footnote.weight(.semibold))
                    .foregroundStyle(percent <= 0 ? Palette.positive : Palette.negative)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func breakdown(_ slices: [(name: String, amount: Int64)], _ total: Int64, _ colors: [Color]) -> some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(slices.indices, id: \.self) { index in
                            Rectangle().fill(colors[index])
                                .frame(width: max(2, (proxy.size.width - CGFloat(slices.count - 1) * 2) * CGFloat(slices[index].amount) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 18, alignment: .leading)], spacing: 6) {
                    ForEach(slices.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(colors[index]).frame(width: 9, height: 9).accessibilityHidden(true)
                            Text(slices[index].name).foregroundStyle(Palette.ink2).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(slices[index].amount.money).fontWeight(.semibold).foregroundStyle(Palette.ink).monospacedDigit()
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Sin gastos este mes").font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Proveedores (`MacProveedores`)

/// Búsqueda, chips Todos / Con saldo / 1099, aviso de 1099-NEC y tabla PROVEEDOR · CATEGORÍA · POR PAGAR ·
/// GASTADO · 1099 · ÚLTIMA COMPRA.
struct VendorTableView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos", withBalance = "Con saldo", form1099 = "1099"
        var id: String { rawValue }
    }

    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var query = ""
    @State private var filter: Filter = .all
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 120

    private var active: [Vendor] { vendors.filter { !$0.isArchived } }

    private func category(_ vendor: Vendor) -> String {
        accounts.first { $0.id == vendor.defaultExpenseAccountID }?.name ?? "—"
    }

    private var filtered: [Vendor] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return active.filter { vendor in
            let inFilter = switch filter {
            case .all: true
            case .withBalance: vendor.openBalance > 0
            case .form1099: vendor.is1099
            }
            return inFilter && (text.isEmpty || vendor.name.localizedStandardContains(text) || category(vendor).localizedStandardContains(text))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MacPageTitle(String(localized: "Proveedores"))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { search.frame(maxWidth: 320); chips; Spacer(minLength: 8); notice }
                    VStack(alignment: .leading, spacing: 10) { search; chips; notice }
                }
                TableCard {
                    Text("Proveedor").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Categoría").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Por pagar").frame(width: amountWidth, alignment: .trailing)
                    Text("Gastado \(Date.now.formatted(.appDateTime.year()))").frame(width: amountWidth + 10, alignment: .trailing)
                    Text("1099").frame(width: 60, alignment: .center)
                    Text("Última compra").frame(width: 110, alignment: .leading)
                } rows: {
                    ForEach(filtered) { vendor in
                        NavigationLink { VendorDetailView(vendor: vendor) } label: { row(vendor) }.buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text(vendors.isEmpty ? String(localized: "Sin proveedores") : String(localized: "Ningún proveedor coincide"))
                            .font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
    }

    private var search: some View { WideSearchField(prompt: "Nombre o categoría", text: $query) }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { option in
                FilterChip(title: option.localizedTitle, isSelected: filter == option) { filter = option }
            }
        }
    }

    @ViewBuilder
    private var notice: some View {
        let count = active.filter(\.is1099).count
        if count > 0 {
            Text("\(count) proveedores requieren formulario 1099-NEC para \(Date.now.formatted(.appDateTime.year()))")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.info)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Palette.infoWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func row(_ vendor: Vendor) -> some View {
        TableRow {
            HStack(spacing: 10) {
                InitialsTile(text: Initials.from(vendor.name), foreground: Palette.outflow, background: Palette.outflowWash)
                Text(vendor.name).fontWeight(.semibold).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(category(vendor)).foregroundStyle(Palette.ink2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(vendor.openBalance == 0 ? "—" : vendor.openBalance.money).fontWeight(.semibold)
                .foregroundStyle(vendor.openBalance == 0 ? Palette.ink3 : Palette.ink).frame(width: amountWidth, alignment: .trailing)
            Text(vendor.spent(inYearOf: .now).money).frame(width: amountWidth + 10, alignment: .trailing)
            Group {
                if vendor.is1099 {
                    StatusChip(text: "1099", foreground: Palette.info, background: Palette.infoWash)
                } else {
                    Text("—").foregroundStyle(Palette.ink3)
                }
            }
            .frame(width: 60)
            Text(vendor.lastPurchase?.dayMonth ?? "—").foregroundStyle(Palette.ink2).frame(width: 110, alignment: .leading)
        }
    }
}

// MARK: - Facturas por pagar (`MacPorPagar`)

/// Cifras, chips y tabla VENCE · PROVEEDOR · Nº · ESTADO · IMPORTE · ACCIÓN («Registrar pago»).
struct BillTableView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case open = "Por pagar", overdue = "Vencidas", thisWeek = "Esta semana", paid = "Pagadas"
        var id: String { rawValue }
    }

    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var filter: Filter = .open
    @State private var paying: Bill?
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    private var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now }

    private func matches(_ bill: Bill, _ filter: Filter) -> Bool {
        switch filter {
        case .open: bill.isOpen
        case .overdue: bill.isOverdue
        case .thisWeek: bill.isOpen && !bill.isOverdue && bill.dueDate < weekEnd
        case .paid: bill.status == .paid
        }
    }

    var body: some View {
        let open = bills.filter(\.isOpen)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MacPageTitle(String(localized: "Facturas por pagar"))
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Total por pagar"), value: open.reduce(0) { $0 + $1.balanceDue }.money),
                    KPIItem(title: String(localized: "Vencido"), value: open.filter(\.isOverdue).reduce(0) { $0 + $1.balanceDue }.money),
                    KPIItem(title: String(localized: "Vence esta semana"),
                            value: open.filter { !$0.isOverdue && $0.dueDate < weekEnd }.reduce(0) { $0 + $1.balanceDue }.money),
                ])
                HStack(spacing: 6) {
                    ForEach(Filter.allCases) { option in
                        FilterChip(title: option.localizedTitle, count: bills.filter { matches($0, option) }.count, isSelected: filter == option) { filter = option }
                    }
                }
                TableCard {
                    Text("Vence").frame(width: 80, alignment: .leading)
                    Text("Proveedor").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Nº").frame(width: 100, alignment: .leading)
                    Text("Estado").frame(width: 120, alignment: .leading)
                    Text("Importe").frame(width: amountWidth, alignment: .trailing)
                    Text("Acción").frame(width: 150, alignment: .trailing)
                } rows: {
                    let shown = bills.filter { matches($0, filter) }
                    ForEach(shown) { bill in
                        TableRow {
                            Text(bill.dueDate.dayMonth).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                                .frame(width: 80, alignment: .leading)
                            Group {
                                if let vendor = bill.vendor {
                                    NavigationLink(vendor.name) { VendorDetailView(vendor: vendor) }.buttonStyle(.plain).fontWeight(.semibold)
                                } else {
                                    Text("Proveedor").fontWeight(.semibold)
                                }
                            }
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(bill.vendorNumber).foregroundStyle(Palette.ink2).frame(width: 100, alignment: .leading)
                            Group {
                                if bill.isOverdue {
                                    StatusChip(text: String(localized: "Vencida"), foreground: Palette.negative, background: Palette.negativeWash)
                                } else {
                                    StatusChip(bill: bill)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            Text(bill.balanceDue == 0 ? bill.total.money : bill.balanceDue.money).fontWeight(.semibold)
                                .frame(width: amountWidth, alignment: .trailing)
                            Group {
                                if bill.isOpen {
                                    Button("Registrar pago") { paying = bill }
                                        .buttonStyle(.borderedProminent).tint(Palette.brand).foregroundStyle(Palette.onBrand).controlSize(.small)
                                        .accessibilityLabel("Registrar pago de \(bill.vendorNumber)")
                                }
                            }
                            .frame(width: 150, alignment: .trailing)
                        }
                    }
                    if shown.isEmpty {
                        Text("Sin facturas en esta vista").font(.subheadline).foregroundStyle(Palette.ink3)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.background)
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) } }
    }
}
