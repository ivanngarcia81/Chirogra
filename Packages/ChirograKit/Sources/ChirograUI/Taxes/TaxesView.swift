import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Impuestos (canvas `Impuestos`): Resumen del trimestre elegido (lo que se debe, cuándo, desglose y pago) y Tasas.
/// «Deducibles» del canvas no está en el MVP.
struct TaxesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Resumen", rates = "Tasas"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @Query(sort: \TaxGroup.name) private var groups: [TaxGroup]
    @Query private var taxLines: [InvoiceTaxLine]
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    @State var tab: Tab = .summary
    /// Trimestre mostrado: 0 el actual, −1 el anterior…
    @State private var quarterOffset = 0
    @State private var showingRate = false
    @State private var showingPayment = false
    @State private var showingGroup = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacImpuestos` en iPad y Mac (hasta AX3); las pestañas del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let payable = accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
        let _ = taxLines.count   // se observa para recalcular el resumen al emitir facturas
        Group {
            if isWide { wideBody(payable: payable) } else { compactBody(payable: payable) }
        }
        .background(Palette.background)
        .navigationTitle("Impuestos")
        .headerTitle()
        .sheet(isPresented: $showingRate) { NavigationStack { TaxRateEditorView() } }
        .sheet(isPresented: $showingPayment) { NavigationStack { SalesTaxPaymentView(owed: payable) } }
        .sheet(isPresented: $showingGroup) { NavigationStack { TaxGroupEditorView() } }
    }

    private func compactBody(payable: Int64) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                Picker("Sección", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch tab {
                case .summary: summary(payable: payable)
                case .rates: ratesTab
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: iPad y Mac (`MacImpuestos`)

    /// Trimestre, cuatro cifras (cobrado, pagado, saldo y fecha límite), tasas con lo cobrado en el trimestre y los
    /// pagos a la agencia. «Gastos deducibles» del canvas es de la fase 2.
    private func wideBody(payable: Int64) -> some View {
        let interval = quarter(quarterOffset)
        let summary = try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1))
        let paid = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil && interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalDebits }
        let due = dueDate(interval)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    quarterMenu(interval)
                    Text("Declaración trimestral").font(.subheadline).foregroundStyle(Palette.ink3)
                }
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Impuesto cobrado"), value: (summary?.totalTax ?? 0).money,
                            foot: String(localized: "sobre \((summary?.taxableSales ?? 0).money) gravables")),
                    KPIItem(title: String(localized: "Pagado"), value: paid.money),
                    KPIItem(title: String(localized: "Saldo por pagar"), value: max(payable, 0).money, isBrand: true),
                    KPIItem(title: String(localized: "Fecha límite"), value: due.shortDate,
                            foot: days >= 0 ? String(localized: "Faltan \(days) días") : String(localized: "Venció hace \(-days) días"),
                            footColor: days < 15 ? Palette.warning : Palette.ink3),
                ])
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ratesTable(summary, interval: interval).frame(maxWidth: .infinity)
                        paymentsCard.frame(width: 340)
                    }
                    VStack(spacing: 16) { ratesTable(summary, interval: interval); paymentsCard }
                }
                Text("El día 20 del mes siguiente es la fecha habitual en Texas y otros estados; confírmala con tu agencia.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Ver reporte") { ReportsView(fixedKind: .salesTax) }.headerButton()
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Registrar pago de impuesto") { showingPayment = true }
                    .disabled(payable <= 0)
                    .headerButton()
            }
        }
    }

    private func quarterMenu(_ interval: DateInterval) -> some View {
        Menu {
            ForEach(0..<4) { index in
                Button(quarterTitle(quarter(-index))) { quarterOffset = -index }
            }
        } label: {
            HStack(spacing: 6) {
                Text(quarterTitle(interval)).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.separator))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trimestre")
        .accessibilityValue(quarterTitle(interval))
    }

    /// Grupos («Combinada») y tasas de cada agencia con lo cobrado en el trimestre.
    private func ratesTable(_ summary: SalesTaxSummary?, interval: DateInterval) -> some View {
        let collected = Dictionary((summary?.rows ?? []).compactMap { row in row.rateID.map { ($0, row.tax) } }, uniquingKeysWith: +)
        let number = (Calendar.current.component(.month, from: interval.start) - 1) / 3 + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasas por jurisdicción").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Menu {
                    Button("Nueva tasa", systemImage: "percent") { showingRate = true }
                    Button("Nuevo grupo", systemImage: "square.stack") { showingGroup = true }
                        .disabled(agencies.flatMap { $0.rates ?? [] }.isEmpty)
                } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Tasa") }.fontWeight(.semibold)
                }
                .accessibilityLabel("Nueva tasa o grupo")
            }
            TableCard {
                Text("Nombre").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tipo").frame(width: 150, alignment: .leading)
                Text("Tasa").frame(width: 80, alignment: .trailing)
                Text("T\(number) cobrado").frame(width: 120, alignment: .trailing)
            } rows: {
                ForEach(groups.filter { !$0.isArchived }) { group in
                    rateTableRow(group.name, kind: String(localized: "Combinada"), percent: group.percent,
                                 collected: (group.rates ?? []).reduce(0) { $0 + (collected[$1.id] ?? 0) }, highlighted: true)
                }
                ForEach(agencies) { agency in
                    ForEach((agency.rates ?? []).filter { !$0.isArchived }) { rate in
                        rateTableRow(rate.name, kind: agency.name, percent: rate.percent, collected: collected[rate.id] ?? 0, highlighted: false)
                    }
                }
                if groups.isEmpty && agencies.allSatisfy({ ($0.rates ?? []).isEmpty }) {
                    Text("Sin tasas todavía").font(.subheadline).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func rateTableRow(_ name: String, kind: String, percent: Decimal, collected: Int64, highlighted: Bool) -> some View {
        TableRow {
            Text(name).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(kind).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 150, alignment: .leading)
            Text("\(percent.formatted())%").fontWeight(.semibold).frame(width: 80, alignment: .trailing)
            Text(collected.money).frame(width: 120, alignment: .trailing)
        }
        .background { Rectangle().fill(highlighted ? Palette.background : .clear) }
    }

    private var paymentsCard: some View {
        let payments = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Pagos a la agencia").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            if payments.isEmpty {
                Text("Sin pagos registrados").font(.subheadline).foregroundStyle(Palette.ink3).padding(.vertical, 8)
            }
            ForEach(payments.prefix(8)) { entry in
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.memo).font(.subheadline).lineLimit(2)
                        Text(entry.date.shortDate).font(.caption).foregroundStyle(Palette.ink3)
                    }
                    Spacer(minLength: 8)
                    Text(entry.totalDebits.money).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Resumen

    private func quarter(_ offset: Int) -> DateInterval {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .month, value: offset * 3, to: .now) ?? .now
        return calendar.dateInterval(of: .quarter, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// «T4 2026 · oct–dic».
    private func quarterTitle(_ interval: DateInterval) -> String {
        let calendar = Calendar.current
        let number = (calendar.component(.month, from: interval.start) - 1) / 3 + 1
        let months = (interval.start..<interval.end.addingTimeInterval(-1)).formatted(.interval.month(.abbreviated).locale(.appText))
        return String(localized: "T\(number) \(interval.start.formatted(.appDateTime.year())) · \(months)")
    }

    /// Fecha habitual de declaración: el día 20 del mes siguiente al trimestre (Texas y muchos estados).
    private func dueDate(_ interval: DateInterval) -> Date {
        Calendar.current.date(byAdding: .day, value: 19, to: interval.end) ?? interval.end
    }

    @ViewBuilder
    private func summary(payable: Int64) -> some View {
        let interval = quarter(quarterOffset)
        let position = SalesTaxPosition(liabilityBalance: payable)
        Menu {
            ForEach(0..<4) { index in
                Button(quarterTitle(quarter(-index))) { quarterOffset = -index }
            }
        } label: {
            HStack(spacing: 6) {
                Text(quarterTitle(interval)).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel("Trimestre")
        .accessibilityValue(quarterTitle(interval))

        HeroCard(title: position.title, value: position.amount.money,
                 detail: payable > 0 ? String(localized: "Declarar y pagar antes del \(dueDate(interval).shortDate)") : position.detail)

        if let summary = try? Bookkeeper(context: context).salesTaxSummary(from: interval.start, to: interval.end.addingTimeInterval(-1)) {
            let paid = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil && interval.contains($0.date) }
                .reduce(0) { $0 + $1.totalDebits }
            VStack(spacing: 0) {
                breakdownRow(String(localized: "Ventas gravables"), summary.taxableSales.money)
                breakdownRow(String(localized: "Ventas no gravables y exentas"), (summary.nonTaxableSales + summary.exemptSales).money)
                ForEach(summary.rows) { row in
                    breakdownRow("\(row.name) · \(row.percent.formatted())%", row.tax.money)
                }
                breakdownRow(String(localized: "Cobrado en el periodo"), summary.totalTax.money, bold: true)
                breakdownRow(String(localized: "Pagado a la autoridad"), paid.money, last: true)
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        Button("Registrar pago de impuesto") { showingPayment = true }
            .buttonStyle(.secondary)
            .disabled(payable <= 0)
        Text("El día 20 del mes siguiente es la fecha habitual en Texas y otros estados; confírmala con tu agencia.")
            .font(.caption).foregroundStyle(Palette.ink3)

        let payments = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil }
        if !payments.isEmpty {
            SectionLabel(text: String(localized: "Pagos a la agencia")).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(payments.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    LabeledContent {
                        Text(entry.totalDebits.money).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.memo)
                            Text(entry.date.shortDate).font(.subheadline).foregroundStyle(Palette.ink3)
                        }
                    }
                    .frame(minHeight: 48)
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func breakdownRow(_ title: String, _ value: String, bold: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            LabeledContent(title, value: value)
                .font(.subheadline.weight(bold ? .semibold : .regular))
                .monospacedDigit()
                .frame(minHeight: 44)
            if !last { Divider() }
        }
    }

    // MARK: Tasas

    @ViewBuilder
    private var ratesTab: some View {
        SectionLabel(text: String(localized: "Grupos (lo que se aplica en la factura)"))
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { Divider() }
                rateRow(group.name, String(localized: "Combinada"), group.percent)
            }
            if !groups.isEmpty { Divider() }
            Button("Nuevo grupo", systemImage: "plus") { showingGroup = true }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .disabled(agencies.flatMap { $0.rates ?? [] }.isEmpty)
        }
        .padding(.horizontal, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        ForEach(agencies) { agency in
            SectionLabel(text: agency.name).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array((agency.rates ?? []).enumerated()), id: \.element.id) { index, rate in
                    if index > 0 { Divider() }
                    rateRow(rate.name, String(localized: "Componente"), rate.percent)
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        Button("Nueva tasa", systemImage: "plus") { showingRate = true }.buttonStyle(.secondary)
        Text("Escribe las tasas de tu estado, condado y ciudad. Chirogra no determina qué es gravable: consúltalo con tu agencia o tu contador.")
            .font(.caption).foregroundStyle(Palette.ink3)
    }

    private func rateRow(_ name: String, _ kind: String, _ percent: Decimal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(kind).font(.caption).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            Text("\(percent.formatted())%").font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

struct TaxRateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]

    @State private var agencyID: UUID?
    @State private var newAgencyName = ""
    @State private var name = ""
    @State private var percent: Decimal = 0
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section(title: "Agencia") {
                Picker("Agencia", selection: $agencyID) {
                    Text("Nueva agencia…").tag(UUID?.none)
                    ForEach(agencies) { Text($0.name).tag(Optional($0.id)) }
                }
                if agencyID == nil { TextField("Nombre (p. ej. Texas Comptroller)", text: $newAgencyName) }
            }
            Section(title: "Tasa") {
                TextField("Nombre (p. ej. Travis County)", text: $name)
                TextField("Porcentaje", value: $percent, format: .number.precision(.fractionLength(0...4)))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        .screenBackground()
        .navigationTitle("Nueva tasa")
        .inlineTitle()
        .discardableEditor(tracking: "\(agencyID?.uuidString ?? "")|\(newAgencyName)|\(name)|\(percent)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.isEmpty || percent <= 0 || (agencyID == nil && newAgencyName.isEmpty)).headerButton()
            }
        }
    }

    private func save() {
        do {
            let agency: TaxAgency
            if let existing = agencies.first(where: { $0.id == agencyID }) {
                agency = existing
            } else {
                let liability = try Bookkeeper(context: context).systemAccount(.salesTaxPayable)
                agency = TaxAgency(name: newAgencyName, liabilityAccountID: liability.id)
                context.insert(agency)
            }
            context.insert(TaxRate(name: name, rateMillionths: TaxComponent.millionths(fromPercent: percent), agency: agency))
            try context.save()
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaxGroupEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \TaxRate.name) private var rates: [TaxRate]
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        Form {
            TextField("Nombre (p. ej. Austin, TX)", text: $name)
            Section(title: "Tasas incluidas") {
                ForEach(rates.filter { !$0.isArchived }) { rate in
                    Toggle(isOn: Binding(get: { selected.contains(rate.id) },
                                         set: { if $0 { selected.insert(rate.id) } else { selected.remove(rate.id) } })) {
                        LabeledContent(rate.name, value: "\(rate.percent.formatted())%")
                    }
                }
            }
            LabeledContent("Tasa combinada",
                           value: String(localized: "\((Decimal(rates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.rateMillionths }) / 10_000).formatted())%"))
        }
        .screenBackground()
        .navigationTitle("Nuevo grupo")
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|" + selected.map(\.uuidString).sorted().joined(separator: ","), token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    context.insert(TaxGroup(name: name, rates: rates.filter { selected.contains($0.id) }))
                    try? context.save()
                    unsavedChanges?.remove(editorToken); dismiss()
                }
                .disabled(name.isEmpty || selected.isEmpty)
                .headerButton()
            }
        }
    }
}

/// Registrar el pago del sales tax cobrado a la agencia (Debe Sales Tax Payable / Haber Banco).
struct SalesTaxPaymentView: View {
    let owed: Int64
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var agencyID: UUID?
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var reference = ""
    @State private var errorMessage: String?

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
        .screenBackground()
        .navigationTitle("Pago de sales tax")
        .inlineTitle()
        .discardableEditor(tracking: "\(agencyID?.uuidString ?? "")|\(amount)|\(date)|\(accountID?.uuidString ?? "")|\(reference)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Registrar", action: save).disabled(amount <= 0 || accountID == nil).headerButton() }
        }
        .onAppear {
            amount = owed
            agencyID = agencyID ?? agencies.first?.id
            accountID = accountID ?? accounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).paySalesTax(to: agencies.first { $0.id == agencyID }, amount: amount, date: date,
                                                         from: account, reference: reference)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
