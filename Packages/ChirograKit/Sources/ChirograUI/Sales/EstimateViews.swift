import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

#if DEBUG
extension QALaunch {
    /// `-qa.seccion estimates`: arranca en Ventas › Estimados (la lista de secciones de `QALaunch.sidebarItem` está en
    /// `MacTablePage.swift`, que no se toca desde aquí).
    static var salesItem: SidebarItem? {
        UserDefaults.standard.string(forKey: "qa.seccion") == "estimates" ? .sales(.estimates) : nil
    }
}
#endif

// MARK: - Estado

extension Estimate {
    /// Estado a mostrar (`effectiveStatus`): un enviado pasado de fecha se ve vencido; uno aceptado con parte ya
    /// facturada, «Facturado en parte».
    var statusTitle: String {
        switch effectiveStatus() {
        case .draft: String(localized: "Borrador")
        case .sent: String(localized: "Enviado")
        case .accepted: hasInvoices ? String(localized: "Facturado en parte") : String(localized: "Aceptado")
        case .declined: String(localized: "Rechazado")
        // Clave propia: «Vencido» del catálogo es el de las facturas («Overdue»); un estimado vencido es «Expired».
        case .expired: String(localized: "estimate.expired", defaultValue: "Vencido")
        case .converted: String(localized: "Convertido")
        }
    }

    /// Punto de color y texto accesible (canvas `Estimado`: «● Aceptado» en verde, «● Convertido» en azul).
    func statusChip(compact: Bool = true) -> StatusChip {
        let (text, dot): (Color, Color) = switch effectiveStatus() {
        case .draft: (Palette.ink2, Palette.gray)
        case .sent: (Palette.ink2, Palette.blue)
        case .accepted: hasInvoices ? (Palette.warning, Palette.orange) : (Palette.positive, Palette.green)
        case .declined: (Palette.negative, Palette.red)
        case .expired: (Palette.warning, Palette.orange)
        case .converted: (Palette.info, Palette.blue)
        }
        return StatusChip(text: statusTitle, foreground: text, background: .clear, compact: compact, dot: dot)
    }

    /// Se puede editar: ni convertido ni con facturas (lo impide `saveEstimate`).
    var isEditable: Bool { status != .converted && !hasInvoices }
    /// Se puede convertir en factura (lo que quede por facturar).
    var isConvertible: Bool { status != .converted && status != .declined && !(lines ?? []).isEmpty && !isFullyInvoiced }

    /// «Aceptado por Laura Méndez el 30 oct · válido hasta 30 nov» (canvas `Estimado`).
    var statusDetail: String {
        let valid = String(localized: "válido hasta \(expirationDate.dayMonth)")
        switch effectiveStatus() {
        case .draft: return String(localized: "Creado el \(issueDate.dayMonth)") + " · " + valid
        case .sent: return String(localized: "Enviado el \((sentDate ?? issueDate).dayMonth)") + " · " + valid
        case .accepted:
            let date = (acceptedDate ?? issueDate).dayMonth
            let accepted = acceptedBy.isEmpty ? String(localized: "Aceptado el \(date)") : String(localized: "Aceptado por \(acceptedBy) el \(date)")
            return accepted + " · " + valid
        case .declined: return String(localized: "Rechazado") + " · " + valid
        case .expired: return String(localized: "Venció el \(expirationDate.dayMonth)")
        case .converted: return String(localized: "Convertido en factura el \((convertedDate ?? issueDate).dayMonth)")
        }
    }

    /// Claves de orden y valores de la tabla del Mac (`nonisolated` para `KeyPathComparator`).
    nonisolated var tableNumber: String { number.isEmpty ? "~" : number }
    nonisolated var customerName: String { customer?.name ?? "" }
    /// Orden de los estados: Borrador, Enviado, Aceptado, Vencido, Rechazado, Convertido.
    nonisolated var statusRank: Int {
        switch effectiveStatus() {
        case .draft: 0
        case .sent: 1
        case .accepted: 2
        case .expired: 3
        case .declined: 4
        case .converted: 5
        }
    }
}

/// Filtro de la lista de estimados (los `rawValue` son las etiquetas en español del catálogo).
enum EstimateFilter: String, CaseIterable, Identifiable {
    case all = "Todos", draft = "Borrador", sent = "Enviado", accepted = "Aceptado", expired = "Vencido",
         declined = "Rechazado", converted = "Convertido"
    var id: String { rawValue }

