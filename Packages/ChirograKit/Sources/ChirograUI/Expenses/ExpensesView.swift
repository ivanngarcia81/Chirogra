import ChirograCore
import ChirograData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
                ForEach(Segment.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)

            switch segment {
            case .expenses: ExpenseListView { segment = .bills }
            case .bills: BillListView()
            case .vendors: VendorListView()
            }
        }
        .background(Palette.background)
        .navigationTitle("Gastos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddButton(title: "Nuevo") { showingEditor = true }
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

/// Gastos (canvas `Gastos`): tarjeta del mes con barra por categoría, aviso de facturas por pagar esta semana y la
/// lista de gastos con un icono por categoría.
struct ExpenseListView: View {
    /// Abre «Por pagar» desde el aviso.
    var showBills: () -> Void = {}
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]

    /// Colores de la barra del canvas, de la categoría mayor a «Otros».
    private static let barColors: [Color] = [
        Color(light: 0x3A3FD1, dark: 0x8F93FF), Color(light: 0x7C80E8, dark: 0x5C61C9),
        Color(light: 0xE58A4E, dark: 0xE58A4E), Color(light: 0xF2B33D, dark: 0xF2B33D), Color(light: 0xB9BCCF, dark: 0x6B7090),
    ]

    private func category(_ expense: Expense) -> Account? {
        let id = expense.sortedLines.first?.accountID
        return accounts.first { $0.id == id }
    }

    var body: some View {
        List {
            Section { monthCard }
                .listRowBackground(Palette.surface)

            let dueSoon = bills.filter { $0.isOpen && $0.dueDate <= Calendar.current.date(byAdding: .day, value: 7, to: .now)! }
            if !dueSoon.isEmpty {
                Section {
                    Button(action: showBills) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill").font(.title3).accessibilityHidden(true)
                            Text("\(dueSoon.count) facturas por pagar esta semana").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(dueSoon.reduce(0) { $0 + $1.balanceDue }.money).font(.subheadline.weight(.bold)).monospacedDigit()
                        }
                        .foregroundStyle(Palette.warning)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Palette.warningWash)
            }

            if expenses.isEmpty {
                EmptyStateView(systemImage: "wallet.bifold", title: String(localized: "Sin gastos todavía"),
                               message: String(localized: "Registra un gasto con el botón + y adjunta el recibo."))
                    .listRowBackground(Palette.surface)
            } else {
                Section {
                    ForEach(expenses) { expense in
                        NavigationLink { ExpenseDetailView(expense: expense) } label: {
                            LedgerRow(title: expense.payee, subtitle: "\(category(expense)?.name ?? String(localized: "Sin categoría")) · \(expense.date.dayMonth)") {
                                IconTile(systemImage: Self.symbol(for: category(expense)), foreground: Palette.outflow, background: Palette.outflowWash)
                            } trailing: {
                                HStack(spacing: 6) {
                                    if !(expense.attachments ?? []).isEmpty {
                                        Image(systemName: "paperclip").foregroundStyle(Palette.ink3).accessibilityLabel("Recibo adjunto")
                                    }
                                    Text("−\(expense.total.money)").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.outflow)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Recientes").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).textCase(nil)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
    }

    /// Gasto del mes por categoría: las mismas cifras que el estado de resultados (gastos y costo de ventas),
    /// para que coincida con «Gastos» de Inicio. Las cuatro mayores y el resto en «Otros».
    private var monthCard: some View {
        let month = DateInterval.month(containing: .now)
        let statement = Ledger(accounts: accounts, lines: journalLines).incomeStatement(month)
        let rows = (statement.costOfGoodsSold + statement.expenses).filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
        let total = rows.reduce(0) { $0 + $1.amount }
        var slices = rows.prefix(4).map { (name: $0.account.name, amount: $0.amount) }
        let rest = rows.dropFirst(4).reduce(0) { $0 + $1.amount }
        if rest > 0 { slices.append((String(localized: "Otros"), rest)) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.month(.wide)).sentenceCased).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                Text(total.money).font(.amount(24)).foregroundStyle(Palette.ink)
            }
            if total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(slices.indices, id: \.self) { index in
                            Rectangle().fill(Self.barColors[index])
                                .frame(width: max(2, (proxy.size.width - CGFloat(slices.count - 1) * 2) * CGFloat(slices[index].amount) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(slices.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(Self.barColors[index]).frame(width: 9, height: 9).accessibilityHidden(true)
                            Text(slices[index].name).foregroundStyle(Palette.ink2).lineLimit(1)
                            Text(slices[index].amount.money).fontWeight(.semibold).foregroundStyle(Palette.ink).monospacedDigit()
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("Sin gastos este mes").font(.subheadline).foregroundStyle(Palette.ink3)
            }
        }
        .padding(.vertical, 4)
    }

    /// Icono por categoría, por palabras del nombre (en español o en inglés) o por el tipo de cuenta.
    static func symbol(for account: Account?) -> String {
        let name = account?.name.lowercased() ?? ""
        let table: [(keys: [String], symbol: String)] = [
            (["material", "suministro", "suppl", "job"], "shippingbox"),
            (["vehí", "vehic", "transport", "car ", "truck", "combustible", "fuel", "gas"], "car"),
            (["software", "suscrip", "subscri"], "laptopcomputer"),
            (["renta", "alquiler", "rent", "lease"], "house"),
            (["seguro", "insurance"], "shield"),
            (["publicidad", "advertis", "marketing"], "megaphone"),
            (["comida", "meal", "restaur"], "fork.knife"),
            (["teléfono", "phone", "internet", "utilit", "servicios públicos"], "bolt"),
            (["subcontrat", "contract labor", "professional", "profesional"], "person.2"),
            (["banco", "bank", "comisi", "fee"], "building.columns"),
        ]
        return table.first { entry in entry.keys.contains { name.contains($0) } }?.symbol ?? "receipt"
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
    @State private var receipts: [(data: Data, name: String, type: UTType)] = []
    @State private var errorMessage: String?

    private var expenseAccounts: [Account] { accounts.filtered { $0.accountType == .expense || $0 == .fixedAsset || $0 == .otherCurrentAsset } }
    private var paymentAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                MoneyField(title: String(localized: "Importe (impuesto incluido)"), minorUnits: $amount).font(.amount(24))
                TextField("Pagado a (comercio o persona)", text: $payee)
                Picker("Proveedor", selection: $vendorID) {
                    Text("Ninguno").tag(UUID?.none)
                    ForEach(vendors) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            }
            Section {
                AccountPicker(title: String(localized: "Categoría"), accounts: expenseAccounts, selection: $categoryID)
                AccountPicker(title: String(localized: "Pagado con"), accounts: paymentAccounts, selection: $paymentAccountID)
                TextField("Nota", text: $memo, axis: .vertical)
            } footer: {
                Text("En EE. UU. el sales tax de tus compras forma parte del gasto.")
            }
            Section(title: "Recibo") {
                ForEach(receipts.indices, id: \.self) { index in
                    HStack {
                        ReceiptThumbnail(data: receipts[index].data, contentType: receipts[index].type.identifier, side: 48)
                        Text(receipts[index].name).lineLimit(1)
                    }
                }
                .onDelete { receipts.remove(atOffsets: $0) }
                ReceiptPickerButtons { data, name, type in receipts.append((data, name, type)) }
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
        let books = Bookkeeper(context: context)
        do {
            try books.record(expense)
        } catch {
            context.delete(expense)
            errorMessage = error.localizedDescription
            return
        }
        // El gasto ya está registrado; un recibo ilegible no lo deshace, solo se avisa.
        var failed: [String] = []
        for receipt in receipts {
            do { try books.attachReceipt(receipt.data, filename: receipt.name, contentType: receipt.type, to: expense) }
            catch { failed.append(receipt.name) }
        }
        if failed.isEmpty { dismiss() } else {
            errorMessage = String(localized: "El gasto se guardó, pero no se pudo adjuntar: \(failed.joined(separator: ", ")). Ábrelo desde la lista para reintentar.")
        }
    }
}

struct BillListView: View {
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var paying: Bill?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                LabeledContent("Total por pagar", value: bills.filter(\.isOpen).reduce(0) { $0 + $1.balanceDue }.money)
                    .font(.headline)
            }
            .listRowBackground(Palette.surface)
            if bills.isEmpty {
                EmptyStateView(systemImage: "doc.text", title: String(localized: "Sin facturas por pagar"),
                               message: String(localized: "Registra las facturas de tus proveedores para saber qué vence y cuándo."))
                    .listRowBackground(Palette.surface)
            }
            Section {
                ForEach(bills) { bill in
                    Button { if bill.isOpen { paying = bill } } label: {
                        LedgerRow(title: bill.vendor?.name ?? String(localized: "Proveedor"), subtitle: "\(bill.vendorNumber) · \(bill.dueDate.dueLabel)") {
                            IconTile(systemImage: "doc.text", foreground: Palette.outflow, background: Palette.outflowWash)
                        } trailing: {
                            VStack(alignment: dynamicTypeSize.amountAlignment, spacing: 3) {
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
                MoneyField(title: String(localized: "Importe total"), minorUnits: $amount)
                AccountPicker(title: String(localized: "Categoría"), accounts: costAccounts, selection: $accountID)
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
                MoneyField(title: String(localized: "Importe"), minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagar desde"), accounts: accounts.filtered { $0.isMoneyAccount && $0 != .undepositedFunds }, selection: $accountID)
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
                EmptyStateView(systemImage: "shippingbox", title: String(localized: "Sin proveedores"), message: String(localized: "Añade a quienes te venden bienes o servicios."))
                    .listRowBackground(Palette.surface)
            }
            ForEach(vendors) { vendor in
                NavigationLink { VendorDetailView(vendor: vendor) } label: {
                    LedgerRow(title: vendor.name, subtitle: vendor.is1099 ? String(localized: "Sujeto a 1099") : (vendor.email.isEmpty ? String(localized: "Proveedor") : vendor.email)) {
                        InitialsTile(text: Initials.from(vendor.name), foreground: Palette.outflow, background: Palette.outflowWash)
                    } trailing: {
                        Text(vendor.openBalance.money).font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationLinkIndicatorVisibility(.hidden)
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
                AccountPicker(title: String(localized: "Categoría por defecto"), accounts: accounts.filtered { $0.accountType == .expense }, selection: $defaultAccountID)
                Toggle("Sujeto a 1099", isOn: $is1099)
                if is1099 { TextField("Últimos 4 dígitos del TIN", text: $tinLast4) }
            } footer: {
                Text("Chirogra solo guarda los últimos 4 dígitos del TIN.")
            }
        }
        .screenBackground()
        .navigationTitle(vendor == nil ? String(localized: "Nuevo proveedor") : vendor!.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
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
