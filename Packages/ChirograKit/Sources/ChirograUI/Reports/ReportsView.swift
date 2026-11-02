import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Reportes, calculados con `ReportBuilder` a partir de las líneas contabilizadas.
/// - iPhone (y la columna estrecha del iPad): `ReportePyG`. «Resultados» con segmentado Mes · Trimestre · Año, la
///   ganancia neta con su gráfica frente al periodo anterior, los grupos de cuentas como listas agrupadas y «Otros
///   reportes» con iconos tipo Ajustes. Los demás reportes, con la misma forma de lista.
/// - iPad: `iPadPyG` / `iPadPyGV`: «Comparar con periodo anterior» y la tabla en grupos de radio 24. Los otros reportes
///   están en la barra lateral.
/// - Mac: `MacPyG`, `MacBalance`, `MacBalanza`, `MacAntigCobrar`, `MacAntigPagar`, `MacSalesTax`: cajas de cifras,
///   el estado como documento (cabecera centrada, sangrías, subrayado doble) y tablas con cebra.
struct ReportsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case income = "Resultados"
        case balance = "Balance general"
        case trial = "Balanza"
        case receivables = "Por cobrar"
        case payables = "Por pagar"
        case salesTax = "Sales tax"
        var id: String { rawValue }

        /// Nombre completo: título en iPad y Mac, y lista «Reportes» de la barra lateral.
        var fullTitle: String {
            switch self {
            case .income: String(localized: "Estado de resultados")
            case .balance: String(localized: "Balance general")
            case .trial: String(localized: "Balanza de comprobación")
            case .receivables: String(localized: "Antigüedad por cobrar")
            case .payables: String(localized: "Antigüedad por pagar")
            case .salesTax: String(localized: "Impuesto sobre ventas")
            }
        }

        /// Icono de «Otros reportes» (`ReportePyG`): símbolo blanco sobre un color del sistema.
        var tile: (symbol: String, color: Color) {
            switch self {
            case .income: ("chart.bar.xaxis", Palette.indigo)
            case .balance: ("scalemass", Palette.blue)
            case .trial: ("tablecells", Palette.teal)
            case .receivables: ("clock", Palette.orange)
            case .payables: ("clock.arrow.circlepath", Palette.red)
            case .salesTax: ("percent", Palette.purple)
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case month = "Mes", quarter = "Trimestre", year = "Año", custom = "Personalizado"
        var id: String { rawValue }

        /// Periodo de calendario que contiene hoy, desplazado `offset` periodos. `custom` no tiene uno propio:
        /// lo resuelve la vista con las fechas elegidas.
        func interval(offset: Int = 0, calendar: Calendar = .current) -> DateInterval {
            let component: Calendar.Component = switch self { case .month, .custom: .month; case .quarter: .quarter; case .year: .year }
            let step = self == .quarter ? 3 : 1
            let date = calendar.date(byAdding: self == .quarter ? .month : component, value: offset * step, to: .now) ?? .now
            return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
        }
    }

    /// Qué dirección es favorable para colorear la variación.
    private enum Trend { case upIsGood, downIsGood }

    /// En la barra lateral de iPad y Mac cada reporte es una entrada propia; sin él (iPhone), Resultados con la lista
    /// «Otros reportes» al final.
    var fixedKind: Kind? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .body) private var amountColumn: CGFloat = Self.amountColumnBase
    @ScaledMetric(relativeTo: .body) private var percentColumn: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var bucketColumn: CGFloat = Self.bucketColumnBase
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var invoices: [Invoice]
    @Query private var bills: [Bill]
    @Query private var companies: [Company]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]
    @Query private var entries: [JournalEntry]

    @State private var period: Period = .month
    @State private var compare = true
    @State private var customStart = Period.month.interval().start
    @State private var customEnd = Period.month.interval().end.addingTimeInterval(-1)
    @State private var editingRange = false
    @State private var width: CGFloat = 0
    /// Fecha de corte de balance, balanza y antigüedad («Al 31 oct 2026»).
    @State private var asOf = Date.now
    /// Trimestre del sales tax en pantallas anchas (`MacSalesTax`): 0 el actual, −1 el anterior…
    @State private var taxQuarter = 0
    #if os(macOS)
    /// Fila elegida del reporte para el inspector del Mac (clave de `macRowKeys`); sin elegir, la primera.
    @State private var macPick: String?
    @State private var openedAccount: Account?
    @State private var openedCustomer: Customer?
    @State private var openedVendor: Vendor?
    @State private var payingAgency: AgencyRow?
    #endif

    private var kind: Kind {
        #if DEBUG
        // `-qa.reporte balance|trial|receivables|payables|salesTax` con `-qa.seccion reports` (solo Debug).
        if fixedKind == nil, let raw = UserDefaults.standard.string(forKey: "qa.reporte"),
           let qa = Kind.allCases.first(where: { "\($0)" == raw }) { return qa }
        #endif
        return fixedKind ?? .income
    }
    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }

    // MARK: Medidas

    #if os(macOS)
    private static let amountColumnBase: CGFloat = 120
    private static let bucketColumnBase: CGFloat = 96
    #else
    private static let amountColumnBase: CGFloat = 116
    private static let bucketColumnBase: CGFloat = 104
    #endif

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Diseño del iPhone: pantalla o columna estrecha, poco ancho o letra de accesibilidad muy grande.
    private var isPhone: Bool {
        #if os(iOS)
        if sizeClass == .compact { return true }
        #endif
        return dynamicTypeSize >= .accessibility3 || (width > 0 && width - 40 < (isMac ? 480 : 560))
    }

    private var margin: CGFloat { isPhone ? Metrics.gutter : 20 }
    private var contentWidth: CGFloat { max(0, width - 2 * margin) }
    private var companyName: String {
        companies.first.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isPhone { phoneContent } else { wideContent }
            }
            .padding(.horizontal, margin)
            .padding(.top, isPhone ? 0 : 8)
            .padding(.bottom, 28)
            .frame(maxWidth: isPhone ? 720 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: isPhone ? .center : .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle(isPhone && kind == .income ? String(localized: "Resultados") : kind.fullTitle)
        #if os(macOS)
        .navigationSubtitle(subtitle)
        #endif
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle()
        #endif
        .toolbar { toolbar }
        .sheet(isPresented: $editingRange) { rangeEditor }
        #if os(macOS)
        .macReportInspector(title: macInspectorTitle, hasSelection: macSelectedKey != nil, placeholder: macPlaceholder,
                            selectionKey: macPick, qaSelectRow: { index in
                                let keys = macRowKeys
                                if keys.indices.contains(index) { macPick = keys[index] }
                            }) {
            macInspector
        } actions: {
            macInspectorActions
        }
        .navigationDestination(item: $openedAccount) { LedgerView(account: $0) }
        .navigationDestination(item: $openedCustomer) { CustomerDetailView(customer: $0) }
        .navigationDestination(item: $openedVendor) { VendorDetailView(vendor: $0) }
        .sheet(item: $payingAgency) { row in
            NavigationStack { SalesTaxPaymentView(owed: salesTaxPayable, agencyID: row.id, amount: row.balance) }.editorSheetSizing()
        }
        #endif
    }

    // MARK: Barra

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !isPhone {
            switch kind {
            case .income:
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) { periodMenu }
                ToolbarItem(placement: .primaryAction) { comparePicker }
                #else
                ToolbarItem(placement: .primaryAction) { periodPicker.fixedSize() }
                #endif
            case .balance, .trial, .receivables, .payables:
                ToolbarItem(placement: .primaryAction) { asOfPicker }
            case .salesTax:
                ToolbarItem(placement: .primaryAction) { quarterPicker }
                ToolbarItem(placement: .primaryAction) {
                    SectionLink(item: .section(.taxes)) { TaxesView() } label: {
                        HStack(spacing: 6) { Image(systemName: "checkmark.circle"); Text("Registrar pago") }
                    }
                    .headerButton()
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: csvFile, preview: SharePreview("\(csvFile.name).csv")) {
                if isPhone { Label("Exportar", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
                else { HStack(spacing: 6) { Image(systemName: "square.and.arrow.up"); Text("Exportar") } }
            }
            .headerButton()
        }
    }

    private var asOfPicker: some View {
        DatePicker("Al", selection: $asOf, in: ...Date.now, displayedComponents: .date)
            .fixedSize()
            .accessibilityLabel("Fecha de corte")
    }

    /// `MacPyG`: menú con Mes, Trimestre, Año y «Elegir fechas…», con el rango en la etiqueta.
    private var periodMenu: some View {
        Menu {
            Picker("Periodo", selection: $period) {
                ForEach([Period.month, .quarter, .year]) { option in
                    Text(option.localizedTitle).tag(option)
                }
                if period == .custom { Text(Period.custom.localizedTitle).tag(Period.custom) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Elegir fechas…") { editingRange = true }
        } label: {
            HStack(spacing: 6) { Image(systemName: "calendar"); Text(rangeLabel) }
        }
        .headerButton()
        .accessibilityLabel("Periodo")
        .accessibilityValue(rangeLabel)
    }

    /// `MacPyG`: «Solo periodo | Vs. anterior».
    private var comparePicker: some View {
        Picker("Comparación", selection: $compare) {
            Text("Solo periodo").tag(false)
            Text("Vs. anterior").tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var periodPicker: some View {
        FilterPicker(title: String(localized: "Periodo"), options: [Period.month, .quarter, .year], selection: $period) {
            $0.localizedTitle
        }
    }

    private var rangeEditor: some View {
        let start = Binding(get: { interval().start }, set: { customStart = $0; customEnd = max(customEnd, $0); period = .custom })
        let end = Binding(get: { interval().end.addingTimeInterval(-1) }, set: { customEnd = $0; customStart = min(customStart, $0); period = .custom })
        return NavigationStack {
            Form {
                DatePicker("Desde", selection: start, displayedComponents: .date)
                DatePicker("Hasta", selection: end, displayedComponents: .date)
            }
            .formStyle(.grouped)
            .navigationTitle("Fechas del periodo")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { editingRange = false }.headerButton() }
            }
        }
        .frame(minWidth: isMac ? 360 : nil, minHeight: isMac ? 200 : nil)
        .presentationDetents([.medium])
    }

    // MARK: Textos del periodo

    private var subtitle: String {
        switch kind {
        case .income: String(localized: "\(companyName) · base devengado · \(companies.first?.currencyCode ?? "USD")")
        case .balance: String(localized: "\(companyName) · base devengado · \(companies.first?.currencyCode ?? "USD")")
        case .trial: String(localized: "Saldos al \(asOf.shortDate) · \(trialBalanceReport.rows.count) cuentas con movimiento")
        case .receivables: String(localized: "Facturas de clientes abiertas · \(lateTotal(receivablesReport).money) vencido")
        case .payables: String(localized: "Facturas de proveedores abiertas · \(lateTotal(payablesReport).money) vencido")
        case .salesTax: String(localized: "Sales tax por jurisdicción · declaración trimestral")
        }
    }

    private func lateTotal(_ report: AgingReport) -> Int64 { report.total - report.total(for: .current) }

    /// «Octubre de 2026», «T4 2026 (oct–dic)» o «1 ene – 31 dic 2026».
    private var rangeTitle: String {
        switch period {
        case .month: periodName(offset: 0)
        case .quarter: "\(periodName(offset: 0)) (\(rangeLabel))"
        case .year, .custom: rangeLabel
        }
    }

    /// «Octubre de 2026», «T4 2026» o «2026».
    private func periodName(offset: Int) -> String {
        let start = interval(offset: offset).start
        switch period {
        case .month, .custom: return start.monthYear
        case .quarter: return String(localized: "T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1) \(start.formatted(.appDateTime.year()))")
        case .year: return start.formatted(.appDateTime.year())
        }
    }

    /// Periodo anterior en corto: «septiembre», «T3», «2025».
    private var previousName: String {
        let start = interval(offset: -1).start
        switch period {
        case .month, .custom: return start.formatted(.appDateTime.month(.wide))
        case .quarter: return String(localized: "T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1)")
        case .year: return start.formatted(.appDateTime.year())
        }
    }

    private var rangeLabel: String {
        let current = interval()
        return (current.start..<current.end.addingTimeInterval(-1)).formatted(.interval.day().month(.abbreviated).year().locale(.appText))
    }

    /// Periodo mostrado, o el anterior de igual duración (`offset: -1`).
    private func interval(offset: Int = 0) -> DateInterval {
        guard period == .custom else { return period.interval(offset: offset) }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(customStart, customEnd))
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd))) ?? start
        let length = end.timeIntervalSince(start)
        return DateInterval(start: start.addingTimeInterval(Double(offset) * length), duration: length)
    }

    /// Encabezado de columna: «Oct 2026», «T4 2026», «2026»; en rangos personalizados, «Actual» / «Anterior».
    /// `short`: solo el mes («Sep»), como la nota de las filas del iPhone.
    private func columnTitle(offset: Int, short: Bool = false) -> String {
        let start = interval(offset: offset).start
        let year = start.formatted(.appDateTime.year())
        switch period {
        case .month: return short ? start.shortMonth.sentenceCased : "\(start.shortMonth.sentenceCased) \(year)"
        case .quarter: return String(localized: "T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1) \(year)")
        case .year: return year
        case .custom: return offset == 0 ? String(localized: "Actual") : String(localized: "Anterior")
        }
    }

    // MARK: - Estados como secciones

    private struct Line: Identifiable {
        enum Style { case line, total, result, grand }
        let name: String
        var amount: Int64
        var previous: Int64? = nil
        var trend: Trend? = nil
        var style: Style = .line
        /// Cuenta de la fila (las de totales y resultados no tienen).
        var account: LedgerAccount? = nil
        var id: String { account.map(\.id.uuidString) ?? "\(name)-\(style)" }
    }

    private struct Block: Identifiable {
        /// `nil`: un resultado suelto (utilidad bruta, ganancia neta), en su propia tarjeta.
        let title: String?
        let lines: [Line]
        var id: String { (title ?? "") + (lines.first?.name ?? "") }
    }

    private func lines(_ rows: [ReportRow], _ previous: [ReportRow]?, trend: Trend?) -> [Line] {
        // Al comparar, también las cuentas que solo tuvieron importe en el periodo anterior (con 0 en el actual): si
        // no, el total anterior no cuadraba con las filas.
        let shown = rows + (previous ?? []).filter { old in !rows.contains { $0.account.id == old.account.id } }
            .map { ReportRow(account: $0.account, amount: 0) }
        return shown.sorted { ($0.account.code, $0.account.name) < ($1.account.code, $1.account.name) }.map { row in
            Line(name: row.account.name, amount: row.amount,
                 previous: previous.map { list in list.first { $0.account.id == row.account.id }?.amount ?? 0 }, trend: trend,
                 account: row.account)
        }
    }

    private var incomeBlocks: [Block] { incomeBlocks(comparing: compare) }

    /// `comparing`: con el periodo anterior en cada fila (el inspector del Mac compara siempre).
    private func incomeBlocks(comparing: Bool) -> [Block] {
        let current = ledger.incomeStatement(interval())
        let previous = comparing ? ledger.incomeStatement(interval(offset: -1)) : nil
        func total(_ name: String, _ now: Int64, _ before: Int64?, _ trend: Trend, _ style: Line.Style = .total) -> Line {
            Line(name: name, amount: now, previous: before, trend: trend, style: style)
        }
        return [
            Block(title: String(localized: "Ingresos"), lines: lines(current.income, previous?.income, trend: .upIsGood)
                  + [total(String(localized: "Total ingresos"), current.totalIncome, previous?.totalIncome, .upIsGood)]),
            Block(title: String(localized: "Costo de ventas"), lines: lines(current.costOfGoodsSold, previous?.costOfGoodsSold, trend: .downIsGood)
                  + [total(String(localized: "Total costo de ventas"), current.totalCostOfGoodsSold, previous?.totalCostOfGoodsSold, .downIsGood)]),
            Block(title: nil, lines: [total(String(localized: "Utilidad bruta"), current.grossProfit, previous?.grossProfit, .upIsGood, .result)]),
            Block(title: String(localized: "Gastos operativos"), lines: lines(current.expenses, previous?.expenses, trend: .downIsGood)
                  + [total(String(localized: "Total gastos operativos"), current.totalExpenses, previous?.totalExpenses, .downIsGood)]),
            Block(title: nil, lines: [total(String(localized: "Ganancia neta"), current.netIncome, previous?.netIncome, .upIsGood, .grand)]),
        ]
    }

    private var balanceBlocks: [Block] {
        let report = balanceSheetReport
        return [
            Block(title: String(localized: "Activos"), lines: lines(report.assets, nil, trend: nil)
                  + [Line(name: String(localized: "Total activos"), amount: report.totalAssets, style: .total)]),
            Block(title: String(localized: "Pasivos"), lines: lines(report.liabilities, nil, trend: nil)
                  + [Line(name: String(localized: "Total pasivos"), amount: report.totalLiabilities, style: .total)]),
            Block(title: String(localized: "Patrimonio"), lines: lines(report.equity, nil, trend: nil) + [
                Line(name: String(localized: "Resultados de años anteriores"), amount: report.priorYearsEarnings),
                Line(name: String(localized: "Resultado del ejercicio"), amount: report.currentYearEarnings),
                Line(name: String(localized: "Total patrimonio"), amount: report.totalEquity, style: .total),
            ]),
            Block(title: nil, lines: [Line(name: String(localized: "Pasivo + patrimonio"), amount: report.totalLiabilities + report.totalEquity,
                                           style: .grand)]),
        ]
    }

    // MARK: Variación

    private func color(for delta: Int64, _ trend: Trend?) -> Color {
        guard let trend, delta != 0 else { return Palette.ink2 }
        return (delta > 0) == (trend == .upIsGood) ? Palette.positive : Palette.negative
    }

    /// «+$1,770.00», «−$360.00» (signo menos tipográfico) o «$0.00».
    private func signedMoney(_ amount: Int64) -> String {
        amount == 0 ? amount.money : (amount > 0 ? "+" : "−") + abs(amount).money
    }

    /// «+12.6%», «−1.8%», «0.0%»; `nil` si el periodo anterior es cero.
    private func percentChange(_ now: Int64, _ before: Int64) -> String? {
        guard before != 0 else { return nil }
        let percent = Double(now - before) / Double(abs(before)) * 100
        let text = abs(percent).formatted(.number.precision(.fractionLength(1)))
        return (percent > 0.05 ? "+" : percent < -0.05 ? "−" : "") + text + "%"
    }

    private func share(_ amount: Int64, of total: Int64) -> String {
        guard total != 0 else { return "—" }
        return (Double(amount) / Double(total) * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    // MARK: - iPhone

    @ViewBuilder
    private var phoneContent: some View {
        Text(phoneSubtitle).font(.subheadline).foregroundStyle(Palette.ink2)
            .padding(.bottom, 8)
        switch kind {
        case .income: phoneIncome
        case .balance: phoneBalance
        case .trial: phoneTrial
        case .receivables: phoneAging(receivablesReport, empty: String(localized: "No hay facturas pendientes de cobro."))
        case .payables: phoneAging(payablesReport, empty: String(localized: "No hay facturas de proveedores pendientes."))
        case .salesTax: phoneSalesTax
        }
        if fixedKind == nil { otherReports }
    }

    private var phoneSubtitle: String {
        switch kind {
        case .income: String(localized: "Estado de resultados · \(companyName)")
        case .salesTax: companyName
        default: subtitle
        }
    }

    /// `ReportePyG`: segmentado, comparar, «Ganancia neta» con su gráfica y los grupos de cuentas.
    @ViewBuilder
    private var phoneIncome: some View {
        let current = ledger.incomeStatement(interval())
        let previous = ledger.incomeStatement(interval(offset: -1))
        periodPicker.padding(.top, 4)
        PhoneGroup {
            Toggle(String(localized: "Comparar con \(previousName)"), isOn: $compare).tint(Palette.green)
                .padding(.horizontal, 16).frame(minHeight: Metrics.target).padding(.vertical, 4)
        }
        .padding(.top, 12)
        netIncomeCard(current, previous).padding(.top, 16)
        ForEach(incomeBlocks) { block in phoneBlock(block) }
    }

    private func netIncomeCard(_ current: IncomeStatement, _ previous: IncomeStatement) -> some View {
        let change = compare ? percentChange(current.netIncome, previous.netIncome) : nil
        let margin = current.totalIncome > 0 ? String(localized: "Margen \(current.netIncome * 100 / current.totalIncome)%") : nil
        let note = change.map { String(localized: "\($0) vs. \(previousName)") } ?? margin
        let bars: [(String, Int64, Int64)] = [
            (String(localized: "Ingresos"), current.totalIncome, previous.totalIncome),
            (String(localized: "Costos"), current.totalCostOfGoodsSold, previous.totalCostOfGoodsSold),
            (String(localized: "Gastos"), current.totalExpenses, previous.totalExpenses),
            (String(localized: "Ganancia"), current.netIncome, previous.netIncome),
        ]
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ganancia neta · \(periodName(offset: 0))").font(.subheadline).foregroundStyle(Palette.ink2)
                Text(current.netIncome.money).font(.amount(36)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
                if let note {
                    Text(note).font(.footnote)
                        .foregroundStyle(change == nil ? Palette.ink2 : color(for: current.netIncome - previous.netIncome, .upIsGood))
                }
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(Palette.separator).frame(height: 0.5)
            ComparisonBars(bars: bars, showsPrevious: compare)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "\(periodName(offset: 0)) frente a \(previousName)"))
                .accessibilityValue(bars.map { "\($0.0): \($0.1.money)" + (compare ? ", \(previousName) \($0.2.money)" : "") }
                    .joined(separator: ". "))
            HStack(spacing: 16) {
                legendDot(periodName(offset: 0), Palette.income)
                if compare { legendDot(periodName(offset: -1).sentenceCased, Palette.gray) }
            }
            .font(.footnote).foregroundStyle(Palette.ink2)
            .accessibilityHidden(true)
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); Text(title) }
    }

    /// Un grupo con encabezado `.footnote` y su tarjeta; los resultados sueltos, en una tarjeta aparte.
    @ViewBuilder
    private func phoneBlock(_ block: Block) -> some View {
        if let title = block.title {
            SectionLabel(text: title).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        }
        PhoneGroup {
            // Solo el total: el grupo no tuvo movimientos.
            if block.title != nil && block.lines.count == 1 {
                Text("Sin movimientos").foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading).padding(.horizontal, 16)
            }
            ForEach(block.lines) { phoneLine($0) }
        }
        .padding(.top, block.title == nil ? 12 : 0)
    }

    private func phoneLine(_ line: Line) -> some View {
        let weight: Font.Weight = switch line.style { case .line: .regular; case .total: .semibold; case .result, .grand: .bold }
        let amountColor = line.style == .grand && kind == .income && line.amount != 0 ? (line.amount > 0 ? Palette.positive : Palette.negative) : Palette.ink
        return AdaptiveRow {
            Text(line.name).fontWeight(weight).foregroundStyle(Palette.ink)
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                Text(line.amount.money).fontWeight(weight).foregroundStyle(amountColor)
                if compare, let previous = line.previous {
                    Text("\(columnTitle(offset: -1, short: true)) \(previous.money)").font(.footnote).foregroundStyle(Palette.ink2)
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// «Otros reportes» (`ReportePyG`): lista con iconos tipo Ajustes y chevron.
    @ViewBuilder
    private var otherReports: some View {
        SectionHeader(String(localized: "Otros reportes"))
            .padding(.top, 26).padding(.bottom, 8)
        PhoneGroup(dividerInset: 16 + 30 + 12) {
            ForEach(Kind.allCases.filter { $0 != .income }) { other in
                NavigationLink { ReportsView(fixedKind: other) } label: {
                    HStack(spacing: 12) {
                        IconTile(systemImage: other.tile.symbol, foreground: other.tile.color)
                        Text(other.fullTitle).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                            .accessibilityHidden(true)
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 6)
                    .frame(minHeight: Metrics.target)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var phoneAsOf: some View {
        PhoneGroup {
            DatePicker("Al", selection: $asOf, in: ...Date.now, displayedComponents: .date)
                .padding(.horizontal, 16).frame(minHeight: Metrics.target).padding(.vertical, 4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var phoneBalance: some View {
        let report = balanceSheetReport
        phoneAsOf
        ForEach(balanceBlocks) { phoneBlock($0) }
        balanceStatus(report.isBalanced, text: report.isBalanced ? String(localized: "Activo = Pasivo + Patrimonio")
                      : String(localized: "Diferencia \((report.totalAssets - report.totalLiabilities - report.totalEquity).money)"))
            .padding(.horizontal, Metrics.gutter).padding(.top, 8)
    }

    /// «● Cuadra» con el punto del color del sistema y el texto en su color AA, sin fondo.
    private func balanceStatus(_ balanced: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            StatusDot(color: balanced ? Palette.green : Palette.red)
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(balanced ? Palette.positive : Palette.negative)
    }

    @ViewBuilder
    private var phoneTrial: some View {
        let report = trialBalanceReport
        phoneAsOf
        SectionLabel(text: String(localized: "Cuentas")).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        PhoneGroup {
            if report.rows.isEmpty { phoneLine(Line(name: String(localized: "Sin movimientos"), amount: 0)) }
            ForEach(report.rows) { row in
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.account.name).foregroundStyle(Palette.ink)
                        Text("\(row.account.code) · \(row.account.subtype.title)").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                } trailing: {
                    VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                        Text((row.debit == 0 ? row.credit : row.debit).money).foregroundStyle(Palette.ink)
                        Text(row.debit == 0 ? String(localized: "Crédito") : String(localized: "Débito")).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        PhoneGroup {
            phoneLine(Line(name: String(localized: "Total débitos"), amount: report.totalDebit, style: .total))
            phoneLine(Line(name: String(localized: "Total créditos"), amount: report.totalCredit, style: .total))
        }
        .padding(.top, 12)
        balanceStatus(report.isBalanced, text: report.isBalanced ? String(localized: "Débitos = créditos")
                      : String(localized: "Diferencia \(abs(report.totalDebit - report.totalCredit).money)"))
            .padding(.horizontal, Metrics.gutter).padding(.top, 8)
    }

    private static let bucketTitles: [AgingReport.Bucket: String] = [
        .current: String(localized: "Al día"), .days1to30: "1–30", .days31to60: "31–60", .days61to90: "61–90", .over90: "90+",
    ]

    private static let bucketColors: [AgingReport.Bucket: Color] = [
        .current: Palette.brand, .days1to30: Palette.yellow, .days31to60: Palette.orange, .days61to90: Palette.red, .over90: Palette.red,
    ]

    private func bucketTitle(_ bucket: AgingReport.Bucket) -> String {
        bucket == .current ? Self.bucketTitles[bucket]! : String(localized: "\(Self.bucketTitles[bucket]!) días")
    }

    @ViewBuilder
    private func phoneAging(_ report: AgingReport, empty: String) -> some View {
        phoneAsOf
        SectionLabel(text: String(localized: "Por antigüedad")).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        PhoneGroup {
            ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                let amount = report.total(for: bucket)
                AdaptiveRow {
                    HStack(spacing: 8) { StatusDot(color: Self.bucketColors[bucket]!); Text(bucketTitle(bucket)) }
                } trailing: {
                    Text(amount.money).foregroundStyle(bucket != .current && amount > 0 ? Palette.negative : Palette.ink)
                }
                .monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            phoneLine(Line(name: String(localized: "Total abierto"), amount: report.total, style: .total))
        }
        SectionLabel(text: kind == .receivables ? String(localized: "Clientes") : String(localized: "Proveedores"))
            .padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        PhoneGroup {
            if report.rows.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading).padding(.horizontal, 16)
            }
            ForEach(report.rows) { row in
                let late = row.total - (row.amounts[.current] ?? 0)
                partyLink(row.party) {
                    AdaptiveRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.party).foregroundStyle(Palette.ink)
                            Text(late > 0 ? String(localized: "Vencido \(late.money)") : String(localized: "Al día"))
                                .font(.footnote).foregroundStyle(late > 0 ? Palette.negative : Palette.ink2)
                        }
                    } trailing: {
                        Text(row.total.money).foregroundStyle(Palette.ink)
                    }
                    .monospacedDigit()
                    .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var phoneSalesTax: some View {
        let report = salesTaxReport
        periodPicker.padding(.top, 4)
        VStack(alignment: .leading, spacing: 2) {
            Text("Impuesto cobrado · \(periodName(offset: 0))").font(.subheadline).foregroundStyle(Palette.ink2)
            Text(report.totalTax.money).font(.amount(36)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
            Text("\(report.from.shortDate) – \(report.to.shortDate)").font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .padding(.top, 16)
        SectionLabel(text: String(localized: "Ventas")).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        PhoneGroup {
            phoneLine(Line(name: String(localized: "Gravables"), amount: report.taxableSales))
            phoneLine(Line(name: String(localized: "No gravables"), amount: report.nonTaxableSales))
            phoneLine(Line(name: String(localized: "Exentas (clientes exentos)"), amount: report.exemptSales))
            phoneLine(Line(name: String(localized: "Ventas totales"), amount: report.totalSales, style: .total))
        }
        SectionLabel(text: String(localized: "Por tasa")).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        PhoneGroup {
            if report.rows.isEmpty {
                Text("Sin impuesto cobrado en el periodo.").foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading).padding(.horizontal, 16)
            }
            ForEach(report.rows) { row in
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(row.name) · \(row.percent.formatted())%").foregroundStyle(Palette.ink)
                        Text("sobre \(row.taxableSales.money)").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                } trailing: {
                    Text(row.tax.money).foregroundStyle(Palette.ink)
                }
                .monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - iPad y Mac

    @ViewBuilder
    private var wideContent: some View {
        switch kind {
        case .income: wideIncome
        case .balance: wideBalance
        case .trial: wideTrial
        case .receivables: wideAging(receivablesReport, party: String(localized: "Cliente"), empty: String(localized: "No hay facturas pendientes de cobro."))
        case .payables: wideAging(payablesReport, party: String(localized: "Proveedor"), empty: String(localized: "No hay facturas de proveedores pendientes."))
        case .salesTax: wideSalesTax(salesTaxReport)
        }
    }

    /// Subtítulo bajo el título de la barra (en el Mac va en la ventana).
    @ViewBuilder
    private var wideSubtitle: some View {
        if !isMac {
            Text(kind == .income ? String(localized: "\(rangeTitle) · base devengado") : subtitle)
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .padding(.horizontal, 8).padding(.bottom, 16)
        }
    }

    private func kpiRow(_ items: [KPIItem]) -> some View {
        KPIGrid(items: items, large: true).padding(.bottom, 16)
    }

    @ViewBuilder
    private var wideIncome: some View {
        let current = ledger.incomeStatement(interval())
        let previous = ledger.incomeStatement(interval(offset: -1))
        wideSubtitle
        if isMac {
            kpiRow(incomeKPIs(current, previous))
            statementDocument(title: Kind.income.fullTitle, range: String(localized: "\(rangeTitle) · base devengado · \(companies.first?.currencyCode ?? "USD")"),
                              blocks: incomeBlocks, columns: incomeColumns)
        } else {
            PhoneGroup {
                Toggle("Comparar con periodo anterior", isOn: $compare).tint(Palette.green)
                    .padding(.horizontal, 16).frame(minHeight: 52)
            }
            statementGroups(blocks: incomeBlocks, columns: incomeColumns).padding(.top, 14)
        }
    }

    private func incomeKPIs(_ current: IncomeStatement, _ previous: IncomeStatement) -> [KPIItem] {
        func change(_ now: Int64, _ before: Int64, _ trend: Trend) -> (String?, Color) {
            guard compare, let percent = percentChange(now, before) else { return (nil, Palette.ink2) }
            return (String(localized: "\(percent) vs. \(previousName)"), color(for: now - before, trend))
        }
        func margin(_ amount: Int64) -> String? {
            current.totalIncome > 0 ? String(localized: "Margen \(amount * 100 / current.totalIncome)%") : nil
        }
        let income = change(current.totalIncome, previous.totalIncome, .upIsGood)
        let expenses = change(current.totalExpenses, previous.totalExpenses, .downIsGood)
        let net = compare ? percentChange(current.netIncome, previous.netIncome) : nil
        return [
            KPIItem(title: String(localized: "Ingresos"), value: current.totalIncome.money, foot: income.0, footColor: income.1),
            KPIItem(title: String(localized: "Utilidad bruta"), value: current.grossProfit.money, foot: margin(current.grossProfit)),
            KPIItem(title: String(localized: "Gastos operativos"), value: current.totalExpenses.money, foot: expenses.0, footColor: expenses.1),
            KPIItem(title: String(localized: "Ganancia neta"), value: current.netIncome.money,
                    foot: [margin(current.netIncome), net].compactMap { $0 }.joined(separator: " · "),
                    footColor: net == nil ? Palette.ink2 : color(for: current.netIncome - previous.netIncome, .upIsGood)),
        ]
    }

    /// Columna de importes de un estado.
    private struct AmountColumn: Identifiable {
        let title: String
        let width: CGFloat
        let value: (Line) -> (text: String, color: Color)?
        var id: String { title }
    }

    /// Periodo y, al comparar, el anterior, la variación (solo Mac, como `MacPyG`) y el % si caben.
    private var incomeColumns: [AmountColumn] {
        var columns = [AmountColumn(title: columnTitle(offset: 0), width: amountColumn) { (line: Line) in (line.amount.money, Palette.ink) }]
        guard compare else { return columns }
        columns.append(AmountColumn(title: columnTitle(offset: -1), width: amountColumn) { (line: Line) in
            line.previous.map { ($0.money, Palette.ink2) }
        })
        let nameRoom: CGFloat = isMac ? 200 : 180
        if isMac && contentWidth - 48 >= nameRoom + 3 * amountColumn + percentColumn + 40 {
            columns.append(AmountColumn(title: String(localized: "Variación"), width: amountColumn) { (line: Line) in
                line.previous.map { (signedMoney(line.amount - $0), color(for: line.amount - $0, line.trend)) }
            })
        }
        if contentWidth - (isMac ? 48 : 32) >= nameRoom + columns.reduce(0) { $0 + $1.width + 8 } + percentColumn + 8 {
            columns.append(AmountColumn(title: "%", width: percentColumn) { (line: Line) in
                line.previous.map { (percentChange(line.amount, $0) ?? "—", color(for: line.amount - $0, line.trend)) }
            })
        }
        return columns
    }

    /// `iPadPyG`: cabecera de columnas fuera de las tarjetas y cada grupo con su encabezado y su celda de radio 24.
    private func statementGroups(blocks: [Block], columns: [AmountColumn]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { Text($0.title).lineLimit(1).frame(width: $0.width, alignment: .trailing).padding(.leading, 8) }
            }
            .font(.footnote).foregroundStyle(Palette.ink2)
            .padding(.horizontal, 16).padding(.bottom, 2)
            .accessibilityHidden(true)
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                if let title = block.title {
                    SectionLabel(text: title).padding(.horizontal, 16).padding(.top, index == 0 ? 10 : 22).padding(.bottom, 7)
                } else {
                    Color.clear.frame(height: 12)
                }
                PhoneGroup {
                    ForEach(block.lines) { line in
                        let weight: Font.Weight = switch line.style { case .line: .regular; case .total: .semibold; case .result, .grand: .bold }
                        HStack(spacing: 0) {
                            Text(line.name).fontWeight(weight).foregroundStyle(Palette.ink).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(columns) { column in
                                let value = column.value(line)
                                Text(value?.text ?? "").fontWeight(column.title == columns.first?.title ? weight : .regular)
                                    .foregroundStyle(value?.color ?? Palette.ink2)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(width: column.width, alignment: .trailing)
                                    .padding(.leading, 8)
                            }
                        }
                        .monospacedDigit()
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .frame(minHeight: Metrics.target)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// `MacPyG` / `MacBalance`: el estado como documento, con cabecera centrada, secciones sangradas, línea sobre los
    /// totales y doble subrayado en el resultado.
    private func statementDocument(title: String, range: String, blocks: [Block], columns: [AmountColumn]) -> some View {
        // Fila elegida para el inspector (solo Mac): rellena de Tinta, como la de una tabla.
        let picked = macPickedKey
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                Text(companyName).font(.headline)
                Text(title).font(.title3.weight(.bold))
                Text(range).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { Text($0.title).lineLimit(1).frame(width: $0.width, alignment: .trailing).padding(.leading, 8) }
            }
            .font(.label).foregroundStyle(Palette.ink2)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 0.5) }
            .accessibilityHidden(true)

            ForEach(blocks) { block in
                if let title = block.title {
                    Text(title).fontWeight(.semibold).padding(.horizontal, 8).frame(minHeight: 28).padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        #if os(macOS)
                        // El encabezado elige el total de su sección (canvas `MacPyG`: la sección con su total).
                        .contentShape(Rectangle())
                        .onTapGesture { if let total = block.lines.last { macPick = total.id } }
                        #endif
                }
                ForEach(block.lines) { line in
                    documentLine(line, columns: columns, inSection: block.title != nil, selected: line.id == picked)
                }
            }
        }
        .monospacedDigit()
        .padding(24)
        .frame(maxWidth: 860)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .frame(maxWidth: .infinity)
    }

    private func documentLine(_ line: Line, columns: [AmountColumn], inSection: Bool, selected: Bool = false) -> some View {
        let weight: Font.Weight = switch line.style { case .line: .regular; case .total, .result: .semibold; case .grand: .bold }
        let indent: CGFloat = !inSection ? 0 : line.style == .line ? 36 : 18
        let ruled = line.style != .line
        let rule = selected ? Palette.onBrandFill.opacity(0.7) : Palette.ink2
        return HStack(spacing: 0) {
            Text(line.name).lineLimit(1).padding(.leading, indent).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { column in
                let value = column.value(line)
                Text(value?.text ?? "").foregroundStyle(selected ? Palette.onBrandFill : value?.color ?? Palette.ink2)
                    .fontWeight(column.title == columns.first?.title ? weight : .regular)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.vertical, 4)
                    .frame(width: column.width, alignment: .trailing)
                    .padding(.leading, 8)
                    .overlay(alignment: .top) { if ruled { Rectangle().fill(rule).frame(height: 0.5).padding(.leading, 8) } }
                    .overlay(alignment: .bottom) {
                        if line.style == .grand {
                            VStack(spacing: 1.5) { Rectangle().frame(height: 0.75); Rectangle().frame(height: 0.75) }
                                .foregroundStyle(rule).padding(.leading, 8)
                        }
                    }
            }
        }
        .fontWeight(weight)
        .foregroundStyle(selected ? Palette.onBrandFill : Palette.ink)
        .padding(.horizontal, 8)
        .frame(minHeight: line.style == .line ? 24 : 28)
        .background(selected ? Palette.brandFill : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.top, line.style == .result || line.style == .grand ? 6 : 0)
        #if os(macOS)
        .contentShape(Rectangle())
        .onTapGesture { macPick = line.id }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : isMac ? .isButton : [])
    }

    // MARK: Balance general

    @ViewBuilder
    private var wideBalance: some View {
        let report = balanceSheetReport
        let difference = report.totalAssets - report.totalLiabilities - report.totalEquity
        wideSubtitle
        kpiRow([KPIItem(title: String(localized: "Activos"), value: report.totalAssets.money),
                KPIItem(title: String(localized: "Pasivos"), value: report.totalLiabilities.money),
                KPIItem(title: String(localized: "Patrimonio"), value: report.totalEquity.money)])
        HStack(spacing: 8) {
            Image(systemName: report.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isBalanced ? Palette.green : Palette.red).accessibilityHidden(true)
            Text("Activo \(report.totalAssets.money) = Pasivo \(report.totalLiabilities.money) + Patrimonio \(report.totalEquity.money)")
                .foregroundStyle(Palette.ink)
            Text(report.isBalanced ? String(localized: "Cuadra") : String(localized: "Diferencia \(difference.money)"))
                .fontWeight(.semibold).foregroundStyle(report.isBalanced ? Palette.positive : Palette.negative)
        }
        .font(.subheadline).monospacedDigit()
        .padding(.horizontal, 2).padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        let columns = [
            AmountColumn(title: asOf.shortDate, width: amountColumn + 10) { (line: Line) in (line.amount.money, Palette.ink) },
            AmountColumn(title: String(localized: "% del total"), width: percentColumn + 20) { (line: Line) in
                (share(line.amount, of: report.totalAssets), Palette.ink2)
            },
        ]
        if isMac {
            statementDocument(title: Kind.balance.fullTitle,
                              range: String(localized: "Al \(asOf.shortDate) · base devengado · \(companies.first?.currencyCode ?? "USD")"),
                              blocks: balanceBlocks, columns: columns)
        } else {
            statementGroups(blocks: balanceBlocks, columns: columns)
        }
    }

    // MARK: Balanza de comprobación

    @ViewBuilder
    private var wideTrial: some View {
        let report = trialBalanceReport
        let difference = abs(report.totalDebit - report.totalCredit)
        let picked = macPickedKey
        wideSubtitle
        TableCard {
            Text("Número").frame(width: 60, alignment: .leading)
            Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tipo").frame(width: 150, alignment: .leading)
            Text("Débito").frame(width: amountColumn, alignment: .trailing)
            Text("Crédito").frame(width: amountColumn, alignment: .trailing)
        } rows: {
            ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                pickableRow(row.account.id.uuidString, index: index, picked: picked) {
                    ReportCellText(text: row.account.code).frame(width: 60, alignment: .leading)
                    Text(row.account.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    ReportCellText(text: row.account.subtype.title).lineLimit(1).frame(width: 150, alignment: .leading)
                    Text(row.debit == 0 ? "" : row.debit.money).frame(width: amountColumn, alignment: .trailing)
                    Text(row.credit == 0 ? "" : row.credit.money).frame(width: amountColumn, alignment: .trailing)
                }
            }
            TableRow {
                Color.clear.frame(width: 60, height: 1)
                Text("Totales").frame(maxWidth: .infinity, alignment: .leading)
                balanceStatus(report.isBalanced, text: report.isBalanced ? String(localized: "Cuadra") : String(localized: "Diferencia \(difference.money)"))
                    .frame(width: 150, alignment: .leading)
                doubleRuled(report.totalDebit.money).frame(width: amountColumn, alignment: .trailing)
                doubleRuled(report.totalCredit.money).frame(width: amountColumn, alignment: .trailing)
            }
            .fontWeight(.semibold)
        }
        Text("Los saldos deudores van en Débito y los acreedores en Crédito.")
            .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, 2).padding(.top, 8)
    }

    /// Cebra de las tablas del Mac (`--row2` en las filas impares); en iPhone e iPad, sin cebra.
    private func zebra(_ index: Int) -> Color {
        isMac && !index.isMultiple(of: 2) ? Palette.surface : .clear
    }

    /// Fila de tabla: en el Mac se elige con un clic para verla en el inspector (`MacReportRow`); en el iPad, la de
    /// siempre.
    @ViewBuilder
    private func pickableRow<Content: View>(_ key: String, index: Int, picked: String?, @ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        MacReportRow(isSelected: key == picked, zebra: !index.isMultiple(of: 2), select: { macPick = key }) { content() }
        #else
        TableRow { content() }.background(zebra(index))
        #endif
    }

    /// Clave de la fila elegida en el Mac; `nil` en iPhone e iPad, donde no se elige.
    private var macPickedKey: String? {
        #if os(macOS)
        macSelectedKey
        #else
        nil
        #endif
    }

    /// Importe de un total con doble subrayado.
    private func doubleRuled(_ text: String) -> some View {
        Text(text)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                VStack(spacing: 1.5) { Rectangle().frame(height: 0.75); Rectangle().frame(height: 0.75) }.foregroundStyle(Palette.ink2)
            }
    }

    // MARK: Antigüedad

    @ViewBuilder
    private func wideAging(_ report: AgingReport, party: String, empty: String) -> some View {
        let grand = report.total
        let picked = macPickedKey
        wideSubtitle
        LazyVGrid(columns: [GridItem(.adaptive(minimum: isMac ? 130 : 150), spacing: 12)], spacing: 12) {
            bucketBox(String(localized: "Total abierto"), grand, share: grand == 0 ? 0 : 1, bar: Palette.gray, late: false,
                      foot: kind == .receivables ? String(localized: "\(report.rows.count) clientes") : String(localized: "\(report.rows.count) proveedores"))
            ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                let amount = report.total(for: bucket)
                let part = grand == 0 ? 0 : Double(amount) / Double(grand)
                bucketBox(bucketTitle(bucket), amount, share: part, bar: Self.bucketColors[bucket]!, late: bucket != .current && amount > 0,
                          foot: String(localized: "\(Int((part * 100).rounded()))% del total"))
            }
        }
        .padding(.bottom, 16)
        TableCard {
            Text(party).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                Text(Self.bucketTitles[bucket]!).frame(width: bucketColumn, alignment: .trailing)
            }
            Text("Total").frame(width: bucketColumn + 8, alignment: .trailing)
        } rows: {
            ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                pickableRow("party:\(row.party)", index: index, picked: picked) {
                    // En el Mac la fila se elige (la ficha se abre desde el inspector); en el iPad, el nombre la abre.
                    #if os(macOS)
                    Text(row.party).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    #else
                    partyLink(row.party) { Text(row.party).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                    #endif
                    ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                        let amount = row.amounts[bucket] ?? 0
                        ReportCellText(text: amount == 0 ? "—" : amount.money,
                                       color: amount == 0 ? Palette.ink2 : bucket == .current ? Palette.ink : Palette.negative)
                            .frame(width: bucketColumn, alignment: .trailing)
                    }
                    Text(row.total.money).fontWeight(.semibold).frame(width: bucketColumn + 8, alignment: .trailing)
                }
            }
            if report.rows.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            TableRow {
                Text("Total").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                    let amount = report.total(for: bucket)
                    Text(amount == 0 ? "—" : amount.money)
                        .foregroundStyle(amount == 0 ? Palette.ink2 : bucket == .current ? Palette.ink : Palette.negative)
                        .frame(width: bucketColumn, alignment: .trailing)
                }
                doubleRuled(grand.money).frame(width: bucketColumn + 8, alignment: .trailing)
            }
            .fontWeight(.semibold)
        }
        Text("Columnas en días después del vencimiento.")
            .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, 2).padding(.top, 8)
    }

    /// Caja de un tramo (`MacAntigCobrar`): etiqueta, importe (rojo si está vencido), barra y porcentaje.
    private func bucketBox(_ title: String, _ amount: Int64, share: Double, bar: Color, late: Bool, foot: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.label).foregroundStyle(Palette.ink2).lineLimit(1)
            Text(amount.money).font(.amount(20)).foregroundStyle(late ? Palette.negative : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Capsule().fill(Palette.surface2).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in Capsule().fill(bar).frame(width: proxy.size.width * share) }
                }
                .accessibilityHidden(true)
            Text(foot).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// Nombre enlazado a la ficha del cliente o del proveedor.
    @ViewBuilder
    private func partyLink<Label: View>(_ name: String, @ViewBuilder label: () -> Label) -> some View {
        if kind == .receivables, let customer = customers.first(where: { $0.name == name }) {
            NavigationLink { CustomerDetailView(customer: customer) } label: { label() }.buttonStyle(.plain)
        } else if kind == .payables, let vendor = vendors.first(where: { $0.name == name }) {
            NavigationLink { VendorDetailView(vendor: vendor) } label: { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }

    // MARK: Sales tax

    private struct AgencyRow: Identifiable {
        let id: UUID?
        let name: String
        let rates: String
        let rateMillionths: Int64
        let taxableSales: Int64
        let collected: Int64
        let paid: Int64
        /// Tasas de la agencia (estatal, ciudad, transporte…) para desglosar la combinada.
        let components: [SalesTaxSummary.RateRow]
        var balance: Int64 { collected - paid }
        /// Clave de la fila para el inspector del Mac.
        var key: String { "agency:\(id?.uuidString ?? "none")" }
    }

    /// Pagos de sales tax de la declaración del trimestre: los que se registran en el trimestre siguiente, que es
    /// cuando se declara (`MacSalesTax`: el T3 se pagó el 20 oct). Por agencia (`nil` sin agencia).
    private func taxPayments(for quarter: DateInterval) -> [(agency: UUID?, date: Date, amount: Int64)] {
        let next = Period.quarter.interval(offset: taxQuarter + 1)
        return entries.filter { $0.status == .posted && $0.sourceRaw == EntrySource.salesTaxPayment.rawValue && next.contains($0.date) && $0.date >= quarter.end }
            .map { entry in (entry.sourceDocumentID, entry.date, (entry.lines ?? []).reduce(0) { $0 + $1.debit }) }
    }

    /// Una fila por agencia: suma de sus tasas, base gravable, cobrado, pagado y saldo.
    private func agencyRows(_ summary: SalesTaxSummary, payments: [(agency: UUID?, date: Date, amount: Int64)]) -> [AgencyRow] {
        let agencyOf = Dictionary(taxRates.map { ($0.id, $0.agency) }, uniquingKeysWith: { first, _ in first })
        var order: [UUID?] = []
        var grouped: [UUID?: [SalesTaxSummary.RateRow]] = [:]
        for row in summary.rows {
            let agency = row.rateID.flatMap { agencyOf[$0] ?? nil }
            if grouped[agency?.id] == nil { order.append(agency?.id) }
            grouped[agency?.id, default: []].append(row)
        }
        for payment in payments where grouped[payment.agency] == nil {
            order.append(payment.agency)
            grouped[payment.agency] = []
        }
        let names = Dictionary(taxRates.compactMap { $0.agency }.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return order.map { id in
            let rows = grouped[id] ?? []
            return AgencyRow(id: id, name: id.flatMap { names[$0] } ?? String(localized: "Sin agencia"),
                             rates: rows.map(\.name).joined(separator: " · "),
                             rateMillionths: rows.reduce(0) { $0 + $1.rateMillionths },
                             taxableSales: rows.map(\.taxableSales).max() ?? 0,
                             collected: rows.reduce(0) { $0 + $1.tax },
                             paid: payments.filter { $0.agency == id }.reduce(0) { $0 + $1.amount },
                             components: rows)
        }
    }

    private func quarterTitle(_ offset: Int) -> String {
        let start = Period.quarter.interval(offset: offset).start
        return String(localized: "T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1) \(start.formatted(.appDateTime.year()))")
    }

    private var quarterPicker: some View {
        Picker("Trimestre", selection: $taxQuarter) {
            ForEach([-3, -2, -1, 0], id: \.self) { Text(quarterTitle($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private func percent(_ millionths: Int64) -> String {
        (Decimal(millionths) / 10_000).formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// `MacSalesTax`: ventas gravables, cobrado, pagado y saldo del trimestre, y la tabla por jurisdicción.
    @ViewBuilder
    private func wideSalesTax(_ summary: SalesTaxSummary) -> some View {
        let quarter = Period.quarter.interval(offset: taxQuarter)
        let payments = taxPayments(for: quarter)
        let rows = agencyRows(summary, payments: payments)
        let paid = payments.reduce(0) { $0 + $1.amount }
        let balance = summary.totalTax - paid
        let lastPayment = payments.map(\.date).max()
        let combined = rows.reduce(0) { $0 + $1.rateMillionths }
        let settled = balance <= 0 && summary.totalTax > 0
        let picked = macPickedKey
        wideSubtitle
        kpiRow([
            KPIItem(title: String(localized: "Ventas gravables"), value: summary.taxableSales.money,
                    foot: String(localized: "Exentas \(summary.exemptSales.money)")),
            KPIItem(title: String(localized: "Impuesto cobrado"), value: summary.totalTax.money,
                    foot: combined > 0 ? String(localized: "Tasa combinada \(percent(combined))") : nil),
            KPIItem(title: String(localized: "Pagado"), value: paid.money,
                    foot: lastPayment.map { String(localized: "Pagado el \($0.shortDate)") } ?? String(localized: "Sin pagos registrados")),
            KPIItem(title: String(localized: "Saldo"), value: balance.money,
                    foot: settled ? String(localized: "Trimestre saldado") : String(localized: "Pendiente de pagar"),
                    footColor: settled ? Palette.positive : balance > 0 ? Palette.warning : Palette.ink2),
        ])
        HStack(alignment: .firstTextBaseline) {
            Text("Por jurisdicción").font(.cardTitle).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(quarterTitle(taxQuarter)).font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 2).padding(.bottom, 6)
        TableCard {
            Text("Jurisdicción").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tasa").frame(width: 64, alignment: .trailing)
            Text("Ventas gravables").frame(width: amountColumn + 20, alignment: .trailing)
            Text("Cobrado").frame(width: amountColumn - 10, alignment: .trailing)
            Text("Pagado").frame(width: amountColumn - 10, alignment: .trailing)
            Text("Saldo").frame(width: amountColumn - 10, alignment: .trailing)
        } rows: {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                pickableRow(row.key, index: index, picked: picked) {
                    Text(row.components.count > 1 ? String(localized: "\(row.name) · tasa combinada") : [row.name, row.rates].filter { !$0.isEmpty }.joined(separator: " · "))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(percent(row.rateMillionths)).frame(width: 64, alignment: .trailing)
                    Text(row.taxableSales.money).frame(width: amountColumn + 20, alignment: .trailing)
                    Text(row.collected.money).frame(width: amountColumn - 10, alignment: .trailing)
                    Text(row.paid.money).frame(width: amountColumn - 10, alignment: .trailing)
                    Text(row.balance.money).fontWeight(.semibold).frame(width: amountColumn - 10, alignment: .trailing)
                }
                // Desglose por jurisdicción de la tasa combinada; lo pagado se registra por agencia.
                if row.components.count > 1 {
                    ForEach(row.components) { component in
                        TableRow {
                            Text(component.name).foregroundStyle(Palette.ink2).lineLimit(1).padding(.leading, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(percent(component.rateMillionths)).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .trailing)
                            Text(component.taxableSales.money).foregroundStyle(Palette.ink2).frame(width: amountColumn + 20, alignment: .trailing)
                            Text(component.tax.money).foregroundStyle(Palette.ink2).frame(width: amountColumn - 10, alignment: .trailing)
                            Text("—").foregroundStyle(Palette.ink2).frame(width: amountColumn - 10, alignment: .trailing)
                            Text("—").foregroundStyle(Palette.ink2).frame(width: amountColumn - 10, alignment: .trailing)
                        }
                    }
                }
            }
            if rows.isEmpty {
                Text("Sin impuesto cobrado en el periodo.").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            TableRow {
                Text("Total · tasa combinada").frame(maxWidth: .infinity, alignment: .leading)
                Text(percent(combined)).frame(width: 64, alignment: .trailing)
                Text(summary.taxableSales.money).frame(width: amountColumn + 20, alignment: .trailing)
                Text(summary.totalTax.money).frame(width: amountColumn - 10, alignment: .trailing)
                Text(paid.money).frame(width: amountColumn - 10, alignment: .trailing)
                doubleRuled(balance.money).frame(width: amountColumn - 10, alignment: .trailing)
            }
            .fontWeight(.semibold)
        }
        Text("Cuentan como pagados los pagos registrados en el trimestre siguiente, cuando se presenta la declaración. Las tasas y las agencias se configuran en Impuestos.")
            .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, 2).padding(.top, 8)
    }

    // MARK: - Inspector del Mac

    #if os(macOS)
    /// Filas que se pueden elegir, en el orden del reporte (la primera es la elegida si no hay otra).
    private var macRowKeys: [String] {
        switch kind {
        case .income: incomeBlocks(comparing: true).flatMap(\.lines).map(\.id)
        case .balance: balanceBlocks.flatMap(\.lines).map(\.id)
        case .trial: trialBalanceReport.rows.map(\.account.id.uuidString)
        case .receivables: receivablesReport.rows.map { "party:\($0.party)" }
        case .payables: payablesReport.rows.map { "party:\($0.party)" }
        case .salesTax: salesTaxQuarterRows.map(\.key)
        }
    }

    /// Lo elegido o, sin elegir (o si ya no está en el reporte), la primera fila, como el canvas.
    private var macSelectedKey: String? {
        let keys = macRowKeys
        if let macPick, keys.contains(macPick) { return macPick }
        return keys.first
    }

    private var macPlaceholder: String {
        switch kind {
        case .income, .balance: String(localized: "El reporte no tiene movimientos todavía.")
        case .trial: String(localized: "No hay cuentas con movimiento al corte.")
        case .receivables: String(localized: "No hay facturas pendientes de cobro.")
        case .payables: String(localized: "No hay facturas de proveedores pendientes.")
        case .salesTax: String(localized: "Sin impuesto cobrado en el periodo.")
        }
    }

    private var macInspectorTitle: String {
        guard let key = macSelectedKey else { return kind.fullTitle }
        switch kind {
        case .income: return incomeBlocks(comparing: true).flatMap(\.lines).first { $0.id == key }?.name ?? kind.fullTitle
        case .balance: return balanceBlocks.flatMap(\.lines).first { $0.id == key }?.name ?? kind.fullTitle
        case .trial: return trialBalanceReport.rows.first { $0.account.id.uuidString == key }?.account.name ?? kind.fullTitle
        case .receivables, .payables: return String(key.dropFirst("party:".count))
        case .salesTax: return salesTaxQuarterRows.first { $0.key == key }?.name ?? kind.fullTitle
        }
    }

    /// Cuenta del libro de una fila del reporte (para «Ver en el libro mayor»).
    private func bookAccount(_ id: UUID?) -> Account? {
        id.flatMap { id in accounts.first { $0.id == id } }
    }

    /// «Cuenta», «Total de sección», «Subtotal» (utilidad bruta), «Resultado» (los del ejercicio en el balance) o el del
    /// total final.
    private func lineKindTitle(_ line: Line, grand: String) -> String {
        if line.account != nil { return String(localized: "Cuenta") }
        switch line.style {
        case .line: return String(localized: "Resultado")
        case .result: return String(localized: "Subtotal")
        case .total: return String(localized: "Total de sección")
        case .grand: return grand
        }
    }

    private func natureTitle(_ balance: NormalBalance) -> String {
        balance == .debit ? String(localized: "Deudora") : String(localized: "Acreedora")
    }

    @ViewBuilder
    private var macInspector: some View {
        if let key = macSelectedKey {
            switch kind {
            case .income: incomeInspector(key)
            case .balance: balanceInspector(key)
            case .trial: trialInspector(key)
            case .receivables: agingInspector(key, report: receivablesReport)
            case .payables: agingInspector(key, report: payablesReport)
            case .salesTax: salesTaxInspector(key)
            }
        }
    }

    @ViewBuilder
    private var macInspectorActions: some View {
        if let key = macSelectedKey {
            switch kind {
            case .income:
                if let account = bookAccount(incomeBlocks(comparing: true).flatMap(\.lines).first { $0.id == key }?.account?.id) {
                    Button("Ver en el libro mayor") { openedAccount = account }.buttonStyle(.primary)
                }
            case .balance:
                if let account = bookAccount(balanceBlocks.flatMap(\.lines).first { $0.id == key }?.account?.id) {
                    Button("Ver en el libro mayor") { openedAccount = account }.buttonStyle(.primary)
                }
            case .trial:
                if let account = bookAccount(UUID(uuidString: key)) {
                    Button("Ver en el libro mayor") { openedAccount = account }.buttonStyle(.primary)
                }
                SectionLink(item: .accounting(.chart)) { ChartOfAccountsView() } label: { Text("Plan de cuentas") }
                    .buttonStyle(.secondary)
            case .receivables:
                let name = String(key.dropFirst("party:".count))
                if let customer = customers.first(where: { $0.name == name }) {
                    ShareLink(item: reminderText(customer), subject: Text("Recordatorio de pago")) { Text("Enviar recordatorio") }
                        .buttonStyle(.primary)
                    Button("Abrir ficha") { openedCustomer = customer }.buttonStyle(.secondary)
                }
            case .payables:
                let name = String(key.dropFirst("party:".count))
                SectionLink(item: .expenses(.bills)) { ExpensesView(fixedSegment: .bills) } label: { Text("Registrar pago") }
                    .buttonStyle(.primary)
                if let vendor = vendors.first(where: { $0.name == name }) {
                    Button("Abrir ficha") { openedVendor = vendor }.buttonStyle(.secondary)
                }
            case .salesTax:
                if let row = salesTaxQuarterRows.first(where: { $0.key == key }) {
                    Button("Registrar pago…") { payingAgency = row }
                        .buttonStyle(.primary)
                        .disabled(row.balance <= 0)
                }
                SectionLink(item: .section(.taxes)) { TaxesView() } label: { Text("Ver tasas") }
                    .buttonStyle(.secondary)
            }
        }
    }

    /// Mismo texto que el recordatorio de la ficha del cliente.
    private func reminderText(_ customer: Customer) -> String {
        let overdue = (customer.invoices ?? []).filter { $0.isOpen && $0.daysOverdue() != nil }.reduce(0) { $0 + $1.balanceDue }
        return overdue > 0
            ? String(localized: "Hola, \(customer.name): tienes \(overdue.money) vencido con nosotros. ¿Nos ayudas con el pago? ¡Gracias!")
            : String(localized: "Hola, \(customer.name): te recordamos que tienes \(customer.openBalance.money) pendiente de pago. ¡Gracias!")
    }

    /// `MacPyG`: la fila con el periodo, su variación frente al anterior, la comparación y su peso en los ingresos.
    @ViewBuilder
    private func incomeInspector(_ key: String) -> some View {
        let lines = incomeBlocks(comparing: true).flatMap(\.lines)
        if let line = lines.first(where: { $0.id == key }) {
            let previous = line.previous ?? 0
            let delta = line.amount - previous
            let percent = percentChange(line.amount, previous)
            let totalIncome = ledger.incomeStatement(interval()).totalIncome
            let kindTitle = lineKindTitle(line, grand: String(localized: "Resultado"))
            MacReportFigure(caption: "\(kindTitle) · \(periodName(offset: 0))", amount: line.amount.money) {
                Text(percent.map { String(localized: "\(signedMoney(delta)) (\($0)) vs. \(previousName)") }
                     ?? String(localized: "\(signedMoney(delta)) vs. \(previousName)"))
                    .foregroundStyle(color(for: delta, line.trend))
            }
            MacInspectorSection(title: String(localized: "Comparación")) {
                MacCompareBars(current: (columnTitle(offset: 0), line.amount), previous: (columnTitle(offset: -1), previous))
                    .padding(.vertical, 6)
                MacInspectorRow(columnTitle(offset: 0), value: line.amount.money)
                MacInspectorRow(columnTitle(offset: -1), value: previous.money)
                MacInspectorRow(String(localized: "Variación"), value: signedMoney(delta), color: color(for: delta, line.trend))
                MacInspectorRow(String(localized: "Porcentaje"), value: percent ?? "—", color: color(for: delta, line.trend))
            }
            MacInspectorSection(title: String(localized: "Proporción")) {
                MacInspectorRow(String(localized: "De los ingresos totales"), value: share(line.amount, of: totalIncome))
            }
            Text("Haz clic en una fila del reporte para ver su detalle aquí.")
                .font(.subheadline).foregroundStyle(Palette.ink2)
        }
    }

    /// `MacBalance`: la fila al corte, su peso, sus datos y la composición del balance.
    @ViewBuilder
    private func balanceInspector(_ key: String) -> some View {
        let report = balanceSheetReport
        let blocks = balanceBlocks
        if let block = blocks.first(where: { $0.lines.contains { $0.id == key } }),
           let line = block.lines.first(where: { $0.id == key }) {
            let inAssets = block.title == String(localized: "Activos")
            let base = inAssets ? report.totalAssets : report.totalLiabilities + report.totalEquity
            let kindTitle = lineKindTitle(line, grand: String(localized: "Total"))
            MacReportFigure(caption: String(localized: "\(kindTitle) · al \(asOf.shortDate)"), amount: line.amount.money) {
                Text(inAssets ? String(localized: "\(share(line.amount, of: base)) de total activos")
                     : String(localized: "\(share(line.amount, of: base)) de pasivo + patrimonio"))
                    .foregroundStyle(Palette.ink2)
            }
            MacInspectorSection(title: String(localized: "Detalles")) {
                if let account = line.account {
                    MacInspectorRow(String(localized: "Número"), value: account.code)
                }
                MacInspectorRow(String(localized: "Sección"), value: block.title ?? String(localized: "Pasivos y patrimonio"))
                if let account = line.account {
                    MacInspectorRow(String(localized: "Tipo"), value: account.subtype.title)
                    MacInspectorRow(String(localized: "Naturaleza"),
                                    value: line.amount < 0 ? String(localized: "\(natureTitle(account.type.normalBalance)) · contracuenta")
                                        : natureTitle(account.type.normalBalance))
                }
                MacInspectorRow(String(localized: "Saldo"), value: line.amount.money, bold: true)
            }
            MacInspectorSection(title: String(localized: "Composición del balance")) {
                MacBalanceMix(liabilities: report.totalLiabilities, equity: report.totalEquity).padding(.vertical, 6)
            }
        }
    }

    /// `MacBalanza`: la cuenta con su saldo deudor o acreedor, su naturaleza y su peso en el total de su lado.
    @ViewBuilder
    private func trialInspector(_ key: String) -> some View {
        let report = trialBalanceReport
        if let row = report.rows.first(where: { $0.account.id.uuidString == key }) {
            let debit = row.debit > 0
            let amount = debit ? row.debit : row.credit
            let nature = row.account.type.normalBalance
            let contrary = (nature == .debit) != debit
            MacReportFigure(caption: String(localized: "Cuenta \(row.account.code) · \(row.account.subtype.title)"), amount: amount.money) {
                Text(debit ? String(localized: "Saldo deudor al \(asOf.shortDate)") : String(localized: "Saldo acreedor al \(asOf.shortDate)"))
                    .foregroundStyle(Palette.ink2)
            }
            MacInspectorSection(title: String(localized: "Cuenta")) {
                MacInspectorRow(String(localized: "Número"), value: row.account.code)
                MacInspectorRow(String(localized: "Tipo"), value: row.account.subtype.title)
                MacInspectorRow(String(localized: "Naturaleza"), value: natureTitle(nature))
                MacInspectorRow(String(localized: "Estado de destino"),
                                value: row.account.type.isBalanceSheet ? String(localized: "Balance general") : String(localized: "Estado de resultados"))
            }
            MacInspectorSection(title: String(localized: "Saldo")) {
                MacInspectorRow(String(localized: "Débito"), value: debit ? row.debit.money : "—")
                MacInspectorRow(String(localized: "Crédito"), value: debit ? "—" : row.credit.money)
                MacInspectorRow(debit ? String(localized: "% del total deudor") : String(localized: "% del total acreedor"),
                                value: share(amount, of: debit ? report.totalDebit : report.totalCredit))
            }
            Text(contrary ? String(localized: "El saldo es contrario a la naturaleza de la cuenta: puede ser una contracuenta (como la depreciación acumulada) o un registro por revisar.")
                 : String(localized: "El saldo coincide con la naturaleza de la cuenta."))
                .font(.subheadline).foregroundStyle(Palette.ink2)
        }
    }

    /// `MacAntigCobrar` / `MacAntigPagar`: el saldo abierto del cliente o proveedor por tramos y su peso en el total.
    @ViewBuilder
    private func agingInspector(_ key: String, report: AgingReport) -> some View {
        if let row = report.rows.first(where: { "party:\($0.party)" == key }) {
            let late = row.total - (row.amounts[.current] ?? 0)
            MacReportFigure(caption: kind == .receivables ? String(localized: "Cliente · saldo abierto") : String(localized: "Proveedor · saldo abierto"),
                            amount: row.total.money) {
                HStack(spacing: 5) {
                    StatusDot(color: late > 0 ? Palette.red : Palette.green)
                    Text(late > 0 ? String(localized: "\(late.money) vencido") : String(localized: "Al corriente"))
                }
                .foregroundStyle(late > 0 ? Palette.negative : Palette.positive)
            }
            MacInspectorSection(title: String(localized: "Antigüedad")) {
                ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                    let amount = row.amounts[bucket] ?? 0
                    // Como `MacInspectorRow`, con el punto del tramo delante de la etiqueta (canvas `MacAntigCobrar`).
                    HStack(spacing: 6) {
                        StatusDot(color: Self.bucketColors[bucket]!)
                        Text(bucketTitle(bucket)).foregroundStyle(Palette.ink2)
                        Spacer(minLength: 8)
                        Text(amount == 0 ? "—" : amount.money)
                            .foregroundStyle(amount == 0 ? Palette.ink2 : bucket == .current ? Palette.ink : Palette.negative)
                    }
                    .monospacedDigit()
                    .frame(minHeight: 26)
                    .accessibilityElement(children: .combine)
                }
            }
            MacInspectorSection(title: String(localized: "Proporción")) {
                MacInspectorRow(String(localized: "Del total abierto"), value: share(row.total, of: report.total))
            }
        }
    }

    /// Filas de agencia del trimestre elegido (`MacSalesTax`).
    private var salesTaxQuarterRows: [AgencyRow] {
        agencyRows(salesTaxReport, payments: taxPayments(for: Period.quarter.interval(offset: taxQuarter)))
    }

    /// Saldo de Sales Tax Payable según libros (lo que pide «Registrar pago…»).
    private var salesTaxPayable: Int64 {
        accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
    }

    /// `MacSalesTax`: el saldo de la agencia en el trimestre, sus cifras, sus tasas y su declaración.
    @ViewBuilder
    private func salesTaxInspector(_ key: String) -> some View {
        let quarter = Period.quarter.interval(offset: taxQuarter)
        let payments = taxPayments(for: quarter)
        if let row = salesTaxQuarterRows.first(where: { $0.key == key }) {
            let due = Calendar.current.date(byAdding: .day, value: 19, to: quarter.end) ?? quarter.end
            let settled = row.balance <= 0 && row.collected > 0
            let agency = taxRates.compactMap(\.agency).first { $0.id == row.id }
            let lastPayment = payments.filter { $0.agency == row.id }.map(\.date).max()
            Text(row.components.count > 1 ? String(localized: "Tasa combinada · \(percent(row.rateMillionths))")
                 : [row.rates, percent(row.rateMillionths)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Palette.ink2)
            MacReportFigure(caption: String(localized: "Saldo por pagar"), amount: row.balance.money) {
                HStack(spacing: 5) {
                    StatusDot(color: settled ? Palette.green : row.balance > 0 ? Palette.orange : Palette.gray)
                    Text(settled ? String(localized: "Trimestre saldado")
                         : row.balance > 0 ? String(localized: "Vence el \(due.shortDate)") : String(localized: "Sin impuesto cobrado"))
                }
                .foregroundStyle(settled ? Palette.positive : row.balance > 0 ? Palette.warning : Palette.ink2)
            }
            MacInspectorSection(title: quarterTitle(taxQuarter)) {
                MacInspectorRow(String(localized: "Ventas gravables"), value: row.taxableSales.money)
                MacInspectorRow(String(localized: "Tasa"), value: percent(row.rateMillionths))
                MacInspectorRow(String(localized: "Impuesto cobrado"), value: row.collected.money)
                MacInspectorRow(String(localized: "Pagado"), value: row.paid.money)
                MacInspectorRow(String(localized: "Saldo"), value: row.balance.money, bold: true)
            }
            if row.components.count > 1 {
                MacInspectorSection(title: String(localized: "Tasas")) {
                    ForEach(row.components) { component in
                        MacInspectorRow(String(localized: "\(component.name) · \(percent(component.rateMillionths))"), value: component.tax.money)
                    }
                }
            }
            MacInspectorSection(title: String(localized: "Declaración")) {
                if let agency {
                    MacInspectorRow(String(localized: "Frecuencia"),
                                    value: (FilingFrequency(rawValue: agency.filingFrequencyRaw) ?? .quarterly).title)
                }
                MacInspectorRow(String(localized: "Estado del pago"),
                                value: lastPayment.map { String(localized: "Pagado el \($0.shortDate)") } ?? String(localized: "Sin pagos registrados"))
            }
        }
    }
    #endif

    // MARK: Datos de los reportes

    private var balanceSheetReport: BalanceSheet {
        let fiscalStart = (try? Bookkeeper(context: context).fiscalYearStart(containing: asOf))
            ?? Calendar.current.dateInterval(of: .year, for: asOf)?.start
        return ReportBuilder.balanceSheet(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: endOfDay(asOf), fiscalYearStart: fiscalStart)
    }

    private var trialBalanceReport: TrialBalance {
        ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: endOfDay(asOf))
    }

    // Las listas de facturas y de facturas de proveedor se observan para que los reportes se actualicen solos.
    private var receivablesReport: AgingReport {
        _ = invoices.count
        return (try? Bookkeeper(context: context).receivablesAging(asOf: asOf)) ?? ReportBuilder.aging(items: [], asOf: asOf)
    }

    private var payablesReport: AgingReport {
        _ = bills.count
        return (try? Bookkeeper(context: context).payablesAging(asOf: asOf)) ?? ReportBuilder.aging(items: [], asOf: asOf)
    }

    /// Último instante del día elegido: lo registrado ese día cuenta en el corte.
    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: date)) ?? date
    }

    private var salesTaxReport: SalesTaxSummary {
        _ = invoices.count
        let interval = isPhone ? interval() : Period.quarter.interval(offset: taxQuarter)
        return (try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1)))
            ?? ReportBuilder.salesTaxSummary(documents: [], from: interval.start, to: interval.end)
    }

    // MARK: Exportar

    /// Cada tipo de reporte exporta su propio contenido.
    private var csvFile: CSVFile {
        switch kind {
        case .income:
            CSVFile(name: String(localized: "Estado de resultados"),
                    text: CSVExport.incomeStatement(ledger.incomeStatement(interval()),
                                                    previous: compare ? ledger.incomeStatement(interval(offset: -1)) : nil))
        case .balance:
            CSVFile(name: String(localized: "Balance general"), text: CSVExport.balanceSheet(balanceSheetReport))
        case .trial:
            CSVFile(name: String(localized: "Balanza de comprobación"), text: CSVExport.trialBalance(trialBalanceReport))
        case .receivables:
            CSVFile(name: String(localized: "Antigüedad de cuentas por cobrar"),
                    text: CSVExport.aging(receivablesReport, title: String(localized: "Antigüedad de cuentas por cobrar"), partyTitle: String(localized: "Cliente")))
        case .salesTax:
            CSVFile(name: String(localized: "Resumen de sales tax"), text: CSVExport.salesTaxSummary(salesTaxReport))
        case .payables:
            CSVFile(name: String(localized: "Antigüedad de cuentas por pagar"),
                    text: CSVExport.aging(payablesReport, title: String(localized: "Antigüedad de cuentas por pagar"), partyTitle: String(localized: "Proveedor")))
        }
    }
}

// MARK: - Piezas

/// Grupo de filas de la lista agrupada (celda de radio 24 con separadores sangrados). Pieza propia del área A; podría
/// subir al sistema.
private struct PhoneGroup<Content: View>: View {
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
        #if os(macOS)
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
        #endif
    }
}

/// Barras del periodo (Tinta) frente al anterior (gris) por concepto (`ReportePyG`), con guías y escala a la derecha.
private struct ComparisonBars: View {
    let bars: [(String, Int64, Int64)]
    let showsPrevious: Bool

    var body: some View {
        let top = max(1, bars.map { max($0.1, showsPrevious ? $0.2 : 0) }.max() ?? 1)
        GeometryReader { proxy in
            let chartHeight = proxy.size.height - 20
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 3) {
                            column(bar.1, top: top, height: chartHeight, color: Palette.income)
                            if showsPrevious { column(bar.2, top: top, height: chartHeight, color: Palette.gray) }
                        }
                        .frame(height: chartHeight, alignment: .bottom)
                        Text(bar.0).font(.caption2).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.separator).frame(height: 0.5)
                    Spacer()
                    Rectangle().fill(Palette.separator).frame(height: 0.5)
                }
                .frame(height: chartHeight)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func column(_ amount: Int64, top: Int64, height: CGFloat, color: Color) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
            .fill(color)
            .frame(width: 22, height: max(amount > 0 ? 2 : 0, height * CGFloat(max(0, amount)) / CGFloat(top)))
    }
}

