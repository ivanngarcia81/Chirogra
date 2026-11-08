import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Impuestos.
/// - iPhone (y la columna estrecha del iPad): tablero `Impuestos`. Subtítulo con el trimestre (menú), segmentado
///   Resumen · Tasas; en Resumen, la tarjeta «Impuesto sobre ventas por pagar» con la hoja de calendario «Declarar y
///   pagar» y «Registrar pago de impuesto», y el desglose como grupo de filas; en Tasas, la lista con «Nueva tasa» en
///   Tinta, su pie gris y el periodo de declaración de cada agencia.
/// - iPad y Mac: `MacImpuestos`: cuatro cajas de cifras, la tabla de tasas con cebra y los pagos a la agencia. En el
///   Mac, además, el inspector de la derecha con la tasa elegida en la tabla y la declaración del trimestre.
/// En Tasas (iPhone) y en la caja «Facturas nuevas» (iPad y Mac): el impuesto predeterminado de la empresa, «Precios con
/// impuesto incluido» y el origen de las ventas. Cada tasa se edita («Editar tasa…»; las facturas emitidas no cambian).
/// Fase 2 (1.3): «Deducibles» como tercera pestaña en el iPhone (`DeductionsView` dentro) y, en iPad y Mac, la tarjeta
/// «Gastos deducibles» de `MacImpuestos` con «Ver por línea» (página `DeductionsView`) y «Exportar para mi contador…».
struct TaxesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Resumen", rates = "Tasas", deductions = "Deducibles"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var journalLines: [JournalLine]
    @CompanyQuery(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @CompanyQuery(sort: \TaxGroup.name) private var groups: [TaxGroup]
    @CompanyQuery private var taxLines: [InvoiceTaxLine]
    @ActiveCompanyQuery private var companies: [Company]
    @CompanyQuery(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    @State var tab: Tab = .summary
    /// Trimestre mostrado: 0 el actual, −1 el anterior…
    @State private var quarterOffset = 0
    @State private var showingRate = false
    @State private var showingPayment = false
    @State private var showingGroup = false
    @State private var editingRate: TaxRate?
    @State private var errorMessage: String?
    /// Fase 2: deducibles del año (tarjeta de iPad y Mac), su página y el paquete del contador.
    @ReportBasisSetting private var basis
    @State private var deductionsMemo = ReportMemo<TaxFormSummary?>()
    @State private var showingDeductions = false
    @State private var exportingPackage = false
    @State private var width: CGFloat = 0
    #if os(macOS)
    /// Tasa o grupo elegido en la tabla para el inspector (clave de `macRateItems`); sin elegir, el primero.
    @State private var macPick: String?
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacImpuestos` en iPad y Mac con sitio para las cajas y la tabla; si no, el diseño del iPhone.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility3 && (width == 0 || width >= 600)
    }

    private var payable: Int64 {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        return accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
    }

    private var company: Company? { companies.first }
    private var defaultTaxID: UUID? { company?.defaultTaxGroupID }

    /// Nombre del impuesto predeterminado («Austin, TX»), si lo hay.
    private var defaultTaxName: String? {
        guard let id = defaultTaxID else { return nil }
        return groups.first { $0.id == id }?.name ?? agencies.flatMap { $0.rates ?? [] }.first { $0.id == id }?.name
    }

    private func setDefault(_ id: UUID?) {
        do { try Bookkeeper(context: context).setDefaultTax(id); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    var body: some View {
        #if DEBUG
        // `-qa.impuestos pagina`: la página de deducibles en lugar de Impuestos (capturas del Mac: la ventana oculta de
        // `open -j` no redibuja lo que se abre encima). Solo Debug.
        if UserDefaults.standard.string(forKey: "qa.impuestos") == "pagina" { DeductionsView() } else { taxesBody }
        #else
        taxesBody
        #endif
    }

    private var taxesBody: some View {
        let _ = taxLines.count   // se observa para recalcular el resumen al emitir facturas
        return ScrollView {
            if isWide { wideBody } else { compactBody }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.background)
        .navigationTitle("Impuestos")
        #if os(macOS)
        .navigationSubtitle(String(localized: "\(quarterTitle(quarter(quarterOffset))) · declaración trimestral"))
        #endif
        .headerTitle()
        #if os(macOS)
        .macInspectorToggle()
        #endif
        .toolbar {
            if isWide {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { quarterMenu(compact: false) }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    SectionLink(item: .report(.salesTax)) { ReportsView(fixedKind: .salesTax) } label: {
                        HStack(spacing: 6) { Image(systemName: "doc.text.magnifyingglass"); Text("Ver reporte") }
                    }
                    .headerButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingPayment = true } label: {
                        HStack(spacing: 6) { Image(systemName: "checkmark.circle"); Text("Registrar pago de impuesto") }
                    }
                    .disabled(payable <= 0)
                    .headerButton()
                }
            }
        }
        .sheet(isPresented: $showingRate) { NavigationStack { TaxRateEditorView() }.editorSheetSizing() }
        .sheet(isPresented: $showingPayment) { NavigationStack { SalesTaxPaymentView(owed: payable) }.editorSheetSizing() }
        .sheet(isPresented: $showingGroup) { NavigationStack { TaxGroupEditorView() }.editorSheetSizing() }
        .sheet(item: $editingRate) { rate in NavigationStack { TaxRateEditorView(rate: rate) }.editorSheetSizing() }
        .sheet(isPresented: $exportingPackage) { NavigationStack { AccountantExportView() }.editorSheetSizing() }
        #if DEBUG
        // `-qa.impuestos deducibles` abre los deducibles: la pestaña en el iPhone, la página en iPad y Mac (solo Debug).
        .task {
            guard UserDefaults.standard.string(forKey: "qa.impuestos") == "deducibles" else { return }
            tab = .deductions
            // Después de medir el ancho: al aparecer, la página aún no sabe si es ancha.
            try? await Task.sleep(for: .seconds(1))
            if isWide { showingDeductions = true }
        }
        #endif
        #if DEBUG
        // `-qa.tasa N` abre «Editar tasa» de la tasa N (orden de la tabla, sin los grupos); `-qa.tasa nueva` y
        // `-qa.tasa grupo`, «Nueva tasa» y «Nuevo grupo». Solo Debug.
        .task {
            guard UserDefaults.standard.object(forKey: "qa.tasa") != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            switch UserDefaults.standard.string(forKey: "qa.tasa") {
            case "nueva": showingRate = true; return
            case "grupo": showingGroup = true; return
            default: break
            }
            let rates = agencies.flatMap { ($0.rates ?? []).filter { !$0.isArchived } }
            let index = UserDefaults.standard.integer(forKey: "qa.tasa")
            if rates.indices.contains(index) { editingRate = rates[index] }
        }
        #endif
        #if os(macOS)
        .macReportInspector(title: macSelectedItem?.name ?? String(localized: "Tasas"), hasSelection: macSelectedItem != nil,
                            placeholder: String(localized: "Aún no hay tasas de impuesto. Añade una con «+» bajo la tabla."),
                            selectionKey: macPick, qaSelectRow: { index in
                                let items = macRateItems
                                if items.indices.contains(index) { macPick = items[index].key }
                            }) {
            if let item = macSelectedItem { rateInspector(item) }
        } actions: {
            SectionLink(item: .report(.salesTax)) { ReportsView(fixedKind: .salesTax) } label: { Text("Ver reporte") }
                .buttonStyle(.primary)
            if let item = macSelectedItem {
                if let rate = item.rate { Button("Editar tasa…") { editingRate = rate }.buttonStyle(.secondary) }
                if item.id == defaultTaxID {
                    Button("Quitar como predeterminada") { setDefault(nil) }.buttonStyle(.secondary)
                } else {
                    Button("Usar como predeterminada") { setDefault(item.id) }.buttonStyle(.secondary)
                }
            }
        }
        #endif
        // Después del inspector del Mac: dentro de él, la pila de la columna no veía el destino.
        .navigationDestination(isPresented: $showingDeductions) { DeductionsView() }
    }

    // MARK: Trimestre

    private func quarter(_ offset: Int) -> DateInterval {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .month, value: offset * 3, to: .now) ?? .now
        return calendar.dateInterval(of: .quarter, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// «T4 2026 · oct–dic».
    private func quarterTitle(_ interval: DateInterval) -> String {
        String(localized: "\(quarterName(interval)) · \(quarterMonths(interval))")
    }

    private func quarterName(_ interval: DateInterval) -> String {
        let number = (Calendar.current.component(.month, from: interval.start) - 1) / 3 + 1
        return String(localized: "T\(number) \(interval.start.formatted(.appDateTime.year()))")
    }

    /// «oct–dic».
    private func quarterMonths(_ interval: DateInterval) -> String {
        (interval.start..<interval.end.addingTimeInterval(-1)).formatted(.interval.month(.abbreviated).locale(.appText))
    }

    /// Fecha habitual de declaración: el día 20 del mes siguiente al trimestre (Texas y muchos estados).
    private func dueDate(_ interval: DateInterval) -> Date {
        Calendar.current.date(byAdding: .day, value: 19, to: interval.end) ?? interval.end
    }

    private func paid(in interval: DateInterval) -> Int64 {
        entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil && interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalDebits }
    }

    private func summary(_ interval: DateInterval) -> SalesTaxSummary? {
        try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1))
    }

    /// «T4 2026 · oct–dic ▾» (iPhone: subtítulo gris bajo el título; iPad: botón de la barra).
    private func quarterMenu(compact: Bool) -> some View {
        Menu {
            Picker("Trimestre", selection: $quarterOffset) {
                ForEach(0..<4) { index in Text(quarterTitle(quarter(-index))).tag(-index) }
            }
            .pickerStyle(.inline)
        } label: {
            if compact {
                HStack(spacing: 4) {
                    Text(quarterTitle(quarter(quarterOffset)))
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 6) { Image(systemName: "calendar"); Text(quarterTitle(quarter(quarterOffset))) }
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .headerButton()
        .accessibilityLabel("Trimestre")
        .accessibilityValue(quarterTitle(quarter(quarterOffset)))
    }

    // MARK: - iPhone (`Impuestos`)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Los deducibles llevan su propio periodo (el año): el trimestre del sales tax no les aplica.
            if tab != .deductions { quarterMenu(compact: true) }
            FilterPicker(title: String(localized: "Sección"), options: Tab.allCases, selection: $tab) { $0.localizedTitle }
                .padding(.top, 8)
            switch tab {
            case .summary: summaryTab
            case .rates: ratesTab
            case .deductions: DeductionsView(embedded: true)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 28)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// «Sales tax por pagar»: cifra grande, la fecha de la declaración y el pago.
    @ViewBuilder
    private var summaryTab: some View {
        let interval = quarter(quarterOffset)
        let position = SalesTaxPosition(liabilityBalance: payable)
        let due = dueDate(interval)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.title).font(.subheadline).foregroundStyle(Palette.ink2)
                Text(position.amount.money).font(.amount(36)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StatusDot(color: position.dotColor)
                    Text(position.detail)
                }
                .font(.footnote).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            if payable > 0 {
                Divider().padding(.leading, 16 + 38 + 12)
                TaxRow(title: String(localized: "Declarar y pagar"),
                       subtitle: String(localized: "Vence el \(due.shortDate)"), subtitleColor: due < .now ? Palette.negative : Palette.warning) {
                    DateTile(date: due)
                } trailing: {
                    Text(payable.money).monospacedDigit().foregroundStyle(Palette.ink)
                }
            }
            Divider().padding(.leading, 16)
            Button { showingPayment = true } label: {
                Label("Registrar pago de impuesto", systemImage: "checkmark.circle")
                    .foregroundStyle(payable > 0 ? Palette.brand : Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(payable <= 0)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .padding(.top, 16)

        if let summary = summary(interval) {
            groupLabel(String(localized: "Desglose · \(quarterMonths(interval)) \(interval.start.formatted(.appDateTime.year()))"))
            RowGroup {
                valueRow(String(localized: "Ventas gravables"), summary.taxableSales.money)
                valueRow(String(localized: "Ventas no gravables y exentas"), (summary.nonTaxableSales + summary.exemptSales).money)
                ForEach(summary.rows) { row in valueRow("\(row.name) · \(row.percent.formatted())%", row.tax.money) }
                valueRow(String(localized: "Cobrado en el periodo"), summary.totalTax.money, bold: true)
                valueRow(String(localized: "Pagado a la autoridad"), paid(in: interval).money)
            }
        }
        footer(String(localized: "El día 20 del mes siguiente es la fecha habitual en Texas y otros estados; confírmala con tu agencia."))

        let payments = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil }
        if !payments.isEmpty {
            groupLabel(String(localized: "Pagos a la agencia"))
            RowGroup {
                ForEach(payments.prefix(5)) { entry in
                    TaxRow(title: entry.memo, subtitle: entry.date.shortDate) {
                        EmptyView()
                    } trailing: {
                        Text(entry.totalDebits.money).monospacedDigit().foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        SectionLabel(text: text).padding(.horizontal, Metrics.gutter).padding(.top, 22).padding(.bottom, 7)
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2)
            .padding(.horizontal, Metrics.gutter).padding(.top, 7)
    }

    private func valueRow(_ title: String, _ value: String, bold: Bool = false) -> some View {
        AdaptiveRow {
            Text(title).foregroundStyle(Palette.ink)
        } trailing: {
            Text(value).fontWeight(bold ? .semibold : .regular).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Tasas

    @ViewBuilder
    private var ratesTab: some View {
        if let errorMessage { ErrorBanner(message: errorMessage).padding(.top, 12) }
        HStack(alignment: .lastTextBaseline) {
            groupLabel(String(localized: "Tasas de impuesto"))
            Spacer(minLength: 8)
            TermHelp(.combinedRate, showsTerm: true).padding(.trailing, Metrics.gutter - 12)
        }
        RowGroup {
            ForEach(groups.filter { !$0.isArchived }) { group in
                let kind = String(localized: "Combinada · \((group.rates ?? []).count) tasas")
                rateRow(group.name, group.id == defaultTaxID ? String(localized: "\(kind) · predeterminada") : kind, group.percent)
                    .contextMenu { defaultButton(group.id) }
            }
            ForEach(agencies) { agency in
                ForEach((agency.rates ?? []).filter { !$0.isArchived }) { rate in
                    let kind = String(localized: "Componente · \(agency.name)")
                    Button { editingRate = rate } label: {
                        rateRow(rate.name, rate.id == defaultTaxID ? String(localized: "\(kind) · predeterminada") : kind, rate.percent,
                                chevron: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Editar tasa")
                    .contextMenu {
                        Button("Editar tasa…", systemImage: "pencil") { editingRate = rate }
                        defaultButton(rate.id)
                    }
                }
            }
            linkRow(String(localized: "Nueva tasa"), "plus") { showingRate = true }
            linkRow(String(localized: "Nuevo grupo"), "square.stack") { showingGroup = true }
                .disabled(agencies.flatMap { $0.rates ?? [] }.isEmpty)
        }
        footer(defaultTaxName.map { name in
            groups.contains { $0.id == defaultTaxID }
                ? String(localized: "\(name) es la tasa predeterminada en facturas nuevas.")
                // Solo la tasa estatal del alta: cómo sumar la local en un paso.
                : String(localized: "\(name) es la tasa predeterminada en facturas nuevas. Si tu ciudad o condado cobra más, elige «Nueva tasa» y escribe solo su parte: la sumamos a esta.")
        } ?? String(localized: "Escribe las tasas de tu estado, condado y ciudad. Chirogra no determina qué es gravable: consúltalo con tu agencia o tu contador."))

        if let company {
            groupLabel(String(localized: "Facturas nuevas"))
            RowGroup {
                TaxDefaultsRows(company: company, groups: groups, agencies: agencies, onDefault: setDefault)
            }
            footer(String(localized: "Con impuesto incluido, el precio de cada línea ya lleva el impuesto y Chirogra lo separa al emitir. El origen de las ventas es informativo: tú eliges la tasa de cada factura."))
        }

        if !agencies.isEmpty {
            groupLabel(String(localized: "Periodo de declaración"))
            RowGroup {
                ForEach(agencies) { agency in
                    AdaptiveRow {
                        Text(agency.name).foregroundStyle(Palette.ink)
                    } trailing: {
                        Picker(agency.name, selection: Binding(
                            get: { FilingFrequency(rawValue: agency.filingFrequencyRaw) ?? .quarterly },
                            set: { agency.filingFrequencyRaw = $0.rawValue; try? context.save() })) {
                            ForEach(FilingFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Palette.ink2)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                }
            }
        }
    }

    private func rateRow(_ name: String, _ kind: String, _ percent: Decimal, chevron: Bool = false) -> some View {
        TaxRow(title: name, subtitle: kind) {
            EmptyView()
        } trailing: {
            HStack(spacing: 8) {
                Text("\(percent.formatted())%").monospacedDigit().foregroundStyle(Palette.ink2)
                if chevron {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// «Usar como predeterminada» / «Quitar como predeterminada» (menú contextual y botones del inspector).
    @ViewBuilder
    private func defaultButton(_ id: UUID) -> some View {
        if id == defaultTaxID {
            Button("Quitar como predeterminada", systemImage: "star.slash") { setDefault(nil) }
        } else {
            Button("Usar como predeterminada", systemImage: "star") { setDefault(id) }
        }
    }

    /// Fila-acción en Tinta con su símbolo («Nueva tasa»), como las del canvas.
    private func linkRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(Palette.brand)
                .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - iPad y Mac (`MacImpuestos`)

    /// Cuatro cifras (cobrado, pagado, saldo y fecha límite), las tasas con lo cobrado en el trimestre y los pagos a la
    /// agencia; a la derecha, «Gastos deducibles» del año (fase 2) encima de «Facturas nuevas» y los pagos.
    private var wideBody: some View {
        let interval = quarter(quarterOffset)
        let summary = summary(interval)
        let paid = paid(in: interval)
        let due = dueDate(interval)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
        let settled = payable <= 0
        return VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
            Text(String(localized: "\(quarterTitle(interval)) · declaración trimestral")).font(.subheadline).foregroundStyle(Palette.ink2)
                .padding(.horizontal, 8)
            #endif
            KPIGrid(items: [
                KPIItem(title: String(localized: "Impuesto cobrado"), value: (summary?.totalTax ?? 0).money,
                        foot: String(localized: "Sobre \((summary?.taxableSales ?? 0).money) gravables")),
                KPIItem(title: String(localized: "Pagado"), value: paid.money,
                        foot: paid > 0 ? String(localized: "Pagos del trimestre") : String(localized: "Sin pagos en el trimestre")),
                KPIItem(title: String(localized: "Saldo por pagar"), value: max(payable, 0).money,
                        foot: settled ? String(localized: "Al día") : String(localized: "Pendiente"),
                        footColor: settled ? Palette.positive : Palette.warning),
                KPIItem(title: String(localized: "Fecha límite"), value: due.shortDate,
                        foot: days >= 0 ? String(localized: "Faltan \(days) días") : String(localized: "Venció hace \(-days) días"),
                        footColor: days < 0 ? Palette.negative : Palette.warning),
            ], large: true)
            let sideBySide = width - 40 >= 820
            let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
            if let errorMessage { ErrorBanner(message: errorMessage) }
            layout {
                ratesTable(summary, interval: interval).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 16) {
                    deductionsCard
                    defaultsCard
                    paymentsCard
                }
                .frame(width: sideBySide ? 320 : nil)
            }
            Text("El día 20 del mes siguiente es la fecha habitual en Texas y otros estados; confírmala con tu agencia.")
                .font(.footnote).foregroundStyle(Palette.ink2).padding(.horizontal, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8).padding(.bottom, 28)
    }

    /// Grupos («Combinada») y tasas de cada agencia con lo cobrado en el trimestre; «+» para añadir.
    private func ratesTable(_ summary: SalesTaxSummary?, interval: DateInterval) -> some View {
        let collected = Dictionary((summary?.rows ?? []).compactMap { row in row.rateID.map { ($0, row.tax) } }, uniquingKeysWith: +)
        let number = (Calendar.current.component(.month, from: interval.start) - 1) / 3 + 1
        let activeGroups = groups.filter { !$0.isArchived }
        let rates = agencies.flatMap { agency in (agency.rates ?? []).filter { !$0.isArchived }.map { (agency, $0) } }
        #if os(macOS)
        let picked = macSelectedItem?.key
        #else
        let picked: String? = nil
        #endif
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tasas por jurisdicción").font(.cardTitle).accessibilityAddTraits(.isHeader)
                TermHelp(.combinedRate, showsTerm: true)
                Spacer(minLength: 8)
                Text("\(activeGroups.count + rates.count) tasas").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 2)
            TableCard {
                Text("Nombre").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tipo").frame(width: 150, alignment: .leading)
                Text("Tasa").frame(width: 64, alignment: .trailing)
                Text("T\(number) cobrado").frame(width: 110, alignment: .trailing)
            } rows: {
                ForEach(Array(activeGroups.enumerated()), id: \.element.id) { index, group in
                    rateTableRow(group.name, kind: String(localized: "Combinada"), percent: group.percent,
                                 collected: (group.rates ?? []).reduce(0) { $0 + (collected[$1.id] ?? 0) }, bold: true,
                                 key: "group:\(group.id)", index: index, picked: picked, id: group.id, rate: nil)
                }
                ForEach(Array(rates.enumerated()), id: \.element.1.id) { index, item in
                    rateTableRow(item.1.name, kind: item.0.name, percent: item.1.percent, collected: collected[item.1.id] ?? 0, bold: false,
                                 key: "rate:\(item.1.id)", index: index + activeGroups.count, picked: picked, id: item.1.id, rate: item.1)
                }
                if activeGroups.isEmpty && rates.isEmpty {
                    Text("Sin tasas todavía").font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Menu {
                            Button("Nueva tasa", systemImage: "percent") { showingRate = true }
                            Button("Nuevo grupo", systemImage: "square.stack") { showingGroup = true }
                                .disabled(rates.isEmpty)
                        } label: {
                            Label("Añadir tasa", systemImage: "plus").labelStyle(.iconOnly)
                                .frame(minWidth: Metrics.target, minHeight: Metrics.target)
                                .contentShape(Rectangle())
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .background(Palette.surface)
                }
            }
        }
    }

    /// Fila de la tabla de tasas; en el Mac se elige con un clic para verla en el inspector (`MacReportRow`).
    @ViewBuilder
    private func rateTableRow(_ name: String, kind: String, percent: Decimal, collected: Int64, bold: Bool,
                              key: String, index: Int, picked: String?, id: UUID, rate: TaxRate?) -> some View {
        let isDefault = id == defaultTaxID
        #if os(macOS)
        MacReportRow(isSelected: key == picked, zebra: !index.isMultiple(of: 2), select: { macPick = key }) {
            rateCells(name, kind: kind, percent: percent, collected: collected, bold: bold, isDefault: isDefault)
        }
        .contextMenu { rateMenu(id: id, rate: rate) }
        #else
        Button { if let rate { editingRate = rate } } label: {
            TableRow { rateCells(name, kind: kind, percent: percent, collected: collected, bold: bold, isDefault: isDefault) }
                .zebra(index)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rateMenu(id: id, rate: rate) }
        #endif
    }

    @ViewBuilder
    private func rateMenu(id: UUID, rate: TaxRate?) -> some View {
        if let rate { Button("Editar tasa…", systemImage: "pencil") { editingRate = rate } }
        defaultButton(id)
    }

    @ViewBuilder
    private func rateCells(_ name: String, kind: String, percent: Decimal, collected: Int64, bold: Bool, isDefault: Bool) -> some View {
        HStack(spacing: 6) {
            Text(name).fontWeight(bold || isDefault ? .semibold : .regular).lineLimit(1)
            if isDefault { ReportCellText(text: String(localized: "· Predeterminada")).font(.subheadline).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        ReportCellText(text: kind).lineLimit(1).frame(width: 150, alignment: .leading)
        Text("\(percent.formatted())%").frame(width: 64, alignment: .trailing)
        Text(collected.money).frame(width: 110, alignment: .trailing)
    }

    // MARK: Inspector del Mac

    #if os(macOS)
    /// Una fila de la tabla de tasas: un grupo (tasa combinada) o una tasa de una agencia.
    struct MacRateItem {
        let key: String
        let name: String
        let percent: Decimal
        /// Agencia de la tasa; `nil` en un grupo.
        let agency: String?
        /// Tasas del grupo; vacío en una tasa suelta.
        let components: [TaxRate]
        let collected: Int64
        /// Id del grupo o de la tasa (el que se guarda como predeterminado).
        let id: UUID
        /// La tasa, para «Editar tasa…»; `nil` en un grupo.
        let rate: TaxRate?
    }

    /// En el orden de la tabla: los grupos y después las tasas de cada agencia.
    private var macRateItems: [MacRateItem] {
        let summary = summary(quarter(quarterOffset))
        let collected = Dictionary((summary?.rows ?? []).compactMap { row in row.rateID.map { ($0, row.tax) } }, uniquingKeysWith: +)
        let groupItems = groups.filter { !$0.isArchived }.map { group in
            MacRateItem(key: "group:\(group.id)", name: group.name, percent: group.percent, agency: nil, components: group.rates ?? [],
                        collected: (group.rates ?? []).reduce(0) { $0 + (collected[$1.id] ?? 0) }, id: group.id, rate: nil)
        }
        let rateItems = agencies.flatMap { agency in
            (agency.rates ?? []).filter { !$0.isArchived }.map { rate in
                MacRateItem(key: "rate:\(rate.id)", name: rate.name, percent: rate.percent, agency: agency.name, components: [],
                            collected: collected[rate.id] ?? 0, id: rate.id, rate: rate)
            }
        }
        return groupItems + rateItems
    }

    /// Lo elegido o, sin elegir, la primera fila (como el canvas).
    private var macSelectedItem: MacRateItem? {
        let items = macRateItems
        return items.first { $0.key == macPick } ?? items.first
    }

    /// La tasa con su porcentaje y su tipo, lo cobrado en el trimestre y la declaración del trimestre.
    @ViewBuilder
    private func rateInspector(_ item: MacRateItem) -> some View {
        let interval = quarter(quarterOffset)
        let summary = summary(interval)
        let due = dueDate(interval)
        let isGroup = item.agency == nil
        MacReportFigure(caption: String(localized: "Tasa de impuesto sobre ventas"), amount: "\(item.percent.formatted())%") {
            Text(isGroup ? String(localized: "Combinada · \(item.components.count) tasas") : String(localized: "Componente · \(item.agency ?? "")"))
                .foregroundStyle(Palette.ink2)
        }
        MacInspectorSection(title: String(localized: "Tasa elegida")) {
            MacInspectorRow(String(localized: "Nombre"), value: item.name)
            MacInspectorRow(String(localized: "Tipo"), value: isGroup ? String(localized: "Combinada") : String(localized: "Componente"))
            if let agency = item.agency { MacInspectorRow(String(localized: "Agencia"), value: agency) }
            MacInspectorRow(String(localized: "Predeterminada"), value: item.id == defaultTaxID ? String(localized: "Sí") : String(localized: "No"))
            MacInspectorRow(String(localized: "Cobrado en \(quarterName(interval))"), value: item.collected.money)
        }
        if isGroup && !item.components.isEmpty {
            MacInspectorSection(title: String(localized: "Tasas incluidas")) {
                ForEach(item.components) { rate in
                    MacInspectorRow(rate.name, value: "\(rate.percent.formatted())%")
                }
            }
        }
        MacInspectorSection(title: String(localized: "Declaración \(quarterName(interval))")) {
            MacInspectorRow(String(localized: "Cobrado"), value: (summary?.totalTax ?? 0).money)
            MacInspectorRow(String(localized: "Pagado"), value: paid(in: interval).money)
            MacInspectorRow(String(localized: "Saldo por pagar"), value: max(payable, 0).money, bold: true)
            MacInspectorRow(String(localized: "Fecha límite"), value: due.shortDate)
        }
    }
    #endif

    /// «Facturas nuevas» (iPad y Mac): impuesto predeterminado, impuesto incluido y origen de las ventas.
    @ViewBuilder
    private var defaultsCard: some View {
        if let company {
            VStack(alignment: .leading, spacing: 0) {
                Text("Facturas nuevas").font(.cardTitle).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                TaxDefaultsRows(company: company, groups: groups, agencies: agencies, onDefault: setDefault, dividers: true)
                Text("El origen es informativo: tú eliges la tasa de cada factura.")
                    .font(.footnote).foregroundStyle(Palette.ink2).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 14)
        }
    }

    /// Deducibles del año en curso (canvas `MacImpuestos` · «Gastos deducibles 2026»): el total, las líneas con más
    /// importe con su barra, «Ver por línea» y «Exportar para mi contador…».
    private var deductionsSummary: TaxFormSummary? {
        guard let form = company.flatMap({ TaxForm.forEntity($0.entityType) }) else { return nil }
        let range = DeductionsPeriod.yearToDate.range()
        let key = "\(basis.rawValue)|\(journalLines.count)|\(accounts.map(\.taxFormLineRaw).joined().hashValue)"
        return deductionsMemo.value(for: key) {
            try? Bookkeeper(context: context).taxSummary(from: range.from, to: range.to, basis: basis, form: form)
        }
    }

    private var deductionsCard: some View {
        let summary = deductionsSummary
        let rows = (summary?.rows ?? []).filter { $0.line.kind == .deduction }.sorted { $0.deductibleAmount > $1.deductibleAmount }
        let top = max(1, rows.first?.deductibleAmount ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gastos deducibles \(Date.now.formatted(.appDateTime.year()))").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text((summary?.totalDeductions ?? 0).money).font(.cardTitle).monospacedDigit()
            }
            .padding(.bottom, 6)
            if summary == nil {
                Text("Sin formulario para este tipo de empresa: exporta el paquete para tu contador.")
                    .font(.subheadline).foregroundStyle(Palette.ink2).padding(.vertical, 6)
            }
            ForEach(rows.prefix(6)) { row in
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.line.name(for: .appText)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.deductibleAmount.money).fontWeight(.semibold).monospacedDigit()
                    }
                    Capsule().fill(Palette.surface2).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(Palette.brand).frame(width: proxy.size.width * CGFloat(max(0, row.deductibleAmount)) / CGFloat(top))
                            }
                        }
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                Button("Ver por línea") { showingDeductions = true }.buttonStyle(.secondary).disabled(summary == nil)
                Button("Exportar para mi contador…") { exportingPackage = true }.buttonStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .card(padding: 14)
    }

    private var paymentsCard: some View {
        let payments = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Pagos a la agencia").font(.cardTitle).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            if payments.isEmpty {
                Text("Sin pagos registrados").font(.subheadline).foregroundStyle(Palette.ink2).padding(.vertical, 8)
            }
            ForEach(payments.prefix(8)) { entry in
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.memo).lineLimit(2)
                        Text(entry.date.shortDate).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 8)
                    Text(entry.totalDebits.money).fontWeight(.semibold).monospacedDigit()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 14)
    }
}

// MARK: - Piezas

/// Ajustes de impuesto de la empresa para las facturas nuevas: «Impuesto predeterminado» (un grupo o una tasa;
/// `setDefaultTax`), «Precios con impuesto incluido» (`Company.pricesIncludeTax`; cada factura copia el valor al
/// crearse, así que las emitidas no cambian) y «Origen de ventas» (origen o destino, informativo).
private struct TaxDefaultsRows: View {
    let company: Company
    let groups: [TaxGroup]
    let agencies: [TaxAgency]
    let onDefault: (UUID?) -> Void
    /// Con líneas entre filas (caja del Mac y del iPad); en el iPhone las pone `RowGroup`.
    var dividers = false
    @Environment(\.modelContext) private var context

    var body: some View {
        row(String(localized: "Impuesto predeterminado")) {
            Picker("Impuesto predeterminado", selection: Binding(get: { company.defaultTaxGroupID }, set: onDefault)) {
                Text("Ninguno").tag(UUID?.none)
                let activeGroups = groups.filter { !$0.isArchived }
                if !activeGroups.isEmpty {
                    Section(heading: String(localized: "Combinadas")) {
                        ForEach(activeGroups) { Text(verbatim: "\($0.name) · \($0.percent.formatted())%").tag(Optional($0.id)) }
                    }
                }
                ForEach(agencies) { agency in
                    let rates = (agency.rates ?? []).filter { !$0.isArchived }
                    if !rates.isEmpty {
                        Section(heading: agency.name) {
                            ForEach(rates) { Text(verbatim: "\($0.name) · \($0.percent.formatted())%").tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .pickerStyle(.menu)
        }
        if dividers { Divider() }
        // El texto a la izquierda y el interruptor a su derecha, como en Ajustes: en la caja de 320 pt del iPad el
        // `Toggle` con su etiqueta bajaba el interruptor a otra línea.
        AdaptiveRow {
            Text("Precios con impuesto incluido").foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        } trailing: {
            Toggle("Precios con impuesto incluido", isOn: Binding(get: { company.pricesIncludeTax }, set: {
                company.pricesIncludeTax = $0
                try? context.save()
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Palette.green)
        }
        .padding(.horizontal, dividers ? 0 : 16).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
        if dividers { Divider() }
        row(String(localized: "Origen de ventas")) {
            Picker("Origen de ventas", selection: Binding(get: { company.salesTaxSourcing }, set: {
                company.salesTaxSourcing = $0
                try? context.save()
            })) {
                ForEach(SalesTaxSourcing.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    /// Fila con su etiqueta a la izquierda y el menú a la derecha (un `Picker` de menú fuera de un `Form` solo muestra
    /// el valor). Si no caben en una línea (caja de 320 pt del iPad, letra de accesibilidad), la etiqueta va arriba y el
    /// menú debajo: al lado de un menú ancho la etiqueta se partía a media palabra («predetermi-nado»).
    private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        let menu = content().labelsHidden().fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).foregroundStyle(Palette.ink).fixedSize()
                Spacer(minLength: 8)
                menu
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                // El menú de iOS 26 lleva 12 pt de margen dentro: así el valor queda alineado con la etiqueta.
                menu.padding(.leading, -12)
                #else
                menu
                #endif
            }
        }
        .padding(.horizontal, dividers ? 0 : 16).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension SalesTaxSourcing {
    var title: String {
        switch self {
        case .origin: String(localized: "Origen (tu negocio)")
        case .destination: String(localized: "Destino (el cliente)")
        }
    }
}

/// Fila de dos líneas con algo a la izquierda (hoja de calendario) y un valor a la derecha; con letra de
/// accesibilidad, en columna.
private struct TaxRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = Palette.ink2
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Palette.ink)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(subtitleColor) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}

extension FilingFrequency {
    var title: String {
        switch self {
        case .monthly: String(localized: "Mensual")
        case .quarterly: String(localized: "Trimestral")
        case .annual: String(localized: "Anual")
        }
    }
}

extension SalesTaxPosition {
    var dotColor: Color {
        switch self {
        case .owed: Palette.orange
        case .settled: Palette.green
        case .credit: Palette.blue
        }
    }
}

/// Alta o edición de una tasa (canvas `MacImpuestos`, «Editar tasa…»): nombre, porcentaje y agencia. Al editar pasa por
/// `Bookkeeper.updateTaxRate`: las facturas ya emitidas guardan su impuesto y no cambian; los borradores toman la tasa
/// nueva al emitirse.
///
/// Una tasa nueva pasa por `Bookkeeper.addTaxRate` y, en un paso, decide qué cobran las facturas nuevas (recorrido
/// «cliente nuevo», 5-nov: antes hacían falta tres pantallas para cobrar el 8.25 % de Austin): si ya hay un impuesto
/// predeterminado (la tasa estatal del alta), «Sumar a Texas (6.25 %)…» viene encendido y al guardar crea el grupo
/// combinado («Austin, TX» 8.25 %) y lo deja como predeterminado; sin predeterminado, «Usarla en las facturas nuevas».
/// El pie dice lo que cobrarán las facturas. La agencia viene elegida (la del predeterminado o la del estado).
/// Se usa también desde la factura («Añadir tasa…», `onSaved`), que solo la ofrece cuando no hay ninguna tasa.
struct TaxRateEditorView: View {
    /// Tasa que se edita; `nil` para una nueva.
    let rate: TaxRate?
    /// Tras guardar una tasa nueva (la factura la deja elegida, build 4).
    var onSaved: ((TaxRate) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @ActiveCompanyQuery private var companies: [Company]
    /// Para que el predeterminado (`defaultCode`) se recalcule si cambian las tasas o los grupos.
    @CompanyQuery private var allRates: [TaxRate]
    @CompanyQuery private var allGroups: [TaxGroup]

    @State private var agencyID: UUID?
    /// La agencia ya se preeligió al abrir (una vez).
    @State private var agencyPreset = false
    /// Sumarla al predeterminado (o, sin él, usarla sola) en las facturas nuevas.
    @State private var useOnNewInvoices = true
    @State private var newAgencyName = ""
    @State private var name: String
    /// Vacío al crear: el campo muestra su marcador en vez de un «0».
    @State private var percent: Decimal?
    @State private var errorMessage: String?

    init(rate: TaxRate? = nil, onSaved: ((TaxRate) -> Void)? = nil) {
        self.rate = rate
        self.onSaved = onSaved
        _agencyID = State(initialValue: rate?.agency?.id)
        _name = State(initialValue: rate?.name ?? "")
        _percent = State(initialValue: rate?.percent)
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                TextField("Nombre", text: $name, prompt: Text(rate == nil && defaultCode != nil ? "Ciudad o condado (p. ej. Austin)" : "Nombre (p. ej. Travis County)"))
                    .accessibilityLabel(Text("Nombre"))
                TextField("Porcentaje", value: $percent, format: .number.precision(.fractionLength(0...4)), prompt: Text("Porcentaje (p. ej. 2)"))
                    .accessibilityLabel(Text("Porcentaje"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            } header: {
                SectionLabel(text: String(localized: "Tasa"))
            } footer: {
                if rate != nil {
                    Label("Las facturas ya emitidas conservan su impuesto y no cambian. Los borradores y las facturas nuevas usarán la tasa nueva.",
                          systemImage: "info.circle")
                } else if defaultCode != nil {
                    Text("Escribe solo la parte de tu ciudad, condado o distrito (en Austin, 2%). Si no la sabes, búscala con tu dirección en la web de impuestos de tu estado.")
                } else {
                    Text("Escribe el porcentaje que cobras. Si cobras varias tasas (estado, condado, ciudad), puedes poner el total o crear una por cada una y juntarlas en un grupo.")
                }
            }
            if rate == nil { useSection }
            Section {
                Picker("Agencia", selection: $agencyID) {
                    ForEach(agencies) { Text($0.name).tag(Optional($0.id)) }
                    Text("Nueva agencia…").tag(UUID?.none)
                }
                if agencyID == nil {
                    TextField("Nombre de la agencia", text: $newAgencyName, prompt: Text("Nombre (p. ej. Texas Comptroller)"))
                        .accessibilityLabel(Text("Nombre de la agencia"))
                }
            } header: {
                SectionLabel(text: String(localized: "Agencia"))
            } footer: {
                if rate == nil {
                    Text("A quién le declaras y pagas esta tasa. En muchos estados, como Texas, la agencia del estado cobra también las tasas locales.")
                }
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle(rate == nil ? "Nueva tasa" : "Editar tasa")
        .inlineTitle()
        .onAppear(perform: presetAgency)
        .discardableEditor(tracking: "\(agencyID?.uuidString ?? "")|\(newAgencyName)|\(name)|\(percent.map { "\($0)" } ?? "")|\(useOnNewInvoices)",
                           token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(!canSave)
                    .headerButton()
            }
        }
    }

    // MARK: Qué cobran las facturas nuevas

    /// Impuesto predeterminado de la empresa (la tasa estatal del alta, o un grupo).
    private var defaultCode: TaxCodeSummary? {
        _ = (allRates.count, allGroups.count, companies.first?.defaultTaxGroupID)
        return try? Bookkeeper(context: context).defaultTaxCode()
    }

    /// Porcentaje escrito en millonésimas, si es válido (más de 0 y hasta 100).
    private var millionths: Int64? {
        guard let percent, percent > 0, percent <= 100 else { return nil }
        return TaxComponent.millionths(fromPercent: percent)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && millionths != nil
            && !(agencyID == nil && newAgencyName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private var useSection: some View {
        let base = defaultCode
        let title = base.map {
            String(localized: "Sumar a \($0.name) (\(StateTaxNote.percent($0.rateMillionths))) y usarla en las facturas nuevas")
        } ?? String(localized: "Usarla en las facturas nuevas")
        Section {
            // El texto a la izquierda y el interruptor a su derecha (con la etiqueta larga, el `Toggle` bajaba el
            // interruptor a otra línea); tocar el texto también lo cambia.
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { useOnNewInvoices.toggle() }
                    .accessibilityHidden(true)
                Toggle(title, isOn: $useOnNewInvoices)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Palette.green)
            }
            .frame(minHeight: Metrics.target)
        } footer: {
            Text(useFooter(base))
        }
    }

    /// «Tus facturas nuevas cobrarán 8.25 %…»: lo que cobrarán según el interruptor y el porcentaje escrito.
    private func useFooter(_ base: TaxCodeSummary?) -> String {
        let local = name.trimmingCharacters(in: .whitespaces)
        guard useOnNewInvoices else {
            if let base {
                return String(localized: "Tus facturas nuevas seguirán cobrando \(StateTaxNote.percent(base.rateMillionths)) (\(base.name)). Podrás elegir esta tasa en cada factura.")
            }
            return String(localized: "Tus facturas nuevas seguirán sin impuesto. Podrás elegir esta tasa en cada factura.")
        }
        guard let base else {
            guard let millionths else { return String(localized: "Tus facturas nuevas cobrarán esta tasa.") }
            return String(localized: "Tus facturas nuevas cobrarán \(StateTaxNote.percent(millionths)).")
        }
        guard let millionths else {
            return String(localized: "Tus facturas nuevas cobrarán \(StateTaxNote.percent(base.rateMillionths)) más esta tasa.")
        }
        let total = StateTaxNote.percent(base.rateMillionths + millionths)
        guard !local.isEmpty else { return String(localized: "Tus facturas nuevas cobrarán \(total).") }
        let group = Bookkeeper(context: context).combinedTaxName(base: base, adding: local, state: companies.first?.state ?? "")
        return String(localized: "Tus facturas nuevas cobrarán \(total) (\(base.name) \(StateTaxNote.percent(base.rateMillionths)) + \(local) \(StateTaxNote.percent(millionths))). Las juntamos en el grupo «\(group)», que verás en Impuestos.")
    }

    /// Una tasa nueva viene con la agencia ya elegida: la del impuesto predeterminado, la del estado o la primera.
    private func presetAgency() {
        guard rate == nil, !agencyPreset else { return }
        agencyPreset = true
        let stateAgency = StateSalesTax.forState(companies.first?.state ?? "")?.agency
        agencyID = defaultCode?.rates.first?.agency?.id
            ?? agencies.first { $0.name == stateAgency && !$0.isArchived }?.id
            ?? agencies.first { !$0.isArchived }?.id
    }

    private func save() {
        do {
            guard let millionths else { return }
            let books = Bookkeeper(context: context)
            let agency = agencies.first { $0.id == agencyID }
            if let rate {
                let owner: TaxAgency
                if let agency {
                    owner = agency
                } else {
                    let liability = try books.systemAccount(.salesTaxPayable)
                    owner = TaxAgency(name: newAgencyName.trimmingCharacters(in: .whitespaces), liabilityAccountID: liability.id)
                    Bookkeeper(context: context).insert(owner)
                }
                try books.updateTaxRate(rate, name: name, agency: owner, rateMillionths: millionths)
            } else {
                let use: NewTaxRateUse = useOnNewInvoices ? .addToDefault : .keep
                let created = try books.addTaxRate(name: name, rateMillionths: millionths, agency: agency,
                                                   newAgencyName: newAgencyName, use: use)
                onSaved?(created.rate)
            }
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Grupo de tasas (tasa combinada): nombre y las tasas que suma. Tocar la fila entera enciende o apaga la tasa.
struct TaxGroupEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \TaxRate.name) private var rates: [TaxRate]
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        Form {
            TextField("Nombre (p. ej. Austin, TX)", text: $name)
            Section(title: "Tasas incluidas") {
                ForEach(rates.filter { !$0.isArchived }) { rate in
                    // Tocar la fila entera enciende o apaga la tasa (antes solo respondía el interruptor).
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Text(rate.name).foregroundStyle(Palette.ink)
                            Text("\(rate.percent.formatted())%").foregroundStyle(Palette.ink2).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(rate.id) }
                        .accessibilityHidden(true)
                        Toggle(isOn: binding(for: rate.id)) { Text(verbatim: "\(rate.name), \(rate.percent.formatted())%") }
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
            LabeledContent {
                Text("\((Decimal(rates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.rateMillionths }) / 10_000).formatted())%")
            } label: {
                HStack(spacing: 0) {
                    Text("Tasa combinada")
                    TermHelp(.combinedRate)
                }
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle("Nuevo grupo")
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|" + selected.map(\.uuidString).sorted().joined(separator: ","), token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Bookkeeper(context: context).insert(TaxGroup(name: name, rates: rates.filter { selected.contains($0.id) }))
                    try? context.save()
                    unsavedChanges?.remove(editorToken); dismiss()
                }
                .disabled(name.isEmpty || selected.isEmpty)
                .headerButton()
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

/// Registrar el pago del sales tax cobrado a la agencia (Debe Sales Tax Payable / Haber Banco).
struct SalesTaxPaymentView: View {
    let owed: Int64
    /// Importe propuesto (el saldo de la agencia en el inspector del Mac); sin él, lo pendiente según libros.
    private let suggestedAmount: Int64?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var agencyID: UUID?
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var reference = ""
    @State private var errorMessage: String?
    /// Pago con fecha en un periodo cerrado: se pide la contraseña de cierre y se repite.
    @State private var closedPeriodRetry: ClosedPeriodRetry?

    /// `agencyID` y `amount`: la agencia y el importe ya elegidos (inspector de `MacSalesTax`).
    init(owed: Int64, agencyID: UUID? = nil, amount: Int64? = nil) {
        self.owed = owed
        suggestedAmount = amount
        _agencyID = State(initialValue: agencyID)
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Picker("Agencia", selection: $agencyID) {
                    Text("Sin agencia").tag(UUID?.none)
                    ForEach(agencies) { Text($0.name).tag(Optional($0.id)) }
                }
                LabeledContent("Pendiente según libros", value: owed.money)
            }
            Section {
                MoneyField(title: String(localized: "Importe pagado"), minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagado desde"), accounts: accounts.filtered { $0 == .bank || $0 == .cash }, selection: $accountID)
                TextField("Periodo o referencia (p. ej. Q3 2026)", text: $reference)
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Pago de sales tax")
        .inlineTitle()
        .discardableEditor(tracking: "\(agencyID?.uuidString ?? "")|\(amount)|\(date)|\(accountID?.uuidString ?? "")|\(reference)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Registrar", action: save).disabled(amount <= 0 || accountID == nil).headerButton() }
        }
        .closedPeriodUnlock($closedPeriodRetry) { errorMessage = $0 }
        .onAppear {
            amount = suggestedAmount ?? owed
            agencyID = agencyID ?? agencies.first?.id
            accountID = accountID ?? accounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        let agency = agencies.first { $0.id == agencyID }
        let (amount, date, reference) = (amount, date, reference)
        let pay: (Bookkeeper) throws -> Void = { books in
            try books.paySalesTax(to: agency, amount: amount, date: date, from: account, reference: reference)
            unsavedChanges?.remove(editorToken); dismiss()
        }
        do {
            try pay(Bookkeeper(context: context))
        } catch {
            if let lock = PeriodClosing.lockDate(of: error) {
                closedPeriodRetry = ClosedPeriodRetry(lockDate: lock, perform: pay)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension SalesTaxPosition {
    var title: String {
        switch self {
        case .owed: String(localized: "Sales tax por pagar")
        case .settled: String(localized: "Sales tax al día")
        case .credit: String(localized: "Sales tax a favor")
        }
    }

    var detail: String {
        switch self {
        case .owed, .settled: String(localized: "Saldo de la cuenta según libros")
        case .credit: String(localized: "Pagaste más de lo cobrado (p. ej. por una nota de crédito): se descuenta de la próxima declaración")
        }
    }
}