    /// Etiqueta visible (como `localizedTitle`, pero «Vencido» con su clave de estimado).
    var title: String {
        self == .expired ? String(localized: "estimate.expired", defaultValue: "Vencido") : localizedTitle
    }

    func matches(_ estimate: Estimate) -> Bool {
        switch self {
        case .all: true
        case .draft: estimate.effectiveStatus() == .draft
        case .sent: estimate.effectiveStatus() == .sent
        case .accepted: estimate.effectiveStatus() == .accepted
        case .expired: estimate.effectiveStatus() == .expired
        case .declined: estimate.effectiveStatus() == .declined
        case .converted: estimate.effectiveStatus() == .converted
        }
    }

    /// Búsqueda por cliente, número, concepto o importe (sin distinguir mayúsculas ni tildes).
    static func search(_ estimate: Estimate, _ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || estimate.number.localizedStandardContains(text) || estimate.title.localizedStandardContains(text)
            || (estimate.customer?.name.localizedStandardContains(text) ?? false) || estimate.total.money.contains(text)
    }
}

// MARK: - Lista (iPhone)

/// Estimados en Ventas (iPhone, iPad con columna estrecha o AX4): menú de sección «Estimados ▾», «N estimados ·
/// Por aceptar $…» sobre el grupo y filas como las de facturas (cliente, número y validez; importe y estado).
struct EstimateListView: View {
    @Binding var query: String
    @Binding var filter: EstimateFilter
    var sectionMenu: SalesSectionMenu?
    var onCreate: () -> Void = {}
    @Query(sort: \Estimate.issueDate, order: .reverse) private var estimates: [Estimate]

    private var filtered: [Estimate] { estimates.filter { filter.matches($0) && EstimateFilter.search($0, query) } }

    /// Lo que espera respuesta del cliente: borradores y enviados vigentes.
    private var pending: Int64 {
        estimates.filter { [.draft, .sent].contains($0.effectiveStatus()) }.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        List {
            if let sectionMenu {
                Section { sectionMenu.sectionMenuRow() }.compactSectionSpacing(0)
            }
            if filtered.isEmpty {
                emptyState.listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filtered) { estimate in
                        NavigationLink { EstimateDetailView(estimate: estimate) } label: { EstimateRow(estimate: estimate) }
                    }
                } header: {
                    summary
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .contentMargins(.top, 4, for: .scrollContent)
    }

    private var summary: some View {
        let count = filter == .all ? Text("\(filtered.count) estimados")
            : Text("\(filtered.count) estimados") + Text(verbatim: " · ") + Text(filter.title)
        let total = Text("Por aceptar \(pending.money)")
        return ViewThatFits(in: .horizontal) {
            HStack {
                count.fixedSize()
                Spacer(minLength: 8)
                total.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                count
                total
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.ink2)
        .monospacedDigit()
        .textCase(nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        if estimates.isEmpty {
            ContentUnavailableView {
                Label("Todavía no hay estimados", systemImage: "list.clipboard")
            } description: {
                Text("Haz un estimado para tu cliente y, cuando lo acepte, conviértelo en factura.")
            } actions: {
                Button("Nuevo estimado", action: onCreate).buttonStyle(.primaryCompact)
            }
        } else {
            ContentUnavailableView {
                Label("Sin resultados", systemImage: "magnifyingglass")
            } description: {
                Text("Prueba con otro cliente, número o estado.")
            } actions: {
                Button("Quitar filtros") {
                    query = ""
                    filter = .all
                }
                .buttonStyle(FillCapsuleButtonStyle(fullWidth: false))
            }
        }
    }
}

/// Fila de estimado: cliente y «E-0001 · Remodelación del lobby» (o la validez) a la izquierda; importe y estado a la
/// derecha. El chevron lo pone la lista.
struct EstimateRow: View {
    let estimate: Estimate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerRow(title: estimate.customer?.name ?? String(localized: "Sin cliente"), subtitle: subtitle) {
            EmptyView()
        } trailing: {
            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 1) {
                Text(estimate.total.money).font(.body).monospacedDigit().foregroundStyle(Palette.ink)
                estimate.statusChip()
            }
        }
    }

    private var subtitle: String {
        let number = estimate.number.isEmpty ? String(localized: "Sin número") : estimate.number
        if !estimate.title.isEmpty { return "\(number) · \(estimate.title)" }
        return "\(number) · " + String(localized: "válido hasta \(estimate.expirationDate.dayMonth)")
    }
}

// MARK: - Detalle

/// Estimado (canvas `Estimado`): resumen con cliente, estado, concepto, total y «Aceptado por … · válido hasta …»;
/// los conceptos y los totales; «Convertir en factura» con Todo el estimado · Anticipo · Elegir líneas y, al convertir,
/// «Factura creada como borrador» con «Revisar y enviar». Arriba, Enviar · Editar y «⋯» con los cambios de estado.
struct EstimateDetailView: View {
    @Bindable var estimate: Estimate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @Query private var companies: [Company]
    @State private var editing = false
    @State private var sending = false
    @State private var accepting = false
    @State private var confirmingDelete = false
    @State private var conversion = EstimateConversionChoice()
    @State private var createdInvoice: Invoice?
    @State private var openedInvoice: Invoice?
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return !dynamicTypeSize.isAccessibilitySize
    }

