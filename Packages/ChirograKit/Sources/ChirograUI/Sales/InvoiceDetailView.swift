import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Factura (canvas: `FacturaDetalle`): aviso de estado, tarjeta con saldo y línea de tiempo, tres acciones,
/// la tarjeta «Registrar pago» en la misma pantalla y, debajo, las líneas, los totales y las notas de crédito.
struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    /// Dentro de la lista y detalle de iPad (`iPadVentas`): sin título propio, que es el de Ventas.
    var embedded = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var companies: [Company]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var showingCreditNote = false
    @State private var showingPreview = false
    @State private var editingDraft = false
    @State private var duplicate: Invoice?
    @State private var confirmingVoid = false
    @State private var errorMessage: String?

    // Registrar pago
    enum PaymentMode: String, CaseIterable, Identifiable {
        case total = "Total", partial = "Parcial"
        var id: String { rawValue }
    }
    @State private var paymentMode: PaymentMode = .total
    @State private var paymentAmount: Int64 = 0
    @State private var paymentDate = Date()
    @State private var depositAccountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var depositAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .creditCard } }
    private var amountToRecord: Int64 { paymentMode == .total ? invoice.balanceDue : paymentAmount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                statusBanner
                statusCard
                actionButtons
                if invoice.isOpen { paymentCard }
                linesCard
                if invoice.status != .draft { totalsCard }
                creditNotesCard
            }
            .padding(Metrics.gutter)
            // En iPad, ancho de lectura hasta que llegue su tablero.
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .modifier(DetailTitle(title: invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number, shown: !embedded))
        .toolbar {
            if invoice.status != .draft && invoice.status != .void {
                ToolbarItem(placement: .primaryAction) { moreMenu }
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }
        }
        .sheet(isPresented: $editingDraft) {
            NavigationStack { InvoiceEditorView(editing: invoice) }
        }
        .sheet(item: $duplicate) { copy in
            NavigationStack { InvoiceEditorView(editing: copy) }
        }
        .sheet(isPresented: $showingCreditNote) {
            NavigationStack { CreditNoteEditorView(invoice: invoice) }
        }
        .confirmationDialog("¿Anular la factura?", isPresented: $confirmingVoid, titleVisibility: .visible) {
            Button("Anular", role: .destructive, action: void)
        } message: {
            Text("Se registrará un asiento de reversión. La factura queda en el historial como anulada.")
        }
        // Al pasar a «Parcial» el monto se vacía para escribir el que se cobra (antes quedaba el saldo completo).
        .onChange(of: paymentMode) { _, mode in paymentAmount = mode == .partial ? 0 : invoice.balanceDue }
        .onAppear {
            paymentAmount = invoice.balanceDue
            depositAccountID = depositAccountID ?? depositAccounts.first { $0.subtype == .bank }?.id
        }
    }

    // MARK: Estado

    @ViewBuilder
    private var statusBanner: some View {
        switch invoice.status {
        case .paid:
            banner(String(localized: "Factura pagada por completo"), systemImage: "checkmark.circle.fill",
                   foreground: Palette.positive, background: Palette.positiveWash)
        case .void:
            banner(String(localized: "Factura anulada"), systemImage: "xmark.circle.fill",
                   foreground: Palette.negative, background: Palette.negativeWash)
        case .draft:
            banner(String(localized: "Borrador: todavía no se ha emitido"), systemImage: "pencil.circle.fill",
                   foreground: Palette.info, background: Palette.infoWash)
        case .sent, .partiallyPaid:
            if let days = invoice.daysOverdue() {
                banner(String(localized: "Vencida hace \(days) días"), systemImage: "exclamationmark.circle.fill",
                       foreground: Palette.negative, background: Palette.negativeWash)
            }
        }
    }

    private func banner(_ text: String, systemImage: String, foreground: Color, background: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow {
                Text(invoice.customer?.name ?? String(localized: "Sin cliente")).font(.subheadline).foregroundStyle(Palette.ink2)
            } trailing: {
                StatusChip(invoice: invoice, compact: false)
            }
            Text(invoice.status == .draft ? invoice.draftAmount.money : invoice.balanceDue.money)
                .font(.amount(34)).tracking(-0.5).foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(summary).font(.subheadline).foregroundStyle(Palette.ink3)
            if invoice.status != .draft && invoice.status != .void { timeline }
        }
        .card()
    }

    private var summary: String {
        switch invoice.status {
        case .draft: String(localized: "Borrador: líneas menos descuento, sin impuesto")
        case .paid, .void: String(localized: "Total de \(invoice.total.money)")
        case .sent, .partiallyPaid: String(localized: "Saldo pendiente de \(invoice.total.money) · vence \(invoice.dueDate.dayMonth)")
        }
    }

    /// Creada → Enviada → Pago → Pagada, con la fecha de cada paso cumplido.
    private var timeline: some View {
        let payments = (invoice.paymentApplications ?? []).compactMap(\.payment?.date).sorted()
        let steps: [(String, String?)] = [
            (String(localized: "Creada"), min(invoice.createdAt, invoice.issueDate).dayMonth),
            (String(localized: "Enviada"), invoice.issueDate.dayMonth),
            (String(localized: "Pago"), payments.first?.dayMonth),
            (String(localized: "Pagada"), invoice.status == .paid ? (payments.last ?? invoice.issueDate).dayMonth : nil),
        ]
        // Con tamaños de accesibilidad, 2×2: en una fila de cuatro se recortaba «Pago».
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(steps.indices, id: \.self) { index in
                let (title, date) = steps[index]
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(date == nil ? Palette.separator : Palette.brand).frame(height: 4)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(date ?? (index == 2 ? String(localized: "Pendiente") : "—"))
                        .font(.caption2).foregroundStyle(Palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Acciones

    @ViewBuilder
    private var actionButtons: some View {
        if invoice.status == .draft {
            VStack(spacing: 8) {
                Button("Emitir factura", action: issue).buttonStyle(.primary)
                HStack(spacing: 8) {
                    Button("Editar borrador") { editingDraft = true }.buttonStyle(.secondary)
                    Button("Vista previa") { showingPreview = true }.buttonStyle(.secondary)
                }
                Button("Eliminar borrador", role: .destructive, action: deleteDraft).buttonStyle(.destructive)
            }
        } else {
            // Con texto grande, uno debajo de otro: en fila se cortaban («Duplic…», «Remin…»).
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                actionTile(String(localized: "Duplicar"), "plus.square.on.square", action: duplicateInvoice)
                actionTile(String(localized: "PDF"), "doc.richtext") { showingPreview = true }
                if invoice.isOpen {
                    ShareLink(item: reminderText, subject: Text("Recordatorio de pago")) {
                        tileLabel(String(localized: "Recordatorio"), "bell")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionTile(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, image) }.buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, _ image: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: image).font(.title3).foregroundStyle(Palette.brand).accessibilityHidden(true)
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Texto del recordatorio: se comparte por Mensajes o Mail (el envío desde la app llega más adelante).
    private var reminderText: String {
        let customer = invoice.customer?.name ?? ""
        return invoice.daysOverdue() == nil
            ? String(localized: "Hola, \(customer): te recordamos que la factura \(invoice.number) por \(invoice.balanceDue.money) vence el \(invoice.dueDate.dayMonth). ¡Gracias!")
            : String(localized: "Hola, \(customer): la factura \(invoice.number) por \(invoice.balanceDue.money) venció el \(invoice.dueDate.dayMonth). ¿Nos ayudas con el pago? ¡Gracias!")
    }

    private var moreMenu: some View {
        Menu {
            if invoice.isOpen, let credit = invoice.customer?.creditBalance, credit > 0 {
                Button("Aplicar saldo a favor (\(min(credit, invoice.balanceDue).money))", systemImage: "arrow.uturn.left", action: applyCredit)
            }
            Button(invoice.status == .paid ? "Nota de crédito o devolución" : "Nota de crédito", systemImage: "minus.circle") {
                showingCreditNote = true
            }
            if invoice.isOpen && invoice.amountPaid == 0 && invoice.creditsApplied == 0 {
                Button("Anular factura", systemImage: "xmark.circle", role: .destructive) { confirmingVoid = true }
            }
        } label: {
            Label("Más acciones", systemImage: "ellipsis")
        }
    }

    // MARK: Registrar pago

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registrar pago").font(.cardTitle)
            // Con tamaños de accesibilidad, menú: el segmentado no crece con el texto.
            let picker = Picker("Tipo de pago", selection: $paymentMode) {
                ForEach(PaymentMode.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .labelsHidden()
            if dynamicTypeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
            VStack(spacing: 0) {
                paymentRow(String(localized: "Monto")) {
                    if paymentMode == .partial {
                        MoneyField(title: String(localized: "Monto"), minorUnits: $paymentAmount)
                            .multilineTextAlignment(.trailing).font(.body.weight(.semibold))
                    } else {
                        Text(invoice.balanceDue.money).font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
                Divider()
                paymentRow(String(localized: "Método")) {
                    Picker("Método", selection: $method) {
                        ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                Divider()
                paymentRow(String(localized: "Depositar en")) {
                    // Menú con etiqueta propia: con AX3 el nombre de la cuenta baja de línea sin cortarse.
                    Menu {
                        AccountPicker(title: String(localized: "Depositar en"), accounts: depositAccounts, selection: $depositAccountID)
                    } label: {
                        HStack(spacing: 4) {
                            Text(depositAccounts.first { $0.id == depositAccountID }?.displayName ?? String(localized: "Elegir…"))
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
                        }
                        .foregroundStyle(Palette.brand)
                    }
                    .accessibilityLabel("Depositar en")
                }
                Divider()
                paymentRow(String(localized: "Fecha")) {
                    DatePicker("Fecha", selection: $paymentDate, displayedComponents: .date).labelsHidden()
                }
            }
            .padding(.horizontal, 12)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("Registrar \(amountToRecord.money)", action: recordPayment)
                .buttonStyle(.primary)
                .disabled(amountToRecord <= 0 || amountToRecord > invoice.balanceDue || depositAccountID == nil)
        }
        .card()
    }

    private func paymentRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).foregroundStyle(Palette.ink2).fixedSize()
                Spacer(minLength: 8)
                content()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(Palette.ink2)
                content()
            }
        }
        .frame(minHeight: 48)
    }

    // MARK: Líneas, totales y créditos

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Productos y servicios"))
            ForEach(invoice.sortedLines) { line in
                AdaptiveRow(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.details.isEmpty ? String(localized: "Sin descripción") : line.details).fontWeight(.semibold)
                        Text(line.isTaxable ? "\(line.quantity.formatted()) × \(line.unitPrice.money) · gravable"
                                             : "\(line.quantity.formatted()) × \(line.unitPrice.money)")
                            .font(.footnote).foregroundStyle(Palette.ink3)
                    }
                } trailing: {
                    Text(line.amount.money).monospacedDigit().fontWeight(.semibold)
                }
                .foregroundStyle(Palette.ink)
            }
        }
        .card()
    }

    private var totalsCard: some View {
        VStack(spacing: 8) {
            LabeledContent("Subtotal", value: invoice.subtotal.money)
            if invoice.discount > 0 { LabeledContent("Descuento", value: "−\(invoice.discount.money)") }
            ForEach(invoice.taxLines ?? []) { tax in
                LabeledContent("\(tax.name) · \((Decimal(tax.rateMillionths) / 10_000).formatted())%", value: tax.amount.money)
            }
            Divider()
            LabeledContent("Total", value: invoice.total.money).fontWeight(.semibold)
            LabeledContent("Cobrado", value: invoice.amountPaid.money)
            if invoice.creditsApplied > 0 { LabeledContent("Notas de crédito", value: "−\(invoice.creditsApplied.money)") }
        }
        .font(.subheadline)
        .monospacedDigit()
        .card()
    }

    @ViewBuilder
    private var creditNotesCard: some View {
        let notes = (invoice.creditNotes ?? []).sorted { $0.date < $1.date }
        let applications = (invoice.creditApplications ?? []).sorted { $0.date < $1.date }
        if !notes.isEmpty || !applications.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !notes.isEmpty {
                    SectionLabel(text: String(localized: "Notas de crédito de esta factura"))
                    ForEach(notes) { note in
                        LabeledContent {
                            Text("−\(note.total.money)").monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.number)
                                Text("\(note.date.shortDate)\(note.reason.isEmpty ? "" : " · \(note.reason)")")
                                    .font(.subheadline).foregroundStyle(Palette.ink3)
                                if note.unappliedAmount > 0 {
                                    Text("\(note.unappliedAmount.money) quedan a favor del cliente")
                                        .font(.subheadline).foregroundStyle(Palette.positive)
                                }
                            }
                        }
                    }
                }
                if !applications.isEmpty {
                    SectionLabel(text: String(localized: "Créditos aplicados"))
                    ForEach(applications) { application in
                        LabeledContent("\(application.note?.number ?? String(localized: "Nota")) · \(application.date.shortDate)",
                                       value: "−\(application.amount.money)")
                    }
                }
            }
            .card()
        }
    }

    // MARK: Operaciones

    private func issue() {
        do { try books.issue(invoice); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    private func recordPayment() {
        guard let account = accounts.first(where: { $0.id == depositAccountID }) else { return }
        do {
            try books.recordPayment(for: invoice, amount: amountToRecord, date: paymentDate, depositAccount: account, method: method)
            errorMessage = nil
            paymentAmount = invoice.balanceDue
            paymentMode = .total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Nuevo borrador con el mismo cliente, líneas, impuesto y mensaje, fechado hoy; se abre para revisarlo.
    private func duplicateInvoice() {
        let terms = invoice.customer?.paymentTermsDays ?? 30
        let input = InvoiceDraftInput(
            customer: invoice.customer, issueDate: .now,
            dueDate: Calendar.current.date(byAdding: .day, value: terms, to: .now) ?? .now,
            taxGroupID: invoice.taxGroupID, discount: invoice.discount, customerMessage: invoice.customerMessage,
            lines: invoice.sortedLines.map {
                .init(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice, isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
            }
        )
        do { duplicate = try books.saveDraft(input, into: nil) } catch { errorMessage = error.localizedDescription }
    }

    private func applyCredit() {
        guard let credit = invoice.customer?.creditBalance else { return }
        do { try books.applyCustomerCredit(to: invoice, amount: min(credit, invoice.balanceDue)); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func void() {
        do { try books.void(invoice); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    private func deleteDraft() {
        context.delete(invoice)
        try? context.save()
        dismiss()
    }
}

extension PaymentMethod {
    var title: String {
        switch self {
        case .cash: String(localized: "Efectivo")
        case .check: String(localized: "Cheque")
        case .bankTransfer: String(localized: "Transferencia")
        case .card: String(localized: "Tarjeta")
        case .other: String(localized: "Otro")
        }
    }
}

/// Nota de crédito contra la factura: importe neto, si es gravable y motivo. El impuesto usa el grupo de la factura.
struct CreditNoteEditorView: View {
    let invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira al guardar, antes de cerrar.
    @State private var editorToken = EditorToken()
    @State private var amount: Int64 = 0
    @State private var isTaxable = true
    @State private var reason = ""
    @State private var date = Date()
    /// Línea de la factura que se acredita; `nil` reparte el importe entre todas en proporción.
    @State private var lineID: UUID?
    @State private var errorMessage: String?
    @Query(sort: \Account.code) private var accounts: [Account]

    private var books: Bookkeeper { Bookkeeper(context: context) }

    private var creditLines: [SalesLine] {
        (try? books.creditLines(for: invoice, amount: amount, isTaxable: isTaxable, lineID: lineID)) ?? []
    }

    private var preview: InvoicePosting? {
        let components = (try? books.taxComponents(groupID: invoice.taxGroupID, on: invoice.issueDate)) ?? []
        return try? PostingRules.creditNote(date: date, memo: "", receivableAccountID: UUID(), lines: creditLines,
                                            taxComponents: components, customerIsTaxExempt: invoice.customer?.isTaxExempt ?? false)
    }

    /// Cuánto rebaja la nota en cada cuenta de ingresos, para que se vea antes de emitirla.
    private var incomeByAccount: [(name: String, amount: Int64)] {
        Dictionary(grouping: creditLines, by: \.incomeAccountID)
            .map { id, lines in (accounts.first { $0.id == id }?.name ?? String(localized: "Ingresos"), lines.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Factura", value: "\(invoice.number) · \(invoice.customer?.name ?? "")")
                LabeledContent("Saldo pendiente", value: invoice.balanceDue.money)
            }
            Section {
                if invoice.sortedLines.count > 1 {
                    Picker("Qué se acredita", selection: $lineID) {
                        Text("Todas las líneas (proporcional)").tag(UUID?.none)
                        ForEach(invoice.sortedLines) { line in
                            Text("\(line.details) · \(line.amount.money)").tag(Optional(line.id))
                        }
                    }
                }
                MoneyField(title: String(localized: "Importe a acreditar (sin impuesto)"), minorUnits: $amount)
                Toggle("Incluye sales tax", isOn: $isTaxable)
                TextField("Motivo (devolución, ajuste de precio…)", text: $reason)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            }
            Section {
                let total = preview?.total ?? 0
                ForEach(incomeByAccount, id: \.name) { row in
                    LabeledContent("Rebaja \(row.name)", value: row.amount.money)
                }
                LabeledContent("Sales tax", value: (preview?.totalTax ?? 0).money)
                LabeledContent("Total de la nota", value: total.money).fontWeight(.semibold)
                if total > 0 {
                    LabeledContent("Se aplica a esta factura", value: min(total, invoice.balanceDue).money)
                    if total > invoice.balanceDue {
                        LabeledContent("Queda a favor del cliente", value: (total - invoice.balanceDue).money)
                            .foregroundStyle(Palette.positive)
                    }
                }
            } footer: {
                Text(String(localized: "Se registra un asiento que reduce ingresos, sales tax por pagar y la cuenta por cobrar del cliente. ")
                     + String(localized: "Lo que no cubra el saldo de esta factura queda a favor del cliente: puedes aplicarlo a otra factura o reembolsarlo desde su ficha."))
            }
        }
        .screenBackground()
        .navigationTitle("Nota de crédito")
        .inlineTitle()
        .discardableEditor(tracking: "\(amount)|\(isTaxable)|\(reason)|\(date)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Emitir", action: save).disabled(amount <= 0 || reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            isTaxable = !(invoice.taxLines ?? []).isEmpty
            if invoice.sortedLines.count == 1 { lineID = invoice.sortedLines.first?.id }
        }
        .onChange(of: lineID) {
            guard let line = invoice.sortedLines.first(where: { $0.id == lineID }) else { return }
            isTaxable = line.isTaxable && !(invoice.taxLines ?? []).isEmpty
        }
    }

    private func save() {
        do {
            try books.issueCreditNote(for: invoice, amount: amount, isTaxable: isTaxable, reason: reason, date: date, lineID: lineID)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Título en línea de la factura, salvo cuando va dentro de la lista y detalle de iPad.
private struct DetailTitle: ViewModifier {
    let title: String
    let shown: Bool
    func body(content: Content) -> some View {
        if shown { content.navigationTitle(title).inlineTitle() } else { content }
    }
}
