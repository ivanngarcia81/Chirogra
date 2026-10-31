import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Factura emitida / registrar pago (canvas: `FacturaDetalle`).
struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingPayment = false
    @State private var editingDraft = false
    @State private var confirmingVoid = false
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    var body: some View {
        List {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(invoice.customer?.name ?? "Sin cliente").font(.title2.weight(.semibold))
                        Spacer()
                        StatusChip(invoice: invoice, compact: false)
                    }
                    Text(invoice.status == .draft ? invoice.linesSubtotal.money : invoice.balanceDue.money)
                        .font(.amount(34))
                    Text(invoice.status == .draft ? "Subtotal del borrador" : "Saldo pendiente de \(invoice.total.money)")
                        .font(.subheadline).foregroundStyle(Palette.ink3)
                }
                .padding(.vertical, 6)
                LabeledContent("Número", value: invoice.number.isEmpty ? "Se asigna al emitir" : invoice.number)
                LabeledContent("Fecha", value: invoice.issueDate.shortDate)
                LabeledContent("Vence", value: invoice.dueDate.shortDate)
            }

            Section("Productos y servicios") {
                ForEach(invoice.sortedLines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.details.isEmpty ? "Sin descripción" : line.details)
                            Text("\(line.quantity.formatted()) × \(line.unitPrice.money)\(line.isTaxable ? " · gravable" : "")")
                                .font(.footnote).foregroundStyle(Palette.ink3)
                        }
                        Spacer()
                        Text(line.amount.money).monospacedDigit()
                    }
                }
            }

            if invoice.status != .draft {
                Section {
                    LabeledContent("Subtotal", value: invoice.subtotal.money)
                    ForEach(invoice.taxLines ?? []) { tax in
                        LabeledContent("\(tax.name) · \((Decimal(tax.rateMillionths) / 10_000).formatted())%", value: tax.amount.money)
                    }
                    LabeledContent("Total", value: invoice.total.money).fontWeight(.semibold)
                    LabeledContent("Cobrado", value: invoice.amountPaid.money)
                }
            }

            Section {
                switch invoice.status {
                case .draft:
                    Button("Emitir factura", action: issue).buttonStyle(.primary)
                    Button("Editar borrador") { editingDraft = true }.buttonStyle(.secondary)
                    Button("Eliminar borrador", role: .destructive, action: deleteDraft).buttonStyle(.destructive)
                case .sent, .partiallyPaid:
                    Button("Registrar pago") { showingPayment = true }.buttonStyle(.primary)
                    if invoice.amountPaid == 0 {
                        Button("Anular factura", role: .destructive) { confirmingVoid = true }.buttonStyle(.destructive)
                    }
                case .paid, .void:
                    EmptyView()
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .screenBackground()
        .navigationTitle(invoice.number.isEmpty ? "Borrador" : invoice.number)
        .inlineTitle()
        .sheet(isPresented: $editingDraft) {
            NavigationStack { InvoiceEditorView(editing: invoice) }
        }
        .sheet(isPresented: $showingPayment) {
            NavigationStack { RecordPaymentView(invoice: invoice) }
        }
        .confirmationDialog("¿Anular la factura?", isPresented: $confirmingVoid, titleVisibility: .visible) {
            Button("Anular", role: .destructive, action: void)
        } message: {
            Text("Se registrará un asiento de reversión. La factura queda en el historial como anulada.")
        }
    }

    private func issue() {
        do { try books.issue(invoice); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    private func void() {
        do { try books.void(invoice); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    private func deleteDraft() {
        context.delete(invoice)
        try? context.save()
        dismiss()
    }
}

struct RecordPaymentView: View {
    let invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var depositAccountID: UUID?
    @State private var method: PaymentMethod = .bankTransfer
    @State private var errorMessage: String?

    private var depositAccounts: [Account] { accounts.filtered { $0.isMoneyAccount && $0 != .creditCard } }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Factura", value: "\(invoice.number) · \(invoice.customer?.name ?? "")")
                LabeledContent("Saldo pendiente", value: invoice.balanceDue.money)
            }
            Section {
                MoneyField(title: "Importe", minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: "Depositar en", accounts: depositAccounts, selection: $depositAccountID)
                Picker("Método", selection: $method) {
                    ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Registrar pago")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Registrar", action: save).disabled(amount <= 0 || depositAccountID == nil)
            }
        }
        .onAppear {
            amount = invoice.balanceDue
            depositAccountID = depositAccountID ?? depositAccounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == depositAccountID }) else { return }
        do {
            try Bookkeeper(context: context).recordPayment(for: invoice, amount: amount, date: date, depositAccount: account, method: method)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension PaymentMethod {
    var title: String {
        switch self {
        case .cash: "Efectivo"
        case .check: "Cheque"
        case .bankTransfer: "Transferencia"
        case .card: "Tarjeta"
        case .other: "Otro"
        }
    }
}
