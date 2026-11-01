import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Reportes (canvas: `ReportePyG`, `MacPyG`). Todos se calculan con `ReportBuilder` a partir de las líneas contabilizadas.
struct ReportsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case income = "Resultados"
        case balance = "Balance general"
        case trial = "Balanza"
        case receivables = "Por cobrar"
        case payables = "Por pagar"
        case salesTax = "Sales tax"
        var id: String { rawValue }
    }

    enum Period: String, CaseIterable, Identifiable {
        case month = "Mes", quarter = "Trimestre", year = "Año"
        var id: String { rawValue }

        func interval(offset: Int = 0, calendar: Calendar = .current) -> DateInterval {
            let component: Calendar.Component = switch self { case .month: .month; case .quarter: .quarter; case .year: .year }
            let step = self == .quarter ? 3 : 1
            let date = calendar.date(byAdding: self == .quarter ? .month : component, value: offset * step, to: .now) ?? .now
            return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
        }
    }

    /// iPhone: una columna como en el canvas. iPad y Mac: el resumen va en fila encima de la tabla o, si hay ancho,
    /// en una columna a la izquierda de la tabla.
    private enum Layout { case compact, stacked, sideBySide }

    /// Una cifra del resumen de un reporte (total de ingresos, un tramo de antigüedad…).
    private struct Tile: Identifiable {
        let title: String
        let value: String
        var note: String? = nil
        var id: String { title }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .body) private var wideColumnWidth: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var wideRowHeight: CGFloat = Self.minimumRowHeight
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var invoices: [Invoice]
    @Query private var bills: [Bill]

    @State private var kind: Kind = .income
    @State private var period: Period = .month
    @State private var compare = true
    @State private var width: CGFloat = 0

    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }

    // MARK: Medidas

    #if os(macOS)
    private static let minimumRowHeight: CGFloat = 34
    #else
    private static let minimumRowHeight: CGFloat = 44
    #endif
    /// Ancho mínimo del contenido para poner el resumen al lado de la tabla.
    private static let sideBySideWidth: CGFloat = 1000
    private static let summaryColumnWidth: CGFloat = 320

    /// Ancho de iPhone (o de iPad en Split View estrecho).
    private var isNarrow: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    /// Una sola columna, como en iPhone: en pantallas estrechas y con tamaños de accesibilidad.
    private var isCompact: Bool { isNarrow || dynamicTypeSize.isAccessibilitySize }

    private var layout: Layout {
        if isCompact { return .compact }
        return width - 2 * margin >= Self.sideBySideWidth ? .sideBySide : .stacked
    }

    /// En pantallas anchas el margen coincide con el del título grande, para que el reporte empiece donde empieza «Reportes».
    private var margin: CGFloat { isNarrow ? Metrics.gutter : 20 }
    private var maxContentWidth: CGFloat {
        switch layout {
        case .compact: isNarrow ? 900 : 1240
        case .stacked: 1000
        case .sideBySide: 1240
        }
    }
    private var amountColumnWidth: CGFloat { isCompact ? columnWidth : wideColumnWidth }
    private var rowFont: Font { isCompact ? .subheadline : .body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? Metrics.cardSpacing : 16) {
                kindChips
                if kind == .income || kind == .salesTax { periodControls }
                switch kind {
                case .income: incomeStatement
                case .balance: balanceSheet
                case .trial: trialBalance
                case .receivables: aging(receivablesReport, total: String(localized: "Total por cobrar"), empty: String(localized: "No hay facturas pendientes de cobro."))
                case .payables: aging(payablesReport, total: String(localized: "Total por pagar"), empty: String(localized: "No hay facturas de proveedores pendientes."))
                case .salesTax: salesTax
                }
            }
            .padding(.horizontal, margin)
            .padding(.vertical, Metrics.gutter)
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Reportes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: csvFile, preview: SharePreview("\(csvFile.name).csv")) {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Kind.allCases) { option in
                    FilterChip(title: option.localizedTitle, isSelected: kind == option) { kind = option }
                }
            }
        }
    }

    private var periodControls: some View {
        HStack {
            Picker("Periodo", selection: $period) {
                ForEach(Period.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            if kind == .income { Toggle("Comparar", isOn: $compare).fixedSize() }
        }
        .controlSize(isNarrow ? .regular : .large)
        .font(isCompact ? nil : .body)
    }

    // MARK: Resumen y tabla

    /// Coloca el resumen (tarjeta destacada y cifras) y la tabla según el ancho disponible. En iPhone sólo se
    /// muestran las cifras de los reportes que ya las tenían (`tilesWhenCompact`).
    @ViewBuilder
    private func report<Detail: View>(hero: HeroCard? = nil, tiles: [Tile], tilesWhenCompact: Bool = false,
                                      @ViewBuilder detail: () -> Detail) -> some View {
        switch layout {
        case .compact:
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                hero
                if tilesWhenCompact {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(tiles) { KPITile(title: $0.title, value: $0.value, note: $0.note) }
                    }
                }
                detail()
            }
        case .stacked:
            VStack(spacing: 12) {
                if let hero { HeroCard(title: hero.title, value: hero.value, detail: hero.detail, prominent: true) }
                tileGrid(tiles, columns: tiles.count)
                    .fixedSize(horizontal: false, vertical: true)
                detail().padding(.top, 4)
            }
        case .sideBySide:
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    if let hero { HeroCard(title: hero.title, value: hero.value, detail: hero.detail, prominent: true) }
                    tileGrid(tiles, columns: tiles.count == 3 ? 1 : 2)
                }
                // Alto natural: sin esto la columna se estira hasta el alto de la tabla.
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.summaryColumnWidth)
                detail().frame(maxWidth: .infinity)
            }
        }
    }

    private func tileGrid(_ tiles: [Tile], columns: Int) -> some View {
        let count = max(columns, 1)
        let rows = stride(from: 0, to: tiles.count, by: count).map { Array(tiles[$0..<min($0 + count, tiles.count)]) }
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { SummaryTile(title: $0.title, value: $0.value, note: $0.note) }
                }
            }
        }
    }

    // MARK: Estado de resultados

    private var incomeStatement: some View {
        let current = ledger.incomeStatement(period.interval())
        let previous = ledger.incomeStatement(period.interval(offset: -1))
        let note: (Int64) -> String? = { compare ? String(localized: "Anterior: \($0.money)") : nil }
        return report(
            hero: HeroCard(title: String(localized: "Ganancia neta"), value: current.netIncome.money,
                           detail: String(localized: "\(period.interval().start.shortDate) – \(period.interval().end.addingTimeInterval(-1).shortDate)")),
            tiles: [Tile(title: String(localized: "Total ingresos"), value: current.totalIncome.money, note: note(previous.totalIncome)),
                    Tile(title: String(localized: "Utilidad bruta"), value: current.grossProfit.money, note: note(previous.grossProfit)),
                    Tile(title: String(localized: "Total gastos"), value: current.totalExpenses.money, note: note(previous.totalExpenses))]
        ) {
            VStack(spacing: 0) {
                header(columns: compare ? [String(localized: "ACTUAL"), String(localized: "ANTERIOR")] : [String(localized: "ACTUAL")])
                group(String(localized: "Ingresos"), current.income, previous.income)
                totalRow(String(localized: "Total ingresos"), current.totalIncome, previous.totalIncome)
                group(String(localized: "Costo de ventas"), current.costOfGoodsSold, previous.costOfGoodsSold)
                totalRow(String(localized: "Utilidad bruta"), current.grossProfit, previous.grossProfit)
                group(String(localized: "Gastos operativos"), current.expenses, previous.expenses)
                totalRow(String(localized: "Total gastos"), current.totalExpenses, previous.totalExpenses)
                totalRow(String(localized: "Ganancia neta"), current.netIncome, previous.netIncome, highlighted: true)
            }
            .card(padding: 0)
        }
    }

    // MARK: Balance general

    private var balanceSheet: some View {
        let report = balanceSheetReport
        return self.report(tiles: [Tile(title: String(localized: "Total activos"), value: report.totalAssets.money),
                                   Tile(title: String(localized: "Total pasivos"), value: report.totalLiabilities.money),
                                   Tile(title: String(localized: "Total patrimonio"), value: report.totalEquity.money)]) {
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
        return self.report(tiles: [Tile(title: String(localized: "Total debe"), value: report.totalDebit.money),
                                   Tile(title: String(localized: "Total haber"), value: report.totalCredit.money)]) {
            VStack(spacing: 0) {
                header(columns: [String(localized: "DEBE"), String(localized: "HABER")])
                ForEach(report.rows) { row in
                    rowView(row.account.name, [row.debit == 0 ? "" : row.debit.money, row.credit == 0 ? "" : row.credit.money])
                }
                Divider()
                rowView(String(localized: "Totales"), [report.totalDebit.money, report.totalCredit.money], bold: true)
                balanceCheck(report.isBalanced, ok: String(localized: "Débitos = créditos"), bad: String(localized: "La balanza no cuadra"))
            }
            .card(padding: 0)
        }
    }

    // MARK: Antigüedad de cuentas por cobrar y por pagar

    private func aging(_ report: AgingReport, total: String, empty: String) -> some View {
        let titles: [AgingReport.Bucket: String] = [.current: String(localized: "Corriente"), .days1to30: "1–30", .days31to60: "31–60", .days61to90: "61–90", .over90: "> 90"]
        return self.report(tiles: AgingReport.Bucket.allCases.map { Tile(title: titles[$0]!, value: report.total(for: $0).money) },
                           tilesWhenCompact: true) {
            VStack(spacing: 0) {
                header(columns: [String(localized: "VENCIDO"), String(localized: "TOTAL")])
                ForEach(report.rows) { row in
                    let overdue = row.total - (row.amounts[.current] ?? 0)
                    rowView(row.party, [overdue.money, row.total.money])
                }
                if report.rows.isEmpty { Text(empty).foregroundStyle(Palette.ink3).padding() }
                Divider()
                rowView(total, ["", report.total.money], bold: true)
            }
            .card(padding: 0)
        }
    }

    // MARK: Sales tax

    @ViewBuilder
    private var salesTax: some View {
        let summary = salesTaxReport
        if layout == .compact {
            SalesTaxSummaryCard(report: summary)
        } else {
            report(hero: HeroCard(title: String(localized: "Sales tax cobrado"), value: summary.totalTax.money,
                                  detail: "\(summary.from.shortDate) – \(summary.to.shortDate)"),
                   tiles: [Tile(title: String(localized: "Ventas totales"), value: summary.totalSales.money),
                           Tile(title: String(localized: "Gravables"), value: summary.taxableSales.money),
                           Tile(title: String(localized: "No gravables"), value: summary.nonTaxableSales.money),
                           Tile(title: String(localized: "Exentas (clientes exentos)"), value: summary.exemptSales.money)]) {
                SalesTaxRatesCard(report: summary, wide: true)
            }
        }
    }

    // MARK: Filas

    private func header(columns: [String]) -> some View {
        HStack {
            Text("CUENTA").frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                // En una línea: si el título es más ancho que la columna («AL 31 OCT 2026»), la columna crece.
                ForEach(columns, id: \.self) {
                    Text($0).lineLimit(1).fixedSize().frame(minWidth: amountColumnWidth, alignment: .trailing)
                }
            }
        }
        .font(.label)
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 16)
        .padding(.vertical, isCompact ? 10 : 14)
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [ReportRow], _ previous: [ReportRow]?) -> some View {
        Text(title).font(isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold)).foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, isCompact ? 10 : 20).padding(.bottom, isCompact ? 2 : 4)
        ForEach(rows) { row in
            line(row.account.name, row.amount, previous.map { list in list.first { $0.account.id == row.account.id }?.amount ?? 0 }, indent: true)
        }
        if rows.isEmpty { line(String(localized: "Sin movimientos"), 0, nil, indent: true).foregroundStyle(Palette.ink3) }
    }

    private func line(_ title: String, _ amount: Int64, _ previous: Int64?, indent: Bool = false) -> some View {
        rowView(title, compare && previous != nil ? [amount.money, previous!.money] : [amount.money], indent: indent)
    }

    private func totalRow(_ title: String, _ amount: Int64, _ previous: Int64?, highlighted: Bool = false) -> some View {
        VStack(spacing: 0) {
            Divider()
            rowView(title, compare && previous != nil ? [amount.money, previous!.money] : [amount.money], bold: true)
                .background(highlighted ? Palette.brandWash : .clear)
        }
    }

    /// Con tamaños de accesibilidad los importes pasan debajo del nombre en vez de ir en columnas fijas.
    /// En pantallas anchas cada fila mide al menos 44 pt (34 en Mac).
    private func rowView(_ title: String, _ values: [String], bold: Bool = false, indent: Bool = false) -> some View {
        let valueViews = ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            Text(value)
                .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : amountColumnWidth, alignment: .trailing)
                .foregroundStyle(index == 0 ? Palette.ink : Palette.ink3)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).padding(.leading, indent ? 8 : 0)
                    HStack(spacing: 16) { valueViews }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(title).padding(.leading, indent ? 8 : 0).frame(maxWidth: .infinity, alignment: .leading)
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
        let interval = period.interval()
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
                    text: CSVExport.incomeStatement(ledger.incomeStatement(period.interval()),
                                                    previous: compare ? ledger.incomeStatement(period.interval(offset: -1)) : nil))
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

