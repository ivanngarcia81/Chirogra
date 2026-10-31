import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Clientes con búsqueda y saldo (canvas: `Clientes`).
struct CustomerListView: View {
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var query = ""

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
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(customer.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                            Text("por cobrar").font(.caption).foregroundStyle(Palette.ink3)
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
