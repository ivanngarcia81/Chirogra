import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Libro mayor en iPad y Mac (canvas `MacLibroMayor`): cuentas a la izquierda y, a la derecha, la tabla
/// FECHA · TIPO · DETALLE · DÉBITO · CRÉDITO · SALDO entre el saldo inicial y el final del periodo.
struct LedgerBrowserView: View {
    enum Period: String, CaseIterable, Identifiable {
        case thisMonth, lastMonth, thisYear, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisMonth: String(localized: "Este mes")
            case .lastMonth: String(localized: "Mes anterior")
            case .thisYear: String(localized: "Este año")
            case .all: String(localized: "Todo")
            }
        }

        var interval: DateInterval? {
            let calendar = Calendar.current
            return switch self {
            case .thisMonth: .month(containing: .now)
            case .lastMonth: .month(containing: .now, offset: -1)
            case .thisYear: calendar.dateInterval(of: .year, for: .now)
            case .all: nil
            }
        }
    }

    /// Una fila de la tabla: saldo inicial, movimiento o saldo final.
    struct Row: Identifiable {
        let id: String
        let date: String
        var kind: String?
        let detail: String
        var debit = ""
        var credit = ""
        let balance: String
        var isSummary = false
    }

    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var selectedID: UUID?
    @State private var period: Period = .thisMonth
    @ScaledMetric(relativeTo: .body) private var listWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .subheadline) private var kindWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 92

    private var active: [Account] { accounts.filter { !$0.isArchived } }

    /// La cuenta elegida o, de entrada, la primera de banco (como en el canvas).
    private var selected: Account? {
        active.first { $0.id == selectedID } ?? active.first { $0.subtype == .bank } ?? active.first
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(active) { account in accountButton(account, balance: ledger.balance(of: account)) }
                }
                .padding(8)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: listWidth)

            if let selected {
                movementsTable(selected).id(selected.id)
            }
        }
        .padding(20)
        .background(Palette.background)
        .navigationTitle("Libro mayor")
        .toolbar {
            // Menú con su texto: un `Picker` en la barra del iPad se veía como una cápsula vacía a todo el ancho.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Periodo", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(period.title)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                }
                .accessibilityLabel("Periodo")
                .accessibilityValue(period.title)
            }
            if let selected {
                ToolbarItem(placement: .primaryAction) {
                    let file = csvFile(for: selected)
                    ShareLink(item: file, preview: SharePreview("\(file.name).csv")) {
                        Text("Exportar CSV")
                    }
                }
            }
        }
    }

    private func accountButton(_ account: Account, balance: Int64) -> some View {
        let isSelected = account.id == selected?.id
        return Button { selectedID = account.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(account.code) · \(account.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(isSelected ? Palette.brand : Palette.ink)
                Text("\(account.type.title) · saldo \(balance.money)").font(.caption).lineLimit(1)
                    .foregroundStyle(isSelected ? Palette.brand : Palette.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Palette.brandWash : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Tabla propia en vez de `Table`: en iPad `Table` reparte el ancho a partes iguales y recortaba el detalle,
    /// y así las filas de saldo inicial y final llevan su fondo, como en el canvas.
    private func movementsTable(_ account: Account) -> some View {
        let rows = rows(for: account)
        return ScrollView {
            LazyVStack(spacing: 0) {
                tableRow(date: String(localized: "Fecha"), kind: nil, detail: String(localized: "Tipo"),
                         title: String(localized: "Detalle"), debit: String(localized: "Débito"),
                         credit: String(localized: "Crédito"), balance: String(localized: "Saldo"), isHeader: true)
                ForEach(rows) { row in
                    Divider()
                    tableRow(date: row.date, kind: row.kind, detail: nil, title: row.detail, debit: row.debit,
                             credit: row.credit, balance: row.balance, isHeader: false, isSummary: row.isSummary)
                        .background(row.id == "closing" ? Palette.brandWash : row.isSummary ? Palette.background : .clear)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Fila FECHA · TIPO · DETALLE · DÉBITO · CRÉDITO · SALDO (la cabecera usa `detail` como título de TIPO).
    private func tableRow(date: String, kind: String?, detail: String?, title: String, debit: String, credit: String,
                          balance: String, isHeader: Bool, isSummary: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(date).frame(width: dateWidth, alignment: .leading)
            Group {
                if isHeader {
                    Text(detail ?? "")
                } else if let kind {
                    StatusChip(text: kind, foreground: Palette.ink2, background: Palette.surface2)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: kindWidth, alignment: .leading)
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(debit).frame(width: amountWidth, alignment: .trailing)
            Text(credit).frame(width: amountWidth, alignment: .trailing)
            Text(balance).fontWeight(isHeader ? nil : .semibold).frame(width: amountWidth, alignment: .trailing)
        }
        .font(isHeader ? .label : .subheadline)
        .tracking(isHeader ? 0.6 : 0)
        .textCase(isHeader ? .uppercase : nil)
        .fontWeight(isSummary ? .semibold : nil)
        .monospacedDigit()
        .foregroundStyle(isHeader ? Palette.ink3 : Palette.ink)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .accessibilityHidden(isHeader)
    }

    private func csvFile(for account: Account) -> CSVFile {
        let range = period.interval
        let ledger = LedgerView.ledger(for: account, from: range?.start, to: range?.end.addingTimeInterval(-1))
        return CSVFile(name: String(localized: "Libro mayor · \(account.name)"),
                       text: CSVExport.accountLedger(ledger, kinds: kinds(for: account)))
    }

    /// Tipo de cada movimiento (cobro, gasto…) según el documento que generó el asiento.
    private func kinds(for account: Account) -> [UUID: String] {
        Dictionary((account.lines ?? []).compactMap { line in line.entry.map { (line.id, $0.source.title) } },
                   uniquingKeysWith: { first, _ in first })
    }

    private func rows(for account: Account) -> [Row] {
        let range = period.interval
        let sources = kinds(for: account)
        let ledger = LedgerView.ledger(for: account, from: range?.start, to: range?.end.addingTimeInterval(-1))
        let day = Date.FormatStyle.dateTime.day().month(.abbreviated)
        var rows: [Row] = []
        if let range {
            rows.append(Row(id: "opening", date: range.start.formatted(day), detail: String(localized: "Saldo inicial"),
                            balance: ledger.openingBalance.money, isSummary: true))
        }
        rows += ledger.rows.map { row in
            Row(id: row.id.uuidString, date: row.movement.date.formatted(day), kind: sources[row.movement.id],
                detail: row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo,
                debit: row.movement.debit > 0 ? row.movement.debit.money : "",
                credit: row.movement.credit > 0 ? row.movement.credit.money : "",
                balance: row.balance.money)
        }
        rows.append(Row(id: "closing", date: (range?.end.addingTimeInterval(-1) ?? .now).formatted(day),
                        detail: String(localized: "Saldo final"),
                        debit: ledger.totalDebit.money, credit: ledger.totalCredit.money,
                        balance: ledger.closingBalance.money, isSummary: true))
        return rows
    }
}
