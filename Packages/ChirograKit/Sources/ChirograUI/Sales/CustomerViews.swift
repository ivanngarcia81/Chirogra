import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Clientes con búsqueda y saldo (canvas: `Clientes`).
struct CustomerListView: View {
    /// Texto de la búsqueda de Ventas (`SalesView`).
    var query = ""
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filtered: [Customer] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return customers.filter {
            !$0.isArchived && (text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) || $0.email.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(systemImage: "person.2", title: customers.isEmpty ? String(localized: "Sin clientes todavía") : String(localized: "Sin resultados"),
                               message: customers.isEmpty ? String(localized: "Añade tu primer cliente con el botón +.") : String(localized: "Prueba con otro nombre."))
                    .listRowBackground(Palette.surface)
            }
            ForEach(filtered) { customer in
                NavigationLink { CustomerDetailView(customer: customer) } label: {
                    LedgerRow(title: customer.name, subtitle: customer.email.isEmpty ? String(localized: "Sin correo") : customer.email) {
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
        .navigationLinkIndicatorVisibility(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

/// Ficha de cliente (canvas: `ClienteFicha`): cabecera, acciones, saldo con vencido y por vencer, y las pestañas
/// Historial, Contacto y Notas.
struct CustomerDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case history = "Historial", contact = "Contacto", notes = "Notas"
        var id: String { rawValue }
    }

    @Bindable var customer: Customer
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var newInvoice = false
    @State private var refunding = false
    @State private var tab: Tab = .history

    private var openInvoices: [Invoice] { (customer.invoices ?? []).filter { $0.isOpen && $0.balanceDue > 0 } }
    private var overdue: Int64 { openInvoices.filter { $0.daysOverdue() != nil }.reduce(0) { $0 + $1.balanceDue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                ProfileHeader(initials: customer.initials, name: customer.name, detail: headerDetail, round: true,
                              foreground: overdue > 0 ? Palette.negative : Palette.brand,
                              background: overdue > 0 ? Palette.negativeWash : Palette.brandWash)
                actions
                balanceCard
                if customer.creditBalance > 0 { creditCard }
                Picker("Sección", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch tab {
                case .history: history
                case .contact: contact
                case .notes: notes
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .inlineTitle()
        .toolbar { Button("Editar") { editing = true } }
        .sheet(isPresented: $editing) { NavigationStack { CustomerEditorView(customer: customer) } }
        .sheet(isPresented: $newInvoice) { NavigationStack { InvoiceEditorView(preselectedCustomer: customer) } }
        .sheet(isPresented: $refunding) { NavigationStack { CustomerRefundView(customer: customer) } }
    }

    /// «Cliente desde marzo de 2025 · Neto 15».
    private var headerDetail: String {
        let since = ([customer.createdAt] + (customer.invoices ?? []).map(\.issueDate)).min() ?? customer.createdAt
        let terms = customer.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(customer.paymentTermsDays)")
        return String(localized: "Cliente desde \(since.formatted(.dateTime.month(.wide).year())) · \(terms)")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ProfileAction(title: String(localized: "Llamar"), systemImage: "phone") {
                if let url = URL(string: "tel:\(customer.phone.filter { $0.isNumber || $0 == "+" })") { openURL(url) }
            }
            .disabled(customer.phone.isEmpty)
            ProfileAction(title: String(localized: "Correo"), systemImage: "envelope") {
                if let url = URL(string: "mailto:\(customer.email)") { openURL(url) }
            }
            .disabled(customer.email.isEmpty)
            ProfileAction(title: String(localized: "Factura"), systemImage: "doc.badge.plus") { newInvoice = true }
        }
    }

    private var balanceCard: some View {
        let total = customer.openBalance
        return VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo pendiente").font(.footnote).foregroundStyle(Palette.ink3)
                    Text(total.money).font(.amount(28)).foregroundStyle(Palette.ink)
                }
            } trailing: {
                if total > 0 {
                    ShareLink(item: reminderText, subject: Text("Recordatorio de pago")) {
                        Text("Recordar pago").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(overdue > 0 ? Palette.negative : Palette.brand)
                            .background(overdue > 0 ? Palette.negativeWash : Palette.brandWash,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            if total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        if overdue > 0 {
                            Rectangle().fill(Palette.negative).frame(width: proxy.size.width * CGFloat(overdue) / CGFloat(total))
                        }
                        Rectangle().fill(Palette.brand)
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Vencido \(overdue.money)").foregroundStyle(Palette.negative).fontWeight(.semibold).fixedSize()
                        Spacer()
                        Text("Por vencer \((total - overdue).money)").foregroundStyle(Palette.ink2).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vencido \(overdue.money)").foregroundStyle(Palette.negative).fontWeight(.semibold)
                        Text("Por vencer \((total - overdue).money)").foregroundStyle(Palette.ink2)
                    }
                }
                .font(.footnote)
            }
            Divider()
            HStack(alignment: .top) {
                stat(String(localized: "Facturado en \(Date.now.formatted(.dateTime.year()))"), billedThisYear.money)
                stat(String(localized: "Paga en promedio"), averageDaysToPay.map { String(localized: "\($0) días") } ?? "—")
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.ink3)
            Text(value).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var billedThisYear: Int64 {
        let year = Calendar.current.component(.year, from: .now)
        return (customer.invoices ?? [])
            .filter { $0.status != .draft && $0.status != .void && Calendar.current.component(.year, from: $0.issueDate) == year }
            .reduce(0) { $0 + $1.total }
    }

    /// Días entre la fecha de la factura y su último cobro, de media entre las facturas pagadas.
    private var averageDaysToPay: Int? {
        let days = (customer.invoices ?? []).filter { $0.status == .paid }.compactMap { invoice -> Int? in
            guard let paid = (invoice.paymentApplications ?? []).compactMap(\.payment?.date).max() else { return nil }
            return Calendar.current.dateComponents([.day], from: invoice.issueDate, to: paid).day
        }
        return days.isEmpty ? nil : days.reduce(0, +) / days.count
    }

    private var reminderText: String {
        overdue > 0
            ? String(localized: "Hola, \(customer.name): tienes \(overdue.money) vencido con nosotros. ¿Nos ayudas con el pago? ¡Gracias!")
            : String(localized: "Hola, \(customer.name): te recordamos que tienes \(customer.openBalance.money) pendiente de pago. ¡Gracias!")
    }

    private var creditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Saldo a favor", value: customer.creditBalance.money)
                .foregroundStyle(Palette.positive).fontWeight(.semibold)
            Text("Viene de notas de crédito que superaron lo que debía. Para usarlo en una factura, abre la factura pendiente y elige «Aplicar saldo a favor».")
                .font(.footnote).foregroundStyle(Palette.ink3)
            Button("Reembolsar", systemImage: "arrow.uturn.backward") { refunding = true }.buttonStyle(.secondary)
        }
        .card()
    }

    // MARK: Pestañas

    /// Facturas y cobros, del más reciente al más antiguo, con un punto de color por estado.
    private var history: some View {
        let invoices = (customer.invoices ?? []).map { HistoryItem.invoice($0) }
        let payments = (customer.payments ?? []).map { HistoryItem.payment($0) }
        let items = (invoices + payments).sorted { $0.date > $1.date }
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text("Sin facturas").foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                switch item {
                case .invoice(let invoice):
                    NavigationLink { InvoiceDetailView(invoice: invoice) } label: { historyRow(item) }.buttonStyle(.plain)
                case .payment:
                    historyRow(item)
                }
            }
        }
        .card(padding: 12)
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 10) {
            Circle().fill(item.color).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.amount).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(item.amountColor)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var contact: some View {
        VStack(spacing: 10) {
            LabeledContent("Correo", value: customer.email.isEmpty ? "—" : customer.email)
            LabeledContent("Teléfono", value: customer.phone.isEmpty ? "—" : customer.phone)
            LabeledContent("Dirección de facturación", value: customer.billingAddress.isEmpty ? "—" : customer.billingAddress)
            if !customer.shippingAddress.isEmpty { LabeledContent("Dirección de envío", value: customer.shippingAddress) }
            LabeledContent("Sales tax", value: customer.isTaxExempt ? String(localized: "Exento") : String(localized: "Gravable"))
        }
        .font(.subheadline)
        .card()
    }

    private var notes: some View {
        TextField("Añadir una nota…", text: $customer.notes, axis: .vertical)
            .lineLimit(4...)
            .card()
    }
}

/// Una entrada del historial de un cliente.
private enum HistoryItem: Identifiable {
    case invoice(Invoice)
    case payment(PaymentReceived)