/// Impuesto cobrado por tasa. En pantallas anchas (`wide`) cada tasa ocupa una fila de 44 pt o más.
struct SalesTaxRatesCard: View {
    let report: SalesTaxSummary
    var wide = false
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 0 : 8) {
            Text("Por tasa").font(.cardTitle).padding(.bottom, wide ? 8 : 0)
            if report.rows.isEmpty { Text("Sin impuesto cobrado en el periodo.").foregroundStyle(Palette.ink3) }
            ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                if wide && index > 0 { Divider() }
                LabeledContent {
                    Text(row.tax.money).monospacedDigit()
                } label: {
                    Text("\(row.name) · \(row.percent.formatted())%")
                    Text("sobre \(row.taxableSales.money)")
                }
                .frame(minHeight: wide ? rowHeight : nil)
                .padding(.vertical, wide ? 6 : 0)
                .accessibilityElement(children: .combine)
            }
        }
        .font(wide ? .body : nil)
        .card(padding: wide ? 20 : Metrics.cardPadding)
    }
}

/// Cifra del resumen de un reporte en iPad y Mac: como `KPITile`, pero ocupa todo el alto de su fila para
/// quedar a la par de la tarjeta destacada.
struct SummaryTile: View {
    let title: String
    let value: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink3)
            Text(value).font(.amount(22)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            if let note { Text(note).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, note].compactMap { $0 }.joined(separator: ", "))
    }
}
