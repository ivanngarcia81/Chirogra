#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Facturas por pagar como tabla + inspector (canvas `MacPorPagar`). Arriba las cajas Total por pagar · Vencido ·
/// Vence esta semana · Pagos programados y el segmentado Por pagar · Vencidas · Esta semana · Programadas · Pagadas con
/// su cuenta; la tabla con la casilla del pago en lote, Vence · Proveedor · Número · Estado · Importe y «Registrar pago»
/// en cada factura abierta; al pie, la barra del pago en lote («Pagar $X»). El inspector muestra la elegida (Detalles,
/// Pago, Importes, Pagos) con «Registrar pago…» (`PayBillView`), «Programar pago…», «Ver proveedor» y «Abrir la factura».
/// Doble clic abre la factura completa (`BillDetailView`).
struct BillTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var filter: BillFilter = .open
    @State private var query = ""
    @State private var creating = false
    @State private var paying: Bill?
    /// La que se está pagando: al cerrar la hoja, si quedó pagada sigue en la tabla («Pagada») hasta cambiar de filtro,
    /// como en el canvas, en vez de desaparecer de golpe con el inspector.
    @State private var payingBill: Bill?
    @State private var paidHere: Set<UUID> = []
    @State private var openedBill: Bill?
    @State private var openedVendor: Vendor?
    @State private var scheduling: Bill?
    /// Facturas marcadas para el pago en lote (casillas de la tabla).
    @State private var checked: Set<UUID> = []
    @State private var payingBatch = false
    @Environment(\.modelContext) private var context

    private var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now }

    private func inFilter(_ bill: Bill, _ filter: BillFilter) -> Bool {
        switch filter {
        case .open: bill.isOpen
        case .overdue: bill.isOverdue
        case .thisWeek: bill.isOpen && !bill.isOverdue && bill.dueDate < weekEnd
        case .scheduled: bill.isScheduled
        case .paid: bill.status == .paid
        }
    }

    private var checkedBills: [Bill] { bills.filter { checked.contains($0.id) && $0.isOpen } }

    private func isChecked(_ bill: Bill) -> Binding<Bool> {
        Binding(get: { checked.contains(bill.id) }, set: { on in
            if on { checked.insert(bill.id) } else { checked.remove(bill.id) }
        })
    }

    private var filtered: [Bill] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return bills.filter { bill in
            (inFilter(bill, filter) || paidHere.contains(bill.id) || bill.id == payingBill?.id) && (text.isEmpty
                || bill.payableVendorName.localizedStandardContains(text)
                || bill.vendorNumber.localizedStandardContains(text)
                || bill.concept.localizedStandardContains(text)
                || bill.payableAmount.money.contains(text))
        }
    }

    private var footer: String {
        filtered.count == bills.count ? String(localized: "\(bills.count) facturas de proveedor")
            : String(localized: "\(filtered.count) de \(bills.count) facturas de proveedor")
    }

    private var kpis: [KPIItem] {
        let open = bills.filter(\.isOpen)
        let overdue = open.filter(\.isOverdue)
        let week = open.filter { !$0.isOverdue && $0.dueDate < weekEnd }
        let scheduled = open.filter(\.isScheduled).sorted { ($0.scheduledPaymentDate ?? .distantFuture) < ($1.scheduledPaymentDate ?? .distantFuture) }
        return [
            KPIItem(title: String(localized: "Total por pagar"), value: open.reduce(0) { $0 + $1.balanceDue }.money),
            KPIItem(title: String(localized: "Vencido"), value: overdue.reduce(0) { $0 + $1.balanceDue }.money,
                    foot: overdue.isEmpty ? nil : String(localized: "\(overdue.count) vencidas"), footColor: Palette.negative),
            KPIItem(title: String(localized: "Vence esta semana"), value: week.reduce(0) { $0 + $1.balanceDue }.money),
            KPIItem(title: String(localized: "Pagos programados"), value: scheduled.reduce(0) { $0 + $1.balanceDue }.money,
                    foot: scheduled.first?.scheduledPaymentDate.map { String(localized: "Próximo el \($0.dayMonth)") }),
        ]
    }

    private var empty: MacTableEmpty {
        if bills.isEmpty {
            return MacTableEmpty(systemImage: "doc.text", title: String(localized: "Sin facturas por pagar"),
                                 message: String(localized: "Registra las facturas de tus proveedores para saber qué vence y cuándo."),
                                 actionTitle: String(localized: "Nueva factura de proveedor"), action: { creating = true })
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty && filter == .open {
            return MacTableEmpty(systemImage: "checkmark.circle", title: String(localized: "Nada por pagar"),
                                 message: String(localized: "Todas las facturas de tus proveedores están pagadas."),
                                 actionTitle: String(localized: "Ver pagadas"), action: { filter = .paid })
        }
        return MacTableEmpty(title: String(localized: "Sin resultados"),
                             message: String(localized: "Ninguna factura coincide con la búsqueda o el filtro."),
                             actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .open })
    }

    var body: some View {
        let open = bills.filter(\.isOpen)
        MacTablePage(
            title: String(localized: "Facturas por pagar"),
            subtitle: String(localized: "\(open.count) abiertas · \(open.reduce(0) { $0 + $1.balanceDue }.money)"),
            rows: filtered, footer: footer,
            query: $query, searchPrompt: Text("Proveedor, número o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\Bill.dueDate)],
            kpis: kpis,
            addTitle: String(localized: "Nueva factura de proveedor"), onAdd: { creating = true },
            onOpen: { openedBill = $0 },
            empty: empty,
            inspectorTitle: { bill in
                guard let bill, !bill.vendorNumber.isEmpty else { return String(localized: "Factura por pagar") }
                return String(localized: "Factura de proveedor \(bill.vendorNumber)")
            },
            inspectorPlaceholder: String(localized: "Selecciona una factura para ver sus detalles.")
        ) {
            TableColumn(Text(verbatim: "")) { bill in
                if bill.isOpen {
                    Toggle(isOn: isChecked(bill)) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel(bill.vendorNumber.isEmpty ? String(localized: "Incluir en el pago en lote")
                                                                       : String(localized: "Incluir \(bill.vendorNumber) en el pago en lote"))
                        .help("Incluir en el pago en lote")
                }
            }
            .width(min: 20, ideal: 22, max: 26)
            TableColumn("Vence", value: \.dueDate) { bill in
                MacCellText(text: bill.dueDate.dayMonth, color: bill.isOverdue ? Palette.negative : Palette.ink2)
            }
            .width(min: 52, ideal: 56, max: 100)
            TableColumn("Proveedor", value: \.payableVendorName) { bill in
                Text(bill.vendor?.name ?? String(localized: "Sin proveedor")).lineLimit(1)
            }
            .width(min: 96, ideal: 120)
            TableColumn("Número", value: \.vendorNumber) { bill in
                MacCellText(text: bill.vendorNumber.isEmpty ? "—" : bill.vendorNumber).lineLimit(1)
            }
            .width(min: 56, ideal: 60, max: 120)
            TableColumn("Estado", value: \.payableStatusRank) { bill in
                MacCellStatus(chip: StatusChip(billWithAge: bill))
            }
            .width(min: 96, ideal: 122, max: 200)
            TableColumn("Importe", value: \.payableAmount) { bill in
                Text(bill.payableAmount.money).monospacedDigit()
            }
            .width(min: 72, ideal: 76, max: 140)
            .alignment(.trailing)
            TableColumn("Acción") { bill in
                if bill.isOpen {
                    Button("Registrar pago") { pay(bill) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel(bill.vendorNumber.isEmpty ? String(localized: "Registrar pago")
                                                                       : String(localized: "Registrar pago de \(bill.vendorNumber)"))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            // El botón pequeño mide ~110 pt («Registrar pago», «Record payment»); con 110 se cortaba (3-nov). Los ideales
            // de todas las columnas caben en lo que deja el inspector en una ventana de 1280 pt: si no, la tabla se
            // desplazaba de lado y esta columna quedaba fuera.
            .width(min: 120, ideal: 124, max: 160)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar por estado"), options: BillFilter.allCases,
                           selection: $filter, label: \.localizedTitle) { option in
                bills.filter { inFilter($0, option) }.count
            }
            // Pago en lote (canvas `MacPorPagar`: al pie; aquí arriba de la tabla para no cruzar el inspector).
            if !checkedBills.isEmpty {
                BatchPayBar(selected: checkedBills, accounts: accounts, clear: { checked = [] },
                            selectAll: { checked.formUnion(filtered.filter(\.isOpen).map(\.id)) }) { payingBatch = true }
                    .padding(.horizontal, -12)
                    .padding(.bottom, -8)
            }
        } inspector: { bill in
            BillInspector(bill: bill, accounts: accounts, inBatch: checked.contains(bill.id)) { openedVendor = $0 }
        } actions: { bill in
            if bill.isOpen {
                Button("Registrar pago…") { pay(bill) }.buttonStyle(.primary)
                HStack(spacing: 8) {
                    Button(bill.isScheduled ? "Cambiar pago…" : "Programar pago…") { scheduling = bill }.buttonStyle(.secondary)
                    if bill.isScheduled {
                        Button("Desprogramar") { unschedule(bill) }.buttonStyle(.destructive)
                    }
                }
            }
            HStack(spacing: 8) {
                if let vendor = bill.vendor {
                    Button("Ver proveedor") { openedVendor = vendor }.buttonStyle(.secondary)
                }
                Button("Abrir la factura") { openedBill = bill }.buttonStyle(.secondary)
            }
        }
        .onChange(of: filter) { paidHere = [] }
        .sheet(item: $scheduling) { bill in NavigationStack { SchedulePaymentView(bill: bill) }.editorSheetSizing() }
        .sheet(isPresented: $payingBatch) {
            NavigationStack {
                BatchPayView(bills: checkedBills) {
                    paidHere.formUnion(checked)
                    checked = []
                }
            }
            .editorSheetSizing()
        }
        .task { RecurringAutomation.run(in: context) }
        .sheet(isPresented: $creating) { NavigationStack { BillEditorView() }.editorSheetSizing() }
        .sheet(item: $paying, onDismiss: {
            if let bill = payingBill, bill.status == .paid { paidHere.insert(bill.id) }
            payingBill = nil
        }) { bill in
            NavigationStack { PayBillView(bill: bill) }.editorSheetSizing()
        }
        .navigationDestination(item: $openedBill) { BillDetailView(bill: $0) }
        .navigationDestination(item: $openedVendor) { VendorDetailView(vendor: $0) }
        #if DEBUG
        // `-qa.pago 1` abre «Registrar pago…» y `-qa.abrir 1` la factura completa de la fila elegida con `-qa.fila`.
        .task {
            try? await Task.sleep(for: .seconds(1))
            guard let id = selection, let bill = bills.first(where: { $0.id == id }) else { return }
            if UserDefaults.standard.bool(forKey: "qa.pago"), bill.isOpen { pay(bill) }
            if UserDefaults.standard.bool(forKey: "qa.abrir") { openedBill = bill }
            if UserDefaults.standard.bool(forKey: "qa.programar"), bill.isOpen { scheduling = bill }
            // `-qa.lote 1` marca todas las abiertas que se ven; `-qa.lote 2` además abre «Pago en lote».
            let lote = UserDefaults.standard.integer(forKey: "qa.lote")
            if lote > 0 { checked = Set(filtered.filter(\.isOpen).map(\.id)) }
            if lote > 1 { payingBatch = true }
        }
        #endif
    }

    /// Abre `PayBillView` (la misma hoja de la ficha y del iPhone) y recuerda la factura para saber si quedó pagada.
    private func pay(_ bill: Bill) {
        payingBill = bill
        paying = bill
    }

    private func unschedule(_ bill: Bill) {
        try? Bookkeeper(context: context).unschedulePayment(for: bill)
    }
}

/// Inspector de la factura por pagar (canvas `MacPorPagar`): proveedor, importe de 24 y estado; Detalles (Proveedor,
/// Número, Fecha, Vence, Categoría, Concepto), Importes (Total, Pagado, Saldo pendiente) y los pagos registrados con su
/// cuenta y método.
private struct BillInspector: View {
    let bill: Bill
    let accounts: [Account]
    let inBatch: Bool
    let openVendor: (Vendor) -> Void

    private func accountName(_ id: UUID?) -> String? { accounts.account(id)?.paymentLabel }

    /// «Cargo automático», «Programado · 7 nov» o «Manual» (canvas `MacPorPagar`, «Método»).
    private var how: String {
        if bill.autoPay { return String(localized: "Cargo automático") }
        if let date = bill.scheduledPaymentDate, bill.isScheduled { return String(localized: "Programado · \(date.dayMonth)") }
        return String(localized: "Manual")
    }

    /// La cuenta de gasto de las líneas, o «Varias» si son distintas.
    private var category: String {
        let names = Set(bill.sortedLines.compactMap { accountName($0.accountID) })
        if names.count > 1 { return String(localized: "Varias") }
        return names.first ?? "—"
    }

    var body: some View {
        MacInspectorSummary(title: bill.vendor?.name ?? String(localized: "Sin proveedor"), amount: bill.payableAmount.money) {
            StatusChip(billWithAge: bill)
        }
        MacInspectorSection(title: String(localized: "Detalles")) {
            MacInspectorRow(label: String(localized: "Proveedor")) {
                if let vendor = bill.vendor {
                    Button(vendor.name) { openVendor(vendor) }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.brand)
                        .lineLimit(1)
                } else {
                    Text("Sin proveedor").foregroundStyle(Palette.ink2)
                }
            }
            MacInspectorRow(String(localized: "Número"), value: bill.vendorNumber.isEmpty ? "—" : bill.vendorNumber)
            MacInspectorRow(String(localized: "Fecha"), value: bill.billDate.shortDate)
            MacInspectorRow(String(localized: "Vence"), value: bill.dueDate.shortDate,
                            color: bill.isOverdue ? Palette.negative : Palette.ink)
            MacInspectorRow(String(localized: "Categoría"), value: category)
            if !bill.concept.isEmpty {
                MacInspectorRow(String(localized: "Concepto"), value: bill.concept)
            }
        }
        if bill.isOpen {
            MacInspectorSection(title: String(localized: "Pago")) {
                MacInspectorRow(String(localized: "Cuenta"),
                                value: accountName(bill.scheduledPaymentAccountID ?? bill.vendor?.preferredPaymentAccountID) ?? "—")
                MacInspectorRow(String(localized: "Método"),
                                value: (bill.scheduledPaymentMethod ?? bill.vendor?.preferredPaymentMethod)?.title ?? "—")
                MacInspectorRow(String(localized: "Pago"), value: how)
                MacInspectorRow(String(localized: "En pago en lote"), value: inBatch ? String(localized: "Sí") : String(localized: "No"))
            }
        }
        MacInspectorSection(title: String(localized: "Importes")) {
            MacInspectorRow(String(localized: "Total"), value: bill.total.money)
            MacInspectorRow(String(localized: "Pagado"), value: bill.amountPaid.money)
            MacInspectorRow(String(localized: "Saldo pendiente"), value: bill.balanceDue.money, bold: true)
        }
        let payments = (bill.payments ?? []).sorted { $0.date > $1.date }
        if !payments.isEmpty {
            MacInspectorSection(title: String(localized: "Pagos")) {
                ForEach(payments) { payment in
                    MacInspectorRow(label: payment.date.shortDate) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(payment.amount.money).foregroundStyle(Palette.ink)
                            Text(paymentDetail(payment)).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    /// «Banco · Transferencia»: la cuenta desde la que se pagó y el método.
    private func paymentDetail(_ payment: BillPayment) -> String {
        let method = PaymentMethod(rawValue: payment.methodRaw)?.title
        return [accountName(payment.paymentAccountID), method].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Bill {
    /// Claves de orden y valores de la tabla del Mac (`nonisolated` para `KeyPathComparator`).
    nonisolated var payableVendorName: String { vendor?.name ?? "" }
    /// Importe de la fila: el saldo si sigue abierta; si no, el total.
    nonisolated var payableAmount: Int64 { isOpen ? balanceDue : total }

    /// Orden de los estados al ordenar por «Estado»: Vencida, Pago parcial, Por pagar, Pagada, Anulada.
    nonisolated var payableStatusRank: Int {
        if isOpen && scheduledPaymentDate != nil { return 2 }
        if isOpen && dueDate < Calendar.current.startOfDay(for: .now) { return 0 }
        return switch status {
        case .partiallyPaid: 1
        case .open: 2
        case .paid: 3
        case .void: 4
        }
    }
}
#endif