/// Archivo .csv para compartir (no texto suelto), con nombre sugerido.
struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName { "\($0.name).csv" }
    }
}

/// Texto de una celda en su color, o en blanco sobre la fila elegida de una tabla del Mac (`MacReportRow`). En iPhone e
/// iPad nunca hay fila elegida: queda en su color.
struct ReportCellText: View {
    let text: String
    var color: Color = Palette.ink2
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(text).foregroundStyle(prominence == .increased ? Palette.onBrandFill : color)
    }
}

#if os(macOS)

// MARK: - Mac: inspector de Inicio, Reportes e Impuestos

/// Inspector de las páginas del Mac que no son tabla (canvas `MacInicio`, `MacPyG`, `MacBalance`, `MacBalanza`,
/// `MacAntigCobrar`, `MacAntigPagar`, `MacSalesTax`, `MacImpuestos`): el mismo inspector nativo de `MacTablePage`
/// (~300 pt a la derecha, botón `sidebar.trailing` de la barra y ⌥⌘I, mostrado u oculto en `macInspectorShown`, igual
/// en todas las páginas) con la fila elegida de la página. Elegir una fila lo abre. Piezas propias de estas páginas;
/// podrían subir a `Shell/MacTablePage.swift`.
private struct MacReportInspector<Inspector: View, Actions: View>: ViewModifier {
    let title: String
    let hasSelection: Bool
    let placeholder: String
    /// Lo elegido a mano: al cambiar, el inspector se abre.
    let selectionKey: String?
    let qaSelectRow: ((Int) -> Void)?
    /// `false`: la página no tiene nada que inspeccionar (Inicio la primera vez): sin inspector (ni botón, con
    /// `macInspectorToggle(isAvailable:)`).
    let isAvailable: Bool
    let inspector: () -> Inspector
    let actions: () -> Actions
    @AppStorage("macInspectorShown") private var shown = true
    #if DEBUG
    @State private var qaApplied = false
    #endif

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: isAvailable ? $shown : .constant(false)) {
                column.inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .onChange(of: selectionKey) { _, key in if key != nil { shown = true } }
            #if DEBUG
            .onAppear {
                // Una vez por página: la primera que aparece puede ser una copia que SwiftUI descarta enseguida.
                guard !qaApplied else { return }
                qaApplied = true
                MacReportQA.apply(shown: $shown, selectRow: qaSelectRow)
            }
            #endif
    }

    /// Como el de `MacTablePage`: título de 15 bold, el contenido con scroll y los botones al pie.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            if hasSelection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) { inspector() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                VStack(spacing: 8) { actions() }
                    .padding(16)
            } else {
                ContentUnavailableView {
                    Label("Sin selección", systemImage: "sidebar.trailing")
                } description: {
                    Text(placeholder)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }
}

