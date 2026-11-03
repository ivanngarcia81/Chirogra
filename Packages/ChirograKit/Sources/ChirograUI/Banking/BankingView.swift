import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

/// Banca del MVP (canvas `BancaCuentas`, `Banca` solo con las cuentas): las cuentas de dinero como filas con su icono
/// de color y el saldo en libros; cada una abre su libro mayor. Importar movimientos, la bandeja «por revisar» y la
/// conciliación son de la fase 2 (DISEÑO §7.4): se anuncian como «Próximamente».
struct BankingView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        let shown = ledger.moneyAccounts.filter { $0.subtype == .bank || $0.subtype == .creditCard || ledger.balance(of: $0) != 0 }
        List {
            Section {
                if shown.isEmpty {
                    EmptyStateView(systemImage: "building.columns", title: String(localized: "Sin cuentas de banco"),
                                   message: String(localized: "Añade tus cuentas de banco y tarjetas en el plan de cuentas."))
                }
                ForEach(shown) { account in
                    NavigationLink { LedgerView(account: account) } label: {
                        // Hasta dos líneas: en el iPhone «Cuenta corriente ••4821» se cortaba en «••4…» (3-nov).
                        LedgerRow(title: account.maskedName, subtitle: String(localized: "Saldo en libros · \(account.code)"), titleLines: 2) {
                            IconTile(systemImage: account.bankSymbol, foreground: account.bankColor)
                        } trailing: {
                            Text(ledger.cashBalance(of: account).money).monospacedDigit().foregroundStyle(Palette.ink)
                        }
                    }
                }
            } header: {
                SectionLabel(text: String(localized: "Cuentas"))
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "square.and.arrow.down", foreground: Palette.gray)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Importar y conciliar").foregroundStyle(Palette.ink)
                        Text("Próximamente").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importar y conciliar, disponible en una próxima versión")
            } footer: {
                Text("Podrás traer tus movimientos en CSV u OFX, categorizarlos desde una bandeja y conciliar con el extracto del banco.")
            }
        }
        .groupedList()
        .screenBackground()
        .navigationTitle("Banca")
        .navigationSubtitle(String(localized: "\(shown.count) cuentas · \(Date.now.monthYear)"))
        .headerTitle()
    }
}

extension Account {
    /// Icono de una cuenta de dinero (canvas: banco en azul, ahorro en verde, tarjeta en índigo, efectivo en verde).
    var bankSymbol: String {
        switch subtype {
        case .creditCard: "creditcard"
        case .cash: "banknote"
        default: "building.columns"
        }
    }

    var bankColor: Color {
        switch subtype {
        case .creditCard: Palette.creditCard
        case .cash: Palette.green
        default:
            ["ahorro", "saving"].contains { name.lowercased().contains($0) } ? Palette.green : Palette.bankAccount
        }
    }
}

/// Movimientos del mes de una cuenta de dinero (canvas `BancaCuentas`, Mac, y `iPadBancaCuentas`): la cuenta con su
/// saldo en grande y la tabla del mes (saldo inicial, retiro, depósito y saldo acumulado), con el mes anterior y el
/// siguiente. Es el detalle de la cuenta elegida en Banca cuando la columna es ancha.
struct AccountMovementsView: View {
    let account: Account
    @State private var monthOffset = 0
    @Query private var journalLines: [JournalLine]
    @Query(sort: \Account.code) private var accounts: [Account]
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 58

    /// Movimientos del mes: el saldo sigue lo que ve el usuario (una tarjeta de crédito en negativo, lo que se debe).
    var body: some View {
        let month = DateInterval.month(containing: .now, offset: monthOffset)
        let end = month.end.addingTimeInterval(-1)
        let ledger = LedgerView.ledger(for: account, from: month.start, to: end)
        let sign: Int64 = account.subtype == .creditCard ? -1 : 1
        let lines = Dictionary((account.lines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let balance = Ledger(accounts: accounts, lines: journalLines).cashBalance(of: account)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.maskedName).font(.subheadline).foregroundStyle(Palette.ink2)
                Text(balance.money).font(.amount(40)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text("Saldo en libros · \(account.code)").font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack { header; Spacer(minLength: 8); monthStepper(month) }
                    VStack(alignment: .leading, spacing: 4) { header; monthStepper(month) }
                }
                TableCard {
                    Text("Fecha").frame(width: dateWidth, alignment: .leading)
                    Text("Descripción").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    Text("Categoría o cuenta").frame(minWidth: 90, maxWidth: 190, alignment: .leading)
                    Text("Retiro").frame(width: amountWidth, alignment: .trailing)
                    Text("Depósito").frame(width: amountWidth, alignment: .trailing)
                    Text("Saldo").frame(width: amountWidth, alignment: .trailing)
                } rows: {
                    TableRow {
                        Text(month.start.dayMonth).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
                        Text("Saldo inicial").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(minWidth: 90, maxWidth: 190, maxHeight: 1)
                        Color.clear.frame(width: amountWidth, height: 1)
                        Color.clear.frame(width: amountWidth, height: 1)
                        Text((sign * ledger.openingBalance).money).frame(width: amountWidth, alignment: .trailing)
                    }
                    .fontWeight(.semibold)
                    ForEach(Array(ledger.rows.enumerated()), id: \.element.id) { index, row in
                        TableRow {
                            Text(row.movement.date.dayMonth).foregroundStyle(Palette.ink2).frame(width: dateWidth, alignment: .leading)
                            Text(row.movement.memo.isEmpty ? String(localized: "Asiento") : row.movement.memo)
                                .lineLimit(1).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                            Text(counterpart(of: lines[row.movement.id])).foregroundStyle(Palette.ink2).lineLimit(1)
                                .frame(minWidth: 90, maxWidth: 190, alignment: .leading)
                            Text(row.movement.credit > 0 ? row.movement.credit.money : "").frame(width: amountWidth, alignment: .trailing)
                            Text(row.movement.debit > 0 ? row.movement.debit.money : "").foregroundStyle(Palette.positive)
                                .frame(width: amountWidth, alignment: .trailing)
                            Text((sign * row.balance).money).frame(width: amountWidth, alignment: .trailing)
                        }
                        .zebra(index + 1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(LedgerView.spokenMovement(row))
                    }
                    if ledger.rows.isEmpty {
                        Text("Sin movimientos este mes").font(.subheadline).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }
                Text("\(String(localized: "\(ledger.rows.count) movimientos")) · \(String(localized: "Saldo al \(end.dayMonth) \((sign * ledger.closingBalance).money)"))")
                    .font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Movimientos").font(.cardTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            NavigationLink("Libro mayor") { LedgerView(account: account) }.font(.subheadline).tint(Palette.brand)
        }
    }

    private func monthStepper(_ month: DateInterval) -> some View {
        HStack(spacing: 4) {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: Metrics.target, height: Metrics.target) }
                .accessibilityLabel("Mes anterior")
            Text(month.start.monthYear)
                .font(.subheadline).foregroundStyle(Palette.ink2).monospacedDigit()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: Metrics.target, height: Metrics.target) }
                .disabled(monthOffset >= 0)
                .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
    }

    /// La otra cuenta del asiento («Varias» si hay más de una).
    private func counterpart(of line: JournalLine?) -> String {
        guard let line, let entry = line.entry else { return "—" }
        let others = Set((entry.lines ?? []).compactMap(\.account).filter { $0.id != line.account?.id }.map(\.maskedName))
        return others.count == 1 ? others.first! : others.isEmpty ? "—" : String(localized: "Varias")
    }
}
