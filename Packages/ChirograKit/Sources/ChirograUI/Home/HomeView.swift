import Charts
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Inicio. iPhone sigue el tablero `Home`: efectivo, resultado del mes, acciones rápidas, gráfica, por cobrar,
/// por pagar y cuentas. iPad y Mac siguen `MacInicio`: cuatro cifras clave iguales, gráfica y cuentas lado a lado,
/// y por cobrar y por pagar lado a lado.
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
    @State private var width: CGFloat = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    enum QuickAction: String, Identifiable {
        case invoice, expense, customer
        var id: String { rawValue }
    }

    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }
    private var thisMonth: IncomeStatement { ledger.incomeStatement(.month(containing: .now)) }
    private var lastMonth: IncomeStatement { ledger.incomeStatement(.month(containing: .now, offset: -1)) }
    private var openInvoices: [Invoice] { invoices.filter { $0.isOpen && $0.balanceDue > 0 } }
    private var overdue: [Invoice] { openInvoices.filter { $0.daysOverdue() != nil } }

    private var isNarrow: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    /// Diseño de `MacInicio`: en iPad y Mac con al menos 700 pt, hasta AX3 incluido.
    private var isWide: Bool {
        !isNarrow && dynamicTypeSize < .accessibility4 && (width == 0 || width - 2 * margin >= 700)
    }

    /// Tarjetas de dos en dos cuando hay sitio (y sin tamaños de accesibilidad, que necesitan todo el ancho).
    private var pairsCards: Bool { isWide && !dynamicTypeSize.isAccessibilitySize && width - 2 * margin >= 860 }

    /// En pantallas anchas el margen coincide con el del título grande.
    private var margin: CGFloat { isNarrow ? Metrics.gutter : 20 }

    private var cashDetail: String {
        String(localized: "En \(ledger.moneyAccounts.filter { $0.subtype != .undepositedFunds }.count) cuentas")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isWide ? 16 : Metrics.cardSpacing) {
                Text(Date.now.monthYear)
                    .font(.subheadline).foregroundStyle(Palette.ink3)

                if isWide {
                    KPIGrid(items: wideKPIs, large: true)
                    pair { chart } and: { bankAccounts }
                    pair { receivables } and: { payables }
                } else {
                    HeroCard(title: String(localized: "Efectivo disponible"), value: ledger.availableCash.money, detail: cashDetail)
                    kpis
                    quickActions
                    chart
                    receivables
                    payables
                    bankAccounts
                }
            }
            .padding(.horizontal, margin)
            .padding(.vertical, Metrics.gutter)
            .frame(maxWidth: isWide ? .infinity : 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Inicio")
        .toolbar {
            if isWide {
                // `MacInicio`: «+ Gasto» neutro y «+ Factura» en color de marca junto al título.
                ToolbarItemGroup(placement: .primaryAction) {
                    // Icono y texto juntos: con `Label` la barra del iPad deja sólo el icono.
                    Button { sheet = .expense } label: { HStack(spacing: 4) { Image(systemName: "plus"); Text("Gasto") } }
                        .accessibilityLabel("Nuevo gasto")
                    Button { sheet = .invoice } label: { HStack(spacing: 4) { Image(systemName: "plus"); Text("Factura") } }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.brand)
                        .accessibilityLabel("Nueva factura")
                }
            } else {
                ToolbarItem(placement: .primaryAction) { newMenu }
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

    private var newMenu: some View {
        Menu {
            Button("Factura", systemImage: "doc.badge.plus") { sheet = .invoice }
            Button("Gasto", systemImage: "wallet.bifold") { sheet = .expense }
            Button("Cliente", systemImage: "person.badge.plus") { sheet = .customer }
        } label: { Label("Nuevo", systemImage: "plus").labelStyle(.iconOnly) }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(Palette.brand)
    }

    /// Dos tarjetas lado a lado si hay sitio; si no, una debajo de otra.
    @ViewBuilder
    private func pair<First: View, Second: View>(@ViewBuilder _ first: () -> First, @ViewBuilder and second: () -> Second) -> some View {
        if pairsCards {
            HStack(alignment: .top, spacing: 16) {
                first().frame(maxWidth: .infinity)
                second().frame(maxWidth: .infinity)
            }
        } else {
            first()
            second()
        }
    }

    /// `MacInicio`: efectivo disponible (destacada), ingresos, gastos y ganancia neta del mes.
    private var wideKPIs: [KPIItem] {
        let expenses = thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold
        let previousExpenses = lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold
        let income = change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true)
        let spent = change(expenses, previousExpenses, higherIsBetter: false)
        return [
            KPIItem(title: String(localized: "Efectivo disponible"), value: ledger.availableCash.money, foot: cashDetail, isBrand: true),
            KPIItem(title: String(localized: "Ingresos del mes"), value: thisMonth.totalIncome.money, foot: income.text, footColor: income.color),
            KPIItem(title: String(localized: "Gastos del mes"), value: expenses.money, foot: spent.text, footColor: spent.color),
            KPIItem(title: String(localized: "Ganancia neta"), value: thisMonth.netIncome.money,
                    foot: thisMonth.totalIncome > 0 ? String(localized: "Margen \(thisMonth.netIncome * 100 / thisMonth.totalIncome)%") : nil),
        ]
    }

    private var kpis: some View {
        // Con tamaños de accesibilidad, una tarjeta por fila: en tres columnas se partían palabras y cifras.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            KPITile(title: String(localized: "Ingresos"), value: thisMonth.totalIncome.money,
                    note: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).text,
                    noteColor: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).color)
            KPITile(title: String(localized: "Gastos"), value: (thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold).money,
                    note: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                 lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).text,
                    noteColor: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                      lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).color)
            KPITile(title: String(localized: "Ganancia neta"), value: thisMonth.netIncome.money,
                    note: thisMonth.totalIncome > 0 ? String(localized: "Margen \(thisMonth.netIncome * 100 / thisMonth.totalIncome)%") : nil)
        }
    }

    private func change(_ current: Int64, _ previous: Int64, higherIsBetter: Bool) -> (text: String?, color: Color) {
        guard previous != 0 else { return (nil, Palette.ink3) }
        let percent = (current - previous) * 100 / abs(previous)
        let good = higherIsBetter ? percent >= 0 : percent <= 0
        let arrow = percent >= 0 ? "↑" : "↓"
        return (String(localized: "\(arrow) \(abs(percent))% vs. mes ant."), good ? Palette.positive : Palette.negative)
    }

    private var quickActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            quickAction(String(localized: "Factura"), "doc.badge.plus", .invoice, prominent: true)
            quickAction(String(localized: "Gasto"), "wallet.bifold", .expense)
            quickAction(String(localized: "Cliente"), "person.badge.plus", .customer)
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
                MonthPoint(month: interval.start, series: String(localized: "Ingresos"), amount: Money(minorUnits: statement.totalIncome).decimalValue.doubleValue),
                MonthPoint(month: interval.start, series: String(localized: "Gastos"),
                           amount: Money(minorUnits: statement.totalExpenses + statement.totalCostOfGoodsSold).decimalValue.doubleValue),
            ]
        }
    }

    /// Resumen hablado de la gráfica: cifras de cada mes, como en la etiqueta del canvas.
    private var chartSummary: String {
        let months = Dictionary(grouping: chartPoints, by: \.month).sorted { $0.key < $1.key }
        return months.map { month, points in
            let income = points.first { $0.series == String(localized: "Ingresos") }?.amount ?? 0
            let expense = points.first { $0.series == String(localized: "Gastos") }?.amount ?? 0
            let name = month.formatted(.dateTime.month(.wide))
            let incomeText = income.formatted(.currency(code: "USD"))
            let expenseText = expense.formatted(.currency(code: "USD"))
            return String(localized: "\(name): ingresos \(incomeText), gastos \(expenseText)")
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
            .chartForegroundStyleScale([String(localized: "Ingresos"): Palette.brand, String(localized: "Gastos"): Palette.expenseBar])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
            // Los ejes no crecen más allá de xxxLarge (se amontonaban); las cifras completas están en el resumen de VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(height: dynamicTypeSize.isAccessibilitySize || isWide ? 220 : 150)
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
        .labelsHidden()
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
                    LedgerRow(title: invoice.customer?.name ?? String(localized: "Sin cliente"),
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
                LedgerRow(title: bill.vendor?.name ?? String(localized: "Proveedor"), subtitle: String(localized: "Factura por pagar \(bill.vendorNumber)")) {
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
                LedgerRow(title: account.name, subtitle: account.subtype == .creditCard ? String(localized: "Tarjeta de crédito") : String(localized: "Saldo según libros")) {
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
