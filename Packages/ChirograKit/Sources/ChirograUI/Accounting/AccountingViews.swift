import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Contabilidad (canvas: `MacDiario`, `MacLibroMayor`): plan de cuentas, asientos, libro mayor y cierre.
struct AccountingView: View {
    var body: some View {
        List {
            NavigationLink { ChartOfAccountsView() } label: { Label("Plan de cuentas", systemImage: "list.bullet.indent") }
            NavigationLink { JournalListView() } label: { Label("Asientos de diario", systemImage: "doc.plaintext") }
            NavigationLink { LedgerAccountPickerView() } label: { Label("Libro mayor", systemImage: "book.closed") }
            NavigationLink { PeriodCloseView() } label: { Label("Cierre de periodo", systemImage: "lock") }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle("Contabilidad")
    }
}

extension AccountType {
    var title: String {
        switch self {
        case .asset: "Activos"
        case .liability: "Pasivos"
        case .equity: "Patrimonio"
        case .income: "Ingresos"
        case .expense: "Gastos"
        }
    }
}

extension AccountSubtype {
    var title: String {
        switch self {
        case .cash: "Efectivo"
        case .bank: "Banco"
        case .accountsReceivable: "Cuentas por cobrar"
        case .undepositedFunds: "Fondos no depositados"
        case .inventory: "Inventario"
        case .otherCurrentAsset: "Otro activo corriente"
        case .fixedAsset: "Activo fijo"
        case .otherAsset: "Otro activo"
        case .accountsPayable: "Cuentas por pagar"
        case .creditCard: "Tarjeta de crédito"
        case .salesTaxPayable: "Sales tax por pagar"
        case .otherCurrentLiability: "Otro pasivo corriente"
        case .longTermLiability: "Pasivo a largo plazo"
        case .ownersEquity: "Capital"
        case .ownersDraw: "Retiros"
        case .retainedEarnings: "Resultados acumulados"
        case .openingBalanceEquity: "Saldos de apertura"
        case .sales: "Ventas"
        case .otherIncome: "Otros ingresos"
        case .costOfGoodsSold: "Costo de ventas"
        case .operatingExpense: "Gasto operativo"
        case .otherExpense: "Otro gasto"
        }
    }
}

struct ChartOfAccountsView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var showingNew = false
    @State private var showArchived = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        List {
            ForEach(AccountType.allCases, id: \.self) { type in
                Section(type.title) {
                    ForEach(accounts.filter { $0.type == type && (showArchived || !$0.isArchived) }) { account in
                        NavigationLink { LedgerView(account: account) } label: {
                            HStack {
                                Text(account.code).foregroundStyle(Palette.ink3).frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name).strikethrough(account.isArchived)
                                    Text(account.subtype.title).font(.caption).foregroundStyle(Palette.ink3)
                                }
                                Spacer()
                                Text(ledger.balance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink2)
                            }
                        }
                        .swipeActions {
                            if !account.isSystem {
                                Button(account.isArchived ? "Restaurar" : "Archivar") { account.isArchived.toggle() }
                            }
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .screenBackground()
        .navigationTitle("Plan de cuentas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { showingNew = true } label: { Label("Nueva cuenta", systemImage: "plus") } }
            ToolbarItem { Toggle("Archivadas", isOn: $showArchived) }
        }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() } }
    }
}

struct AccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @State private var code = ""
    @State private var name = ""
    @State private var subtype: AccountSubtype = .operatingExpense

    private var codeTaken: Bool { accounts.contains { $0.code == code && !code.isEmpty } }

    var body: some View {
        Form {
            TextField("Código", text: $code)
            if codeTaken { Text("Ya existe una cuenta con ese código.").foregroundStyle(Palette.negative).font(.footnote) }
            TextField("Nombre", text: $name)
            Picker("Tipo", selection: $subtype) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Section(type.title) {
                        ForEach(AccountSubtype.allCases.filter { $0.accountType == type }, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Nueva cuenta")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    context.insert(Account(code: code, name: name, subtype: subtype))
                    try? context.save()
                    dismiss()
                }
                .disabled(name.isEmpty || codeTaken)
            }
        }
    }
}

struct JournalListView: View {
    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var showingEditor = false

