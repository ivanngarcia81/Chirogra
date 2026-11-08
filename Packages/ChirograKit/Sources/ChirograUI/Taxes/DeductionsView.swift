import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Deducibles (fase 2, PLAN-FASE2 §5, docs/DATOS-V4.md §6)
//
// Totales del periodo por línea del Schedule C (dueño único y LLC) o del Form 1120-S (S corp), según el tipo de
// empresa (`TaxForm.forEntity`), con el detalle por cuenta. Cada cuenta va a la línea sugerida por su número en la
// plantilla (o por su tipo de detalle); el usuario la cambia o la excluye (`setTaxLine`), aquí o en el editor de la
// cuenta. Es una ayuda para el preparador, no una declaración: Chirogra no calcula el impuesto sobre la renta.
// - iPhone: pestaña «Deducibles» de Impuestos (canvas `Impuestos`): tarjeta con el total deducible y lo no deducible,
//   «Exportar para mi contador» y la lista por línea con su barra; cada línea abre sus cuentas.
// - iPad y Mac: página propia desde la tarjeta de Impuestos (canvas `MacImpuestos` · «Gastos deducibles»): cajas de
//   cifras y la tabla por línea con sus cuentas; en el Mac, el inspector con la cuenta elegida y su línea.

enum DeductionsText {
    static var disclaimer: String {
        String(localized: "Es una ayuda para quien prepara tu declaración, no una declaración de impuestos. Revisa las líneas con tu contador antes de presentar nada al IRS.")
    }
}

/// Periodo de los deducibles: el año en curso hasta hoy (como el canvas, «ene–oct 2026»), el año pasado o un trimestre.
enum DeductionsPeriod: String, CaseIterable, Identifiable {
    case yearToDate, lastYear, thisQuarter, lastQuarter
    var id: String { rawValue }

    var title: String {
        switch self {
        case .yearToDate: String(localized: "Este año")
        case .lastYear: String(localized: "Año pasado")
        case .thisQuarter: String(localized: "Este trimestre")
        case .lastQuarter: String(localized: "Trimestre anterior")
        }
    }

    /// Del primer día al último instante incluido.
    func range(calendar: Calendar = .current, now: Date = .now) -> (from: Date, to: Date) {
        func interval(_ component: Calendar.Component, offset: Int) -> DateInterval {
            let step = component == .quarter ? 3 : 1
            let date = calendar.date(byAdding: component == .quarter ? .month : component, value: offset * step, to: now) ?? now
            return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
        }
        let span: DateInterval = switch self {
        case .yearToDate: interval(.year, offset: 0)
        case .lastYear: interval(.year, offset: -1)
        case .thisQuarter: interval(.quarter, offset: 0)
        case .lastQuarter: interval(.quarter, offset: -1)
        }
        if self == .yearToDate {
            // Hasta hoy, como el canvas («ene–oct 2026»).
            let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now)) ?? now
            return (span.start, min(endOfToday, span.end.addingTimeInterval(-1)))
        }
        return (span.start, span.end.addingTimeInterval(-1))
    }

    /// «ene–dic 2026».
    func label(calendar: Calendar = .current) -> String {
        let range = range(calendar: calendar)
        return (range.from..<range.to).formatted(.interval.month(.abbreviated).year().locale(.appText))
    }

    #if DEBUG
    /// `-qa.deduciblesPeriodo año|añoPasado|trimestre|trimestreAnterior` (solo Debug).
    static var qaInitial: DeductionsPeriod {
        switch UserDefaults.standard.string(forKey: "qa.deduciblesPeriodo") {
        case "añoPasado": .lastYear
        case "trimestre": .thisQuarter
        case "trimestreAnterior": .lastQuarter
        default: .yearToDate
        }
    }
    #endif
}

/// Deducibles. `embedded`: solo el contenido, dentro de la pestaña de Impuestos del iPhone (sin desplazamiento ni barra
/// propios); si no, la página completa (iPad y Mac, o desde un enlace).
struct DeductionsView: View {
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @CompanyQuery private var entries: [JournalEntry]
    @ActiveCompanyQuery private var companies: [Company]
    @ReportBasisSetting private var basis
    #if DEBUG
    @State private var period: DeductionsPeriod = .qaInitial
    #else
    @State private var period: DeductionsPeriod = .yearToDate
    #endif
    @State private var memo = ReportMemo<TaxFormSummary?>()
    @State private var editingAccount: Account?
    @State private var exportingPackage = false
    @State private var errorMessage: String?
    @State private var width: CGFloat = 0
    #if os(macOS)
    /// Fila elegida para el inspector: «account:<id>» o «line:<id>».
    @State private var macPick: String?
    @State private var openedAccount: Account?
    #endif

