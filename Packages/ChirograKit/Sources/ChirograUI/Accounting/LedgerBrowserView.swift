import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Libro mayor en iPad y Mac (canvas `MacLibroMayor`): la cuenta y el periodo en la barra, el resumen del periodo
/// (saldo inicial, débitos, créditos y saldo final) y la tabla Fecha · Tipo · Detalle · Débito · Crédito · Saldo.
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

    @CompanyQuery(sort: \Account.code) private var accounts: [Account]
    @State private var selectedID: UUID?
    @State private var period: Period = .thisMonth
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .subheadline) private var kindWidth: CGFloat = 120
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 100

    private var active: [Account] { accounts.filter { !$0.isArchived } }

    /// La cuenta elegida o, de entrada, la primera de banco (como en el canvas).
    private var selected: Account? {
        active.first { $0.id == selectedID } ?? active.first { $0.subtype == .bank } ?? active.first
    }

    /// Último instante del periodo (hoy si es «Todo»).
    private var end: Date { period.interval.map { $0.end.addingTimeInterval(-1) } ?? .now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selected {
                    let ledger = LedgerView.ledger(for: selected, from: period.interval?.start, to: period.interval.map { _ in end })
                    LedgerSummary(opening: ledger.openingBalance, debits: ledger.totalDebit, credits: ledger.totalCredit,
                                  closing: ledger.closingBalance,
                                  debitCount: ledger.rows.filter { $0.movement.debit > 0 }.count,
                                  creditCount: ledger.rows.filter { $0.movement.credit > 0 }.count,
                                  from: period.interval?.start, to: end)
                    LedgerTable(ledger: ledger, kinds: LedgerView.kinds(for: selected), from: period.interval?.start, to: end,
                                dateWidth: dateWidth, kindWidth: kindWidth, amountWidth: amountWidth)
                        .id(selected.id)
                } else {
                    EmptyStateView(systemImage: "book.closed", title: String(localized: "Sin cuentas"),
                                   message: String(localized: "El plan de cuentas está vacío."))
                }
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Libro mayor")
        .navigationSubtitle(String(localized: "Movimientos por cuenta con saldo acumulado"))
        .headerTitle()
        .toolbar {
            // Menús con su texto: un `Picker` en la barra del iPad se veía como una cápsula vacía a todo el ancho.
            ToolbarItem(placement: .primaryAction) { accountMenu }
            ToolbarItem(placement: .primaryAction) { periodMenu }
            if let selected {
                ToolbarItem(placement: .primaryAction) {
                    let file = csvFile(for: selected)
                    ShareLink(item: file, preview: SharePreview("\(file.name).csv")) {
                        Label("Exportar CSV", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                    }
                    .headerButton()
                }
            }
        }
    }

    /// Cuenta (canvas: «1010 · Banco · Corriente ▾»), por tipo.
    private var accountMenu: some View {
        Menu {
            Picker("Cuenta", selection: Binding(get: { selected?.id }, set: { selectedID = $0 })) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Section(type.title) {
                        ForEach(active.filter { $0.type == type }) { Text(verbatim: "\($0.code) · \($0.name)").tag(Optional($0.id)) }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent").accessibilityHidden(true)
                Text(verbatim: selected.map { "\($0.code) · \($0.name)" } ?? "—").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Cuenta")
        .accessibilityValue(selected?.displayName ?? "")
        .headerButton()
    }

    private var periodMenu: some View {
        Menu {
            Picker("Periodo", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar").accessibilityHidden(true)
                Text(period.title)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Periodo")
        .accessibilityValue(period.title)
        .headerButton()
    }

    private func csvFile(for account: Account) -> CSVFile {
        let range = period.interval
        let ledger = LedgerView.ledger(for: account, from: range?.start, to: range?.end.addingTimeInterval(-1))
        return CSVFile(name: String(localized: "Libro mayor · \(account.name)"),
                       text: CSVExport.accountLedger(ledger, kinds: LedgerView.kinds(for: account)))
    }
}
