import Charts
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Inicio.
/// - iPhone (y la columna estrecha del iPad): tablero `Home` / `HomeOscuro`. Subtítulo «Empresa · Mes ▾» que elige el
///   mes, una sola tarjeta de resumen (efectivo y, debajo, ingresos · gastos · ganancia), acciones rápidas, gráfica con
///   «6 meses · 12 meses» y los grupos Por cobrar, Por pagar y Cuentas con su título fuera de la tarjeta.
/// - iPad: `iPadInicio` / `iPadInicioV` / `iPadInicioOscuro`, en maestro-detalle: columna con Efectivo, Resultados,
///   Por cobrar y Por pagar (la elegida rellena de Tinta) y, al lado, su detalle.
/// - Mac: `MacInicio`: cajas de cifras, gráfica de 12 meses con las cuentas al lado y las tablas de por cobrar y por
///   pagar; a la derecha, el inspector con la factura por cobrar elegida en la tabla (la primera si no hay otra).
/// - Primera vez: `EstadoVacio` (en todas, centrado y con ancho de lectura en iPad y Mac).
struct HomeView: View {
    @Query private var companies: [Company]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \Invoice.dueDate) private var invoices: [Invoice]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query private var expenses: [Expense]
    @Query private var customers: [Customer]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// Mes mostrado: 0 el actual, −1 el anterior…
    @State private var monthOffset = 0
    @State private var chartMonths = 6
    @State private var sheet: NewItem?
    @State private var width: CGFloat = 0
    /// Sección elegida en la columna del iPad (`iPadInicio`).
    @State private var padSection: PadSection = .results
    /// Aviso de la campana cuyo documento se abre encima.
    @State private var openedNotice: Notice?
    @ScaledMetric(relativeTo: .footnote) private var legendDot: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var padColumnWidth: CGFloat = 340
    #if os(macOS)
    /// Factura por cobrar elegida en la tabla para el inspector (`MacInicio`); sin elegir, la primera.
    @State private var macInvoiceID: UUID?
    @State private var payingInvoice: Invoice?
    @State private var openedInvoice: Invoice?
    @State private var openedCustomer: Customer?
    #endif

    enum NewItem: String, Identifiable {
        case invoice, expense, customer
        var id: String { rawValue }
    }

    enum PadSection: String, CaseIterable, Identifiable {
        case cash, results, receivables, payables
        var id: String { rawValue }
    }

    // MARK: Datos

    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }
    private var month: DateInterval { .month(containing: .now, offset: monthOffset) }
    private var thisMonth: IncomeStatement { ledger.incomeStatement(month) }
    private var lastMonth: IncomeStatement { ledger.incomeStatement(.month(containing: .now, offset: monthOffset - 1)) }
    private var openInvoices: [Invoice] { invoices.filter { $0.isOpen && $0.balanceDue > 0 } }
    private var overdue: [Invoice] { openInvoices.filter { $0.daysOverdue() != nil } }
    private var overdueTotal: Int64 { overdue.reduce(0) { $0 + $1.balanceDue } }
    private var receivableTotal: Int64 { openInvoices.reduce(0) { $0 + $1.balanceDue } }
    /// Las vencidas primero (las más atrasadas arriba) y después por vencimiento.
    private var receivableRows: [Invoice] {
        openInvoices.sorted { ($0.daysOverdue() ?? -1, $1.dueDate) > ($1.daysOverdue() ?? -1, $0.dueDate) }
    }
    /// Por pagar en los próximos 14 días (también las ya vencidas).
    private var soonBills: [Bill] {
        let limit = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        return bills.filter { $0.isOpen && $0.balanceDue > 0 && $0.dueDate <= limit }
    }
    private var monthExpenses: Int64 { thisMonth.totalExpenses + thisMonth.totalCostOfGoodsSold }
    private var previousExpenses: Int64 { lastMonth.totalExpenses + lastMonth.totalCostOfGoodsSold }
    private var companyName: String { companies.first?.displayName ?? "" }

    /// Cuentas de Inicio: bancos y tarjetas siempre; caja y fondos no depositados si tienen saldo.
    private var shownAccounts: [Account] {
        ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
    }

    /// Primera vez (`EstadoVacio`): todavía no hay movimientos ni documentos.
    private var isFirstUse: Bool { journalLines.isEmpty && invoices.isEmpty && expenses.isEmpty }

    // MARK: Diseño

    private enum Layout { case phone, pad, mac }

    private var layout: Layout {
        #if os(macOS)
        return .mac
        #else
        // El maestro-detalle necesita la columna de 340 y al menos 420 para el detalle; con letra de accesibilidad
        // grande, el diseño del iPhone (una columna) no corta nada.
        if sizeClass == .compact || dynamicTypeSize >= .accessibility2 { return .phone }
        if width > 0 && width < padColumnWidth + 420 { return .phone }
        return .pad
        #endif
    }

    var body: some View {
        Group {
            if isFirstUse {
                ScrollView { firstUse }
            } else {
                switch layout {
                case .phone: ScrollView { phoneBody }
                case .pad: padBody
                case .mac: ScrollView { macBody }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Inicio")
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle(isAvailable: !isFirstUse)
        #endif
        .toolbar { toolbar }
        .sheet(item: $sheet) { item in
            NavigationStack {
                switch item {
                case .invoice: InvoiceEditorView()
                case .expense: ExpenseEditorView()
                case .customer: CustomerEditorView()
                }
            }
            .editorSheetSizing()
        }
        .navigationDestination(item: $openedNotice) { NoticeDestination(notice: $0) }
        #if os(macOS)
        .macReportInspector(title: macInvoice.map(invoiceTitle) ?? String(localized: "Por cobrar"), hasSelection: macInvoice != nil,
                            placeholder: String(localized: "No tienes facturas pendientes de cobro."),
                            selectionKey: macInvoiceID?.uuidString, qaSelectRow: { index in
                                let rows = Array(receivableRows.prefix(8))
                                if rows.indices.contains(index) { macInvoiceID = rows[index].id }
                            }, isAvailable: !isFirstUse) {
            if let invoice = macInvoice { invoiceInspector(invoice) }
        } actions: {
            if let invoice = macInvoice { invoiceActions(invoice) }
        }
        .sheet(item: $payingInvoice) { invoice in NavigationStack { InvoicePaymentSheet(invoice: invoice) }.editorSheetSizing() }
        .navigationDestination(item: $openedInvoice) { InvoiceDetailView(invoice: $0) }
        .navigationDestination(item: $openedCustomer) { CustomerDetailView(customer: $0) }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch layout {
        case .phone:
            ToolbarItem(placement: .primaryAction) { bell }
            ToolbarItem(placement: .primaryAction) { newMenu }
            if let company = companies.first {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { companyButton(company) }
                    .sharedBackgroundVisibility(.hidden)
            }
        case .pad:
            ToolbarItem(placement: .primaryAction) { bell }
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .expense } label: { Label("Nuevo gasto", systemImage: "wallet.bifold") }.headerButton()
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                // Icono y texto juntos: con `Label` la barra del iPad deja solo el icono.
                Button { sheet = .invoice } label: { HStack(spacing: 6) { Image(systemName: "plus"); Text("Factura") } }
                    .accessibilityLabel("Nueva factura")
                    .headerButton()
            }
        case .mac:
            ToolbarItem(placement: .primaryAction) { if !isFirstUse { periodMenu(compact: false) } }
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { sheet = .expense } label: { HStack(spacing: 4) { Image(systemName: "plus"); Text("Gasto") } }
                        .accessibilityLabel("Nuevo gasto")
                    Button { sheet = .invoice } label: { HStack(spacing: 4) { Image(systemName: "plus"); Text("Factura") } }
                        .accessibilityLabel("Nueva factura")
                }
                .headerButton()
            }
            ToolbarItem(placement: .primaryAction) { bell }
        }
    }

    /// Campana de avisos (canvas `Home`, `iPadInicio`), junto a «+» en el mismo grupo de vidrio.
    private var bell: some View {
        NoticesButton { openedNotice = $0 }.headerButton()
    }

    private var newMenu: some View {
        Menu {
            Button("Factura", systemImage: "doc.badge.plus") { sheet = .invoice }
            Button("Gasto", systemImage: "wallet.bifold") { sheet = .expense }
            Button("Cliente", systemImage: "person.badge.plus") { sheet = .customer }
        } label: { Label("Nuevo", systemImage: "plus").labelStyle(.iconOnly) }
        .headerButton()
    }

    /// Monograma de la empresa (canvas: el de la cuenta), que abre los ajustes.
    private func companyButton(_ company: Company) -> some View {
        NavigationLink { SettingsView() } label: {
            Text(Initials.from(company.displayName.isEmpty ? company.legalName : company.displayName))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Palette.monogram, in: Circle())
        }
        .accessibilityLabel(String(localized: "Ajustes de \(companyName)"))
    }

    // MARK: Periodo

    /// «Octubre 2026 ▾»: elige el mes de las cifras (los últimos 12).
    private func periodMenu(compact: Bool, prefix: String? = nil) -> some View {
        Menu {
            Picker("Mes", selection: $monthOffset) {
                ForEach(0..<12, id: \.self) { offset in
                    Text(DateInterval.month(containing: .now, offset: -offset).start.monthYear).tag(-offset)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text([prefix, month.start.monthYear].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(compact ? .subheadline : .body)
            .foregroundStyle(compact ? Palette.ink2 : Palette.ink)
            .frame(minHeight: compact ? Metrics.target : nil)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Periodo")
        .accessibilityValue(month.start.monthYear)
    }

    // MARK: Cifras

    /// «▲ 12%» (verde si es favorable); `suffix` añade « vs. sep». `nil` si el mes anterior es cero.
    private func change(_ current: Int64, _ previous: Int64, higherIsBetter: Bool, monthStyle: MonthStyle? = nil) -> (text: String, color: Color)? {
        guard previous != 0 else { return nil }
        let percent = (current - previous) * 100 / abs(previous)
        let good = higherIsBetter ? percent >= 0 : percent <= 0
        let arrow = percent >= 0 ? "▲" : "▼"
        let text: String
        if let monthStyle {
            let previousMonth = DateInterval.month(containing: .now, offset: monthOffset - 1).start
            let name = monthStyle == .short ? previousMonth.shortMonth : previousMonth.formatted(.appDateTime.month(.wide))
            text = String(localized: "\(arrow) \(abs(percent))% vs. \(name)")
        } else {
            text = "\(arrow) \(abs(percent))%"
        }
        return (text, good ? Palette.positive : Palette.negative)
    }

    private enum MonthStyle { case short, long }

    private var margin: String? {
        thisMonth.totalIncome > 0 ? String(localized: "Margen \(thisMonth.netIncome * 100 / thisMonth.totalIncome)%") : nil
    }

    private var accountsDetail: String {
        String(localized: "\(shownAccounts.count) cuentas · según libros")
    }

    /// Ingresos · Gastos · Ganancia en tres columnas (`Home`: dentro de la tarjeta de efectivo; `iPadInicio`: en su
    /// propia tarjeta, con separadores verticales). Con letra de accesibilidad, una debajo de otra.
    private func resultColumns(large: Bool) -> some View {
        let income = change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true, monthStyle: large ? .short : nil)
        let spent = change(monthExpenses, previousExpenses, higherIsBetter: false, monthStyle: large ? .short : nil)
        let items: [(String, Int64, String?, Color)] = [
            (String(localized: "Ingresos"), thisMonth.totalIncome, income?.text, income?.color ?? Palette.ink2),
            (String(localized: "Gastos"), monthExpenses, spent?.text, spent?.color ?? Palette.ink2),
            (large ? String(localized: "Ganancia neta") : String(localized: "Ganancia"), thisMonth.netIncome, margin, Palette.ink2),
        ]
        let stacked = dynamicTypeSize.isAccessibilitySize
        let stack = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: large ? 16 : 8))
        return stack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: large ? 16 : 0) {
                    if large && index > 0 && !stacked {
                        Rectangle().fill(Palette.separator).frame(width: 0.5).frame(maxHeight: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(large ? .subheadline : .footnote).foregroundStyle(Palette.ink2)
                        Text(large ? item.1.money : item.1.moneyWhole)
                            .font(large ? .amount(24) : .headline).monospacedDigit()
                            .foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                        if let note = item.2 {
                            Text(note).font(.footnote).foregroundStyle(item.3).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.0)
                    .accessibilityValue([item.1.money, item.2.map(KPITile.spoken)].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// «Efectivo disponible» con la cifra grande y «● N cuentas · según libros».
    private func cashHeader(amountSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Efectivo disponible").font(.subheadline).foregroundStyle(Palette.ink2)
            Text(ledger.availableCash.money).font(.amount(amountSize)).foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                StatusDot(color: Palette.green)
                Text(accountsDetail)
            }
            .font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - iPhone (`Home`)

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            periodMenu(compact: true, prefix: companyName)
                .padding(.horizontal, Metrics.gutter)

            VStack(alignment: .leading, spacing: 14) {
                cashHeader(amountSize: 36)
                Rectangle().fill(Palette.separator).frame(height: 0.5)
                resultColumns(large: false)
            }
            .padding(18)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Resumen del mes")

            quickActions
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 20)

            groupTitle(String(localized: "Ingresos y gastos"))
            chartCard(height: dynamicTypeSize.isAccessibilitySize ? 220 : 150, barWidth: chartMonths == 6 ? 15 : 8,
                      pickerOnTop: true)
                .padding(.horizontal, Metrics.gutter)

            groupTitle(String(localized: "Por cobrar")) { seeAllInvoices }
            receivablesCard(limit: 3)
                .padding(.horizontal, Metrics.gutter)

            groupTitle(String(localized: "Por pagar · 14 días")) { seeAllBills }
            payablesCard
                .padding(.horizontal, Metrics.gutter)

            groupTitle(String(localized: "Cuentas")) { bankingLink }
            accountsCard
                .padding(.horizontal, Metrics.gutter)
        }
        .padding(.bottom, 24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    /// Título de grupo fuera de la tarjeta (`SectionHeader`), a 32 pt del borde como en el canvas.
    private func groupTitle(_ title: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        SectionHeader(title: title, trailing: trailing)
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 26)
            .padding(.bottom, 8)
    }

    private var seeAllInvoices: some View {
        SectionLink(item: .sales(.invoices)) { SalesView(fixedSegment: .invoices) } label: { Text("Ver todo") }
            .buttonStyle(.plain).foregroundStyle(Palette.brand)
    }

    private var seeAllBills: some View {
        SectionLink(item: .expenses(.bills)) { ExpensesView(fixedSegment: .bills) } label: { Text("Ver todo") }
            .buttonStyle(.plain).foregroundStyle(Palette.brand)
    }

    private var bankingLink: some View {
        SectionLink(item: .section(.banking)) { BankingView() } label: { Text("Banca") }
            .buttonStyle(.plain).foregroundStyle(Palette.brand)
    }

    /// Factura · Gasto · Cliente («Escanear» es de la fase 2). Con letra de accesibilidad, una fila por acción.
    @ViewBuilder
    private var quickActions: some View {
        let actions: [(String, String, NewItem)] = [
            (String(localized: "Factura"), "doc.badge.plus", .invoice),
            (String(localized: "Gasto"), "wallet.bifold", .expense),
            (String(localized: "Cliente"), "person.badge.plus", .customer),
        ]
        if dynamicTypeSize.isAccessibilitySize {
            HomeRowGroup(dividerInset: 16 + 30 + 12) {
                ForEach(actions, id: \.2) { action in
                    Button { sheet = action.2 } label: {
                        HomeRow(title: action.0, chevron: false) {
                            IconTile(systemImage: action.1, foreground: Palette.brand)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Acciones rápidas")
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(actions, id: \.2) { action in
                    QuickAction(title: action.0, systemImage: action.1) { sheet = action.2 }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Acciones rápidas")
        }
    }

    // MARK: Gráfica

    private struct MonthPoint: Identifiable {
        let month: Date
        let isIncome: Bool
        let amount: Double
        var id: String { "\(month.timeIntervalSince1970)-\(isIncome)" }
    }

    private func chartPoints(months: Int) -> [MonthPoint] {
        (0..<months).reversed().flatMap { back -> [MonthPoint] in
            let interval = DateInterval.month(containing: .now, offset: monthOffset - back)
            let statement = ledger.incomeStatement(interval)
            return [
                MonthPoint(month: interval.start, isIncome: true, amount: Money(minorUnits: statement.totalIncome).decimalValue.doubleValue),
                MonthPoint(month: interval.start, isIncome: false,
                           amount: Money(minorUnits: statement.totalExpenses + statement.totalCostOfGoodsSold).decimalValue.doubleValue),
            ]
        }
    }

    /// Resumen hablado: ingresos y gastos de cada mes.
    private func chartSummary(_ points: [MonthPoint]) -> String {
        Dictionary(grouping: points, by: \.month).sorted { $0.key < $1.key }.map { month, points in
            let income = (points.first { $0.isIncome }?.amount ?? 0).formatted(.currency(code: "USD"))
            let spent = (points.first { !$0.isIncome }?.amount ?? 0).formatted(.currency(code: "USD"))
            let name = month.formatted(.appDateTime.month(.wide))
            return String(localized: "\(name): ingresos \(income), gastos \(spent)")
        }
        .joined(separator: ". ")
    }

    /// Barras Tinta (ingresos) y naranja (gastos), guías en «$10k» a la derecha y leyenda con puntos. En el iPhone el
    /// segmentado va arriba (`Home`); en el iPad, con la leyenda en la misma fila (`iPadInicio`).
    private func chartCard(height: CGFloat, barWidth: CGFloat, pickerOnTop: Bool, months fixedMonths: Int? = nil,
                           title: String? = nil) -> some View {
        let months = fixedMonths ?? chartMonths
        let points = chartPoints(months: months)
        return VStack(alignment: .leading, spacing: 14) {
            if let title {
                ViewThatFits(in: .horizontal) {
                    HStack { Text(title).font(.cardTitle).fixedSize(); Spacer(minLength: 12); legend }
                    VStack(alignment: .leading, spacing: 6) { Text(title).font(.cardTitle); legend }
                }
            } else if pickerOnTop {
                monthsPicker
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { legend.fixedSize(); Spacer(minLength: 12); monthsPicker.fixedSize() }
                    VStack(alignment: .leading, spacing: 10) { legend; monthsPicker }
                }
            }
            Chart(points) { point in
                BarMark(x: .value("Mes", point.month, unit: .month), y: .value("Importe", point.amount), width: .fixed(barWidth))
                    .foregroundStyle(by: .value("Serie", point.isIncome ? String(localized: "Ingresos") : String(localized: "Gastos")))
                    .position(by: .value("Serie", point.isIncome ? 0 : 1))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            }
            .chartForegroundStyleScale([String(localized: "Ingresos"): Palette.income, String(localized: "Gastos"): Palette.expenseBar])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow)).foregroundStyle(Palette.ink2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.separator)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            // «$10k» como el canvas; el formato compacto del sistema pone «$10 K».
                            Text(amount == 0 ? "$0" : "$\(Int((amount / 1000).rounded()))k").foregroundStyle(Palette.ink2)
                        }
                    }
                }
            }
            // Los ejes no crecen más allá de xxxLarge (se amontonaban); las cifras están en el resumen hablado.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Ingresos y gastos de los últimos \(months) meses"))
            .accessibilityValue(chartSummary(points))
            if pickerOnTop && title == nil { legend }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        #if os(macOS)
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        #endif
    }

    private var monthsPicker: some View {
        FilterPicker(title: String(localized: "Periodo de la gráfica"), options: [6, 12], selection: $chartMonths) {
            $0 == 6 ? String(localized: "6 meses") : String(localized: "12 meses")
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(String(localized: "Ingresos"), Palette.income)
            legendItem(String(localized: "Gastos"), Palette.expenseBar)
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: legendDot, height: legendDot)
            Text(title)
        }
    }

    // MARK: Por cobrar

    /// Total pendiente, barra vencido (rojo) / por vencer (Tinta) y sus importes.
    private func receivablesSummary(amountSize: CGFloat, counts: Bool) -> some View {
        let upcoming = receivableTotal - overdueTotal
        let overdueText = counts ? String(localized: "Vencido \(overdueTotal.money) · \(overdue.count) facturas")
            : String(localized: "Vencido \(overdueTotal.money)")
        let upcomingText = counts ? String(localized: "Por vencer \(upcoming.money) · \(openInvoices.count - overdue.count) facturas")
            : String(localized: "Por vencer \(upcoming.money)")
        return VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow(alignment: .firstTextBaseline) {
                Text("Total pendiente").font(.subheadline).foregroundStyle(Palette.ink2)
            } trailing: {
                Text(receivableTotal.money).font(.amount(amountSize)).foregroundStyle(Palette.ink)
            }
            if receivableTotal > 0 {
                GeometryReader { proxy in
                    let overdueWidth = overdueTotal == 0 ? 0 : max(4, (proxy.size.width - 2) * CGFloat(overdueTotal) / CGFloat(receivableTotal))
                    HStack(spacing: overdueTotal > 0 && upcoming > 0 ? 2 : 0) {
                        if overdueTotal > 0 { Rectangle().fill(Palette.red).frame(width: overdueWidth) }
                        if upcoming > 0 { Rectangle().fill(Palette.brand) }
                    }
                }
                .frame(height: 6)
                .background(Palette.surface2)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(overdueText).foregroundStyle(overdueTotal > 0 ? Palette.negative : Palette.ink2).fixedSize()
                        Spacer(minLength: 8)
                        Text(upcomingText).foregroundStyle(Palette.ink2).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(overdueText).foregroundStyle(overdueTotal > 0 ? Palette.negative : Palette.ink2)
                        Text(upcomingText).foregroundStyle(Palette.ink2)
                    }
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «F-1038 · venció el 23 oct» / «F-1047 · vence el 12 nov».
    private func dueText(_ invoice: Invoice) -> String {
        let date = invoice.dueDate.dayMonth
        return invoice.daysOverdue() != nil ? String(localized: "\(invoice.number) · venció el \(date)")
            : String(localized: "\(invoice.number) · vence el \(date)")
    }

    private func invoiceRow(_ invoice: Invoice) -> some View {
        let status = StatusChip(invoice: invoice)
        return NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
            HomeRow(title: invoice.customer?.name ?? String(localized: "Sin cliente"), subtitle: dueText(invoice)) {
                EmptyView()
            } trailing: {
                VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                    Text(invoice.balanceDue.money).monospacedDigit().foregroundStyle(Palette.ink)
                    Text(status.text).font(.footnote).foregroundStyle(status.foreground)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func receivablesCard(limit: Int) -> some View {
        VStack(spacing: 0) {
            receivablesSummary(amountSize: 22, counts: false)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            if openInvoices.isEmpty {
                Divider().padding(.leading, 16)
                emptyRow(String(localized: "No tienes facturas pendientes de cobro."))
            }
            ForEach(receivableRows.prefix(limit)) { invoice in
                Divider().padding(.leading, 16)
                invoiceRow(invoice)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: Por pagar

    private func billRow(_ bill: Bill) -> some View {
        let vendor = bill.vendor?.name ?? String(localized: "Proveedor")
        let subtitle = bill.vendorNumber.isEmpty ? String(localized: "Factura por pagar")
            : String(localized: "Factura por pagar \(bill.vendorNumber)")
        return HomeRow(title: vendor, subtitle: subtitle, chevron: false) {
            DateTile(date: bill.dueDate)
        } trailing: {
            Text(bill.balanceDue.money).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .accessibilityLabel(String(localized: "\(vendor), vence el \(bill.dueDate.dayMonth)"))
    }

    private var payablesCard: some View {
        HomeRowGroup(dividerInset: 16 + 38 + 12) {
            if soonBills.isEmpty {
                emptyRow(String(localized: "Nada por pagar en las próximas dos semanas."))
            }
            ForEach(soonBills) { billRow($0) }
        }
    }

    // MARK: Cuentas

    private func accountTile(_ account: Account) -> IconTile {
        switch account.subtype {
        case .creditCard: IconTile(systemImage: "creditcard", foreground: Palette.creditCard)
        case .cash: IconTile(systemImage: "banknote", foreground: Palette.green)
        case .undepositedFunds: IconTile(systemImage: "tray.and.arrow.down", foreground: Palette.teal)
        default: IconTile(systemImage: "building.columns", foreground: Palette.bankAccount)
        }
    }

    private func accountRow(_ account: Account) -> some View {
        NavigationLink { LedgerView(account: account) } label: {
            HomeRow(title: account.maskedName, subtitle: "\(account.code) · \(account.subtype.title)") {
                accountTile(account)
            } trailing: {
                Text(ledger.cashBalance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var accountsCard: some View {
        HomeRowGroup(dividerInset: 16 + 30 + 12) {
            if shownAccounts.isEmpty { emptyRow(String(localized: "Aún no tienes cuentas de banco ni tarjetas.")) }
            ForEach(shownAccounts) { accountRow($0) }
        }
    }

    // MARK: - iPad (`iPadInicio`)

    private var padBody: some View {
        HStack(alignment: .top, spacing: 0) {
            padColumn
                .frame(width: padColumnWidth)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { padDetail }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(padSection)
        }
    }

    private func padTitle(_ section: PadSection) -> String {
        switch section {
        case .cash: String(localized: "Efectivo")
        case .results: String(localized: "Resultados")
        case .receivables: String(localized: "Por cobrar")
        case .payables: String(localized: "Por pagar")
        }
    }

    /// Columna del resumen: empresa · mes, y las cuatro secciones con icono, detalle y cifra.
    private var padColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                periodMenu(compact: true, prefix: companyName)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                ForEach(PadSection.allCases) { section in padItem(section) }
            }
            .padding(8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.leading, 8).padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Secciones del resumen")
    }

    private func padItem(_ section: PadSection) -> some View {
        let selected = padSection == section
        let soonTotal = soonBills.reduce(0) { $0 + $1.balanceDue }
        let (icon, color, subtitle, subtitleColor, value): (String, Color, String, Color, Int64) = switch section {
        case .cash:
            ("building.columns", Palette.blue, String(localized: "\(shownAccounts.count) cuentas"), Palette.ink2, ledger.availableCash)
        case .results:
            ("chart.bar.xaxis", Palette.indigo, margin.map { String(localized: "Ganancia · \($0.lowercased())") } ?? String(localized: "Ganancia del mes"),
             Palette.ink2, thisMonth.netIncome)
        case .receivables:
            ("doc.text", Palette.green,
             overdue.isEmpty ? String(localized: "\(openInvoices.count) facturas abiertas")
                : String(localized: "\(overdue.count) vencidas · \(overdueTotal.money)"),
             overdue.isEmpty ? Palette.ink2 : Palette.negative, receivableTotal)
        case .payables:
            ("calendar", Palette.orange, String(localized: "Próximos 14 días"), Palette.ink2, soonTotal)
        }
        return Button { padSection = section } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: icon, foreground: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(padTitle(section)).font(.body)
                    Text(subtitle).font(.footnote).foregroundStyle(selected ? Palette.onBrandFill.opacity(0.85) : subtitleColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(value.moneyWhole).font(.body.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(selected ? Palette.onBrandFill : Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 64)
            .background(selected ? Palette.brandFill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var padDetail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(padTitle(padSection)).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(padLede).font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 16)

        VStack(alignment: .leading, spacing: 20) {
            switch padSection {
            case .cash:
                cashHeader(amountSize: 34)
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: String(localized: "Cuentas")) { bankingLink }
                    accountsCard
                }
            case .results:
                resultColumns(large: true)
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                chartCard(height: 220, barWidth: chartMonths == 6 ? 18 : 9, pickerOnTop: false)
                SectionLink(item: .report(.income)) { ReportsView(fixedKind: .income) } label: { Text("Ver estado de resultados") }
                    .buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            case .receivables:
                receivablesSummary(amountSize: 28, counts: true)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                HomeRowGroup(dividerInset: 16) {
                    if openInvoices.isEmpty { emptyRow(String(localized: "No tienes facturas pendientes de cobro.")) }
                    ForEach(receivableRows.prefix(8)) { invoiceRow($0) }
                }
                SectionLink(item: .sales(.invoices)) { SalesView(fixedSegment: .invoices) } label: { Text("Ver todas las facturas") }
                    .buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            case .payables:
                payablesCard
                SectionLink(item: .expenses(.bills)) { ExpensesView(fixedSegment: .bills) } label: { Text("Ver todas las facturas por pagar") }
                    .buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            }
        }
    }

    private var padLede: String {
        switch padSection {
        case .cash: accountsDetail
        case .results: String(localized: "\(month.start.monthYear) · ingresos, gastos y ganancia")
        case .receivables: String(localized: "\(openInvoices.count) facturas abiertas")
        case .payables: String(localized: "Próximos 14 días · \(soonBills.reduce(0) { $0 + $1.balanceDue }.money)")
        }
    }

    // MARK: - Mac (`MacInicio`)

    private var macKPIs: [KPIItem] {
        let income = change(thisMonth.totalIncome, lastMonth.totalIncome, higherIsBetter: true, monthStyle: .long)
        let spent = change(monthExpenses, previousExpenses, higherIsBetter: false, monthStyle: .long)
        return [
            KPIItem(title: String(localized: "Efectivo disponible"), value: ledger.availableCash.money, foot: accountsDetail),
            KPIItem(title: String(localized: "Ingresos del mes"), value: thisMonth.totalIncome.money, foot: income?.text, footColor: income?.color ?? Palette.ink2),
            KPIItem(title: String(localized: "Gastos del mes"), value: monthExpenses.money, foot: spent?.text, footColor: spent?.color ?? Palette.ink2),
            KPIItem(title: String(localized: "Ganancia neta"), value: thisMonth.netIncome.money, foot: margin),
        ]
    }

    private var macBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(companyName).font(.subheadline).foregroundStyle(Palette.ink2)
            KPIGrid(items: macKPIs, large: true)
            macPair(firstShare: 2) {
                chartCard(height: 190, barWidth: 12, pickerOnTop: false, months: 12,
                          title: String(localized: "Ingresos y gastos · 12 meses"))
            } and: {
                macAccounts
            }
            macPair(firstShare: 1) { macReceivables } and: { macPayables }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8).padding(.bottom, 28)
    }

    /// Dos bloques lado a lado si caben (como el `flex-wrap` del canvas); si no, uno debajo del otro.
    private func macPair(firstShare: CGFloat, @ViewBuilder _ first: () -> some View, @ViewBuilder and second: () -> some View) -> some View {
        let available = width - 2 * Metrics.gutter
        let sideBySide = available >= 760 && !dynamicTypeSize.isAccessibilitySize
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        let firstWidth = sideBySide ? (available - 12) * firstShare / (firstShare + 1) : nil
        return layout {
            first().frame(width: firstWidth)
            second().frame(maxWidth: .infinity)
        }
    }

    private var macAccounts: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cuentas").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                bankingLink
            }
            .padding(.bottom, 6)
            if shownAccounts.isEmpty {
                Text("Aún no tienes cuentas de banco ni tarjetas.").font(.subheadline).foregroundStyle(Palette.ink2).padding(.vertical, 8)
            }
            ForEach(shownAccounts) { account in
                Divider()
                NavigationLink { LedgerView(account: account) } label: {
                    HStack(spacing: 10) {
                        accountTile(account)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(account.maskedName).lineLimit(1)
                            Text("\(account.code) · \(account.subtype.title)").font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(ledger.cashBalance(of: account).money).fontWeight(.semibold).monospacedDigit()
                    }
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
    }

    /// Título de tabla del Mac (13 bold) con un dato gris a la derecha.
    private func macTableTitle(_ title: String, @ViewBuilder detail: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.cardTitle).fixedSize().accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                detail()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cardTitle).accessibilityAddTraits(.isHeader)
                detail()
            }
        }
        .padding(.horizontal, 2)
    }

    private var macReceivables: some View {
        VStack(alignment: .leading, spacing: 6) {
            macTableTitle(String(localized: "Facturas por cobrar")) {
                (Text("\(overdueTotal.money) vencido").foregroundStyle(overdueTotal > 0 ? Palette.negative : Palette.ink2)
                 + Text(" · ") + Text("\((receivableTotal - overdueTotal).money) por vencer"))
                    .font(.subheadline).foregroundStyle(Palette.ink2)
            }
            TableCard {
                Text("Número").frame(width: 64, alignment: .leading)
                Text("Cliente").frame(maxWidth: .infinity, alignment: .leading)
                Text("Estado").frame(width: 120, alignment: .leading)
                Text("Importe").frame(width: 90, alignment: .trailing)
            } rows: {
                if openInvoices.isEmpty {
                    emptyRow(String(localized: "No tienes facturas pendientes de cobro."))
                }
                #if os(macOS)
                // Un clic elige la factura y la muestra en el inspector (canvas `MacInicio`); «Abrir factura», ahí.
                let picked = macInvoice?.id
                ForEach(Array(receivableRows.prefix(8).enumerated()), id: \.element.id) { index, invoice in
                    MacReportRow(isSelected: invoice.id == picked, zebra: !index.isMultiple(of: 2), select: { macInvoiceID = invoice.id }) {
                        ReportCellText(text: invoice.number).lineLimit(1).frame(width: 64, alignment: .leading)
                        Text(invoice.customer?.name ?? String(localized: "Sin cliente")).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        MacCellStatus(chip: StatusChip(invoice: invoice)).frame(width: 120, alignment: .leading)
                        Text(invoice.balanceDue.money).frame(width: 90, alignment: .trailing)
                    }
                    .contextMenu { Button("Abrir factura") { openedInvoice = invoice } }
                }
                #else
                ForEach(Array(receivableRows.prefix(8).enumerated()), id: \.element.id) { index, invoice in
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: {
                        TableRow {
                            Text(invoice.number).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 64, alignment: .leading)
                            Text(invoice.customer?.name ?? String(localized: "Sin cliente")).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            StatusChip(invoice: invoice).frame(width: 120, alignment: .leading)
                            Text(invoice.balanceDue.money).frame(width: 90, alignment: .trailing)
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Palette.surface)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var macPayables: some View {
        let week = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        let thisWeek = bills.filter { $0.isOpen && $0.dueDate <= week }.reduce(0) { $0 + $1.balanceDue }
        let upcoming = bills.filter { $0.isOpen && $0.balanceDue > 0 }.prefix(8)
        return VStack(alignment: .leading, spacing: 6) {
            macTableTitle(String(localized: "Cuentas por pagar · próximas")) {
                Text("\(thisWeek.money) esta semana").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            TableCard {
                Text("Vence").frame(width: 64, alignment: .leading)
                Text("Proveedor").frame(maxWidth: .infinity, alignment: .leading)
                Text("Número").frame(width: 90, alignment: .leading)
                Text("Importe").frame(width: 90, alignment: .trailing)
            } rows: {
                if upcoming.isEmpty {
                    emptyRow(String(localized: "Nada por pagar en las próximas dos semanas."))
                }
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, bill in
                    SectionLink(item: .expenses(.bills)) { ExpensesView(fixedSegment: .bills) } label: {
                        TableRow {
                            Text(bill.dueDate.dayMonth).foregroundStyle(bill.dueDate < .now ? Palette.negative : Palette.ink2)
                                .lineLimit(1).frame(width: 64, alignment: .leading)
                            Text(bill.vendor?.name ?? String(localized: "Proveedor")).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(bill.vendorNumber).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 90, alignment: .leading)
                            Text(bill.balanceDue.money).frame(width: 90, alignment: .trailing)
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Palette.surface)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Inspector (`MacInicio`)

    #if os(macOS)
    /// La factura elegida o, sin elegir (o si ya se cobró), la primera de la tabla, como el canvas.
    private var macInvoice: Invoice? {
        let rows = receivableRows.prefix(8)
        return rows.first { $0.id == macInvoiceID } ?? rows.first
    }

    private func invoiceTitle(_ invoice: Invoice) -> String {
        String(localized: "Factura \(invoice.number)")
    }

    /// «Venció hace 8 días», «Vence hoy», «Vence en 11 días».
    private func dueNote(_ invoice: Invoice) -> String {
        if let days = invoice.daysOverdue() { return String(localized: "Venció hace \(days) días") }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: invoice.dueDate)).day ?? 0
        return days <= 0 ? String(localized: "Vence hoy") : String(localized: "Vence en \(days) días")
    }

    /// Estado, saldo pendiente con su vencimiento, cliente, fechas, importes y la actividad que guarda la factura
    /// (creada, emitida y sus cobros). «Vista por el cliente» y «Recordatorio enviado» del canvas no se guardan.
    @ViewBuilder
    private func invoiceInspector(_ invoice: Invoice) -> some View {
        StatusChip(invoice: invoice, compact: true)
        MacReportFigure(caption: String(localized: "Saldo pendiente"), amount: invoice.balanceDue.money) {
            Text(dueNote(invoice)).foregroundStyle(invoice.daysOverdue() != nil ? Palette.negative : Palette.ink2)
        }
        MacInspectorSection(title: String(localized: "Cliente")) {
            MacInspectorRow(label: String(localized: "Nombre")) {
                if let customer = invoice.customer {
                    Button(customer.name) { openedCustomer = customer }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                } else {
                    Text("Sin cliente").foregroundStyle(Palette.ink2)
                }
            }
            if let customer = invoice.customer {
                MacInspectorRow(String(localized: "Términos"),
                                value: customer.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(customer.paymentTermsDays)"))
            }
        }
        MacInspectorSection(title: String(localized: "Fechas")) {
            MacInspectorRow(String(localized: "Emitida"), value: invoice.issueDate.shortDate)
            MacInspectorRow(String(localized: "Vencimiento"), value: invoice.dueDate.shortDate,
                            color: invoice.daysOverdue() != nil ? Palette.negative : Palette.ink)
        }
        MacInspectorSection(title: String(localized: "Importe")) {
            MacInspectorRow(String(localized: "Total"), value: invoice.total.money)
            MacInspectorRow(String(localized: "Pagado"), value: invoice.amountPaid.money)
            if invoice.creditsApplied > 0 {
                MacInspectorRow(String(localized: "Notas de crédito"), value: "−\(invoice.creditsApplied.money)")
            }
            MacInspectorRow(String(localized: "Saldo"), value: invoice.balanceDue.money, bold: true)
        }
        MacInspectorSection(title: String(localized: "Actividad")) {
            MacInspectorRow(String(localized: "Creada"), value: min(invoice.createdAt, invoice.issueDate).shortDate)
            MacInspectorRow(String(localized: "Emitida"), value: invoice.issueDate.shortDate)
            ForEach((invoice.paymentApplications ?? []).sorted { ($0.payment?.date ?? .distantPast) < ($1.payment?.date ?? .distantPast) }) { application in
                MacInspectorRow(String(localized: "Cobro de \(application.amount.money)"), value: application.payment?.date.shortDate ?? "—")
            }
        }
    }

    /// «Registrar pago…» (vidrio), «Enviar recordatorio» y «Abrir factura».
    @ViewBuilder
    private func invoiceActions(_ invoice: Invoice) -> some View {
        Button("Registrar pago…") { payingInvoice = invoice }.buttonStyle(.primary)
        HStack(spacing: 8) {
            ShareLink(item: invoice.reminderText, subject: Text("Recordatorio de pago")) { Text("Enviar recordatorio") }
                .buttonStyle(.secondary)
            Button("Abrir factura") { openedInvoice = invoice }.buttonStyle(.secondary)
        }
    }
    #endif

    // MARK: - Primera vez (`EstadoVacio`)

    /// Pasos del MVP (el canvas incluye importar el banco y escanear recibos, que son de la fase 2).
    private var steps: [(title: String, done: Bool, action: NewItem?)] {
        [(String(localized: "Crear tu empresa"), true, nil),
         (String(localized: "Añadir tu primer cliente"), !customers.isEmpty, .customer),
         (String(localized: "Crear tu primera factura"), !invoices.isEmpty, .invoice),
         (String(localized: "Registrar un gasto"), !expenses.isEmpty, .expense)]
    }

    private var firstUse: some View {
        let done = steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            Text(companyName).font(.subheadline).foregroundStyle(Palette.ink2)
                .padding(.horizontal, Metrics.gutter)

            VStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Palette.ink2)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                Text("Aquí verás cómo va tu negocio")
                    .font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Cuando registres ventas y gastos, aparecerán tu efectivo, tus ingresos del mes y lo que te deben.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: 300)
                Button("Crear tu primera factura") { sheet = .invoice }
                    .buttonStyle(.primaryCompact)
                    .padding(.top, 10)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32).padding(.top, 30).padding(.bottom, 6)

            SectionHeader(title: String(localized: "Primeros pasos")) {
                Text("\(done) de \(steps.count)").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 26).padding(.bottom, 8)

            VStack(spacing: 0) {
                ProgressView(value: Double(done), total: Double(steps.count))
                    .tint(Palette.brand)
                    .accessibilityLabel("Progreso de configuración")
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
                ForEach(steps.indices, id: \.self) { index in
                    Divider().padding(.leading, 16 + 22 + 12)
                    stepRow(steps[index])
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .padding(.horizontal, Metrics.gutter)
        }
        .padding(.top, 4).padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private func stepRow(_ step: (title: String, done: Bool, action: NewItem?)) -> some View {
        Button { if let action = step.action, !step.done { sheet = action } } label: {
            HStack(spacing: 12) {
                Group {
                    if step.done {
                        Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Palette.green, in: Circle())
                    } else {
                        Circle().strokeBorder(Palette.chevron, lineWidth: 1.5).frame(width: 22, height: 22)
                    }
                }
                .accessibilityHidden(true)
                Text(step.title).foregroundStyle(step.done ? Palette.ink2 : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !step.done {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Sin `.disabled`: el paso hecho se ve con su círculo verde a pleno color, como en el canvas.
        .allowsHitTesting(!step.done)
        .accessibilityValue(step.done ? Text("Completado") : Text("Pendiente"))
    }
}

// MARK: - Filas del canvas

/// Grupo de filas en una celda de radio 24 (`Home`: Por pagar, Cuentas), con separadores sangrados desde el texto.
/// Pieza propia del área A; podría subir al sistema junto a `LedgerRow`.
private struct HomeRowGroup<Content: View>: View {
    var dividerInset: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 { Divider().padding(.leading, dividerInset) }
                    rows[index]
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

/// Fila del canvas `Home`: icono opcional, título `.body` y subtítulo `.footnote` gris, importe a la derecha y chevron.
/// Con letra de accesibilidad, todo en columna.
private struct HomeRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var chevron = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        HStack(spacing: 10) {
            layout {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).foregroundStyle(Palette.ink).lineLimit(stacked ? nil : 1)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(stacked ? nil : 1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                trailing.fixedSize(horizontal: !stacked, vertical: false)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension HomeRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, chevron: Bool = true, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, subtitle: subtitle, chevron: chevron, leading: leading, trailing: { EmptyView() })
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

#Preview {
    NavigationStack { HomeView() }.modelContainer(SampleData.makeContainer())
}