    private var company: Company? { companies.first }
    private var form: TaxForm? { company.flatMap { TaxForm.forEntity($0.entityType) } }
    private var locale: Locale { .appText }

    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return !embedded && dynamicTypeSize < .accessibility3 && (width == 0 || width >= 600)
    }

    /// Resumen del periodo, recalculado solo si cambian el periodo, la base, el diario o la línea de alguna cuenta.
    private var summary: TaxFormSummary? {
        guard let form else { return nil }
        let lineChoices = accounts.map(\.taxFormLineRaw).joined(separator: ",")
        let key = "\(period.rawValue)|\(basis.rawValue)|\(form.rawValue)|\(journalLines.count)|\(entries.count)|\(lineChoices.hashValue)"
        let range = period.range()
        return memo.value(for: key) {
            try? Bookkeeper(context: context).taxSummary(from: range.from, to: range.to, basis: basis, form: form)
        }
    }

    private var deductionRows: [TaxFormSummary.Row] { (summary?.rows ?? []).filter { $0.line.kind == .deduction } }
    private var incomeRows: [TaxFormSummary.Row] { (summary?.rows ?? []).filter { $0.line.kind == .income } }
    /// Lo que no se deduce: las cuentas excluidas y la parte no deducible (comidas al 50 %).
    private var notDeductible: Int64 {
        guard let summary else { return 0 }
        let excludedExpenses = summary.excluded.filter { $0.account.type == .expense }.reduce(0) { $0 + $1.amount }
        return excludedExpenses + deductionRows.reduce(0) { $0 + $1.amount - $1.deductibleAmount }
    }

    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 0) { compactContent }
                .sheet(item: $editingAccount) { account in taxLineSheet(account) }
                .sheet(isPresented: $exportingPackage) { exportSheet }
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            if isWide {
                wideContent.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
            } else {
                VStack(alignment: .leading, spacing: 0) { compactContent }
                    .padding(.horizontal, Metrics.gutter).padding(.bottom, 28)
                    .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Deducibles")
        #if os(macOS)
        .navigationSubtitle(String(localized: "\(form?.title ?? "") · \(period.label()) · \(basis.subtitle)"))
        #endif
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle(isAvailable: form != nil)
        #endif
        .toolbar {
            if isWide {
                ToolbarItem(placement: .primaryAction) { periodMenu }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) { BasisPicker(basis: $basis, compact: true); TermHelp(.accountingBasis) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { exportingPackage = true } label: {
                        HStack(spacing: 6) { Image(systemName: "archivebox"); Text("Exportar para mi contador…") }
                    }
                    .headerButton()
                }
            }
        }
        .sheet(item: $editingAccount) { account in taxLineSheet(account) }
        .sheet(isPresented: $exportingPackage) { exportSheet }
        #if DEBUG
        .task { await applyQA() }
        #endif
        #if os(macOS)
        .macReportInspector(title: macInspectorTitle, hasSelection: macSelectedKey != nil,
                            placeholder: String(localized: "Sin gastos ni ingresos en el periodo."), selectionKey: macPick,
                            qaSelectRow: { index in
                                let keys = macKeys
                                if keys.indices.contains(index) { macPick = keys[index] }
                            }, isAvailable: form != nil) {
            macInspector
        } actions: {
            macActions
        }
        .navigationDestination(item: $openedAccount) { LedgerView(account: $0) }
        #endif
    }

    #if DEBUG
    /// `-qa.lineaFiscal N` abre el cambio de línea de la cuenta N (en el orden de la lista; solo Debug).
    private func applyQA() async {
        guard UserDefaults.standard.object(forKey: "qa.lineaFiscal") != nil else { return }
        try? await Task.sleep(for: .seconds(1))
        let all = (summary?.rows ?? []).flatMap(\.accounts)
        let index = UserDefaults.standard.integer(forKey: "qa.lineaFiscal")
        if all.indices.contains(index) { editingAccount = account(all[index].account.id) }
    }
    #endif

    private func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }

    private var exportSheet: some View {
        let range = period.range()
        return NavigationStack {
            AccountantExportView(initialInterval: DateInterval(start: range.from, end: range.to.addingTimeInterval(1)))
        }
        .editorSheetSizing()
    }

    private func taxLineSheet(_ account: Account) -> some View {
        NavigationStack { TaxLinePickerView(account: account, form: form ?? .scheduleC) }.editorSheetSizing()
    }

    // MARK: Piezas comunes

    private var periodMenu: some View {
        Menu {
            Picker("Periodo", selection: $period) {
                ForEach(DeductionsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) { Image(systemName: "calendar"); Text("\(period.title) · \(period.label())") }
        }
        .menuIndicator(.hidden)
        .headerButton()
        .accessibilityLabel("Periodo")
        .accessibilityValue(Text(verbatim: "\(period.title), \(period.label())"))
    }

    /// Aviso de que es una ayuda para el preparador (siempre a la vista, no solo en el pie).
    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Palette.info).accessibilityHidden(true)
            Text(DeductionsText.disclaimer).font(.subheadline).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.infoWash, in: RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Sin formulario para el tipo de empresa (sociedad, C corp).
    private var noFormNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sin formulario para \(company?.entityType.title ?? "")").font(.headline).foregroundStyle(Palette.ink)
            Text("Chirogra prepara el Schedule C (dueño único y LLC) y el Form 1120-S (S corp). Para sociedades (1065) y C corp (1120), exporta el paquete para tu contador con los reportes y el diario.")
                .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            Button("Exportar para mi contador…") { exportingPackage = true }.buttonStyle(.primaryCompact).padding(.top, 4)
        }
        .card(padding: 16)
    }

    private func lineName(_ line: TaxFormLine) -> String { line.label(for: locale) }

    // MARK: - iPhone

    @ViewBuilder
    private var compactContent: some View {
        HStack {
            Menu {
                Picker("Periodo", selection: $period) {
                    ForEach(DeductionsPeriod.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(period.title) · \(period.label())")
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(minHeight: Metrics.target).contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("Periodo")
            .accessibilityValue(Text(verbatim: "\(period.title), \(period.label())"))
            Spacer(minLength: 0)
        }
        .padding(.top, embedded ? 8 : 0)
        BasisPicker(basis: $basis).padding(.top, 4)
        if let errorMessage { ErrorBanner(message: errorMessage).padding(.top, 12) }
        if form == nil {
            noFormNote.padding(.top, 16)
        } else {
            totalCard.padding(.top, 16)
            disclaimer.padding(.top, 12)
            if !deductionRows.isEmpty {
                label(String(localized: "Deducciones · \(form?.title ?? "")"))
                RowGroup { ForEach(deductionRows) { compactLineRow($0, top: deductionRows.map(\.amount).max() ?? 1) } }
            }
            if !incomeRows.isEmpty {
                label(String(localized: "Ingresos"))
                RowGroup { ForEach(incomeRows) { compactLineRow($0, top: incomeRows.map(\.amount).max() ?? 1) } }
            }
            if let excluded = summary?.excluded, !excluded.isEmpty {
                label(String(localized: "Excluidas del formulario"))
                RowGroup { ForEach(excluded) { accountRow($0, line: nil) } }
            }
            if deductionRows.isEmpty && incomeRows.isEmpty {
                Text("Sin ingresos ni gastos en el periodo.").font(.subheadline).foregroundStyle(Palette.ink2).padding(.top, 16)
            }
            Text("Toca una línea para ver sus cuentas y cambiar a qué línea va cada una.")
                .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, Metrics.gutter).padding(.top, 8)
        }
    }

    private func label(_ text: String) -> some View {
        SectionLabel(text: text).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
    }

    /// Canvas `Impuestos` · Deducibles: el total, lo no deducible a la derecha y «Exportar para mi contador».
    private var totalCard: some View {
        VStack(spacing: 0) {
            AdaptiveRow(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gastos deducibles · \(period.label())").font(.subheadline).foregroundStyle(Palette.ink2)
                    Text((summary?.totalDeductions ?? 0).money).font(.amount(34)).foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            } trailing: {
                VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                    Text("No deducible").font(.footnote).foregroundStyle(Palette.ink2)
                    Text(notDeductible.money).monospacedDigit().foregroundStyle(Palette.ink)
                }
                .padding(.bottom, 5)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            Divider().padding(.leading, 16)
            Button { exportingPackage = true } label: {
                Label("Exportar para mi contador", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Palette.brand)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    /// Línea del formulario con su importe y su barra (canvas: barra de 6 pt en Tinta); abre sus cuentas.
    private func compactLineRow(_ row: TaxFormSummary.Row, top: Int64) -> some View {
        NavigationLink {
            DeductionLineDetail(lineID: row.id, period: period, onEdit: { editingAccount = account($0) })
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                AdaptiveRow {
                    Text(lineName(row.line)).foregroundStyle(Palette.ink)
                } trailing: {
                    HStack(spacing: 8) {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                            Text(row.deductibleAmount.money).monospacedDigit().foregroundStyle(Palette.ink)
                            if row.deductibleAmount != row.amount {
                                Text("de \(row.amount.money)").font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                            }
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                            .accessibilityHidden(true)
                    }
                }
                Capsule().fill(Palette.brand)
                    .frame(width: nil, height: 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: max(0.03, top == 0 ? 0 : CGFloat(abs(row.amount)) / CGFloat(abs(top))), y: 1, anchor: .leading)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Muestra las cuentas de la línea")
    }

    /// Cuenta dentro de una línea (o excluida): su importe y, al tocarla, el cambio de línea.
    private func accountRow(_ row: ReportRow, line: TaxFormLine?) -> some View {
        Button { editingAccount = account(row.account.id) } label: {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.account.name).foregroundStyle(Palette.ink)
                    Text(line.map(lineName) ?? String(localized: "Excluida · \(row.account.code)"))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
            } trailing: {
                Text(row.amount.money).monospacedDigit().foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Cambia la línea del formulario")
    }

    // MARK: - iPad y Mac

    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
            Text(verbatim: "\(form?.title ?? "") · \(period.label()) · \(basis.subtitle)").font(.subheadline).foregroundStyle(Palette.ink2)
                .padding(.horizontal, 8)
            #endif
            if let errorMessage { ErrorBanner(message: errorMessage) }
            if form == nil {
                noFormNote
            } else if let summary {
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Ingresos"), value: summary.totalIncome.money, foot: form?.title),
                    KPIItem(title: String(localized: "Gastos deducibles"), value: summary.totalDeductions.money,
                            foot: String(localized: "\(deductionRows.count) líneas")),
                    KPIItem(title: String(localized: "No deducible"), value: notDeductible.money,
                            foot: String(localized: "Excluidas y comidas al 50 %")),
                    KPIItem(title: String(localized: "Ingresos menos deducciones"), value: (summary.totalIncome - summary.totalDeductions).money,
                            foot: String(localized: "Aproximado, antes de ajustes")),
                ], large: true)
                disclaimer
                linesTable(summary)
            }
        }
    }

    private func linesTable(_ summary: TaxFormSummary) -> some View {
        #if os(macOS)
        let picked = macSelectedKey
        #else
        let picked: String? = nil
        #endif
        let groups: [(String, [TaxFormSummary.Row])] = [(String(localized: "Ingresos"), incomeRows), (String(localized: "Deducciones"), deductionRows)]
        return TableCard {
            Text("Línea").frame(width: 56, alignment: .leading)
            Text("Concepto").frame(maxWidth: .infinity, alignment: .leading)
            Text("Importe").frame(width: 120, alignment: .trailing)
            Text("Deducible").frame(width: 120, alignment: .trailing)
        } rows: {
            ForEach(groups, id: \.0) { title, rows in
                if !rows.isEmpty {
                    TableRow { Text(title).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading) }
                        .accessibilityAddTraits(.isHeader)
                    ForEach(rows) { row in
                        tableRow(key: "line:\(row.id)", picked: picked, account: nil) {
                            Text(row.line.number).fontWeight(.semibold).frame(width: 56, alignment: .leading)
                            Text(row.line.name(for: locale)).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.amount.money).fontWeight(.semibold).frame(width: 120, alignment: .trailing)
                            Text(row.line.kind == .income ? "—" : row.deductibleAmount.money).fontWeight(.semibold)
                                .frame(width: 120, alignment: .trailing)
                        }
                        ForEach(row.accounts) { item in
                            tableRow(key: "account:\(item.account.id)", picked: picked, account: item.account.id) {
                                ReportCellText(text: item.account.code).frame(width: 56, alignment: .leading)
                                Text(item.account.name).lineLimit(1).padding(.leading, 14).frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.amount.money).frame(width: 120, alignment: .trailing)
                                Text(verbatim: "").frame(width: 120)
                            }
                        }
                    }
                }
            }
            if !summary.excluded.isEmpty {
                TableRow { Text("Excluidas del formulario").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(summary.excluded) { item in
                    tableRow(key: "account:\(item.account.id)", picked: picked, account: item.account.id) {
                        ReportCellText(text: item.account.code).frame(width: 56, alignment: .leading)
                        Text(item.account.name).lineLimit(1).padding(.leading, 14).frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.amount.money).frame(width: 120, alignment: .trailing)
                        ReportCellText(text: String(localized: "Excluida")).frame(width: 120, alignment: .trailing)
                    }
                }
            }
            if summary.rows.isEmpty && summary.excluded.isEmpty {
                Text("Sin ingresos ni gastos en el periodo.").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            TableRow {
                Color.clear.frame(width: 56, height: 1)
                Text("Total deducible").frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "").frame(width: 120)
                Text(summary.totalDeductions.money).frame(width: 120, alignment: .trailing)
            }
            .fontWeight(.semibold)
        }
    }

    /// En el Mac la fila se elige para el inspector; en el iPad, tocar una cuenta abre el cambio de línea.
    @ViewBuilder
    private func tableRow<Content: View>(key: String, picked: String?, account id: UUID?, @ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        MacReportRow(isSelected: key == picked, select: { macPick = key }) { content() }
        #else
        if let id {
            Button { editingAccount = account(id) } label: { TableRow { content() } }
                .buttonStyle(.plain)
                .accessibilityHint("Cambia la línea del formulario")
        } else {
            TableRow { content() }
        }
        #endif
    }

    // MARK: Inspector del Mac

    #if os(macOS)
    private var macKeys: [String] {
        guard let summary else { return [] }
        return (incomeRows + deductionRows).flatMap { row in ["line:\(row.id)"] + row.accounts.map { "account:\($0.account.id)" } }
            + summary.excluded.map { "account:\($0.account.id)" }
    }

    private var macSelectedKey: String? {
        let keys = macKeys
        if let macPick, keys.contains(macPick) { return macPick }
        return keys.first { $0.hasPrefix("account:") } ?? keys.first
    }

    private var selectedAccountID: UUID? {
        guard let key = macSelectedKey, key.hasPrefix("account:") else { return nil }
        return UUID(uuidString: String(key.dropFirst("account:".count)))
    }

    private var selectedRow: TaxFormSummary.Row? {
        guard let key = macSelectedKey, key.hasPrefix("line:") else { return nil }
        return summary?.rows.first { "line:\($0.id)" == key }
    }

    private var macInspectorTitle: String {
        if let id = selectedAccountID, let account = account(id) { return account.name }
        if let row = selectedRow { return row.line.name(for: locale) }
        return String(localized: "Deducibles")
    }

    @ViewBuilder
    private var macInspector: some View {
        if let id = selectedAccountID, let account = account(id), let form {
            let amount = (summary?.rows.flatMap(\.accounts) ?? []).first { $0.account.id == id }?.amount
                ?? summary?.excluded.first { $0.account.id == id }?.amount ?? 0
            let current = try? Bookkeeper(context: context).taxLine(for: account, form: form)
            MacReportFigure(caption: String(localized: "Cuenta \(account.code) · \(period.label())"), amount: amount.money) {
                Text(current.map(lineName) ?? String(localized: "Excluida del formulario")).foregroundStyle(Palette.ink2)
            }
            MacInspectorSection(title: String(localized: "Línea del \(form.title)")) {
                TaxLineMenu(account: account, form: form, onError: { errorMessage = $0 })
                    .padding(.vertical, 4)
                MacInspectorRow(String(localized: "Sugerida"), value: suggestedLine(account, form: form).map(lineName) ?? "—")
                if let current, current.deductiblePercent != 100 {
                    MacInspectorRow(String(localized: "Deducible"), value: "\(current.deductiblePercent)%")
                }
            }
            Text("La línea sugerida sale del número de la cuenta en la plantilla. Cámbiala si tu contador la lleva a otra; el cambio se guarda en la cuenta y vale para todos los periodos.")
                .font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        } else if let row = selectedRow {
            MacReportFigure(caption: String(localized: "Línea \(row.line.number) · \(period.label())"), amount: row.amount.money) {
                Text(row.line.kind == .income ? String(localized: "Ingreso") : String(localized: "Deducible \(row.deductibleAmount.money)"))
                    .foregroundStyle(Palette.ink2)
            }
            MacInspectorSection(title: String(localized: "Cuentas")) {
                ForEach(row.accounts) { item in MacInspectorRow(item.account.name, value: item.amount.money) }
            }
            MacInspectorSection(title: String(localized: "Formulario")) {
                MacInspectorRow(String(localized: "Parte"), value: row.line.part)
                MacInspectorRow(String(localized: "En inglés"), value: row.line.english)
            }
        }
    }

    @ViewBuilder
    private var macActions: some View {
        if let id = selectedAccountID, let account = account(id) {
            Button("Ver en el libro mayor") { openedAccount = account }.buttonStyle(.primary)
            Button("Volver a la sugerida") {
                do { try Bookkeeper(context: context).setTaxLine(nil, for: account); errorMessage = nil } catch { errorMessage = error.localizedDescription }
            }
            .buttonStyle(.secondary)
            .disabled(account.taxFormLineRaw.isEmpty)
        }
        Button("Exportar para mi contador…") { exportingPackage = true }.buttonStyle(.secondary)
    }
    #endif

    private func suggestedLine(_ account: Account, form: TaxForm) -> TaxFormLine? {
        TaxLinePickerView.suggested(for: account, form: form, sector: company.flatMap { BusinessSector(rawValue: $0.sectorRaw) } ?? .services)
    }
}

