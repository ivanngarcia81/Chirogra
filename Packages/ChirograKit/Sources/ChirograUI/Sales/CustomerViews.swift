import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Clientes con búsqueda y saldo (canvas: `Clientes`).
struct CustomerListView: View {
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var query = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filtered: [Customer] {
        customers.filter { !$0.isArchived && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(systemImage: "person.2", title: customers.isEmpty ? "Sin clientes todavía" : "Sin resultados",
                               message: customers.isEmpty ? "Añade tu primer cliente con el botón +." : "Prueba con otro nombre.")
                    .listRowBackground(Palette.surface)
            }
            ForEach(filtered) { customer in
                NavigationLink { CustomerDetailView(customer: customer) } label: {
                    LedgerRow(title: customer.name, subtitle: customer.email.isEmpty ? "Sin correo" : customer.email) {
                        InitialsTile(text: customer.initials)
                    } trailing: {
                        VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 2) {
                            Text(customer.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                            Text("por cobrar").font(.caption).foregroundStyle(Palette.ink3)
                            if customer.creditBalance > 0 {
                                Text("\(customer.creditBalance.money) a favor").font(.caption.weight(.semibold)).foregroundStyle(Palette.positive)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .searchable(text: $query, prompt: "Buscar clientes")
    }
}

/// Ficha de cliente (canvas: `ClienteFicha`).
struct CustomerDetailView: View {
    @Bindable var customer: Customer
    @State private var editing = false
    @State private var newInvoice = false
    @State private var refunding = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    InitialsTile(text: customer.initials)
                    VStack(alignment: .leading) {
                        Text(customer.name).font(.title3.weight(.semibold))
                        if !customer.email.isEmpty { Text(customer.email).foregroundStyle(Palette.ink3) }
                    }
                }
                LabeledContent("Saldo por cobrar", value: customer.openBalance.money)
                LabeledContent("Condiciones", value: customer.paymentTermsDays == 0 ? "Al recibir" : "Neto \(customer.paymentTermsDays)")
                if customer.isTaxExempt { LabeledContent("Sales tax", value: "Exento") }
            }
            if customer.creditBalance > 0 {
                Section {
                    LabeledContent("Saldo a favor", value: customer.creditBalance.money)
                        .foregroundStyle(Palette.positive).fontWeight(.semibold)
                    Button("Reembolsar", systemImage: "arrow.uturn.backward") { refunding = true }
                } footer: {
                    Text("Viene de notas de crédito que superaron lo que debía. Para usarlo en una factura, abre la factura pendiente y elige «Aplicar saldo a favor».")
                }
            }
            Section {
                Button("Nueva factura", systemImage: "doc.badge.plus") { newInvoice = true }
            }
            Section("Facturas") {
                let invoices = (customer.invoices ?? []).sorted { $0.issueDate > $1.issueDate }
                if invoices.isEmpty { Text("Sin facturas").foregroundStyle(Palette.ink3) }
                ForEach(invoices) { invoice in
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: { InvoiceRow(invoice: invoice) }
                }
            }
        }
        .screenBackground()
        .navigationTitle(customer.name)
        .inlineTitle()
        .toolbar { Button("Editar") { editing = true } }
        .sheet(isPresented: $editing) { NavigationStack { CustomerEditorView(customer: customer) } }
        .sheet(isPresented: $newInvoice) { NavigationStack { InvoiceEditorView(preselectedCustomer: customer) } }
        .sheet(isPresented: $refunding) { NavigationStack { CustomerRefundView(customer: customer) } }
    }
}

struct CustomerEditorView: View {
    var customer: Customer?
    var onCreate: ((Customer) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaxGroup.name) private var taxGroups: [TaxGroup]

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var billingAddress = ""
    @State private var terms = 30
    @State private var taxGroupID: UUID?
    @State private var isTaxExempt = false
    @State private var exemptionReason = ""

    init(customer: Customer? = nil, onCreate: ((Customer) -> Void)? = nil) {
        self.customer = customer
        self.onCreate = onCreate
    }

    var body: some View {
        Form {
            Section {
                TextField("Nombre o empresa", text: $name)
                TextField("Correo", text: $email)
                    .textContentType(.emailAddress)
                TextField("Teléfono", text: $phone)
                TextField("Dirección de facturación", text: $billingAddress, axis: .vertical)
            }
            Section("Cobro") {
                Picker("Condiciones de pago", selection: $terms) {
                    Text("Al recibir").tag(0)
                    Text("Neto 15").tag(15)
                    Text("Neto 30").tag(30)
                    Text("Neto 60").tag(60)
                }
                Picker("Impuesto por defecto", selection: $taxGroupID) {
                    Text("Sin impuesto").tag(UUID?.none)
                    ForEach(taxGroups) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Exento de sales tax", isOn: $isTaxExempt)
                if isTaxExempt { TextField("Motivo (reventa, sin fines de lucro…)", text: $exemptionReason) }
            }
        }
        .screenBackground()
        .navigationTitle(customer == nil ? "Nuevo cliente" : "Editar cliente")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let customer else { return }
            name = customer.name; email = customer.email; phone = customer.phone
            billingAddress = customer.billingAddress; terms = customer.paymentTermsDays
            taxGroupID = customer.defaultTaxGroupID; isTaxExempt = customer.isTaxExempt
            exemptionReason = customer.exemptionReason
        }
    }

    private func save() {
        let target = customer ?? Customer(name: name)
        if customer == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.email = email; target.phone = phone; target.billingAddress = billingAddress
        target.paymentTermsDays = terms; target.defaultTaxGroupID = taxGroupID
        target.isTaxExempt = isTaxExempt; target.exemptionReason = exemptionReason
        try? context.save()
        if customer == nil { onCreate?(target) }
        dismiss()
    }
}

/// Reembolso del saldo a favor del cliente: Debe Cuentas por cobrar / Haber Banco.
struct CustomerRefundView: View {
    let customer: Customer
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var errorMessage: String?

    private var paymentAccounts: [Account] { accounts.filtered { $0 == .bank || $0 == .cash } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Cliente", value: customer.name)
                LabeledContent("Saldo a favor", value: customer.creditBalance.money)
            }
            Section {
                MoneyField(title: "Importe a reembolsar", minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: "Pagar desde", accounts: paymentAccounts, selection: $accountID)
            } footer: {
                Text("Se registra la salida de dinero del banco y se cancela ese saldo a favor en cuentas por cobrar.")
            }
        }
        .screenBackground()
        .navigationTitle("Reembolso")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Reembolsar", action: save).disabled(amount <= 0 || accountID == nil)
            }
        }
        .onAppear {
            amount = customer.creditBalance
            accountID = accountID ?? paymentAccounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).refundCustomerCredit(customer, amount: amount, date: date, from: account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
