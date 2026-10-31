import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Nueva factura (canvas: `FacturaNueva`). Trabaja con estado local y solo crea modelos al guardar,
/// así cancelar no deja nada a medias.
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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \TaxGroup.name) private var taxGroups: [TaxGroup]

    @State private var customerID: UUID?
    @State private var issueDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var taxGroupID: UUID?
    @State private var lines: [LineDraft] = [LineDraft()]
    @State private var customerMessage = ""
    @State private var errorMessage: String?
    @State private var savedInvoice: Invoice?
    @State private var showingNewCustomer = false

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
            taxComponents: components, customerIsTaxExempt: customer?.isTaxExempt ?? false
        )
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            Section("Cliente") {
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
                LabeledContent("Número", value: (try? books.peekDocumentNumber(.invoice)) ?? "—")
                DatePicker("Fecha", selection: $issueDate, displayedComponents: .date)
                DatePicker("Vence", selection: $dueDate, in: issueDate..., displayedComponents: .date)
            }

            Section("Productos y servicios") {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Descripción", text: $line.details).font(.body.weight(.semibold))
                        HStack {
                            MoneyField(title: "Precio", minorUnits: $line.unitPrice)
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
                        AccountPicker(title: "Cuenta de ingreso", accounts: incomeAccounts, selection: $line.incomeAccountID)
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
                LabeledContent("Subtotal", value: (preview?.subtotal ?? 0).money)
                LabeledContent("Sales tax", value: (preview?.totalTax ?? 0).money)
                LabeledContent {
                    Text((preview?.total ?? 0).money).font(.amount(24))
                } label: {
                    Text("Total").font(.headline)
                }
            }

            Section("Mensaje para el cliente") {
                TextField("Notas y términos", text: $customerMessage, axis: .vertical)
            }

            Section {
                Button("Emitir factura", action: issue).buttonStyle(.primary)
                    .disabled(customerID == nil || validLines.isEmpty)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            } footer: {
                Text("Al emitirla se registra el asiento contable: débito a cuentas por cobrar, crédito a ingresos y sales tax.")
            }
        }
        .screenBackground()
        .navigationTitle("Nueva factura")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar borrador", action: saveDraft).disabled(customerID == nil)
            }
        }
        .onAppear {
            if customerID == nil { customerID = preselectedCustomer?.id }
            if lines.first?.incomeAccountID == nil { lines[0].incomeAccountID = incomeAccounts.first?.id }
        }
        .onChange(of: customerID) {
            guard let customer else { return }
            taxGroupID = customer.defaultTaxGroupID
            dueDate = Calendar.current.date(byAdding: .day, value: customer.paymentTermsDays, to: issueDate) ?? issueDate
        }
        .sheet(isPresented: $showingNewCustomer) {
            NavigationStack { CustomerEditorView { customerID = $0.id } }
        }
    }

    @discardableResult
    private func makeInvoice() -> Invoice? {
        if let savedInvoice { return savedInvoice }
        guard let customer else { return nil }
        let invoice = Invoice(customer: customer, issueDate: issueDate, dueDate: dueDate)
        invoice.taxGroupID = taxGroupID
        invoice.customerMessage = customerMessage
        context.insert(invoice)
        for (index, line) in validLines.enumerated() {
            let model = InvoiceLine(details: line.details, quantity: line.quantity, unitPrice: line.unitPrice,
                                    isTaxable: line.isTaxable, incomeAccountID: line.incomeAccountID, order: index)
            model.invoice = invoice
            context.insert(model)
        }
        savedInvoice = invoice
        return invoice
    }

    private func saveDraft() {
        do {
            makeInvoice()
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func issue() {
        guard let invoice = makeInvoice() else { return }
        do {
            try books.issue(invoice)
            dismiss()
        } catch {
            // La factura queda como borrador; el usuario puede corregir y volver a emitir.
            try? context.save()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { InvoiceEditorView() }.modelContainer(SampleData.makeContainer())
}
