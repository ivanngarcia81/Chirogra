import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// Por pagar del esquema 2 (docs/DATOS-V2.md §1, §6, §7): programar el pago de una factura, pagar varias en lote y
// las cuentas de pago con sus últimos 4 dígitos («Corriente ••4821»). Lo usan el iPhone, la columna maestro del iPad,
// la tabla del Mac, la ficha de la factura y la del proveedor.

// MARK: - Cuentas de pago

extension Account {
    /// Nombre de una cuenta de pago (canvas: «Corriente ••4821»): con los últimos 4 dígitos, el nombre enmascarado;
    /// sin ellos, el número y el nombre, como el resto de selectores de cuenta.
    var paymentLabel: String { last4.isEmpty ? displayName : maskedName }
}

/// Selector de la cuenta desde la que se paga (banco, caja o tarjeta) con su «••4821». Como `AccountPicker`, que vive
/// en el sistema de diseño y muestra el número y el nombre; candidato a subir allí.
struct PaymentAccountPicker: View {
    let title: String
    let accounts: [Account]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Elegir…").tag(UUID?.none)
            ForEach(accounts) { account in
                Text(account.paymentLabel).tag(Optional(account.id))
            }
        }
    }
}

extension PaymentMethod {
    /// Los que se ofrecen al pagar una factura de proveedor, en el orden del canvas.
    static let billMethods: [PaymentMethod] = [.bankTransfer, .check, .card, .cash]
}

extension Array where Element == Account {
    /// Cuentas desde las que se puede pagar: banco, caja y tarjeta (no «Fondos sin depositar»).
    var paymentAccounts: [Account] { filtered { $0.isMoneyAccount && $0 != .undepositedFunds } }

    func account(_ id: UUID?) -> Account? { id.flatMap { id in first { $0.id == id } } }
}

// MARK: - Estado de una factura por pagar

extension Bill {
    /// Pago programado vencido: la fecha ya pasó y la factura sigue abierta.
    var isScheduleLate: Bool {
        guard isScheduled, let date = scheduledPaymentDate else { return false }
        return date < Calendar.current.startOfDay(for: .now)
    }

