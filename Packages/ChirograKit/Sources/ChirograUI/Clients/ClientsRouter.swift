import ChirograData
import SwiftData
import SwiftUI

// MARK: - Panel de clientes: navegación (docs/PANEL-CLIENTES.md, canvas «Chirogra — Panel de clientes»)
//
// - iPad y Mac: «Clientes» es la primera entrada de la barra lateral (`AppSection.clients`) y la que se abre al arrancar.
// - iPhone: el panel tapa las pestañas al abrir la app; al elegir un cliente se ven sus pestañas, e Inicio lleva arriba
//   «‹ Clientes» para volver (canvas `iPhoneEntrada`).
// - Tocar un pendiente cambia a esa empresa y abre la pantalla del pendiente (`ClientRoute`): la app se rehace con la
//   empresa nueva y cada pantalla recoge la ruta que le toca al aparecer (`onClientRoute`).

/// Adónde lleva el panel al abrir un cliente o uno de sus pendientes.
enum ClientRoute: Equatable {
    case home
    case bankInbox
    case overdueInvoices
    case salesTax
    /// Conciliación de esa cuenta (o la lista de cuentas).
    case reconcile(UUID?)
    case notices
    case accountantPackage
    case periodClose

    /// Pantalla de la barra lateral (iPad y Mac) en que se recoge la ruta.
    var sidebarItem: SidebarItem {
        switch self {
        case .home, .notices: .section(.home)
        case .bankInbox: .banking(.inbox)
        case .overdueInvoices: .sales(.invoices)
        case .salesTax, .accountantPackage: .section(.taxes)
        case .reconcile: .banking(.reconcile)
        case .periodClose: .accounting(.close)
        }
    }

    /// Pestaña del iPhone en que se recoge la ruta («Más» para Impuestos y Cierre).
    var phoneTab: AppSection {
        switch self {
        case .home, .notices: .home
        case .bankInbox, .reconcile: .banking
        case .overdueInvoices: .sales
        case .salesTax, .accountantPackage, .periodClose: .settings
        }
    }
}

@MainActor
@Observable
final class ClientsRouter {
    static let shared = ClientsRouter()

    /// iPhone: el panel a la vista en lugar de las pestañas. Empieza a la vista: el contador abre la app en Clientes.
    var showsPanel = true
    /// iPad y Mac: cada vez que cambia, la barra lateral abre «Clientes» («Todos los clientes» del selector).
    private(set) var panelRequests = 0
    /// Ruta por recoger tras abrir un cliente.
    private(set) var pending: ClientRoute?
    /// En iPad y Mac, «Clientes» se abre una sola vez al arrancar.
    var openedAtLaunch = false
    /// Arranque de la app: el panel solo se abre solo en sus primeros segundos.
    let launchedAt = Date()
    /// Clientes que necesitan atención (el número de «Clientes» en la barra lateral). Lo pone el panel al cargar.
    var attentionCount: Int?

    /// «Todos los clientes» del selector de empresa y «‹ Clientes» de Inicio.
    func showPanel() {
        showsPanel = true
        panelRequests += 1
    }

    /// Abre un cliente: lo deja como empresa activa y lleva a la pantalla de `route`.
    func open(_ companyID: UUID, route: ClientRoute = .home) {
        pending = route
        showsPanel = false
        CompanyHub.shared.select(companyID)
        // Si ninguna pantalla la recoge (p. ej. se canceló el cambio de empresa), no se queda para la próxima vez.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if pending == route { pending = nil }
        }
    }

    /// La pantalla que recoge `route` la quita de pendientes. Devuelve la ruta si coincide con `matches`.
    func take(where matches: (ClientRoute) -> Bool) -> ClientRoute? {
        guard let route = pending, matches(route) else { return nil }
        pending = nil
        return route
    }

    /// El panel existe con el plan para contadores o, sin él (p. ej. con la suscripción vencida), si se llevan varias
    /// empresas.
    static func isAvailable(companies: [Company]) -> Bool {
        SubscriptionStore.shared.plan == .accountant || companies.filter { !$0.isArchived }.count > 1
    }
}

extension View {
    /// Recoge la ruta del panel que le toca a esta pantalla al aparecer y si llega con la pantalla ya abierta.
    func onClientRoute(_ matches: @escaping (ClientRoute) -> Bool, perform action: @escaping (ClientRoute) -> Void) -> some View {
        modifier(ClientRouteReceiver(matches: matches, action: action))
    }
}

private struct ClientRouteReceiver: ViewModifier {
    let matches: (ClientRoute) -> Bool
    let action: (ClientRoute) -> Void
    @State private var router = ClientsRouter.shared

    func body(content: Content) -> some View {
        content
            .task(id: router.pending) {
                // Un instante, para que la pantalla ya esté puesta (las que empujan otra encima la pierden si no).
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let route = router.take(where: matches) else { return }
                action(route)
            }
    }
}