/// Las cuentas de una línea del formulario (iPhone e iPad), con el cambio de línea de cada una.
struct DeductionLineDetail: View {
    let lineID: String
    let period: DeductionsPeriod
    let onEdit: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @ActiveCompanyQuery private var companies: [Company]
    @ReportBasisSetting private var basis
    @State private var editingAccount: Account?

    private var row: TaxFormSummary.Row? {
        let _ = journalLines.count
        let range = period.range()
        let form = companies.first.flatMap { TaxForm.forEntity($0.entityType) }
        return (try? Bookkeeper(context: context).taxSummary(from: range.from, to: range.to, basis: basis, form: form))?
            .rows.first { $0.id == lineID }
    }

    var body: some View {
        let _ = accounts.map(\.taxFormLineRaw)
        List {
            if let row {
                Section {
                    LabeledContent("Importe", value: row.amount.money)
                    if row.line.kind == .deduction {
                        LabeledContent("Deducible", value: row.deductibleAmount.money)
                    }
                    LabeledContent("Periodo", value: period.label())
                } header: {
                    SectionLabel(text: row.line.label(for: .appText))
                } footer: {
                    Text(row.line.english)
                }
                Section {
                    ForEach(row.accounts) { item in
                        Button { editingAccount = accounts.first { $0.id == item.account.id } } label: {
                            LabeledContent {
                                Text(item.amount.money).monospacedDigit()
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.account.name).foregroundStyle(Palette.ink)
                                    Text(item.account.code).font(.footnote).foregroundStyle(Palette.ink2)
                                }
                            }
                            .frame(minHeight: Metrics.target)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Cambia la línea del formulario")
                    }
                } header: {
                    SectionLabel(text: String(localized: "Cuentas"))
                } footer: {
                    Text("Toca una cuenta para llevarla a otra línea o excluirla.")
                }
            } else {
                Text("Esta línea ya no tiene importes en el periodo.").foregroundStyle(Palette.ink2)
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle(row.map { String(localized: "Línea \($0.line.number)") } ?? String(localized: "Línea"))
        .inlineTitle()
        .sheet(item: $editingAccount) { account in
            NavigationStack {
                TaxLinePickerView(account: account, form: companies.first.flatMap { TaxForm.forEntity($0.entityType) } ?? .scheduleC)
            }
            .editorSheetSizing()
        }
    }
}

// MARK: - Cambiar la línea de una cuenta

/// Valor del selector: "" = la sugerida, `TaxFormCatalog.none` = excluida, o el id de una línea («scheduleC:22»).
enum TaxLineChoice {
    static let suggested = ""

