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
    @State private var showingCreditNote = false
    @State private var showingPreview = false
    @Query private var companies: [Company]
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
                    Text(invoice.status == .draft ? invoice.draftAmount.money : invoice.balanceDue.money)
                        .font(.amount(34))
                    Text(invoice.status == .draft ? "Borrador: líneas menos descuento, sin impuesto" : "Saldo pendiente de \(invoice.total.money)")
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
                    if invoice.discount > 0 { LabeledContent("Descuento", value: "−\(invoice.discount.money)") }
                    ForEach(invoice.taxLines ?? []) { tax in
                        LabeledContent("\(tax.name) · \((Decimal(tax.rateMillionths) / 10_000).formatted())%", value: tax.amount.money)
                    }
                    LabeledContent("Total", value: invoice.total.money).fontWeight(.semibold)
                    LabeledContent("Cobrado", value: invoice.amountPaid.money)
                    if invoice.creditsApplied > 0 { LabeledContent("Notas de crédito", value: "−\(invoice.creditsApplied.money)") }
                }
            }

            if let notes = invoice.creditNotes, !notes.isEmpty {
                Section("Notas de crédito de esta factura") {
                    ForEach(notes.sorted { $0.date < $1.date }) { note in
                        LabeledContent {
                            Text("−\(note.total.money)").monospacedDigit()
                        } label: {
                            Text(note.number)
                            Text("\(note.date.shortDate)\(note.reason.isEmpty ? "" : " · \(note.reason)")")
                            if note.unappliedAmount > 0 {
                                Text("\(note.unappliedAmount.money) quedan a favor del cliente").foregroundStyle(Palette.positive)
                            }
                        }
                    }
                }
            }

            if let applications = invoice.creditApplications, !applications.isEmpty {
                Section("Créditos aplicados") {
                    ForEach(applications.sorted { $0.date < $1.date }) { application in
                        LabeledContent("\(application.note?.number ?? "Nota") · \(application.date.shortDate)",
                                       value: "−\(application.amount.money)")
                    }
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
                    if let credit = invoice.customer?.creditBalance, credit > 0 {
                        Button("Aplicar saldo a favor (\(min(credit, invoice.balanceDue).money))", action: applyCredit)
                            .buttonStyle(.secondary)
                    }
                    Button("Nota de crédito") { showingCreditNote = true }.buttonStyle(.secondary)
                    if invoice.amountPaid == 0 && invoice.creditsApplied == 0 {
                        Button("Anular factura", role: .destructive) { confirmingVoid = true }.buttonStyle(.destructive)
                    }
                case .paid:
                    Button("Nota de crédito o devolución") { showingCreditNote = true }.buttonStyle(.secondary)
                case .void:
                    EmptyView()
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .screenBackground()
        .navigationTitle(invoice.number.isEmpty ? "Borrador" : invoice.number)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Vista previa", systemImage: "doc.text.magnifyingglass") { showingPreview = true }
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack { InvoicePreviewView(invoice: invoice, company: companies.first) }
        }
        .sheet(isPresented: $editingDraft) {
            NavigationStack { InvoiceEditorView(editing: invoice) }
        }
        .sheet(isPresented: $showingCreditNote) {
            NavigationStack { CreditNoteEditorView(invoice: invoice) }
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

    private func applyCredit() {
        guard let credit = invoice.customer?.creditBalance else { return }
        do { try books.applyCustomerCredit(to: invoice, amount: min(credit, invoice.balanceDue)); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
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

/// Nota de crédito contra la factura: importe neto, si es gravable y motivo. El impuesto usa el grupo de la factura.
struct CreditNoteEditorView: View {
    let invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int64 = 0
    @State private var isTaxable = true
    @State private var reason = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }

    private var preview: InvoicePosting? {
        let components = (try? books.taxComponents(groupID: invoice.taxGroupID, on: invoice.issueDate)) ?? []
        return try? PostingRules.creditNote(date: date, memo: "", receivableAccountID: UUID(),
                                            lines: [SalesLine(incomeAccountID: UUID(), amount: amount, isTaxable: isTaxable)],
                                            taxComponents: components, customerIsTaxExempt: invoice.customer?.isTaxExempt ?? false)
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Factura", value: "\(invoice.number) · \(invoice.customer?.name ?? "")")
                LabeledContent("Saldo pendiente", value: invoice.balanceDue.money)
            }
            Section {
                MoneyField(title: "Importe a acreditar (sin impuesto)", minorUnits: $amount)
                Toggle("Incluye sales tax", isOn: $isTaxable)
                TextField("Motivo (devolución, ajuste de precio…)", text: $reason)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
            }
            Section {
                let total = preview?.total ?? 0
                LabeledContent("Sales tax", value: (preview?.totalTax ?? 0).money)
                LabeledContent("Total de la nota", value: total.money).fontWeight(.semibold)
                if total > 0 {
                    LabeledContent("Se aplica a esta factura", value: min(total, invoice.balanceDue).money)
                    if total > invoice.balanceDue {
                        LabeledContent("Queda a favor del cliente", value: (total - invoice.balanceDue).money)
                            .foregroundStyle(Palette.positive)
                    }
                }
            } footer: {
                Text("Se registra un asiento que reduce ingresos, sales tax por pagar y la cuenta por cobrar del cliente. "
                     + "Lo que no cubra el saldo de esta factura queda a favor del cliente: puedes aplicarlo a otra factura o reembolsarlo desde su ficha.")
            }
        }
        .screenBackground()
        .navigationTitle("Nota de crédito")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Emitir", action: save).disabled(amount <= 0 || reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { isTaxable = !(invoice.taxLines ?? []).isEmpty }
    }

    private func save() {
        do {
            try books.issueCreditNote(for: invoice, amount: amount, isTaxable: isTaxable, reason: reason, date: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
