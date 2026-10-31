import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Gastos (canvas: `Gastos`, `ProveedorFicha`): gastos pagados, facturas por pagar y proveedores.
struct ExpensesView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case expenses = "Gastos"
        case bills = "Por pagar"
        case vendors = "Proveedores"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .expenses
    @State private var showingEditor = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)

            switch segment {
            case .expenses: ExpenseListView()
            case .bills: BillListView()
            case .vendors: VendorListView()
            }
        }
        .background(Palette.background)
        .navigationTitle("Gastos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: { Label("Nuevo", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                switch segment {
                case .expenses: ExpenseEditorView()
                case .bills: BillEditorView()
                case .vendors: VendorEditorView()
                }
            }
        }
    }
}

struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var accounts: [Account]

    private func categoryName(_ expense: Expense) -> String {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }?.name ?? "Sin categoría"
    }

    var body: some View {
        List {
            let thisMonth = DateInterval.month(containing: .now)
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Gastado este mes").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
                        Text(expenses.filter { thisMonth.contains($0.date) }.reduce(0) { $0 + $1.total }.money).font(.amount(28))
                    }
                    Spacer()
                }
            }
            .listRowBackground(Palette.surface)

            if expenses.isEmpty {
                EmptyStateView(systemImage: "wallet.bifold", title: "Sin gastos todavía",
                               message: "Registra un gasto con el botón + y adjunta el recibo.")
                    .listRowBackground(Palette.surface)
            }
            Section {
                ForEach(expenses) { expense in
                    LedgerRow(title: expense.payee, subtitle: "\(categoryName(expense)) · \(expense.date.dayMonth)") {
                        IconTile(systemImage: "receipt", foreground: Palette.outflow, background: Palette.outflowWash)
                    } trailing: {
                        Text("−\(expense.total.money)").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.outflow)
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
    }
}

struct ExpenseEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var payee = ""
    @State private var vendorID: UUID?
    @State private var date = Date()
    @State private var amount: Int64 = 0
    @State private var categoryID: UUID?
    @State private var paymentAccountID: UUID?
    @State private var memo = ""
    @State private var errorMessage: String?

    private var expenseAccounts: [Account] { accounts.filtered { $0.accountType == .expense || $0 == .fixedAsset || $0 == .otherCurrentAsset } }
    private var paymentAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                MoneyField(title: "Importe (impuesto incluido)", minorUnits: $amount).font(.amount(24))
                TextField("Pagado a (comercio o persona)", text: $payee)
                Picker("Proveedor", selection: $vendorID) {
                    Text("Ninguno").tag(UUID?.none)
                    ForEach(vendors) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            }
            Section {
                AccountPicker(title: "Categoría", accounts: expenseAccounts, selection: $categoryID)
                AccountPicker(title: "Pagado con", accounts: paymentAccounts, selection: $paymentAccountID)
                TextField("Nota", text: $memo, axis: .vertical)
            } footer: {
                Text("En EE. UU. el sales tax de tus compras forma parte del gasto. La lectura automática de recibos llega en la fase 2.")
            }
        }
        .screenBackground()
        .navigationTitle("Nuevo gasto")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(amount <= 0 || categoryID == nil || paymentAccountID == nil || (payee.isEmpty && vendorID == nil))
            }
        }
        .onChange(of: vendorID) {
            guard let vendor = vendors.first(where: { $0.id == vendorID }) else { return }
            if payee.isEmpty { payee = vendor.name }
            if let defaultAccount = vendor.defaultExpenseAccountID { categoryID = defaultAccount }
        }
        .onAppear { paymentAccountID = paymentAccountID ?? paymentAccounts.first { $0.subtype == .bank }?.id }
    }

    private func save() {
        let vendor = vendors.first { $0.id == vendorID }
        let expense = Expense(date: date, payee: payee.isEmpty ? (vendor?.name ?? "") : payee, paymentAccountID: paymentAccountID, vendor: vendor)
        expense.memo = memo
        let line = ExpenseLine(details: memo.isEmpty ? expense.payee : memo, amount: amount, accountID: categoryID)
        context.insert(expense)
        line.expense = expense
        context.insert(line)
        do {
            try Bookkeeper(context: context).record(expense)
            dismiss()
        } catch {
            context.delete(expense)
            errorMessage = error.localizedDescription
        }
    }
}

struct BillListView: View {
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var paying: Bill?

    var body: some View {
        List {
            Section {
                LabeledContent("Total por pagar", value: bills.filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }.money)
                    .font(.headline)
            }
            .listRowBackground(Palette.surface)
            if bills.isEmpty {
                EmptyStateView(systemImage: "doc.text", title: "Sin facturas por pagar",
                               message: "Registra las facturas de tus proveedores para saber qué vence y cuándo.")
                    .listRowBackground(Palette.surface)
            }
            Section {
                ForEach(bills) { bill in
                    Button { if bill.isOpen { paying = bill } } label: {
                        LedgerRow(title: bill.vendor?.name ?? "Proveedor", subtitle: "\(bill.vendorNumber) · vence \(bill.dueDate.dayMonth)") {
                            IconTile(systemImage: "doc.text", foreground: Palette.outflow, background: Palette.outflowWash)
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(bill.balanceDue.money).font(.body.weight(.semibold)).monospacedDigit()
                                StatusChip(bill: bill)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) } }
    }
}

struct BillEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var vendorID: UUID?
    @State private var number = ""
    @State private var billDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var amount: Int64 = 0
    @State private var accountID: UUID?
    @State private var details = ""
    @State private var errorMessage: String?

