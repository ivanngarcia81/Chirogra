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
        case aging = "Antigüedad"
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

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query private var invoices: [Invoice]

    @State private var kind: Kind = .income
    @State private var period: Period = .month
    @State private var compare = true

    private var ledger: Ledger { Ledger(accounts: accounts, lines: journalLines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                kindChips
                if kind == .income {
                    HStack {
                        Picker("Periodo", selection: $period) {
                            ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Spacer()
                        Toggle("Comparar", isOn: $compare).fixedSize()
                    }
                }
                switch kind {
                case .income: incomeStatement
                case .balance: balanceSheet
                case .trial: trialBalance
                case .aging: aging
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .navigationTitle("Reportes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: csv, preview: SharePreview("\(kind.rawValue).csv")) {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Kind.allCases) { option in
                    Button(option.rawValue) { kind = option }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(kind == option ? Palette.background : Palette.ink2)
                        .background(kind == option ? Palette.ink : Palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(kind == option ? Palette.ink : Palette.separator))
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Estado de resultados

    private var incomeStatement: some View {
        let current = ledger.incomeStatement(period.interval())
        let previous = ledger.incomeStatement(period.interval(offset: -1))
        return VStack(spacing: Metrics.cardSpacing) {
            HeroCard(title: "Ganancia neta", value: current.netIncome.money,
                     detail: "\(period.interval().start.shortDate) – \(period.interval().end.addingTimeInterval(-1).shortDate)")
            VStack(spacing: 0) {
                header(columns: compare ? ["ACTUAL", "ANTERIOR"] : ["ACTUAL"])
                group("Ingresos", current.income, previous.income)
                totalRow("Total ingresos", current.totalIncome, previous.totalIncome)
                group("Costo de ventas", current.costOfGoodsSold, previous.costOfGoodsSold)
                totalRow("Utilidad bruta", current.grossProfit, previous.grossProfit)
                group("Gastos operativos", current.expenses, previous.expenses)
                totalRow("Total gastos", current.totalExpenses, previous.totalExpenses)
                totalRow("Ganancia neta", current.netIncome, previous.netIncome, highlighted: true)
            }
            .card(padding: 0)
        }
    }

    // MARK: Balance general

    private var balanceSheet: some View {
        let fiscalStart = (try? Bookkeeper(context: context).fiscalYearStart(containing: .now))
            ?? Calendar.current.dateInterval(of: .year, for: .now)?.start
        let report = ReportBuilder.balanceSheet(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now, fiscalYearStart: fiscalStart)
        return VStack(spacing: 0) {
            header(columns: ["AL \(Date.now.shortDate.uppercased())"])
            group("Activos", report.assets, nil)
            totalRow("Total activos", report.totalAssets, nil)
            group("Pasivos", report.liabilities, nil)
            totalRow("Total pasivos", report.totalLiabilities, nil)
            group("Patrimonio", report.equity, nil)
            line("Resultados de años anteriores", report.priorYearsEarnings, nil)
            line("Resultado del ejercicio", report.currentYearEarnings, nil)
            totalRow("Total patrimonio", report.totalEquity, nil)
            totalRow("Pasivo + patrimonio", report.totalLiabilities + report.totalEquity, nil, highlighted: true)
            balanceCheck(report.isBalanced, ok: "Activo = Pasivo + Patrimonio", bad: "El balance no cuadra")
        }
        .card(padding: 0)
    }

    // MARK: Balanza de comprobación

    private var trialBalance: some View {
        let report = ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now)
        return VStack(spacing: 0) {
            header(columns: ["DEBE", "HABER"])
            ForEach(report.rows) { row in
                rowView(row.account.name, [row.debit == 0 ? "" : row.debit.money, row.credit == 0 ? "" : row.credit.money])
            }
            Divider()
            rowView("Totales", [report.totalDebit.money, report.totalCredit.money], bold: true)
            balanceCheck(report.isBalanced, ok: "Débitos = créditos", bad: "La balanza no cuadra")
        }
        .card(padding: 0)
    }

    // MARK: Antigüedad de cuentas por cobrar

    private var aging: some View {
        let items = invoices.filter(\.isOpen).map {
            AgingReport.OpenItem(party: $0.customer?.name ?? "Sin cliente", document: $0.number, dueDate: $0.dueDate, balance: $0.balanceDue)
        }
        let report = ReportBuilder.aging(items: items, asOf: .now)
        let titles: [AgingReport.Bucket: String] = [.current: "Corriente", .days1to30: "1–30", .days31to60: "31–60", .days61to90: "61–90", .over90: "> 90"]
        return VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(AgingReport.Bucket.allCases, id: \.self) { bucket in
                    KPITile(title: titles[bucket]!, value: report.total(for: bucket).money)
                }
            }
            VStack(spacing: 0) {
                header(columns: ["VENCIDO", "TOTAL"])
                ForEach(report.rows) { row in
                    let overdue = row.total - (row.amounts[.current] ?? 0)
                    rowView(row.party, [overdue.money, row.total.money])
                }
                if report.rows.isEmpty { Text("No hay facturas pendientes.").foregroundStyle(Palette.ink3).padding() }
                Divider()
                rowView("Total por cobrar", ["", report.total.money], bold: true)
            }
            .card(padding: 0)
        }
    }

    // MARK: Filas

    private func header(columns: [String]) -> some View {
        HStack {
            Text("CUENTA").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { Text($0).frame(width: 110, alignment: .trailing) }
        }
        .font(.label)
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [ReportRow], _ previous: [ReportRow]?) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
        ForEach(rows) { row in
            line(row.account.name, row.amount, previous.map { list in list.first { $0.account.id == row.account.id }?.amount ?? 0 }, indent: true)
        }
        if rows.isEmpty { line("Sin movimientos", 0, nil, indent: true).foregroundStyle(Palette.ink3) }
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

    private func rowView(_ title: String, _ values: [String], bold: Bool = false, indent: Bool = false) -> some View {
        HStack {
            Text(title).padding(.leading, indent ? 8 : 0).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value).frame(width: 110, alignment: .trailing)
                    .foregroundStyle(index == 0 ? Palette.ink : Palette.ink3)
            }
        }
        .font(bold ? .subheadline.weight(.semibold) : .subheadline)
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func balanceCheck(_ balanced: Bool, ok: String, bad: String) -> some View {
        Label(balanced ? ok : bad, systemImage: balanced ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(balanced ? Palette.positive : Palette.negative)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(balanced ? Palette.positiveWash : Palette.negativeWash)
    }

    // MARK: Exportar

    private var csv: String {
        var rows: [[String]] = []
        switch kind {
        case .income:
            let report = ledger.incomeStatement(period.interval())
            rows = [["Cuenta", "Importe"]]
                + (report.income + report.costOfGoodsSold + report.expenses).map { [$0.account.name, Money(minorUnits: $0.amount).decimalValue.description] }
                + [["Ganancia neta", Money(minorUnits: report.netIncome).decimalValue.description]]
        case .balance, .trial:
            let report = ReportBuilder.trialBalance(accounts: ledger.ledgerAccounts, lines: ledger.lines, asOf: .now)
            rows = [["Código", "Cuenta", "Debe", "Haber"]]
                + report.rows.map { [$0.account.code, $0.account.name, Money(minorUnits: $0.debit).decimalValue.description, Money(minorUnits: $0.credit).decimalValue.description] }
        case .aging:
            rows = [["Cliente", "Factura", "Vence", "Saldo"]]
                + invoices.filter(\.isOpen).map { [$0.customer?.name ?? "", $0.number, $0.dueDate.ISO8601Format(.iso8601.year().month().day()), Money(minorUnits: $0.balanceDue).decimalValue.description] }
        }
        return rows.map { $0.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack { ReportsView() }.modelContainer(SampleData.makeContainer())
}
