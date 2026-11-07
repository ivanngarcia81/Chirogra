import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Nueva factura o edición de un borrador. iPhone (canvas `FacturaNueva`): cliente con monograma; Número · Fecha ·
/// Términos; líneas con la cantidad en una cápsula «− | +»; totales; «Notas y términos»; y una barra de vidrio con el
/// total, «Vista previa» y «Emitir». iPad y Mac (canvas `MacFacturaNueva`): cajas «Cliente» y «Condiciones», tabla de
/// artículos, «Mensaje y términos» y «Totales». Trabaja con estado local y solo escribe en el modelo al guardar, así
/// cancelar no deja nada a medias.
///
/// También es el editor de estimados (`mode: .estimate`, canvas `Estimado`): el mismo formulario con «Concepto», «Válido
/// hasta» en lugar de los términos y «Guardar estimado» en lugar de «Emitir»; no hace asiento. Las facturas y estimados
/// nuevos nacen con los valores de la empresa y del cliente (`Bookkeeper.newInvoiceDefaults`), y los totales siguen las
/// reglas de emisión, también con precios con impuesto incluido.
struct InvoiceEditorView: View {
    /// Factura (nueva o borrador) o estimado (nuevo o existente).
    enum Mode {
        case invoice
        case estimate(Estimate?)
    }

    struct LineDraft: Identifiable {
        let id = UUID()
        var details = ""
        var quantity: Decimal = 1
        var unitPrice: Int64 = 0
        var isTaxable = true
        var incomeAccountID: UUID?

        var amount: Int64 { Money(decimal: quantity * Money(minorUnits: unitPrice).decimalValue).minorUnits }
    }