    var id: UUID {
        switch self {
        case .invoice(let invoice): invoice.id
        case .payment(let payment): payment.id
        }
    }

    var date: Date {
        switch self {
        case .invoice(let invoice): invoice.issueDate
        case .payment(let payment): payment.date
        }
    }

    var title: String {
        switch self {
        case .invoice(let invoice):
            let number = invoice.number.isEmpty ? String(localized: "Borrador") : invoice.number
            return String(localized: "Factura \(number) · \(invoice.statusTitle.lowercased())")
        case .payment(let payment):
            let numbers = (payment.applications ?? []).compactMap(\.invoice?.number).joined(separator: ", ")
            return numbers.isEmpty ? String(localized: "Pago recibido") : String(localized: "Pago recibido · \(numbers)")
        }
    }

    var subtitle: String {
        switch self {
        case .invoice(let invoice):
            invoice.isOpen ? "\(invoice.issueDate.dayMonth) · \(invoice.dueDate.dueLabel)" : invoice.issueDate.dayMonth
        case .payment(let payment):
            "\(payment.date.dayMonth) · \((PaymentMethod(rawValue: payment.methodRaw) ?? .other).title.lowercased())"
        }
    }

    var amount: String {
        switch self {
        case .invoice(let invoice): invoice.total.money
        case .payment(let payment): "+\(payment.amount.money)"
        }
    }

    var color: Color {
        switch self {
        case .invoice(let invoice):
            invoice.daysOverdue() != nil ? Palette.negative : invoice.isOpen ? Palette.brand : Palette.ink3
        case .payment: Palette.positive
        }
    }

    var amountColor: Color {
        switch self {
        case .invoice(let invoice): invoice.daysOverdue() != nil ? Palette.negative : Palette.ink
        case .payment: Palette.positive
        }
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
            Section(title: "Cobro") {
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
                MoneyField(title: String(localized: "Importe a reembolsar"), minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $accountID)
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
