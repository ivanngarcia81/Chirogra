import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Ficha de proveedor (canvas `ProveedorFicha` en iPhone, `MacProveedorFicha` en iPad y Mac): cabecera, acciones,
/// resumen de tres cifras, la próxima factura por pagar e historial de gastos y facturas. Se edita desde «Editar».
struct VendorDetailView: View {
    let vendor: Vendor
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var editing = false
    @State private var paying: Bill?
    @State private var scheduling: Bill?
    @State private var addingExpense = false
    @State private var payFromID: UUID?
    @State private var payDate = Date()
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `MacProveedorFicha` en iPad y Mac (hasta AX3); la ficha del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    private var year: Int { Calendar.current.component(.year, from: .now) }
    private var bills: [Bill] { (vendor.bills ?? []).filter { $0.status != .void } }
    private var openBills: [Bill] { bills.filter(\.isOpen).sorted { $0.dueDate < $1.dueDate } }
    private var expenses: [Expense] { vendor.expenses ?? [] }
    private var category: String? { accounts.first { $0.id == vendor.defaultExpenseAccountID }?.name }
    private var paymentAccounts: [Account] { accounts.paymentAccounts }

    /// «Transferencia · Corriente ••4821» (canvas `MacProveedorFicha`: «Pago preferido»), o `nil` sin preferencia.
    private var preferredPayment: String? {
        let parts = [vendor.preferredPaymentMethod?.title, accounts.account(vendor.preferredPaymentAccountID)?.paymentLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «Recibido el 4 ago 2026», «Pendiente».
    private var w9Status: String {
        guard vendor.w9Received else { return String(localized: "Pendiente") }
        return vendor.w9ReceivedDate.map { String(localized: "Recibido el \($0.shortDate)") } ?? String(localized: "Recibido")
    }
    private var terms: String {
        vendor.paymentTermsDays == 0 ? String(localized: "Al recibir") : String(localized: "Neto \(vendor.paymentTermsDays)")
    }

    var body: some View {
        Group {
            if isWide { wideBody } else { compactBody }
        }
        .background(Palette.background)
        .recordTitle(vendor.name, section: [String(localized: "Proveedor"), category].compactMap { $0 }.joined(separator: " · "))
        .toolbar {
            Button("Editar") { editing = true }.headerButton()
            if isWide {
                Button { addingExpense = true } label: {
                    Label("Gasto", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Nuevo gasto")
                .headerButton()
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { VendorEditorView(vendor: vendor) }.editorSheetSizing() }
        .sheet(item: $paying) { bill in NavigationStack { PayBillView(bill: bill) }.editorSheetSizing() }
        .sheet(item: $scheduling) { bill in NavigationStack { SchedulePaymentView(bill: bill) }.editorSheetSizing() }
        .sheet(isPresented: $addingExpense) {
            NavigationStack { ExpenseEditorView(preselectedVendor: vendor) }.editorSheetSizing()
        }
        .onAppear {
            payFromID = payFromID ?? vendor.preferredPaymentAccountID ?? paymentAccounts.first { $0.subtype == .bank }?.id
        }
    }

    // MARK: iPhone (`ProveedorFicha`)

    private var compactBody: some View {
        List {
            if let errorMessage { ErrorBanner(message: errorMessage).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
            Section {
                VStack(spacing: 18) {
                    ProfileHeader(initials: Initials.from(vendor.name), name: vendor.name,
                                  detail: [category, terms, sinceText].compactMap { $0 }.joined(separator: " · "))
                        .fixedSize(horizontal: false, vertical: true)
                    actions
                }
                .padding(.top, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section { summary }

            if let bill = openBills.first { payCard(bill) }

            Section {
                LabeledContent("Pago preferido", value: preferredPayment ?? String(localized: "Sin preferencia"))
                if vendor.is1099 || vendor.w9Received {
                    LabeledContent("Formulario W-9") {
                        Text(w9Status).foregroundStyle(vendor.w9Received ? Palette.positive : Palette.warning)
                    }
                    if let attachment = vendor.w9Attachment { w9Link(attachment) }
                }
            } header: {
                SectionLabel(text: String(localized: "Pagos e impuestos"))
            } footer: {
                if vendor.is1099 && !vendor.w9Received {
                    Text("Pídele el W-9 antes de pagarle: lo necesitas para el 1099-NEC.")
                }
            }

            Section {
                if historyItems.isEmpty {
                    Text("Sin compras todavía").foregroundStyle(Palette.ink2)
                }
                ForEach(historyItems) { item in historyLink(item) }
            } header: {
                SectionLabel(text: String(localized: "Historial"))
            } footer: {
                if let category { Text("Categoría predeterminada: \(category)") }
            }
        }
        .groupedList()
        .screenBackground()
    }

    /// Llamar · Mensaje · Correo · Recibo (canvas): los tres primeros abren el teléfono, Mensajes o Mail con el dato
    /// del proveedor; «Recibo» abre un gasto nuevo de este proveedor para adjuntar el recibo (el escaneo es de la fase 2).
    private var actions: some View {
        let phone = vendor.phone.filter { $0.isNumber || $0 == "+" }
        return HStack(spacing: 8) {
            ProfileAction(title: String(localized: "Llamar"), systemImage: "phone") { open("tel:\(phone)") }
                .disabled(phone.isEmpty)
            ProfileAction(title: String(localized: "Mensaje"), systemImage: "message") { open("sms:\(phone)") }
                .disabled(phone.isEmpty)
            ProfileAction(title: String(localized: "Correo"), systemImage: "envelope") { open("mailto:\(vendor.email)") }
                .disabled(vendor.email.isEmpty)
            ProfileAction(title: String(localized: "Recibo"), systemImage: "doc.viewfinder") { addingExpense = true }
        }
        .padding(.horizontal, 8)
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url)
    }

    /// Resumen de tres cifras en una sola tarjeta con separadores verticales; con texto de accesibilidad, en columna.
    private var summary: some View {
        let stats = [
            (String(localized: "Por pagar"), vendor.openBalance.money),
            (String(localized: "Gastado \(Date.now.formatted(.appDateTime.year()))"), spentThisYear.money),
            (String(localized: "Compras"), (bills.count + expenses.count).formatted()),
        ]
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                         : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            ForEach(stats.indices, id: \.self) { index in
                if index > 0 && !dynamicTypeSize.isAccessibilitySize { Divider() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(stats[index].0).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
                    Text(stats[index].1).font(.headline).foregroundStyle(Palette.ink).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }

    /// La próxima factura por pagar con «Pagar desde», la fecha y «Registrar pago» por el saldo (canvas: el grupo
    /// «Factura por pagar»; programar el pago es de la fase 2). «Otro importe…» abre el pago parcial.
    @ViewBuilder
    private func payCard(_ bill: Bill) -> some View {
        Section {
            NavigationLink { BillDetailView(bill: bill) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text([bill.vendorNumber, bill.concept].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(String(localized: "Factura por pagar")))
                            .foregroundStyle(Palette.ink).lineLimit(2)
                        HStack(spacing: 4) {
                            StatusChip(billWithAge: bill)
                            Text("· \(bill.dueDate.dueLabel)").font(.footnote).foregroundStyle(Palette.ink2)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(bill.balanceDue.money).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
            }
            .navigationLinkIndicatorVisibility(.hidden)
            PaymentAccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $payFromID)
            DatePicker("Fecha de pago", selection: $payDate, displayedComponents: .date)
            Button { pay(bill) } label: {
                Label(String(localized: "Registrar pago de \(bill.balanceDue.money)"), systemImage: "checkmark.circle")
                    .frame(minHeight: Metrics.target)
            }
            .disabled(payFromID == nil)
            if bill.isScheduled {
                Button(role: .destructive) { unschedule(bill) } label: {
                    Label("Cancelar pago programado", systemImage: "xmark.circle").frame(minHeight: Metrics.target)
                }
                .foregroundStyle(Palette.negative)
            } else {
                Button { schedule(bill) } label: {
                    Label("Programar pago", systemImage: "calendar.badge.clock").frame(minHeight: Metrics.target)
                }
                .disabled(payFromID == nil)
            }
            Button { paying = bill } label: {
                Text("Otro importe…").frame(minHeight: Metrics.target)
            }
        } header: {
            SectionLabel(text: openBills.count > 1 ? String(localized: "Próxima factura por pagar · \(openBills.count) abiertas")
                                                   : String(localized: "Factura por pagar"))
        } footer: {
            Text("Chirogra te recuerda el pago; el dinero se mueve desde tu banco.")
        }
    }

    private func pay(_ bill: Bill) {
        guard let account = accounts.first(where: { $0.id == payFromID }) else { return }
        do {
            try Bookkeeper(context: context).pay(bill, amount: bill.balanceDue, date: payDate, from: account,
                                                 method: vendor.preferredPaymentMethod ?? .bankTransfer)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Programar pago» con la cuenta y la fecha de la tarjeta (canvas `ProveedorFicha`), sin hoja.
    private func schedule(_ bill: Bill) {
        guard let account = accounts.first(where: { $0.id == payFromID }) else { return }
        do {
            try Bookkeeper(context: context).schedulePayment(for: bill, on: payDate, from: account,
                                                             method: vendor.preferredPaymentMethod ?? .bankTransfer)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unschedule(_ bill: Bill) {
        do {
            try Bookkeeper(context: context).unschedulePayment(for: bill)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// La copia del W-9 para compartirla o abrirla.
    @ViewBuilder
    private func w9Link(_ attachment: Attachment) -> some View {
        if let data = attachment.data {
            ShareLink(item: AttachmentFile(data: data, filename: attachment.filename, contentType: attachment.contentType),
                      preview: SharePreview(attachment.filename)) {
                Label(String(localized: "Copia del W-9 · \(attachment.filename)"), systemImage: "doc.text")
                    .lineLimit(1)
                    .frame(minHeight: Metrics.target)
            }
        }
    }

    // MARK: Historial

    private enum Item: Identifiable {
        case bill(Bill), expense(Expense)
        var id: UUID { switch self { case .bill(let bill): bill.id; case .expense(let expense): expense.id } }
        var date: Date { switch self { case .bill(let bill): bill.billDate; case .expense(let expense): expense.date } }
    }

    private var historyItems: [Item] { (bills.map(Item.bill) + expenses.map(Item.expense)).sorted { $0.date > $1.date } }

    private func title(of item: Item) -> String {
        switch item {
        case .bill(let bill):
            String(localized: "Factura \(bill.vendorNumber) · \(bill.status == .paid ? String(localized: "pagada") : String(localized: "por pagar"))")
        case .expense(let expense):
            expense.memo.isEmpty ? String(localized: "Gasto") : String(localized: "Gasto · \(expense.memo)")
        }
    }

    private func account(of item: Item) -> String {
        switch item {
        case .bill: String(localized: "Cuentas por pagar")
        case .expense(let expense): accounts.account(expense.paymentAccountID)?.paymentLabel ?? "—"
        }
    }

    private func amount(of item: Item) -> Int64 {
        switch item {
        case .bill(let bill): bill.total
        case .expense(let expense): expense.total
        }
    }

    private func hasReceipt(_ item: Item) -> Bool {
        switch item {
        case .bill(let bill): !(bill.attachments ?? []).isEmpty
        case .expense(let expense): !(expense.attachments ?? []).isEmpty
        }
    }

    @ViewBuilder
    private func historyLink(_ item: Item) -> some View {
        let row = LedgerRow(title: title(of: item), subtitle: "\(item.date.dayMonth) · \(account(of: item))") {
            EmptyView()
        } trailing: {
            HStack(spacing: 6) {
                if hasReceipt(item) {
                    Image(systemName: "paperclip").font(.footnote).foregroundStyle(Palette.ink2).accessibilityLabel("Recibo adjunto")
                }
                Text(amount(of: item).money).monospacedDigit().foregroundStyle(Palette.ink)
            }
        }
        switch item {
        case .bill(let bill): NavigationLink { BillDetailView(bill: bill) } label: { row }.navigationLinkIndicatorVisibility(.hidden)
        case .expense(let expense): NavigationLink { ExpenseDetailView(expense: expense) } label: { row }.navigationLinkIndicatorVisibility(.hidden)
        }
    }

    // MARK: iPad y Mac (`MacProveedorFicha`)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                wideHeader
                KPIGrid(items: [
                    KPIItem(title: String(localized: "Por pagar"), value: vendor.openBalance.money,
                            foot: openBills.first.map { String(localized: "\(openBills.count) facturas · vence el \($0.dueDate.dayMonth)") }
                                ?? String(localized: "Al corriente"),
                            footColor: openBills.isEmpty ? Palette.positive : Palette.ink2),
                    KPIItem(title: String(localized: "Gastado en \(Date.now.formatted(.appDateTime.year()))"), value: spentThisYear.money,
                            foot: String(localized: "Desde el \(Calendar.current.dateInterval(of: .year, for: .now)?.start.dayMonth ?? "")")),
                    KPIItem(title: String(localized: "Compras"), value: (bills.count + expenses.count).formatted(),
                            foot: historyItems.first.map { String(localized: "Última el \($0.date.dayMonth)") }),
                ])
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) { openBillsTable; historyTable }.frame(minWidth: 520, maxWidth: .infinity)
                        sideColumn.frame(width: 300)
                    }
                    VStack(alignment: .leading, spacing: 16) { openBillsTable; historyTable; sideColumn }
                }
            }
            .padding(Metrics.gutter)
        }
    }

    /// Monograma de 48 pt, nombre de 20 bold y, debajo, condiciones y «1099-NEC» en azul si aplica.
    private var wideHeader: some View {
        HStack(spacing: 12) {
            Monogram(initials: Initials.from(vendor.name))
            VStack(alignment: .leading, spacing: 2) {
                Text(vendor.name).font(.title3.weight(.bold)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Text([category, terms, sinceText].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(Palette.ink2)
                    if vendor.is1099 {
                        Text("·").foregroundStyle(Palette.ink2)
                        Text("1099-NEC").fontWeight(.semibold).foregroundStyle(Palette.info)
                    }
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var openBillsTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Facturas por pagar").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TableCard {
                Text("Número").frame(width: 80, alignment: .leading)
                Text("Concepto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Vence").frame(width: 64, alignment: .leading)
                Text("Importe").frame(width: 96, alignment: .trailing)
                Text("Estado").frame(width: 120, alignment: .leading)
                Color.clear.frame(width: 140, height: 1)
            } rows: {
                ForEach(Array(openBills.enumerated()), id: \.element.id) { index, bill in
                    TableRow {
                        Text(bill.vendorNumber.isEmpty ? "—" : bill.vendorNumber).frame(width: 80, alignment: .leading)
                        Text(bill.concept.isEmpty ? "—" : bill.concept).foregroundStyle(Palette.ink2)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(bill.dueDate.dayMonth).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                            .frame(width: 64, alignment: .leading)
                        Text(bill.balanceDue.money).frame(width: 96, alignment: .trailing)
                        StatusChip(billWithAge: bill).frame(width: 120, alignment: .leading)
                        Button("Registrar pago") { paying = bill }
                            .buttonStyle(.bordered).controlSize(.small)
                            .lineLimit(1).fixedSize()
                            .accessibilityLabel("Registrar pago de \(bill.vendorNumber)")
                            .frame(width: 140, alignment: .trailing)
                    }
                    .zebra(index)
                    .contextMenu {
                        Button("Registrar pago…", systemImage: "checkmark.circle") { paying = bill }
                        BillScheduleMenuItems(bill: bill) { scheduling = bill }
                    }
                }
                if openBills.isEmpty {
                    Text("Nada por pagar").font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
        }
    }

    private var historyTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Historial").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            TableCard {
                Text("Fecha").frame(width: 64, alignment: .leading)
                Text("Concepto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cuenta").frame(width: 150, alignment: .leading)
                Text("Importe").frame(width: 96, alignment: .trailing)
            } rows: {
                ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                    Group {
                        switch item {
                        case .bill(let bill):
                            NavigationLink { BillDetailView(bill: bill) } label: { historyRow(item) }
                        case .expense(let expense):
                            NavigationLink { ExpenseDetailView(expense: expense) } label: { historyRow(item) }
                        }
                    }
                    .buttonStyle(.plain)
                    .zebra(index)
                }
                if historyItems.isEmpty {
                    Text("Sin compras todavía").font(.subheadline).foregroundStyle(Palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
        }
    }

    private func historyRow(_ item: Item) -> some View {
        TableRow {
            Text(item.date.dayMonth).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
            HStack(spacing: 4) {
                Text(title(of: item)).lineLimit(1)
                if hasReceipt(item) {
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(Palette.ink2).accessibilityLabel("Recibo adjunto")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(account(of: item)).foregroundStyle(Palette.ink2).lineLimit(1).frame(width: 150, alignment: .leading)
            Text(amount(of: item).money).frame(width: 96, alignment: .trailing)
        }
    }

    /// Columna del inspector: 1099 y contacto, con «Editar» y el pago de la próxima factura al pie.
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            form1099Card
            contactCard
            HStack(spacing: 8) {
                Button("Editar") { editing = true }.buttonStyle(.secondary)
                if let bill = openBills.first {
                    Button(bill.vendorNumber.isEmpty ? String(localized: "Registrar pago") : String(localized: "Pagar \(bill.vendorNumber)")) { paying = bill }
                        .buttonStyle(.primary)
                }
            }
            if let bill = openBills.first {
                Button(bill.isScheduled ? String(localized: "Cambiar pago programado…") : String(localized: "Programar pago…")) { scheduling = bill }
                    .buttonStyle(.secondary)
            }
        }
    }

    /// Solo lectura: se cambia desde «Editar».
    private var form1099Card: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: String(localized: "Formulario 1099")).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                DetailRow(String(localized: "Requiere 1099"), value: vendor.is1099 ? String(localized: "Sí") : String(localized: "No"))
                Divider()
                DetailRow(String(localized: "TIN"), value: vendor.tinLast4.isEmpty ? "—" : "•••–••–\(vendor.tinLast4)")
                if vendor.is1099 || vendor.w9Received {
                    Divider()
                    DetailRow(title: String(localized: "Formulario W-9")) {
                        HStack(spacing: 5) {
                            StatusDot(color: vendor.w9Received ? Palette.green : Palette.orange)
                            Text(w9Status).foregroundStyle(vendor.w9Received ? Palette.positive : Palette.warning)
                        }
                    }
                }
                if let attachment = vendor.w9Attachment {
                    Divider()
                    w9Link(attachment).buttonStyle(.borderless)
                }
                if vendor.is1099 {
                    Divider()
                    Text("Si le pagas $600 o más en el año, envíale el 1099-NEC antes del 31 de enero.")
                        .font(.footnote).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, Metrics.cardPadding)
            .card(padding: 0)
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: String(localized: "Contacto")).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                DetailRow(String(localized: "Correo"), value: vendor.email.isEmpty ? "—" : vendor.email.replacingOccurrences(of: "@", with: "@\u{200B}"))
                Divider()
                DetailRow(String(localized: "Teléfono"), value: vendor.phone.isEmpty ? "—" : vendor.phone)
                Divider()
                DetailRow(String(localized: "Categoría"), value: category ?? "—")
                Divider()
                DetailRow(String(localized: "Plazo de pago"), value: terms)
                Divider()
                DetailRow(String(localized: "Pago preferido"), value: preferredPayment ?? String(localized: "Sin preferencia"))
            }
            .padding(.horizontal, Metrics.cardPadding)
            .card(padding: 0)
        }
    }

    /// «desde 2024»: el primer movimiento o el alta del proveedor.
    private var sinceText: String {
        let since = ([vendor.createdAt] + bills.map(\.billDate) + expenses.map(\.date)).min() ?? vendor.createdAt
        return String(localized: "desde \(since.formatted(.appDateTime.year()))")
    }

    private var spentThisYear: Int64 {
        let calendar = Calendar.current
        return bills.filter { calendar.component(.year, from: $0.billDate) == year }.reduce(0) { $0 + $1.total }
            + expenses.filter { calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.total }
    }
}

/// Monograma de 48 pt de la cabecera de una ficha del Mac (canvas `MacProveedorFicha`).
private struct Monogram: View {
    let initials: String
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 48

    var body: some View {
        Text(initials)
            .font(.system(size: side * 0.38, weight: .semibold))
            .frame(width: side, height: side)
            .foregroundStyle(.white)
            .background(Palette.monogram, in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    /// Cebra de las tablas del Mac (canvas: filas alternas en `--row2`); en iPhone e iPad las filas van sin cebra.
    @ViewBuilder
    func zebra(_ index: Int) -> some View {
        #if os(macOS)
        background(index.isMultiple(of: 2) ? Color.clear : Palette.surface)
        #else
        self
        #endif
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