/// Botón `sidebar.trailing` de la barra que muestra u oculta el inspector (⌥⌘I). Va aparte del inspector para ponerlo
/// antes que la barra de la página: así queda el último por la derecha, como en el canvas.
private struct MacInspectorToggle: ViewModifier {
    let isAvailable: Bool
    @AppStorage("macInspectorShown") private var shown = true

    func body(content: Content) -> some View {
        content.toolbar {
            if isAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button { shown.toggle() } label: {
                        Label(shown ? "Ocultar inspector" : "Mostrar inspector", systemImage: "sidebar.trailing")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help(shown ? "Ocultar inspector (⌥⌘I)" : "Mostrar inspector (⌥⌘I)")
                    .tint(shown ? Palette.brand : Palette.ink)
                }
            }
        }
    }
}

extension View {
    /// Botón del inspector en la barra; aplicarlo antes del `.toolbar` de la página (ver `MacInspectorToggle`).
    func macInspectorToggle(isAvailable: Bool = true) -> some View {
        modifier(MacInspectorToggle(isAvailable: isAvailable))
    }

    /// Inspector del Mac con lo elegido en la página (ver `MacReportInspector`). `qaSelectRow` elige la fila N con
    /// `-qa.fila N` (solo Debug).
    func macReportInspector<Inspector: View, Actions: View>(
        title: String, hasSelection: Bool, placeholder: String, selectionKey: String?,
        qaSelectRow: ((Int) -> Void)? = nil, isAvailable: Bool = true,
        @ViewBuilder inspector: @escaping () -> Inspector,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        modifier(MacReportInspector(title: title, hasSelection: hasSelection, placeholder: placeholder, selectionKey: selectionKey,
                                    qaSelectRow: qaSelectRow, isAvailable: isAvailable, inspector: inspector, actions: actions))
    }
}

