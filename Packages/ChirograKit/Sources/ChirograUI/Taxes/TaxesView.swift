import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Impuestos (canvas: `Impuestos`): saldo de sales tax por pagar, tasas por jurisdicción y grupos.
struct TaxesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @Query(sort: \TaxGroup.name) private var groups: [TaxGroup]
    @Query private var taxLines: [InvoiceTaxLine]

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showingRate = false
    @State private var showingPayment = false
    @State private var showingGroup = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let payable = accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
        let quarter = Calendar.current.dateInterval(of: .quarter, for: .now)
        let _ = taxLines.count   // se observa para recalcular el resumen al emitir facturas
        List {
            Section {
                let position = SalesTaxPosition(liabilityBalance: payable)
                HeroCard(title: position.title, value: position.amount.money, detail: position.detail)
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            Section {
                Button("Registrar pago a la agencia", systemImage: "building.columns") { showingPayment = true }
                    .disabled(payable <= 0)
                let payments = entries.filter { $0.source == .salesTaxPayment && $0.reversesEntryID == nil }
                ForEach(payments.prefix(5)) { entry in
                    LabeledContent {
                        Text(entry.totalDebits.money).monospacedDigit()
                    } label: {
                        Text(entry.memo)
                        Text(entry.date.shortDate)
                    }
                }
            } header: {
                Text("Pagos a la agencia")
            }

            Section("Este trimestre") {
                if let quarter, let summary = try? Bookkeeper(context: context).salesTaxSummary(
                    from: quarter.start, to: quarter.end.addingTimeInterval(-1)) {
                    LabeledContent("Ventas gravables", value: summary.taxableSales.money)
                    LabeledContent("No gravables y exentas", value: (summary.nonTaxableSales + summary.exemptSales).money)
                    ForEach(summary.rows) { row in
                        LabeledContent("\(row.name) · \(row.percent.formatted())%", value: row.tax.money)
                    }
                    LabeledContent("Total cobrado", value: summary.totalTax.money).fontWeight(.semibold)
                }
            }
            .monospacedDigit()

            Section("Grupos (lo que se aplica en la factura)") {
                ForEach(groups) { group in
                    LabeledContent(group.name, value: "\(group.percent.formatted())%")
                }
                Button("Nuevo grupo", systemImage: "plus") { showingGroup = true }.disabled(agencies.flatMap { $0.rates ?? [] }.isEmpty)
            }

            ForEach(agencies) { agency in
                Section(agency.name) {
                    ForEach(agency.rates ?? []) { rate in
                        LabeledContent(rate.name, value: "\(rate.percent.formatted())%")
                    }
                }
            }
            Section {
                Button("Nueva tasa", systemImage: "plus") { showingRate = true }
            } footer: {
                Text("Escribe las tasas de tu estado, condado y ciudad. Chirogra no determina qué es gravable: consúltalo con tu agencia o tu contador.")
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Impuestos")
        .sheet(isPresented: $showingRate) { NavigationStack { TaxRateEditorView() } }
        .sheet(isPresented: $showingPayment) { NavigationStack { SalesTaxPaymentView(owed: payable) } }
        .sheet(isPresented: $showingGroup) { NavigationStack { TaxGroupEditorView() } }
    }
}

struct TaxRateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]

    @State private var agencyID: UUID?
    @State private var newAgencyName = ""
    @State private var name = ""
    @State private var percent: Decimal = 0
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section("Agencia") {
                Picker("Agencia", selection: $agencyID) {
                    Text("Nueva agencia…").tag(UUID?.none)
                    ForEach(agencies) { Text($0.name).tag(Optional($0.id)) }
                }
                if agencyID == nil { TextField("Nombre (p. ej. Texas Comptroller)", text: $newAgencyName) }
            }
            Section("Tasa") {
                TextField("Nombre (p. ej. Travis County)", text: $name)
                TextField("Porcentaje", value: $percent, format: .number.precision(.fractionLength(0...4)))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        .screenBackground()
        .navigationTitle("Nueva tasa")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(name.isEmpty || percent <= 0 || (agencyID == nil && newAgencyName.isEmpty))
            }
        }
    }

    private func save() {
        do {
            let agency: TaxAgency
            if let existing = agencies.first(where: { $0.id == agencyID }) {
                agency = existing
            } else {
                let liability = try Bookkeeper(context: context).systemAccount(.salesTaxPayable)
                agency = TaxAgency(name: newAgencyName, liabilityAccountID: liability.id)
                context.insert(agency)
            }
            context.insert(TaxRate(name: name, rateMillionths: TaxComponent.millionths(fromPercent: percent), agency: agency))
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaxGroupEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaxRate.name) private var rates: [TaxRate]
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        Form {
            TextField("Nombre (p. ej. Austin, TX)", text: $name)
            Section("Tasas incluidas") {
                ForEach(rates.filter { !$0.isArchived }) { rate in
                    Toggle(isOn: Binding(get: { selected.contains(rate.id) },
                                         set: { if $0 { selected.insert(rate.id) } else { selected.remove(rate.id) } })) {
                        LabeledContent(rate.name, value: "\(rate.percent.formatted())%")
                    }
                }
            }
            LabeledContent("Tasa combinada",
                           value: String(localized: "\((Decimal(rates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.rateMillionths }) / 10_000).formatted())%"))
        }
        .screenBackground()
        .navigationTitle("Nuevo grupo")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    context.insert(TaxGroup(name: name, rates: rates.filter { selected.contains($0.id) }))
                    try? context.save()
                    dismiss()
                }
                .disabled(name.isEmpty || selected.isEmpty)
            }
        }
    }
}

/// Registrar el pago del sales tax cobrado a la agencia (Debe Sales Tax Payable / Haber Banco).
struct SalesTaxPaymentView: View {
    let owed: Int64
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaxAgency.name) private var agencies: [TaxAgency]
    @Query(sort: \Account.code) private var accounts: [Account]
    @State private var agencyID: UUID?
    @State private var amount: Int64 = 0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var reference = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                Picker("Agencia", selection: $agencyID) {
                    Text("Sin agencia").tag(UUID?.none)
                    ForEach(agencies) { Text($0.name).tag(Optional($0.id)) }
                }
                LabeledContent("Pendiente según libros", value: owed.money)
            }
            Section {
                MoneyField(title: String(localized: "Importe pagado"), minorUnits: $amount)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                AccountPicker(title: String(localized: "Pagado desde"), accounts: accounts.filtered { $0 == .bank || $0 == .cash }, selection: $accountID)
                TextField("Periodo o referencia (p. ej. Q3 2026)", text: $reference)
            }
        }
        .screenBackground()
        .navigationTitle("Pago de sales tax")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Registrar", action: save).disabled(amount <= 0 || accountID == nil) }
        }
        .onAppear {
            amount = owed
            agencyID = agencyID ?? agencies.first?.id
            accountID = accountID ?? accounts.first { $0.subtype == .bank }?.id
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            try Bookkeeper(context: context).paySalesTax(to: agencies.first { $0.id == agencyID }, amount: amount, date: date,
                                                         from: account, reference: reference)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension SalesTaxPosition {
    var title: String {
        switch self {
        case .owed: String(localized: "Sales tax por pagar")
        case .settled: String(localized: "Sales tax al día")
        case .credit: String(localized: "Sales tax a favor")
        }
    }

    var detail: String {
        switch self {
        case .owed, .settled: String(localized: "Saldo de la cuenta según libros")
        case .credit: String(localized: "Pagaste más de lo cobrado (p. ej. por una nota de crédito): se descuenta de la próxima declaración")
        }
    }
}
