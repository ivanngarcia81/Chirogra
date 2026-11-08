import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Presupuesto contra real (fase 2, PLAN-FASE2 §6, docs/DATOS-V4.md §5)
//
// Vive en **Reportes** («Presupuesto contra real»): el canvas no lo dibuja, y lo que se mira cada mes es el reporte, así
// que va junto al estado de resultados (en «Más › Reportes» del iPhone y en la barra lateral de iPad y Mac). Los
// presupuestos se crean y se editan desde la misma página (menú del presupuesto), sin otra entrada en Contabilidad.
// - iPhone: el presupuesto (menú), Mes · Trimestre · Año, el periodo con ‹ ›, la base y la utilidad neta frente a lo
//   previsto; después las cuentas de ingresos y de gastos con lo real, lo previsto, la diferencia y su barra.
// - iPad y Mac: cajas de cifras y la tabla Cuenta · Presupuesto · Real · Diferencia · %; en el Mac, el inspector con la
//   cuenta elegida en todos los periodos y «Editar importes…».
// La diferencia es real − presupuesto: en verde lo favorable (ingresar más, gastar menos), en rojo lo desfavorable, y
// siempre con su signo y su porcentaje (no solo el color).

struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @CompanyQuery(sort: \Budget.createdAt) private var budgets: [Budget]
    @CompanyQuery private var budgetLines: [BudgetLine]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @ActiveCompanyQuery private var companies: [Company]
    @ReportBasisSetting private var basis
    @AppStorage("budgetSelection") private var storedSelection = ""
    @State private var grouping: BudgetGrouping = .month
    /// Periodo mostrado dentro del año fiscal; `nil` = el que contiene hoy (o el primero).
    @State private var periodIndex: Int?
    @State private var memo = ReportMemo<BudgetReport?>()
    @State private var creating = false
    @State private var editing: Budget?
    @State private var editingAccount: Account?
    @State private var renaming: Budget?
    @State private var newName = ""
    @State private var deleting: Budget?
    @State private var errorMessage: String?
    @State private var width: CGFloat = 0
    #if os(macOS)
    @State private var macPick: String?
    @State private var openedAccount: Account?
    #endif

    // MARK: Datos

    /// Más reciente primero, como `Bookkeeper.budgets()`.
    private var sortedBudgets: [Budget] {
        budgets.sorted { ($1.fiscalYear, $0.createdAt) < ($0.fiscalYear, $1.createdAt) }
    }

    /// El elegido (recordado en el aparato) o el del año fiscal en curso, o el más reciente.
    private var budget: Budget? {
        if let id = UUID(uuidString: storedSelection), let chosen = budgets.first(where: { $0.id == id }) { return chosen }
        let year = currentFiscalYear
        return sortedBudgets.first { $0.fiscalYear == year } ?? sortedBudgets.first
    }

    private var currentFiscalYear: Int {
        let start = companies.first?.fiscalYearStartMonth ?? 1
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return (parts.month ?? 1) >= start ? (parts.year ?? 2026) : (parts.year ?? 2026) - 1
    }

    private var report: BudgetReport? {
        guard let budget else { return nil }
        let planned = budgetLines.filter { $0.budget?.id == budget.id }
        let key = "\(budget.id)|\(grouping.rawValue)|\(basis.rawValue)|\(journalLines.count)|\(planned.count)|\(planned.reduce(0) { $0 &+ $1.amount &* Int64($1.month) })"
        return memo.value(for: key) { try? Bookkeeper(context: context).budgetVsActual(budget, grouping: grouping, basis: basis) }
    }

    private var index: Int {
        guard let report, !report.periods.isEmpty else { return 0 }
        if let periodIndex, report.periods.indices.contains(periodIndex) { return periodIndex }
        return report.periods.firstIndex { $0.start <= .now && .now <= $0.end } ?? 0
    }

    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility3 && (width == 0 || width >= 600)
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    // MARK: Página

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if budgets.isEmpty {
                    emptyState
                } else if isWide {
                    wideContent
                } else {
                    compactContent
                }
            }
            .padding(.horizontal, isWide ? 20 : Metrics.gutter)
            .padding(.top, isWide ? 8 : 0)
            .padding(.bottom, 28)
            .frame(maxWidth: isWide ? .infinity : 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle(ReportsView.Kind.budget.fullTitle)
        #if os(macOS)
        .navigationSubtitle(Text(verbatim: budget.map { "\($0.name) · \(fiscalYearLabel($0)) · \(basis.subtitle)" } ?? ""))
        #endif
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle(isAvailable: budget != nil)
        #endif
        .toolbar { toolbar }
        .onChange(of: grouping) { periodIndex = nil }
        .onChange(of: storedSelection) { periodIndex = nil }
        .sheet(isPresented: $creating) {
            NavigationStack {
                BudgetCreateView(budgets: sortedBudgets, suggestedYear: currentFiscalYear) { storedSelection = $0.uuidString }
            }
            .editorSheetSizing()
        }
        .sheet(item: $editing) { budget in NavigationStack { BudgetEditorView(budget: budget) }.editorSheetSizing() }
        .sheet(item: $editingAccount) { account in
            if let budget { NavigationStack { BudgetAccountEditor(budget: budget, account: account) }.editorSheetSizing() }
        }
        .alert("Cambiar nombre", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                if let renaming { run { try Bookkeeper(context: context).renameBudget(renaming, to: newName) } }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("¿Borrar el presupuesto?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let deleting { run { try Bookkeeper(context: context).deleteBudget(deleting) } }
                storedSelection = ""
                deleting = nil
            }
        } message: {
            Text("Se borran sus importes. Tus libros no cambian.")
        }
        #if DEBUG
        .task { await applyQA() }
        #endif
        #if os(macOS)
        .macReportInspector(title: macInspectorTitle, hasSelection: macSelectedAccount != nil,
                            placeholder: String(localized: "Elige una cuenta para ver todos sus periodos."), selectionKey: macPick,
                            qaSelectRow: { index in
                                let keys = macKeys
                                if keys.indices.contains(index) { macPick = keys[index] }
                            }, isAvailable: budget != nil) {
            macInspector
        } actions: {
            macActions
        }
        .navigationDestination(item: $openedAccount) { LedgerView(account: $0) }
        #endif
    }

    #if DEBUG
    /// `-qa.presupuesto nuevo|editar|cuenta` abre crear, el editor o el de la primera cuenta con importe; `-qa.agrupar
    /// trimestre|año` cambia la agrupación (solo Debug).
    private func applyQA() async {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "qa.agrupar") {
        case "trimestre": grouping = .quarter
        case "año": grouping = .year
        default: break
        }
        guard let action = defaults.string(forKey: "qa.presupuesto") else { return }
        try? await Task.sleep(for: .seconds(1))
        switch action {
        case "nuevo": creating = true
        case "editar": editing = budget
        case "cuenta":
            let ids = Set((budget?.lines ?? []).compactMap(\.accountID))
            editingAccount = accounts.first { ids.contains($0.id) }
        default: break
        }
    }
    #endif

    private func run(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    /// «2026» o, con otro inicio del año fiscal, «jul 2026 – jun 2027».
    private func fiscalYearLabel(_ budget: Budget) -> String {
        guard let months = try? Bookkeeper(context: context).months(ofFiscalYear: budget.fiscalYear),
              let first = months.first, let last = months.last else { return String(budget.fiscalYear) }
        if first.month == 1 { return String(budget.fiscalYear) }
        return (first.start..<last.end).formatted(.interval.month(.abbreviated).year().locale(.appText))
    }

    // MARK: Barra

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !budgets.isEmpty {
            ToolbarItem(placement: .primaryAction) { budgetMenu(compact: !isWide) }
            if isWide {
                ToolbarItem(placement: .primaryAction) { groupingPicker.fixedSize() }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) { BasisPicker(basis: $basis, compact: true); TermHelp(.accountingBasis) }
                }
            }
            if let report {
                ToolbarItem(placement: .primaryAction) { exportMenu(report) }
            }
        }
    }

    /// El presupuesto elegido y sus acciones: elegir otro, nuevo, editar importes, cambiar nombre y borrar.
    private func budgetMenu(compact: Bool) -> some View {
        Menu {
            if sortedBudgets.count > 1 {
                Picker("Presupuesto", selection: Binding(get: { budget?.id.uuidString ?? "" }, set: { storedSelection = $0 })) {
                    ForEach(sortedBudgets) { Text("\($0.name) · \(String($0.fiscalYear))").tag($0.id.uuidString) }
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button("Nuevo presupuesto…", systemImage: "plus") { SubscriptionStore.shared.whenWritable { creating = true } }
            if let budget {
                Button("Editar importes…", systemImage: "pencil") { SubscriptionStore.shared.whenWritable { editing = budget } }
                Button("Cambiar nombre…", systemImage: "character.cursor.ibeam") { newName = budget.name; renaming = budget }
                Divider()
                Button("Borrar presupuesto…", systemImage: "trash", role: .destructive) { deleting = budget }
            }
        } label: {
            if compact {
                Label("Presupuesto", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            } else {
                HStack(spacing: 6) { Image(systemName: "target"); Text(budget?.name ?? String(localized: "Presupuesto")) }
            }
        }
        .menuIndicator(.hidden)
        .headerButton()
        .accessibilityLabel("Presupuesto")
        .accessibilityValue(Text(verbatim: budget?.name ?? ""))
    }

    private var groupingPicker: some View {
        FilterPicker(title: String(localized: "Agrupar"), options: BudgetGrouping.allCases, selection: $grouping) { option in
            switch option {
            case .month: String(localized: "Mes")
            case .quarter: String(localized: "Trimestre")
            case .year: String(localized: "Año")
            }
        }
    }

    private func exportMenu(_ report: BudgetReport) -> some View {
        Menu {
            ShareLink(item: CSVFile(name: budget?.name ?? String(localized: "Presupuesto"), text: CSVExport.budget(report)),
                      preview: SharePreview((budget?.name ?? "") + ".csv")) {
                Label("CSV (hoja de cálculo)", systemImage: "tablecells")
            }
            ShareLink(item: LazyReportPDF(name: budget?.name ?? String(localized: "Presupuesto"), documents: [pdfDocument(report)],
                                          companyName: companies.first?.shownName ?? ""),
                      preview: SharePreview((budget?.name ?? "") + ".pdf")) {
                Label("PDF", systemImage: "doc.richtext")
            }
        } label: {
            if isWide { HStack(spacing: 6) { Image(systemName: "square.and.arrow.up"); Text("Exportar") } }
            else { Label("Exportar", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
        }
        .menuIndicator(.hidden)
        .headerButton()
        .accessibilityLabel("Exportar")
    }

    // MARK: Periodo

    private func periodTitle(_ report: BudgetReport, _ index: Int) -> String {
        guard report.periods.indices.contains(index) else { return "" }
        let period = report.periods[index]
        switch grouping {
        case .month: return period.start.monthYear
        case .quarter:
            return String(localized: "T\(index + 1) · \((period.start..<period.end).formatted(.interval.month(.abbreviated).year().locale(.appText)))")
        case .year: return budget.map(fiscalYearLabel) ?? ""
        }
    }

    /// «‹ Octubre de 2026 ›»: el periodo dentro del año del presupuesto.
    private func periodStepper(_ report: BudgetReport) -> some View {
        HStack(spacing: 4) {
            Button { periodIndex = max(0, index - 1) } label: {
                Image(systemName: "chevron.left").frame(minWidth: Metrics.target, minHeight: Metrics.target).contentShape(Rectangle())
            }
            .disabled(index == 0)
            .accessibilityLabel("Periodo anterior")
            Text(periodTitle(report, index)).font(.headline).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button { periodIndex = min(report.periods.count - 1, index + 1) } label: {
                Image(systemName: "chevron.right").frame(minWidth: Metrics.target, minHeight: Metrics.target).contentShape(Rectangle())
            }
            .disabled(index >= report.periods.count - 1)
            .accessibilityLabel("Periodo siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
    }

    // MARK: Cálculos de una fila

    private struct Figures {
        let budget: Int64
        let actual: Int64
        let isExpense: Bool
        var variance: Int64 { actual - budget }
        var isFavorable: Bool { isExpense ? variance <= 0 : variance >= 0 }
        var percent: Double? { budget == 0 ? nil : Double(actual) / Double(budget) }
    }

    private func figures(_ row: BudgetReport.Row, at index: Int) -> Figures {
        Figures(budget: row.budget.indices.contains(index) ? row.budget[index] : 0,
                actual: row.actual.indices.contains(index) ? row.actual[index] : 0, isExpense: row.account.type == .expense)
    }

    private func total(_ rows: [BudgetReport.Row], at index: Int, isExpense: Bool) -> Figures {
        Figures(budget: rows.reduce(0) { $0 + ($1.budget.indices.contains(index) ? $1.budget[index] : 0) },
                actual: rows.reduce(0) { $0 + ($1.actual.indices.contains(index) ? $1.actual[index] : 0) }, isExpense: isExpense)
    }

    private func net(_ report: BudgetReport, at index: Int) -> Figures {
        Figures(budget: report.budgetedNetIncome.indices.contains(index) ? report.budgetedNetIncome[index] : 0,
                actual: report.actualNetIncome.indices.contains(index) ? report.actualNetIncome[index] : 0, isExpense: false)
    }

    private func varianceColor(_ figures: Figures) -> Color {
        figures.variance == 0 ? Palette.ink2 : figures.isFavorable ? Palette.positive : Palette.negative
    }

    /// «+$1,200.00» / «−$300.00».
    private func signed(_ amount: Int64) -> String {
        amount == 0 ? amount.money : (amount > 0 ? "+" : "−") + abs(amount).money
    }

    private func percentText(_ figures: Figures) -> String {
        figures.percent.map { ($0 * 100).formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—"
    }

    /// Lo que lee VoiceOver de la diferencia: con «favorable» o «desfavorable», no solo el color.
    private func spokenVariance(_ figures: Figures) -> String {
        guard figures.variance != 0 else { return String(localized: "Igual que el presupuesto") }
        return figures.isFavorable ? String(localized: "\(signed(figures.variance)), favorable") : String(localized: "\(signed(figures.variance)), desfavorable")
    }

    // MARK: - Vacío

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyStateView(systemImage: "target", title: String(localized: "Sin presupuestos"),
                           message: String(localized: "Pon cuánto esperas vender y gastar cada mes, y compáralo con lo real. Puedes empezar vacío, copiando otro o con lo real del año pasado."),
                           actionTitle: String(localized: "Nuevo presupuesto")) { creating = true }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: - iPhone

    @ViewBuilder
    private var compactContent: some View {
        if let budget, let report {
            Text("\(budget.name) · \(fiscalYearLabel(budget))").font(.subheadline).foregroundStyle(Palette.ink2).padding(.bottom, 8)
            groupingPicker
            BasisPicker(basis: $basis).padding(.top, 10)
            periodStepper(report).padding(.top, 8)
            if let errorMessage { ErrorBanner(message: errorMessage).padding(.top, 8) }
            netCard(report).padding(.top, 8)
            compactSection(String(localized: "Ingresos"), report.income, isExpense: false)
            compactSection(String(localized: "Gastos"), report.expenses, isExpense: true)
            if !report.other.isEmpty { compactSection(String(localized: "Otras cuentas"), report.other, isExpense: false) }
            legend.padding(.horizontal, Metrics.gutter).padding(.top, 8)
        }
    }

    private var legend: some View {
        Text("Diferencia = real − presupuesto. En verde lo favorable (vender más o gastar menos de lo previsto) y en rojo lo desfavorable.")
            .font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
    }

    private func netCard(_ report: BudgetReport) -> some View {
        let figures = net(report, at: index)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Utilidad neta · \(periodTitle(report, index))").font(.subheadline).foregroundStyle(Palette.ink2)
            Text(figures.actual.money).font(.amount(36)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
            Text("Presupuesto \(figures.budget.money)").font(.footnote).foregroundStyle(Palette.ink2)
            Text(signed(figures.variance)).font(.footnote.weight(.semibold)).foregroundStyle(varianceColor(figures))
                .accessibilityLabel(spokenVariance(figures))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func compactSection(_ title: String, _ rows: [BudgetReport.Row], isExpense: Bool) -> some View {
        SectionLabel(text: title).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
        RowGroup(macBorder: true) {
            if rows.isEmpty {
                Text("Sin presupuesto ni movimientos").foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading).padding(.horizontal, 16)
            }
            ForEach(rows) { row in compactRow(row) }
            let sum = total(rows, at: index, isExpense: isExpense)
            AdaptiveRow {
                Text(isExpense ? String(localized: "Total gastos") : String(localized: "Total ingresos")).fontWeight(.semibold)
            } trailing: {
                VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                    Text(sum.actual.money).fontWeight(.semibold)
                    Text(signed(sum.variance)).font(.footnote).foregroundStyle(varianceColor(sum))
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// Cuenta: lo real y lo previsto, la diferencia de color con su signo, y una barra de lo real sobre lo previsto.
    private func compactRow(_ row: BudgetReport.Row) -> some View {
        let figures = figures(row, at: index)
        let account = accounts.first { $0.id == row.account.id }
        return Button { if let account { SubscriptionStore.shared.whenWritable { editingAccount = account } } } label: {
            VStack(alignment: .leading, spacing: 6) {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.account.name).foregroundStyle(Palette.ink)
                        Text("Real \(figures.actual.money) de \(figures.budget.money)").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                } trailing: {
                    VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                        Text(signed(figures.variance)).foregroundStyle(varianceColor(figures))
                        Text(percentText(figures)).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                BudgetBar(actual: figures.actual, budget: figures.budget, favorable: figures.isFavorable)
            }
            .monospacedDigit()
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.account.name)
        .accessibilityValue(String(localized: "Real \(figures.actual.money) de \(figures.budget.money). \(spokenVariance(figures))"))
        .accessibilityHint("Editar los importes de la cuenta")
    }

    // MARK: - iPad y Mac

    @ViewBuilder
    private var wideContent: some View {
        if let budget, let report {
            #if os(iOS)
            Text(verbatim: "\(budget.name) · \(fiscalYearLabel(budget)) · \(basis.subtitle)").font(.subheadline).foregroundStyle(Palette.ink2)
                .padding(.horizontal, 8).padding(.bottom, 12)
            #endif
            if let errorMessage { ErrorBanner(message: errorMessage).padding(.bottom, 12) }
            let income = total(report.income, at: index, isExpense: false)
            let expenses = total(report.expenses, at: index, isExpense: true)
            let netFigures = net(report, at: index)
            KPIGrid(items: [
                KPIItem(title: String(localized: "Ingresos"), value: income.actual.money,
                        foot: String(localized: "\(signed(income.variance)) vs. \(income.budget.money)"), footColor: varianceColor(income)),
                KPIItem(title: String(localized: "Gastos"), value: expenses.actual.money,
                        foot: String(localized: "\(signed(expenses.variance)) vs. \(expenses.budget.money)"), footColor: varianceColor(expenses)),
                KPIItem(title: String(localized: "Utilidad neta"), value: netFigures.actual.money,
                        foot: String(localized: "\(signed(netFigures.variance)) vs. \(netFigures.budget.money)"), footColor: varianceColor(netFigures)),
                KPIItem(title: String(localized: "Gasto usado"), value: percentText(expenses),
                        foot: String(localized: "del presupuesto de gastos")),
            ], large: true)
            .padding(.bottom, 16)
            periodStepper(report).frame(maxWidth: 420).padding(.bottom, 8)
            table(report)
            legend.padding(.horizontal, 2).padding(.top, 8)
        }
    }

    private func table(_ report: BudgetReport) -> some View {
        #if os(macOS)
        let picked = macSelectedKey
        #else
        let picked: String? = nil
        #endif
        let sections: [(String, [BudgetReport.Row], Bool)] = [
            (String(localized: "Ingresos"), report.income, false), (String(localized: "Gastos"), report.expenses, true),
        ] + (report.other.isEmpty ? [] : [(String(localized: "Otras cuentas"), report.other, false)])
        return TableCard {
            Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Presupuesto").frame(width: 120, alignment: .trailing)
            Text("Real").frame(width: 120, alignment: .trailing)
            Text("Diferencia").frame(width: 120, alignment: .trailing)
            Text(verbatim: "%").frame(width: 56, alignment: .trailing)
        } rows: {
            ForEach(sections, id: \.0) { title, rows, isExpense in
                TableRow { Text(title).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading) }
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                    let figures = figures(row, at: index)
                    tableRow(key: row.account.id.uuidString, picked: picked, zebra: !offset.isMultiple(of: 2), account: row.account.id) {
                        Text(row.account.name).lineLimit(1).padding(.leading, 14).frame(maxWidth: .infinity, alignment: .leading)
                        Text(figures.budget.money).frame(width: 120, alignment: .trailing)
                        Text(figures.actual.money).frame(width: 120, alignment: .trailing)
                        ReportCellText(text: signed(figures.variance), color: varianceColor(figures)).frame(width: 120, alignment: .trailing)
                        ReportCellText(text: percentText(figures)).frame(width: 56, alignment: .trailing)
                    }
                    .accessibilityValue(spokenVariance(figures))
                }
                let sum = total(rows, at: index, isExpense: isExpense)
                TableRow {
                    Text(isExpense ? String(localized: "Total gastos") : String(localized: "Total ingresos")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(sum.budget.money).frame(width: 120, alignment: .trailing)
                    Text(sum.actual.money).frame(width: 120, alignment: .trailing)
                    Text(signed(sum.variance)).foregroundStyle(varianceColor(sum)).frame(width: 120, alignment: .trailing)
                    Text(percentText(sum)).foregroundStyle(Palette.ink2).frame(width: 56, alignment: .trailing)
                }
                .fontWeight(.semibold)
            }
            let netFigures = net(report, at: index)
            TableRow {
                Text("Utilidad neta").frame(maxWidth: .infinity, alignment: .leading)
                Text(netFigures.budget.money).frame(width: 120, alignment: .trailing)
                Text(netFigures.actual.money).frame(width: 120, alignment: .trailing)
                Text(signed(netFigures.variance)).foregroundStyle(varianceColor(netFigures)).frame(width: 120, alignment: .trailing)
                Text(percentText(netFigures)).foregroundStyle(Palette.ink2).frame(width: 56, alignment: .trailing)
            }
            .fontWeight(.bold)
        }
    }

    /// Mac: la fila se elige para el inspector. iPad: tocarla abre los importes de la cuenta.
    @ViewBuilder
    private func tableRow<Content: View>(key: String, picked: String?, zebra: Bool, account id: UUID,
                                         @ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        MacReportRow(isSelected: key == picked, zebra: zebra, select: { macPick = key }) { content() }
        #else
        Button { if let account = accounts.first(where: { $0.id == id }) { SubscriptionStore.shared.whenWritable { editingAccount = account } } } label: {
            TableRow { content() }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Editar los importes de la cuenta")
        #endif
    }

    // MARK: Inspector del Mac

    #if os(macOS)
    private var macKeys: [String] {
        guard let report else { return [] }
        return (report.income + report.expenses + report.other).map(\.account.id.uuidString)
    }

    private var macSelectedKey: String? {
        let keys = macKeys
        if let macPick, keys.contains(macPick) { return macPick }
        return keys.first
    }

    private var macSelectedRow: BudgetReport.Row? {
        guard let key = macSelectedKey, let report else { return nil }
        return (report.income + report.expenses + report.other).first { $0.account.id.uuidString == key }
    }

    private var macSelectedAccount: Account? {
        macSelectedRow.flatMap { row in accounts.first { $0.id == row.account.id } }
    }

    private var macInspectorTitle: String { macSelectedRow?.account.name ?? ReportsView.Kind.budget.fullTitle }

    @ViewBuilder
    private var macInspector: some View {
        if let row = macSelectedRow, let report {
            let figures = figures(row, at: index)
            MacReportFigure(caption: String(localized: "Real · \(periodTitle(report, index))"), amount: figures.actual.money) {
                Text(String(localized: "\(signed(figures.variance)) vs. presupuesto \(figures.budget.money)"))
                    .foregroundStyle(varianceColor(figures))
            }
            MacInspectorSection(title: String(localized: "Por periodo")) {
                ForEach(report.periods.indices, id: \.self) { index in
                    let item = self.figures(row, at: index)
                    MacInspectorRow(label: periodTitle(report, index).sentenceCased) {
                        HStack(spacing: 6) {
                            Text(item.actual.money)
                            Text(signed(item.variance)).foregroundStyle(varianceColor(item)).font(.subheadline)
                        }
                    }
                }
            }
            MacInspectorSection(title: String(localized: "Año")) {
                MacInspectorRow(String(localized: "Presupuesto"), value: row.totalBudget.money)
                MacInspectorRow(String(localized: "Real"), value: row.totalActual.money)
                MacInspectorRow(String(localized: "Diferencia"), value: signed(row.variance),
                                color: row.variance == 0 ? Palette.ink2 : row.isFavorable ? Palette.positive : Palette.negative, bold: true)
            }
        }
    }

    @ViewBuilder
    private var macActions: some View {
        if let account = macSelectedAccount {
            Button("Editar importes…") { SubscriptionStore.shared.whenWritable { editingAccount = account } }.buttonStyle(.primary)
            Button("Ver en el libro mayor") { openedAccount = account }.buttonStyle(.secondary)
        }
    }
    #endif

    // MARK: PDF

    private func pdfDocument(_ report: BudgetReport) -> ReportDocument {
        var rows: [ReportDocument.Row] = []
        let sections: [(String, [BudgetReport.Row], Bool)] = [
            (String(localized: "Ingresos"), report.income, false), (String(localized: "Gastos"), report.expenses, true),
        ]
        for (title, list, isExpense) in sections {
            rows.append(ReportDocument.Row(label: title, style: .heading))
            for row in list {
                let item = figures(row, at: index)
                rows.append(ReportDocument.Row(label: "\(row.account.code) · \(row.account.name)",
                                               values: [item.budget.money, item.actual.money, signed(item.variance), percentText(item)], indent: 1))
            }
            let sum = total(list, at: index, isExpense: isExpense)
            rows.append(ReportDocument.Row(label: isExpense ? String(localized: "Total gastos") : String(localized: "Total ingresos"),
                                           values: [sum.budget.money, sum.actual.money, signed(sum.variance), percentText(sum)], style: .total))
            rows.append(ReportDocument.Row(label: "", style: .spacer))
        }
        let netFigures = net(report, at: index)
        rows.append(ReportDocument.Row(label: String(localized: "Utilidad neta"),
                                       values: [netFigures.budget.money, netFigures.actual.money, signed(netFigures.variance), percentText(netFigures)],
                                       style: .grand))
        return ReportDocument(title: String(localized: "Presupuesto contra real"),
                              subtitle: "\(budget?.name ?? "") · \(periodTitle(report, index)) · \(basis.subtitle)",
                              columns: [String(localized: "Presupuesto"), String(localized: "Real"), String(localized: "Diferencia"), "%"],
                              rows: rows, footnote: String(localized: "Diferencia = real − presupuesto."))
    }
}

/// Barra de lo real sobre lo previsto: de color si va bien, roja si se pasa (en gastos) o se queda corto (en ingresos).
private struct BudgetBar: View {
    let actual: Int64
    let budget: Int64
    let favorable: Bool

    var body: some View {
        let share = budget <= 0 ? (actual > 0 ? 1 : 0) : min(1, Double(max(0, actual)) / Double(budget))
        Capsule().fill(Palette.surface2).frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(favorable ? Palette.brand : Palette.red).frame(width: proxy.size.width * share)
                }
            }
            .accessibilityHidden(true)
    }
}
