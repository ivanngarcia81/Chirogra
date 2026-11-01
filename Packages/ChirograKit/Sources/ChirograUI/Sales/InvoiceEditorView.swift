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
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            Section(title: "Cliente") {
                Picker("Cliente", selection: $customerID) {
                    Text("Elegir cliente…").tag(UUID?.none)
                    ForEach(customers.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Nuevo cliente", systemImage: "person.badge.plus") { showingNewCustomer = true }
                if let customer, customer.isTaxExempt {
                    Label("Cliente exento de sales tax", systemImage: "checkmark.seal").foregroundStyle(Palette.positive)
                }
            }

            Section {
                LabeledContent("Número", value: savedInvoice.map { $0.number.isEmpty ? String(localized: "Se asigna al emitir") : $0.number }
                    ?? (try? books.peekDocumentNumber(.invoice)) ?? "—")
                DatePicker("Fecha", selection: $issueDate, displayedComponents: .date)
                DatePicker("Vence", selection: $dueDate, in: issueDate..., displayedComponents: .date)
            }

            Section(title: "Productos y servicios") {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Descripción", text: $line.details).font(.body.weight(.semibold))
                        HStack {
                            MoneyField(title: String(localized: "Precio"), minorUnits: $line.unitPrice)
                            Stepper(value: $line.quantity, in: 1...9_999) {
                                Text("× \(line.quantity.formatted())").monospacedDigit()
                            }
                            .fixedSize()
                        }
                        HStack {
                            Toggle("Gravable", isOn: $line.isTaxable).fixedSize()
                            Spacer()
                            Text(line.amount.money).font(.body.weight(.semibold)).monospacedDigit()
                        }
                        AccountPicker(title: String(localized: "Cuenta de ingreso"), accounts: incomeAccounts, selection: $line.incomeAccountID)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir producto o servicio", systemImage: "plus") {
                    lines.append(LineDraft(incomeAccountID: incomeAccounts.first?.id))
                }
            }

            Section {
                Picker("Impuesto sobre ventas", selection: $taxGroupID) {
                    Text("Sin impuesto").tag(UUID?.none)
                    ForEach(taxGroups.filter { !$0.isArchived }) { group in
                        Text("\(group.name) · \(group.percent.formatted())%").tag(Optional(group.id))
                    }
                }
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
                    Text((preview?.total ?? 0).money).font(.amount(24))
                } label: {
                    Text("Total").font(.headline)
                }
            }

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
        .sheet(item: $previewing) { invoice in
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }
        }
        .navigationTitle(editing == nil ? "Nueva factura" : "Editar borrador")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar borrador", action: saveDraft).disabled(customerID == nil)
            }
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
