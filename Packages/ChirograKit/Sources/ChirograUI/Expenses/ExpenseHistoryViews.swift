import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Estado de un gasto que se muestra junto al importe (lo normal, contabilizado, no lleva estado).
enum ExpenseStatus {
    case pending, void, edited(Int)

    init?(_ expense: Expense) {
        if expense.isVoid { self = .void } else if !expense.isPosted { self = .pending } else if expense.revision > 0 {
            self = .edited(expense.revision)
        } else { return nil }
    }

    var title: String {
        switch self {
        case .pending: String(localized: "Por confirmar")
        case .void: String(localized: "Anulado")
        case .edited(let times): times == 1 ? String(localized: "Editado") : String(localized: "Editado \(times) veces")
        }
    }

    func chip(compact: Bool = true) -> StatusChip {
        switch self {
        case .pending: StatusChip(text: title, foreground: Palette.warning, background: .clear, compact: compact, dot: Palette.orange)
        case .void: StatusChip(text: title, foreground: Palette.ink2, background: .clear, compact: compact, dot: Palette.gray)
        case .edited: StatusChip(text: title, foreground: Palette.info, background: .clear, compact: compact, dot: Palette.teal)
        }
    }
}

/// Un asiento del historial de un gasto: el original, su reversión y el vigente tras cada edición.
struct ExpenseHistoryItem: Identifiable {
    let entry: JournalEntry
    let role: String
    let isCurrent: Bool
    var id: UUID { entry.id }

    static func items(_ entries: [JournalEntry], current: UUID?) -> [ExpenseHistoryItem] {
        let numbers = Dictionary(entries.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
        return entries.map { entry in
            let role: String
            if let original = entry.reversesEntryID {
                role = numbers[original].map { String(localized: "Reversión del #\($0)") } ?? String(localized: "Reversión")
            } else if entry.id == current, !entry.isReversed {
                role = entry.replacesEntryID == nil ? String(localized: "Vigente") : String(localized: "Vigente, tras editar")
            } else if entry.replacedByEntryID != nil {
                role = String(localized: "Original, revertido al editar")
            } else if entry.isReversed {
                role = String(localized: "Revertido")
            } else {
                role = String(localized: "Asiento")
            }
            return ExpenseHistoryItem(entry: entry, role: role, isCurrent: entry.id == current && !entry.isReversed)
        }
    }
}

/// «Historial» del detalle de un gasto: sus asientos, del más antiguo al más nuevo. Al editar un gasto contabilizado
/// aparecen el original, su reversión (en la misma fecha) y el nuevo; los reportes cuadran porque los dos primeros se
/// anulan entre sí.
struct ExpenseHistorySection: View {
    let expense: Expense
    @CompanyQuery private var entries: [JournalEntry]

    init(expense: Expense) {
        self.expense = expense
        let id: UUID? = expense.id
        _entries = CompanyQuery(filter: #Predicate<JournalEntry> { $0.sourceDocumentID == id }, sort: \.number)
    }

    var body: some View {
        let items = ExpenseHistoryItem.items(entries, current: expense.journalEntryID)
        Section {
            ForEach(items) { item in
                NavigationLink { JournalEntryDetailView(entry: item.entry) } label: {
                    LedgerRow(title: String(localized: "Asiento #\(item.entry.number)"),
                              subtitle: "\(item.entry.date.shortDate) · \(item.role)") {
                        EmptyView()
                    } trailing: {
                        Text(item.entry.totalDebits.money).monospacedDigit()
                            .foregroundStyle(item.isCurrent ? Palette.ink : Palette.ink2)
                    }
                }
            }
        } header: {
            SectionLabel(text: String(localized: "Historial"))
        } footer: {
            if expense.revision == 1 {
                Text("Editado una vez: la edición revirtió el asiento anterior en su fecha y registró uno nuevo.")
            } else if expense.revision > 1 {
                Text("Editado \(expense.revision) veces: cada edición revierte el asiento anterior en su fecha y registra uno nuevo.")
            }
        }
    }
}

#if os(macOS)
/// «Historial» en el inspector del Mac: «#12 · 29 oct · Vigente» y el importe.
struct ExpenseHistoryInspectorSection: View {
    let expense: Expense
    let open: (JournalEntry) -> Void
    @CompanyQuery private var entries: [JournalEntry]

    init(expense: Expense, open: @escaping (JournalEntry) -> Void) {
        self.expense = expense
        self.open = open
        let id: UUID? = expense.id
        _entries = CompanyQuery(filter: #Predicate<JournalEntry> { $0.sourceDocumentID == id }, sort: \.number)
    }

    var body: some View {
        let items = ExpenseHistoryItem.items(entries, current: expense.journalEntryID)
        if !items.isEmpty {
            MacInspectorSection(title: String(localized: "Historial")) {
                ForEach(items) { item in
                    MacInspectorRow(label: "#\(item.entry.number) · \(item.entry.date.dayMonth)") {
                        Button { open(item.entry) } label: {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(item.entry.totalDebits.money).foregroundStyle(item.isCurrent ? Palette.ink : Palette.ink2)
                                Text(item.role).font(.footnote).foregroundStyle(item.isCurrent ? Palette.positive : Palette.ink2).lineLimit(1)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help("Ver asiento")
                    }
                }
            }
        }
    }
}
#endif
