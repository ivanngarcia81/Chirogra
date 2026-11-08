import ChirograCore
import ChirograData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - PDF de los reportes (fase 2)
//
// Un reporte se pasa a `ReportDocument` (título, periodo, columnas y filas ya con su texto) y `ReportPDF` lo dibuja en
// páginas tamaño carta con SwiftUI (`ImageRenderer`, como el PDF de la factura), en claro y con la letra fija: no
// depende de la pantalla ni del tamaño de letra del aparato. El paquete del contador junta varios en un solo PDF con
// una portada.

/// Un reporte listo para imprimir.
struct ReportDocument: Identifiable, Sendable {
    struct Row: Identifiable, Sendable {
        enum Style { case heading, line, total, grand, note, spacer }
        var label: String
        var values: [String] = []
        var style: Style = .line
        /// Sangría en niveles (cuentas dentro de su sección).
        var indent = 0
        /// Colores de las cifras en el PDF: solo para la diferencia del presupuesto (con su signo, no solo color).
        var valueColors: [Color]? = nil
        let id = UUID()
    }

    var title: String
    /// «1 ene – 31 dic 2026 · base caja · USD».
    var subtitle: String
    /// Títulos de las columnas de cifras (la primera columna, la del concepto, no lleva título).
    var columns: [String]
    var rows: [Row]
    /// Pie del reporte (avisos como el de los deducibles).
    var footnote: String? = nil
    let id = UUID()
}

enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 48
    /// Filas que caben en una página debajo de la cabecera (15 pt cada una).
    static let rowsPerPage = 38

    /// Las páginas de un reporte: cada una con su trozo de filas (al menos una página, aunque no tenga filas).
    static func pages(for document: ReportDocument) -> [[ReportDocument.Row]] {
        var pages: [[ReportDocument.Row]] = []
        var current: [ReportDocument.Row] = []
        for row in document.rows {
            if current.count >= rowsPerPage {
                pages.append(current)
                current = []
            }
            // Un encabezado no se queda solo al pie de una página.
            if row.style == .heading, current.count >= rowsPerPage - 2, !current.isEmpty {
                pages.append(current)
                current = []
            }
            if current.isEmpty && row.style == .spacer { continue }
            current.append(row)
        }
        if !current.isEmpty || pages.isEmpty { pages.append(current) }
        return pages
    }

    /// PDF de uno o varios reportes; `cover` añade una portada delante (el paquete del contador).
    @MainActor
    static func render(_ documents: [ReportDocument], companyName: String, cover: ReportCover? = nil) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let paged = documents.map { ($0, pages(for: $0)) }
        let total = paged.reduce(cover == nil ? 0 : 1) { $0 + $1.1.count }
        var number = 0
        func draw(_ page: some View) {
            number += 1
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height)
                .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, render in
                pdf.beginPDFPage(nil)
                render(pdf)
                pdf.endPDFPage()
            }
        }
        if let cover {
            draw(ReportCoverPage(cover: cover, companyName: companyName))
        }
        for (document, pages) in paged {
            for (index, rows) in pages.enumerated() {
                draw(ReportPDFPage(document: document, companyName: companyName, rows: rows, isFirst: index == 0,
                                   isLast: index == pages.count - 1, pageNumber: number + 1, pageCount: total))
            }
        }
        pdf.closePDF()
        return data as Data
    }
}

/// Portada del paquete: empresa, periodo, base, contenido y el aviso.
struct ReportCover {
    var title: String
    var period: String
    var basis: String
    var contents: [String]
    var note: String
}

