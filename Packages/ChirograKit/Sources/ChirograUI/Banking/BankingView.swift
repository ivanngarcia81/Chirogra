import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Banca. La importación de extractos, la bandeja "por revisar" y la conciliación son de la fase 2
/// (DISEÑO §7.4); en el MVP se muestran los saldos según libros y un estado vacío que lo explica.
/// Banca (canvas `Banca`): las cuentas en un carrusel de tarjetas (la principal en color de marca) y, de momento,
/// el aviso de lo que llegará (importar movimientos, bandeja y conciliación son de la fase 2).
struct BankingView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @LayoutSizeClass private var sizeClass
    #endif

    /// `BancaCuentas` en iPad y Mac (hasta AX3); el carrusel del iPhone en pantallas estrechas.
    private var isWide: Bool {
        #if os(iOS)
        if sizeClass != .regular { return false }
        #endif
        return dynamicTypeSize < .accessibility4
    }

    var body: some View {
        if isWide { BankingWideView() } else { compactBody }
    }

    @ViewBuilder
    private var compactBody: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        let main = shown.first { $0.subtype == .bank }?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shown) { account in
                            NavigationLink { LedgerView(account: account) } label: {
                                accountCard(account, balance: ledger.cashBalance(of: account), featured: account.id == main)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .scrollClipDisabled()

                EmptyStateView(systemImage: "tray.and.arrow.down",
                               title: String(localized: "Próximamente: importar y conciliar"),
                               message: String(localized: "Podrás traer tus movimientos en CSV u OFX, categorizarlos desde una bandeja y conciliar con el extracto del banco."))
                    .card()
                    .padding(.horizontal, Metrics.gutter)
            }
            .padding(.vertical, Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Banca")
        .headerTitle()
    }

    private func accountCard(_ account: Account, balance: Int64, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(account.name) · \(account.code)").font(.footnote.weight(.semibold)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(featured ? Palette.onBrand.opacity(0.85) : Palette.ink3)
            Text(balance.money).font(.amount(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(featured ? Palette.onBrand : Palette.ink)
            Text(account.subtype.title).font(.caption.weight(.semibold))
                .foregroundStyle(featured ? Palette.onBrand.opacity(0.9) : Palette.ink3)
        }
        .padding(14)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 300 : featured ? 220 : 180, alignment: .leading)
        .background(featured ? Palette.brand : Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Banca en iPad y Mac (canvas `BancaCuentas`): tarjetas de cuenta que se eligen como en un grupo de radio y los
/// movimientos del mes de la cuenta elegida con retiro, depósito y saldo acumulado. «Importar y conciliar» es de la
/// fase 2 y se muestra desactivado.
struct BankingWideView: View {
    enum NewMovement: String, Identifiable {
        case expense, entry
        var id: String { rawValue }
    }

    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]
    @State private var selectedID: UUID?
    @State private var monthOffset = 0
    @State private var adding: NewMovement?
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 110

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        let selected = shown.first { $0.id == selectedID } ?? shown.first
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Como el `auto-fit` del canvas: las tarjetas ocupan todo el ancho, hasta cuatro por fila.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, min(shown.count, 4))), spacing: 12) {
                    ForEach(shown) { account in
                        accountCard(account, balance: ledger.cashBalance(of: account), selected: account.id == selected?.id)
                    }
                }
                if let selected { movements(of: selected) }
            }
            .padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Banca")
        .headerTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Label("Importar y conciliar · Próximamente", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
                    .accessibilityLabel("Importar y conciliar, disponible en una próxima versión")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Gasto", systemImage: "wallet.bifold") { adding = .expense }
                    Button("Asiento manual", systemImage: "list.bullet.rectangle") { adding = .entry }
                } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Movimiento") }
                }
                .accessibilityLabel("Nuevo movimiento")
                .headerButton()
            }
        }
        .sheet(item: $adding) { kind in
            NavigationStack {
                switch kind {
                case .expense: ExpenseEditorView()
                case .entry: JournalEntryEditorView()
                }
            }
        }
    }

    private func accountCard(_ account: Account, balance: Int64, selected: Bool) -> some View {
        Button { selectedID = account.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(account.name, systemImage: account.subtype == .creditCard ? "creditcard" : "building.columns")
                    .font(.footnote.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(selected ? Palette.onBrand.opacity(0.9) : Palette.ink2)
                Text(balance.money).font(.amount(24)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
                Text("Saldo en libros · \(account.code)").font(.caption)
                    .foregroundStyle(selected ? Palette.onBrand.opacity(0.85) : Palette.ink3)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(selected ? Palette.brand : Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Palette.brand : Palette.separator))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Movimientos del mes: el saldo sigue lo que ve el usuario (una tarjeta de crédito en negativo, lo que se debe).
    private func movements(of account: Account) -> some View {
        let month = DateInterval.month(containing: .now, offset: monthOffset)
        let end = month.end.addingTimeInterval(-1)
        let ledger = LedgerView.ledger(for: account, from: month.start, to: end)
        let sign: Int64 = account.subtype == .creditCard ? -1 : 1
        let lines = Dictionary((account.lines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { header(account); Spacer(minLength: 8); monthStepper(month) }
                VStack(alignment: .leading, spacing: 8) { header(account); monthStepper(month) }
            }
            TableCard {
                Text("Fecha").frame(width: 64, alignment: .leading)
                Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
                Text("Categoría o cuenta").frame(width: 190, alignment: .leading)
                Text("Retiro").frame(width: amountWidth, alignment: .trailing)
                Text("Depósito").frame(width: amountWidth, alignment: .trailing)
                Text("Saldo").frame(width: amountWidth, alignment: .trailing)
            } rows: {
                TableRow {
                    Text(month.start.dayMonth).frame(width: 64, alignment: .leading)
                    Text("Saldo inicial").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 190, height: 1)
                    Color.clear.frame(width: amountWidth, height: 1)
                    Color.clear.frame(width: amountWidth, height: 1)
                    Text((sign * ledger.openingBalance).money).frame(width: amountWidth, alignment: .trailing)
                }
                .fontWeight(.semibold)
                .background(Palette.background)
                ForEach(ledger.rows) { row in
                    TableRow {
                        Text(row.movement.date.dayMonth).foregroundStyle(Palette.ink2).frame(width: 64, alignment: .leading)
                        Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo).fontWeight(.semibold)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(counterpart(of: lines[row.movement.id])).foregroundStyle(Palette.ink2).lineLimit(1)
                            .frame(width: 190, alignment: .leading)
                        Text(row.movement.credit > 0 ? row.movement.credit.money : "").frame(width: amountWidth, alignment: .trailing)
                        Text(row.movement.debit > 0 ? row.movement.debit.money : "").foregroundStyle(Palette.positive)
                            .frame(width: amountWidth, alignment: .trailing)
                        Text((sign * row.balance).money).fontWeight(.semibold).frame(width: amountWidth, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(LedgerView.spokenMovement(row))
                }
                if ledger.rows.isEmpty {
                    Text("Sin movimientos este mes").font(.subheadline).foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
        }
    }

    private func header(_ account: Account) -> some View {
        HStack(spacing: 10) {
            Text("Movimientos · \(account.name)").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            NavigationLink("Libro mayor") { LedgerView(account: account) }.font(.subheadline.weight(.semibold))
        }
    }

    private func monthStepper(_ month: DateInterval) -> some View {
        HStack(spacing: 4) {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Mes anterior")
            Text(month.start.formatted(.appDateTime.month(.wide).year()).sentenceCased)
                .font(.subheadline).foregroundStyle(Palette.ink2).monospacedDigit()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(monthOffset >= 0)
                .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
    }

    /// La otra cuenta del asiento («Varias» si hay más de una).
    private func counterpart(of line: JournalLine?) -> String {
        guard let line, let entry = line.entry else { return "—" }
        let others = Set((entry.lines ?? []).compactMap(\.account).filter { $0.id != line.account?.id }.map(\.name))
        return others.count == 1 ? others.first! : others.isEmpty ? "—" : String(localized: "Varias")
    }
}
