#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Facturas como tabla + inspector (canvas `MacVentas`, `MacVentasOscuro`). Arriba el segmentado de estados con su
/// cuenta, las cajas Por cobrar · Vencido · Cobrado en el mes · Borradores y la tabla Número · Cliente · Emitida ·
/// Vence · Estado · Importe. El inspector muestra la factura elegida (Detalles, Importes) con «Registrar pago…»,
/// «Enviar recordatorio», «Abrir factura» y «Ver cliente». Doble clic abre la factura completa (`InvoiceDetailView`).
struct InvoiceTablePage: View {
    static let isReady = true
    #if DEBUG
    @MainActor private static var qaIssued = false
    #endif
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var context
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @Query private var payments: [PaymentReceived]
    @State private var filter: InvoiceListView.Filter = .all
    @State private var query = ""
    @State private var creating = false
    @State private var paying: Invoice?
    @State private var sending: Invoice?
    @State private var reminding: Invoice?
    @State private var editing: Invoice?
    @State private var openedInvoice: Invoice?
    @State private var openedCustomer: Customer?
    @State private var errorMessage: String?
    /// Recién emitida desde el inspector: «Factura F-1001 emitida · Enviar a…».
    @State private var justIssued: Invoice?

    private var filtered: [Invoice] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return invoices.filter { invoice in
            filter.matches(invoice) && (text.isEmpty
                || invoice.number.localizedStandardContains(text)
                || invoice.customerName.localizedStandardContains(text)
                || invoice.tableAmount.money.contains(text))
        }
    }

    private var footer: String {
        filtered.count == invoices.count ? String(localized: "\(invoices.count) facturas")
            : String(localized: "\(filtered.count) de \(invoices.count) facturas")
    }

    private var kpis: [KPIItem] {
        let open = invoices.filter(\.isOpen)
        let overdue = open.filter { $0.daysOverdue() != nil }
        let month = DateInterval.month(containing: .now)
        let collected = payments.filter { month.contains($0.date) }.reduce(0) { $0 + $1.amount }
        let monthName = Date.now.formatted(.appDateTime.month(.wide))
        return [
            KPIItem(title: String(localized: "Por cobrar"), value: open.reduce(0) { $0 + $1.balanceDue }.money),
            KPIItem(title: String(localized: "Vencido"), value: overdue.reduce(0) { $0 + $1.balanceDue }.money,
                    foot: overdue.isEmpty ? nil : String(localized: "\(overdue.count) facturas"), footColor: Palette.negative),
            KPIItem(title: String(localized: "Cobrado en \(monthName)"), value: collected.money),
            KPIItem(title: String(localized: "Borradores"), value: "\(invoices.filter { $0.status == .draft }.count)"),
        ]
    }

    var body: some View {
        MacTablePage(
            title: String(localized: "Facturas"),
            subtitle: String(localized: "Ventas · \(invoices.count) facturas"),
            rows: filtered, footer: footer,
            query: $query, searchPrompt: Text("Cliente, número o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\Invoice.tableNumber, order: .reverse)],
            kpis: kpis,
            addTitle: String(localized: "Nueva factura"), onAdd: { creating = true },
            onOpen: { openedInvoice = $0 },
            empty: invoices.isEmpty
                ? MacTableEmpty(guide: .invoices, action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ninguna factura coincide con la búsqueda o el filtro."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { invoice in
                guard let invoice else { return String(localized: "Factura") }
                return invoice.number.isEmpty ? String(localized: "Borrador") : String(localized: "Factura \(invoice.number)")
            },
            inspectorPlaceholder: String(localized: "Selecciona una factura para ver sus detalles.")
        ) {
            TableColumn("Número", value: \.tableNumber) { invoice in
                MacCellText(text: invoice.number.isEmpty ? "—" : invoice.number)
            }
            .width(min: 56, ideal: 64, max: 110)
            TableColumn("Cliente", value: \.customerName) { invoice in
                Text(invoice.customer?.name ?? String(localized: "Sin cliente")).lineLimit(1)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Emitida", value: \.issueDate) { invoice in
                MacCellText(text: invoice.issueDate.dayMonth)
            }
            .width(min: 52, ideal: 60, max: 100)
            TableColumn("Vence", value: \.dueDate) { invoice in
                MacCellText(text: invoice.dueDate.dayMonth, color: invoice.daysOverdue() != nil ? Palette.negative : Palette.ink2)
            }
            .width(min: 52, ideal: 60, max: 100)
            TableColumn("Estado", value: \.statusRank) { invoice in
                MacCellStatus(chip: invoice.tableStatus)
            }
            .width(min: 100, ideal: 130, max: 220)
            TableColumn("Importe", value: \.tableAmount) { invoice in
                Text(invoice.tableAmount.money).monospacedDigit()
            }
            .width(min: 76, ideal: 90, max: 140)
            .alignment(.trailing)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar por estado"), options: InvoiceListView.Filter.allCases,
                           selection: $filter, label: \.localizedTitle) { option in
                invoices.filter(option.matches).count
            }
        } inspector: { invoice in
            InvoiceInspector(invoice: invoice, errorMessage: errorMessage) { openedCustomer = $0 }
        } actions: { invoice in
            actions(for: invoice)
        }
        .onChange(of: selection) { errorMessage = nil }
        .sheet(isPresented: $creating) { NavigationStack { InvoiceEditorView() }.editorSheetSizing() }
        .sheet(item: $paying) { invoice in NavigationStack { InvoicePaymentSheet(invoice: invoice) }.editorSheetSizing() }
        .sheet(item: $sending) { invoice in NavigationStack { SendDocumentView(source: .invoice(invoice)) }.editorSheetSizing() }
        .sheet(item: $reminding) { invoice in
            NavigationStack { SendDocumentView(source: .invoice(invoice), purpose: .reminder) }.editorSheetSizing()
        }
        .sheet(item: $editing) { invoice in NavigationStack { InvoiceEditorView(editing: invoice) }.editorSheetSizing() }
        .offerToSendIssued($justIssued)
        .navigationDestination(item: $openedInvoice) { InvoiceDetailView(invoice: $0) }
        .navigationDestination(item: $openedCustomer) { CustomerDetailView(customer: $0) }
        #if DEBUG
        // `-qa.pago 1` abre «Registrar pago…» y `-qa.abrir 1` la factura completa de la fila elegida con `-qa.fila`.
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nuevo") { creating = true; return }
            guard let id = selection, let invoice = invoices.first(where: { $0.id == id }) else { return }
            if UserDefaults.standard.bool(forKey: "qa.pago"), invoice.isOpen { paying = invoice }
            if UserDefaults.standard.bool(forKey: "qa.abrir") { openedInvoice = invoice }
            // `-qa.enviar 1` abre «Enviar factura…» y `-qa.recordar 1` «Enviar recordatorio» de la fila elegida.
            if UserDefaults.standard.bool(forKey: "qa.enviar"), invoice.status != .draft { sending = invoice }
            if UserDefaults.standard.bool(forKey: "qa.recordar"), invoice.isOpen { reminding = invoice }
            // `-qa.editar 1` abre el editor de la fila elegida (borrador o emitida sin cobros) y `-qa.emitir 1` emite una
            // copia en borrador de la fila elegida, para ver «Factura … emitida · Enviar a…» sin el ratón.
            if UserDefaults.standard.bool(forKey: "qa.editar"),
               invoice.status == .draft || Bookkeeper(context: context).canEditIssued(invoice) { editing = invoice }
            if UserDefaults.standard.bool(forKey: "qa.emitir"), !Self.qaIssued {
                Self.qaIssued = true   // la tarea puede correr dos veces al montar la tabla
                let books = Bookkeeper(context: context)
                let copy = try? books.saveDraft(InvoiceDraftInput(
                    customer: invoice.customer, issueDate: .now, dueDate: invoice.dueDate, taxGroupID: invoice.taxGroupID,
                    lines: invoice.sortedLines.map {
                        .init(details: $0.details, quantity: $0.quantity, unitPrice: $0.unitPrice, isTaxable: $0.isTaxable,
                              incomeAccountID: $0.incomeAccountID)
                    }))
                if let copy { issue(copy) }
            }
        }
        #endif
    }

    /// Botones al pie del inspector: la acción principal del estado (emitir o cobrar) y, debajo, las secundarias.
    @ViewBuilder
    private func actions(for invoice: Invoice) -> some View {
        if invoice.status == .draft {
            Button("Emitir factura") { issue(invoice) }.buttonStyle(.primary)
            Button("Editar borrador") { editing = invoice }.buttonStyle(.secondary)
        } else if invoice.isOpen {
            Button("Registrar pago…") { paying = invoice }.buttonStyle(.primary)
            if invoice.lastSentDate == nil {
                Button("Enviar factura…") { sending = invoice }.buttonStyle(.secondary)
            }
            // Canvas `MacClienteFicha`: «Recordatorio enviado» cuando ya se mandó hoy (se puede mandar otro).
            Button(invoice.lastReminderDate.map(Calendar.current.isDateInToday) == true
                   ? String(localized: "Recordatorio enviado hoy") : String(localized: "Enviar recordatorio…")) { reminding = invoice }
                .buttonStyle(.secondary)
            // Sin cobros ni créditos se corrige (reversión + asiento nuevo, mismo número); con ellos, nota de crédito.
            if Bookkeeper(context: context).canEditIssued(invoice) {
                Button("Editar factura…") { editing = invoice }.buttonStyle(.secondary)
            }
        } else if invoice.status != .void {
            Button("Enviar factura…") { sending = invoice }.buttonStyle(.secondary)
        }
        HStack(spacing: 8) {
            Button("Abrir factura") { openedInvoice = invoice }.buttonStyle(.secondary)
            if let customer = invoice.customer {
                Button("Ver cliente") { openedCustomer = customer }.buttonStyle(.secondary)
            }
        }
    }

    private func issue(_ invoice: Invoice) {
        do {
            try Bookkeeper(context: context).issue(invoice)
            errorMessage = nil
            justIssued = invoice
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Inspector de la factura (canvas `MacVentas`): cliente, importe de 24 y estado; Detalles (Número, Cliente, Emitida,
/// Vence) e Importes (Importe, Cobrado, Saldo pendiente).
private struct InvoiceInspector: View {
    let invoice: Invoice
    let errorMessage: String?
    let openCustomer: (Customer) -> Void

    var body: some View {
        if let errorMessage { ErrorBanner(message: errorMessage) }
        MacInspectorSummary(title: invoice.customer?.name ?? String(localized: "Sin cliente"), amount: invoice.tableAmount.money) {
            invoice.tableStatus
        }
        MacInspectorSection(title: String(localized: "Detalles")) {
            MacInspectorRow(String(localized: "Número"), value: invoice.number.isEmpty ? "—" : invoice.number)
            MacInspectorRow(label: String(localized: "Cliente")) {
                if let customer = invoice.customer {
                    Button(customer.name) { openCustomer(customer) }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                } else {
                    Text("Sin cliente").foregroundStyle(Palette.ink2)
                }
            }
            MacInspectorRow(String(localized: "Emitida"), value: invoice.issueDate.shortDate)
            MacInspectorRow(String(localized: "Vence"), value: invoice.dueDate.shortDate,
                            color: invoice.daysOverdue() != nil ? Palette.negative : Palette.ink)
            if let sent = invoice.lastSentDate {
                MacInspectorRow(String(localized: "Enviada"), value: sent.shortDate)
            }
            if let reminder = invoice.lastReminderDate {
                MacInspectorRow(String(localized: "Recordatorio"),
                                value: Calendar.current.isDateInToday(reminder) ? String(localized: "Enviado hoy") : reminder.shortDate,
                                color: Calendar.current.isDateInToday(reminder) ? Palette.positive : Palette.ink)
            }
        }
        MacInspectorSection(title: String(localized: "Importes")) {
            MacInspectorRow(String(localized: "Importe"), value: invoice.tableAmount.money)
            if invoice.status != .draft {
                MacInspectorRow(String(localized: "Cobrado"), value: invoice.amountPaid.money)
                if invoice.creditsApplied > 0 {
                    MacInspectorRow(String(localized: "Notas de crédito"), value: "−\(invoice.creditsApplied.money)")
                }
                MacInspectorRow(String(localized: "Saldo pendiente"), value: invoice.balanceDue.money, bold: true)
            }
        }
    }
}

/// «Registrar pago…» del inspector: hoja del Mac con Total · Parcial, monto, método, cuenta de depósito y fecha (lo
/// mismo que el grupo «Registrar pago» de `InvoiceDetailView`), con «Cancelar» y la acción por defecto.
struct InvoicePaymentSheet: View {
    let invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var editorToken = EditorToken()
    @State private var mode: InvoiceDetailView.PaymentMode = .total
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var depositAccountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer
    @State private var errorMessage: String?

    private var depositAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .creditCard } }
    private var amountToRecord: Int64 { mode == .total ? invoice.balanceDue : amount }
    private var canRecord: Bool { amountToRecord > 0 && amountToRecord <= invoice.balanceDue && depositAccountID != nil }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Cliente", value: invoice.customer?.name ?? "—")
                LabeledContent("Factura", value: invoice.number)
                LabeledContent("Saldo pendiente", value: invoice.balanceDue.money).monospacedDigit()
            }
            Section {
                Picker("Tipo de pago", selection: $mode) {
                    ForEach(InvoiceDetailView.PaymentMode.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Monto") {
                    if mode == .partial {
                        MoneyField(title: String(localized: "Monto"), minorUnits: $amount)
                            .multilineTextAlignment(.trailing).labelsHidden()
                    } else {
                        Text(invoice.balanceDue.money).monospacedDigit()
                    }
                }
                Picker("Método", selection: $method) {
                    ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                AccountPicker(title: String(localized: "Depositar en"), accounts: depositAccounts, selection: $depositAccountID)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            } footer: {
                if mode == .partial && amount > invoice.balanceDue {
                    Text("El monto supera el saldo de \(invoice.balanceDue.money).").foregroundStyle(Palette.negative)
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Registrar pago")
        .discardableEditor(tracking: "\(mode)|\(amount)|\(date)|\(depositAccountID?.uuidString ?? "")|\(method)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Registrar \(amountToRecord.money)", action: record).disabled(!canRecord).headerButton()
            }
        }
        // Al pasar a «Parcial» el monto se vacía para escribir el que se cobra.
        .onChange(of: mode) { _, mode in amount = mode == .partial ? 0 : invoice.balanceDue }
        .onAppear {
            amount = invoice.balanceDue
            depositAccountID = depositAccountID ?? depositAccounts.first { $0.subtype == .bank }?.id
        }
        .frame(minWidth: 420, minHeight: 360)
        #if DEBUG
        // `-qa.registrar 1` (con `-qa.pago 1`): registra el pago solo, para comprobar el camino sin el ratón.
        .task {
            guard UserDefaults.standard.bool(forKey: "qa.registrar") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            record()
        }
        #endif
    }

    private func record() {
        guard let account = accounts.first(where: { $0.id == depositAccountID }) else { return }
        do {
            try Bookkeeper(context: context).recordPayment(for: invoice, amount: amountToRecord, date: date, depositAccount: account, method: method)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Invoice {
    /// Claves de orden y valores de la tabla del Mac.
    nonisolated var customerName: String { customer?.name ?? "" }
    /// Número para ordenar: los borradores (sin número) van arriba en orden descendente, como la F-1048 del canvas.
    nonisolated var tableNumber: String { number.isEmpty ? "~" : number }
    /// Importe de la fila: el total, o lo que suman las líneas si es un borrador.
    nonisolated var tableAmount: Int64 { status == .draft ? draftAmount : total }

    /// Orden de los estados al ordenar por «Estado»: Borrador, Enviada, Pago parcial, Vencida, Pagada, Anulada.
    nonisolated var statusRank: Int {
        if daysOverdue() != nil { return 3 }
        return switch status {
        case .draft: 0
        case .sent: 1
        case .partiallyPaid: 2
        case .paid: 4
        case .void: 5
        }
    }

    /// Estado de la fila (canvas `MacVentas`): el de siempre, y el pago parcial con lo que falta («Parcial · $850 pend.»).
    var tableStatus: StatusChip {
        if status == .partiallyPaid && daysOverdue() == nil {
            return StatusChip(text: String(localized: "Parcial · \(balanceDue.money) pend."), foreground: Palette.warning,
                              background: .clear, compact: true, dot: Palette.orange)
        }
        return StatusChip(invoice: self)
    }
}
#endif