private struct ReportCoverPage: View {
    let cover: ReportCover
    let companyName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(companyName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(cover.title).font(.system(size: 26, weight: .bold))
            Text("\(cover.period) · \(cover.basis)").font(.system(size: 13))
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 0.5).padding(.vertical, 6)
            Text("Contenido").font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(cover.contents.enumerated()), id: \.offset) { _, item in
                    Text(verbatim: "•  \(item)").font(.system(size: 11))
                }
            }
            Spacer()
            Text(cover.note).font(.system(size: 9.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Preparado con Chirogra · \(Date.now.shortDate)").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.black)
        .padding(ReportPDF.margin)
        .frame(width: ReportPDF.pageSize.width, height: ReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }
}

/// Una página: cabecera centrada como el documento del Mac (`MacPyG`), columnas y filas, pie con la página.
private struct ReportPDFPage: View {
    let document: ReportDocument
    let companyName: String
    let rows: [ReportDocument.Row]
    let isFirst: Bool
    let isLast: Bool
    let pageNumber: Int
    let pageCount: Int

    private var amountWidth: CGFloat {
        switch document.columns.count {
        case 0, 1, 2: 104
        case 3: 92
        default: 74
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                Text(companyName).font(.system(size: 11, weight: .semibold))
                Text(isFirst ? document.title : String(localized: "\(document.title) (continuación)")).font(.system(size: 15, weight: .bold))
                Text(document.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
            HStack(spacing: 0) {
                Text(verbatim: "").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(document.columns.enumerated()), id: \.offset) { _, title in
                    Text(title).lineLimit(1).frame(width: amountWidth, alignment: .trailing)
                }
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            .frame(height: 18)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.25)).frame(height: 0.5) }
            ForEach(rows) { row in line(row) }
            if isLast, let footnote = document.footnote {
                Text(footnote).font(.system(size: 8.5)).foregroundStyle(.secondary).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: "Chirogra")
                Spacer()
                Text("Página \(pageNumber) de \(pageCount)")
            }
            .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .foregroundStyle(.black)
        .padding(ReportPDF.margin)
        .frame(width: ReportPDF.pageSize.width, height: ReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }

    @ViewBuilder
    private func line(_ row: ReportDocument.Row) -> some View {
        let weight: Font.Weight = switch row.style {
        case .heading, .total: .semibold
        case .grand: .bold
        default: .regular
        }
        switch row.style {
        case .spacer:
            Color.clear.frame(height: 15)
        case .note:
            Text(row.label).font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 15, alignment: .leading)
        default:
            HStack(spacing: 0) {
                Text(row.label).lineLimit(1).truncationMode(.tail)
                    .padding(.leading, CGFloat(row.indent) * 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                    Text(value).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(row.valueColors.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? .black)
                        .frame(width: amountWidth, alignment: .trailing)
                        .overlay(alignment: .top) {
                            if (row.style == .total || row.style == .grand) && !value.isEmpty {
                                Rectangle().fill(Color.black.opacity(0.4)).frame(height: 0.5).padding(.leading, 12)
                            }
                        }
                }
            }
            .font(.system(size: 10, weight: weight))
            .frame(height: 15)
        }
    }
}

/// PDF de uno o varios reportes para compartir: se dibuja al compartirlo, no cada vez que se dibuja la pantalla.
struct LazyReportPDF: Transferable, Sendable {
    let name: String
    let documents: [ReportDocument]
    let companyName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in
            await MainActor.run { ReportPDF.render(file.documents, companyName: file.companyName) }
        }
        .suggestedFileName { "\($0.name).pdf" }
    }
}

// MARK: - Cada reporte como documento

extension ReportDocument {
    private static func rows(_ rows: [ReportRow], indent: Int = 1, values: (ReportRow) -> [String]) -> [Row] {
        rows.sorted { ($0.account.code, $0.account.name) < ($1.account.code, $1.account.name) }
            .map { Row(label: "\($0.account.code) · \($0.account.name)", values: values($0), indent: indent) }
    }

    static func incomeStatement(_ current: IncomeStatement, previous: IncomeStatement? = nil, columns: [String], subtitle: String) -> ReportDocument {
        func amounts(_ now: Int64, _ before: Int64?) -> [String] { [now.money] + (before.map { [$0.money] } ?? []) }
        func section(_ title: String, _ list: [ReportRow], _ old: [ReportRow]?, total: String, _ now: Int64, _ before: Int64?) -> [Row] {
            let shown = list + (old ?? []).filter { row in !list.contains { $0.account.id == row.account.id } }.map { ReportRow(account: $0.account, amount: 0) }
            return [Row(label: title, style: .heading)]
                + rows(shown) { row in amounts(row.amount, old.map { $0.first { $0.account.id == row.account.id }?.amount ?? 0 }) }
                + [Row(label: total, values: amounts(now, before), style: .total), Row(label: "", style: .spacer)]
        }
        var list: [Row] = []
        list += section(String(localized: "Ingresos"), current.income, previous?.income, total: String(localized: "Total ingresos"),
                        current.totalIncome, previous?.totalIncome)
        list += section(String(localized: "Costo de ventas"), current.costOfGoodsSold, previous?.costOfGoodsSold,
                        total: String(localized: "Total costo de ventas"), current.totalCostOfGoodsSold, previous?.totalCostOfGoodsSold)
        list.append(Row(label: String(localized: "Utilidad bruta"), values: amounts(current.grossProfit, previous?.grossProfit), style: .total))
        list.append(Row(label: "", style: .spacer))
        list += section(String(localized: "Gastos operativos"), current.expenses, previous?.expenses,
                        total: String(localized: "Total gastos operativos"), current.totalExpenses, previous?.totalExpenses)
        list.append(Row(label: String(localized: "Ganancia neta"), values: amounts(current.netIncome, previous?.netIncome), style: .grand))
        return ReportDocument(title: String(localized: "Estado de resultados"), subtitle: subtitle, columns: columns, rows: list)
    }

