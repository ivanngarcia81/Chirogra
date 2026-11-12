import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Crear y editar presupuestos (fase 2)
//
// Crear: vacío, copiando otro presupuesto o con lo real de un año fiscal, con un ajuste en % (110 = +10 %).
// Editar: las cuentas de ingresos y gastos con su total del año; cada una abre sus 12 meses, con «Repartir» para poner
// un total anual a partes iguales. Todo pasa por `Bookkeeper` (`createBudget`, `setBudgetAmounts`, `setAnnualBudget`).

/// Hoja «Nuevo presupuesto».
struct BudgetCreateView: View {
    enum Origin: String, CaseIterable, Identifiable {
        case empty, copy, actuals
        var id: String { rawValue }
        var title: String {
            switch self {
            case .empty: String(localized: "Vacío")
            case .copy: String(localized: "Copiar otro")
            case .actuals: String(localized: "Desde lo real")
            }
        }
    }

    let budgets: [Budget]
    let suggestedYear: Int
    let onCreated: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @State private var name = ""
    @State private var year = 0
    @State private var origin: Origin = .empty
    @State private var sourceID: UUID?
    @State private var sourceYear = 0
    @State private var factor = 100
    @State private var errorMessage: String?

    private var years: [Int] { Array((suggestedYear - 2)...(suggestedYear + 2)) }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                TextField("Nombre", text: $name, prompt: Text("Presupuesto \(String(year))"))
                Picker("Año fiscal", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
            } header: {
                SectionLabel(text: String(localized: "Presupuesto"))
            }
            Section {
                Picker("Empezar", selection: $origin) {
                    ForEach(Origin.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch origin {
                case .empty:
                    EmptyView()
                case .copy:
                    Picker("Copiar de", selection: $sourceID) {
                        Text("Elegir…").tag(UUID?.none)
                        ForEach(budgets) { budget in
                            let year = String(budget.fiscalYear)
                            Text(verbatim: budget.name.contains(year) ? budget.name : "\(budget.name) · \(year)").tag(Optional(budget.id))
                        }
                    }
                case .actuals:
                    Picker("Lo real de", selection: $sourceYear) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                if origin != .empty {
                    Stepper(value: $factor, in: 0...500, step: 5) {
                        LabeledContent("Ajuste", value: factorText)
                    }
                }
            } header: {
                SectionLabel(text: String(localized: "Importes"))
            } footer: {
                Text(footer)
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Nuevo presupuesto")
        .inlineTitle()
        .discardableEditor(tracking: "\(name)|\(origin.rawValue)|\(factor)|\(sourceID?.uuidString ?? "")", token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Crear", action: create)
                    .disabled(origin == .copy && sourceID == nil)
                    .headerButton()
            }
        }
        .onAppear {
            if year == 0 { year = suggestedYear; sourceYear = suggestedYear - 1; sourceID = budgets.first?.id }
        }
    }

    private var factorText: String {
        factor == 100 ? String(localized: "Igual") : (factor > 100 ? "+\(factor - 100) %" : "−\(100 - factor) %")
    }

    private var footer: String {
        switch origin {
        case .empty: String(localized: "Después pones los importes de cada cuenta por mes o por año.")
        case .copy: String(localized: "Copia los importes del otro presupuesto mes a mes, con el ajuste.")
        case .actuals: String(localized: "Pone en cada cuenta de ingresos y gastos lo que se registró ese año fiscal, mes a mes, con el ajuste.")
        }
    }

    private func create() {
        let books = Bookkeeper(context: context)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let title = trimmed.isEmpty ? String(localized: "Presupuesto \(String(year))") : trimmed
        do {
            let budget: Budget = switch origin {
            case .empty: try books.createBudget(name: title, fiscalYear: year)
            case .copy: try books.createBudget(name: title, fiscalYear: year, copying: budgets.first { $0.id == sourceID }, factorPercent: factor)
            case .actuals: try books.createBudget(name: title, fiscalYear: year, fromActualsOf: sourceYear, factorPercent: factor)
            }
            onCreated(budget.id)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Hoja «Editar importes»: el nombre y las cuentas de resultados con su total del año.
struct BudgetEditorView: View {
    let budget: Budget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery private var lines: [BudgetLine]
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var editingAccount: Account?

    /// Cuentas de ingresos, costo y gastos, sin las archivadas ni las que solo agrupan.
    private var groups: [(String, [Account])] {
        let shown = accounts.filter { !$0.type.isBalanceSheet && !$0.isArchived && $0.isLeaf }
        return [
            (String(localized: "Ingresos"), shown.filter { $0.type == .income }),
            (String(localized: "Gastos"), shown.filter { $0.type == .expense }),
        ]
    }

    private func annual(_ account: Account) -> Int64 {
        lines.filter { $0.budget?.id == budget.id && $0.accountID == account.id }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                TextField("Nombre", text: $name)
                    .onSubmit(rename)
                LabeledContent("Año fiscal", value: String(budget.fiscalYear))
                LabeledContent("Total ingresos", value: groups[0].1.reduce(0) { $0 + annual($1) }.money)
                LabeledContent("Total gastos", value: groups[1].1.reduce(0) { $0 + annual($1) }.money)
            } header: {
                SectionLabel(text: String(localized: "Presupuesto"))
            }
            ForEach(groups, id: \.0) { title, list in
                Section {
                    ForEach(list) { account in
                        Button { editingAccount = account } label: {
                            LabeledContent {
                                HStack(spacing: 8) {
                                    Text(annual(account) == 0 ? "—" : annual(account).money).monospacedDigit()
                                        .foregroundStyle(annual(account) == 0 ? Palette.ink2 : Palette.ink)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chevron)
                                        .accessibilityHidden(true)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name).foregroundStyle(Palette.ink)
                                    Text(account.code).font(.footnote).foregroundStyle(Palette.ink2)
                                }
                            }
                            .frame(minHeight: Metrics.target)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Editar los 12 meses")
                    }
                } header: {
                    SectionLabel(text: title)
                }
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle("Editar importes")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { rename(); dismiss() }.headerButton()
            }
        }
        .onAppear { if name.isEmpty { name = budget.name } }
        .sheet(item: $editingAccount) { account in
            NavigationStack { BudgetAccountEditor(budget: budget, account: account) }.editorSheetSizing()
        }
    }

    private func rename() {
        guard name.trimmingCharacters(in: .whitespaces) != budget.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do { try Bookkeeper(context: context).renameBudget(budget, to: name); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}

/// Los 12 meses de una cuenta, en el orden del año fiscal, con el total anual y «Repartir».
struct BudgetAccountEditor: View {
    let budget: Budget
    let account: Account
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unsavedChanges) private var unsavedChanges
    @State private var editorToken = EditorToken()
    @State private var months: [BudgetMonth] = []
    @State private var amounts: [Int64] = Array(repeating: 0, count: 12)
    @State private var annual: Int64 = 0
    @State private var loaded = false
    @State private var errorMessage: String?

    private var total: Int64 { amounts.reduce(0, +) }

    var body: some View {
        Form {
            if let errorMessage { ErrorBanner(message: errorMessage) }
            Section {
                LabeledContent("Total anual") {
                    MoneyField(title: String(localized: "Total anual"), minorUnits: $annual).multilineTextAlignment(.trailing)
                }
                .fieldRow()
                Button("Repartir en los 12 meses", systemImage: "equal.square") {
                    let shares = PostingRules.allocate(abs(annual), weights: Array(repeating: 1, count: 12))
                    amounts = shares.map { annual < 0 ? -$0 : $0 }
                }
                .disabled(annual == 0)
            } header: {
                SectionLabel(text: "\(account.code) · \(account.name)")
            } footer: {
                Text("Pon el total del año y repártelo a partes iguales, o escribe cada mes. Los centavos que sobran van a los primeros meses.")
            }
            Section {
                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                    LabeledContent(month.start.formatted(.appDateTime.month(.wide).year()).sentenceCased) {
                        MoneyField(title: month.start.monthYear, minorUnits: $amounts[index]).multilineTextAlignment(.trailing)
                    }
                    .fieldRow()
                }
                LabeledContent("Suma de los meses", value: total.money).fontWeight(.semibold)
            } header: {
                SectionLabel(text: String(localized: "Por mes"))
            }
        }
        .formStyle(.grouped)
        .screenBackground()
        .navigationTitle(account.name)
        .inlineTitle()
        .discardableEditor(tracking: amounts, token: editorToken)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save).headerButton() }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        months = (try? Bookkeeper(context: context).months(ofFiscalYear: budget.fiscalYear)) ?? []
        amounts = months.map { budget.amount(accountID: account.id, month: $0.month) }
        if amounts.count != 12 { amounts = Array(repeating: 0, count: 12) }
        annual = amounts.reduce(0, +)
    }

    private func save() {
        do {
            try Bookkeeper(context: context).setBudgetAmounts(amounts, account: account, in: budget)
            unsavedChanges?.remove(editorToken)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
