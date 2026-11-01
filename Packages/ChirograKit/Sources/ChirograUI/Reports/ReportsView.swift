import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Reportes. iPhone sigue el tablero `ReportePyG` del canvas; iPad y Mac, `MacPyG`: cabecera con la empresa y
/// exportar, filtros, cuatro cifras clave y la tabla con variación frente al periodo anterior.
/// Todos se calculan con `ReportBuilder` a partir de las líneas contabilizadas.
struct ReportsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case income = "Resultados"
        case balance = "Balance general"
        case trial = "Balanza"
        case receivables = "Por cobrar"
        case payables = "Por pagar"
        case salesTax = "Sales tax"
        var id: String { rawValue }

        /// Nombre completo: título en iPad y Mac, y lista «Reportes» de la barra lateral del Mac.
        var fullTitle: String {
            switch self {
            case .income: String(localized: "Estado de resultados")
            case .balance: String(localized: "Balance general")
            case .trial: String(localized: "Balanza de comprobación")
            case .receivables: String(localized: "Antigüedad por cobrar")
            case .payables: String(localized: "Antigüedad por pagar")
            case .salesTax: String(localized: "Resumen de sales tax")
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

    /// Ancho de una columna de importes: normal, «%» o tramo de antigüedad.
    private enum ColumnSize { case regular, percent, bucket }

    /// Una celda de importe en una fila de la tabla.
    private struct Cell {
        let text: String
        var color: Color = Palette.ink
        var size: ColumnSize = .regular
    }

    /// En la barra lateral del Mac cada reporte es una entrada propia; entonces no se muestran las pestañas.
    var fixedKind: Kind? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .body) private var wideColumnWidth: CGFloat = 120
    @ScaledMetric(relativeTo: .body) private var percentColumnWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .body) private var bucketColumnWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var wideRowHeight: CGFloat = Self.minimumRowHeight
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var invoices: [Invoice]
    @Query private var bills: [Bill]
    @Query private var companies: [Company]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]
    @Query private var entries: [JournalEntry]

    @State private var selectedKind: Kind = .income
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

    private var kind: Kind { fixedKind ?? selectedKind }
    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }

    // MARK: Medidas

    #if os(macOS)
    private static let minimumRowHeight: CGFloat = 34
    #else
    private static let minimumRowHeight: CGFloat = 44
    #endif

    /// Ancho de iPhone (o de iPad en Split View estrecho).
    private var isNarrow: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    /// Una sola columna como en iPhone: en pantallas estrechas, con menos de 600 pt de contenido y con los dos
    /// tamaños de accesibilidad más grandes. En iPad con AX1–AX3 hay sitio para las columnas.
    private var isCompact: Bool {
        isNarrow || dynamicTypeSize >= .accessibility4 || (width > 0 && width - 2 * margin < 600)
    }

    /// VARIACIÓN y % sólo si caben junto a los dos periodos (no en iPad vertical con la barra lateral).
    private var showsVariationColumns: Bool { !isCompact && width - 2 * margin >= (showsDeltaColumn ? 760 : 640) }

    /// La variación en dinero sólo en el Mac (`MacPyG`); el iPad (`iPadPyG`) muestra sólo el %.
    private var showsDeltaColumn: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Importes debajo del nombre en vez de en columnas: sólo en la columna única con tamaños de accesibilidad.
    private var stacksRows: Bool { isCompact && dynamicTypeSize.isAccessibilitySize }

    /// En pantallas anchas el margen coincide con el del título grande, para que el reporte empiece donde empieza el título.
    private var margin: CGFloat { isNarrow ? Metrics.gutter : 20 }
    private var rowFont: Font { isCompact ? .subheadline : .body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? Metrics.cardSpacing : 16) {
                if !isNarrow { pageHeader }
                if fixedKind == nil { kindChips }
                if kind == .income || (kind == .salesTax && isCompact) { periodControls }
                switch kind {
                case .income: incomeStatement
                case .balance: balanceSheet
                case .trial: trialBalance
                case .receivables: aging(receivablesReport, party: String(localized: "CLIENTE"), total: String(localized: "Total por cobrar"), empty: String(localized: "No hay facturas pendientes de cobro."))
                case .payables: aging(payablesReport, party: String(localized: "PROVEEDOR"), total: String(localized: "Total por pagar"), empty: String(localized: "No hay facturas de proveedores pendientes."))
                case .salesTax: salesTax
                }
            }
            .padding(.horizontal, margin)
            .padding(.vertical, Metrics.gutter)
            .frame(maxWidth: isNarrow ? 900 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle(isNarrow ? String(localized: "Reportes") : kind.fullTitle)
        .toolbar {
            if isNarrow {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: csvFile, preview: SharePreview("\(csvFile.name).csv")) {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: Cabecera y filtros

    /// `MacPyG`: empresa · base · moneda, y «Exportar CSV» a la derecha. En el Mac el título va también aquí,
    /// porque el de la ventana es pequeño.
    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) { pageTitle; Spacer(minLength: 8); headerActions }
            VStack(alignment: .leading, spacing: 12) { pageTitle; HStack(spacing: 12) { headerActions } }
        }
    }

    private var pageTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            #if os(macOS)
            Text(kind.fullTitle).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ink)
            #endif
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink3)
        }
    }

    /// Fecha de corte («Al …»), trimestre del sales tax y exportar. En el Mac «Exportar CSV» con borde (`MacPyG`);
    /// en el iPad, «Exportar» en color de marca (`iPadPyG`).
    @ViewBuilder
    private var headerActions: some View {
        if kind == .balance || kind == .trial || kind == .receivables || kind == .payables {
            DatePicker("Al", selection: $asOf, in: ...Date.now, displayedComponents: .date)
                .fixedSize()
                .font(.subheadline.weight(.semibold))
        }
        if kind == .salesTax { quarterPicker }
        ShareLink(item: csvFile, preview: SharePreview("\(csvFile.name).csv")) {
            #if os(macOS)
            Text("Exportar CSV")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
            #else
            Text("Exportar")
                .font(.body.weight(.semibold))
                .foregroundStyle(kind == .salesTax ? Palette.ink : Palette.onBrand)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(kind == .salesTax ? Palette.surface : Palette.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(kind == .salesTax ? Palette.separator : .clear))
            #endif
        }
        .buttonStyle(.plain)
        if kind == .salesTax {
            NavigationLink { TaxesView() } label: {
                Text("Registrar pago de impuesto")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onBrand)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Self.minimumRowHeight)
                    .background(Palette.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        let company = companies.first
        let name = company.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? ""
        switch kind {
        case .income:
            #if os(macOS)
            return String(localized: "\(name) · base devengado · \(company?.currencyCode ?? "USD")")
            #else
            return String(localized: "\(rangeTitle) · base devengado")
            #endif
        case .balance:
            return String(localized: "\(name) · base devengado · \(company?.currencyCode ?? "USD")")
        case .trial:
            let count = trialBalanceReport.rows.count
            return String(localized: "Saldos al \(asOf.shortDate) · \(count) cuentas con movimiento")
        case .receivables:
            return String(localized: "Facturas de clientes abiertas · días después del vencimiento · \(lateTotal(receivablesReport).money) vencido")
        case .payables:
            return String(localized: "Facturas de proveedores abiertas · días después del vencimiento · \(lateTotal(payablesReport).money) vencido")
        case .salesTax:
            return String(localized: "Sales tax por agencia · un trimestre por declaración")
        }
    }

    /// «Octubre de 2026», «T4 2026 (oct–dic)» o «2026», para el subtítulo del iPad.
    private var rangeTitle: String {
        switch period {
        case .month: return periodName(offset: 0).sentenceCased
        case .quarter: return "\(periodName(offset: 0)) (\(rangeLabel))"
        case .year, .custom: return rangeLabel
        }
    }

    private func lateTotal(_ report: AgingReport) -> Int64 { report.total - report.total(for: .current) }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Kind.allCases) { option in
                    FilterChip(title: option.localizedTitle, isSelected: kind == option) { selectedKind = option }
                }
            }
        }
    }

    @ViewBuilder
    private var periodControls: some View {
        if isNarrow {
            // `ReportePyG`: botón «Octubre 2026 ▾» (elige mes, trimestre o año) y casilla «vs. septiembre».
            // Si no caben juntos (iPhone pequeño, texto grande), la casilla baja a su línea.
            ViewThatFits(in: .horizontal) {
                HStack { periodMenu; Spacer(minLength: 8); if kind == .income { compareCheckbox.fixedSize() } }
                VStack(alignment: .leading, spacing: 8) { periodMenu; if kind == .income { compareCheckbox } }
            }
        } else {
            #if os(macOS)
            // `MacPyG`: segmentado con «Personalizado», botón con el rango y casilla «Comparar con periodo anterior».
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { periodPicker(Period.allCases); rangeButton; compareBox }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) { periodPicker(Period.allCases); rangeButton }
                    compareBox
                }
            }
            #else
            // `iPadPyG`: Mes, Trimestre y Año, y la casilla; el rango va en el subtítulo.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { periodPicker([.month, .quarter, .year]); compareBox }
                VStack(alignment: .leading, spacing: 12) { periodPicker([.month, .quarter, .year]); compareBox }
            }
            #endif
        }
    }

    private var periodMenu: some View {
        Menu {
            Picker("Periodo", selection: $period) {
                ForEach(Period.allCases.filter { $0 != .custom }) { Text($0.localizedTitle).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(periodName(offset: 0)).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Periodo")
        .accessibilityValue(periodName(offset: 0))
    }

    private var compareCheckbox: some View {
        Toggle(isOn: $compare) { Text("vs. \(previousName)").foregroundStyle(Palette.ink2) }
            .toggleStyle(CheckboxStyle())
    }

    /// «Octubre 2026», «T4 2026» o «2026».
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

    /// Segmentado; con tamaños de accesibilidad, menú (el segmentado no crece con el texto).
    @ViewBuilder
    private func periodPicker(_ options: [Period]) -> some View {
        let picker = Picker("Periodo", selection: $period) {
            ForEach(options) { Text($0.localizedTitle).tag($0) }
        }
        .labelsHidden()
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker
                .pickerStyle(.segmented)
                .fixedSize()
                .controlSize(isNarrow ? .regular : .large)
        }
    }

    private var rangeButton: some View {
        Button { editingRange = true } label: {
            HStack(spacing: 6) {
                Text(rangeLabel).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(String(localized: "Fechas del periodo"))
        .accessibilityValue(rangeLabel)
        .popover(isPresented: $editingRange) { rangeEditor }
    }

    /// Elegir fechas pasa el periodo a «Personalizado».
    private var rangeEditor: some View {
        let start = Binding(get: { interval().start }, set: { customStart = $0; customEnd = max(customEnd, $0); period = .custom })
        let end = Binding(get: { interval().end.addingTimeInterval(-1) }, set: { customEnd = $0; customStart = min(customStart, $0); period = .custom })
        return VStack(alignment: .leading, spacing: 12) {
            DatePicker("Desde", selection: start, displayedComponents: .date)
            DatePicker("Hasta", selection: end, displayedComponents: .date)
        }
        .padding(20)
        .frame(minWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    private var compareBox: some View {
        Toggle(isOn: $compare) { Text("Comparar con periodo anterior").foregroundStyle(Palette.ink2) }
            .toggleStyle(CheckboxStyle())
            .opacity(kind == .income ? 1 : 0)
            .accessibilityHidden(kind != .income)
            .fixedSize()
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

    /// Encabezado de columna del periodo: «OCT 2026», «T4 2026», «2026»; en rangos personalizados, «ACTUAL»/«ANTERIOR».
    private func columnTitle(offset: Int) -> String {
        let start = interval(offset: offset).start
        let year = start.formatted(.appDateTime.year())
        switch period {
        // Tres letras como en el canvas («SEP 2026»; la abreviatura del sistema en español es «sept»). En iPhone,
        // sólo el mes («OCT · SEP»), como en `ReportePyG`.
        case .month: return isNarrow ? start.shortMonth.uppercased() : "\(start.shortMonth.uppercased()) \(year)"
        case .quarter: return String(localized: "T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1) \(year)")
        case .year: return year
        case .custom: return offset == 0 ? String(localized: "ACTUAL") : String(localized: "ANTERIOR")
        }
    }

    // MARK: Estado de resultados

    private var incomeStatement: some View {
        let current = ledger.incomeStatement(interval())
        let previous = ledger.incomeStatement(interval(offset: -1))
        return VStack(spacing: isCompact ? Metrics.cardSpacing : 16) {
            if isCompact {
                HeroCard(title: String(localized: "Ganancia neta"), value: current.netIncome.money,
                         detail: String(localized: "\(interval().start.shortDate) – \(interval().end.addingTimeInterval(-1).shortDate)"),
                         badge: compare ? percentChange(current.netIncome, previous.netIncome).map { "\($0) vs. \(previousShort)" } : nil)
            } else {
                KPIGrid(items: incomeKPIs(current, previous))
            }
            VStack(spacing: 0) {
                header(columns: compare ? [columnTitle(offset: 0), columnTitle(offset: -1)] : [columnTitle(offset: 0)], variation: compare)
                group(String(localized: "Ingresos"), current.income, compare ? previous.income : nil, trend: .upIsGood)
                totalRow(String(localized: "Total ingresos"), current.totalIncome, previous.totalIncome, trend: .upIsGood)
                group(String(localized: "Costo de ventas"), current.costOfGoodsSold, compare ? previous.costOfGoodsSold : nil, trend: .downIsGood)
                totalRow(String(localized: "Total costo de ventas"), current.totalCostOfGoodsSold, previous.totalCostOfGoodsSold, trend: .downIsGood)
                totalRow(String(localized: "Utilidad bruta"), current.grossProfit, previous.grossProfit, trend: .upIsGood)
                group(String(localized: "Gastos operativos"), current.expenses, compare ? previous.expenses : nil, trend: .downIsGood)
                totalRow(String(localized: "Total gastos operativos"), current.totalExpenses, previous.totalExpenses, trend: .downIsGood)
                totalRow(String(localized: "Ganancia neta"), current.netIncome, previous.netIncome, trend: .upIsGood, highlighted: true)
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    private func incomeKPIs(_ current: IncomeStatement, _ previous: IncomeStatement) -> [KPIItem] {
        func change(_ now: Int64, _ before: Int64, _ trend: Trend) -> (String?, Color) {
            guard compare, let percent = percentChange(now, before) else { return (nil, Palette.ink3) }
            return (percent, color(for: now - before, trend))
        }
        func margin(_ amount: Int64) -> String? {
            current.totalIncome > 0 ? String(localized: "Margen \(amount * 100 / current.totalIncome)%") : nil
        }
        let income = change(current.totalIncome, previous.totalIncome, .upIsGood)
        let expenses = change(current.totalExpenses, previous.totalExpenses, .downIsGood)
        let net = change(current.netIncome, previous.netIncome, .upIsGood)
        return [
            KPIItem(title: String(localized: "Ingresos"), value: current.totalIncome.money, foot: income.0, footColor: income.1),
            KPIItem(title: String(localized: "Utilidad bruta"), value: current.grossProfit.money, foot: margin(current.grossProfit)),
            KPIItem(title: String(localized: "Gastos operativos"), value: current.totalExpenses.money, foot: expenses.0, footColor: expenses.1),
            KPIItem(title: String(localized: "Ganancia neta"), value: current.netIncome.money,
                foot: [margin(current.netIncome), net.0].compactMap { $0 }.joined(separator: " · "), isBrand: true),
        ]
    }

    // MARK: Balance general

    @ViewBuilder
    private var balanceSheet: some View {
        if isCompact { compactBalanceSheet } else { wideBalanceSheet }
    }

    /// `MacBalance`: tres cifras, la comprobación arriba y dos columnas (activos | pasivos y patrimonio).
    private var wideBalanceSheet: some View {
        let report = balanceSheetReport
        let twoColumns = width - 2 * margin >= 2 * 380 + 16
        let assets = VStack(spacing: 0) {
            group(String(localized: "Activos"), report.assets, nil)
            totalRow(String(localized: "Total activos"), report.totalAssets, nil, highlighted: true)
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        let liabilities = VStack(spacing: 0) {
            group(String(localized: "Pasivos"), report.liabilities, nil)
            totalRow(String(localized: "Total pasivos"), report.totalLiabilities, nil, highlighted: true)
            group(String(localized: "Patrimonio"), report.equity, nil)
            line(String(localized: "Resultados de años anteriores"), report.priorYearsEarnings, nil, indent: true)
            line(String(localized: "Resultado del ejercicio"), report.currentYearEarnings, nil, indent: true)
            totalRow(String(localized: "Total patrimonio"), report.totalEquity, nil, highlighted: true)
            totalRow(String(localized: "Pasivo + patrimonio"), report.totalLiabilities + report.totalEquity, nil, highlighted: true)
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        return VStack(spacing: 16) {
            KPIGrid(items: [KPIItem(title: String(localized: "Activos"), value: report.totalAssets.money),
                            KPIItem(title: String(localized: "Pasivos"), value: report.totalLiabilities.money),
                            KPIItem(title: String(localized: "Patrimonio"), value: report.totalEquity.money, isBrand: true)])
            equationBanner(report)
            if twoColumns {
                HStack(alignment: .top, spacing: 16) { assets.frame(maxWidth: .infinity); liabilities.frame(maxWidth: .infinity) }
            } else {
                assets
                liabilities
            }
        }
    }

    private func equationBanner(_ report: BalanceSheet) -> some View {
        let difference = report.totalAssets - report.totalLiabilities - report.totalEquity
        return HStack(spacing: 10) {
            Image(systemName: report.isBalanced ? "checkmark" : "exclamationmark.triangle").fontWeight(.bold).accessibilityHidden(true)
            Text("Activo \(report.totalAssets.money) = Pasivo \(report.totalLiabilities.money) + Patrimonio \(report.totalEquity.money)")
            Spacer(minLength: 8)
            Text(report.isBalanced ? String(localized: "Cuadra") : String(localized: "Diferencia \(difference.money)")).font(.footnote.weight(.semibold))
        }
        .font(.body.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(report.isBalanced ? Palette.positive : Palette.negative)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(report.isBalanced ? Palette.positiveWash : Palette.negativeWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var compactBalanceSheet: some View {
        let report = balanceSheetReport
        return VStack(spacing: 16) {
            VStack(spacing: 0) {
                header(columns: [String(localized: "AL \(asOf.shortDate.uppercased())")])
                group(String(localized: "Activos"), report.assets, nil)
                totalRow(String(localized: "Total activos"), report.totalAssets, nil)
                group(String(localized: "Pasivos"), report.liabilities, nil)
                totalRow(String(localized: "Total pasivos"), report.totalLiabilities, nil)
                group(String(localized: "Patrimonio"), report.equity, nil)
                line(String(localized: "Resultados de años anteriores"), report.priorYearsEarnings, nil, indent: true)
                line(String(localized: "Resultado del ejercicio"), report.currentYearEarnings, nil, indent: true)
                totalRow(String(localized: "Total patrimonio"), report.totalEquity, nil)
                totalRow(String(localized: "Pasivo + patrimonio"), report.totalLiabilities + report.totalEquity, nil, highlighted: true)
                balanceCheck(report.isBalanced, ok: String(localized: "Activo = Pasivo + Patrimonio"), bad: String(localized: "El balance no cuadra"))
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    // MARK: Balanza de comprobación

    private var trialBalanceReport: TrialBalance {
        ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: endOfDay(asOf))
    }

    @ViewBuilder
    private var trialBalance: some View {
        if isCompact { compactTrialBalance } else { wideTrialBalance }
    }

    /// `MacBalanza`: Nº · CUENTA · TIPO · DÉBITO · CRÉDITO y la fila de totales con «Cuadra».
    private var wideTrialBalance: some View {
        let report = trialBalanceReport
        let difference = abs(report.totalDebit - report.totalCredit)
        return TableCard {
            Text("Nº").frame(width: 56, alignment: .leading)
            Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tipo").frame(width: 170, alignment: .leading)
            Text("Débito").frame(width: wideColumnWidth + 10, alignment: .trailing)
            Text("Crédito").frame(width: wideColumnWidth + 10, alignment: .trailing)
        } rows: {
            ForEach(report.rows) { row in
                TableRow {
                    Text(row.account.code).foregroundStyle(Palette.ink3).frame(width: 56, alignment: .leading)
                    Text(row.account.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.account.subtype.title).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 170, alignment: .leading)
                    Text(row.debit == 0 ? "" : row.debit.money).frame(width: wideColumnWidth + 10, alignment: .trailing)
                    Text(row.credit == 0 ? "" : row.credit.money).frame(width: wideColumnWidth + 10, alignment: .trailing)
                }
            }
            VStack(spacing: 0) {
                Rectangle().fill(Palette.ink).frame(height: 2)
                HStack(spacing: 12) {
                    Color.clear.frame(width: 56, height: 1)
                    Text("Totales").frame(maxWidth: .infinity, alignment: .leading)
                    Text(report.isBalanced ? String(localized: "✓ Cuadra") : String(localized: "Diferencia \(difference.money)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(report.isBalanced ? Palette.positive : Palette.negative)
                        .frame(width: 170, alignment: .leading)
                    Text(report.totalDebit.money).frame(width: wideColumnWidth + 10, alignment: .trailing)
                    Text(report.totalCredit.money).frame(width: wideColumnWidth + 10, alignment: .trailing)
                }
                .font(.body.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background(report.isBalanced ? Palette.positiveWash : Palette.negativeWash)
                .accessibilityElement(children: .combine)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var compactTrialBalance: some View {
        let report = trialBalanceReport
        return VStack(spacing: 16) {
            VStack(spacing: 0) {
                header(columns: [String(localized: "DEBE"), String(localized: "HABER")])
                ForEach(report.rows) { row in
                    rowView(row.account.name, [Cell(text: row.debit == 0 ? "" : row.debit.money),
                                               Cell(text: row.credit == 0 ? "" : row.credit.money, color: Palette.ink3)])
                }
                Divider()
                rowView(String(localized: "Totales"), [Cell(text: report.totalDebit.money), Cell(text: report.totalCredit.money, color: Palette.ink3)], bold: true)
                balanceCheck(report.isBalanced, ok: String(localized: "Débitos = créditos"), bad: String(localized: "La balanza no cuadra"))
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    // MARK: Antigüedad de cuentas por cobrar y por pagar

    private func aging(_ report: AgingReport, party: String, total: String, empty: String) -> some View {
        let titles: [AgingReport.Bucket: String] = [.current: String(localized: "Corriente"), .days1to30: "1–30", .days31to60: "31–60", .days61to90: "61–90", .over90: "> 90"]
        // En pantallas anchas, una columna por tramo (si caben con al menos 180 pt para el nombre).
        let byBucket = !isCompact && width - 2 * margin - 32 >= 6 * bucketColumnWidth + 180
        return VStack(alignment: .leading, spacing: isCompact ? Metrics.cardSpacing : 16) {
            if isCompact {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                        KPITile(title: titles[bucket]!, value: report.total(for: bucket).money)
                    }
                }
            } else {
                agingBuckets(report)
            }
            if byBucket {
                agingTable(report, party: party, total: total, empty: empty)
            } else {
            VStack(spacing: 0) {
                if byBucket {
                    header(party, columns: AgingReport.Bucket.allCases.map { titles[$0]!.uppercased() } + [String(localized: "TOTAL")], size: .bucket)
                    ForEach(report.rows) { row in
                        rowView(row.party, AgingReport.Bucket.allCases.map { bucket in
                            let amount = row.amounts[bucket] ?? 0
                            return Cell(text: amount == 0 ? "—" : amount.money, color: amount == 0 ? Palette.ink3 : Palette.ink, size: .bucket)
                        } + [Cell(text: row.total.money, size: .bucket)])
                    }
                } else {
                    header(party, columns: [String(localized: "VENCIDO"), String(localized: "TOTAL")])
                    ForEach(report.rows) { row in
                        let overdue = row.total - (row.amounts[.current] ?? 0)
                        rowView(row.party, [Cell(text: overdue.money), Cell(text: row.total.money, color: Palette.ink3)])
                    }
                }
                if report.rows.isEmpty { Text(empty).foregroundStyle(Palette.ink3).padding() }
                Divider()
                if byBucket {
                    rowView(total, AgingReport.Bucket.allCases.map { bucket in
                        let amount = report.total(for: bucket)
                        return Cell(text: amount == 0 ? "—" : amount.money, color: amount == 0 ? Palette.ink3 : Palette.ink, size: .bucket)
                    }
                                   + [Cell(text: report.total.money, size: .bucket)], bold: true)
                } else {
                    rowView(total, [Cell(text: ""), Cell(text: report.total.money, color: Palette.ink3)], bold: true)
                }
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
        }
    }

    private static let wideBucketTitles: [AgingReport.Bucket: String] = [
        .current: String(localized: "Al día"), .days1to30: "1–30", .days31to60: "31–60", .days61to90: "61–90", .over90: "90+",
    ]

    /// `MacAntigCobrar`: «Total abierto» en color de marca y una tarjeta por tramo con su barra; lo vencido, en rojo.
    private func agingBuckets(_ report: AgingReport) -> some View {
        let grand = report.total
        let colors: [AgingReport.Bucket: Color] = [.current: Palette.brand, .days1to30: Color(light: 0xF2B33D, dark: 0xF2B33D),
                                                   .days31to60: Color(light: 0xE58A4E, dark: 0xE58A4E), .days61to90: Palette.negative, .over90: Palette.negative]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            bucketCard(String(localized: "Total abierto"), grand, share: 1, bar: Palette.onBrand, brand: true, late: false)
            ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                let amount = report.total(for: bucket)
                bucketCard(bucket == .current ? Self.wideBucketTitles[bucket]! : String(localized: "\(Self.wideBucketTitles[bucket]!) días"),
                           amount, share: grand == 0 ? 0 : Double(amount) / Double(grand), bar: colors[bucket]!, brand: false,
                           late: bucket != .current && amount > 0)
            }
        }
    }

    private func bucketCard(_ title: String, _ amount: Int64, share: Double, bar: Color, brand: Bool, late: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).opacity(0.85)
            Text(amount.money).font(.amount(20)).lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(brand ? Palette.onBrand.opacity(0.25) : Palette.surface2)
                    Capsule().fill(bar).frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .foregroundStyle(brand ? Palette.onBrand : late ? Palette.negative : Palette.ink)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand ? Palette.brand : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Tabla por tramos con el nombre enlazado a la ficha del cliente o del proveedor.
    private func agingTable(_ report: AgingReport, party: String, total: String, empty: String) -> some View {
        TableCard {
            Text(party).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                Text(Self.wideBucketTitles[bucket]!).frame(width: bucketColumnWidth, alignment: .trailing)
            }
            Text("Total").frame(width: bucketColumnWidth + 10, alignment: .trailing)
        } rows: {
            ForEach(report.rows) { row in
                TableRow {
                    partyLink(row.party).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                        let amount = row.amounts[bucket] ?? 0
                        Text(amount == 0 ? "—" : amount.money)
                            .fontWeight(bucket != .current && amount > 0 ? .semibold : .regular)
                            .foregroundStyle(amount == 0 ? Palette.ink3 : bucket == .current ? Palette.ink : Palette.negative)
                            .frame(width: bucketColumnWidth, alignment: .trailing)
                    }
                    Text(row.total.money).fontWeight(.bold).frame(width: bucketColumnWidth + 10, alignment: .trailing)
                }
            }
            if report.rows.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            VStack(spacing: 0) {
                Rectangle().fill(Palette.ink).frame(height: 2)
                HStack(spacing: 12) {
                    Text(total).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                        let amount = report.total(for: bucket)
                        Text(amount == 0 ? "—" : amount.money).frame(width: bucketColumnWidth, alignment: .trailing)
                    }
                    Text(report.total.money).frame(width: bucketColumnWidth + 10, alignment: .trailing)
                }
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background(Palette.brandWash)
                .accessibilityElement(children: .combine)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func partyLink(_ name: String) -> some View {
        if kind == .receivables, let customer = customers.first(where: { $0.name == name }) {
            NavigationLink(name) { CustomerDetailView(customer: customer) }.buttonStyle(.plain).fontWeight(.semibold).lineLimit(1)
        } else if kind == .payables, let vendor = vendors.first(where: { $0.name == name }) {
            NavigationLink(name) { VendorDetailView(vendor: vendor) }.buttonStyle(.plain).fontWeight(.semibold).lineLimit(1)
        } else {
            Text(name).fontWeight(.semibold).lineLimit(1)
        }
    }

    // MARK: Sales tax

    @ViewBuilder
    private var salesTax: some View {
        let summary = salesTaxReport
        if isCompact {
            SalesTaxSummaryCard(report: summary)
        } else {
            wideSalesTax(summary)
        }
    }

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

    private var quarterPicker: some View {
        Picker("Trimestre", selection: $taxQuarter) {
            ForEach([-3, -2, -1, 0], id: \.self) { offset in
                let start = Period.quarter.interval(offset: offset).start
                Text("T\((Calendar.current.component(.month, from: start) - 1) / 3 + 1) \(start.formatted(.appDateTime.year()))").tag(offset)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private func percent(_ millionths: Int64) -> String {
        (Decimal(millionths) / 10_000).formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// `MacSalesTax`: ventas gravables, cobrado, pagado y saldo del trimestre, y la tabla por agencia.
    private func wideSalesTax(_ summary: SalesTaxSummary) -> some View {
        let quarter = Period.quarter.interval(offset: taxQuarter)
        let payments = taxPayments(for: quarter)
        let rows = agencyRows(summary, payments: payments)
        let paid = payments.reduce(0) { $0 + $1.amount }
        let balance = summary.totalTax - paid
        let lastPayment = payments.map(\.date).max()
        return VStack(alignment: .leading, spacing: 16) {
            KPIGrid(items: [
                KPIItem(title: String(localized: "Ventas gravables"), value: summary.taxableSales.money,
                        foot: String(localized: "Exentas \(summary.exemptSales.money)")),
                KPIItem(title: String(localized: "Impuesto cobrado"), value: summary.totalTax.money),
                KPIItem(title: String(localized: "Pagado"), value: paid.money,
                        foot: lastPayment.map { String(localized: "Pagado el \($0.shortDate)") } ?? String(localized: "Sin pagos registrados")),
                KPIItem(title: String(localized: "Saldo"), value: balance.money,
                        foot: balance <= 0 && summary.totalTax > 0 ? String(localized: "Trimestre saldado") : String(localized: "Pendiente de pagar"),
                        isBrand: balance > 0),
            ])
            TableCard {
                Text("Jurisdicción").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tasa").frame(width: 70, alignment: .trailing)
                Text("Ventas gravables").frame(width: 150, alignment: .trailing)
                Text("Cobrado").frame(width: wideColumnWidth, alignment: .trailing)
                Text("Pagado").frame(width: wideColumnWidth, alignment: .trailing)
                Text("Saldo").frame(width: wideColumnWidth, alignment: .trailing)
            } rows: {
                ForEach(rows) { row in
                    TableRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).fontWeight(.semibold)
                            if row.components.count > 1 {
                                Text("Tasa combinada").font(.caption).foregroundStyle(Palette.ink3)
                            } else if !row.rates.isEmpty {
                                Text(row.rates).font(.caption).foregroundStyle(Palette.ink3)
                            }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(percent(row.rateMillionths)).frame(width: 70, alignment: .trailing)
                        Text(row.taxableSales.money).frame(width: 150, alignment: .trailing)
                        Text(row.collected.money).frame(width: wideColumnWidth, alignment: .trailing)
                        Text(row.paid.money).frame(width: wideColumnWidth, alignment: .trailing)
                        Text(row.balance.money).fontWeight(.bold).frame(width: wideColumnWidth, alignment: .trailing)
                    }
                    // Desglose por jurisdicción de la tasa combinada; lo pagado se registra por agencia.
                    if row.components.count > 1 {
                        ForEach(row.components) { component in
                            TableRow {
                                Text(component.name).foregroundStyle(Palette.ink2).lineLimit(1).padding(.leading, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(percent(component.rateMillionths)).foregroundStyle(Palette.ink2).frame(width: 70, alignment: .trailing)
                                Text(component.taxableSales.money).foregroundStyle(Palette.ink2).frame(width: 150, alignment: .trailing)
                                Text(component.tax.money).foregroundStyle(Palette.ink2).frame(width: wideColumnWidth, alignment: .trailing)
                                Text("—").foregroundStyle(Palette.ink3).frame(width: wideColumnWidth, alignment: .trailing)
                                Text("—").foregroundStyle(Palette.ink3).frame(width: wideColumnWidth, alignment: .trailing)
                            }
                        }
                    }
                }
                if rows.isEmpty {
                    Text("Sin impuesto cobrado en el periodo.").font(.subheadline).foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.ink).frame(height: 2)
                    HStack(spacing: 12) {
                        Text("Total · tasa combinada").frame(maxWidth: .infinity, alignment: .leading)
                        Text(percent(rows.reduce(0) { $0 + $1.rateMillionths })).frame(width: 70, alignment: .trailing)
                        Text(summary.taxableSales.money).frame(width: 150, alignment: .trailing)
                        Text(summary.totalTax.money).frame(width: wideColumnWidth, alignment: .trailing)
                        Text(paid.money).frame(width: wideColumnWidth, alignment: .trailing)
                        Text(balance.money).frame(width: wideColumnWidth, alignment: .trailing)
                    }
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 18)
                    .frame(minHeight: 46)
                    .background(Palette.brandWash)
                    .accessibilityElement(children: .combine)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Cuentan como pagados los pagos registrados en el trimestre siguiente, cuando se presenta la declaración. Las tasas y las agencias se configuran en Impuestos.")
                .font(.footnote).foregroundStyle(Palette.ink3)
        }
    }

    // MARK: Filas

    /// `variation`: añade «VARIACIÓN» y «%» (sólo en pantallas anchas, como en `MacPyG`).
    private func header(_ first: String = String(localized: "CUENTA"), columns: [String], size: ColumnSize = .regular,
                        variation: Bool = false) -> some View {
        let showsVariation = variation && showsVariationColumns
        let titles = columns + (showsVariation && showsDeltaColumn ? [String(localized: "VARIACIÓN")] : [])
        return HStack {
            Text(first).frame(maxWidth: .infinity, alignment: .leading)
            if !stacksRows {
                // En una línea: si el título es más ancho que la columna («AL 31 OCT 2026»), la columna crece.
                ForEach(titles, id: \.self) {
                    Text($0).lineLimit(1).fixedSize().frame(minWidth: amountWidth(size), alignment: .trailing)
                }
                if showsVariation { Text("%").frame(minWidth: amountWidth(.percent), alignment: .trailing) }
            }
        }
        .font(.label)
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 16)
        .padding(.vertical, isCompact ? 10 : 14)
    }

    private func amountWidth(_ size: ColumnSize) -> CGFloat {
        // En iPhone los importes van sin «$», así que las columnas pueden ser más estrechas.
        if isCompact { return isNarrow ? columnWidth * 0.82 : columnWidth }
        return switch size {
        case .regular: wideColumnWidth
        case .percent: percentColumnWidth
        case .bucket: bucketColumnWidth
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [ReportRow], _ previous: [ReportRow]?, trend: Trend? = nil) -> some View {
        Text(title).font(isCompact ? .footnote.weight(.semibold) : .body.weight(.semibold)).foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, isCompact ? 10 : 20).padding(.bottom, isCompact ? 2 : 4)
        // Al comparar, también las cuentas que solo tuvieron importe en el periodo anterior (con 0 en el actual):
        // si no, el total anterior no cuadraba con las filas.
        let shown = rows + (previous ?? []).filter { old in !rows.contains { $0.account.id == old.account.id } }
            .map { ReportRow(account: $0.account, amount: 0) }
        ForEach(shown.sorted { ($0.account.code, $0.account.name) < ($1.account.code, $1.account.name) }) { row in
            line(row.account.name, row.amount, previous.map { list in list.first { $0.account.id == row.account.id }?.amount ?? 0 },
                 trend: trend, indent: true)
        }
        if shown.isEmpty { rowView(String(localized: "Sin movimientos"), [], indent: true).foregroundStyle(Palette.ink3) }
    }

    private func line(_ title: String, _ amount: Int64, _ previous: Int64?, trend: Trend? = nil, indent: Bool = false) -> some View {
        rowView(title, cells(amount, previous, trend: trend), indent: indent)
    }

    private func totalRow(_ title: String, _ amount: Int64, _ previous: Int64?, trend: Trend? = nil, highlighted: Bool = false) -> some View {
        VStack(spacing: 0) {
            Divider()
            rowView(title, cells(amount, previous, trend: trend), bold: true)
                // Banda a todo el ancho: con `.background(Color)` tomaba la forma redondeada de la tarjeta.
                .background { Rectangle().fill(highlighted ? Palette.brandWash : .clear) }
        }
    }

    /// Importe actual y, si se compara, el anterior; en pantallas anchas también la variación y el %.
    /// En iPhone, importes sin «$» (como en `ReportePyG`): así los nombres de cuenta caben en una línea.
    private func amountText(_ amount: Int64) -> String { isNarrow ? amount.amountOnly : amount.money }

    /// «sep», «T3» o «2025» para la insignia de la tarjeta destacada.
    private var previousShort: String {
        period == .month ? interval(offset: -1).start.shortMonth : previousName
    }

    /// Títulos de las columnas de importes del reporte abierto; con tamaños de accesibilidad acompañan a cada importe.
    private var columnLabels: [String] {
        switch kind {
        case .income: compare ? [columnTitle(offset: 0), columnTitle(offset: -1)] : []
        case .trial: [String(localized: "DEBE"), String(localized: "HABER")]
        case .receivables, .payables: [String(localized: "VENCIDO"), String(localized: "TOTAL")]
        case .balance, .salesTax: []
        }
    }

    private func cells(_ amount: Int64, _ previous: Int64?, trend: Trend?) -> [Cell] {
        guard compare, let previous else { return [Cell(text: amountText(amount))] }
        var cells = [Cell(text: amountText(amount)), Cell(text: amountText(previous), color: Palette.ink3)]
        if let trend, showsVariationColumns {
            let delta = amount - previous
            let tint = color(for: delta, trend)
            if showsDeltaColumn { cells.append(Cell(text: signedMoney(delta), color: tint)) }
            cells.append(Cell(text: percentChange(amount, previous) ?? "—", color: tint, size: .percent))
        }
        return cells
    }

    private func color(for delta: Int64, _ trend: Trend) -> Color {
        if delta == 0 { return Palette.ink3 }
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

    /// Con tamaños de accesibilidad los importes pasan debajo del nombre en vez de ir en columnas fijas.
    /// En pantallas anchas cada fila mide al menos 44 pt (34 en Mac).
    private func rowView(_ title: String, _ cells: [Cell], bold: Bool = false, indent: Bool = false) -> some View {
        let valueViews = ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
            Text(cell.text)
                .frame(minWidth: stacksRows ? nil : amountWidth(cell.size), alignment: .trailing)
                .foregroundStyle(cell.color)
        }
        return Group {
            if stacksRows {
                // Cada importe en su línea y con el título de su columna («OCT 1,800.00»): apilados sin
                // etiqueta no se sabía qué periodo era cada uno.
                let labels = columnLabels
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).padding(.leading, indent ? 8 : 0)
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        if !cell.text.isEmpty {
                            HStack(spacing: 6) {
                                if labels.count == cells.count {
                                    Text(labels[index]).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
                                }
                                Text(cell.text).foregroundStyle(cell.color)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(title).padding(.leading, indent ? (isCompact ? 8 : 18) : 0).frame(maxWidth: .infinity, alignment: .leading)
                    valueViews
                }
            }
        }
        .font(bold ? rowFont.weight(.semibold) : rowFont)
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: isCompact ? nil : wideRowHeight)
        .accessibilityElement(children: .combine)
    }

    private func balanceCheck(_ balanced: Bool, ok: String, bad: String) -> some View {
        Label(balanced ? ok : bad, systemImage: balanced ? "checkmark.circle" : "exclamationmark.triangle")
            .font(isCompact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(balanced ? Palette.positive : Palette.negative)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isCompact ? 14 : 16)
            .background(balanced ? Palette.positiveWash : Palette.negativeWash)
    }

    // MARK: Datos de los reportes

    private var balanceSheetReport: BalanceSheet {
        let fiscalStart = (try? Bookkeeper(context: context).fiscalYearStart(containing: asOf))
            ?? Calendar.current.dateInterval(of: .year, for: asOf)?.start
        return ReportBuilder.balanceSheet(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: endOfDay(asOf), fiscalYearStart: fiscalStart)
    }

    // Las listas de facturas y de facturas de proveedor se observan para que los reportes se actualicen solos.
    private var receivablesReport: AgingReport {
        _ = invoices.count
        return (try? Bookkeeper(context: context).receivablesAging(asOf: asOf)) ?? ReportBuilder.aging(items: [], asOf: asOf)
    }

    /// Último instante del día elegido: lo registrado ese día cuenta en el corte.
    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: date)) ?? date
    }

    private var salesTaxReport: SalesTaxSummary {
        _ = invoices.count
        let interval = isCompact ? interval() : Period.quarter.interval(offset: taxQuarter)
        return (try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1)))
            ?? ReportBuilder.salesTaxSummary(documents: [], from: interval.start, to: interval.end)
    }

    private var payablesReport: AgingReport {
        _ = bills.count
        return (try? Bookkeeper(context: context).payablesAging(asOf: asOf)) ?? ReportBuilder.aging(items: [], asOf: asOf)
    }

    // MARK: Exportar

    /// Cada tipo de reporte exporta su propio contenido (antes "Balance general" exportaba la balanza).
    private var csvFile: CSVFile {
        switch kind {
        case .income:
            CSVFile(name: String(localized: "Estado de resultados"),
                    text: CSVExport.incomeStatement(ledger.incomeStatement(interval()),
                                                    previous: compare ? ledger.incomeStatement(interval(offset: -1)) : nil))
        case .balance:
            CSVFile(name: String(localized: "Balance general"), text: CSVExport.balanceSheet(balanceSheetReport))
        case .trial:
            CSVFile(name: String(localized: "Balanza de comprobación"),
                    text: CSVExport.trialBalance(trialBalanceReport))
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

/// Casilla de verificación (`MacPyG`: «Comparar con periodo anterior»). En el Mac se usa la del sistema.
private struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(configuration).toggleStyle(.checkbox)
        #else
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Palette.brand : Palette.ink3)
                configuration.label.font(.subheadline)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("Activado") : Text("Desactivado"))
        #endif
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

#Preview {
    NavigationStack { ReportsView() }.modelContainer(SampleData.makeContainer())
}

/// Resumen de sales tax: ventas gravables, no gravables y exentas, e impuesto por tasa (DISEÑO §4.7).
struct SalesTaxSummaryCard: View {
    let report: SalesTaxSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            HeroCard(title: String(localized: "Sales tax cobrado"), value: report.totalTax.money,
                     detail: "\(report.from.shortDate) – \(report.to.shortDate)")
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ventas totales", value: report.totalSales.money).fontWeight(.semibold)
                LabeledContent("Gravables", value: report.taxableSales.money)
                LabeledContent("No gravables", value: report.nonTaxableSales.money)
                LabeledContent("Exentas (clientes exentos)", value: report.exemptSales.money)
            }
            .monospacedDigit()
            .card()
            SalesTaxRatesCard(report: report)
        }
    }
}

/// Impuesto cobrado por tasa (iPhone; en pantallas anchas es una tabla dentro de `ReportsView`).
struct SalesTaxRatesCard: View {
    let report: SalesTaxSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Por tasa").font(.cardTitle)
            if report.rows.isEmpty { Text("Sin impuesto cobrado en el periodo.").foregroundStyle(Palette.ink3) }
            ForEach(report.rows) { row in
                LabeledContent {
                    Text(row.tax.money).monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(row.name) · \(row.percent.formatted())%")
                        Text("sobre \(row.taxableSales.money)").font(.subheadline).foregroundStyle(Palette.ink3)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