    private var costAccounts: [Account] { accounts.filtered { $0.accountType == .expense || $0 == .fixedAsset || $0 == .inventory } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Picker("Proveedor", selection: $vendorID) {
                    Text("Elegir…").tag(UUID?.none)
                    ForEach(vendors) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Número de la factura del proveedor", text: $number)
                DatePicker("Fecha", selection: $billDate, displayedComponents: .date)
                DatePicker("Vence", selection: $dueDate, in: billDate..., displayedComponents: .date)
            }
            Section {
                MoneyField(title: "Importe total", minorUnits: $amount)
                AccountPicker(title: "Categoría", accounts: costAccounts, selection: $accountID)
                TextField("Descripción", text: $details)
            }
        }
        .screenBackground()
        .navigationTitle("Factura por pagar")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(vendorID == nil || amount <= 0 || accountID == nil)
            }
        }
        .onChange(of: vendorID) {
            guard let vendor = vendors.first(where: { $0.id == vendorID }) else { return }
            accountID = vendor.defaultExpenseAccountID ?? accountID
            dueDate = Calendar.current.date(byAdding: .day, value: vendor.paymentTermsDays, to: billDate) ?? dueDate
        }
    }

    private func save() {
        let bill = Bill(vendor: vendors.first { $0.id == vendorID }, vendorNumber: number, billDate: billDate, dueDate: dueDate)
        let line = BillLine(details: details, amount: amount, accountID: accountID)
        context.insert(bill)
        line.bill = bill
        context.insert(line)
        do {
            try Bookkeeper(context: context).record(bill)
            dismiss()
        } catch {
            context.delete(bill)
            errorMessage = error.localizedDescription
        }
    }
}

struct PayBillView: View {
    let bill: Bill
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Proveedor", value: bill.vendor?.name ?? "")
                LabeledContent("Saldo", value: bill.balanceDue.money)
            }
            Section {
                MoneyField(title: "Importe", minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: "Pagar desde", accounts: accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds }, selection: $accountID)
            }
        }
        .screenBackground()
        .navigationTitle("Pagar factura")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Pagar", action: pay).disabled(amount <= 0 || accountID == nil) }
        }
        .onAppear { amount = bill.balanceDue }
    }

    private func pay() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).pay(bill, amount: amount, date: date, from: account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VendorListView: View {
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    var body: some View {
        List {
            if vendors.isEmpty {
                EmptyStateView(systemImage: "shippingbox", title: "Sin proveedores", message: "Añade a quienes te venden bienes o servicios.")
                    .listRowBackground(Palette.surface)
            }
            ForEach(vendors) { vendor in
                NavigationLink { VendorEditorView(vendor: vendor) } label: {
                    LedgerRow(title: vendor.name, subtitle: vendor.is1099 ? "Sujeto a 1099" : (vendor.email.isEmpty ? "Proveedor" : vendor.email)) {
                        InitialsTile(text: String(vendor.name.prefix(2)).uppercased(), foreground: Palette.outflow, background: Palette.outflowWash)
                    } trailing: {
                        Text(vendor.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
    }
}

struct VendorEditorView: View {
    var vendor: Vendor?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var terms = 30
    @State private var defaultAccountID: UUID?
    @State private var is1099 = false
    @State private var tinLast4 = ""

    var body: some View {
        Form {
            Section {
                TextField("Nombre o empresa", text: $name)
                TextField("Correo", text: $email)
                TextField("Teléfono", text: $phone)
            }
            Section {
                Picker("Condiciones de pago", selection: $terms) {
                    Text("Al recibir").tag(0); Text("Neto 15").tag(15); Text("Neto 30").tag(30); Text("Neto 60").tag(60)
                }
                AccountPicker(title: "Categoría por defecto", accounts: accounts.filtered { $0.accountType == .expense }, selection: $defaultAccountID)
                Toggle("Sujeto a 1099", isOn: $is1099)
                if is1099 { TextField("Últimos 4 dígitos del TIN", text: $tinLast4) }
            } footer: {
                Text("Chirogra solo guarda los últimos 4 dígitos del TIN.")
            }
        }
        .screenBackground()
        .navigationTitle(vendor == nil ? "Nuevo proveedor" : vendor!.name)
        .inlineTitle()
        .toolbar {
            if vendor == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let vendor else { return }
            name = vendor.name; email = vendor.email; phone = vendor.phone; terms = vendor.paymentTermsDays
            defaultAccountID = vendor.defaultExpenseAccountID; is1099 = vendor.is1099; tinLast4 = vendor.tinLast4
        }
    }

    private func save() {
        let target = vendor ?? Vendor(name: name)
        if vendor == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.email = email; target.phone = phone; target.paymentTermsDays = terms
        target.defaultExpenseAccountID = defaultAccountID; target.is1099 = is1099
        target.tinLast4 = String(tinLast4.filter(\.isNumber).suffix(4))
        try? context.save()
        dismiss()
    }
}
