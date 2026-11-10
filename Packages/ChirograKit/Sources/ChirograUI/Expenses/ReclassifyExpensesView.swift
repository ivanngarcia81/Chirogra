import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

// MARK: - Reclasificar gastos (plan de trabajo del 10-nov, «reclasificar en lote»)
//
// Como «Reclassify transactions» de QuickBooks: se elige la categoría actual y el periodo, se marcan los gastos (todos
// marcados al empezar) y la categoría nueva. Solo cambian las líneas de la categoría actual (`reclassifyExpenses`); los
// contabilizados se corrigen con su reversión y un asiento nuevo, como al editarlos. Se abre desde Gastos (menú «···» en
// iPhone e iPad, barra en el Mac).

/// Periodo de los gastos a reclasificar.
enum ReclassifyPeriod: String, CaseIterable, Identifiable {
    case month, quarter, year, lastYear, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: String(localized: "Este mes")
        case .quarter: String(localized: "Este trimestre")
        case .year: String(localized: "Este año")
        case .lastYear: String(localized: "El año pasado")
        case .all: String(localized: "Todo")
        }
    }

    func contains(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        switch self {
        case .month: return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .quarter:
            let quarter = { (d: Date) in (calendar.component(.year, from: d), (calendar.component(.month, from: d) - 1) / 3) }
            return quarter(date) == quarter(now)
        case .year: return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .lastYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now) - 1
        case .all: return true
        }
    }
}

struct ReclassifyExpensesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @CompanyQuery(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var period: ReclassifyPeriod = .year
    /// Los desmarcados (empiezan todos marcados).
    @State private var excluded: Set<UUID> = []
    @State private var confirming = false
    @State private var result: ReclassificationResult?
    @State private var errorMessage: String?

    /// Gastos con alguna línea de la categoría actual en el periodo, sin los anulados.
    private var candidates: [Expense] {
        guard let from else { return [] }
        return expenses.filter { expense in
            !expense.isVoid && period.contains(expense.date) && expense.sortedLines.contains { $0.accountID == from }
        }
    }

    private var chosen: [Expense] { candidates.filter { !excluded.contains($0.id) } }

    /// Lo que pasa de una categoría a otra (solo las líneas de la actual).
    private func amount(of expense: Expense) -> Int64 {
        expense.sortedLines.filter { $0.accountID == from }.reduce(0) { $0 + $1.amount }
    }

    private var canApply: Bool { from != nil && to != nil && from != to && !chosen.isEmpty }

    private func name(_ id: UUID?) -> String { accounts.first { $0.id == id }?.displayName ?? "" }

    var body: some View {
        Form {
            Section {
                ExpenseCategoryPicker(title: String(localized: "Categoría actual"), accounts: accounts, selection: $from)
                Picker("Periodo", selection: $period) {
                    ForEach(ReclassifyPeriod.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Qué reclasificar")
            }

            if from != nil {
                Section {
                    if candidates.isEmpty {
                        Text("No hay gastos de esta categoría en el periodo.").foregroundStyle(Palette.ink2)
                    }
                    ForEach(candidates) { expense in row(expense) }
                } header: {
                    HStack {
                        let total = chosen.reduce(0) { $0 + amount(of: $1) }.money
                        if candidates.count == 1 {
                            Text("\(chosen.count) de 1 gasto · \(total)")
                        } else {
                            Text("\(chosen.count) de \(candidates.count) gastos · \(total)")
                        }
                        Spacer()
                        if !candidates.isEmpty {
                            Button(excluded.isEmpty ? "Desmarcar todos" : "Marcar todos") {
                                excluded = excluded.isEmpty ? Set(candidates.map(\.id)) : []
                            }
                            .font(.subheadline)
                            .textCase(nil)
                        }
                    }
                }
            }

            Section {
                ExpenseCategoryPicker(title: String(localized: "Nueva categoría"), accounts: accounts, selection: $to)
            } footer: {
                Text("Solo cambian las líneas de la categoría actual. Los gastos ya registrados se corrigen con un asiento que revierte el anterior y uno nuevo, como al editarlos. Los de un periodo cerrado no se cambian.")
            }

            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reclasificar gastos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Reclasificar") { confirming = true }.disabled(!canApply)
            }
        }
        .onChange(of: from) { excluded = [] }
        .onChange(of: period) { excluded = [] }
        .alert(chosen.count == 1 ? String(localized: "¿Reclasificar 1 gasto?") : String(localized: "¿Reclasificar \(chosen.count) gastos?"),
               isPresented: $confirming) {
            Button("Reclasificar") { apply() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("De «\(name(from))» a «\(name(to))». Total: \(chosen.reduce(0) { $0 + amount(of: $1) }.money).")
        }
        .alert(resultTitle, isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("Aceptar") {
                if result?.failures.isEmpty == true { dismiss() }
                result = nil
            }
        } message: {
            Text(resultMessage)
        }
    }

    private func row(_ expense: Expense) -> some View {
        let isOn = !excluded.contains(expense.id)
        return Button {
            if isOn { excluded.insert(expense.id) } else { excluded.remove(expense.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Palette.brand : Palette.ink2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.payee.isEmpty ? (expense.vendor?.name ?? String(localized: "Sin beneficiario")) : expense.payee)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(expense.isPosted ? expense.date.dayMonth : String(localized: "\(expense.date.dayMonth) · por confirmar"))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 8)
                Text(amount(of: expense).money).monospacedDigit().foregroundStyle(Palette.ink)
            }
            .frame(minHeight: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var resultTitle: String {
        guard let result else { return "" }
        return result.failures.isEmpty ? String(localized: "Gastos reclasificados")
            : String(localized: "Algunos gastos no se cambiaron")
    }

    private var resultMessage: String {
        guard let result else { return "" }
        var lines = [result.changed == 1 ? String(localized: "Se reclasificó 1 gasto.")
                                          : String(localized: "Se reclasificaron \(result.changed) gastos.")]
        if !result.failures.isEmpty {
            lines.append(result.failures.count == 1 ? String(localized: "No se pudo cambiar 1:")
                                                    : String(localized: "No se pudieron cambiar \(result.failures.count):"))
            lines += result.failures.prefix(5).map { "• \($0.name): \($0.reason)" }
        }
        return lines.joined(separator: "\n")
    }

    private func apply() {
        guard let from, let to else { return }
        do {
            result = try Bookkeeper(context: context).reclassifyExpenses(chosen, from: from, to: to)
            errorMessage = nil
            excluded = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
