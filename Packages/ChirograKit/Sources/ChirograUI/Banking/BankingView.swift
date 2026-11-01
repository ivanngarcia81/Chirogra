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

    var body: some View {
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
