import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Nueva factura o edición de un borrador (canvas: `FacturaNueva`). Trabaja con estado local y solo
/// escribe en el modelo al guardar, así cancelar no deja nada a medias.
struct InvoiceEditorView: View {
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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @ScaledMetric(relativeTo: .subheadline) private var amountColumn: CGFloat = 110
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \TaxGroup.name) private var taxGroups: [TaxGroup]
    @Query private var companies: [Company]

    @State private var customerID: UUID?
    @State private var issueDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var taxGroupID: UUID?
    @State private var lines: [LineDraft] = [LineDraft()]
    @State private var discount: Int64 = 0
    @State private var customerMessage = ""
    @State private var errorMessage: String?
    @State private var savedInvoice: Invoice?
    @State private var showingNewCustomer = false
    @State private var previewing: Invoice?
    @State private var confirmingCancel = false
    @State private var loadedDraft = false
    /// Al cargar un borrador no se aplican los valores por defecto del cliente (impuesto, vencimiento).
    @State private var skipCustomerDefaults = false

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var customer: Customer? { customers.first { $0.id == customerID } }
    private var incomeAccounts: [Account] { accounts.filtered { $0.accountType == .income } }
    private var validLines: [LineDraft] { lines.filter { $0.amount > 0 } }

    private var preview: InvoicePosting? {
        let defaultIncome = incomeAccounts.first?.id ?? UUID()
        let components = (try? books.taxComponents(groupID: taxGroupID, on: issueDate)) ?? []
        return try? PostingRules.invoice(
            date: issueDate, memo: "", receivableAccountID: UUID(),
            lines: validLines.map { SalesLine(incomeAccountID: $0.incomeAccountID ?? defaultIncome, amount: $0.amount, isTaxable: $0.isTaxable) },
            taxComponents: components, customerIsTaxExempt: customer?.isTaxExempt ?? false,
            discount: discount, discountAccountID: discount > 0 ? UUID() : nil
        )
    }

    var body: some View {
        Group {
            if isWide { wideForm } else { compactForm }
        }
        .sheet(item: $previewing) { invoice in
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }
        }
        .navigationTitle(editing == nil ? "Nueva factura" : "Editar borrador")
        .modifier(InlineTitleUnless(wide: isWide))
        // En pantalla ancha se abre en la navegación: «Cancelar» hace de «Atrás» (y pregunta por el borrador).
        .navigationBarBackButtonHidden(isWide)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: cancel) }
            // «Guardar» y no «Guardar borrador»: con el texto largo el título se cortaba en «Nueva f…».
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: saveDraft)
                    .disabled(customerID == nil)
                    .accessibilityLabel("Guardar borrador")
            }
            if isWide {
                // `MacFacturaNueva`: «Vista previa» y la acción principal arriba, junto al título.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Vista previa", action: showPreview).disabled(customerID == nil || validLines.isEmpty)
                    Button("Emitir factura", action: issue)
                        .buttonStyle(.borderedProminent).tint(Palette.brand)
                        .disabled(customerID == nil || validLines.isEmpty)
                }
            }
        }
        // La vista previa guarda la factura como borrador: al cancelar se pregunta qué hacer con él.
        .interactiveDismissDisabled(hasNewDraft)
        .confirmationDialog("¿Conservar el borrador?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Conservar borrador", action: saveDraft)
            Button("Descartar borrador", role: .destructive, action: discardDraft)
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Al ver la vista previa se guardó como borrador.")
        }
        .onAppear {
            if let editing, !loadedDraft { load(editing) }
            if customerID == nil { customerID = preselectedCustomer?.id }
            if lines.first?.incomeAccountID == nil { lines[0].incomeAccountID = incomeAccounts.first?.id }
        }
        .onChange(of: customerID) {
            if skipCustomerDefaults { skipCustomerDefaults = false; return }
            guard let customer else { return }
            taxGroupID = customer.defaultTaxGroupID
            dueDate = Calendar.current.date(byAdding: .day, value: customer.paymentTermsDays, to: issueDate) ?? issueDate
        }
        .sheet(isPresented: $showingNewCustomer) {
            NavigationStack { CustomerEditorView { customerID = $0.id } }
        }
    }

    private var compactForm: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            // Canvas `FacturaNueva`: tarjeta del cliente con iniciales y correo; al tocarla se elige otro.
            Section {
                Menu {
                    Picker("Cliente", selection: $customerID) {
                        Text("Elegir cliente…").tag(UUID?.none)
                        ForEach(customers.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Nuevo cliente", systemImage: "person.badge.plus") { showingNewCustomer = true }
                } label: {
                    HStack(spacing: 12) {
                        InitialsTile(text: customer?.initials ?? "+")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cliente").font(.footnote).foregroundStyle(Palette.ink3)
                            Text(customer?.name ?? String(localized: "Elegir cliente…"))
                                .font(.body.weight(.semibold)).foregroundStyle(customer == nil ? Palette.brand : Palette.ink)
                            if let email = customer?.email, !email.isEmpty {
                                Text(email).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Palette.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cliente")
                .accessibilityValue(customer?.name ?? String(localized: "Sin elegir"))
                if let customer, customer.isTaxExempt {
                    Label("Cliente exento de sales tax", systemImage: "checkmark.seal").foregroundStyle(Palette.positive)
                }
            }

            // Número · Fecha · Vence en una franja; si no caben, una debajo de otra.
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) { numberCell; Divider(); dateCell; Divider(); dueCell }
                    VStack(alignment: .leading, spacing: 10) { numberCell; dateCell; dueCell }
                }
            }

            Section(title: "Productos y servicios") {
                ForEach($lines) { $line in
                    lineRow($line)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir producto o servicio", systemImage: "plus") {
                    lines.append(LineDraft(incomeAccountID: incomeAccounts.first?.id))
                }
                .fontWeight(.semibold)
            }

            Section {
                // «Impuesto» y no «Impuesto sobre ventas»: así etiqueta y grupo caben en una línea, como en el canvas.
                Picker("Impuesto", selection: $taxGroupID) {
                    Text("Sin impuesto").tag(UUID?.none)
                    ForEach(taxGroups.filter { !$0.isArchived }) { group in
                        Text("\(group.name) · \(group.percent.formatted())%").tag(Optional(group.id))
                    }
                }
                .accessibilityLabel("Impuesto sobre ventas")
                LabeledContent("Subtotal", value: validLines.reduce(0) { $0 + $1.amount }.money)
                LabeledContent("Descuento") {
                    MoneyField(title: String(localized: "Descuento"), minorUnits: $discount)
                        .multilineTextAlignment(.trailing)
                }
                if discount > validLines.reduce(0, { $0 + $1.amount }) {
                    Text("El descuento no puede ser mayor que el subtotal.").font(.footnote).foregroundStyle(Palette.negative)
                }
                LabeledContent("Sales tax", value: (preview?.totalTax ?? 0).money)
                LabeledContent {
                    Text((preview?.total ?? 0).money).font(.amount(28)).monospacedDigit()
                } label: {
                    Text("Total").font(.headline)
                }
            }
            .font(.subheadline)

            Section(title: "Mensaje para el cliente") {
                TextField("Notas y términos", text: $customerMessage, axis: .vertical)
            }

            Section {
            } footer: {
                Text("Al emitirla se registra el asiento contable: débito a cuentas por cobrar, crédito a ingresos y sales tax.")
            }
        }
        .screenBackground()
        // Canvas `FacturaNueva`: «Vista previa» y la acción principal fijas abajo.
        .bottomActionBar {
            Button("Vista previa", action: showPreview).buttonStyle(.secondary)
                .disabled(customerID == nil || validLines.isEmpty)
            Button("Emitir factura", action: issue).buttonStyle(.primary)
                .disabled(customerID == nil || validLines.isEmpty)
        }
    }

    /// `MacFacturaNueva` en iPad y Mac (hasta AX3); el formulario del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    // MARK: iPad y Mac (`MacFacturaNueva`)

    private var wideForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                wideHeaderCard
                wideLinesCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        wideMessageCard.frame(maxWidth: .infinity)
                        wideTotalsCard.frame(width: 340)
                    }
                    VStack(spacing: 16) { wideMessageCard; wideTotalsCard }
                }
                Text("Al emitirla se registra el asiento contable: débito a cuentas por cobrar, crédito a ingresos y sales tax.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
    }

    private func fieldLabel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cliente (ancho doble), número, fecha y vencimiento con el plazo como título.
    private var wideHeaderCard: some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: issueDate),
                                                   to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 14) {
            fieldLabel(String(localized: "Cliente")) {
                Menu {
                    Picker("Cliente", selection: $customerID) {
                        Text("Elegir cliente…").tag(UUID?.none)
                        ForEach(customers.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Nuevo cliente", systemImage: "person.badge.plus") { showingNewCustomer = true }
                } label: {
                    HStack(spacing: 6) {
                        if let customer {
                            Text(customer.name).fontWeight(.semibold).foregroundStyle(Palette.ink)
                            if !customer.email.isEmpty { Text("· \(customer.email)").foregroundStyle(Palette.ink3) }
                        } else {
                            Text("Elegir cliente…").foregroundStyle(Palette.brand)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Palette.ink3)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.separator))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cliente")
                .accessibilityValue(customer?.name ?? String(localized: "Sin elegir"))
            }
            fieldLabel(String(localized: "Número")) {
                Text(savedInvoice.map { $0.number.isEmpty ? String(localized: "Al emitir") : $0.number }
                     ?? (try? books.peekDocumentNumber(.invoice)) ?? "—")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).frame(minHeight: 38)
            }
            fieldLabel(String(localized: "Fecha")) {
                DatePicker("Fecha", selection: $issueDate, displayedComponents: .date).labelsHidden().frame(minHeight: 38)
            }
            fieldLabel(days == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(days)")) {
                DatePicker("Vence", selection: $dueDate, in: issueDate..., displayedComponents: .date).labelsHidden().frame(minHeight: 38)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Tabla de líneas: # · PRODUCTO O SERVICIO · CUENTA · CANT. · PRECIO · IMPUESTO · IMPORTE.
    private var wideLinesCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Producto o servicio").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cuenta de ingreso").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cant.").frame(width: 120, alignment: .center)
                Text("Precio").frame(width: amountColumn, alignment: .trailing)
                Text("Impuesto").frame(width: 96, alignment: .leading)
                Text("Importe").frame(width: amountColumn, alignment: .trailing)
                Color.clear.frame(width: 32, height: 1)
            }
            .font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(Palette.ink3)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .accessibilityHidden(true)
            ForEach(Array($lines.enumerated()), id: \.element.id) { index, $line in
                Divider()
                HStack(spacing: 10) {
                    Text("\(index + 1)").foregroundStyle(Palette.ink3).frame(width: 24, alignment: .leading).accessibilityHidden(true)
                    TextField("Producto o servicio", text: $line.details).fieldBox().frame(maxWidth: .infinity)
                    Menu {
                        Picker("Cuenta de ingreso", selection: $line.incomeAccountID) {
                            ForEach(incomeAccounts) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                    } label: {
                        Text(incomeAccounts.first { $0.id == line.incomeAccountID }?.displayName ?? String(localized: "Cuenta de ingreso"))
                            .lineLimit(1).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Cuenta de ingreso")
                    QuantityStepper(quantity: $line.quantity).frame(width: 120)
                    MoneyField(title: String(localized: "Precio"), minorUnits: $line.unitPrice)
                        .multilineTextAlignment(.trailing).fieldBox().frame(width: amountColumn)
                    Button(line.isTaxable ? String(localized: "Gravable") : String(localized: "Exento")) { line.isTaxable.toggle() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(line.isTaxable ? Palette.brand : Palette.ink2)
                        .frame(width: 96, height: 38)
                        .background(line.isTaxable ? Palette.brandWash : Palette.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                        .accessibilityLabel("Gravable")
                        .accessibilityValue(line.isTaxable ? Text("Sí") : Text("No"))
                    Text(line.amount.money).fontWeight(.semibold).monospacedDigit().frame(width: amountColumn, alignment: .trailing)
                    Button { lines.remove(at: index) } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
                    .disabled(lines.count <= 1)
                    .accessibilityLabel("Quitar la línea \(index + 1)")
                }
                .font(.subheadline)
                .padding(.horizontal, 18).padding(.vertical, 6)
            }
            Divider()
            Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft(incomeAccountID: incomeAccounts.first?.id)) }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.brand)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 18)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var wideMessageCard: some View {
        fieldLabel(String(localized: "Mensaje para el cliente")) {
            TextField("Notas y términos", text: $customerMessage, axis: .vertical)
                .lineLimit(3...)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.separator))
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var wideTotalsCard: some View {
        VStack(spacing: 8) {
            LabeledContent("Subtotal", value: validLines.reduce(0) { $0 + $1.amount }.money)
            LabeledContent("Impuesto") {
                Picker("Impuesto", selection: $taxGroupID) {
                    Text("Sin impuesto").tag(UUID?.none)
                    ForEach(taxGroups.filter { !$0.isArchived }) { group in
                        Text("\(group.name) · \(group.percent.formatted())%").tag(Optional(group.id))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Impuesto sobre ventas")
            }
            LabeledContent("Descuento") {
                MoneyField(title: String(localized: "Descuento"), minorUnits: $discount).multilineTextAlignment(.trailing).frame(maxWidth: 120)
            }
            if discount > validLines.reduce(0, { $0 + $1.amount }) {
                Text("El descuento no puede ser mayor que el subtotal.").font(.footnote).foregroundStyle(Palette.negative)
            }
            LabeledContent("Sales tax", value: (preview?.totalTax ?? 0).money)
            Divider()
            LabeledContent {
                Text((preview?.total ?? 0).money).font(.amount(24)).monospacedDigit()
            } label: {
                Text("Total").font(.headline)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Celdas y líneas

    private func cell<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Palette.ink3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var numberCell: some View {
        cell(String(localized: "Número")) {
            Text(savedInvoice.map { $0.number.isEmpty ? String(localized: "Al emitir") : $0.number }
                 ?? (try? books.peekDocumentNumber(.invoice)) ?? "—")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
        }
    }

    private var dateCell: some View {
        cell(String(localized: "Fecha")) {
            DatePicker("Fecha", selection: $issueDate, displayedComponents: .date).labelsHidden().fixedSize()
        }
    }

    /// El título es el plazo del cliente («Neto 15») cuando el vencimiento coincide con él.
    private var dueCell: some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: issueDate),
                                                   to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        let title = days == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(days)")
        return cell(title) {
            DatePicker("Vence", selection: $dueDate, in: issueDate..., displayedComponents: .date).labelsHidden().fixedSize()
        }
    }

    /// Línea compacta: descripción y total; precio, impuesto y cantidad con −/+; la cuenta de ingreso en un menú.
    private func lineRow(_ line: Binding<LineDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Descripción", text: line.details).font(.body.weight(.semibold))
                Text(line.wrappedValue.amount.money).font(.body.weight(.semibold)).monospacedDigit()
            }
            HStack(spacing: 8) {
                MoneyField(title: String(localized: "Precio"), minorUnits: line.unitPrice)
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                    .fixedSize()
                Text("·").foregroundStyle(Palette.ink3).accessibilityHidden(true)
                Button(line.wrappedValue.isTaxable ? String(localized: "Gravable") : String(localized: "Sin impuesto")) {
                    line.wrappedValue.isTaxable.toggle()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Palette.brand)
                .accessibilityLabel("Gravable")
                .accessibilityValue(line.wrappedValue.isTaxable ? Text("Sí") : Text("No"))
                Spacer(minLength: 4)
                QuantityStepper(quantity: line.quantity)
            }
            Menu {
                Picker("Cuenta de ingreso", selection: line.incomeAccountID) {
                    ForEach(incomeAccounts) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } label: {
                Text(incomeAccounts.first { $0.id == line.wrappedValue.incomeAccountID }?.displayName ?? String(localized: "Cuenta de ingreso"))
                    .font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            .accessibilityLabel("Cuenta de ingreso")
        }
        .padding(.vertical, 4)
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
        lines = invoice.sortedLines.map {
            LineDraft(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice,
                      isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
        }
        if lines.isEmpty { lines = [LineDraft(incomeAccountID: incomeAccounts.first?.id)] }
    }

    private var input: InvoiceDraftInput {
        InvoiceDraftInput(
            customer: customer, issueDate: issueDate, dueDate: dueDate, taxGroupID: taxGroupID,
            discount: discount, customerMessage: customerMessage,
            lines: validLines.map {
                .init(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice,
                      isTaxable: $0.isTaxable, incomeAccountID: $0.incomeAccountID)
            }
        )
    }

    /// Guarda (o reescribe) el borrador con lo que hay ahora en pantalla.
    @discardableResult
    private func persistDraft() throws -> Invoice {
        let invoice = try books.saveDraft(input, into: savedInvoice)
        savedInvoice = invoice
        return invoice
    }

    /// Borrador creado en esta pantalla (por la vista previa) al hacer una factura nueva.
    private var hasNewDraft: Bool { editing == nil && savedInvoice != nil }

    private func cancel() {
        if hasNewDraft { confirmingCancel = true } else { dismiss() }
    }

    private func discardDraft() {
        if let savedInvoice {
            context.delete(savedInvoice)
            try? context.save()
        }
        dismiss()
    }

    private func saveDraft() {
        do {
            try persistDraft()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// La vista previa sale del PDF real, así que primero se guarda el borrador.
    private func showPreview() {
        do {
            previewing = try persistDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func issue() {
        do {
            // Si un intento anterior falló, el borrador se reescribe con las correcciones antes de emitir.
            try books.issue(try persistDraft())
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { InvoiceEditorView() }.modelContainer(SampleData.makeContainer())
}

/// Cantidad con «−» y «+» en una píldora (canvas `FacturaNueva`); para VoiceOver es un `Stepper`.
struct QuantityStepper: View {
    @Binding var quantity: Decimal

    var body: some View {
        HStack(spacing: 0) {
            Button { quantity = max(1, quantity - 1) } label: {
                Image(systemName: "minus").frame(width: 36, height: 32)
            }
            .disabled(quantity <= 1)
            Text(quantity.formatted()).font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 24)
            Button { quantity += 1 } label: {
                Image(systemName: "plus").frame(width: 36, height: 32)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityRepresentation {
            Stepper("Cantidad", value: $quantity, in: 1...9_999)
        }
    }
}

/// Título en línea en pantallas estrechas; grande en las anchas (`MacFacturaNueva`).
struct InlineTitleUnless: ViewModifier {
    let wide: Bool
    func body(content: Content) -> some View {
        if wide { content } else { content.inlineTitle() }
    }
}
