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

    @State private var showingRate = false
    @State private var showingGroup = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let payable = accounts.filter { $0.subtype == .salesTaxPayable }.reduce(0) { $0 + ledger.balance(of: $1) }
        let quarter = Calendar.current.dateInterval(of: .quarter, for: .now)
        let collected = taxLines.filter { line in
            guard let invoice = line.invoice, invoice.status != .void, let quarter else { return false }
            return quarter.contains(invoice.issueDate)
        }
        List {
            Section {
                HeroCard(title: "Sales tax por pagar", value: payable.money, detail: "Saldo de la cuenta según libros")
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            Section("Cobrado este trimestre") {
                let byRate = Dictionary(grouping: collected, by: \.name)
                if byRate.isEmpty { Text("Sin ventas gravables este trimestre.").foregroundStyle(Palette.ink3) }
                ForEach(byRate.keys.sorted(), id: \.self) { name in
                    let lines = byRate[name] ?? []
                    LabeledContent(name) {
                        VStack(alignment: .trailing) {
                            Text(lines.reduce(0) { $0 + $1.amount }.money).monospacedDigit()
                            Text("sobre \(lines.reduce(0) { $0 + $1.taxableBase }.money)").font(.caption).foregroundStyle(Palette.ink3)
                        }
                    }
                }
            }

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
                           value: "\((Decimal(rates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.rateMillionths }) / 10_000).formatted())%")
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
