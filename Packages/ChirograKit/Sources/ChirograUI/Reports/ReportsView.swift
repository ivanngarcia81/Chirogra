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
    @Environment(\.horizontalSizeClass) private var sizeClass
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

    @State private var selectedKind: Kind = .income
    @State private var period: Period = .month
    @State private var compare = true
    @State private var customStart = Period.month.interval().start
    @State private var customEnd = Period.month.interval().end.addingTimeInterval(-1)
    @State private var editingRange = false
    @State private var width: CGFloat = 0

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
    private var showsVariationColumns: Bool { !isCompact && width - 2 * margin >= 760 }

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
                if kind == .income || kind == .salesTax { periodControls }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                #if os(macOS)
                Text(kind.fullTitle).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ink)
                #endif
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            ShareLink(item: csvFile, preview: SharePreview("\(csvFile.name).csv")) {
                Text("Exportar CSV")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        let company = companies.first
        let name = company.map { $0.displayName.isEmpty ? $0.legalName : $0.displayName } ?? ""
        return String(localized: "\(name) · base devengado · \(company?.currencyCode ?? "USD")")
    }

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
            // En un iPhone de 402 pt el segmentado y «Comparar» no caben juntos: «Comparar» baja a su línea.
            ViewThatFits(in: .horizontal) {
                HStack {
                    periodPicker(Period.allCases.filter { $0 != .custom })
                    Spacer()
                    if kind == .income { Toggle("Comparar", isOn: $compare).fixedSize() }
                }
                VStack(alignment: .leading, spacing: 8) {
                    periodPicker(Period.allCases.filter { $0 != .custom })
                    if kind == .income { Toggle("Comparar con periodo anterior", isOn: $compare) }
                }
            }
        } else {
            // `MacPyG`: segmentado con «Personalizado», botón con el rango y casilla «Comparar con periodo anterior».
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { periodPicker(Period.allCases); rangeButton; compareBox }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) { periodPicker(Period.allCases); rangeButton }
                    compareBox
                }
            }
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
        return (current.start..<current.end.addingTimeInterval(-1)).formatted(.interval.day().month(.abbreviated).year())
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
        let year = start.formatted(.dateTime.year())
        switch period {
        // Tres letras como en el canvas («SEP 2026»; la abreviatura del sistema en español es «sept»).
        case .month: return "\(start.formatted(.dateTime.month(.wide)).prefix(3).uppercased()) \(year)"
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
                         detail: String(localized: "\(interval().start.shortDate) – \(interval().end.addingTimeInterval(-1).shortDate)"))
            } else {
                KPIGrid(items: incomeKPIs(current, previous))
            }
            VStack(spacing: 0) {
                header(columns: compare ? [columnTitle(offset: 0), columnTitle(offset: -1)] : [columnTitle(offset: 0)], variation: compare)
                group(String(localized: "Ingresos"), current.income, previous.income, trend: .upIsGood)
                totalRow(String(localized: "Total ingresos"), current.totalIncome, previous.totalIncome, trend: .upIsGood)
                group(String(localized: "Costo de ventas"), current.costOfGoodsSold, previous.costOfGoodsSold, trend: .downIsGood)
                totalRow(String(localized: "Total costo de ventas"), current.totalCostOfGoodsSold, previous.totalCostOfGoodsSold, trend: .downIsGood)
                totalRow(String(localized: "Utilidad bruta"), current.grossProfit, previous.grossProfit, trend: .upIsGood)
                group(String(localized: "Gastos operativos"), current.expenses, previous.expenses, trend: .downIsGood)
                totalRow(String(localized: "Total gastos operativos"), current.totalExpenses, previous.totalExpenses, trend: .downIsGood)
                totalRow(String(localized: "Ganancia neta"), current.netIncome, previous.netIncome, trend: .upIsGood, highlighted: true)
            }
            .card(padding: 0)
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

    private var balanceSheet: some View {
        let report = balanceSheetReport
        return VStack(spacing: 16) {
            if !isCompact {
                KPIGrid(items: [KPIItem(title: String(localized: "Total activos"), value: report.totalAssets.money),
                         KPIItem(title: String(localized: "Total pasivos"), value: report.totalLiabilities.money),
                         KPIItem(title: String(localized: "Total patrimonio"), value: report.totalEquity.money)])
            }
            VStack(spacing: 0) {
                header(columns: [String(localized: "AL \(Date.now.shortDate.uppercased())")])
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
        }
    }

    // MARK: Balanza de comprobación

    private var trialBalance: some View {
        let report = ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now)
        return VStack(spacing: 16) {
            if !isCompact {
                KPIGrid(items: [KPIItem(title: String(localized: "Total debe"), value: report.totalDebit.money),
                         KPIItem(title: String(localized: "Total haber"), value: report.totalCredit.money)])
            }
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
                KPIGrid(items: AgingReport.Bucket.allCases.map { KPIItem(title: titles[$0]!, value: report.total(for: $0).money) })
            }
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
        }
    }

    // MARK: Sales tax

    @ViewBuilder
    private var salesTax: some View {
        let summary = salesTaxReport
        if isCompact {
            SalesTaxSummaryCard(report: summary)
        } else {
            VStack(spacing: 16) {
                KPIGrid(items: [KPIItem(title: String(localized: "Sales tax cobrado"), value: summary.totalTax.money, isBrand: true),
                         KPIItem(title: String(localized: "Ventas totales"), value: summary.totalSales.money),
                         KPIItem(title: String(localized: "Gravables"), value: summary.taxableSales.money),
                         KPIItem(title: String(localized: "No gravables"), value: summary.nonTaxableSales.money),
                         KPIItem(title: String(localized: "Exentas (clientes exentos)"), value: summary.exemptSales.money)])
                // «Por tasa» con el mismo estilo de tabla que el resto de reportes: TASA · BASE · IMPUESTO.
                VStack(spacing: 0) {
                    header(String(localized: "TASA"), columns: [String(localized: "BASE"), String(localized: "IMPUESTO")])
                    ForEach(summary.rows) { row in
                        rowView("\(row.name) · \(row.percent.formatted())%", [Cell(text: row.taxableSales.money), Cell(text: row.tax.money)])
                    }
                    if summary.rows.isEmpty {
                        Text("Sin impuesto cobrado en el periodo.").foregroundStyle(Palette.ink3).padding()
                    }
                    Divider()
                    rowView(String(localized: "Total"), [Cell(text: ""), Cell(text: summary.totalTax.money)], bold: true)
                }
                .card(padding: 0)
            }
        }
    }

    // MARK: Filas

    /// `variation`: añade «VARIACIÓN» y «%» (sólo en pantallas anchas, como en `MacPyG`).
    private func header(_ first: String = String(localized: "CUENTA"), columns: [String], size: ColumnSize = .regular,
                        variation: Bool = false) -> some View {
        let showsVariation = variation && showsVariationColumns
        let titles = columns + (showsVariation ? [String(localized: "VARIACIÓN")] : [])
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
        if isCompact { return columnWidth }
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
        ForEach(rows) { row in
            line(row.account.name, row.amount, previous.map { list in list.first { $0.account.id == row.account.id }?.amount ?? 0 },
                 trend: trend, indent: true)
        }
        if rows.isEmpty { rowView(String(localized: "Sin movimientos"), [], indent: true).foregroundStyle(Palette.ink3) }
    }

    private func line(_ title: String, _ amount: Int64, _ previous: Int64?, trend: Trend? = nil, indent: Bool = false) -> some View {
        rowView(title, cells(amount, previous, trend: trend), indent: indent)
    }

    private func totalRow(_ title: String, _ amount: Int64, _ previous: Int64?, trend: Trend? = nil, highlighted: Bool = false) -> some View {
        VStack(spacing: 0) {
            Divider()
            rowView(title, cells(amount, previous, trend: trend), bold: true)
                .background(highlighted ? Palette.brandWash : .clear)
        }
    }

    /// Importe actual y, si se compara, el anterior; en pantallas anchas también la variación y el %.
    private func cells(_ amount: Int64, _ previous: Int64?, trend: Trend?) -> [Cell] {
        guard compare, let previous else { return [Cell(text: amount.money)] }
        var cells = [Cell(text: amount.money), Cell(text: previous.money, color: Palette.ink3)]
        if let trend, showsVariationColumns {
            let delta = amount - previous
            let tint = color(for: delta, trend)
            cells.append(Cell(text: signedMoney(delta), color: tint))
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).padding(.leading, indent ? 8 : 0)
                    HStack(spacing: 16) { valueViews }
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
        let fiscalStart = (try? Bookkeeper(context: context).fiscalYearStart(containing: .now))
            ?? Calendar.current.dateInterval(of: .year, for: .now)?.start
        return ReportBuilder.balanceSheet(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now, fiscalYearStart: fiscalStart)
    }

    // Las listas de facturas y de facturas de proveedor se observan para que los reportes se actualicen solos.
    private var receivablesReport: AgingReport {
        _ = invoices.count
        return (try? Bookkeeper(context: context).receivablesAging()) ?? ReportBuilder.aging(items: [], asOf: .now)
    }

    private var salesTaxReport: SalesTaxSummary {
        _ = invoices.count
        let interval = interval()
        return (try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1)))
            ?? ReportBuilder.salesTaxSummary(documents: [], from: interval.start, to: interval.end)
    }

    private var payablesReport: AgingReport {
        _ = bills.count
        return (try? Bookkeeper(context: context).payablesAging()) ?? ReportBuilder.aging(items: [], asOf: .now)
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
                    text: CSVExport.trialBalance(ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now)))
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
