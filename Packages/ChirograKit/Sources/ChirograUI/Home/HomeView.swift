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
    @Query private var expenses: [Expense]
    @Query private var customers: [Customer]

    @State private var months = 6
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var quickActionSide: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var dateTileWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var tableNumberWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .subheadline) private var tableAmountWidth: CGFloat = 90
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

    /// Diseño de `MacInicio`: en iPad y Mac con al menos 600 pt (iPad vertical con la barra lateral), hasta AX3.
    private var isWide: Bool {
        !isNarrow && dynamicTypeSize < .accessibility4 && (width == 0 || width - 2 * margin >= 600)
    }

    /// Tarjetas de dos en dos cuando hay sitio (y sin tamaños de accesibilidad, que necesitan todo el ancho).
    private var pairsCards: Bool { isWide && !dynamicTypeSize.isAccessibilitySize && width - 2 * margin >= 860 }

    /// En pantallas anchas el margen coincide con el del título grande.
    private var margin: CGFloat { isNarrow ? Metrics.gutter : 20 }

    private var cashDetail: String {
        String(localized: "En \(ledger.moneyAccounts.filter { $0.subtype != .undepositedFunds }.count) cuentas")
    }

    /// Primera vez (canvas `EstadoVacio`): todavía no hay movimientos ni facturas.
    private var isFirstUse: Bool { journalLines.isEmpty && invoices.isEmpty && expenses.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isWide ? 16 : Metrics.cardSpacing) {
                Text(isFirstUse ? companies.first?.displayName ?? "" : Date.now.monthYear)
                    .font(.subheadline).foregroundStyle(Palette.ink3)

                if isFirstUse {
                    firstSteps
                    emptyDashboard
                } else if isWide {
                    KPIGrid(items: wideKPIs, large: true)
                    pair { chart } and: { bankAccounts }
                    // Por pagar no se estira: con una sola fila quedaba una tarjeta casi vacía.
                    pair(fill: false) { receivables } and: { payables }
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
            .frame(maxWidth: isFirstUse ? 720 : isWide ? .infinity : 1100, alignment: .leading)
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

    // MARK: Primera vez (`EstadoVacio`)

    /// Pasos del MVP (el canvas incluye importar el banco y escanear recibos, que son de la fase 2).
    private var steps: [(title: String, done: Bool, action: QuickAction?)] {
        [(String(localized: "Crear tu empresa"), true, nil),
         (String(localized: "Añadir tu primer cliente"), !customers.isEmpty, .customer),
         (String(localized: "Crear tu primera factura"), !invoices.isEmpty, .invoice),
         (String(localized: "Registrar un gasto"), !expenses.isEmpty, .expense)]
    }

    private var firstSteps: some View {
        let done = steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Primeros pasos").font(.headline).foregroundStyle(Palette.ink)
                    Text("\(done) de \(steps.count) completados").font(.footnote).foregroundStyle(Palette.ink3)
                }
            }
            ProgressView(value: Double(done), total: Double(steps.count))
                .tint(Palette.brand)
                .accessibilityLabel("Progreso")
            VStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { index in
                    let step = steps[index]
                    if index > 0 { Divider() }
                    Button { if let action = step.action, !step.done { sheet = action } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: step.done ? "checkmark" : "circle")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(step.done ? Palette.positive : .clear)
                                .frame(width: 26, height: 26)
                                .background(step.done ? Palette.positiveWash : .clear, in: Circle())
                                .overlay(Circle().stroke(step.done ? .clear : Palette.separator, lineWidth: 2))
                                .accessibilityHidden(true)
                            Text(step.title).fontWeight(step.done ? .regular : .semibold)
                                .foregroundStyle(step.done ? Palette.ink3 : Palette.ink)
                            Spacer(minLength: 8)
                            if !step.done {
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
                            }
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(step.done)
                    .accessibilityValue(step.done ? Text("Completado") : Text("Pendiente"))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyDashboard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array([24, 40, 30, 52, 44, 62].enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 4).fill(index >= 4 ? Palette.brandWash : Palette.surface2)
                        .frame(width: 14, height: CGFloat(height))
                }
            }
            .accessibilityHidden(true)
            Text("Aquí verás cómo va tu negocio").font(.headline).foregroundStyle(Palette.ink)
            Text("Cuando registres ventas y gastos, aparecerán tu efectivo, tus ingresos del mes y lo que te deben.")
                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            Button("Crear tu primera factura") { sheet = .invoice }
                .buttonStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    /// Dos tarjetas lado a lado si hay sitio; si no, una debajo de otra.
    @ViewBuilder
    private func pair<First: View, Second: View>(fill: Bool = true, @ViewBuilder _ first: () -> First,
                                                 @ViewBuilder and second: () -> Second) -> some View {
        if pairsCards && !fill {
            HStack(alignment: .top, spacing: 16) {
                first().frame(maxWidth: .infinity)
                second().frame(maxWidth: .infinity)
            }
        } else if pairsCards {
            // Las dos tarjetas con la altura de la más alta, sin hueco debajo de la más baja.
            HStack(alignment: .top, spacing: 16) {
                first().frame(maxWidth: .infinity, maxHeight: .infinity)
                second().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(\.cardFillsHeight, true)
            .fixedSize(horizontal: false, vertical: true)
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

    /// `Home`: tres tarjetas de la misma altura, cifras sin centavos y nota de una línea. Con tamaños de
    /// accesibilidad, una tarjeta por fila: en tres columnas se partían palabras y cifras.
    private var kpis: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            KPITile(title: String(localized: "Ingresos"), value: thisMonth.totalIncome.moneyWhole,
                    note: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).text,
                    noteColor: change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true).color)
            KPITile(title: String(localized: "Gastos"), value: (thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold).moneyWhole,
                    note: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                 lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).text,
                    noteColor: change(thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold,
                                      lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold, higherIsBetter: false).color)
            KPITile(title: String(localized: "Ganancia neta"), value: thisMonth.netIncome.moneyWhole,
                    note: thisMonth.totalIncome > 0 ? String(localized: "Margen \(thisMonth.netIncome * 100 / thisMonth.totalIncome)%") : nil)
        }
        .environment(\.cardFillsHeight, !dynamicTypeSize.isAccessibilitySize)
        .fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
    }

    private func change(_ current: Int64, _ previous: Int64, higherIsBetter: Bool) -> (text: String?, color: Color) {
        guard previous != 0 else { return (nil, Palette.ink3) }
        let percent = (current - previous) * 100 / abs(previous)
        let good = higherIsBetter ? percent >= 0 : percent <= 0
        let arrow = percent >= 0 ? "↑" : "↓"
        let month = Calendar.current.date(byAdding: .month, value: -1, to: .now)?.shortMonth ?? ""
        return (String(localized: "\(arrow) \(abs(percent))% vs. \(month)"), good ? Palette.positive : Palette.negative)
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
                BarMark(x: .value("Mes", point.month, unit: .month), y: .value("Importe", point.amount),
                        width: .fixed(months == 6 ? 16 : 8))
                    .foregroundStyle(by: .value("Serie", point.series))
                    .position(by: .value("Serie", point.series))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale([String(localized: "Ingresos"): Palette.brand, String(localized: "Gastos"): Palette.expenseBar])
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
            // `Home`: pocas guías discontinuas con cifras redondas («$10K»).
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Palette.separator)
                    AxisValueLabel {
                        if let amount = value.as(Double.self), amount > 0 {
                            Text(amount.formatted(.currency(code: "USD").notation(.compactName).precision(.fractionLength(0))))
                        }
                    }
                }
            }
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
            if isWide {
                // `MacInicio`: tabla Nº · cliente · estado · importe, las vencidas primero.
                ForEach(openInvoices.sorted { ($0.daysOverdue() ?? -1) > ($1.daysOverdue() ?? -1) }.prefix(5)) { invoice in
                    Divider()
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                        HStack(spacing: 12) {
                            Text(invoice.number).foregroundStyle(Palette.ink3).frame(width: tableNumberWidth, alignment: .leading)
                            Text(invoice.customer?.name ?? String(localized: "Sin cliente")).fontWeight(.semibold).lineLimit(1)
                            Spacer(minLength: 8)
                            StatusChip(invoice: invoice)
                            Text(invoice.balanceDue.money).fontWeight(.semibold).frame(minWidth: tableAmountWidth, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            } else {
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
            }
            if openInvoices.isEmpty {
                Text("No tienes facturas pendientes de cobro.").font(.subheadline).foregroundStyle(Palette.ink3)
            }
            Divider()
            NavigationLink { SalesView() } label: {
                HStack {
                    Text("Ver todas las facturas").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.brand)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private var payables: some View {
        let soon = bills.filter { $0.isOpen && $0.dueDate <= Calendar.current.date(byAdding: .day, value: 14, to: .now)! }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Por pagar · próximos 14 días").font(.cardTitle)
            if isWide {
                // `MacInicio`: tabla fecha · proveedor · número · importe.
                ForEach(soon) { bill in
                    Divider()
                    HStack(spacing: 12) {
                        Text(bill.dueDate.dayMonth).foregroundStyle(Palette.ink3).frame(width: tableNumberWidth, alignment: .leading)
                        Text(bill.vendor?.name ?? String(localized: "Proveedor")).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(bill.vendorNumber).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                        Text(bill.balanceDue.money).fontWeight(.semibold).frame(minWidth: tableAmountWidth, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                }
            } else {
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
            }
            if soon.isEmpty {
                Text("Nada por pagar en las próximas dos semanas.").font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
        .card()
    }

    /// Cuentas bancarias y tarjetas; caja y fondos no depositados sólo si tienen saldo (M4).
    private var bankAccounts: some View {
        let shown = ledger.moneyAccounts.filter { account in
            account.subtype == .bank || account.subtype == .creditCard || ledger.balance(of: account) != 0
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cuentas bancarias").font(.cardTitle)
            ForEach(shown) { account in
                Divider()
                LedgerRow(title: account.name, subtitle: "\(account.code) · \(account.subtype.title)") {
                    IconTile(systemImage: account.subtype == .creditCard ? "creditcard" : "building.columns")
                } trailing: {
                    Text(ledger.cashBalance(of: account).money).font(.body.weight(.semibold)).monospacedDigit()
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
