#if os(macOS)
import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Mac: Asientos de diario como tabla + inspector (canvas `MacDiario`). Arriba el segmentado por origen con su cuenta y
/// la tabla Número · Fecha · Concepto · Origen · Estado · Importe. El inspector muestra el asiento elegido (Asiento y
/// sus líneas con Débito · Crédito y totales, como el editor de `MacDiario`) con «Abrir asiento» y, si es manual y no
/// se ha revertido, «Revertir asiento…». «Nuevo asiento» abre la hoja de siempre (`JournalEntryEditorView`); doble
/// clic abre el asiento completo (`JournalEntryDetailView`).
struct JournalTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\JournalEntry.date, order: .reverse), SortDescriptor(\JournalEntry.number, order: .reverse)])
    private var entries: [JournalEntry]
    @State private var filter: JournalFilter = .all
    @State private var query = ""
    @State private var creating = false
    @State private var opened: JournalEntry?
    @State private var reversing: JournalEntry?
    @State private var errorMessage: String?

    private var filtered: [JournalEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            filter.matches(entry) && (text.isEmpty
                || entry.tableMemo.localizedStandardContains(text)
                || "#\(entry.number)".contains(text)
                || entry.source.title.localizedStandardContains(text)
                || entry.totalDebits.money.contains(text)
                || (entry.lines ?? []).contains { $0.account?.displayName.localizedStandardContains(text) == true })
        }
    }

    private var footer: String {
        filtered.count == entries.count ? String(localized: "\(entries.count) asientos")
            : String(localized: "\(filtered.count) de \(entries.count) asientos")
    }

    var body: some View {
        MacTablePage(
            title: String(localized: "Asientos de diario"),
            subtitle: String(localized: "Contabilidad · \(entries.count) asientos"),
            rows: filtered, footer: footer,
            query: $query, searchPrompt: Text("Concepto, número, cuenta o monto"),
            selection: $selection,
            sortOrder: [KeyPathComparator(\JournalEntry.date, order: .reverse), KeyPathComparator(\JournalEntry.number, order: .reverse)],
            addTitle: String(localized: "Nuevo asiento"), onAdd: { creating = true },
            onOpen: { opened = $0 },
            empty: entries.isEmpty
                ? MacTableEmpty(systemImage: "doc.plaintext", title: String(localized: "Sin asientos"),
                                message: String(localized: "Los documentos generan asientos automáticamente; también puedes crear uno manual."),
                                actionTitle: String(localized: "Nuevo asiento"), action: { creating = true })
                : MacTableEmpty(title: String(localized: "Sin resultados"),
                                message: String(localized: "Ningún asiento coincide con la búsqueda o el filtro."),
                                actionTitle: String(localized: "Quitar filtros"), action: { query = ""; filter = .all }),
            inspectorTitle: { entry in
                guard let entry else { return String(localized: "Asiento") }
                return String(localized: "Asiento #\(entry.number)")
            },
            inspectorPlaceholder: String(localized: "Selecciona un asiento para ver sus líneas.")
        ) {
            TableColumn("Número", value: \.number) { entry in
                MacCellText(text: "#\(entry.number)").monospacedDigit()
            }
            .width(min: 44, ideal: 56, max: 90)
            TableColumn("Fecha", value: \.date) { entry in
                MacCellText(text: entry.date.shortDate)
            }
            .width(min: 76, ideal: 92, max: 130)
            TableColumn("Concepto", value: \.tableMemo) { entry in
                Text(entry.tableMemo).lineLimit(1)
            }
            .width(min: 120, ideal: 170)
            TableColumn("Origen", value: \.sourceRaw) { entry in
                MacCellText(text: entry.source.title)
            }
            .width(min: 70, ideal: 96, max: 180)
            TableColumn("Estado", value: \.tableStatusRank) { entry in
                MacCellStatus(chip: entry.tableStatus)
            }
            .width(min: 90, ideal: 108, max: 160)
            TableColumn("Importe", value: \.totalDebits) { entry in
                Text(entry.totalDebits.money).monospacedDigit()
            }
            .width(min: 76, ideal: 90, max: 140)
            .alignment(.trailing)
        } filter: {
            MacTableFilter(title: String(localized: "Filtrar por origen"), options: JournalFilter.allCases,
                           selection: $filter, label: \.title) { option in
                entries.filter(option.matches).count
            }
        } inspector: { entry in
            JournalEntryInspector(entry: entry, entries: entries, errorMessage: errorMessage)
        } actions: { entry in
            Button("Abrir asiento") { opened = entry }.buttonStyle(.primary)
            if entry.canReverse {
                Button("Revertir asiento…") { reversing = entry }.buttonStyle(.destructive)
            }
        }
        .onChange(of: selection) { errorMessage = nil }
        .confirmationDialog("¿Revertir este asiento?", isPresented: Binding(get: { reversing != nil }, set: { if !$0 { reversing = nil } }),
                            titleVisibility: .visible, presenting: reversing) { entry in
            Button("Revertir", role: .destructive) { reverse(entry) }
        } message: { _ in
            Text("Los asientos contabilizados no se editan ni se borran: se corrigen con un asiento de reversión.")
        }
        .sheet(isPresented: $creating) { NavigationStack { JournalEntryEditorView() }.editorSheetSizing() }
        .navigationDestination(item: $opened) { JournalEntryDetailView(entry: $0) }
        #if DEBUG
        // `-qa.abrir 1` abre el asiento completo de la fila elegida con `-qa.fila`; `-qa.nuevo 1`, la hoja «Nuevo asiento».
        .task {
            try? await Task.sleep(for: .seconds(1))
            if UserDefaults.standard.bool(forKey: "qa.nuevo") { creating = true }
            guard let id = selection, let entry = entries.first(where: { $0.id == id }) else { return }
            if UserDefaults.standard.bool(forKey: "qa.abrir") { opened = entry }
        }
        #endif
    }

    private func reverse(_ entry: JournalEntry) {
        do {
            let reversal = try Bookkeeper(context: context).reverse(entry)
            errorMessage = nil
            selection = reversal.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Filtro por origen: todos, los manuales, los que generan los documentos (facturas, cobros, gastos…) y los revertidos o
/// de reversión.
private enum JournalFilter: String, CaseIterable, Hashable {
    case all, manual, automatic, reversals

    var title: String {
        switch self {
        case .all: String(localized: "Todos")
        case .manual: String(localized: "Manuales")
        case .automatic: String(localized: "De documentos")
        case .reversals: String(localized: "Reversiones")
        }
    }

    func matches(_ entry: JournalEntry) -> Bool {
        switch self {
        case .all: true
        case .manual: entry.source == .manual
        case .automatic: entry.source != .manual && entry.source != .reversal
        case .reversals: entry.source == .reversal || entry.isReversed || entry.reversesEntryID != nil
        }
    }
}

/// Inspector del asiento (canvas `MacDiario`: «Asiento» con Número · Fecha · Estado y la tabla de líneas): concepto,
/// importe de 24 y estado; Asiento (Número, Fecha, Origen y la reversión si la hay) y Líneas.
private struct JournalEntryInspector: View {
    let entry: JournalEntry
    let entries: [JournalEntry]
    let errorMessage: String?

    var body: some View {
        if let errorMessage { ErrorBanner(message: errorMessage) }
        MacInspectorSummary(title: entry.tableMemo, amount: entry.totalDebits.money) { entry.tableStatus }
        MacInspectorSection(title: String(localized: "Asiento")) {
            MacInspectorRow(String(localized: "Número"), value: "#\(entry.number)")
            MacInspectorRow(String(localized: "Fecha"), value: entry.date.shortDate)
            MacInspectorRow(String(localized: "Origen"), value: entry.source.title)
            if let id = entry.reversedByEntryID, let reversal = entries.first(where: { $0.id == id }) {
                MacInspectorRow(String(localized: "Revertido por"), value: String(localized: "Asiento #\(reversal.number)"))
            }
            if let id = entry.reversesEntryID, let original = entries.first(where: { $0.id == id }) {
                MacInspectorRow(String(localized: "Revierte a"), value: String(localized: "Asiento #\(original.number)"))
            }
        }
        JournalLinesSection(entry: entry)
    }
}

/// Líneas del asiento en el inspector: Cuenta · Débito · Crédito, con la descripción de la línea debajo de la cuenta y
/// los totales en negrita (canvas `MacDiario`, tabla de líneas, en 300 pt).
private struct JournalLinesSection: View {
    let entry: JournalEntry
    @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 74

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Líneas").font(.label).foregroundStyle(Palette.ink2).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Text("Cuenta").frame(maxWidth: .infinity, alignment: .leading)
                Text("Débito").frame(width: amountWidth, alignment: .trailing)
                Text("Crédito").frame(width: amountWidth, alignment: .trailing)
            }
            .font(.label).foregroundStyle(Palette.ink2)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
            ForEach(entry.sortedLines) { line in
                Divider()
                let account = line.account?.displayName ?? String(localized: "Cuenta eliminada")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account).foregroundStyle(Palette.ink).lineLimit(2)
                        if !line.memo.isEmpty { Text(line.memo).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(2) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(line.debit > 0 ? line.debit.money : "").frame(width: amountWidth, alignment: .trailing)
                    Text(line.credit > 0 ? line.credit.money : "").frame(width: amountWidth, alignment: .trailing)
                }
                .monospacedDigit()
                .padding(.vertical, 5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(JournalEntryDetailView.spokenLine(account: account, memo: line.memo, debit: line.debit, credit: line.credit))
            }
            Divider()
            HStack(spacing: 8) {
                Text("Totales").frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.totalDebits.money).frame(width: amountWidth, alignment: .trailing)
                Text(entry.totalCredits.money).frame(width: amountWidth, alignment: .trailing)
            }
            .fontWeight(.semibold)
            .monospacedDigit()
            .padding(.vertical, 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Totales: debe \(entry.totalDebits.money), haber \(entry.totalCredits.money)")
        }
        .font(.body)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

extension JournalEntry {
    /// Claves de orden y valores de la tabla del Mac.
    nonisolated var tableMemo: String { memo.isEmpty ? String(localized: "Asiento \(number)") : memo }

    /// Orden de los estados al ordenar por «Estado»: Borrador, Contabilizado, Reversión, Revertido.
    nonisolated var tableStatusRank: Int {
        if status == .draft { return 0 }
        if isReversed { return 3 }
        return reversesEntryID != nil ? 2 : 1
    }

    /// Un asiento manual contabilizado que no se ha revertido ni es una reversión (lo mismo que `JournalEntryDetailView`).
    var canReverse: Bool { source == .manual && status == .posted && !isReversed && reversesEntryID == nil }

    /// Estado de la fila: punto + texto, como las facturas.
    var tableStatus: StatusChip {
        switch tableStatusRank {
        case 0: StatusChip(text: String(localized: "Borrador"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.orange)
        case 3: StatusChip(text: String(localized: "Revertido"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.gray)
        case 2: StatusChip(text: String(localized: "Reversión"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.gray)
        default: StatusChip(text: String(localized: "Contabilizado"), foreground: Palette.ink2, background: .clear, compact: true, dot: Palette.green)
        }
    }
}
#endif