    static func balanceSheet(_ report: BalanceSheet, subtitle: String) -> ReportDocument {
        var list: [Row] = [Row(label: String(localized: "Activos"), style: .heading)]
        list += rows(report.assets) { [$0.amount.money] }
        list.append(Row(label: String(localized: "Total activos"), values: [report.totalAssets.money], style: .total))
        list += [Row(label: "", style: .spacer), Row(label: String(localized: "Pasivos"), style: .heading)]
        list += rows(report.liabilities) { [$0.amount.money] }
        list.append(Row(label: String(localized: "Total pasivos"), values: [report.totalLiabilities.money], style: .total))
        list += [Row(label: "", style: .spacer), Row(label: String(localized: "Patrimonio"), style: .heading)]
        list += rows(report.equity) { [$0.amount.money] }
        list.append(Row(label: String(localized: "Resultados de años anteriores"), values: [report.priorYearsEarnings.money], indent: 1))
        list.append(Row(label: String(localized: "Resultado del ejercicio"), values: [report.currentYearEarnings.money], indent: 1))
        list.append(Row(label: String(localized: "Total patrimonio"), values: [report.totalEquity.money], style: .total))
        list.append(Row(label: "", style: .spacer))
        list.append(Row(label: String(localized: "Pasivo + patrimonio"), values: [(report.totalLiabilities + report.totalEquity).money], style: .grand))
        return ReportDocument(title: String(localized: "Balance general"), subtitle: subtitle, columns: [report.asOf.shortDate], rows: list)
    }

    static func trialBalance(_ report: TrialBalance, subtitle: String) -> ReportDocument {
        var list = report.rows.map { row in
            Row(label: "\(row.account.code) · \(row.account.name)", values: [row.debit == 0 ? "" : row.debit.money, row.credit == 0 ? "" : row.credit.money])
        }
        list.append(Row(label: String(localized: "Totales"), values: [report.totalDebit.money, report.totalCredit.money], style: .grand))
        return ReportDocument(title: String(localized: "Balanza de comprobación"), subtitle: subtitle,
                              columns: [String(localized: "Débito"), String(localized: "Crédito")], rows: list)
    }

    static func cashFlow(_ report: CashFlowStatement, previous: CashFlowStatement? = nil, columns: [String], subtitle: String) -> ReportDocument {
        var list: [Row] = []
        for section in CashFlowLayout.sections(report, previous: previous) {
            if let title = section.title { list.append(Row(label: title, style: .heading)) }
            for line in section.lines {
                var values = [line.amount.money]
                if let before = line.previous { values.append(before.money) }
                let style: Row.Style = switch line.style { case .line: .line; case .total: .total; case .grand: .grand }
                list.append(Row(label: line.name, values: values, style: style, indent: line.style == .line && section.title != nil ? 1 : 0))
            }
            list.append(Row(label: "", style: .spacer))
        }
        return ReportDocument(title: String(localized: "Flujo de efectivo"), subtitle: subtitle, columns: columns, rows: list)
    }

    static func taxSummary(_ report: TaxFormSummary, subtitle: String, locale: Locale = .appText) -> ReportDocument {
        var list: [Row] = []
        for kind in [TaxFormLine.Kind.income, .deduction] {
            let lines = report.rows.filter { $0.line.kind == kind }
            guard !lines.isEmpty else { continue }
            list.append(Row(label: kind == .income ? String(localized: "Ingresos") : String(localized: "Deducciones"), style: .heading))
            for row in lines {
                list.append(Row(label: row.line.label(for: locale),
                                values: [row.amount.money, kind == .income ? "" : row.deductibleAmount.money], style: .total))
                list += row.accounts.map { Row(label: "\($0.account.code) · \($0.account.name)", values: [$0.amount.money, ""], indent: 1) }
            }
            list.append(Row(label: "", style: .spacer))
        }
        list.append(Row(label: String(localized: "Total de ingresos"), values: [report.totalIncome.money, ""], style: .total))
        list.append(Row(label: String(localized: "Total deducible"), values: ["", report.totalDeductions.money], style: .grand))
        if !report.excluded.isEmpty {
            list += [Row(label: "", style: .spacer), Row(label: String(localized: "Cuentas excluidas"), style: .heading)]
            list += report.excluded.map { Row(label: "\($0.account.code) · \($0.account.name)", values: [$0.amount.money, ""], indent: 1) }
        }
        return ReportDocument(title: String(localized: "Deducibles · \(report.form.title)"), subtitle: subtitle,
                              columns: [String(localized: "Importe"), String(localized: "Deducible")], rows: list,
                              footnote: DeductionsText.disclaimer)
    }
}