    var preselectedCustomer: Customer?
    /// Borrador existente que se edita; `nil` para una factura nueva.
    var editing: Invoice?
    var mode: Mode = .invoice

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var amountColumn: CGFloat = 104
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \TaxGroup.name) private var taxGroups: [TaxGroup]
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]
    @Query private var companies: [Company]
    /// «Añadir tasa…» del menú de impuesto (sin ninguna tasa todavía): abre el editor de tasa de Impuestos.
    @State private var addingTaxRate = false

    @State private var customerID: UUID?
    @State private var issueDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    /// «Otra fecha» en Términos: el vencimiento se elige a mano.
    @State private var customDue = false
    @State private var taxGroupID: UUID?
    @State private var lines: [LineDraft] = [LineDraft()]
    @State private var discount: Int64 = 0
    /// «Añadir descuento» muestra el campo (canvas `FacturaNueva`).
    @State private var showingDiscount = false
    @State private var customerMessage = ""
    /// Concepto del estimado («Remodelación del lobby»).
    @State private var estimateTitle = ""
    /// Precios con impuesto incluido: el del borrador o estimado que se edita; `nil` = el de la empresa.
    @State private var pricesIncludeTax: Bool?
    @State private var errorMessage: String?
    @State private var savedInvoice: Invoice?
    @State private var savedEstimate: Estimate?
    @State private var previewingEstimate: Estimate?
    @State private var showingNewCustomer = false
    @State private var previewing: Invoice?
    @State private var confirmingCancel = false
    @State private var confirmingDiscardChanges = false
    /// Lo que había al abrir el editor, para saber si hay cambios sin guardar.
    @State private var baseline: String?
    @Environment(\.unsavedChanges) private var unsavedChanges
    /// Testigo del editor en `UnsavedChanges`: se retira antes de cerrar (al descartar, guardar o emitir), porque
    /// durante la animación de salida seguiría contando y la barra lateral preguntaría sin editor a la vista.
    @State private var editorToken = EditorToken()
    @State private var loadedDraft = false
    /// Al cargar un borrador no se aplican los valores por defecto del cliente (impuesto, vencimiento).
    @State private var skipCustomerDefaults = false
    /// Teclado a la vista (iPhone): la barra de abajo se oculta para no tapar la línea que se edita.
    @State private var keyboardShown = false
    /// Factura recién emitida: se ofrece enviarla antes de cerrar (`offerToSendIssued`).
    @State private var justIssued: Invoice?
    /// Corregir una emitida con fecha en un periodo cerrado: se repite con los libros desbloqueados.
    @State private var closedPeriodRetry: ClosedPeriodRetry?
    /// Ancho del editor (iOS). En la hoja del iPad la clase de tamaño ya es compacta aunque mida 760–980 pt, así que el
    /// diseño ancho se elige por el ancho; `nil` hasta medirlo.
    @State private var width: CGFloat?

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var customer: Customer? { customers.first { $0.id == customerID } }
    private var isEstimate: Bool { if case .estimate = mode { true } else { false } }
    /// Se corrige una factura ya emitida (sin cobros ni créditos): guardar revierte su asiento y registra uno nuevo.
    private var isEditingIssued: Bool { !isEstimate && (editing.map { $0.status != .draft } ?? false) }
    private var editingEstimate: Estimate? { if case .estimate(let estimate) = mode { estimate } else { nil } }
    private var includesTax: Bool { pricesIncludeTax ?? companies.first?.pricesIncludeTax ?? false }
    private var incomeAccounts: [Account] { accounts.filtered { $0.accountType == .income } }
    private var validLines: [LineDraft] { lines.filter { $0.amount > 0 } }
    private var linesSubtotal: Int64 { validLines.reduce(0) { $0 + $1.amount } }
    private var canIssue: Bool { customerID != nil && !validLines.isEmpty }

    private var preview: InvoicePosting? {
        let defaultIncome = incomeAccounts.first?.id ?? UUID()
        let components = (try? books.taxComponents(groupID: taxGroupID, on: issueDate)) ?? []
        return try? PostingRules.invoice(
            date: issueDate, memo: "", receivableAccountID: UUID(),
            lines: validLines.map { SalesLine(incomeAccountID: $0.incomeAccountID ?? defaultIncome, amount: $0.amount, isTaxable: $0.isTaxable) },
            taxComponents: components, customerIsTaxExempt: customer?.isTaxExempt ?? false,
            discount: discount, discountAccountID: discount > 0 ? UUID() : nil, pricesIncludeTax: includesTax
        )
    }

    /// «Sales tax» o, con precios con impuesto incluido, «Sales tax incluido» (no se suma: ya va en el subtotal).
    private var taxRowTitle: String { includesTax ? String(localized: "Sales tax incluido") : String(localized: "Sales tax") }

    /// Lo que escribe el usuario (no los valores por defecto que pone el cliente).
    private var signature: String {
        let lineText = lines.map { "\($0.details)|\($0.quantity)|\($0.unitPrice)|\($0.isTaxable)" }.joined(separator: ";")
        return "\(customerID?.uuidString ?? "")#\(lineText)#\(discount)#\(customerMessage)#\(estimateTitle)"
    }

    private var editorTitle: String {
        if isEstimate { return editingEstimate == nil ? String(localized: "Nuevo estimado") : String(localized: "Editar estimado") }
        if isEditingIssued { return String(localized: "Editar factura") }
        return editing == nil ? String(localized: "Nueva factura") : String(localized: "Editar borrador")
    }

    /// «Emitir factura» o «Guardar estimado».
    private var primaryTitle: String {
        if isEditingIssued { return String(localized: "Guardar cambios") }
        return isEstimate ? String(localized: "Guardar estimado") : String(localized: "Emitir factura")
    }

    private var ledgerNote: String {
        if isEditingIssued {
            return String(localized: "Si solo cambias el vencimiento, el mensaje o las descripciones, no se registra ningún asiento.")
        }
        return isEstimate
            ? String(localized: "Un estimado no registra nada en la contabilidad. Al convertirlo en factura se crea un borrador.")
            : String(localized: "Al emitirla se registra el asiento contable: débito a cuentas por cobrar, crédito a ingresos y sales tax.")
    }

    /// Aviso de arriba al corregir una emitida (como el de los gastos contabilizados).
    private var issuedNoticeText: String {
        String(localized: "Esta factura ya está en tus libros. Al guardar, Chirogra revierte su asiento y registra uno nuevo con los cambios; conserva el número \(editing?.number ?? "") y la edición queda en su actividad.")
    }

    private var issuedNotice: some View {
        Label {
            Text(issuedNoticeText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Palette.info)
        }
        .foregroundStyle(Palette.ink)
    }

    private var hasChanges: Bool { hasNewDraft || (baseline.map { $0 != signature } ?? false) }

    var body: some View {
        Group {
            if isWide { wideForm } else { compactForm }
        }
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #endif
        .sheet(item: $previewing) { invoice in
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }.editorSheetSizing()
        }
        .sheet(item: $previewingEstimate) { estimate in
            NavigationStack { DocumentPreviewView(source: .estimate(estimate), company: companies.first) }.editorSheetSizing()
        }
        .navigationTitle(editorTitle)
        #if os(macOS)
        .modifier(InlineTitleUnless(wide: isWide))
        // La hoja tomaba ~684 pt y la tabla de artículos iba apretada (2-nov): ancho de `MacFacturaNueva`.
        .frame(minWidth: 860, idealWidth: 920, minHeight: 620, idealHeight: 760)
        #else
        // En línea también en la hoja ancha del iPad: con el título grande, «×» se iba al menú de desbordamiento.
        .inlineTitle()
        #endif
        .toolbar {
            // Los avisos van anclados a «Cancelar»: en la vista dividida del iPad salían sobre la barra lateral.
            ToolbarItem(placement: .cancellationAction) {
                Button(action: cancel) {
                    #if os(macOS)
                    Text("Cancelar")
                    #else
                    // Canvas `FacturaNueva`: «×» de vidrio.
                    Label("Cancelar", systemImage: "xmark").labelStyle(.iconOnly)
                    #endif
                }
                .confirmationDialog(isEstimate ? "¿Conservar el estimado?" : "¿Conservar el borrador?", isPresented: $confirmingCancel,
                                    titleVisibility: .visible) {
                    Button(isEstimate ? "Conservar estimado" : "Conservar borrador", action: saveDraft)
                    Button(isEstimate ? "Descartar estimado" : "Descartar borrador", role: .destructive, action: discardDraft)
                    Button("Seguir editando", role: .cancel) {}
                } message: {
                    Text(isEstimate ? "Al ver la vista previa se guardó el estimado." : "Al ver la vista previa se guardó como borrador.")
                }
                .confirmationDialog("¿Descartar los cambios?", isPresented: $confirmingDiscardChanges, titleVisibility: .visible) {
                    Button("Descartar", role: .destructive) { close() }
                    Button("Seguir editando", role: .cancel) {}
                }
                .headerButton()
            }
            #if os(macOS)
            // Una hoja del Mac solo muestra «Cancelar» y la acción de confirmar: aquí «Emitir factura» (con Return);
            // «Vista previa» y «Guardar borrador» van en el contenido.
            ToolbarItem(placement: .confirmationAction) {
                if isWide {
                    Button(primaryTitle, action: primaryAction).disabled(!canIssue)
                } else {
                    Button("Guardar", action: saveDraft).disabled(isEditingIssued ? !canIssue : customerID == nil)
                        .accessibilityLabel(isEditingIssued ? "Guardar cambios" : isEstimate ? "Guardar estimado" : "Guardar borrador")
                }
            }
            #else
            // Canvas `FacturaNueva`: «✓» a la derecha. De vidrio sin relleno (decisión del usuario, 2-nov): en
            // `.confirmationAction` el sistema lo rellenaba con el color del texto (un círculo negro).
            if !isWide {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveDraft) {
                        Label(isEditingIssued ? "Guardar cambios" : isEstimate ? "Guardar estimado" : "Guardar borrador",
                              systemImage: "checkmark").labelStyle(.iconOnly)
                    }
                    .disabled(isEditingIssued ? !canIssue : customerID == nil)
                    .headerButton()
                }
            } else {
                // En la hoja ancha, «Guardar borrador» va en el contenido, como en el Mac: con cuatro botones en la
                // barra, «×» se iba al menú de desbordamiento.
                // `MacFacturaNueva`: «Vista previa» y la acción principal arriba, junto al título.
                if !isEditingIssued {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Vista previa", action: showPreview).disabled(!canIssue).headerButton()
                    }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(primaryTitle, action: primaryAction).disabled(!canIssue).headerButton()
                }
            }
            #endif
        }
        // Con cambios, o con el borrador que guardó la vista previa, la hoja no se cierra tocando fuera: «Cancelar»
        // pregunta qué hacer. Antes solo se bloqueaba con borrador, y lo escrito se perdía.
        .interactiveDismissDisabled(hasChanges)
        .onAppear {
            if let editing, !loadedDraft { load(editing) }
            if let editingEstimate, !loadedDraft { load(editingEstimate) }
            if !loadedDraft, baseline == nil { applyNewDocumentDefaults() }
            if customerID == nil { customerID = preselectedCustomer?.id }
            if lines.first?.incomeAccountID == nil { lines[0].incomeAccountID = incomeAccounts.first?.id }
            if baseline == nil { baseline = signature }
            if discount > 0 { showingDiscount = true }
        }
        // La barra lateral pregunta antes de cambiar de pantalla si hay cambios (y al descartar borra el borrador
        // que guardó la vista previa).
        .reportsUnsavedChanges(hasChanges, token: editorToken, onDiscard: deleteSavedDraft)
        #if DEBUG
        // `-qa.tasaNueva 1`: sin ninguna tasa, abre «Añadir tasa…» del menú de impuesto (en el Mac el menú no se captura).
        .task {
            if UserDefaults.standard.bool(forKey: "qa.tasaNueva"), hasNoTaxRates {
                try? await Task.sleep(for: .seconds(1))
                addingTaxRate = true
            }
        }
        // `-qa.impuestoIncluido 1`: activa «Precios con impuesto incluido» en la empresa (su interruptor está en Impuestos).
        .task {
            if UserDefaults.standard.bool(forKey: "qa.impuestoIncluido"), let company = companies.first, !company.pricesIncludeTax {
                company.pricesIncludeTax = true
            }
        }
        #endif
        // Con un aviso de «Cancelar» abierto o cerrándose, su acción aún puede retirar el editor
        // (ver `UnsavedChanges.confirmation`).
        .onChange(of: confirmingCancel || confirmingDiscardChanges) { _, open in unsavedChanges?.confirmation(isOpen: open) }
        .onChange(of: customerID) {
            if skipCustomerDefaults { skipCustomerDefaults = false; return }
            guard let customer else { return }
            // Impuesto del cliente o el de la empresa (ninguno si está exento) y vencimiento según sus condiciones.
            let defaults = try? books.newInvoiceDefaults(for: customer, issueDate: issueDate)
            taxGroupID = defaults?.taxGroupID ?? customer.defaultTaxGroupID
            if !isEstimate {
                customDue = false
                dueDate = defaults?.dueDate ?? Calendar.current.date(byAdding: .day, value: customer.paymentTermsDays, to: issueDate) ?? issueDate
            }
        }
        // Con unos términos (Neto 15…), el vencimiento se mueve con la fecha; con «Otra fecha», nunca queda antes.
        .onChange(of: issueDate) { old, new in
            let days = Self.days(from: old, to: dueDate)
            if !customDue, Self.standardTerms.contains(days) {
                dueDate = Calendar.current.date(byAdding: .day, value: days, to: new) ?? new
            } else if dueDate < new {
                dueDate = new
            }
        }
        .sheet(isPresented: $showingNewCustomer) {
            NavigationStack { CustomerEditorView { customerID = $0.id } }.editorSheetSizing()
        }
        // Tras «Emitir factura», «Factura F-1001 emitida · Enviar a…»; al terminar se cierra el editor.
        .offerToSendIssued($justIssued) { dismiss() }
        .closedPeriodUnlock($closedPeriodRetry) { errorMessage = $0 }
    }

    // MARK: Términos

    /// Términos del canvas (`FacturaNueva`, `MacFacturaNueva`); `otherTerms` es «Otra fecha».
    private static let standardTerms = [0, 15, 30, 60]
    private static let otherTerms = -1

    private static func days(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    private static func termsTitle(_ days: Int) -> String {
        switch days {
        case otherTerms: String(localized: "Otra fecha")
        case 0: String(localized: "Al recibir")
        default: String(localized: "Neto \(days)")
        }
    }

    private var termsSelection: Binding<Int> {
        Binding {
            let days = Self.days(from: issueDate, to: dueDate)
            return customDue || !Self.standardTerms.contains(days) ? Self.otherTerms : days
        } set: { days in
            if days == Self.otherTerms {
                customDue = true
            } else {
                customDue = false
                dueDate = Calendar.current.date(byAdding: .day, value: days, to: issueDate) ?? issueDate
            }
        }
    }

    private var termsPicker: some View {
        Picker("Términos", selection: termsSelection) {
            ForEach(Self.standardTerms + [Self.otherTerms], id: \.self) { Text(Self.termsTitle($0)).tag($0) }
        }
    }

    private var dueDatePicker: some View {
        DatePicker("Vence", selection: $dueDate, in: issueDate..., displayedComponents: .date)
    }

    /// Validez del estimado (canvas `Estimado`: «válido hasta 30 nov»).
    private var validUntilPicker: some View {
        DatePicker("Válido hasta", selection: $dueDate, in: issueDate..., displayedComponents: .date)
    }

    private var documentNumber: String {
        if isEstimate {
            return savedEstimate?.number ?? (try? books.peekDocumentNumber(.estimate)) ?? "—"
        }
        return savedInvoice.map { $0.number.isEmpty ? String(localized: "Al emitir") : $0.number }
            ?? (try? books.peekDocumentNumber(.invoice)) ?? "—"
    }

    /// Tasas que no van en ningún grupo: también se pueden elegir solas (p. ej. la que se crea desde aquí).
    private var looseTaxRates: [TaxRate] {
        let grouped = Set(taxGroups.filter { !$0.isArchived }.flatMap { ($0.rates ?? []).map(\.id) })
        return taxRates.filter { !$0.isArchived && !grouped.contains($0.id) }
    }

    /// La empresa no tiene ninguna tasa: el menú ofrece «Añadir tasa…».
    private var hasNoTaxRates: Bool { taxGroups.allSatisfy(\.isArchived) && taxRates.allSatisfy(\.isArchived) }

    /// Etiqueta de «Añadir tasa…» en el menú (no es una tasa: al elegirla se abre el editor y el menú no cambia).
    private static let addTaxRateTag = UUID(uuidString: "00000000-0000-0000-0000-00000000A0DD")!

    private var taxSelection: Binding<UUID?> {
        Binding(get: { taxGroupID }, set: { id in
            if id == Self.addTaxRateTag { addingTaxRate = true } else { taxGroupID = id }
        })
    }

    private var taxPicker: some View {
        // «Impuesto» y no «Impuesto sobre ventas»: así etiqueta y grupo caben en una línea, como en el canvas.
        Picker("Impuesto", selection: taxSelection) {
            Text("Sin impuesto").tag(UUID?.none)
            ForEach(taxGroups.filter { !$0.isArchived }) { group in
                Text("\(group.name) · \(group.percent.formatted())%").tag(Optional(group.id))
            }
            ForEach(looseTaxRates) { rate in
                Text("\(rate.name) · \(rate.percent.formatted())%").tag(Optional(rate.id))
            }
            if hasNoTaxRates {
                Divider()
                Text("Añadir tasa…").tag(Optional(Self.addTaxRateTag))
            }
        }
        .accessibilityLabel("Impuesto sobre ventas")
        .sheet(isPresented: $addingTaxRate) {
            NavigationStack { TaxRateEditorView { taxGroupID = $0.id } }.editorSheetSizing()
        }
    }

    /// La factura sale sin sales tax (sin tasa elegida, cliente exento o ninguna línea gravable): se dice bajo los totales.
    private var carriesNoTax: Bool {
        taxGroupID == nil || (customer?.isTaxExempt ?? false) || (!validLines.isEmpty && (preview?.totalTax ?? 0) == 0)
    }

    private var noTaxNote: String {
        if customer?.isTaxExempt ?? false { return String(localized: "El cliente está exento: esta factura no lleva impuesto.") }
        if taxGroupID == nil && hasNoTaxRates {
            return String(localized: "Esta factura no lleva impuesto. Si cobras sales tax, elige «Añadir tasa…» en Impuesto.")
        }
        return String(localized: "Esta factura no lleva impuesto.")
    }

    private func incomeAccountName(_ id: UUID?) -> String {
        incomeAccounts.first { $0.id == id }?.displayName ?? String(localized: "Elegir…")
    }

    // MARK: iPhone (`FacturaNueva`)

    private var compactForm: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            if isEditingIssued { Section { issuedNotice } }

            // Tarjeta del cliente con monograma y correo; al tocarla se elige otro o se crea uno.
            Section {
                Menu { customerMenuContent } label: {
                    HStack(spacing: 12) {
                        InitialsTile(text: customer?.initials ?? "+")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(customer?.name ?? String(localized: "Elegir cliente…"))
                                .font(.body).foregroundStyle(customer == nil ? Palette.brand : Palette.ink)
                            if let email = customer?.email, !email.isEmpty {
                                Text(email).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cliente")
                .accessibilityValue(customer?.name ?? String(localized: "Sin elegir"))
                if let customer, customer.isTaxExempt {
                    Label("Cliente exento de sales tax", systemImage: "checkmark.seal").foregroundStyle(Palette.positive)
                }
            }

            // Número · Fecha · Términos como filas del formulario; el vencimiento, en el pie.
            Section {
                LabeledContent("Número", value: documentNumber)
                if isEstimate {
                    TextField("Concepto", text: $estimateTitle, prompt: Text("Concepto (opcional)"))
                }
                DatePicker("Fecha", selection: $issueDate, displayedComponents: .date)
                if isEstimate {
                    validUntilPicker
                } else {
                    termsPicker
                    if termsSelection.wrappedValue == Self.otherTerms { dueDatePicker }
                }
            } footer: {
                if isEstimate { Text("Válido hasta el \(dueDate.shortDate).") } else { Text("Vence el \(dueDate.shortDate).") }
            }

            Section(title: "Productos y servicios") {
                ForEach($lines) { $line in
                    lineRow($line)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button { addLine() } label: {
                    Label {
                        Text("Añadir producto o servicio").foregroundStyle(Palette.brand)
                    } icon: {
                        Image(systemName: "plus.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Palette.green)
                    }
                }
            }

            Section {
                LabeledContent("Subtotal", value: linesSubtotal.money)
                taxPicker
                LabeledContent(taxRowTitle, value: (preview?.totalTax ?? 0).money)
                if showingDiscount || discount > 0 {
                    LabeledContent("Descuento") {
                        MoneyField(title: String(localized: "Descuento"), minorUnits: $discount)
                            .multilineTextAlignment(.trailing)
                    }
                    if discount > linesSubtotal {
                        Text("El descuento no puede ser mayor que el subtotal.").font(.footnote).foregroundStyle(Palette.negative)
                    }
                } else {
                    Button("Añadir descuento") { showingDiscount = true }.foregroundStyle(Palette.brand)
                }
                LabeledContent {
                    Text((preview?.total ?? 0).money).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink)
                } label: {
                    Text("Total").fontWeight(.semibold)
                }
            } footer: {
                if carriesNoTax {
                    Text(noTaxNote)
                } else if includesTax {
                    Text("Los precios ya incluyen el sales tax: el total es el subtotal menos el descuento.")
                }
            }

            Section {
                NavigationLink { InvoiceNotesEditor(message: $customerMessage) } label: {
                    HStack(spacing: 12) {
                        Text("Notas y términos").layoutPriority(1)
                        Spacer(minLength: 8)
                        Text(messageSummary).foregroundStyle(Palette.ink2).lineLimit(1)
                    }
                }
            } footer: {
                Text(ledgerNote)
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        // El teclado lleva «Listo» y se cierra al desplazar.
        .keyboardDoneButton()
        #if os(iOS)
        // Con el teclado a la vista la barra de abajo tapaba la línea que se edita (el precio, con el teclado numérico,
        // que no tiene tecla para cerrarse): se oculta mientras se escribe.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        #endif
        .modifier(HiddenWhile(hidden: keyboardShown) { bottomBar })
    }

    /// Canvas `FacturaNueva`: barra de vidrio con el total, «Vista previa» y la acción principal.
    @ViewBuilder
    private var bottomBar: some View {
        BottomActionBar {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total").font(.footnote).foregroundStyle(Palette.ink2)
                Text((preview?.total ?? 0).money).font(.headline).monospacedDigit().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .accessibilityElement(children: .combine)
            if dynamicTypeSize.isAccessibilitySize {
                if !isEditingIssued {
                    Button("Vista previa", action: showPreview).buttonStyle(.secondary).disabled(!canIssue)
                }
                Button(primaryTitle, action: primaryAction).buttonStyle(.primary).disabled(!canIssue)
            } else {
                // La vista previa sale del PDF guardado: al corregir una emitida mostraría la versión de antes.
                if !isEditingIssued {
                    Button("Vista previa", action: showPreview).buttonStyle(FillCapsuleButtonStyle(fullWidth: false)).disabled(!canIssue)
                }
                Button(action: primaryAction) { Text(isEstimate || isEditingIssued ? "Guardar" : "Emitir") }
                    .buttonStyle(.primaryCompact)
                    .accessibilityLabel(primaryTitle)
                    .disabled(!canIssue)
            }
        }
    }

    /// Primera línea del mensaje, o «Ninguno».
    private var messageSummary: String {
        let first = customerMessage.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Ninguno") : first
    }

    @ViewBuilder
    private var customerMenuContent: some View {
        Picker("Cliente", selection: $customerID) {
            Text("Elegir cliente…").tag(UUID?.none)
            ForEach(customers.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
        }
        Button("Nuevo cliente", systemImage: "person.badge.plus") { showingNewCustomer = true }
    }

    private func addLine() {
        lines.append(LineDraft(incomeAccountID: incomeAccounts.first?.id))
    }

    /// Desde aquí cabe la tabla de artículos de `MacFacturaNueva` (la hoja del iPad mide 760 pt en vertical).
    static let wideMinimumWidth: CGFloat = 640

    /// `MacFacturaNueva` en iPad y Mac (hasta AX3); el formulario del iPhone en pantallas, columnas u hojas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        // El iPhone sigue con la clase de tamaño (en horizontal, solo los Max son regulares).
        if UIDevice.current.userInterfaceIdiom == .pad, let width {
            if width < Self.wideMinimumWidth { return false }
        } else if sizeClass != .regular {
            return false
        }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    /// Línea del formulario estrecho, en el orden que pidió el usuario (7-nov): descripción con precio y «Gravable»;
    /// debajo, cantidad y cuenta de ingreso; y al final el total de la línea (antes iba arriba, junto a la descripción,
    /// y se confundía con el precio).
    private func lineRow(_ line: Binding<LineDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    TextField("Descripción", text: line.details, axis: .vertical)
                        .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
                    priceAndTax(line)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Descripción", text: line.details, axis: .vertical)
                    priceAndTax(line)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    QuantityStepper(quantity: line.quantity)
                    Spacer(minLength: 4)
                    incomeAccountMenu(line.incomeAccountID).font(.footnote)
                }
                VStack(alignment: .leading, spacing: 6) {
                    QuantityStepper(quantity: line.quantity)
                    incomeAccountMenu(line.incomeAccountID).font(.footnote)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total de la línea").font(.footnote).foregroundStyle(Palette.ink2)
                Spacer()
                Text(line.wrappedValue.amount.money).monospacedDigit().fontWeight(.semibold).foregroundStyle(Palette.ink)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }

    private func priceAndTax(_ line: Binding<LineDraft>) -> some View {
        HStack(spacing: 6) {
            // El precio en su caja, con «Precio» de guía mientras está vacío: con solo «$0.00» en gris no se distinguía
            // del importe de la línea (a la derecha) ni se veía que se podía escribir (recorrido «cliente nuevo», 5-nov).
            // Con una etiqueta delante ya no cabía la cantidad en la misma fila. Área de toque de 44 pt.
            MoneyField(title: String(localized: "Precio"), minorUnits: line.unitPrice, prompt: String(localized: "Precio"))
                .foregroundStyle(Palette.ink)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minWidth: 64, minHeight: 30)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minHeight: Metrics.target)
                .contentShape(Rectangle())
            Text(verbatim: "·").foregroundStyle(Palette.ink2).accessibilityHidden(true)
            Button(line.wrappedValue.isTaxable ? String(localized: "Gravable") : String(localized: "Sin impuesto")) {
                line.wrappedValue.isTaxable.toggle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.brand)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Gravable")
            .accessibilityValue(line.wrappedValue.isTaxable ? Text("Sí") : Text("No"))
            TermHelp(.taxable)
        }
        .font(.footnote)
    }

    /// Cuenta de ingreso de una línea: menú con la cuenta elegida; VoiceOver lee nombre y cuenta en un elemento.
    private func incomeAccountMenu(_ selection: Binding<UUID?>) -> some View {
        let name = incomeAccountName(selection.wrappedValue)
        return Menu {
            Picker("Cuenta de ingreso", selection: selection) {
                ForEach(incomeAccounts) { Text($0.displayName).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                // Con tamaños de accesibilidad, en varias líneas: en una se cortaba («Ingresos por…»).
                Text(name).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).accessibilityHidden(true)
            }
            .foregroundStyle(Palette.ink2)
            .frame(minHeight: Metrics.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cuenta de ingreso")
        .accessibilityValue(name)
    }

    // MARK: iPad y Mac (`MacFacturaNueva`)

    private var wideForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                if isEditingIssued {
                    issuedNotice
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        customerBox.frame(minWidth: 320, maxWidth: .infinity)
                        termsBox.frame(minWidth: 260, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 16) { customerBox; termsBox }
                }
                linesBox
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        messageBox.frame(minWidth: 320, maxWidth: .infinity)
                        totalsBox.frame(width: 300)
                    }
                    VStack(alignment: .leading, spacing: 16) { messageBox; totalsBox }
                }
                Text(ledgerNote)
                    .font(.footnote).foregroundStyle(Palette.ink2)
                if !isEditingIssued {
                    HStack(spacing: 10) {
                        #if os(macOS)
                        Button("Vista previa", action: showPreview).disabled(!canIssue)
                        #endif
                        if !isEstimate {
                            Button("Guardar borrador", action: saveDraft).disabled(customerID == nil)
                        }
                    }
                    .buttonStyle(.secondary).fixedSize()
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .keyboardDoneButton()
        .background(Palette.background)
    }

    #if os(macOS)
    private static let boxRowHeight: CGFloat = 34
    #else
    private static let boxRowHeight: CGFloat = 48
    #endif

    /// Caja con su título fuera (canvas: «Cliente», «Condiciones», «Totales» en 13 bold).
    private func box<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        box(title, trailing: { EmptyView() }, content: content)
    }

    private func box<Trailing: View, Content: View>(_ title: String, @ViewBuilder trailing: () -> Trailing,
                                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing().font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 2)
            VStack(spacing: 0) { content() }.card(padding: 0)
        }
    }

    /// Fila «etiqueta · control» de una caja, con la línea de separación sangrada.
    private func boxRow<Content: View>(_ title: String, first: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            if !first { Divider().padding(.leading, 12) }
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Palette.ink).fixedSize()
                Spacer(minLength: 8)
                content()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Self.boxRowHeight)
        }
    }

    private var customerBox: some View {
        box(String(localized: "Cliente")) {
            boxRow(String(localized: "Cliente"), first: true) {
                Menu { customerMenuContent } label: {
                    HStack(spacing: 6) {
                        if let customer {
                            Text(customer.name).fontWeight(.semibold).foregroundStyle(Palette.ink).layoutPriority(1)
                            if !customer.email.isEmpty { Text(customer.email).foregroundStyle(Palette.ink2) }
                        } else {
                            Text("Elegir cliente…").foregroundStyle(Palette.brand)
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Palette.ink2)
                            .accessibilityHidden(true)
                    }
                    .lineLimit(1)
                    .frame(minHeight: Metrics.target)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cliente")
                .accessibilityValue(customer?.name ?? String(localized: "Sin elegir"))
            }
            boxRow(String(localized: "Número")) {
                Text(documentNumber).foregroundStyle(Palette.ink2).monospacedDigit()
            }
            if isEstimate {
                boxRow(String(localized: "Concepto")) {
                    TextField("Concepto", text: $estimateTitle, prompt: Text("Opcional"))
                        .labelsHidden().multilineTextAlignment(.trailing).fieldBox().frame(maxWidth: 260)
                }
            }
            if let customer, customer.isTaxExempt {
                boxRow(String(localized: "Sales tax")) {
                    Label("Cliente exento de sales tax", systemImage: "checkmark.seal").foregroundStyle(Palette.positive)
                }
            }
        }
    }

    private var termsBox: some View {
        box(String(localized: "Condiciones")) {
            boxRow(String(localized: "Fecha"), first: true) {
                DatePicker("Fecha", selection: $issueDate, displayedComponents: .date).labelsHidden()
            }
            if isEstimate {
                boxRow(String(localized: "Válido hasta")) {
                    validUntilPicker.labelsHidden()
                }
            } else {
                boxRow(String(localized: "Condiciones")) {
                    termsPicker.labelsHidden().fixedSize()
                }
                boxRow(String(localized: "Vence")) {
                    if termsSelection.wrappedValue == Self.otherTerms {
                        dueDatePicker.labelsHidden()
                    } else {
                        Text(dueDate.shortDate).foregroundStyle(Palette.ink2)
                    }
                }
            }
        }
    }

    /// Tabla de artículos: # · Producto o servicio (con la cuenta de ingreso debajo) · Cant. · Precio · Impuesto · Importe.
    private var linesBox: some View {
        box(String(localized: "Artículos")) {
            Text("\(lines.count) líneas")
        } content: {
            TableCard {
                Text(verbatim: "#").frame(width: 20, alignment: .trailing)
                Text("Producto o servicio").frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                Text("Cant.").frame(width: Self.quantityColumn, alignment: .trailing)
                Text("Precio").frame(width: amountColumn, alignment: .trailing)
                HStack(spacing: 0) {
                    Text("Impuesto")
                    TermHelp(.taxable).font(.footnote)
                }
                .frame(width: Self.taxColumn, alignment: .leading)
                Text("Importe").frame(width: amountColumn, alignment: .trailing)
                Color.clear.frame(width: 24, height: 1)
            } rows: {
                ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                    // Como `TableRow`, pero sin combinar los controles: cada campo se edita por separado con VoiceOver.
                    LineEditRow {
                        Text("\(index + 1)").foregroundStyle(Palette.ink2).frame(width: 20, alignment: .trailing).accessibilityHidden(true)
                        // La cuenta de ingreso, debajo del producto: como columna aparte la tabla no cabía en la hoja
                        // del iPad (760 pt) y se cortaba por los lados.
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Producto o servicio", text: $line.details).fieldBox()
                            incomeAccountMenu($line.incomeAccountID).font(.footnote)
                        }
                        .frame(minWidth: 140, maxWidth: .infinity)
                        QuantityStepper(quantity: $line.quantity, valueInside: true).frame(width: Self.quantityColumn, alignment: .trailing)
                        MoneyField(title: String(localized: "Precio"), minorUnits: $line.unitPrice)
                            .multilineTextAlignment(.trailing).fieldBox().frame(width: amountColumn)
                        Picker("Impuesto", selection: $line.isTaxable) {
                            Text("Gravable").tag(true)
                            Text("Exento").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .frame(width: Self.taxColumn, alignment: .leading)
                        .accessibilityLabel("Impuesto, línea \(index + 1)")
                        Text(line.amount.money).fontWeight(.semibold).frame(width: amountColumn, alignment: .trailing)
                        Button { lines.remove(at: index) } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 24, height: Metrics.target)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.ink2)
                        .disabled(lines.count <= 1)
                        .accessibilityLabel("Quitar la línea \(index + 1)")
                    }
                    .zebra(index)
                }
                Divider()
                Button("Añadir línea", systemImage: "plus", action: addLine)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .frame(maxWidth: .infinity, minHeight: Metrics.target, alignment: .leading)
                    .padding(.horizontal, TableCard<EmptyView, EmptyView>.inset)
            }
        }
    }

    #if os(macOS)
    private static let quantityColumn: CGFloat = 76
    private static let taxColumn: CGFloat = 96
    #else
    private static let quantityColumn: CGFloat = 104
    private static let taxColumn: CGFloat = 116
    #endif

    private var messageBox: some View {
        box(String(localized: "Mensaje y términos")) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mensaje para el cliente").foregroundStyle(Palette.ink)
                TextField("Notas y términos", text: $customerMessage, axis: .vertical)
                    .lineLimit(3...)
                    .fieldBox()
            }
            .padding(12)
        }
    }

    private var totalsBox: some View {
        box(String(localized: "Totales")) {
            boxRow(String(localized: "Subtotal"), first: true) {
                Text(linesSubtotal.money).monospacedDigit()
            }
            boxRow(String(localized: "Impuesto")) {
                taxPicker.labelsHidden().fixedSize()
            }
            boxRow(String(localized: "Descuento")) {
                MoneyField(title: String(localized: "Descuento"), minorUnits: $discount)
                    .multilineTextAlignment(.trailing).fieldBox().frame(maxWidth: 120)
            }
            if discount > linesSubtotal {
                Text("El descuento no puede ser mayor que el subtotal.").font(.footnote).foregroundStyle(Palette.negative)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            boxRow(taxRowTitle) {
                Text((preview?.totalTax ?? 0).money).monospacedDigit()
            }
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Total").font(.headline)
                    Spacer(minLength: 8)
                    Text((preview?.total ?? 0).money).font(.amount(24)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if carriesNoTax {
                    Text(noTaxNote).font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
        }
    }

    private func load(_ invoice: Invoice) {
        loadedDraft = true
        savedInvoice = invoice
        skipCustomerDefaults = invoice.customer != nil
        customerID = invoice.customer?.id
        issueDate = invoice.issueDate
        dueDate = invoice.dueDate
        taxGroupID = invoice.taxGroupID
        discount = invoice.discount
        customerMessage = invoice.customerMessage
        pricesIncludeTax = invoice.pricesIncludeTax
        lines = invoice.sortedLines.map {
            LineDraft(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice,
                      isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
        }
        if lines.isEmpty { lines = [LineDraft(incomeAccountID: incomeAccounts.first?.id)] }
    }

    private func load(_ estimate: Estimate) {
        loadedDraft = true
        savedEstimate = estimate
        skipCustomerDefaults = estimate.customer != nil
        customerID = estimate.customer?.id
        estimateTitle = estimate.title
        issueDate = estimate.issueDate
        dueDate = estimate.expirationDate
        customDue = true
        taxGroupID = estimate.taxGroupID
        discount = estimate.discount
        customerMessage = estimate.customerMessage
        pricesIncludeTax = estimate.pricesIncludeTax
        lines = estimate.sortedLines.map {
            LineDraft(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice,
                      isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
        }
        if lines.isEmpty { lines = [LineDraft(incomeAccountID: incomeAccounts.first?.id)] }
    }

    /// Factura o estimado nuevo: impuesto predeterminado de la empresa (o el del cliente), vencimiento según los términos
    /// predeterminados y el mensaje por defecto de la plantilla.
    private func applyNewDocumentDefaults() {
        guard editing == nil, editingEstimate == nil,
              let defaults = try? books.newInvoiceDefaults(for: preselectedCustomer, issueDate: issueDate) else { return }
        if customerMessage.isEmpty { customerMessage = defaults.customerMessage }
        taxGroupID = defaults.taxGroupID
        if !isEstimate { dueDate = defaults.dueDate }
    }

    private var input: InvoiceDraftInput {
        InvoiceDraftInput(
            customer: customer, issueDate: issueDate, dueDate: dueDate, taxGroupID: taxGroupID,
            discount: discount, customerMessage: customerMessage,
            lines: validLines.map {
                .init(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice,
                      isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
            },
            pricesIncludeTax: pricesIncludeTax
        )
    }

    private var estimateInput: EstimateInput {
        EstimateInput(customer: customer, title: estimateTitle.trimmingCharacters(in: .whitespaces), issueDate: issueDate,
                      expirationDate: dueDate, taxGroupID: taxGroupID, discount: discount, customerMessage: customerMessage,
                      lines: input.lines, pricesIncludeTax: pricesIncludeTax)
    }

    /// Guarda (o reescribe) el estimado con lo que hay ahora en pantalla.
    @discardableResult
    private func persistEstimate() throws -> Estimate {
        let estimate = try books.saveEstimate(estimateInput, into: savedEstimate)
        savedEstimate = estimate
        return estimate
    }

    /// «Emitir factura» o «Guardar estimado».
    private func primaryAction() {
        if isEditingIssued { saveIssuedChanges() } else if isEstimate { saveDraft() } else { issue() }
    }

    /// Guarda (o reescribe) el borrador con lo que hay ahora en pantalla.
    @discardableResult
    private func persistDraft() throws -> Invoice {
        let invoice = try books.saveDraft(input, into: savedInvoice)
        savedInvoice = invoice
        return invoice
    }

    /// Borrador (o estimado) creado en esta pantalla por la vista previa al hacer uno nuevo.
    private var hasNewDraft: Bool {
        isEstimate ? editingEstimate == nil && savedEstimate != nil : editing == nil && savedInvoice != nil
    }

    private func deleteSavedDraft() {
        if isEstimate {
            guard editingEstimate == nil, let savedEstimate else { return }
            context.delete(savedEstimate)
        } else {
            guard editing == nil, let savedInvoice else { return }
            context.delete(savedInvoice)
        }
        try? context.save()
    }

    /// Retira el registro de cambios y cierra.
    private func close() {
        unsavedChanges?.remove(editorToken)
        dismiss()
    }

    private func cancel() {
        if hasNewDraft { confirmingCancel = true } else if hasChanges { confirmingDiscardChanges = true } else { close() }
    }

    private func discardDraft() {
        deleteSavedDraft()
        close()
    }

    private func saveDraft() {
        if isEditingIssued { saveIssuedChanges(); return }
        do {
            if isEstimate { try persistEstimate() } else { try persistDraft() }
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// La vista previa sale del PDF real, así que primero se guarda el borrador (o el estimado).
    private func showPreview() {
        guard !isEditingIssued else { return }
        do {
            if isEstimate { previewingEstimate = try persistEstimate() } else { previewing = try persistDraft() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func issue() {
        do {
            // Si un intento anterior falló, el borrador se reescribe con las correcciones antes de emitir.
            let invoice = try persistDraft()
            try books.issue(invoice)
            errorMessage = nil
            // Ya no hay nada sin guardar; el editor se cierra al responder «Factura … emitida».
            unsavedChanges?.remove(editorToken)
            justIssued = invoice
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Corrige la factura emitida (`Bookkeeper.updateIssuedInvoice`); en un periodo cerrado pide desbloquear.
    private func saveIssuedChanges() {
        guard let invoice = editing else { return }
        let input = self.input
        do {
            try books.updateIssuedInvoice(invoice, with: input)
            close()
        } catch {
            if let lockDate = PeriodClosing.lockDate(of: error) {
                closedPeriodRetry = ClosedPeriodRetry(lockDate: lockDate) { unlocked in
                    try unlocked.updateIssuedInvoice(invoice, with: input)
                    close()
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { InvoiceEditorView() }.modelContainer(SampleData.makeContainer())
}

/// Fija `content` como barra de vidrio inferior (`safeAreaBar`) salvo mientras `hidden`.
private struct HiddenWhile<Bar: View>: ViewModifier {
    let hidden: Bool
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        content.safeAreaBar(edge: .bottom, spacing: 0) {
            if !hidden { bar }
        }
    }
}

/// Fila editable de la tabla de artículos: las medidas de `TableRow` (línea arriba, 44 pt; 28 en el Mac) sin combinar
/// sus controles en un solo elemento de accesibilidad.
private struct LineEditRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: TableCard<EmptyView, EmptyView>.columnSpacing) { content }
                #if os(macOS)
                .font(.body)
                #else
                .font(.subheadline)
                #endif
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, TableCard<EmptyView, EmptyView>.inset)
                .padding(.vertical, 4)
                .frame(minHeight: Metrics.target)
        }
    }
}

/// «Notas y términos» de la factura (canvas `FacturaNueva`): el mensaje que va al pie del PDF.
private struct InvoiceNotesEditor: View {
    @Binding var message: String

    var body: some View {
        Form {
            Section {
                TextField("Mensaje para el cliente", text: $message, axis: .vertical)
                    .lineLimit(5...)
            } footer: {
                Text("Aparece al pie de la factura, debajo de los totales.")
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Notas y términos")
        .inlineTitle()
    }
}

/// Cantidad (canvas `FacturaNueva`): «N ×» y una cápsula «− | +» con áreas de 44 pt; para VoiceOver es un `Stepper`.
/// En el Mac, un campo numérico con su `Stepper`, como en `MacFacturaNueva`.
struct QuantityStepper: View {
    @Binding var quantity: Decimal
    /// La cantidad entre «−» y «+» (tabla del iPad), en lugar de «N ×» delante.
    var valueInside = false
    /// La cápsula crece con el texto: con AX los símbolos se salían de sus 32 pt.
    @ScaledMetric(relativeTo: .body) private var pillHeight: CGFloat = 32
    private var buttonWidth: CGFloat { (valueInside ? 36 : 46) * pillHeight / 32 }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 4) {
            TextField("Cantidad", value: $quantity, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 36)
            Stepper("Cantidad", value: $quantity, in: 1...9_999).labelsHidden()
        }
        #else
        HStack(spacing: 8) {
            if !valueInside {
                Text("\(quantity.formatted()) ×").font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
                    .fixedSize()
            }
            HStack(spacing: 0) {
                Button { quantity = max(1, quantity - 1) } label: {
                    Image(systemName: "minus").frame(width: buttonWidth, height: max(Metrics.target, pillHeight)).contentShape(Rectangle())
                }
                .disabled(quantity <= 1)
                if valueInside {
                    Text(quantity.formatted()).font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 24)
                } else {
                    Rectangle().fill(Palette.separator).frame(width: 0.5, height: 18)
                }
                Button { quantity += 1 } label: {
                    Image(systemName: "plus").frame(width: buttonWidth, height: max(Metrics.target, pillHeight)).contentShape(Rectangle())
                }
            }
            .font(.body.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink)
            .background(Capsule().fill(Palette.surface2).frame(height: pillHeight))
        }
        .accessibilityRepresentation {
            Stepper("Cantidad", value: $quantity, in: 1...9_999)
                .accessibilityValue(quantity.formatted())
        }
        #endif
    }
}

/// Título en línea en pantallas estrechas; grande en las anchas (`MacFacturaNueva`).
struct InlineTitleUnless: ViewModifier {
    let wide: Bool
    func body(content: Content) -> some View {
        if wide { content.headerTitle() } else { content.inlineTitle() }
    }
}