    /// Lo que muestra el selector para la cuenta: lo guardado si es de este formulario; si no, la sugerida.
    static func current(for account: Account, form: TaxForm) -> String {
        let raw = account.taxFormLineRaw
        if raw == TaxFormCatalog.none { return raw }
        if let line = TaxFormCatalog.line(id: raw), line.form == form { return raw }
        return suggested
    }
}

/// Hoja con todas las líneas del formulario por parte, la sugerida arriba y «Excluir». Guarda al elegir.
struct TaxLinePickerView: View {
    let account: Account
    let form: TaxForm
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ActiveCompanyQuery private var companies: [Company]
    @State private var errorMessage: String?

    static func suggested(for account: Account, form: TaxForm, sector: BusinessSector) -> TaxFormLine? {
        TaxFormCatalog.defaultLineNumber(code: account.code, subtype: account.subtype, sector: sector, form: form)
            .flatMap { TaxFormCatalog.line($0, in: form) }
    }

    private var suggested: TaxFormLine? {
        Self.suggested(for: account, form: form, sector: companies.first.flatMap { BusinessSector(rawValue: $0.sectorRaw) } ?? .services)
    }

    private var choice: String { TaxLineChoice.current(for: account, form: form) }

    /// Las líneas del mismo tipo que la cuenta (ingreso o deducción) y, aparte, las demás.
    private var parts: [(String, [TaxFormLine])] {
        let lines = TaxFormCatalog.lines(for: form)
        var order: [String] = []
        var grouped: [String: [TaxFormLine]] = [:]
        for line in lines {
            if grouped[line.part] == nil { order.append(line.part) }
            grouped[line.part, default: []].append(line)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                option(TaxLineChoice.suggested, title: String(localized: "Usar la sugerida"),
                       detail: suggested.map { $0.label(for: .appText) } ?? String(localized: "Sin línea sugerida"))
                option(TaxFormCatalog.none, title: String(localized: "Excluir del formulario"),
                       detail: String(localized: "No es deducible o no va en la declaración del negocio"))
            } header: {
                SectionLabel(text: "\(account.code) · \(account.name)")
            } footer: {
                Text(DeductionsText.disclaimer)
            }
            ForEach(parts, id: \.0) { part, lines in
                Section {
                    ForEach(lines) { line in
                        option(line.id, title: line.label(for: .appText), detail: line.deductiblePercent == 100 ? nil : String(localized: "Deducible al \(line.deductiblePercent) %"))
                    }
                } header: {
                    SectionLabel(text: part)
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(String(localized: "Línea del \(form.title)"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.headerButton() }
        }
    }

    private func option(_ value: String, title: String, detail: String?) -> some View {
        Button {
            do {
                try Bookkeeper(context: context).setTaxLine(value == TaxLineChoice.suggested ? nil : value, for: account)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(Palette.ink)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink2) }
                }
                Spacer(minLength: 8)
                if choice == value {
                    Image(systemName: "checkmark").foregroundStyle(Palette.brand).fontWeight(.semibold)
                }
            }
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }
}

/// Selector de línea en un menú (inspector del Mac y editor de la cuenta): guarda al elegir.
struct TaxLineMenu: View {
    let account: Account
    let form: TaxForm
    var onError: (String) -> Void = { _ in }
    @Environment(\.modelContext) private var context

    var body: some View {
        Picker(String(localized: "Línea"), selection: Binding(
            get: { TaxLineChoice.current(for: account, form: form) },
            set: { value in
                do { try Bookkeeper(context: context).setTaxLine(value == TaxLineChoice.suggested ? nil : value, for: account) }
                catch { onError(error.localizedDescription) }
            })) {
            TaxLineOptions(form: form)
        }
        .pickerStyle(.menu)
    }
}

/// Opciones del selector de línea: «Sugerida», las del formulario y «Excluir».
struct TaxLineOptions: View {
    let form: TaxForm

    var body: some View {
        Text("Sugerida").tag(TaxLineChoice.suggested)
        ForEach(TaxFormCatalog.lines(for: form)) { line in
            Text(line.label(for: .appText)).tag(line.id)
        }
        Text("Excluir del formulario").tag(TaxFormCatalog.none)
    }
}