#if DEBUG
/// `-qa.inspector 0|1` y `-qa.fila N` también en Inicio, Reportes e Impuestos (como `QALaunch` en las tablas).
private enum MacReportQA {
    static func apply(shown: Binding<Bool>, selectRow: ((Int) -> Void)?) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "qa.inspector") != nil { shown.wrappedValue = defaults.bool(forKey: "qa.inspector") }
        if defaults.object(forKey: "qa.fila") != nil {
            let index = defaults.integer(forKey: "qa.fila")
            // Un momento después: al aparecer, las consultas de la página aún pueden venir vacías.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                selectRow?(index)
            }
        }
    }
}
#endif

/// Cifra de cabecera del inspector (canvas `MacPyG`, `MacBalance`, `MacInicio`…): leyenda gris, importe de 24 y una nota.
struct MacReportFigure<Foot: View>: View {
    let caption: String
    let amount: String
    @ViewBuilder var foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.subheadline).foregroundStyle(Palette.ink2)
            Text(amount).font(.amount(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
            foot.font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Fila elegible de las tablas propias del Mac (Inicio, Reportes, Impuestos): como `TableRow`, con su cebra, y la
/// elegida rellena de Tinta con el texto en blanco (`ReportCellText`, `MacCellText` y `MacCellStatus` cambian solos).
/// Un clic la elige y abre el inspector.
struct MacReportRow<Content: View>: View {
    let isSelected: Bool
    var zebra = false
    let select: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: TableCard<EmptyView, EmptyView>.columnSpacing) { content }
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.onBrandFill : Palette.ink)
                .padding(.horizontal, TableCard<EmptyView, EmptyView>.inset)
                .frame(minHeight: Metrics.target)
        }
        .background(isSelected ? Palette.brandFill : zebra ? Palette.surface : Color.clear)
        .environment(\.backgroundProminence, isSelected ? .increased : .standard)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
    }
}