    /// Lo que se ve de su pago en una fila (canvas `Gastos` · Por pagar: «Programado · Corriente ••4821»).
    func paymentSummary(accounts: [Account]) -> String? {
        guard isScheduled, let date = scheduledPaymentDate else { return nil }
        let account = accounts.account(scheduledPaymentAccountID ?? vendor?.preferredPaymentAccountID)
        let lead = String(localized: "Se paga el \(date.dayMonth)")
        return [lead, account?.paymentLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Programar pago

/// Programar (o cambiar) el pago de una factura por pagar (canvas `ProveedorFicha`: «Pagar desde», «Fecha de pago»,
/// «Programar pago»). No mueve dinero ni hace asiento: Chirogra lo recuerda y lo registra el día elegido (o se registra
/// a mano antes). Si ya está programada, «Cancelar pago programado» la desprograma.
struct SchedulePaymentView: View {
    let bill: Bill
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer
    @State private var errorMessage: String?
    @State private var loaded = false

    private var paymentAccounts: [Account] { accounts.paymentAccounts }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Proveedor", value: bill.vendor?.name ?? "—")
                if !bill.vendorNumber.isEmpty { LabeledContent("Número", value: bill.vendorNumber) }
                LabeledContent("Vence") {
                    Text(bill.dueDate.shortDate).foregroundStyle(bill.isOverdue ? Palette.negative : Palette.ink2)
                }
                LabeledContent("Saldo", value: bill.balanceDue.money).monospacedDigit()
            } header: {
                SectionLabel(text: String(localized: "Factura"))
            }
            Section {
                PaymentAccountPicker(title: String(localized: "Pagar desde"), accounts: paymentAccounts, selection: $accountID)
                DatePicker("Fecha de pago", selection: $date, displayedComponents: .date)
                Picker("Método", selection: $method) {
                    ForEach(PaymentMethod.billMethods, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                SectionLabel(text: String(localized: "Pago programado"))
            } footer: {
                Text("Chirogra te recuerda el pago; el dinero se mueve desde tu banco.")
            }
            if bill.isScheduled {
                Section {
                    Button(role: .destructive, action: unschedule) {
                        Label("Cancelar pago programado", systemImage: "xmark.circle").frame(minHeight: Metrics.target)
                    }
                    .foregroundStyle(Palette.negative)
                }
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle(bill.isScheduled ? "Cambiar pago programado" : "Programar pago")
        .inlineTitle()
        .discardableEditor(tracking: "\(date)|\(accountID?.uuidString ?? "")|\(method)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Programar", action: save).disabled(accountID == nil).headerButton()
            }
        }
        .onAppear(perform: load)
    }

    /// Lo programado si ya lo está; si no, el vencimiento (o mañana, si ya venció) y el pago preferido del proveedor.
    private func load() {
        guard !loaded else { return }
        loaded = true
        let today = Calendar.current.startOfDay(for: .now)
        date = bill.scheduledPaymentDate ?? max(bill.dueDate, today)
        accountID = bill.scheduledPaymentAccountID ?? bill.vendor?.preferredPaymentAccountID
            ?? paymentAccounts.first { $0.subtype == .bank }?.id
        method = bill.scheduledPaymentMethod ?? bill.vendor?.preferredPaymentMethod ?? .bankTransfer
    }

    private func save() {
        guard let account = accounts.account(accountID) else { return }
        do {
            try Bookkeeper(context: context).schedulePayment(for: bill, on: date, from: account, method: method)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unschedule() {
        do {
            try Bookkeeper(context: context).unschedulePayment(for: bill)
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pago en lote

/// Pagar varias facturas de una vez (canvas `MacPorPagar`: casillas y «Pagar $X»): el saldo completo de cada una,
/// un pago y un asiento por factura, todas con la misma fecha, cuenta y método. Todo o nada.
struct BatchPayView: View {
    let bills: [Bill]
    /// Se llama tras registrar los pagos (para vaciar la selección).
    var onPaid: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer
    @State private var reference = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    private var open: [Bill] { bills.filter(\.isOpen).sorted { $0.dueDate < $1.dueDate } }
    private var total: Int64 { open.reduce(0) { $0 + $1.balanceDue } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                ForEach(open) { bill in
                    LabeledContent {
                        Text(bill.balanceDue.money).monospacedDigit()
                    } label: {
                        Text(bill.vendor?.name ?? String(localized: "Sin proveedor"))
                        Text([bill.vendorNumber, bill.dueDate.dueLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
                LabeledContent {
                    Text(total.money).monospacedDigit().fontWeight(.semibold)
                } label: {
                    Text("Total").fontWeight(.semibold)
                }
            } header: {
                SectionLabel(text: String(localized: "\(open.count) facturas"))
            }
            Section {
                PaymentAccountPicker(title: String(localized: "Pagar desde"), accounts: accounts.paymentAccounts, selection: $accountID)
                DatePicker("Fecha de pago", selection: $date, displayedComponents: .date)
                Picker("Método", selection: $method) {
                    ForEach(PaymentMethod.billMethods, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Referencia (opcional)", text: $reference)
            } header: {
                SectionLabel(text: String(localized: "Pago"))
            } footer: {
                Text("Se registra un pago por factura, por su saldo completo. El dinero se mueve desde tu banco.")
            }
        }
        .formStyle(.grouped)
        .keyboardDoneButton()
        .screenBackground()
        .navigationTitle("Pago en lote")
        .inlineTitle()
        .discardableEditor(tracking: "\(date)|\(accountID?.uuidString ?? "")|\(method)|\(reference)", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Pagar", action: pay)
                    .disabled(accountID == nil || open.isEmpty)
                    .headerButton()
            }
        }
        .onAppear(perform: load)
    }

    /// La cuenta y el método preferidos si todas las facturas los comparten; si no, la primera cuenta de banco.
    private func load() {
        guard !loaded else { return }
        loaded = true
        let preferred = Set(open.map { $0.scheduledPaymentAccountID ?? $0.vendor?.preferredPaymentAccountID })
        let methods = Set(open.map { $0.scheduledPaymentMethod ?? $0.vendor?.preferredPaymentMethod })
        accountID = (preferred.count == 1 ? preferred.first ?? nil : nil) ?? accounts.paymentAccounts.first { $0.subtype == .bank }?.id
        method = (methods.count == 1 ? methods.first ?? nil : nil) ?? .bankTransfer
    }

    private func pay() {
        guard let account = accounts.account(accountID) else { return }
        do {
            try Bookkeeper(context: context).payBills(open, on: date, from: account, method: method, reference: reference)
            onPaid()
            unsavedChanges?.remove(editorToken); dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Barra del pago en lote al pie de una lista (canvas `MacPorPagar`: «3 facturas seleccionadas · Se pagarán desde…»
/// y «Pagar $X»), en vidrio. Sin nada marcado, explica qué hacer.
struct BatchPayBar: View {
    let selected: [Bill]
    let accounts: [Account]
    let clear: () -> Void
    /// «Seleccionar todas» (en el Mac, donde la cabecera de la tabla no lleva casilla).
    var selectAll: (() -> Void)? = nil
    let pay: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var total: Int64 { selected.reduce(0) { $0 + $1.balanceDue } }

    private var title: String {
        switch selected.count {
        case 0: String(localized: "Pago en lote")
        case 1: String(localized: "1 factura seleccionada")
        default: String(localized: "\(selected.count) facturas seleccionadas")
        }
    }

    private var subtitle: String {
        guard !selected.isEmpty else { return String(localized: "Marca las facturas que quieras pagar juntas") }
        let ids = Set(selected.map { $0.scheduledPaymentAccountID ?? $0.vendor?.preferredPaymentAccountID })
        if ids.count == 1, let account = accounts.account(ids.first ?? nil) {
            return String(localized: "Se pagarán desde \(account.paymentLabel)")
        }
        return String(localized: "Elige la cuenta al confirmar")
    }

    var body: some View {
        // Lo que quepa a lo ancho: todo en una fila (Mac, iPhone); en la columna estrecha del iPad o con letra
        // grande, el resumen arriba y los botones debajo; si ni así caben, solo «Pagar $X».
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    summary
                    Spacer(minLength: 8)
                    buttons(all: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) { summary; buttons(all: false) }
            VStack(alignment: .leading, spacing: 8) { summary; payButton }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func buttons(all: Bool) -> some View {
        HStack(spacing: 8) {
            if all, let selectAll {
                Button("Seleccionar todas", action: selectAll).buttonStyle(.secondary).fixedSize()
            }
            if !selected.isEmpty {
                Button("Deseleccionar", action: clear).buttonStyle(.secondary).fixedSize()
            }
            payButton
        }
    }

    private var payButton: some View {
        Button(selected.isEmpty ? String(localized: "Pagar") : String(localized: "Pagar \(total.money)"), action: pay)
            .buttonStyle(.primaryCompact)
            .disabled(selected.isEmpty)
            .fixedSize()
    }
}

/// Círculo de selección de una fila en el modo de selección (como Mail o Fotos): marcado en Tinta.
struct SelectionMark: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isOn ? Palette.brand : Palette.chevron)
            .accessibilityHidden(true)
    }
}

// MARK: - Acciones de una factura

/// «Programar pago» o «Cambiar pago programado» y «Cancelar pago programado» de una factura abierta, para menús y
/// acciones de deslizar. `schedule` abre `SchedulePaymentView`.
struct BillScheduleMenuItems: View {
    let bill: Bill
    let schedule: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        if bill.isOpen {
            Button(bill.isScheduled ? "Cambiar pago programado…" : "Programar pago…", systemImage: "calendar.badge.clock", action: schedule)
            if bill.isScheduled {
                Button("Cancelar pago programado", systemImage: "calendar.badge.minus", role: .destructive) {
                    try? Bookkeeper(context: context).unschedulePayment(for: bill)
                }
            }
        }
    }
}
