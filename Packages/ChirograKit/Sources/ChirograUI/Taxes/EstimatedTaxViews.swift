import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Apartado para impuestos estimados (1.4; canvas «Chirogra 1.4», tableros `Apartado`, `ApartadoVacio`,
// `PagoIRS`, `Reportes`, `iPadApartado`, `MacApartado`; docs/DATOS-V6.md)
//
// Cuánto apartar cada periodo del 1040-ES, las cuatro fechas del año, el porcentaje y los pagos al IRS. Es una guía:
// el monto real lo dice el contador. Los datos están en `Bookkeeper+EstimatedTax.swift`.

/// Páginas de Impuestos en la barra lateral de iPad y Mac (canvas `Sidebar`: «Impuesto sobre ventas» e «Impuestos
/// estimados»).
enum TaxesPage: String, CaseIterable, Identifiable, Hashable {
    case salesTax, estimated
    var id: String { rawValue }

    var title: String {
        switch self {
        case .salesTax: String(localized: "Impuesto sobre ventas")
        case .estimated: String(localized: "Impuestos estimados")
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .salesTax: TaxesView()
        case .estimated: EstimatedTaxView()
        }
    }
}

extension EstimatedTaxCalendar.Period {
    /// «4.º pago · sep–dic»
    var title: String {
        // Tres letras («sep–dic», como el canvas): el formato abreviado en español da «sept».
        func month(_ date: Date) -> String { String(date.formatted(.appDateTime.month(.wide)).lowercased().prefix(3)) }
        let months = "\(month(start))–\(month(end.addingTimeInterval(-1)))"
        return "\(Bookkeeper.periodTitle(number)) · \(months)"
    }
}

/// El resumen para la tarjeta y la pantalla, a hoy, con la base de los reportes.
@MainActor
private func estimatedTaxSummary(_ context: ModelContext, basis: AccountingBasis) -> EstimatedTaxSummary? {
    try? Bookkeeper(context: context).estimatedTaxSummary(basis: basis)
}

/// «Vence el 15 de enero · faltan 51 días» (o «vence hoy», «venció hace 3 días»).
private func dueText(_ summary: EstimatedTaxSummary) -> String {
    let date = summary.focus.period.due.formatted(.appDateTime.day().month(.wide))
    switch summary.daysLeft {
    case 0: return String(localized: "Vence hoy, \(date)")
    case 1: return String(localized: "Vence el \(date) · falta 1 día")
    case let days where days > 1: return String(localized: "Vence el \(date) · faltan \(days) días")
    default: return String(localized: "Vencía el \(date)")
    }
}

/// El contenido de la tarjeta (canvas `Main`, `Reportes`): ganancia del periodo, cuánto apartar, el vencimiento y lo
/// pagado frente a lo apartado en el año.
struct EstimatedTaxSummaryContent: View {
    let summary: EstimatedTaxSummary
    var amountSize: CGFloat = 34

    var body: some View {
        let year = summary.setAsideThisYear
        let share = year > 0 ? min(1, Double(summary.paidThisYear) / Double(year)) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Este periodo ganaste").foregroundStyle(Palette.ink2)
                Text(summary.focus.profit.money).fontWeight(.semibold).foregroundStyle(Palette.brand)
            }
            .font(.subheadline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Aparta").font(.body)
                Text(summary.focus.toSetAside.money).font(.amount(amountSize)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(summary.percent) %").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            Text(dueText(summary)).font(.subheadline).foregroundStyle(summary.daysLeft < 0 ? Palette.negative : Palette.ink)
            Divider()
            Capsule().fill(Palette.fill2).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in Capsule().fill(Palette.brand).frame(width: proxy.size.width * share) }
                }
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Pagado al IRS \(summary.paidThisYear.money)")
                    Spacer(minLength: 8)
                    Text("Apartado en \(String(summary.taxYear)) \(year.money)").foregroundStyle(Palette.ink2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pagado al IRS \(summary.paidThisYear.money)")
                    Text("Apartado en \(String(summary.taxYear)) \(year.money)").foregroundStyle(Palette.ink2)
                }
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tarjeta «Apartado para impuestos» de Inicio y Reportes. Sale salvo que se apague; en una corporación (S o C), solo
/// si se encendió a mano (la guía es para dueño único y LLC de un solo dueño).
struct EstimatedTaxCard: View {
    @Environment(\.modelContext) private var context
    @ActiveCompanyQuery private var companies: [Company]
    @CompanyQuery private var settings: [EstimatedTaxSetting]
    @CompanyQuery private var payments: [EstimatedTaxPayment]
    @CompanyQuery private var lines: [JournalLine]
    @ReportBasisSetting private var basis
    /// En Reportes la tarjeta lleva su título dentro; en Inicio el título va fuera (grupo de Inicio).
    var showsTitle = false

    static func isShown(settings: [EstimatedTaxSetting], company: Company?) -> Bool {
        if let setting = settings.min(by: { $0.createdAt < $1.createdAt }) { return setting.showsCard }
        return ![.sCorp, .cCorp].contains(company?.entityType ?? .soleProprietorship)
    }

    var body: some View {
        _ = (payments.count, lines.count)
        return Group {
            if Self.isShown(settings: settings, company: companies.first), let summary = estimatedTaxSummary(context, basis: basis) {
                SectionLink(item: .taxes(.estimated)) { EstimatedTaxView() } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        if showsTitle {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Apartado para impuestos").font(.headline).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("Ajustar").foregroundStyle(Palette.brand)
                            }
                        }
                        EstimatedTaxSummaryContent(summary: summary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Abre impuestos estimados"))
                .accessibilityIdentifier("tarjeta.apartado")
                .recorridoObjetivo("tarjeta.apartado")
                .id("tarjeta.apartado")
            }
        }
    }
}

/// Pantalla «Impuestos estimados» (canvas `Apartado`): el pago que toca, «Registrar pago al IRS», las cuatro fechas del
/// año, los pagos anotados, el porcentaje y el interruptor de la tarjeta.
struct EstimatedTaxView: View {
    @Environment(\.modelContext) private var context
    @ActiveCompanyQuery private var companies: [Company]
    @CompanyQuery private var settings: [EstimatedTaxSetting]
    @CompanyQuery(sort: \EstimatedTaxPayment.date) private var payments: [EstimatedTaxPayment]
    @CompanyQuery private var lines: [JournalLine]
    @ReportBasisSetting private var basis
    @State private var paying = false
    @State private var deleting: EstimatedTaxPayment?
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    var body: some View {
        _ = (payments.count, lines.count, settings.count)
        let summary = estimatedTaxSummary(context, basis: basis)
        return Form {
            #if !os(macOS)
            // En el Mac va de subtítulo de la ventana.
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pagos trimestrales al IRS · formulario 1040-ES").font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            #endif
            if let summary {
                Section {
                    if summary.focus.profit > 0 || summary.paidThisYear > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "\(summary.focus.period.title) · al \(Date.now.dayMonth)"))
                                .font(.subheadline).foregroundStyle(Palette.ink2)
                            EstimatedTaxSummaryContent(summary: summary, amountSize: 36)
                        }
                        .padding(.vertical, 6)
                        .recorridoObjetivo("apartado.resumen")
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "percent").font(.system(size: 40)).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                            Text("Aún no hay ganancia este periodo").font(.title3.bold()).multilineTextAlignment(.center)
                            Text(String(localized: "Cuando registres ingresos y gastos, aquí verás cuánto apartar antes del \(summary.focus.period.due.formatted(.appDateTime.day().month(.wide))).").replacingOccurrences(of: "  ", with: " "))
                                .font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .recorridoObjetivo("apartado.resumen")
                    }
                }
                #if !os(macOS)
                // En el Mac, el formulario va en el inspector (canvas `MacApartado`).
                Section {
                    Button { paying = true } label: { Label("Registrar pago al IRS", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                #endif
                Section(heading: String(localized: "Las cuatro fechas de \(String(summary.taxYear))")) {
                    ForEach(summary.rows) { row in periodRow(row, summary: summary) }
                }
                let made = payments.filter { $0.taxYear == summary.taxYear }
                if !made.isEmpty {
                    Section(heading: String(localized: "Pagos anotados")) {
                        ForEach(made) { payment in
                            LabeledContent {
                                Text(payment.amount.money).foregroundStyle(Palette.ink)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Bookkeeper.periodTitle(payment.period))
                                    Text(payment.date.shortDate).font(.footnote).foregroundStyle(Palette.ink2)
                                }
                            }
                            .contextMenu {
                                Button("Quitar pago", systemImage: "trash", role: .destructive) { deleting = payment }
                            }
                            .swipeActions {
                                Button("Quitar", role: .destructive) { deleting = payment }
                            }
                        }
                    }
                }
            }
            Section {
                Stepper(value: percentBinding, in: 1...60) {
                    LabeledContent("Porcentaje a apartar", value: "\(currentPercent) %")
                }
                Toggle("Mostrar en Inicio y Reportes", isOn: showsCardBinding)
            } header: {
                SectionLabel(text: String(localized: "Ajuste"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sugerido: entre 25 % y 30 %. Es una guía, no asesoría fiscal; tu contador te dice el monto real.")
                    Text("Pensado para dueño único y LLC de un solo dueño. Si tu negocio es una corporación, puedes apagar la tarjeta con el interruptor.")
                }
            }
            if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padReadingList(PadReading.detail)
        .screenBackground()
        .navigationTitle("Impuestos estimados")
        #if os(macOS)
        .navigationSubtitle(String(localized: "Pagos trimestrales al IRS · formulario 1040-ES"))
        .macInspectorToggle(isAvailable: summary != nil)
        .macReportInspector(title: String(localized: "Registrar pago al IRS"), hasSelection: summary != nil,
                            placeholder: "", selectionKey: nil, isAvailable: summary != nil) {
            IRSPaymentSheet(summary: summary, inline: true)
        } actions: {
            EmptyView()
        }
        #endif
        .sheet(isPresented: $paying) {
            NavigationStack { IRSPaymentSheet(summary: summary) }.editorSheetSizing()
        }
        .alert("¿Quitar este pago?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Quitar", role: .destructive) {
                if let deleting { remove(deleting) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se revierte su asiento. El pago al IRS no cambia: Chirogra solo lo anota.")
        }
    }

    private func periodRow(_ row: EstimatedTaxRow, summary: EstimatedTaxSummary) -> some View {
        let isFocus = row.period.number == summary.focus.period.number
        let (text, color, dot): (String, Color, Color) =
            if row.isPaid {
                (String(localized: "Pagado el \(row.lastPaymentDate?.dayMonth ?? "")"), Palette.positive, Palette.green)
            } else if isFocus {
                (dueText(summary), Palette.info, Palette.blue)
            } else if row.period.due < Calendar.current.startOfDay(for: .now) && row.toSetAside == 0 {
                (String(localized: "Nada que apartar"), Palette.ink2, Palette.gray)
            } else if row.period.due < Calendar.current.startOfDay(for: .now) {
                (String(localized: "Sin pago anotado"), Palette.warning, Palette.orange)
            } else {
                (String(localized: "Vence el \(row.period.due.dayMonth)"), Palette.ink2, Palette.gray)
            }
        let amount = row.isPaid ? row.paid : row.toSetAside
        return HStack(spacing: 12) {
            DateTile(date: row.period.due)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.period.title).foregroundStyle(Palette.ink)
                StatusChip(text: text, foreground: color, compact: true, dot: dot)
            }
            Spacer(minLength: 8)
            Text(row.isStarted || row.isPaid ? amount.money : "—").foregroundStyle(Palette.ink).monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var currentPercent: Int { settings.min(by: { $0.createdAt < $1.createdAt })?.percent ?? 25 }

    private var percentBinding: Binding<Int> {
        Binding(get: { currentPercent }, set: { value in run { try books.setEstimatedTax(percent: value) } })
    }

    private var showsCardBinding: Binding<Bool> {
        Binding(get: { EstimatedTaxCard.isShown(settings: settings, company: companies.first) },
                set: { value in run { try books.setEstimatedTax(showsCard: value) } })
    }

    private func remove(_ payment: EstimatedTaxPayment) {
        run { try books.deleteEstimatedTaxPayment(payment) }
        deleting = nil
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}

/// Hoja «Pago al IRS» (canvas `PagoIRS`): a qué pago corresponde, fecha, monto y la cuenta de la que salió. Chirogra
/// solo lo anota; el pago se hace con el IRS.
struct IRSPaymentSheet: View {
    let summary: EstimatedTaxSummary?
    /// En el inspector del Mac (canvas `MacApartado`): los campos sin hoja ni título, «Registrar pago» debajo y, al
    /// guardar, «Pago registrado» en vez de cerrarse.
    var inline = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var periodKey = ""
    @State private var date = Date()
    @State private var amount: Int64 = 0
    @State private var accountID: UUID?
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var recorded = false

    /// Los cuatro pagos del año del que toca y el 4.º del año anterior (se paga en enero).
    private var choices: [EstimatedTaxCalendar.Period] {
        guard let year = summary?.taxYear else { return [] }
        let previous = EstimatedTaxCalendar.periods(of: year - 1, calendar: .current).last.map { [$0] } ?? []
        return previous + EstimatedTaxCalendar.periods(of: year, calendar: .current)
    }

    private func key(_ period: EstimatedTaxCalendar.Period) -> String { "\(period.year)-\(period.number)" }

    private var moneyAccounts: [Account] {
        accounts.filter { !$0.isArchived && [.bank, .cash, .creditCard].contains($0.subtype) }
    }

    var body: some View {
        if inline { inlineForm } else { sheet }
    }

    /// Los campos en columna, con su nombre encima (como los formularios del inspector del Mac).
    private var inlineForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Pago", selection: $periodKey) {
                ForEach(choices, id: \.self) { period in
                    Text("\(period.title) \(String(period.year))").tag(key(period))
                }
            }
            DatePicker("Fecha", selection: $date, displayedComponents: .date)
            LabeledContent("Monto") {
                MoneyField(title: String(localized: "Monto"), minorUnits: $amount).multilineTextAlignment(.trailing)
            }
            Picker("Salió de", selection: $accountID) {
                ForEach(moneyAccounts) { Text($0.displayName).tag(Optional($0.id)) }
            }
            Text("Chirogra solo lo anota. El pago lo haces tú directamente con el IRS.")
                .font(.footnote).foregroundStyle(Palette.ink2)
            if recorded {
                Label("Pago registrado", systemImage: "checkmark").font(.footnote).foregroundStyle(Palette.positive)
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Button("Registrar pago", action: save)
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear(perform: load)
        .onChange(of: amount) { if amount != 0 { recorded = false } }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let focus = summary?.focus {
            periodKey = key(focus.period)
            amount = max(0, focus.toSetAside - focus.paid)
        }
        accountID = moneyAccounts.first { $0.subtype == .bank }?.id ?? moneyAccounts.first?.id
    }

    private var sheet: some View {
        Form {
            Section {
                Picker("Pago", selection: $periodKey) {
                    ForEach(choices, id: \.self) { period in
                        Text("\(period.title) \(String(period.year))").tag(key(period))
                    }
                }
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                LabeledContent("Monto") {
                    MoneyField(title: String(localized: "Monto"), minorUnits: $amount).multilineTextAlignment(.trailing)
                }
                .fieldRow()
                Picker("Salió de", selection: $accountID) {
                    ForEach(moneyAccounts) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } footer: {
                Text("Chirogra solo lo anota. El pago lo haces tú directamente con el IRS.")
            }
            if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Pago al IRS")
        .inlineTitle()
        .discardableEditor(tracking: "\(periodKey)|\(date.timeIntervalSinceReferenceDate)|\(amount)|\(accountID?.uuidString ?? "")", token: editorToken)
        .bottomActionBar {
            Button("Registrar pago", action: save).buttonStyle(PrimaryButtonStyle())
        }
        .onAppear(perform: load)
    }

    private func save() {
        guard let period = choices.first(where: { key($0) == periodKey }), let accountID else {
            errorMessage = String(localized: "Elige el pago y la cuenta de la que salió.")
            return
        }
        do {
            try Bookkeeper(context: context).recordEstimatedTaxPayment(taxYear: period.year, period: period.number, date: date,
                                                                       amount: amount, fromAccountID: accountID)
            if inline {
                errorMessage = nil
                recorded = true
                amount = 0
                return
            }
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