    var body: some View {
        List {
            if entries.isEmpty {
                EmptyStateView(systemImage: "doc.plaintext", title: "Sin asientos", message: "Los documentos generan asientos automáticamente; también puedes crear uno manual.")
            }
            ForEach(entries) { entry in
                NavigationLink { JournalEntryDetailView(entry: entry) } label: {
                    LedgerRow(title: entry.memo.isEmpty ? "Asiento \(entry.number)" : entry.memo,
                              subtitle: "#\(entry.number) · \(entry.date.shortDate) · \(entry.source.title)") {
                        EmptyView()
                    } trailing: {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(entry.totalDebits.money).monospacedDigit()
                            if entry.isReversed || entry.reversesEntryID != nil {
                                StatusChip(text: entry.isReversed ? "Revertido" : "Reversión", foreground: Palette.ink3, background: Palette.surface2)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationTitle("Asientos de diario")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { showingEditor = true } label: { Label("Nuevo asiento", systemImage: "plus") } }
        }
        .sheet(isPresented: $showingEditor) { NavigationStack { JournalEntryEditorView() } }
    }
}

extension EntrySource {
    var title: String {
        switch self {
        case .manual: "Manual"
        case .invoice: "Factura"
        case .creditNote: "Nota de crédito"
        case .paymentReceived: "Cobro"
        case .bill: "Factura de proveedor"
        case .billPayment: "Pago a proveedor"
        case .expense: "Gasto"
        case .salesTaxPayment: "Pago de sales tax"
        case .reversal: "Reversión"
        case .opening: "Saldos iniciales"
        }
    }
}

/// Editor de asiento (canvas: `MacDiario`): totales en vivo y aviso hasta que débitos = créditos.
struct JournalEntryEditorView: View {
    struct LineDraft: Identifiable {
        let id = UUID()
        var accountID: UUID?
        var memo = ""
        var debit: Int64 = 0
        var credit: Int64 = 0
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.code) private var accounts: [Account]

    @State private var date = Date()
    @State private var memo = ""
    @State private var lines: [LineDraft] = [LineDraft(), LineDraft()]
    @State private var errorMessage: String?

    private var books: Bookkeeper { Bookkeeper(context: context) }
    private var postable: [Account] { accounts.filter(\.isPostable) }

    private var draft: JournalEntryDraft {
        JournalEntryDraft(date: date, memo: memo, source: .manual, lines: lines.compactMap { line in
            guard let accountID = line.accountID else { return nil }
            return JournalLineDraft(accountID: accountID, debit: line.debit, credit: line.credit, memo: line.memo)
        })
    }

    private var validationErrors: [JournalValidationError] {
        guard let validator = try? books.validator() else { return [] }
        return validator.errors(for: draft)
    }

    var body: some View {
        let entry = draft
        let isValid = validationErrors.isEmpty && lines.allSatisfy { $0.accountID != nil || ($0.debit == 0 && $0.credit == 0) }
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Concepto", text: $memo)
            }
            Section {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        AccountPicker(title: "Cuenta", accounts: postable, selection: $line.accountID)
                        TextField("Descripción", text: $line.memo).font(.subheadline)
                        HStack {
                            MoneyField(title: "Débito", minorUnits: $line.debit)
                            MoneyField(title: "Crédito", minorUnits: $line.credit)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Añadir línea", systemImage: "plus") { lines.append(LineDraft()) }
            } header: {
                Text("Líneas")
            } footer: {
                HStack {
                    Text("Totales")
                    Spacer()
                    Text("Debe \(entry.totalDebits.money)  ·  Haber \(entry.totalCredits.money)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
            }

            Section {
                statusBanner(entry)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .screenBackground()
        .navigationTitle("Nuevo asiento")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Registrar asiento", action: save).disabled(!isValid) }
        }
    }

    @ViewBuilder
    private func statusBanner(_ entry: JournalEntryDraft) -> some View {
        let balanced = entry.isBalanced && entry.totalDebits > 0
        let message: String = if balanced {
            validationErrors.first?.localizedMessage ?? "El asiento cuadra: débitos = créditos"
        } else if entry.difference > 0 {
            "No cuadra: faltan créditos por \(abs(entry.difference).money)"
        } else if entry.difference < 0 {
            "No cuadra: faltan débitos por \(abs(entry.difference).money)"
        } else {
            "Escribe los importes al debe y al haber"
        }
        let ok = balanced && validationErrors.isEmpty
        Label(message, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ok ? Palette.positive : Palette.negative)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ok ? Palette.positiveWash : Palette.negativeWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func save() {
        do {
            try books.post(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JournalEntryDetailView: View {
    let entry: JournalEntry
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?
    @State private var confirming = false

    var body: some View {
        List {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Número", value: "#\(entry.number)")
                LabeledContent("Fecha", value: entry.date.shortDate)
                LabeledContent("Origen", value: entry.source.title)
                if !entry.memo.isEmpty { LabeledContent("Concepto", value: entry.memo) }
            }
            Section("Líneas") {
                ForEach(entry.sortedLines) { line in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(line.account?.displayName ?? "Cuenta eliminada")
                            if !line.memo.isEmpty { Text(line.memo).font(.caption).foregroundStyle(Palette.ink3) }
                        }
                        Spacer()
                        Text(line.debit > 0 ? line.debit.money : "").frame(width: 100, alignment: .trailing)
                        Text(line.credit > 0 ? line.credit.money : "").frame(width: 100, alignment: .trailing)
                    }
                    .monospacedDigit()
                }
                HStack {
                    Text("Totales").bold()
                    Spacer()
                    Text(entry.totalDebits.money).frame(width: 100, alignment: .trailing)
                    Text(entry.totalCredits.money).frame(width: 100, alignment: .trailing)
                }
                .monospacedDigit()
            }
            if entry.source == .manual && !entry.isReversed && entry.reversesEntryID == nil {
                Section {
                    Button("Revertir asiento", role: .destructive) { confirming = true }
                } footer: {
                    Text("Los asientos contabilizados no se editan ni se borran: se corrigen con un asiento de reversión.")
                }
            }
        }
        .screenBackground()
        .navigationTitle("Asiento #\(entry.number)")
        .inlineTitle()
        .confirmationDialog("¿Revertir este asiento?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Revertir", role: .destructive) {
                do { try Bookkeeper(context: context).reverse(entry) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

struct LedgerAccountPickerView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    var body: some View {
        List(accounts.filter { !$0.isArchived }) { account in
            NavigationLink(account.displayName) { LedgerView(account: account) }
                .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationTitle("Libro mayor")
    }
}

/// Libro mayor de una cuenta con saldo acumulado (canvas: `MacLibroMayor`).
/// El signo de cada movimiento sigue la naturaleza de la cuenta: en pasivo, patrimonio e ingreso
/// un crédito aumenta el saldo (+); en activo y gasto lo aumenta un débito.
struct LedgerView: View {
    let account: Account

    private var ledger: AccountLedger {
        let movements = (account.lines ?? []).compactMap { line -> LedgerMovement? in
            guard let entry = line.entry, entry.status == .posted else { return nil }
            return LedgerMovement(id: line.id, date: entry.date, memo: entry.memo, debit: line.debit, credit: line.credit)
        }
        return ReportBuilder.accountLedger(account: account.ledgerAccount, movements: movements)
    }

    var body: some View {
        let ledger = ledger
        List {
            Section {
                LabeledContent("Saldo", value: ledger.closingBalance.money).font(.headline)
                LabeledContent("Tipo", value: "\(account.type.title) · \(account.subtype.title)")
                LabeledContent("Aumenta con", value: account.type.normalBalance == .debit ? "Débitos" : "Créditos")
            }
            Section {
                if ledger.rows.isEmpty { Text("Sin movimientos").foregroundStyle(Palette.ink3) }
                ForEach(ledger.rows.reversed()) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.movement.memo.isEmpty ? "Asiento" : row.movement.memo).lineLimit(2)
                            Text("\(row.movement.date.shortDate) · \(row.movement.debit > 0 ? "Débito" : "Crédito")")
                                .font(.caption).foregroundStyle(Palette.ink3)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(row.increasesBalance ? "+" : "−")\(abs(row.effect).money)")
                                .foregroundStyle(row.increasesBalance ? Palette.ink : Palette.outflow)
                            Text("Saldo \(row.balance.money)").font(.caption).foregroundStyle(Palette.ink3)
                        }
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.movement.memo), \(row.movement.date.shortDate), "
                        + "\(row.movement.debit > 0 ? "débito" : "crédito") de \(max(row.movement.debit, row.movement.credit).money), "
                        + "\(row.increasesBalance ? "aumenta" : "reduce") el saldo a \(row.balance.money)")
                }
            } header: {
                Text("Movimientos")
            } footer: {
                Text("+ aumenta el saldo de la cuenta y − lo reduce, según su naturaleza.")
            }
        }
        .listRowBackground(Palette.surface)
        .screenBackground()
        .navigationTitle(account.name)
    }
}

/// Cierre de periodo: fecha hasta la que no se admiten asientos (DISEÑO §4.2).
struct PeriodCloseView: View {
    @Query private var companies: [Company]
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            if let company = companies.first {
                Section {
                    Toggle("Cerrar periodos", isOn: Binding(
                        get: { company.lockDate != nil },
                        set: { company.lockDate = $0 ? Calendar.current.date(byAdding: .day, value: -1, to: DateInterval.month(containing: .now).start) : nil }
                    ))
                    if let lockDate = company.lockDate {
                        DatePicker("Cerrado hasta", selection: Binding(get: { lockDate }, set: { company.lockDate = $0 }), displayedComponents: .date)
                    }
                } footer: {
                    Text("No se podrá registrar nada con fecha igual o anterior al cierre. Así los reportes que ya entregaste no cambian.")
                }
            }
        }
        .screenBackground()
        .navigationTitle("Cierre de periodo")
        .onDisappear { try? context.save() }
    }
}
