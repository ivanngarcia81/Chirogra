import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import TipKit

/// Factura. iPhone (canvas `FacturaDetalle`): cliente, saldo de 40 y estado centrados; baldosas Duplicar · PDF ·
/// Recordatorio; «Registrar pago» como grupo con Total · Parcial y el botón dentro; «Actividad» con círculos de Tinta.
/// iPad y Mac (canvas `iPadVentas`, columna derecha): el resumen a la izquierda, las acciones en la barra y «Actividad»
/// antes de «Registrar pago». Debajo, en todos, las líneas, los totales y las notas de crédito.
struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    /// Dentro de la lista y detalle de iPad (`iPadVentas`): sin título propio, que es el de Ventas.
    var embedded = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ActiveCompanyQuery private var companies: [Company]
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var showingCreditNote = false
    @State private var showingPreview = false
    /// «Enviar factura» (y «PDF»): la hoja de envío con Para y Asunto (canvas `FacturaEnviar`).
    @State private var sending = false
    /// «Recordatorio»: la misma hoja con el texto del recordatorio; al enviarlo queda anotado.
    @State private var reminding = false
    @State private var editingDraft = false
    @State private var duplicate: Invoice?
    @State private var confirmingVoid = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    /// Banca 1.2: anular algo conciliado pide confirmación (`ReconciledChange`).
    @State private var reconciledRetry: ReconciledChangeRetry?
    /// Borrador recién emitido desde aquí: se ofrece enviarlo (`offerToSendIssued`).
    @State private var justIssued: Invoice?
    /// El campo «Monto» de «Parcial» tiene el foco: se desplaza hasta «Registrar $…» para que el teclado no lo tape.
    @FocusState private var amountFocused: Bool

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
    private var isDraft: Bool { invoice.status == .draft }
    private var remindedToday: Bool { invoice.lastReminderDate.map(Calendar.current.isDateInToday) ?? false }
    /// Emitida y aún sin enviar por correo desde la app: se propone «Enviar factura».
    private var needsSending: Bool { invoice.isOpen && invoice.lastSentDate == nil }

    /// iPad (columna ancha) y Mac: el detalle de `iPadVentas`; en el iPhone y la columna estrecha, el de `FacturaDetalle`.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let errorMessage { ErrorBanner(message: errorMessage).padding(.bottom, 12) }
                    summary
                    if isDraft {
                        draftActions.padding(.top, 16)
                    } else {
                        if needsSending {
                            Button("Enviar factura", systemImage: "paperplane") { sending = true }
                                .buttonStyle(.primary)
                                .padding(.top, 14)
                        }
                        if !isWide { actionTiles.padding(.top, 14) }
                    }
                    if !isDraft {
                        if isWide {
                            activity
                            if invoice.isOpen { paymentSection }
                        } else {
                            if invoice.isOpen { paymentSection }
                            activity
                        }
                    }
                    linesSection
                    totalsSection
                    creditNotesSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
            }
            // «Registrar pago › Parcial»: el teclado decimal no tiene tecla para cerrarse y tapaba «Registrar $…»
            // (recorrido «cliente nuevo», 5-nov). Ahora lleva «Listo», se cierra al desplazar y, al escribir el monto,
            // la pantalla sube hasta el botón.
            .keyboardDoneButton()
            .onChange(of: amountFocused) { _, focused in
                guard focused else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    // En el centro y no abajo: abajo quedaba bajo el «Listo» flotante del teclado.
                    withAnimation { proxy.scrollTo(Self.recordButtonID, anchor: .center) }
                }
            }
        }
        .background(Palette.background)
        .modifier(DetailTitle(title: invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number, shown: !embedded))
        .toolbar {
            // `iPadVentas`: Duplicar · Compartir PDF · Recordatorio en un grupo de vidrio de la barra.
            if isWide && !isDraft {
                ToolbarItemGroup(placement: .primaryAction) {
                    if books.canEditIssued(invoice) {
                        Button("Editar factura", systemImage: "pencil") { editingDraft = true }.headerButton()
                    } else {
                        Button("Duplicar", systemImage: "plus.square.on.square", action: duplicateInvoice).headerButton()
                    }
                    Button("PDF", systemImage: "doc.richtext") { sending = true }.headerButton()
                    if invoice.isOpen {
                        Button(remindedToday ? "Recordatorio enviado hoy" : "Recordatorio",
                               systemImage: remindedToday ? "checkmark" : "bell") { reminding = true }
                            .headerButton()
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }.editorSheetSizing()
        }
        .sheet(isPresented: $sending) {
            NavigationStack { SendDocumentView(source: .invoice(invoice)) }.editorSheetSizing()
        }
        .sheet(isPresented: $reminding) {
            NavigationStack { SendDocumentView(source: .invoice(invoice), purpose: .reminder) }.editorSheetSizing()
        }
        .sheet(isPresented: $editingDraft) {
            NavigationStack { InvoiceEditorView(editing: invoice) }.editorSheetSizing()
        }
        .sheet(item: $duplicate) { copy in
            NavigationStack { InvoiceEditorView(editing: copy) }.editorSheetSizing()
        }
        .sheet(isPresented: $showingCreditNote) {
            NavigationStack { CreditNoteEditorView(invoice: invoice) }.editorSheetSizing()
        }
        .offerToSendIssued($justIssued)
        .reconciledChangeConfirmation($reconciledRetry) { errorMessage = $0 }
        .confirmationDialog("¿Anular la factura?", isPresented: $confirmingVoid, titleVisibility: .visible) {
            Button("Anular", role: .destructive, action: void)
        } message: {
            Text("Se registrará un asiento de reversión. La factura queda en el historial como anulada.")
        }
        .confirmationDialog("¿Eliminar el borrador?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar borrador", role: .destructive, action: deleteDraft)
        }
        // Al pasar a «Parcial» el monto se vacía para escribir el que se cobra (antes quedaba el saldo completo).
        .onChange(of: paymentMode) { _, mode in paymentAmount = mode == .partial ? 0 : invoice.balanceDue }
        .onAppear {
            paymentAmount = invoice.balanceDue
            depositAccountID = depositAccountID ?? depositAccounts.first { $0.subtype == .bank }?.id
        }
    }

    // MARK: Resumen

    /// Cliente, saldo (o importe del borrador) y estado: centrados en el iPhone, a la izquierda en iPad y Mac.
    @ViewBuilder
    private var summary: some View {
        let customer = invoice.customer?.name ?? String(localized: "Sin cliente")
        // Abierta: lo que falta por cobrar. Pagada o anulada: el total (un «$0.00» grande no dice nada).
        // Borrador: el total con las reglas de emisión (impuesto, descuento, impuesto incluido), como el PDF.
        let shown = isDraft ? ((try? books.totals(for: invoice).total) ?? invoice.draftAmount)
            : (invoice.status == .paid || invoice.status == .void) ? invoice.total : invoice.balanceDue
        let amount = Text(shown.money)
            .font(.system(.largeTitle, weight: .bold)).monospacedDigit()
            .foregroundStyle(Palette.ink)
            .minimumScaleFactor(0.6).lineLimit(1)
        if isWide {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number.isEmpty ? customer : "\(customer) · \(invoice.number)")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                amount
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        StatusChip(invoice: invoice, compact: false).fixedSize()
                        Text(verbatim: "·").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                        Text(detail).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        StatusChip(invoice: invoice, compact: false)
                        Text(detail).font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                }
                if remindedToday && invoice.isOpen { reminderNote }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 2) {
                Text(customer).font(.subheadline).foregroundStyle(Palette.ink2)
                amount
                StatusChip(invoice: invoice, compact: false)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center).padding(.top, 2)
                if remindedToday && invoice.isOpen { reminderNote.padding(.top, 2) }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }

    /// «✓ Recordatorio enviado hoy» (canvas `MacClienteFicha`).
    private var reminderNote: some View {
        Label("Recordatorio enviado hoy", systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.positive)
    }

    private var detail: String {
        switch invoice.status {
        // La fecha a la vista antes de emitir: el borrador de un estimado convertido no la enseñaba (QA Hudson, H01).
        case .draft: String(localized: "Borrador con fecha \(invoice.issueDate.shortDate) · vence el \(invoice.dueDate.shortDate). El asiento se registra al emitirla.")
        case .paid:
            // Saldada en parte con notas de crédito: lo cobrado y lo acreditado por separado (QA Hudson, H09: decía
            // «Total cobrado $2,400» con $2,000 cobrados y $400 de nota de crédito).
            invoice.total - invoice.amountPaid > 0
                ? String(localized: "Saldada: cobrado \(invoice.amountPaid.money) + crédito \((invoice.total - invoice.amountPaid).money)")
                : String(localized: "Total cobrado \(invoice.total.money)")
        case .void: String(localized: "Total de \(invoice.total.money)")
        case .sent, .partiallyPaid:
            invoice.balanceDue < invoice.total
                ? String(localized: "Por cobrar de un total de \(invoice.total.money) · vence \(invoice.dueDate.dayMonth)")
                : String(localized: "Por cobrar · vence \(invoice.dueDate.dayMonth)")
        }
    }

    // MARK: Acciones

    /// Borrador: «Emitir factura» y, debajo, Editar · Vista previa · Eliminar.
    private var draftActions: some View {
        VStack(spacing: 8) {
            Button("Emitir factura", action: issue).buttonStyle(.primary)
            tileRow {
                actionTile(String(localized: "Editar"), "pencil") { editingDraft = true }
                actionTile(String(localized: "Vista previa"), "doc.richtext") { showingPreview = true }
                actionTile(String(localized: "Eliminar"), "trash", tint: Palette.negative) { confirmingDelete = true }
            }
        }
    }

    /// Canvas `FacturaDetalle`: Duplicar · PDF · Recordatorio en baldosas `surface` de radio 16. Mientras la emitida se
    /// puede corregir, la primera baldosa es «Editar» (Duplicar sigue en «⋯»): escondido en el menú no se encontraba
    /// (recorrido «cliente nuevo», 6-nov).
    private var actionTiles: some View {
        tileRow {
            if books.canEditIssued(invoice) {
                actionTile(String(localized: "Editar"), "pencil") { editingDraft = true }
                    .accessibilityLabel("Editar factura")
            } else {
                actionTile(String(localized: "Duplicar"), "plus.square.on.square", action: duplicateInvoice)
            }
            actionTile(String(localized: "PDF"), "doc.richtext") { sending = true }
            if invoice.isOpen {
                if remindedToday {
                    actionTile(String(localized: "Enviado hoy"), "checkmark.circle", tint: Palette.positive) { reminding = true }
                        .accessibilityLabel("Recordatorio enviado hoy")
                } else {
                    actionTile(String(localized: "Recordatorio"), "bell") { reminding = true }
                }
            }
        }
    }

    /// Con texto grande, una debajo de otra: en fila se cortaban («Duplic…», «Remin…»).
    private func tileRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }

    private func actionTile(_ title: String, _ image: String, tint: Color = Palette.brand, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, image, tint: tint) }.buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, _ image: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            // Alto fijo del ícono: el lápiz de «Editar» es más bajo que los otros y subía su texto.
            Image(systemName: image).font(.title3).frame(height: 28).accessibilityHidden(true)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// «⋯» de la barra (canvas: editar, duplicar, anular).
    private var moreMenu: some View {
        Menu {
            if isDraft {
                Button("Editar borrador", systemImage: "pencil") { editingDraft = true }
                Button("Eliminar borrador", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } else {
                Button("Duplicar", systemImage: "plus.square.on.square", action: duplicateInvoice)
                if invoice.isOpen, let credit = invoice.customer?.creditBalance, credit > 0 {
                    Button("Aplicar saldo a favor (\(min(credit, invoice.balanceDue).money))", systemImage: "arrow.uturn.left", action: applyCredit)
                }
                if books.canEditIssued(invoice) {
                    // Corrige la emitida: revierte su asiento y registra uno nuevo, con el mismo número.
                    Button("Editar factura", systemImage: "pencil") { editingDraft = true }
                }
                if invoice.status != .void {
                    Button(invoice.status == .paid ? "Nota de crédito o devolución" : "Nota de crédito", systemImage: "minus.circle") {
                        showingCreditNote = true
                    }
                }
                let canVoid = invoice.isOpen && invoice.amountPaid == 0 && invoice.creditsApplied == 0
                if canVoid {
                    Button("Anular factura", systemImage: "xmark.circle", role: .destructive) { confirmingVoid = true }
                }
                if invoice.status != .void && !books.canEditIssued(invoice) {
                    // «Editar» y «Anular» se ven desactivados con el motivo encima (QA Hudson, H21: desaparecían del
                    // menú sin explicar por qué): con cobros o créditos el asiento ya tiene otros que dependen de él.
                    Section {
                        Button("Editar factura", systemImage: "pencil") {}.disabled(true)
                        if !canVoid {
                            Button("Anular factura", systemImage: "xmark.circle") {}.disabled(true)
                        }
                    } header: {
                        Text(invoice.amountPaid > 0 ? "Tiene cobros: usa una nota de crédito." : "Tiene créditos aplicados: usa una nota de crédito.")
                    }
                }
            }
        } label: {
            Label("Más acciones", systemImage: "ellipsis")
        }
        .headerButton()
    }

    // MARK: Actividad

    /// Creada → Emitida → envíos, recordatorios y ediciones por fecha (con su destinatario) → Pago → Pagada (o Anulada),
    /// con círculos rellenos de Tinta en los pasos cumplidos. Sin envío anotado y pendiente de cobro, el paso por hacer
    /// es «Enviar al cliente» (antes «Enviada · Sin enviar», que se leía como si ya se hubiera mandado).
    private var activity: some View {
        let payments = (invoice.paymentApplications ?? []).compactMap(\.payment?.date).sorted()
        var steps: [(title: String, detail: String, value: String, done: Bool)] = [
            (String(localized: "Creada"), "", min(invoice.createdAt, invoice.issueDate).dayMonth, true),
            (String(localized: "Emitida"), "", invoice.issueDate.dayMonth, true),
        ]
        let events = invoice.sortedEvents.reversed()
        var dated: [(date: Date, step: (title: String, detail: String, value: String, done: Bool))] = events.map { event in
            (event.date, (event.kind == .sent ? String(localized: "Enviada") : String(localized: "Recordatorio enviado"),
                          event.recipient, event.date.dayMonth, true))
        }
        for edit in (try? books.edits(of: invoice)) ?? [] {
            dated.append((edit.date, (String(localized: "Editada"),
                                      edit.action == "edit" ? String(localized: "Asiento revertido y registrado de nuevo") : "",
                                      edit.date.dayMonth, true)))
        }
        steps += dated.sorted { $0.date < $1.date }.map(\.step)
        if invoice.isOpen && !events.contains(where: { $0.kind == .sent }) {
            steps.append((String(localized: "Enviar al cliente"), "", String(localized: "Pendiente"), false))
        }
        if invoice.status == .void {
            steps.append((String(localized: "Anulada"), "", "", true))
        } else {
            steps.append((String(localized: "Pago"), "", invoice.amountPaid > 0 ? invoice.amountPaid.money : String(localized: "Pendiente"), invoice.amountPaid > 0))
            steps.append((String(localized: "Pagada"), "", invoice.status == .paid ? (payments.last ?? invoice.issueDate).dayMonth : "—",
                          invoice.status == .paid))
        }
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Actividad"))
            VStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { index in
                    let step = steps[index]
                    if index > 0 { Divider().padding(.leading, Metrics.cardPadding + 34) }
                    HStack(spacing: 12) {
                        ActivityMark(done: step.done)
                        AdaptiveRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title).foregroundStyle(step.done ? Palette.ink : Palette.ink2)
                                if !step.detail.isEmpty {
                                    Text(step.detail).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2).truncationMode(.middle)
                                }
                            }
                        } trailing: {
                            Text(step.value).foregroundStyle(Palette.ink2).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 6)
                    .frame(minHeight: Metrics.target)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(step.done ? Text("Hecho") : Text("Pendiente"))
                }
            }
            .card(padding: 0)
        }
    }

    // MARK: Registrar pago

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Registrar pago"))
            InlineTip(tip: RecordPaymentTip()).padding(.bottom, 8)
            VStack(spacing: 0) {
                FilterPicker(title: String(localized: "Tipo de pago"), options: PaymentMode.allCases, selection: $paymentMode, label: \.localizedTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                paymentRow(String(localized: "Monto")) {
                    if paymentMode == .partial {
                        MoneyField(title: String(localized: "Monto"), minorUnits: $paymentAmount)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                    } else {
                        Text(invoice.balanceDue.money).monospacedDigit().foregroundStyle(Palette.ink)
                            .accessibilityLabel("Monto")
                            .accessibilityValue(invoice.balanceDue.money)
                    }
                }
                paymentRow(String(localized: "Método")) {
                    // Menú con etiqueta propia, en gris como el canvas; VoiceOver lee nombre y valor en un elemento.
                    Menu {
                        Picker("Método", selection: $method) {
                            ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        menuLabel(method.title)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Método")
                    .accessibilityValue(method.title)
                }
                paymentRow(String(localized: "Depositar en")) {
                    let depositName = depositAccounts.first { $0.id == depositAccountID }?.displayName ?? String(localized: "Elegir…")
                    // Menú con etiqueta propia: con AX3 el nombre de la cuenta baja de línea sin cortarse.
                    Menu {
                        AccountPicker(title: String(localized: "Depositar en"), accounts: depositAccounts, selection: $depositAccountID)
                    } label: {
                        menuLabel(depositName)
                    }
                    .buttonStyle(.plain)
                    // Como «Método»: VoiceOver lee el nombre y la cuenta elegida en un solo elemento.
                    .accessibilityLabel("Depositar en")
                    .accessibilityValue(depositName)
                }
                paymentRow(String(localized: "Fecha")) {
                    DatePicker("Fecha", selection: $paymentDate, displayedComponents: .date).labelsHidden()
                        #if os(iOS)
                        // El botón compacto de UIKit se anuncia como «Selector de fecha»: se sustituye por
                        // «Fecha, <día>». Al tocar dos veces, VoiceOver toca el centro y abre el calendario.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Fecha")
                        .accessibilityValue(paymentDate.formatted(date: .long, time: .omitted))
                        .accessibilityAddTraits(.isButton)
                        #endif
                }
                ClosedPeriodDateNote(date: paymentDate)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.top, 4)
                // Por qué el botón está gris (QA Hudson, H11: un cobro mayor que el saldo o de $0 no lo decía).
                if paymentMode == .partial && (paymentAmount > invoice.balanceDue || paymentAmount <= 0) {
                    Text(paymentAmount > invoice.balanceDue
                         ? String(localized: "Máximo \(invoice.balanceDue.money) (saldo pendiente).")
                         : String(localized: "Escribe el monto cobrado: hasta \(invoice.balanceDue.money)."))
                        .font(.footnote)
                        .foregroundStyle(paymentAmount > invoice.balanceDue ? Palette.negative : Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                        .padding(.top, 4)
                }
                if !isWide {
                    recordButton.padding(.horizontal, Metrics.cardPadding).padding(.top, 6).padding(.bottom, 16)
                }
            }
            .card(padding: 0)
            // `iPadVentas`: el botón va debajo del grupo.
            if isWide { recordButton.padding(.top, 16) }
        }
    }

    private static let recordButtonID = "registrarPago"

    private var recordButton: some View {
        Button("Registrar \(amountToRecord.money)", action: recordPayment)
            .buttonStyle(.primary)
            .disabled(amountToRecord <= 0 || amountToRecord > invoice.balanceDue || depositAccountID == nil)
            .id(Self.recordButtonID)
    }

    /// Valor de un menú del formulario: en gris con el símbolo de menú, y en varias líneas si no cabe.
    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
        }
        .foregroundStyle(Palette.ink2)
        .frame(minHeight: Metrics.target)
        .contentShape(Rectangle())
    }

    /// Fila «etiqueta · valor» del grupo, con la línea sangrada; si no cabe, el valor baja.
    private func paymentRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, Metrics.cardPadding)
            ViewThatFits(in: .horizontal) {
                // El título visible no se anuncia: cada control ya lleva su nombre y su valor («Método, Transferencia»);
                // si no, VoiceOver lo leía dos veces.
                HStack {
                    Text(title).foregroundStyle(Palette.ink).fixedSize().accessibilityHidden(true)
                    Spacer(minLength: 8)
                    content()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(Palette.ink).accessibilityHidden(true)
                    content()
                }
            }
            .padding(.horizontal, Metrics.cardPadding)
            .frame(minHeight: Metrics.target)
        }
    }

    // MARK: Líneas, totales y créditos

    /// Encabezado de grupo del canvas («Registrar pago», «Actividad»): `.footnote` gris, alineado con el texto.
    private func sectionLabel(_ text: String) -> some View {
        SectionLabel(text: text)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.top, 22)
            .padding(.bottom, 7)
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "Productos y servicios"))
            VStack(spacing: 0) {
                ForEach(Array(invoice.sortedLines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                    AdaptiveRow(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.details.isEmpty ? String(localized: "Sin descripción") : line.details).foregroundStyle(Palette.ink)
                            Text(line.isTaxable ? "\(line.quantity.formatted()) × \(line.unitPrice.money) · gravable"
                                                 : "\(line.quantity.formatted()) × \(line.unitPrice.money)")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    } trailing: {
                        Text(line.amount.money).monospacedDigit().foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
                if invoice.sortedLines.isEmpty {
                    Text("Sin líneas").foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                }
            }
            .card(padding: 0)
        }
    }

    /// Subtotal, descuento, impuesto, total, cobrado y notas de crédito. Con precios con impuesto incluido el impuesto
    /// va después del total, en gris («Incluye Austin 8.25 %»): Subtotal − Descuento = Total (DATOS-V2 §4).
    private var totalsSection: some View {
        // Un borrador aún no tiene los totales guardados: los calcula `SalesDocument` como al emitirlo.
        let base: [SalesDocument.Total] = isDraft ? SalesDocument(invoice: invoice).totals : SalesDocument.rows(
            subtotal: invoice.subtotal, discount: invoice.discount,
            taxes: (invoice.taxLines ?? []).sorted { $0.name < $1.name }.map { ($0.name, $0.rateMillionths, $0.amount) },
            total: invoice.total, pricesIncludeTax: invoice.pricesIncludeTax)
        var rows: [(String, String, Bool, Bool)] = base.map { ($0.title, $0.value, $0.style == .accent, $0.style == .subtle) }
        if !isDraft { rows.append((String(localized: "Cobrado"), invoice.amountPaid.money, false, false)) }
        if invoice.creditsApplied > 0 { rows.append((String(localized: "Notas de crédito"), "−\(invoice.creditsApplied.money)", false, false)) }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let (title, value, bold, subtle) = rows[index]
                if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                AdaptiveRow {
                    Text(title).foregroundStyle(subtle ? Palette.ink2 : Palette.ink).fontWeight(bold ? .semibold : .regular)
                } trailing: {
                    Text(value).monospacedDigit().foregroundStyle(bold ? Palette.ink : Palette.ink2).fontWeight(bold ? .semibold : .regular)
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

    @ViewBuilder
    private var creditNotesSection: some View {
        let notes = (invoice.creditNotes ?? []).sorted { $0.date < $1.date }
        let applications = (invoice.creditApplications ?? []).sorted { $0.date < $1.date }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel(String(localized: "Notas de crédito de esta factura"))
                VStack(spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                        AdaptiveRow(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.number).foregroundStyle(Palette.ink)
                                Text("\(note.date.shortDate)\(note.reason.isEmpty ? "" : " · \(note.reason)")")
                                    .font(.footnote).foregroundStyle(Palette.ink2)
                                if note.unappliedAmount > 0 {
                                    Text("\(note.unappliedAmount.money) quedan a favor del cliente")
                                        .font(.footnote).foregroundStyle(Palette.positive)
                                }
                            }
                        } trailing: {
                            Text("−\(note.total.money)").monospacedDigit().foregroundStyle(Palette.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card(padding: 0)
            }
        }
        if !applications.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel(String(localized: "Créditos aplicados"))
                VStack(spacing: 0) {
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                        if index > 0 { Divider().padding(.leading, Metrics.cardPadding) }
                        AdaptiveRow {
                            Text("\(application.note?.number ?? String(localized: "Nota")) · \(application.date.shortDate)").foregroundStyle(Palette.ink)
                        } trailing: {
                            Text("−\(application.amount.money)").monospacedDigit().foregroundStyle(Palette.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.cardPadding)
                        .padding(.vertical, 6)
                        .frame(minHeight: Metrics.target)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card(padding: 0)
            }
        }
    }

    // MARK: Operaciones

    private func issue() {
        do {
            try books.issue(invoice)
            errorMessage = nil
            justIssued = invoice
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordPayment() {
        guard let account = accounts.first(where: { $0.id == depositAccountID }) else { return }
        do {
            try books.recordPayment(for: invoice, amount: amountToRecord, date: paymentDate, depositAccount: account, method: method)
            RecordPaymentTip().invalidate(reason: .actionPerformed)
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
            dueDate: (try? books.newInvoiceDefaults(for: invoice.customer).dueDate)
                ?? Calendar.current.date(byAdding: .day, value: terms, to: .now) ?? .now,
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
        do { try books.void(invoice); errorMessage = nil } catch {
            // Banca 1.2: si el cobro o la factura están conciliados, se pregunta antes (`ReconciledChange`).
            if let retry = ReconciledChange.retry(for: error, { try $0.void(invoice) }) { reconciledRetry = retry } else { errorMessage = error.localizedDescription }
        }
    }

    /// Borra el borrador dejando lo que tenía en la bitácora (1.2).
    private func deleteDraft() {
        do { try books.deleteDraft(invoice); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

/// Paso de la actividad (canvas `FacturaDetalle`): círculo de 22 pt relleno de Tinta con una marca blanca si está
/// cumplido; si no, un anillo gris.
private struct ActivityMark: View {
    let done: Bool
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        Group {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.5, weight: .bold))
                    .foregroundStyle(Palette.onBrandFill)
                    .frame(width: side, height: side)
                    .background(Palette.brandFill, in: Circle())
            } else {
                Circle().strokeBorder(Palette.chevron, lineWidth: 1.5).frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }
}

extension Invoice {
    /// Texto del recordatorio: se comparte por Mensajes o Mail (el envío desde la app llega más adelante).
    var reminderText: String {
        let customer = customer?.name ?? ""
        return daysOverdue() == nil
            ? String(localized: "Hola, \(customer): te recordamos que la factura \(number) por \(balanceDue.money) vence el \(dueDate.dayMonth). ¡Gracias!")
            : String(localized: "Hola, \(customer): la factura \(number) por \(balanceDue.money) venció el \(dueDate.dayMonth). ¿Nos ayudas con el pago? ¡Gracias!")
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
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]

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
                    .labeledField(String(localized: "Importe a acreditar (sin impuesto)"))
                Toggle("Incluye sales tax", isOn: $isTaxable)
                TextField("Motivo (devolución, ajuste de precio…)", text: $reason)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                ClosedPeriodDateNote(date: date)
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
        .formStyle(.grouped)
        .screenBackground()
        .keyboardDoneButton()
        .navigationTitle("Nota de crédito")
        .inlineTitle()
        .discardableEditor(tracking: "\(amount)|\(isTaxable)|\(reason)|\(date)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Emitir", action: save).disabled(amount <= 0 || reason.trimmingCharacters(in: .whitespaces).isEmpty).headerButton()
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