    private var invoices: [Invoice] { (try? books.invoices(for: estimate)) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage { ErrorBanner(message: errorMessage).padding(.bottom, 12) }
                summary
                linesSection
                totalsSection
                if let createdInvoice {
                    createdSection(createdInvoice)
                } else if estimate.isConvertible {
                    EstimateConversionSection(estimate: estimate, choice: $conversion)
                    if isWide { convertButton.padding(.top, 16) }
                }
                invoicesSection
                if !estimate.customerMessage.isEmpty { messageSection }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        }
        .background(Palette.background)
        .navigationTitle(estimate.number.isEmpty ? String(localized: "Estimado") : estimate.number)
        .inlineTitle()
        .modifier(ConvertBar(shown: !isWide && (createdInvoice != nil || estimate.isConvertible)) { bottomButton })
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Enviar", systemImage: "square.and.arrow.up") { sending = true }
                    .disabled(estimate.status == .converted || estimate.status == .declined)
                    .headerButton()
                if estimate.isEditable {
                    Button("Editar") { editing = true }.headerButton()
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { InvoiceEditorView(mode: .estimate(estimate)) }.editorSheetSizing()
        }
        .sheet(isPresented: $sending) {
            NavigationStack { SendDocumentView(source: .estimate(estimate)) }.editorSheetSizing()
        }
        .sheet(isPresented: $accepting) {
            NavigationStack { EstimateAcceptView(estimate: estimate) }.editorSheetSizing()
        }
        .navigationDestination(item: $openedInvoice) { InvoiceDetailView(invoice: $0) }
        .confirmationDialog("¿Eliminar el estimado?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar estimado", role: .destructive, action: delete)
        } message: {
            Text("No afecta a la contabilidad.")
        }
        .onAppear { conversion.prepare(for: estimate) }
    }

    // MARK: Resumen

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(estimate.customer?.name ?? String(localized: "Sin cliente")).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
                estimate.statusChip(compact: false)
            }
            if !estimate.title.isEmpty {
                Text(estimate.title).font(.headline).foregroundStyle(Palette.ink).padding(.top, 4)
            }
            Text(estimate.total.money)
                .font(.system(.largeTitle, weight: .bold)).monospacedDigit()
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(estimate.statusDetail).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ text: String) -> some View {
        SectionLabel(text: text)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.top, 22)
            .padding(.bottom, 7)
    }

    /// Conceptos: descripción y «40 × $58.00» debajo; importe a la derecha.
    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Conceptos"))
            VStack(spacing: 0) {
                ForEach(Array(estimate.sortedLines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.details.isEmpty ? String(localized: "Sin descripción") : line.details).foregroundStyle(Palette.ink)
                            Text(lineDetail(line)).font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    } trailing: {
                        Text(line.amount.money).monospacedDigit().foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
                if estimate.sortedLines.isEmpty {
                    Text("Sin líneas").foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                }
            }
            .card(padding: 0)
        }
    }

    private func lineDetail(_ line: EstimateLine) -> String {
        var parts = ["\(line.quantity.formatted()) × \(line.unitPrice.money)"]
        if line.isTaxable { parts.append(String(localized: "gravable")) }
        if line.invoicedQuantity > 0 {
            parts.append(line.remainingQuantity > 0 ? String(localized: "facturado \(line.invoicedQuantity.formatted())")
                         : String(localized: "facturado"))
        }
        return parts.joined(separator: " · ")
    }

    /// Subtotal, descuento, impuesto y total con las reglas de emisión (también con impuesto incluido).
    private var totalsSection: some View {
        let rows = SalesDocument(estimate: estimate).totals
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                let bold = row.style == .accent || row.style == .strong
                AdaptiveRow {
                    Text(row.title).foregroundStyle(row.style == .subtle ? Palette.ink2 : Palette.ink).fontWeight(bold ? .semibold : .regular)
                } trailing: {
                    Text(row.value).monospacedDigit().foregroundStyle(bold ? Palette.ink : Palette.ink2).fontWeight(bold ? .semibold : .regular)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 6)
                .frame(minHeight: Metrics.target)
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 0)
        .padding(.top, 20)
    }

    /// Canvas: «Factura F-1050 creada como borrador» con el detalle del anticipo; «Revisar y enviar» la abre.
    private func createdSection(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Factura"))
            Button { openedInvoice = invoice } label: {
                HStack(spacing: 12) {
                    IconTile(systemImage: "checkmark", foreground: Palette.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Factura creada como borrador").foregroundStyle(Palette.ink)
                        Text(createdDetail(invoice)).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 10)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .card(padding: 0)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            if isWide {
                Button("Revisar y enviar") { openedInvoice = invoice }.buttonStyle(.primary).padding(.top, 16)
            }
        }
    }

    private func createdDetail(_ invoice: Invoice) -> String {
        let amount = (try? books.totals(for: invoice).total) ?? invoice.draftAmount
        if estimate.status == .converted { return String(localized: "Total de \(amount.money) · estimado cerrado") }
        let remaining = EstimateConversionChoice.amount(estimate, portion: .all, books: books)
        return String(localized: "\(amount.money) · queda \(remaining.money) por facturar")
    }

    @ViewBuilder
    private var invoicesSection: some View {
        let invoices = invoices.filter { $0.id != createdInvoice?.id }
        if !invoices.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel(String(localized: "Facturas de este estimado"))
                VStack(spacing: 0) {
                    ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                        if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                        Button { openedInvoice = invoice } label: {
                            HStack {
                                InvoiceRow(invoice: invoice)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, Metrics.cardPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Mensaje para el cliente"))
            Text(estimate.customerMessage).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    // MARK: Acciones

    @ViewBuilder
    private var bottomButton: some View {
        if let createdInvoice {
            Button("Revisar y enviar") { openedInvoice = createdInvoice }.buttonStyle(.primary)
        } else {
            convertButton
        }
    }

    private var convertButton: some View {
        Button("Convertir en factura", action: convert)
            .buttonStyle(.primary)
            .disabled(!conversion.isValid(for: estimate))
    }

    private var moreMenu: some View {
        Menu {
            let status = estimate.effectiveStatus()
            if status == .draft || status == .expired {
                Button("Marcar como enviado", systemImage: "paperplane") { setStatus(.sent) }
            }
            if status == .draft || status == .sent || status == .expired || status == .declined {
                Button("Marcar como aceptado…", systemImage: "checkmark.circle") { accepting = true }
            }
            if status == .draft || status == .sent || status == .expired {
                Button("Marcar como rechazado", systemImage: "xmark.circle") { setStatus(.declined) }
            }
            Button("Vista previa del PDF", systemImage: "doc.richtext") { sending = true }
            if !estimate.hasInvoices {
                Button("Eliminar estimado", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        } label: {
            Label("Más acciones", systemImage: "ellipsis")
        }
        .headerButton()
    }

    private func setStatus(_ status: EstimateStatus) {
        do { try books.setStatus(status, of: estimate); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    private func convert() {
        do {
            createdInvoice = try books.convertToInvoice(estimate, portion: conversion.portion)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        context.delete(estimate)
        try? context.save()
        dismiss()
    }
}

/// Barra de vidrio inferior con el botón principal (iPhone), como `FacturaNueva` y el canvas `Estimado`.
private struct ConvertBar<Bar: View>: ViewModifier {
    let shown: Bool
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if shown { content.bottomActionBar { bar } } else { content }
    }
}

// MARK: - Convertir en factura

/// Qué parte del estimado pasa a la factura (canvas `Estimado`: Todo el estimado · Anticipo del 50 % · Elegir líneas).
struct EstimateConversionChoice {
    enum Option: Hashable { case all, deposit, lines }

    var option: Option = .all
    var percent = 50
    var lineIDs: Set<UUID> = []

    var portion: EstimateConversion {
        switch option {
        case .all: .all
        case .deposit: .percent(Decimal(percent))
        case .lines: .lines(Array(lineIDs))
        }
    }

    /// Las líneas que quedan por facturar, todas elegidas al principio.
    mutating func prepare(for estimate: Estimate) {
        if lineIDs.isEmpty { lineIDs = Set(estimate.sortedLines.filter { $0.remainingQuantity > 0 }.map(\.id)) }
    }

    func isValid(for estimate: Estimate) -> Bool {
        switch option {
        case .all: estimate.isConvertible
        case .deposit: estimate.isConvertible && percent > 0
        case .lines: !lineIDs.isEmpty
        }
    }

    /// Total de la factura que saldría (las mismas reglas que `Bookkeeper.convertToInvoice`: cantidades, parte del
    /// descuento e impuesto, también con impuesto incluido).
    static func amount(_ estimate: Estimate, portion: EstimateConversion, books: Bookkeeper) -> Int64 {
        let lines = estimate.sortedLines
        let quantities: [Decimal] = lines.map { line in
            let remaining = max(line.remainingQuantity, 0)
            switch portion {
            case .all: return remaining
            case .percent(let percent): return min(remaining, line.quantity * max(percent, 0) / 100)
            case .lines(let ids): return ids.contains(line.id) ? remaining : 0
            }
        }
        func lineAmount(_ quantity: Decimal, _ price: Int64) -> Int64 {
            Money(decimal: quantity * Money(minorUnits: price).decimalValue).minorUnits
        }
        let chosen = zip(lines, quantities).filter { $0.1 > 0 && lineAmount($0.1, $0.0.unitPrice) > 0 }
        guard !chosen.isEmpty else { return 0 }
        let invoicedNow = chosen.reduce(Int64(0)) { $0 + lineAmount($1.1, $1.0.unitPrice) }
        let remainingDiscount = estimate.discount - estimate.discountInvoiced
        let closesEstimate = zip(lines, quantities).allSatisfy { $0.0.remainingQuantity - $0.1 <= 0 }
        let share: Int64
        if closesEstimate {
            share = remainingDiscount
        } else {
            let base = estimate.linesSubtotal
            share = base == 0 ? 0 : min(remainingDiscount, (estimate.discount * invoicedNow).dividedRoundingHalfAwayFromZero(by: base))
        }
        let discount = min(max(share, 0), invoicedNow)
        let components = (try? books.taxComponents(groupID: estimate.taxGroupID, on: .now)) ?? []
        let posting = try? PostingRules.invoice(
            date: .now, memo: "", receivableAccountID: UUID(),
            lines: chosen.map { SalesLine(incomeAccountID: $0.0.incomeAccountID ?? UUID(), amount: lineAmount($0.1, $0.0.unitPrice), isTaxable: $0.0.isTaxable) },
            taxComponents: components, customerIsTaxExempt: estimate.customer?.isTaxExempt ?? false,
            discount: discount, discountAccountID: discount > 0 ? UUID() : nil, pricesIncludeTax: estimate.pricesIncludeTax)
        return posting?.total ?? invoicedNow - discount
    }
}

/// «Convertir en factura»: las tres opciones con su importe, el porcentaje del anticipo y, al elegir líneas, las
/// líneas que quedan por facturar. Debajo, «Se creará una factura en borrador por $…».
struct EstimateConversionSection: View {
    let estimate: Estimate
    @Binding var choice: EstimateConversionChoice
    @Environment(\.modelContext) private var context

    private var books: Bookkeeper { Bookkeeper(context: context) }

    private func amount(_ portion: EstimateConversion) -> Int64 { EstimateConversionChoice.amount(estimate, portion: portion, books: books) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: String(localized: "Convertir en factura"))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, 22)
                .padding(.bottom, 7)
            VStack(spacing: 0) {
                optionRow(.all, title: String(localized: "Todo el estimado"),
                          subtitle: estimate.hasInvoices ? String(localized: "Lo que queda por facturar") : String(localized: "Una sola factura"),
                          amount: amount(.all).money, first: true)
                optionRow(.deposit, title: String(localized: "Anticipo del \(choice.percent) %"),
                          subtitle: String(localized: "El resto queda pendiente en el estimado"),
                          amount: amount(.percent(Decimal(choice.percent))).money)
                if choice.option == .deposit {
                    Divider().padding(.leading, Metrics.cardPadding + 30)
                    Stepper(value: $choice.percent, in: 5...95, step: 5) {
                        Text("Porcentaje: \(choice.percent) %")
                    }
                    .padding(.leading, Metrics.cardPadding + 30)
                    .padding(.trailing, Metrics.cardPadding)
                    .frame(minHeight: Metrics.target)
                }
                optionRow(.lines, title: String(localized: "Elegir líneas"), subtitle: String(localized: "Factura por etapas de la obra"),
                          amount: choice.option == .lines ? amount(.lines(Array(choice.lineIDs))).money : "—")
                if choice.option == .lines {
                    ForEach(estimate.sortedLines.filter { $0.remainingQuantity > 0 }) { line in
                        Divider().padding(.leading, Metrics.cardPadding + 30)
                        lineToggle(line)
                    }
                }
            }
            .card(padding: 0)
            Text("Se creará una factura en borrador por \(amount(choice.portion).money).")
                .font(.footnote).foregroundStyle(Palette.ink2)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, 7)
        }
    }

    /// Opción con la marca de selección a la izquierda (canvas: ✓ en Tinta), título, detalle e importe.
    private func optionRow(_ option: EstimateConversionChoice.Option, title: String, subtitle: String, amount: String,
                           first: Bool = false) -> some View {
        let selected = choice.option == option
        return VStack(spacing: 0) {
            if !first { Divider().padding(.leading, Metrics.cardPadding + 30) }
            Button { choice.option = option } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.brand)
                        .opacity(selected ? 1 : 0)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    AdaptiveRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).foregroundStyle(Palette.ink)
                            Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    } trailing: {
                        Text(amount).monospacedDigit().foregroundStyle(Palette.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 8)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func lineToggle(_ line: EstimateLine) -> some View {
        let isOn = choice.lineIDs.contains(line.id)
        return Button {
            if isOn { choice.lineIDs.remove(line.id) } else { choice.lineIDs.insert(line.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Palette.brand : Palette.chevron)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(line.details.isEmpty ? String(localized: "Sin descripción") : line.details).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(Money(decimal: line.remainingQuantity * Money(minorUnits: line.unitPrice).decimalValue).minorUnits.money)
                    .monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .padding(.leading, Metrics.cardPadding + 30)
            .padding(.trailing, Metrics.cardPadding)
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// «Convertir en factura…» del inspector del Mac: las opciones en una hoja, «Cancelar» y «Convertir».
struct ConvertEstimateSheet: View {
    let estimate: Estimate
    var onConverted: (Invoice) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var choice = EstimateConversionChoice()
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage { ErrorBanner(message: errorMessage).padding(.bottom, 8) }
                Text("\(estimate.number) · \(estimate.customer?.name ?? "")").font(.headline).foregroundStyle(Palette.ink)
                EstimateConversionSection(estimate: estimate, choice: $choice)
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Convertir en factura")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.headerButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Convertir", action: convert).disabled(!choice.isValid(for: estimate)).headerButton()
            }
        }
        .onAppear { choice.prepare(for: estimate) }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func convert() {
        do {
            let invoice = try Bookkeeper(context: context).convertToInvoice(estimate, portion: choice.portion)
            onConverted(invoice)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// «Marcar como aceptado…»: quién lo aceptó (la persona de contacto, si la hay) y cuándo.
struct EstimateAcceptView: View {
    let estimate: Estimate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @State private var acceptedBy = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Estimado", value: "\(estimate.number) · \(estimate.total.money)")
                TextField("Aceptado por", text: $acceptedBy, prompt: Text("Nombre de quien lo aceptó"))
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            } footer: {
                Text("Queda anotado en el estimado. Después podrás convertirlo en factura.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Marcar como aceptado")
        .inlineTitle()
        .discardableEditor(tracking: "\(acceptedBy)|\(date)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).headerButton()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            acceptedBy = estimate.customer?.contactName.isEmpty == false ? estimate.customer?.contactName ?? "" : ""
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }

    private func save() {
        do {
            try Bookkeeper(context: context).setStatus(.accepted, of: estimate, acceptedBy: acceptedBy.trimmingCharacters(in: .whitespaces), date: date)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
