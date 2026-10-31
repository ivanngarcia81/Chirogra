import ChirograData
import SwiftData
import SwiftUI

/// Banca. La importación de extractos, la bandeja "por revisar" y la conciliación son de la fase 2
/// (DISEÑO §7.4); en el MVP se muestran los saldos según libros y un estado vacío que lo explica.
struct BankingView: View {
    @Query(sort: \Account.code) private var accounts: [Account]
    @Query private var journalLines: [JournalLine]

    var body: some View {
        let ledger = Ledger(accounts: accounts, lines: journalLines)
        List {
            Section("Saldos según libros") {
                ForEach(ledger.moneyAccounts) { account in
                    NavigationLink { LedgerView(account: account) } label: {
                        LedgerRow(title: account.name, subtitle: account.code) {
                            IconTile(systemImage: account.subtype == .creditCard ? "creditcard" : "building.columns")
                        } trailing: {
                            Text(ledger.balance(of: account).money).font(.body.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                EmptyStateView(systemImage: "tray.and.arrow.down",
                               title: "Importar y conciliar llega en la fase 2",
                               message: "Podrás traer tus movimientos en CSV u OFX, categorizarlos desde una bandeja y conciliar con el extracto del banco.")
            }
            .listRowBackground(Palette.surface)
        }
        .screenBackground()
        .navigationTitle("Banca")
    }
}
