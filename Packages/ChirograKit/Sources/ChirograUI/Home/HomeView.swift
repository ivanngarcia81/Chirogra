import Charts
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Inicio (canvas: `Home`, `MacInicio`): efectivo, resultado del mes, acciones rápidas,
/// ingresos vs. gastos, por cobrar, por pagar y cuentas.
struct HomeView: View {
    @Query private var companies: [Company]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \Invoice.dueDate) private var invoices: [Invoice]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]

    @State private var months = 6
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var quickActionSide: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var dateTileWidth: CGFloat = 44
    @State private var sheet: QuickAction?

    enum QuickAction: String, Identifiable {
        case invoice, expense, customer
        var id: String { rawValue }
    }

    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }
    private var thisMonth: IncomeStatement { ledger.incomeStatement(.month(containing: .now)) }
    private var lastMonth: IncomeStatement { ledger.incomeStatement(.month(containing: .now, offset: -1)) }
    private var openInvoices: [Invoice] { invoices.filter { $0.isOpen && $0.balanceDue > 0 } }
    private var overdue: [Invoice] { openInvoices.filter { $0.daysOverdue() != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                Text(Date.now.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.subheadline).foregroundStyle(Palette.ink3)

                HeroCard(title: "Efectivo disponible", value: ledger.availableCash.money,
                         detail: "En \(ledger.moneyAccounts.filter { $0.subtype != .undepositedFunds }.count) cuentas")

                kpis
                quickActions
                chart
                receivables
                payables
                bankAccounts
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Inicio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Factura", systemImage: "doc.badge.plus") { sheet = .invoice }
                    Button("Gasto", systemImage: "wallet.bifold") { sheet = .expense }
                    Button("Cliente", systemImage: "person.badge.plus") { sheet = .customer }
                } label: { Label("Nuevo", systemImage: "plus") }
            }
        }
        .sheet(item: $sheet) { action in
            NavigationStack {
                switch action {
                case .invoice: InvoiceEditorView()
                case .expense: ExpenseEditorView()
                case .customer: CustomerEditorView()
                }
            }
        }
    }

    private var kpis: some View {
        // Con tamaños de accesibilidad, una tarjeta por fila: en tres columnas se partían palabras y cifras.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            KPITile(title: "Ingresos", value: thisMonth.totalIncome.money,
                    note: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).text,
                    noteColor: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).color)
            KPITile(title: "Gastos", value: (thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold).money,
                    note: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                 lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).text,
                    noteColor: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                      lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).color)
            KPITile(title: "Ganancia neta", value: thisMonth.netIncome.money,
                    note: thisMonth.totalIncome > 0 ? "Margen \(thisMonth.netIncome * 100 / thisMonth.totalIncome)%" : nil)
        }
    }

    private func change(_ current: Int64, _ previous: Int64, higherIsBetter: Bool) -> (text: String?, color: Color) {
        guard previous != 0 else { return (nil, Palette.ink3) }
        let percent = (current - previous) * 100 / abs(previous)
        let good = higherIsBetter ? percent >= 0 : percent <= 0
        return ("\(percent >= 0 ? "↑" : "↓") \(abs(percent))% vs. mes ant.", good ? Palette.positive : Palette.negative)
    }

    private var quickActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            quickAction("Factura", "doc.badge.plus", .invoice, prominent: true)
            quickAction("Gasto", "wallet.bifold", .expense)
            quickAction("Cliente", "person.badge.plus", .customer)
        }
    }

    /// Icono sobre el título; con tamaños de accesibilidad, icono a la izquierda y una acción por fila.
    private func quickAction(_ title: String, _ image: String, _ action: QuickAction, prominent: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 6))
        return Button { sheet = action } label: {
            layout {
                Image(systemName: image)
                    .font(.title2)
                    .frame(width: quickActionSide, height: quickActionSide)
                    .foregroundStyle(prominent ? Palette.onBrand : Palette.brand)
                    .background(prominent ? Palette.brand : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
        }
        .buttonStyle(.plain)
    }

    private struct MonthPoint: Identifiable {
        let month: Date
        let series: String
        let amount: Double
        var id: String { "\(month.timeIntervalSince1970)-\(series)" }
    }

    private var chartPoints: [MonthPoint] {
        (0..<months).reversed().flatMap { offset -> [MonthPoint] in
            let interval = DateInterval.month(containing: .now, offset: -offset)
            let statement = ledger.incomeStatement(interval)
            return [
                MonthPoint(month: interval.start, series: "Ingresos", amount: Money(minorUnits: statement.totalIncome).decimalValue.doubleValue),
                MonthPoint(month: interval.start, series: "Gastos",
                           amount: Money(minorUnits: statement.totalExpenses + statement.totalCostOfGoodsSold).decimalValue.doubleValue),
            ]
        }
    }

    /// Resumen hablado de la gráfica: cifras de cada mes, como en la etiqueta del canvas.
    private var chartSummary: String {
        let months = Dictionary(grouping: chartPoints, by: \.month).sorted { $0.key < $1.key }
        return months.map { month, points in
            let income = points.first { $0.series == "Ingresos" }?.amount ?? 0
            let expense = points.first { $0.series == "Gastos" }?.amount ?? 0
            return "\(month.formatted(.dateTime.month(.wide))): ingresos \(income.formatted(.currency(code: "USD"))), "
                + "gastos \(expense.formatted(.currency(code: "USD")))"
        }
        .joined(separator: ". ")
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Ingresos vs. gastos").font(.cardTitle).fixedSize()
                    Spacer()
                    chartPeriodPicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingresos vs. gastos").font(.cardTitle)
                    chartPeriodPicker
                }
            }
            Chart(chartPoints) { point in
                BarMark(x: .value("Mes", point.month, unit: .month), y: .value("Importe", point.amount))
                    .foregroundStyle(by: .value("Serie", point.series))
                    .position(by: .value("Serie", point.series))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["Ingresos": Palette.brand, "Gastos": Palette.expenseBar])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
            // Los ejes no crecen más allá de xxxLarge (se amontonaban); las cifras completas están en el resumen de VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
            .accessibilityLabel("Ingresos y gastos de los últimos \(months) meses")
            .accessibilityValue(chartSummary)
        }
        .card()
    }

    private var chartPeriodPicker: some View {
        Picker("Periodo de la gráfica", selection: $months) {
            Text("6 M").tag(6)
            Text("12 M").tag(12)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var receivables: some View {
        let overdueTotal = overdue.reduce(0) { $0 + $1.balanceDue }
        let total = openInvoices.reduce(0) { $0 + $1.balanceDue }
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Por cobrar").font(.cardTitle).fixedSize()
                    Spacer()
                    Text(total.money).font(.amount(17)).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Por cobrar").font(.cardTitle)
                    Text(total.money).font(.amount(17))
                }
            }
            if total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Rectangle().fill(Palette.negative)
                            .frame(width: proxy.size.width * CGFloat(overdueTotal) / CGFloat(total))
                        Rectangle().fill(Palette.brand)
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
                let overdueText = Text("Vencidas · \(overdueTotal.money) (\(overdue.count))")
                    .foregroundStyle(Palette.negative).fontWeight(.semibold)
                let upcomingText = Text("Por vencer · \((total - overdueTotal).money) (\(openInvoices.count - overdue.count))")
                    .foregroundStyle(Palette.ink2)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        overdueText.fixedSize()
                        Spacer()
                        upcomingText.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        overdueText
                        upcomingText
                    }
                }
                .font(.footnote)
            }
            ForEach(openInvoices.prefix(3)) { invoice in
                Divider()
                NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                    LedgerRow(title: invoice.customer?.name ?? "Sin cliente",
                              subtitle: "\(invoice.number) · \(invoice.dueDate.dueLabel)") {
                        EmptyView()
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
                            Text(invoice.balanceDue.money).font(.body.weight(.semibold)).monospacedDigit()
                            StatusChip(invoice: invoice)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if openInvoices.isEmpty {
                Text("No tienes facturas pendientes de cobro.").font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
        .card()
    }

    private var payables: some View {
        let soon = bills.filter { $0.isOpen && $0.dueDate <= Calendar.current.date(byAdding: .day, value: 14, to: .now)! }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Por pagar · próximos 14 días").font(.cardTitle)
            ForEach(soon) { bill in
                Divider()
                LedgerRow(title: bill.vendor?.name ?? "Proveedor", subtitle: "Factura por pagar \(bill.vendorNumber)") {
                    VStack(spacing: 0) {
                        Text(bill.dueDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.caption2.weight(.bold)).foregroundStyle(Palette.outflow)
                        Text(bill.dueDate.formatted(.dateTime.day())).font(.headline)
                    }
                    .frame(minWidth: dateTileWidth)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vence el \(bill.dueDate.dayMonth)")
                    .padding(.vertical, 4)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 10))
                } trailing: {
                    Text(bill.balanceDue.money).font(.body.weight(.semibold)).monospacedDigit()
                }
            }
            if soon.isEmpty {
                Text("Nada por pagar en las próximas dos semanas.").font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
        .card()
    }

    private var bankAccounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cuentas").font(.cardTitle)
            ForEach(ledger.moneyAccounts) { account in
                Divider()
                LedgerRow(title: account.name, subtitle: account.subtype == .creditCard ? "Tarjeta de crédito" : "Saldo según libros") {
                    IconTile(systemImage: account.subtype == .creditCard ? "creditcard" : "building.columns")
                } trailing: {
                    let balance = ledger.balance(of: account)
                    Text((account.subtype == .creditCard ? -balance : balance).money).font(.body.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .card()
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

#Preview {
    NavigationStack { HomeView() }.modelContainer(SampleData.makeContainer())
}