/// Dos barras horizontales, el periodo (Tinta) frente al anterior (gris), del inspector de `MacPyG`.
private struct MacCompareBars: View {
    let current: (title: String, amount: Int64)
    let previous: (title: String, amount: Int64)

    var body: some View {
        let top = max(1, abs(current.amount), abs(previous.amount))
        VStack(alignment: .leading, spacing: 6) {
            bar(current.title, current.amount, top: top, color: Palette.income)
            bar(previous.title, previous.amount, top: top, color: Palette.gray)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current.title): \(current.amount.money), \(previous.title): \(previous.amount.money)")
    }

    private func bar(_ title: String, _ amount: Int64, top: Int64, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
            Capsule().fill(Palette.surface2).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(color).frame(width: max(amount == 0 ? 0 : 3, proxy.size.width * CGFloat(abs(amount)) / CGFloat(top)))
                    }
                }
        }
    }
}

/// Barra apilada Pasivos (naranja) · Patrimonio (Tinta) con su leyenda (`MacBalance`, «Composición del balance»).
private struct MacBalanceMix: View {
    let liabilities: Int64
    let equity: Int64

    var body: some View {
        let total = max(0, liabilities) + max(0, equity)
        let share = total == 0 ? 0 : Double(max(0, liabilities)) / Double(total)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: share > 0 && share < 1 ? 2 : 0) {
                    if share > 0 { Rectangle().fill(Palette.orange).frame(width: (proxy.size.width - 2) * share) }
                    if share < 1 && total > 0 { Rectangle().fill(Palette.brand) }
                }
            }
            .frame(height: 8)
            .background(Palette.surface2)
            .clipShape(Capsule())
            HStack(spacing: 12) {
                HStack(spacing: 5) { StatusDot(color: Palette.orange); Text("Pasivos \(percent(share))") }
                HStack(spacing: 5) { StatusDot(color: Palette.brand); Text("Patrimonio \(percent(total == 0 ? 0 : 1 - share))") }
            }
            .font(.subheadline).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Composición del balance")
        .accessibilityValue("Pasivos \(percent(share)), patrimonio \(percent(total == 0 ? 0 : 1 - share))")
    }

    private func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

#endif

#Preview {
    NavigationStack { ReportsView() }.modelContainer(SampleData.makeContainer())
}
