import ChirograCore
import ChirograData
import SwiftUI

// MARK: - Mover dinero (build 40, QA Hudson H03)
//
// Traspasos, el pago de la tarjeta y lo que el dueño saca o pone solo se registraban desde Más › Contabilidad ›
// Asientos de diario › Nuevo asiento, una sección «para tu contador». Ahora se abren también desde el «+» de Inicio y
// desde la ficha de cada cuenta en Banca, con las mismas plantillas (`JournalTemplate`) y las cuentas ya elegidas.

/// Un atajo de «Mover dinero»: la plantilla y las cuentas propuestas.
struct MoveMoneyShortcut: Identifiable {
    enum Kind { case transfer, payCard, ownerDraw, ownerContribution }

    let id = UUID()
    let kind: Kind
    /// Cuenta de dinero de la plantilla (de dónde sale; en la aportación, a dónde entra). `nil`: la primera, el banco.
    var from: UUID?
    /// Destino del traspaso. `nil`: en el pago de la tarjeta, la primera tarjeta; si no, la primera cuenta distinta.
    var to: UUID?

    var template: JournalTemplate {
        switch kind {
        case .transfer, .payCard: .transfer
        case .ownerDraw: .ownerDraw
        case .ownerContribution: .ownerContribution
        }
    }

    var memo: String { kind == .payCard ? Self.cardPaymentMemo : template.defaultMemo }

    /// Concepto del pago de la tarjeta (se puede cambiar).
    static var cardPaymentMemo: String { String(localized: "Pago de la tarjeta") }
}

/// Las opciones de «Mover dinero» para un menú. Con `account` (la ficha de una cuenta en Banca), las de esa cuenta:
/// de un banco o la caja, pasar a otra cuenta, pagar la tarjeta, sacar o poner dinero; de una tarjeta, pagarla.
struct MoveMoneyMenuItems: View {
    var account: Account?
    let open: (MoveMoneyShortcut) -> Void
    @CompanyQuery(sort: \Account.code) private var accounts: [Account]

    private var moneyAccounts: [Account] { JournalTemplate.moneyAccounts(in: accounts) }
    private var hasCard: Bool { moneyAccounts.contains { $0.subtype == .creditCard && $0.id != account?.id } }

    var body: some View {
        if let account, account.subtype == .creditCard {
            if moneyAccounts.contains(where: { $0.subtype != .creditCard }) {
                item("Pagar esta tarjeta", "creditcard", .init(kind: .payCard, to: account.id))
            }
        } else {
            if moneyAccounts.count > 1 {
                item(account == nil ? "Mover dinero entre cuentas" : "Pasar a otra cuenta", "arrow.left.arrow.right",
                     .init(kind: .transfer, from: account?.id))
            }
            if hasCard {
                item("Pagar la tarjeta", "creditcard", .init(kind: .payCard, from: account?.id))
            }
            item("Saqué dinero para mí", "arrow.up.circle", .init(kind: .ownerDraw, from: account?.id))
            item("Puse dinero de mi bolsillo", "arrow.down.circle", .init(kind: .ownerContribution, from: account?.id))
        }
    }

    private func item(_ title: LocalizedStringKey, _ image: String, _ shortcut: MoveMoneyShortcut) -> some View {
        Button { SubscriptionStore.shared.whenWritable { open(shortcut) } } label: { Label(title, systemImage: image) }
    }
}

/// «Mover dinero» en la barra de la ficha de una cuenta de dinero (Banca), con su hoja.
struct MoveMoneyButton: View {
    let account: Account
    @State private var shortcut: MoveMoneyShortcut?

    var body: some View {
        Menu {
            MoveMoneyMenuItems(account: account) { shortcut = $0 }
        } label: {
            Label("Mover dinero", systemImage: "arrow.left.arrow.right")
        }
        .help("Mover dinero")
        .sheet(item: $shortcut) { picked in NavigationStack { JournalEntryEditorView(shortcut: picked) }.editorSheetSizing() }
    }
}
